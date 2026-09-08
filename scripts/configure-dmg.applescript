on run argv
    set volumeName to item 1 of argv

    tell application "Finder"
        set targetDisk to first disk whose name is my volumeName
        tell targetDisk
            open
            set current view of container window to icon view
            set toolbar visible of container window to false
            set statusbar visible of container window to false
            set bounds of container window to {120, 120, 780, 540}

            set viewOptions to the icon view options of container window
            set arrangement of viewOptions to not arranged
            set icon size of viewOptions to 112
            set text size of viewOptions to 14
            set background color of viewOptions to {62194, 62194, 62194}
            set background picture of viewOptions to file ".background:background.png"

            set position of item "RazerMon.app" of container window to {175, 205}
            set position of item "Applications" of container window to {485, 205}
            update without registering applications
            delay 2
            close
            open
            set toolbar visible of container window to false
            set statusbar visible of container window to false
            delay 2
        end tell
    end tell
end run
