#!/bin/bash
# Builds ~/Applications/VPN Connect.app from setup/vpn/forticlient/VPNConnect.applescript.
# No admin needed. Afterwards allow it once in System Settings > Privacy & Security > Accessibility.
#
#   setup/vpn/install-applet.sh             build (or rebuild) and open the Accessibility settings
#   setup/vpn/install-applet.sh --uninstall remove the app and its cache folder
#
# A rebuild changes the app's signature, so macOS may need it allowed again (toggle it off and on).

set -euo pipefail
PATH=/usr/bin:/bin:/usr/sbin:/sbin

HERE=$(cd "$(dirname "$0")" && pwd)
APP="${VPN_APPLET:-$HOME/Applications/VPN Connect.app}"
BUNDLE_ID="local.vpnconnect"

if [ "${1:-}" = --uninstall ]; then
  rm -rf "$APP" "$HOME/Library/Caches/vpn-connect"
  echo "install-applet: removed $APP. Also remove it from Privacy & Security > Accessibility."
  exit 0
fi

[ -d /Applications/FortiClient.app ] || { echo "install-applet: FortiClient isn't installed" >&2; exit 1; }
mkdir -p "$(dirname "$APP")"
rm -rf "$APP"
osacompile -o "$APP" "$HERE/forticlient/VPNConnect.applescript"

P="$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$P" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string $BUNDLE_ID" "$P"
/usr/libexec/PlistBuddy -c "Add :LSUIElement bool true" "$P" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :NSAppleEventsUsageDescription string 'Clicks SAML Login and Disconnect in FortiClient for the vpn command.'" "$P" 2>/dev/null || true
codesign --force --deep --sign - "$APP"
codesign --verify "$APP"

echo "install-applet: built $APP"
if [ -z "${VPN_APPLET_NO_SETTINGS:-}" ]; then
  echo "install-applet: allow 'VPN Connect' under Accessibility (click +, pick it from ~/Applications), then run: setup/vpn/vpn setup-check"
  open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
fi
