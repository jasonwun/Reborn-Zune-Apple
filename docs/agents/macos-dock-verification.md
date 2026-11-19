# Isolated macOS Dock verification

Use this path when native acceptance includes the Dock menu. It avoids another
running development instance, keeps the real Library and store untouched, and
makes `applicationDockMenu` available through LaunchServices.

## Launch an isolated copy

1. Build the normal macOS scheme successfully. Copy that app bundle rather than
   creating a fresh build with product overrides, so SwiftPM resource bundles
   remain in place.
2. Give the copy a unique product and bundle identity. Do not quit or rename an
   existing development instance.
3. Put debug settings in the copy's `LSEnvironment`, then re-sign it. Launch the
   copy with `open -n`; invoking its executable directly can leave the custom
   Dock menu absent.
4. Keep the store inside the new bundle's sandbox container. Grant the separate
   test Library through the app's Open Panel.

Example, run from the repository root after replacing `SRC` with the built app
path and creating a test Library:

```sh
SRC='/path/to/Reborn Zune.app'
APP_NAME='Reborn Zune Verification'
BUNDLE_ID='dev.yjd.rebornzune.verification'
DST="/tmp/$APP_NAME.app"
STORE="$HOME/Library/Containers/$BUNDLE_ID/Data/tmp/verification.store"
TEST_LIBRARY="$HOME/Music/RebornZune-Verification"

cp -R "$SRC" "$DST"
INFO="$DST/Contents/Info.plist"
mkdir -p "$(dirname "$STORE")"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$INFO"
/usr/libexec/PlistBuddy -c "Set :CFBundleName $APP_NAME" "$INFO"
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName $APP_NAME" "$INFO" \
  2>/dev/null || /usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string $APP_NAME" "$INFO"
/usr/libexec/PlistBuddy -c 'Add :LSEnvironment dict' "$INFO"
/usr/libexec/PlistBuddy -c \
  "Add :LSEnvironment:REBORN_ZUNE_DEBUG_LIBRARY_FOLDER string $TEST_LIBRARY" "$INFO"
/usr/libexec/PlistBuddy -c \
  "Add :LSEnvironment:REBORN_ZUNE_DEBUG_STORE string $STORE" "$INFO"
/usr/libexec/PlistBuddy -c \
  'Add :LSEnvironment:REBORN_ZUNE_DEBUG_NO_LIGHTING string 1' "$INFO"
codesign --deep --force --sign - \
  --entitlements RebornZune-macOS.entitlements "$DST"
open -n "$DST"
```

## Inspect the real Dock menu

Use the unique product name to select the Dock item through System Events:

```applescript
tell application "System Events" to tell process "Dock"
  set icon to first UI element of list 1 whose name is "Reborn Zune Verification"
  perform action "AXShowMenu" of icon
  delay 1
  get name of every menu item of menu 1 of icon
end tell
```

Open a submenu and inspect its items before capturing the screen:

```applescript
tell application "System Events" to tell process "Dock"
  set icon to first UI element of list 1 whose name is "Reborn Zune Verification"
  set recent to menu item "Recently Played" of menu 1 of icon
  click recent
  delay 1
  get {name, enabled} of every menu item of menu 1 of recent
end tell
```

```sh
screencapture -x reports/screenshots/dock-verification.png
```

Read the screenshot and verify the ticket's ordering, enabled state, and
click-to-play behavior.

### Target the app when other instances are running

The unique display name selects the Dock icon, but System Events can still call
every development process `Reborn Zune`. Get the isolated app's PID with `orca
computer list-apps --json`, then use an explicit loop for app windows and menus:

```applescript
set targetPID to 12345 -- Replace with the isolated app's PID.
tell application "System Events"
  set targetProcess to missing value
  repeat with candidate in every process
    try
      if (unix id of candidate) is targetPID then set targetProcess to candidate
    end try
  end repeat
  tell targetProcess to get name of every menu bar item of menu bar 1
end tell
```

Use the loop rather than a `whose unix id` filter, which selected the wrong
process in a multi-instance verification run. Resolve the menu bar item again
for each action: changing between Play and Pause rebuilds the Controls menu and
can invalidate a cached reference. Read back the expected app state after every
action; a successful accessibility call alone is not behavior evidence.

## Inspect related system Now Playing behavior

Open the system status item and expand the row belonging to the isolated app.
Through System Events, inspect `window "Control Center"` of process
`ControlCenter`; its `entire contents` expose the current title, transport
buttons, and an `AXSlider` for playback position. Other apps can appear in the
same surface, so select the row by the current Track title.

If assigning the slider's value does not change the app, use the slider's
accessibility position and size to click the desired fraction with CGEvent:

```text
x = sliderX + sliderWidth * fraction
y = sliderY + sliderHeight / 2
post leftMouseDown, then leftMouseUp at (x, y)
```

Read the app's displayed position after every remote action. For paused
exactness, read the system slider twice with a delay and compare the full values.
Capture and inspect playing, paused, and seeking states together with the app.

## Clean up only the isolated copy

After verification, quit only the unique bundle ID and remove only its test
Library, store, and app copy. Container-manager metadata at the container root
can be protected; remove the isolated `Data` contents without changing system
privacy settings or other app containers.
