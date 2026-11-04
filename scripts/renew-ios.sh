#!/bin/zsh
# Re-sign B-Town Bus with the free Apple ID and reinstall it on the iPhone.
# Run by hand, or every few days by the launchd agent (scripts/me.singhdan.btownbus.renew.plist).
# Works over USB or Wi-Fi as long as the phone is reachable and unlocked.
# The agent runs from a copy at ~/Developer/btown-bus-renew (macOS blocks background jobs from
# ~/Documents) and pulls the latest main from GitHub before building.
set -u
DEVICE=00008130-001119291142001C
REPO=${0:A:h:h}
APP=$REPO/ios/build/Build/Products/Debug-iphoneos/BTownBus.app
log() { print -r -- "$(date '+%F %T') $*"; }

git -C "$REPO" pull -q --ff-only 2>/dev/null || log "couldn't update from GitHub, building what's here"
cd "$REPO/ios" || exit 1
# Skip if the current signature still has more than 3 days left.
if [[ -f $APP/embedded.mobileprovision && ${1:-} != --force ]]; then
  expiry=$(security cms -D -i "$APP/embedded.mobileprovision" 2>/dev/null | plutil -extract ExpirationDate raw -o - - 2>/dev/null)
  left=$(( $(date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$expiry" +%s 2>/dev/null || echo 0) - $(date +%s) ))
  if (( left > 3 * 86400 )); then log "still valid until $expiry, skipping"; exit 0; fi
fi

if ! xcrun devicectl list devices 2>/dev/null | grep "$DEVICE" | grep -qE "available|connected"; then
  log "iPhone not reachable, will retry later"; exit 0
fi

log "building"
xcodebuild -project BTownBus.xcodeproj -scheme BTownBus -destination 'generic/platform=iOS' \
  -derivedDataPath build -allowProvisioningUpdates build -quiet >/dev/null 2>&1 || { log "build failed (signed out of Xcode?)"; exit 1; }
expiry=$(security cms -D -i "$APP/embedded.mobileprovision" | plutil -extract ExpirationDate raw -o - -)

log "installing (signed until $expiry)"
if xcrun devicectl device install app --device "$DEVICE" "$APP" 2>&1 | grep -q "App installed"; then
  log "installed"
  osascript -e "display notification \"Signed until ${expiry%%T*}\" with title \"B-Town Bus renewed\"" 2>/dev/null
else
  log "install failed (phone locked?), will retry later"
fi
