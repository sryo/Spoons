These Hammerspoon scripts are designed to enhance the usability and productivity of macOS by providing various workspace management features. The scripts help display time near the mouse cursor, manage and dispose of .dmg files, provide a virtual keyboard for typing on your Mac from other devices, prevent the menu bar from appearing, automatically tile windows, or open URLs in different browsers.

### AutoDMG
[`AutoDMG.lua`](https://github.com/sryo/Spoons/blob/main/AutoDMG.lua) simplifies the process of mounting DMG files, locating applications within them, and copying those applications to the Applications folder.

#### Features
- Automatic installation: Monitors the Downloads folder for new DMGs and performs installation automatically.
- Automatic cleanup: After installation, the script unmounts the DMG and deletes the original file to keep the Downloads folder organized.

![cloudpad](https://github.com/user-attachments/assets/47fd58d2-fcf9-4c11-9dd3-7e74d4abc9bc)
### CloudPad
[`CloudPad.lua`](https://github.com/sryo/Spoons/blob/main/CloudPad.lua) - Use your phone as a keyboard/trackpad for your Mac via a local web server.

#### How to Use
- Press ⌘⌃C to copy the server URL.
- Open the URL on your phone's browser.

![framemaster](https://github.com/user-attachments/assets/155fd5d5-3bb4-4ad3-9056-ef8c22bf7514)
### FrameMaster
[`FrameMaster.lua`](https://github.com/sryo/Spoons/blob/main/FrameMaster.lua) - Take control of your Mac's 'hot corners', menu bar, and dock. Master your screen frame and manage your workflow with minimal distractions.

#### Features
- Hot corners: Define custom actions for each corner of the screen. Actions are defined in the hotCorners table and can be updated as needed.
- Keep the dock and menubar hidden.
- Reopen last app: When an app is killed, a modal will be shown to allow you to easily reopen it.

#### How to Use

| Action                        | Shortcut                                              |
|-------------------------------|-------------------------------------------------------|
| Close or Quit App          | Move mouse to the top-left corner                     |
| Kill Frontmost App         | <kbd>⇧ SHIFT</kbd> + move mouse to the top-left corner |
| Reopen Last App Modal      | Automatically shown when an app is killed             |
| Toggle Fullscreen          | Move mouse to the top-right corner                    |
| Zoom Window                | <kbd>⇧ SHIFT</kbd> + move mouse to the top-right corner |
| Minimize Window            | Move mouse to the bottom-right corner                 |
| Hide App                   | <kbd>⇧ SHIFT</kbd> + move mouse to the bottom-right corner |
| Open Finder                | Move mouse to the bottom-left corner                  |
| Open System Preferences    | <kbd>⇧ SHIFT</kbd> + move mouse to the bottom-left corner |


![hyperlinkhijacker](https://github.com/user-attachments/assets/330318f0-2bfd-4502-bc80-5d1ab06adabe)
### HyperlinkHijacker
[`HyperlinkHijacker.lua`](https://github.com/sryo/Spoons/blob/main/HyperlinkHijacker.lua) - It's your link, and you decide where it goes. 

#### How to Use

| Action               | Shortcut                                  |
|----------------------|---------------------------------------------|
| Open link in the first browser | Click the link and wait  |
| Choose browser to open link    | Click link and select from the list |
| Bypass chooser and open directly | <kbd>⇧ SHIFT</kbd> + Click the link |
| Copy link to clipboard         | Select "Copy to Clipboard" from the list |


### 🗂️🔍 MenuMaestro
[`MenuMaestro.lua`](https://github.com/sryo/Spoons/blob/main/MenuMaestro.lua) - Easily access menu items and shortcuts with a visually appealing interface.

#### How to Use

| Action               | Shortcut                                  |
|----------------------|---------------------------------------------|
| Activate menu chooser | <kbd>^ CTRL</kbd><kbd>⌥ ALT</kbd><kbd>SPACE</kbd> or tap with 5 fingers on trackpad |
| Search and select menu item    | Type and choose with keyboard/mouse |


![sssssssscroll](https://github.com/user-attachments/assets/fa3450ea-c3ef-4f77-bf99-958cfb570fc9)
### Sssssssscroll
[`Sssssssscroll.lua`](https://github.com/sryo/Spoons/blob/main/Sssssssscroll.lua) - Use mouth noises to scroll.

#### How to Use
| Action               | Sound/Shortcut                            |
|----------------------|---------------------------------------------|
| Toggle listener on/off | <kbd>⌘ CMD</kbd><kbd>⌥ ALT</kbd><kbd>^ CTRL</kbd><kbd>S</kbd> |
| Continuous scroll    | Make a continuous "Ssssssss" sound        |
| Single action        | Make a single water drop sound (lip pop)  |
| Double action        | Make two quick water drop sounds (lip pops) |

Note: Actions may vary depending on the active application. Default actions include scrolling down, scrolling up, and pressing Shift+Space.

### 🪄🖱️ TrackpadKeys
[`TrackpadKeys.lua`](https://github.com/sryo/Spoons/blob/main/TrackpadKeys.lua) adds a row of keys to the top of the trackpad.

#### How to Use

| Action               | Shortcut                                  |
|----------------------|---------------------------------------------|
| Activate virtual keyboard row | Swipe top edge of trackpad  |
| Input uppercase letters       | Touch bottom corner while swiping the top |


### 🪄🌇 WindowScape
[`WindowScape.lua`](https://github.com/sryo/Spoons/blob/main/WindowScape.lua) is the ultimate tool in window organization, transforming chaos into a neat urban landscape.

#### Features
- Automatically tiles windows of whitelisted applications (or set it to avoid tiling the apps listed there).

#### How to Use

| Action               | Shortcut                                  |
|----------------------|---------------------------------------------|
| Add/Remove app to/from whitelist | <kbd>^ CTRL</kbd><kbd>⌘ CMD</kbd><kbd><</kbd> |
| Move window backward in tiling order | <kbd>^ CTRL</kbd><kbd>⌘ CMD</kbd><kbd>←</kbd> or 3 fingers touch + a tap to the left |
| Move window forward in tiling order  | <kbd>^ CTRL</kbd><kbd>⌘ CMD</kbd><kbd>→</kbd> or 3 fingers touch + a tap to the right |
| Move window to previous space       | <kbd>^ CTRL</kbd><kbd>⌘ CMD</kbd><kbd>⌥ ALT</kbd><kbd>←</kbd> or 4 fingers touch + a tap to the left |
| Move window to next space           | <kbd>^ CTRL</kbd><kbd>⌘ CMD</kbd><kbd>⌥ ALT</kbd><kbd>→</kbd> or 4 fingers touch + a tap to the right |


![zxnav](https://github.com/user-attachments/assets/aa33821c-baea-4c8f-8fe8-629f8e54bd5e)
### ZXNav
[`ZXNav.lua`](https://github.com/sryo/Spoons/blob/main/ZXNav.lua) - Moves text navigation and editing actions closer to the spacebar for easier reach.

#### How to Use

| Action               | Shortcut                                  |
|----------------------|---------------------------------------------|
| **Moving Around**                    |                              |
| Jump to the start of the line (Home) | <kbd>SPACE</kbd><kbd>Z</kbd> |
| Jump to the end of the line (End)    | <kbd>SPACE</kbd><kbd>X</kbd> |
| Move up a line                       | <kbd>SPACE</kbd><kbd>C</kbd> |
| Move down a line                     | <kbd>SPACE</kbd><kbd>V</kbd> |
| Move left                            | <kbd>SPACE</kbd><kbd>B</kbd> |
| Move right                           | <kbd>SPACE</kbd><kbd>N</kbd> |
| **Text Manipulation**                |                              |
| Munch characters (Delete)            | <kbd>SPACE</kbd><kbd>M</kbd> |
| Insert a new line (Return)           | <kbd>SPACE</kbd><kbd>,</kbd> |

### AppTimeout
[`AppTimeout.lua`](https://github.com/sryo/Spoons/blob/main/AppTimeout.lua) - automatically close apps that have no windows.

### NoTunes
[`NoTunes.lua`](https://github.com/sryo/Spoons/blob/main/NoTunes.lua) - Block iTunes/Music and launch Spotify instead.

### WanderFocus
[`WanderFocus.lua`](https://github.com/sryo/Spoons/blob/main/WanderFocus.lua) - A focus-follows-mouse implementation.

### FAQ

**Q:** How do I use these scripts?

**A:** To use these scripts, you need to have Hammerspoon installed on your macOS system. Once you have Hammerspoon installed, clone this repository to your local machine, copy or symlink the desired script(s) to your Hammerspoon configuration directory, and add a line to your `init.lua` file to require the script(s). Reload your Hammerspoon configuration, and the scripts will start working automatically.

**Q:** Are these scripts free to use?

**A:** Yes, these scripts are free to use, modify, and distribute. If you find these scripts useful and want to support their development, consider sharing them with others, contributing improvements, or reporting any issues you encounter.
