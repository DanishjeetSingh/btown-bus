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
# When the signature on the phone runs out, written after each install. The build folder can't be
# trusted for this: a build whose install failed (phone locked) would look fresh while the phone isn't.
STATE=~/Library/Logs/btown-bus/installed-until
PROFILES=~/Library/Developer/Xcode/UserData/"Provisioning Profiles"
log() { print -r -- "$(date '+%F %T') $*"; }
notify() { osascript -e "display notification \"$2\" with title \"$1\"" 2>/dev/null; }
expiry_of() { security cms -D -i "$APP/embedded.mobileprovision" 2>/dev/null | plutil -extract ExpirationDate raw -o - - 2>/dev/null; }
seconds_left() { print $(( $(date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$1" +%s 2>/dev/null || print 0) - $(date +%s) )); }

git -C "$REPO" pull -q --ff-only 2>/dev/null || log "couldn't update from GitHub, building what's here"
cd "$REPO/ios" || exit 1

installed=$(cat "$STATE" 2>/dev/null)
if [[ -n $installed && ${1:-} != --force ]] && (( $(seconds_left "$installed") > 3 * 86400 )); then
  log "phone's copy is good until $installed, skipping"; exit 0
fi

if ! xcrun devicectl list devices 2>/dev/null | grep "$DEVICE" | grep -qE "available|connected"; then
  log "iPhone not reachable, will retry later"; exit 0
fi

built=$(expiry_of)
# A build from an earlier run that never got installed and still has days left only needs installing.
if [[ -z $built || $built == "$installed" || ${1:-} == --force ]] || (( $(seconds_left "$built") <= 3 * 86400 )); then
  # Xcode keeps reusing its saved 7-day profile until it expires, so a rebuild alone signs with the same
  # end date. Set this app's saved profiles aside so Xcode fetches fresh ones; put them back if it can't.
  aside=$(mktemp -d)
  for profile in "$PROFILES"/*.mobileprovision(N); do
    if security cms -D -i "$profile" 2>/dev/null | grep -q "me.singhdan.btownbus"; then mv "$profile" "$aside/"; fi
  done
  log "building"
  output=$(xcodebuild -project BTownBus.xcodeproj -scheme BTownBus -destination 'generic/platform=iOS' \
    -derivedDataPath build -allowProvisioningUpdates build -quiet 2>&1)
  if (( $? != 0 )); then
    mv "$aside"/*.mobileprovision(N) "$PROFILES"/ 2>/dev/null
    if print -r -- "$output" | grep -q "No Accounts"; then
      log "Xcode is signed out of the Apple ID; can't renew"
      notify "B-Town Bus can't renew" "Xcode is signed out. Open Xcode → Settings → Accounts and sign in."
    else
      log "build failed: $(print -r -- "$output" | grep -m1 error:)"
      notify "B-Town Bus can't renew" "The build failed. See ~/Library/Logs/btown-bus/renew.log."
    fi
    exit 1
  fi
  rm -rf "$aside"
  built=$(expiry_of)
  if (( $(seconds_left "$built") <= 3 * 86400 )); then
    log "Xcode only signed it until $built; reinstalling wouldn't help"
    notify "B-Town Bus can't renew" "Xcode reused an old signature (until ${built%%T*})."
    exit 1
  fi
fi

log "installing (signed until $built)"
if xcrun devicectl device install app --device "$DEVICE" "$APP" 2>&1 | grep -q "App installed"; then
  print -r -- "$built" > "$STATE"
  log "installed"
  notify "B-Town Bus renewed" "Signed until ${built%%T*}"
else
  log "install failed (phone locked?), will retry later"
fi
