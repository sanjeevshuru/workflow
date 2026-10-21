#!/bin/bash
# One-time install of the command-line VPN (openfortivpn, SAML sign-in). Run by an admin:
#
#   sudo setup/vpn/install.sh --user <developer-login> [--openfortivpn <path>] [--domains "<d1> <d2>"]
#   sudo setup/vpn/install.sh --user <developer-login> --uninstall
#
# What it installs (everything root-owned):
#   /usr/local/libexec/fortivpn/        openfortivpn + its OpenSSL libraries, relinked and ad-hoc signed,
#                                       so nothing that runs as root loads code from a user-writable folder
#   /etc/openfortivpn/work.conf         gateway, realm, SAML port, CA bundle (no secrets: sign-in is SAML)
#   /etc/openfortivpn/ca-bundle.pem     system CAs + the GoDaddy G2 intermediate the gateway doesn't send
#   /etc/openfortivpn/resolver-domains  internal DNS domains for /etc/resolver (split DNS)
#   /etc/ppp/ip-up, /etc/ppp/ip-down    write/remove /etc/resolver/<domain> for the VPN link only
#   /Library/LaunchDaemons/local.fortivpn.plist   on-demand daemon (no RunAtLoad, no KeepAlive)
#   /etc/sudoers.d/fortivpn             <user> may run exactly two commands without a password:
#                                       launchctl kickstart / kill SIGTERM system/local.fortivpn
#   /usr/local/bin/vpn                  the user command
#   /var/log/fortivpn.log               root-owned, readable by <user> through an ACL
#
# --root <dir> stages everything under <dir> without root (no chown, launchctl or sudoers install);
# the test suite uses it.

set -euo pipefail
PATH=/usr/bin:/bin:/usr/sbin:/sbin

HERE=$(cd "$(dirname "$0")" && pwd)
LABEL="local.fortivpn"
GATEWAY_HOST="vpnwm.japfacomfeed.co.id"
GATEWAY_PORT="443"
REALM="sso"
SAML_PORT="8020"
DEFAULT_DOMAINS="japfacomfeed.co.id"
MARKER="fortivpn-managed"

USER_NAME=""
OFV_SRC=""
DOMAINS="$DEFAULT_DOMAINS"
ROOT=""
UNINSTALL=0

die() { echo "install: $*" >&2; exit 1; }
step() { echo "install: $*"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --user) USER_NAME="${2:-}"; shift 2 ;;
    --openfortivpn) OFV_SRC="${2:-}"; shift 2 ;;
    --domains) DOMAINS="${2:-}"; shift 2 ;;
    --root) ROOT="${2:-}"; shift 2 ;;
    --uninstall) UNINSTALL=1; shift ;;
    -h|--help) sed -n '2,25p' "$0"; exit 0 ;;
    *) die "unknown option $1 (see --help)" ;;
  esac
done

[ "$(uname -s)" = Darwin ] || die "macOS only"
[ -n "$USER_NAME" ] || die "--user <developer-login> is required"
id -u "$USER_NAME" >/dev/null 2>&1 || die "no such user: $USER_NAME"
printf '%s' "$USER_NAME" | grep -Eq '^[A-Za-z0-9._@-]+$' || die "unsupported characters in user name: $USER_NAME"
if [ -z "$ROOT" ]; then
  [ "$(id -u)" -eq 0 ] || die "run with sudo (an admin account), or use --root <dir> to stage"
else
  mkdir -p "$ROOT"; ROOT=$(cd "$ROOT" && pwd)
fi

LIBEXEC="$ROOT/usr/local/libexec/fortivpn"
ETC="$ROOT/etc/openfortivpn"
PPP="$ROOT/etc/ppp"
PLIST="$ROOT/Library/LaunchDaemons/$LABEL.plist"
SUDOERS="$ROOT/etc/sudoers.d/fortivpn"
BIN="$ROOT/usr/local/bin/vpn"
LOGFILE="$ROOT/var/log/fortivpn.log"

own() { [ -n "$ROOT" ] || chown "$@"; }
staged() { [ -n "$ROOT" ]; }

is_ours() { [ ! -e "$1" ] || grep -q "$MARKER" "$1"; }

# ---------------------------------------------------------------- uninstall
if [ "$UNINSTALL" -eq 1 ]; then
  if ! staged; then
    launchctl kill SIGTERM "system/$LABEL" 2>/dev/null || true
    launchctl bootout "system/$LABEL" 2>/dev/null || true
  fi
  rm -f "$PLIST" "$SUDOERS" "$BIN" "$LOGFILE"
  rm -rf "$LIBEXEC" "$ETC"
  for f in "$PPP/ip-up" "$PPP/ip-down" "$ROOT"/etc/resolver/*; do
    [ -f "$f" ] && grep -q "$MARKER" "$f" && rm -f "$f"
  done
  step "removed. openfortivpn itself (Homebrew) is left installed: brew uninstall openfortivpn"
  exit 0
fi

# ---------------------------------------------------------------- checks
[ -x /usr/sbin/pppd ] || die "/usr/sbin/pppd is missing; openfortivpn needs it"

if [ -z "$OFV_SRC" ]; then
  home=$(dscl . -read "/Users/$USER_NAME" NFSHomeDirectory 2>/dev/null | awk '{print $2}')
  for c in /opt/homebrew/bin/openfortivpn /usr/local/bin/openfortivpn "$home/homebrew/bin/openfortivpn"; do
    [ -x "$c" ] && { OFV_SRC="$c"; break; }
  done
fi
[ -n "$OFV_SRC" ] && [ -x "$OFV_SRC" ] || die "openfortivpn not found; brew install openfortivpn, or pass --openfortivpn <path>"
OFV_SRC=$(realpath "$OFV_SRC")
"$OFV_SRC" --help 2>&1 | grep -q -- '--saml-login' || die "$OFV_SRC has no --saml-login (needs openfortivpn 1.17+)"

for f in "$PPP/ip-up" "$PPP/ip-down"; do
  is_ours "$f" || die "$f exists and wasn't written by this installer; merge it by hand (see setup/vpn.md)"
done
for d in $DOMAINS; do
  printf '%s' "$d" | grep -Eq '^[A-Za-z0-9.-]+$' || die "invalid domain: $d"
done

# ---------------------------------------------------------------- binary + libraries
step "copying $OFV_SRC and its libraries to ${LIBEXEC#"$ROOT"}"
rm -rf "$LIBEXEC"; mkdir -p "$LIBEXEC"
cp "$OFV_SRC" "$LIBEXEC/openfortivpn"

non_system_deps() {
  otool -L "$1" | tail -n +2 | awk '{print $1}' \
    | grep -Ev '^(/usr/lib/|/System/|@)' | grep -v "/$(basename "$1")\$" || true
}

queue="$LIBEXEC/openfortivpn"
while [ -n "$queue" ]; do
  # shellcheck disable=SC2086 # split the space-separated queue on purpose
  set -- $queue; file="$1"; shift; queue="$*"
  for dep in $(non_system_deps "$file"); do
    base=$(basename "$dep")
    if [ ! -e "$LIBEXEC/$base" ]; then
      cp "$(realpath "$dep")" "$LIBEXEC/$base"
      chmod 644 "$LIBEXEC/$base"
      install_name_tool -id "@loader_path/$base" "$LIBEXEC/$base" 2>/dev/null
      queue="$queue $LIBEXEC/$base"
    fi
    install_name_tool -change "$dep" "@loader_path/$base" "$file" 2>/dev/null
  done
done

for f in "$LIBEXEC"/*.dylib "$LIBEXEC/openfortivpn"; do
  [ -e "$f" ] || continue
  codesign --force --sign - "$f" 2>/dev/null
  left=$(non_system_deps "$f")
  [ -z "$left" ] || die "$f still links outside ${LIBEXEC#"$ROOT"}: $left"
done
chmod 755 "$LIBEXEC/openfortivpn"
# Empty OpenSSL config: stops libcrypto from reading the user-writable Homebrew openssl.cnf as root.
echo "# $MARKER: empty on purpose (see setup/vpn/install.sh)" >"$LIBEXEC/openssl.cnf"
chmod 644 "$LIBEXEC/openssl.cnf"
"$LIBEXEC/openfortivpn" --version >/dev/null 2>&1 || die "relinked openfortivpn doesn't run"
own -R root:wheel "$LIBEXEC"

# ---------------------------------------------------------------- config
step "writing ${ETC#"$ROOT"}"
mkdir -p "$ETC"; chmod 755 "$ETC"
cat >"$ETC/work.conf" <<EOF
# $MARKER: written by setup/vpn/install.sh. No secrets: sign-in is SAML (Microsoft) in the browser.
host = $GATEWAY_HOST
port = $GATEWAY_PORT
realm = $REALM
saml-login = $SAML_PORT
ca-file = /etc/openfortivpn/ca-bundle.pem
set-routes = 1
half-internet-routes = 0
# macOS ignores /etc/resolv.conf; /etc/ppp/ip-up sets /etc/resolver/<domain> instead.
set-dns = 0
pppd-use-peerdns = 1
pppd-ipparam = fortivpn
EOF
# The gateway sends only its leaf certificate; add GoDaddy's G2 intermediate to the system CAs.
cat /etc/ssl/cert.pem "$HERE/certs/godaddy-g2-intermediate.pem" >"$ETC/ca-bundle.pem"
{
  echo "# $MARKER: internal DNS domains, one per line; ip-up points each at the VPN's DNS servers"
  for d in $DOMAINS; do echo "$d"; done
} >"$ETC/resolver-domains"
chmod 644 "$ETC"/*
own -R root:wheel "$ETC"

# ---------------------------------------------------------------- pppd hooks
step "installing ${PPP#"$ROOT"}/ip-up and ip-down"
mkdir -p "$PPP"
install -m 755 "$HERE/ip-up" "$PPP/ip-up"
install -m 755 "$HERE/ip-down" "$PPP/ip-down"
own root:wheel "$PPP/ip-up" "$PPP/ip-down"

# ---------------------------------------------------------------- log
mkdir -p "$(dirname "$LOGFILE")"
touch "$LOGFILE"; chmod 600 "$LOGFILE"; own root:wheel "$LOGFILE"
chmod -a "user:$USER_NAME allow read" "$LOGFILE" 2>/dev/null || true
chmod +a "user:$USER_NAME allow read" "$LOGFILE"

# ---------------------------------------------------------------- launchd
step "writing ${PLIST#"$ROOT"}"
mkdir -p "$(dirname "$PLIST")"
cat >"$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<!-- $MARKER: written by setup/vpn/install.sh. Started on demand by 'vpn up'; never at boot. -->
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>/usr/local/libexec/fortivpn/openfortivpn</string>
    <string>-c</string>
    <string>/etc/openfortivpn/work.conf</string>
  </array>
  <key>RunAtLoad</key><false/>
  <key>KeepAlive</key><false/>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key><string>/usr/bin:/bin:/usr/sbin:/sbin</string>
    <key>OPENSSL_CONF</key><string>/usr/local/libexec/fortivpn/openssl.cnf</string>
    <key>OPENSSL_MODULES</key><string>/usr/local/libexec/fortivpn</string>
    <key>SSL_CERT_FILE</key><string>/etc/openfortivpn/ca-bundle.pem</string>
    <key>SSL_CERT_DIR</key><string>/var/empty</string>
  </dict>
  <key>StandardOutPath</key><string>/var/log/fortivpn.log</string>
  <key>StandardErrorPath</key><string>/var/log/fortivpn.log</string>
</dict>
</plist>
EOF
chmod 644 "$PLIST"; own root:wheel "$PLIST"
plutil -lint "$PLIST" >/dev/null || die "invalid plist"

# ---------------------------------------------------------------- sudoers
step "writing ${SUDOERS#"$ROOT"}"
tmp=$(mktemp)
cat >"$tmp" <<EOF
# $MARKER: written by setup/vpn/install.sh. Lets $USER_NAME start and stop the on-demand VPN
# daemon without a password. Exact arguments only; nothing else runs as root.
Cmnd_Alias FORTIVPN_CMDS = /bin/launchctl kickstart system/$LABEL, /bin/launchctl kill SIGTERM system/$LABEL
"$USER_NAME" ALL=(root) NOPASSWD: FORTIVPN_CMDS
EOF
visudo -c -q -f "$tmp" >/dev/null || { rm -f "$tmp"; die "generated sudoers file doesn't parse"; }
mkdir -p "$(dirname "$SUDOERS")"
if staged; then install -m 440 "$tmp" "$SUDOERS"; else install -m 440 -o root -g wheel "$tmp" "$SUDOERS"; fi
rm -f "$tmp"

# ---------------------------------------------------------------- user command
mkdir -p "$(dirname "$BIN")"
install -m 755 "$HERE/vpn" "$BIN"; own root:wheel "$BIN"

# ---------------------------------------------------------------- load + verify
# launchctl is replaceable only in --root staging, for the test suite (sudo resets the environment).
LCTL=/bin/launchctl
if staged && [ -n "${INSTALL_LAUNCHCTL:-}" ]; then LCTL="$INSTALL_LAUNCHCTL"; fi

loaded() { "$LCTL" print "system/$LABEL" >/dev/null 2>&1; }
running() { "$LCTL" print "system/$LABEL" 2>/dev/null | grep -q 'pid = '; }
wait_for() { # wait_for <seconds> <command…>: until the command succeeds
  local n=$(( $1 * 4 )); shift
  while [ "$n" -gt 0 ]; do "$@" && return 0; sleep 0.25; n=$((n - 1)); done
  return 1
}
not() { ! "$@"; }

# Reload the daemon so a changed plist takes effect. bootout is asynchronous: bootstrapping again
# before the old job is gone fails with "Bootstrap failed: 5: Input/output error".
reload_daemon() {
  if loaded; then
    if running; then
      step "the VPN is connected: disconnecting it to reload the daemon (run 'vpn up' afterwards)"
      "$LCTL" kill SIGTERM "system/$LABEL" 2>/dev/null || true
      wait_for 15 not running || step "warning: openfortivpn didn't stop within 15s"
    fi
    "$LCTL" bootout "system/$LABEL" 2>/dev/null || true
    wait_for 15 not loaded || die "the old daemon didn't unload; try again in a few seconds"
  fi
  "$LCTL" enable "system/$LABEL" 2>/dev/null || true
  local try out
  for try in 1 2 3 4 5; do
    if out=$("$LCTL" bootstrap system "$PLIST" 2>&1); then
      loaded && return 0
    fi
    [ "$try" -lt 5 ] && sleep 1
  done
  die "couldn't load the daemon: ${out:-unknown error}"
}

if ! staged || [ -n "${INSTALL_LAUNCHCTL:-}" ]; then
  reload_daemon
  step "daemon loaded"
fi
if ! staged; then
  sudo -l -U "$USER_NAME" | grep -q "system/$LABEL" || die "sudoers rule not active (is /etc/sudoers.d included?)"
  step "done. As $USER_NAME, run: vpn up"
else
  step "staged under $ROOT"
fi
