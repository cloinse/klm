on run arguments
  set volumeName to item 1 of arguments
  set applicationName to item 2 of arguments

  tell application "Finder"
    tell disk (volumeName as text)
      open
      set current view of container window to icon view
      set toolbar visible of container window to false
      set statusbar visible of container window to false
      set bounds of container window to {120, 120, 780, 540}

      set viewOptions to the icon view options of container window
      set arrangement of viewOptions to not arranged
      set icon size of viewOptions to 112
      set text size of viewOptions to 14
      set background picture of viewOptions to file ".background:background.png"

      set position of item (applicationName & ".app") to {170, 210}
      set position of item "Applications" to {490, 210}
      update without registering applications
      delay 2
      close
    end tell
  end tell
end run
