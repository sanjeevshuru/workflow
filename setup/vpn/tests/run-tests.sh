#!/bin/bash
# Tests for the FortiClient-driven vpn command (setup/vpn/vpn) and the VPN Connect applet source.
# The applet is simulated through a fake `open`; no Accessibility permission, VPN or sign-in needed.
#
#   setup/vpn/tests/run-tests.sh

set -u
VPN_DIR=$(cd "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/vpn-fc-tests.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

PASS=0; FAIL=0; FAILED=""; OUT=""
ok()  { PASS=$((PASS + 1)); printf '  ok    %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); FAILED="$FAILED\n  - $1"; printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; }
check() {
  local name="$1"; shift
  if "$@"; then ok "$name"; else bad "$name" "${OUT:+last vpn output: $(printf '%s' "$OUT" | tail -n 6 | tr '\n' '|')}"; fi
}
section() { printf '\n%s\n' "$1"; }

F="$WORK/fakebin"; S="$WORK/sim"; APPDIR="$WORK/VPN Connect.app"
mkdir -p "$F" "$S" "$APPDIR"

# Fake `open`: `open -g <applet>` runs the simulated applet in the background, like LaunchServices.
cat >"$F/open" <<'EOF'
#!/bin/bash
echo "$*" >>"$SIM/open-calls"
[ "$1" = -g ] && [ "$2" = "$FORTIVPN_APPLET" ] || { echo "UNEXPECTED open $*" >>"$SIM/violations"; exit 1; }
nohup "$FAKE_BIN/applet" >/dev/null 2>&1 &
EOF

cat >"$F/applet" <<'EOF'
#!/bin/bash
st="$FORTIVPN_STATE"; sc=$(cat "$SIM/scenario" 2>/dev/null || echo ok)
req=$(cat "$st/request" 2>/dev/null); rm -f "$st/request"
echo "$req" >>"$SIM/requests"
answer() { printf '%s\n' "$1" >"$st/result.tmp" && mv "$st/result.tmp" "$st/result"; }
sleep 0.5
case "$sc:$req" in
  silent:*) exit 0 ;;
  notallowed:*) answer "error: not allowed (-25211): allow 'VPN Connect' in System Settings > Privacy & Security > Accessibility" ;;
  nobutton:connect) answer "error: 1002 no SAML Login / Connect button found (run: vpn dump)" ;;
  already:connect) touch "$SIM/reachable"; answer "ok: already connected" ;;
  already-nodns:connect) answer "ok: already connected" ;;
  ok:connect) answer "ok: clicked SAML Login"; sleep 1.5; touch "$SIM/reachable" ;;
  nosignin:connect) answer "ok: clicked SAML Login" ;;
  *:disconnect)
    if [ -e "$SIM/reachable" ]; then answer "ok: clicked Disconnect"; sleep 1; rm -f "$SIM/reachable"
    else answer "ok: already disconnected"; fi ;;
  *:status) if [ -e "$SIM/reachable" ]; then answer "ok: connected"; else answer "ok: disconnected"; fi ;;
  *:check) answer "ok: allowed; window 'FortiClient -- Zero Trust Fabric Agent'" ;;
  *:dump) answer "$(printf 'ok: dump of FortiClient\nAXButton  SAML Login\nAXStaticText  VPN SAML DM')" ;;
  *) answer "error: unknown request $req" ;;
esac
EOF

cat >"$F/nc" <<'EOF'
#!/bin/bash
[ -e "$SIM/reachable" ]
EOF
chmod +x "$F"/*

export SIM="$S" FAKE_BIN="$F"
export FORTIVPN_APPLET="$APPDIR" FORTIVPN_STATE="$WORK/state"
export FORTIVPN_PATH="$F:/usr/bin:/bin:/usr/sbin:/sbin"
export FORTIVPN_TIMEOUT=5 FORTIVPN_APPLET_WAIT=3 FORTIVPN_DOWN_WAIT=5
VPN="$VPN_DIR/vpn"

reset() {
  sleep 0.3; pkill -f "$F/applet" 2>/dev/null
  while pgrep -f "$F/applet" >/dev/null; do sleep 0.1; done
  rm -rf "${S:?}"/* "$FORTIVPN_STATE"
  echo "${1:-ok}" >"$S/scenario"
}
count() { if [ -e "$S/$1" ]; then wc -l <"$S/$1" | tr -d ' '; else echo 0; fi; }
run() { OUT=$("$VPN" "$@" 2>&1); RC=$?; }
has() { grep -q -- "$1" <<<"$OUT"; }

# ------------------------------------------------------------------ lint
section "Lint"
if command -v shellcheck >/dev/null; then
  for f in vpn install-applet.sh tests/run-tests.sh; do
    if msg=$(shellcheck -x "$VPN_DIR/$f" 2>&1); then ok "shellcheck $f"; else bad "shellcheck $f" "$(echo "$msg" | head -5)"; fi
  done
else
  bad "shellcheck installed" "brew install shellcheck"
fi
check "vpn parses with macOS /bin/bash 3.2" /bin/bash -n "$VPN"
check "applet source compiles (osacompile)" osacompile -o "$WORK/check.scpt" "$VPN_DIR/forticlient/VPNConnect.applescript"
SRC="$VPN_DIR/forticlient/VPNConnect.applescript"
check "applet only drives the FortiClient process" test -z "$(grep -o 'process "[^"]*"' "$SRC" | grep -v 'process "FortiClient"')"
check "applet accepts only the fixed request words" test "$(grep -o 'req is "[a-z]*"' "$SRC" | sort -u | tr '\n' ' ')" = 'req is "check" req is "connect" req is "disconnect" req is "dump" req is "status" '
check "applet runs no shell command built from the request" test -z "$(grep 'do shell script' "$SRC" | grep -E '& req|req &')"

# ------------------------------------------------------------------ vpn command
section "vpn command (simulated applet)"
reset; run bogus
check "unknown command → usage, exit 64" test "$RC" = 64
reset; run check
check "check when unreachable → exit 1, no applet launched" test "$RC" = 1 -a "$(count open-calls)" = 0

reset ok; start=$(date +%s); run up; took=$(( $(date +%s) - start ))
check "up → exit 0, connected" test "$RC" = 0 -a -n "$(has 'connected: jcvs' && echo y)"
check "  … asked the applet to connect, once" test "$(cat "$S/requests" 2>/dev/null)" = connect
check "  … reports what was clicked" has 'FortiClient: ok: clicked SAML Login'
check "  … says to finish the sign-in in the browser" has 'Microsoft sign-in'
check "  … promptly (${took}s)" test "$took" -le 4
check "  … cleaned up request and lock" test ! -e "$FORTIVPN_STATE/request" -a ! -e "$FORTIVPN_STATE/lock"

run up
check "up when already reachable → exit 0, applet not launched again" test "$RC" = 0 -a "$(count open-calls)" = 1
run check
check "check when connected → exit 0" test "$RC" = 0
run status
check "status → FortiClient connected + reachable, exit 0" test "$RC" = 0 -a -n "$(has 'FortiClient: ok: connected' && echo y)"

run down
check "down → exit 0, disconnected" test "$RC" = 0 -a -n "$(has '^vpn: disconnected' && echo y)"
check "  … clicked Disconnect" has 'clicked Disconnect'
run down
check "down again → 'already disconnected', exit 0" test "$RC" = 0 -a -n "$(has 'already disconnected' && echo y)"
run status
check "status when down → exit 1" test "$RC" = 1 -a -n "$(has 'unreachable' && echo y)"

reset already; run up
check "FortiClient already connected (UI) → exit 0 once reachable" test "$RC" = 0
reset already-nodns; start=$(date +%s); run up; took=$(( $(date +%s) - start ))
check "FortiClient connected but host unreachable → exit 2 with hint" test "$RC" = 2 -a -n "$(has 'DNS or routes' && echo y)"

reset notallowed; run up
check "applet not allowed under Accessibility → exit 3 with setup hint" test "$RC" = 3 -a -n "$(has 'install-applet.sh' && echo y)"
reset notallowed; run setup-check
check "setup-check reports 'not allowed' → exit 3" test "$RC" = 3 -a -n "$(has 'not allowed' && echo y)"
reset ok; run setup-check
check "setup-check when allowed → exit 0, 'setup OK'" test "$RC" = 0 -a -n "$(has 'setup OK' && echo y)"

reset nobutton; run up
check "no SAML Login button (new FortiClient UI) → exit 1, points to vpn dump" test "$RC" = 1 -a -n "$(has 'vpn dump' && echo y)"
reset ok; run dump
check "dump prints FortiClient's labels" test "$RC" = 0 -a -n "$(has 'AXButton  SAML Login' && echo y)"

reset nosignin; start=$(date +%s); run up; took=$(( $(date +%s) - start ))
check "sign-in never finishes → exit 1 after the timeout (${took}s)" test "$RC" = 1 -a "$took" -ge 5 -a "$took" -le 9
check "  … with a clear message" has 'not connected after'

reset silent; start=$(date +%s); run up; took=$(( $(date +%s) - start ))
check "applet never answers → exit 1 after the applet wait (${took}s)" test "$RC" = 1 -a -n "$(has "didn't answer" && echo y)"
check "  … lock released" test ! -e "$FORTIVPN_STATE/lock"

reset ok; mkdir -p "$FORTIVPN_STATE/lock"; run up
check "another vpn command running (fresh lock) → exit 1, applet not launched" test "$RC" = 1 -a "$(count open-calls)" = 0 -a -n "$(has 'another vpn command' && echo y)"
reset ok; mkdir -p "$FORTIVPN_STATE/lock"; touch -t 202001010000 "$FORTIVPN_STATE/lock"; run up
check "stale lock from a crash (> 2 min) is cleared → exit 0" test "$RC" = 0

reset ok; OUT=$(FORTIVPN_APPLET="$WORK/missing.app" "$VPN" up 2>&1); RC=$?
check "applet not built → exit 3, points to install-applet.sh" test "$RC" = 3 -a -n "$(has 'install-applet.sh' && echo y)"

reset ok
check "open was only ever called as 'open -g <applet>'" test ! -s "$S/violations"

# ------------------------------------------------------------------ installer
section "install-applet.sh (into a temp folder)"
OUT=""
T="$WORK/build/VPN Connect.app"
if out=$(VPN_APPLET="$T" VPN_APPLET_NO_SETTINGS=1 "$VPN_DIR/install-applet.sh" 2>&1); then ok "builds the applet"; else bad "builds the applet" "$out"; fi
check "  … bundle id local.vpnconnect" test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$T/Contents/Info.plist" 2>/dev/null)" = local.vpnconnect
check "  … hidden from the Dock (LSUIElement)" test "$(/usr/libexec/PlistBuddy -c 'Print :LSUIElement' "$T/Contents/Info.plist" 2>/dev/null)" = true
check "  … has an Apple Events usage text" /usr/libexec/PlistBuddy -c 'Print :NSAppleEventsUsageDescription' "$T/Contents/Info.plist"
check "  … validly signed" codesign --verify "$T"
check "  … contains the compiled script" test -f "$T/Contents/Resources/Scripts/main.scpt"
if out=$(VPN_APPLET="$T" "$VPN_DIR/install-applet.sh" --uninstall 2>&1) && [ ! -e "$T" ]; then ok "uninstall removes it"; else bad "uninstall removes it" "$out"; fi

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || { printf 'Failed:%b\n' "$FAILED"; exit 1; }
