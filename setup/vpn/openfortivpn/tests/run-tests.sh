#!/bin/bash
# Tests for setup/vpn: the vpn command (against a simulated openfortivpn daemon), the pppd hooks,
# and the installer (staged with --root). Needs no root, no VPN and no sign-in.
#
#   setup/vpn/openfortivpn/tests/run-tests.sh            all offline tests
#   LIVE=1 setup/vpn/openfortivpn/tests/run-tests.sh     also check the gateway's TLS chain against the CA bundle

set -u
VPN_DIR=$(cd "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/fortivpn-tests.XXXXXX")
trap 'pkill -f "$WORK/fakebin/daemon" 2>/dev/null; rm -rf "$WORK"' EXIT

PASS=0; FAIL=0; FAILED=""
ok()   { PASS=$((PASS + 1)); printf '  ok    %s\n' "$1"; }
bad()  { FAIL=$((FAIL + 1)); FAILED="$FAILED\n  - $1"; printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; }
OUT=""
check() {
  local name="$1"; shift
  if "$@"; then ok "$name"; else bad "$name" "${OUT:+last vpn output: $(printf '%s' "$OUT" | tail -n 6 | tr '\n' '|')}"; fi
}
section() { printf '\n%s\n' "$1"; }

# ------------------------------------------------------------------ fakes
F="$WORK/fakebin"; S="$WORK/state"
mkdir -p "$F" "$S"

cat >"$F/sudo" <<'EOF'
#!/bin/bash
# Mirrors /etc/sudoers.d/fortivpn: only these exact commands, only with -n.
echo "$*" >>"$FAKE_STATE/sudo-calls"
[ -e "$FAKE_STATE/nosudo" ] && { echo "sudo: a password is required" >&2; exit 1; }
[ "${1:-}" = -n ] || { echo "VIOLATION (no -n): $*" >>"$FAKE_STATE/violations"; exit 1; }
shift
case "$*" in
  "launchctl kickstart system/local.fortivpn"|"launchctl kill SIGTERM system/local.fortivpn") exec "$@" ;;
  *) echo "VIOLATION: $*" >>"$FAKE_STATE/violations"; echo "sudo: not allowed" >&2; exit 1 ;;
esac
EOF

cat >"$F/launchctl" <<'EOF'
#!/bin/bash
case "$1 $2" in
  "kickstart system/local.fortivpn")
    echo x >>"$FAKE_STATE/kickstarts"
    [ -e "$FAKE_STATE/running" ] && exit 0
    touch "$FAKE_STATE/running"
    nohup "$FAKE_BIN/daemon" >/dev/null 2>&1 &
    echo $! >"$FAKE_STATE/daemon.pid"
    sleep 0.2 ;;
  "kill SIGTERM")
    echo x >>"$FAKE_STATE/kills"
    [ -e "$FAKE_STATE/daemon.pid" ] && kill "$(cat "$FAKE_STATE/daemon.pid")" 2>/dev/null
    rm -f "$FAKE_STATE/running" "$FAKE_STATE/ppp" "$FAKE_STATE/daemon.pid"
    echo "INFO:   Cancelling threads..." >>"$FAKE_LOG" ;;
  *) echo "fake launchctl: unexpected $*" >&2; exit 1 ;;
esac
EOF

# Simulated openfortivpn: scenario from $FAKE_STATE/scenario.
cat >"$F/daemon" <<'EOF'
#!/bin/bash
L="$FAKE_LOG"; ST="$FAKE_STATE"
sc=$(cat "$ST/scenario" 2>/dev/null || echo ok)
# Clean up only if this is still the current daemon (an old one may be dying late).
finish() { [ "$(cat "$ST/daemon.pid" 2>/dev/null)" = "$$" ] && rm -f "$ST/running" "$ST/ppp" "$ST/daemon.pid"; exit 0; }
trap finish TERM
while [ ! -e "$ST/daemon.pid" ]; do sleep 0.05; done
[ "$sc" = crash ] && { echo "ERROR:  Could not load config" >>"$L"; finish; }
echo "INFO:   Listening for SAML login on port 8020" >>"$L"
echo "INFO:   Using SAML authentication URL https://vpnwm.japfacomfeed.co.id:443/remote/saml/start?redirect=1&realm=sso" >>"$L"
# The "user" signs in once the browser opens.
while [ ! -e "$ST/opened" ]; do sleep 0.2; done
sleep 1
case "$sc" in
  authfail) echo "ERROR:  Invalid SAML session id received from Fortinet server." >>"$L"; finish ;;
  hang) while :; do sleep 1; done ;;
esac
echo "DEBUG:  Found dns server 10.20.0.53 in xml config" >>"$L"
touch "$ST/ppp"
[ "$sc" = nodns ] || touch "$ST/reachable"
echo "INFO:   Tunnel is up and running." >>"$L"
while :; do sleep 1; done
EOF

cat >"$F/pgrep" <<'EOF'
#!/bin/bash
[ -e "$FAKE_STATE/running" ]
EOF
cat >"$F/ifconfig" <<'EOF'
#!/bin/bash
if [ -e "$FAKE_STATE/ppp" ]; then echo "lo0 en0 utun0 ppp0"; else echo "lo0 en0 utun0"; fi
EOF
cat >"$F/nc" <<'EOF'
#!/bin/bash
[ -e "$FAKE_STATE/reachable" ]
EOF
cat >"$F/open" <<'EOF'
#!/bin/bash
echo "$1" >>"$FAKE_STATE/opened"
EOF
chmod +x "$F"/*

export FAKE_STATE="$S" FAKE_BIN="$F" FAKE_LOG="$WORK/fortivpn.log"
export FORTIVPN_PATH="$F:/usr/bin:/bin:/usr/sbin:/sbin"
export FORTIVPN_LOG="$FAKE_LOG" FORTIVPN_CONF="$WORK/work.conf"
export FORTIVPN_TIMEOUT=6 FORTIVPN_START_WAIT=5

printf 'host = vpnwm.japfacomfeed.co.id\nport = 443\nrealm = sso\n' >"$FORTIVPN_CONF"

VPN="$VPN_DIR/vpn"
reset() {
  pkill -f "$F/daemon" 2>/dev/null
  while pgrep -f "$F/daemon" >/dev/null; do sleep 0.1; done
  rm -f "$S"/*
  : >"$FAKE_LOG"
  echo "${1:-ok}" >"$S/scenario"
}
count() { [ -e "$S/$1" ] && wc -l <"$S/$1" | tr -d ' ' || echo 0; }
run() { OUT=$("$VPN" "$@" 2>&1); RC=$?; }

# ------------------------------------------------------------------ lint
section "Lint"
if command -v shellcheck >/dev/null; then
  for f in vpn ip-up ip-down install.sh tests/run-tests.sh; do
    if msg=$(shellcheck -x "$VPN_DIR/$f" 2>&1); then ok "shellcheck $f"; else bad "shellcheck $f" "$(echo "$msg" | head -5)"; fi
  done
else
  bad "shellcheck installed" "brew install shellcheck"
fi
check "vpn parses with macOS /bin/bash 3.2" /bin/bash -n "$VPN"
check "install.sh parses with /bin/bash 3.2" /bin/bash -n "$VPN_DIR/install.sh"
check "ip-up parses with /bin/sh" /bin/sh -n "$VPN_DIR/ip-up"
check "ip-down parses with /bin/sh" /bin/sh -n "$VPN_DIR/ip-down"

# ------------------------------------------------------------------ vpn command
section "vpn command (simulated daemon)"

reset; run status
check "status when idle → disconnected, exit 1" test "$RC" = 1 -a -n "$(echo "$OUT" | grep 'disconnected')"
run check
check "check when unreachable → exit 1" test "$RC" = 1
run bogus
check "unknown command → usage, exit 64" test "$RC" = 64

reset ok; start=$(date +%s); run up; took=$(( $(date +%s) - start ))
check "up → exit 0" test "$RC" = 0
check "up → reports connected and probe reachable" grep -q 'connected (ppp0); jcvs.japfacomfeed.co.id reachable' <<<"$OUT"
check "up → opened the exact SAML URL from the log" test "$(cat "$S/opened" 2>/dev/null)" = "https://vpnwm.japfacomfeed.co.id:443/remote/saml/start?redirect=1&realm=sso"
check "up → one kickstart" test "$(count kickstarts)" = 1
check "up → finished promptly (${took}s)" test "$took" -le 5

run up
check "up again → 'already connected', exit 0" test "$RC" = 0 -a -n "$(echo "$OUT" | grep 'already connected')"
check "up again → no second kickstart" test "$(count kickstarts)" = 1
check "up again → browser not reopened" test "$(count opened)" = 1

run status
check "status when up → connected, exit 0" test "$RC" = 0 -a -n "$(echo "$OUT" | grep 'connected (ppp0)')"
run check
check "check when up → reachable, exit 0" test "$RC" = 0

run down
check "down → exit 0, disconnected" test "$RC" = 0 -a -n "$(echo "$OUT" | grep '^vpn: disconnected')"
check "down → daemon stopped via launchctl kill SIGTERM" test "$(count kills)" = 1 -a ! -e "$S/running"
run status
check "status after down → disconnected" test "$RC" = 1
run down
check "down again → 'already disconnected', exit 0, no extra kill" test "$RC" = 0 -a "$(count kills)" = 1

reset ok; touch "$S/reachable"; run up
check "up while another VPN gives reachability → exit 0, no kickstart" test "$RC" = 0 -a "$(count kickstarts)" = 0
check "  … and says so" grep -q 'already reachable through another VPN' <<<"$OUT"

reset authfail; start=$(date +%s); run up; took=$(( $(date +%s) - start ))
check "sign-in rejected → exit 1" test "$RC" = 1
check "  … shows the log tail with the error" grep -q 'Invalid SAML session id' <<<"$OUT"
check "  … fails fast, not at the timeout (${took}s)" test "$took" -lt 6

reset crash; run up
check "daemon crashes at start → exit 1 with log tail" test "$RC" = 1 -a -n "$(echo "$OUT" | grep 'Could not load config')"

reset hang; start=$(date +%s); run up; took=$(( $(date +%s) - start ))
check "no sign-in within timeout → exit 1, 'timed out'" test "$RC" = 1 -a -n "$(echo "$OUT" | grep 'timed out')"
check "  … daemon stopped afterwards" test "$(count kills)" = 1 -a ! -e "$S/running"
check "  … took about the timeout (${took}s)" test "$took" -ge 6 -a "$took" -le 10

reset hang; printf 'INFO:   Tunnel is up and running.\nINFO:   Cancelling threads...\n' >"$FAKE_LOG"; run up
check "stale 'Tunnel is up' from an earlier session is ignored" test "$RC" = 1 -a -n "$(echo "$OUT" | grep 'timed out')"

reset nodns; run up
check "tunnel up but probe host unreachable → exit 2 with DNS hint" test "$RC" = 2 -a -n "$(echo "$OUT" | grep 'check DNS')"
run down

reset ok; touch "$S/nosudo"; run up
check "not installed (sudo wants a password) → exit 3 with install hint" test "$RC" = 3 -a -n "$(echo "$OUT" | grep 'install.sh')"

# Re-attach: a previous 'vpn up' was interrupted while waiting for the sign-in.
reset ok
echo "INFO:   Tunnel is up and running." >"$FAKE_LOG"      # old session
"$F/launchctl" kickstart system/local.fortivpn; sleep 1  # daemon now waiting, browser never opened
run up
check "up while a sign-in is pending → re-attaches, exit 0" test "$RC" = 0 -a -n "$(echo "$OUT" | grep 'reopening the browser')"
check "  … no second kickstart" test "$(count kickstarts)" = 1
run down

reset ok; rm -f "$FORTIVPN_CONF.bak"; mv "$FORTIVPN_CONF" "$FORTIVPN_CONF.bak"
FORTIVPN_LOG="$WORK/unreadable.log" "$VPN" up >/dev/null 2>&1 &
pid=$!; sleep 4; touch "$S/opened"; wait "$pid"; RC=$?
mv "$FORTIVPN_CONF.bak" "$FORTIVPN_CONF"
check "no log and no conf → fails cleanly (exit 1), daemon stopped" test "$RC" = 1 -a ! -e "$S/running"
reset ok

check "sudo only ever got the two allowed commands" test ! -s "$S/violations"

# ------------------------------------------------------------------ pppd hooks
section "pppd hooks (ip-up / ip-down, staged)"
R="$WORK/root"; mkdir -p "$R/etc/openfortivpn" "$R/var/log" "$R/etc/resolver"
printf '# comment\njapfacomfeed.co.id\n\ncorp.internal\nbad;domain\n' >"$R/etc/openfortivpn/resolver-domains"
export FORTIVPN_ROOT="$R"
UP="$VPN_DIR/ip-up"; DOWN="$VPN_DIR/ip-down"

DNS1=10.1.1.1 DNS2=10.1.1.2 "$UP" ppp0 /dev/x 0 10.9.0.2 10.9.0.1 fortivpn
check "ip-up uses DNS1/DNS2 from pppd" test "$(grep -c nameserver "$R/etc/resolver/japfacomfeed.co.id" 2>/dev/null)" = 2
check "  … one file per listed domain" test -f "$R/etc/resolver/corp.internal"
check "  … skips an invalid domain" test ! -e "$R/etc/resolver/bad;domain"
check "  … files carry the managed marker" grep -q '^# fortivpn-managed' "$R/etc/resolver/corp.internal"
"$DOWN" ppp0 /dev/x 0 10.9.0.2 10.9.0.1 fortivpn
check "ip-down removes them" test ! -e "$R/etc/resolver/japfacomfeed.co.id" -a ! -e "$R/etc/resolver/corp.internal"

cat >"$R/var/log/fortivpn.log" <<'EOF'
DEBUG:  Found dns server 172.16.9.9 in xml config
INFO:   Listening for SAML login on port 8020
DEBUG:  Found dns server 10.20.0.53 in xml config
DEBUG:  Found dns server 10.20.0.54 in xml config
DEBUG:  Found dns server 999.1.1.1; rm -rf in xml config
EOF
env -u DNS1 -u DNS2 "$UP" ppp0 /dev/x 0 10.9.0.2 10.9.0.1 fortivpn
f="$R/etc/resolver/japfacomfeed.co.id"
check "ip-up falls back to this session's servers from the log" test "$(grep nameserver "$f" | tr '\n' ' ')" = "nameserver 10.20.0.53 nameserver 10.20.0.54 "
check "  … ignores the previous session's server" test -z "$(grep 172.16.9.9 "$f")"
check "  … ignores malformed values" test -z "$(grep 999 "$f")"
"$DOWN" ppp0 /dev/x 0 10.9.0.2 10.9.0.1 fortivpn

DNS1=10.1.1.1 "$UP" ppp0 /dev/x 0 10.9.0.2 10.9.0.1 some-other-vpn
check "ip-up ignores other PPP links (ipparam ≠ fortivpn)" test ! -e "$R/etc/resolver/japfacomfeed.co.id"

echo "nameserver 8.8.8.8" >"$R/etc/resolver/corp.internal"
DNS1=10.1.1.1 "$UP" ppp0 /dev/x 0 10.9.0.2 10.9.0.1 fortivpn
check "ip-up leaves a resolver file it didn't write alone" test "$(cat "$R/etc/resolver/corp.internal")" = "nameserver 8.8.8.8"
"$DOWN" ppp0 /dev/x 0 10.9.0.2 10.9.0.1 fortivpn
check "ip-down leaves a resolver file it didn't write alone" test -f "$R/etc/resolver/corp.internal"
check "ip-down still removes its own" test ! -e "$R/etc/resolver/japfacomfeed.co.id"

: >"$R/var/log/fortivpn.log"
env -u DNS1 -u DNS2 "$UP" ppp0 /dev/x 0 10.9.0.2 10.9.0.1 fortivpn
check "ip-up with no DNS info writes nothing and logs why" test ! -e "$R/etc/resolver/japfacomfeed.co.id" -a -n "$(grep 'no DNS servers' "$R/var/log/fortivpn.log")"
unset FORTIVPN_ROOT

# ------------------------------------------------------------------ installer
section "Installer (staged with --root)"
INST="$VPN_DIR/install.sh"; IR="$WORK/inst"
OFV="$(command -v openfortivpn || true)"
if [ -z "$OFV" ]; then
  bad "openfortivpn installed (brew install openfortivpn)"
else
  out=$("$INST" --user "$(id -un)" --root "$IR" 2>&1); rc=$?
  check "install.sh --root succeeds" test "$rc" = 0 || printf '%s\n' "$out"
  B="$IR/usr/local/libexec/fortivpn/openfortivpn"
  runs_ok() { "$1" --version >/dev/null 2>&1; }
  check "binary copied and runs" runs_ok "$B"
  check "binary links nothing under /Users, /opt or /usr/local" test -z "$(otool -L "$B" "$IR"/usr/local/libexec/fortivpn/*.dylib | grep -E '^\s+/(Users|opt|usr/local)/')"
  check "binary and libraries are validly signed" codesign --verify "$B"
  check "libraries copied alongside" test -n "$(ls "$IR"/usr/local/libexec/fortivpn/libssl*.dylib "$IR"/usr/local/libexec/fortivpn/libcrypto*.dylib 2>/dev/null)"
  check "plist passes plutil -lint" plutil -lint -s "$IR/Library/LaunchDaemons/local.fortivpn.plist"
  check "plist: not started at boot, no KeepAlive" test "$(plutil -extract RunAtLoad raw "$IR/Library/LaunchDaemons/local.fortivpn.plist")$(plutil -extract KeepAlive raw "$IR/Library/LaunchDaemons/local.fortivpn.plist")" = falsefalse
  check "plist: OpenSSL can't read user-writable config" test "$(plutil -extract EnvironmentVariables.OPENSSL_CONF raw "$IR/Library/LaunchDaemons/local.fortivpn.plist")" = /usr/local/libexec/fortivpn/openssl.cnf
  check "sudoers passes visudo -c" visudo -c -q -f "$IR/etc/sudoers.d/fortivpn"
  check "sudoers: exactly the two launchctl commands, mode 440" test "$(grep -c '/bin/launchctl' "$IR/etc/sudoers.d/fortivpn")" = 1 -a "$(stat -f %Lp "$IR/etc/sudoers.d/fortivpn")" = 440
  check "sudoers: no wildcard" test -z "$(grep -v '^#' "$IR/etc/sudoers.d/fortivpn" | grep '\*')"
  check "work.conf has no password" test -z "$(grep -i -E '^\s*(password|username|otp)' "$IR/etc/openfortivpn/work.conf")"
  check "CA bundle includes the GoDaddy G2 intermediate" grep -q -f <(sed -n 2p "$VPN_DIR/certs/godaddy-g2-intermediate.pem") "$IR/etc/openfortivpn/ca-bundle.pem"
  # shellcheck disable=SC2010 # ls -le is the only way to show ACLs
  check "log file has a read ACL for the user" test -n "$(ls -le "$IR/var/log/fortivpn.log" | grep "user:$(id -un) allow read")"
  check "vpn command installed, executable" test -x "$IR/usr/local/bin/vpn"

  # openfortivpn reads the config before its root check: any bad key would show up here.
  cfg=$("$B" -c "$IR/etc/openfortivpn/work.conf" -v 2>&1)
  check "openfortivpn accepts every key in work.conf" test -z "$(echo "$cfg" | grep -i -E 'bad|unknown|invalid')"
  check "  … reads host, realm and SAML port from it" test -n "$(echo "$cfg" | grep 'host = "vpnwm.japfacomfeed.co.id"')" -a -n "$(echo "$cfg" | grep 'realm = "sso"')"
  check "  … and then stops at the root check (as expected without sudo)" grep -q 'root privileges' <<<"$cfg"

  out=$("$INST" --user "$(id -un)" --root "$IR" 2>&1)
  check "re-running the installer is safe (idempotent)" test $? = 0

  echo "#!/bin/sh" >"$IR/etc/ppp/ip-up"
  out=$("$INST" --user "$(id -un)" --root "$IR" 2>&1); rc=$?
  check "installer refuses to overwrite a foreign /etc/ppp/ip-up" test "$rc" != 0 -a -n "$(echo "$out" | grep 'merge it by hand')"
  rm -f "$IR/etc/ppp/ip-up"

  out=$("$INST" --user "$(id -un)" --root "$IR" --uninstall 2>&1)
  check "uninstall removes everything it installed" test -z "$(find "$IR" -type f)"

  out=$("$INST" --user "$(id -un)" 2>&1); rc=$?
  check "installer without sudo and without --root refuses" test "$rc" != 0 -a -n "$(echo "$out" | grep 'run with sudo')"
  out=$("$INST" --user no-such-user-xyz --root "$IR" 2>&1); rc=$?
  check "installer rejects an unknown user" test "$rc" != 0
  out=$("$INST" --user "$(id -un)" --root "$IR" --domains 'ok.com bad;x' 2>&1); rc=$?
  check "installer rejects an invalid domain" test "$rc" != 0
fi

# ------------------------------------------------------------------ live (optional)
if [ "${LIVE:-0}" = 1 ]; then
  section "Live gateway checks (no sign-in)"
  b="$WORK/bundle.pem"; cat /etc/ssl/cert.pem "$VPN_DIR/certs/godaddy-g2-intermediate.pem" >"$b"
  v=$(echo | openssl s_client -connect vpnwm.japfacomfeed.co.id:443 -servername vpnwm.japfacomfeed.co.id -CAfile "$b" -verify_hostname vpnwm.japfacomfeed.co.id 2>/dev/null | grep 'Verify return code')
  check "gateway certificate verifies with the CA bundle ($v)" grep -q 'return code: 0' <<<"$v"
  v=$(echo | openssl s_client -connect vpnwm.japfacomfeed.co.id:443 -servername vpnwm.japfacomfeed.co.id -CAfile /etc/ssl/cert.pem 2>/dev/null | grep 'Verify return code')
  check "… and does NOT verify without the intermediate (why it's bundled)" grep -q 'return code: 21' <<<"$v"
  loc=$(curl -s --max-time 10 'https://vpnwm.japfacomfeed.co.id/remote/saml/start?redirect=1&realm=sso' | grep -o "login.microsoftonline.com" | head -1)
  check "SAML start URL redirects to Microsoft Entra" test "$loc" = login.microsoftonline.com
fi

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || { printf 'Failed:%b\n' "$FAILED"; exit 1; }
