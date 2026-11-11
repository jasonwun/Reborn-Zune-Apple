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
click-to-play behavior. After verification, quit only the unique bundle ID and
remove only its test Library, store, and app copy.
