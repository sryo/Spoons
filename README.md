These Hammerspoon scripts are designed to enhance the usability and productivity of macOS by providing various workspace management features. The scripts currently help display time near the mouse cursor, prevent the menu bar from appearing, automatically tile windows of whitelisted applications, and open URLs in different browsers.

### ⚡🅰️ ForceKeys
`Forcekeys.lua` maps a keyboard onto the Magic Trackpad, making text input a touch away.

#### Features
- Supports standard keys, special keys, and key combinations
- Customizable key layouts
- Previews for keys and key combinations
- Printable template
  
#### How to Use
- Define your desired key layouts in the layouts variable.
- Run the script, and your Magic Trackpad will now also function as a keyboard.

### 🖥️🐙 FrameMaster
`FrameMaster.lua` - Take control of your Mac's 'hot corners', menu bar, and dock. Master your screen frame and manage your workflow with minimal distractions.

#### Features
- Hot corners: Define custom actions for each corner of the screen. Actions are defined in the hotCorners table and can be updated as needed.
- Keep the dock and menubar hidden.
- Reopen last app: When an app is killed, a modal will be shown to allow you to easily reopen it.

#### How to Use
- Start the script and try moving your mouse to the corners of the screen to see the actions and tooltips.
- Use the Shift key to change the action performed in a corner.

### 🌐🔀 HyperlinkHijacker
`HyperlinkHijacker.lua` - It's your link, and you decide where it goes. 

#### How to Use
- When you click a link, a list will pop up with your defined browsers/profiles. If no choice is made before the countdown ends, the first browser in the list will automatically open the link. To bypass the chooser and directly open the link in the first browser, press the Shift key while clicking the link.
- A handy feature is the ability to copy a link directly to your clipboard by choosing the "Copy to Clipboard" option in the chooser.
- Passthroughs are rules that allow specific links to bypass the browser and open directly in their respective applications. You can define them in the passthroughs variable. For example:
```lua
local passthroughs = {
    spotify = { url = "https://open.spotify.com/", appName = "Spotify", bundleID = "com.spotify.client" },
    -- Add more passthroughs here if needed
}
```
- Setting up Browsers: Specify your preferred browsers in the browsers variable along with any necessary arguments. For example:
```lua
local browsers = {
    { name = "Arc", appName = "Arc", bundleID = "company.thebrowser.Browser", args = {""} },
    { name = "Google Chrome", appName = "Google Chrome", bundleID = "com.google.Chrome", args = {""} },
    -- Add more options here if needed
}
```

### ⏱️↖️ TimeTrail
`TimeTrail.lua` gives you a moving clock right next to your mouse, because who needs a stationary clock?

### 🪄🌇 WindowScape
`WindowScape.lua` is the ultimate tool in window organization, transforming chaos into a neat urban landscape.

#### Features
- Automatically tiles windows of whitelisted applications (or set it to avoid tiling the apps listed there).

#### How to Use
Use the `cmd + <` hotkey to add/remove the application of the currently focused window to/from the whitelist.
After whitelisting an application, its windows will be automatically tiled by the script.

### FAQ

**Q:** How do I use these scripts?

**A:** To use these scripts, you need to have Hammerspoon installed on your macOS system. Once you have Hammerspoon installed, clone this repository to your local machine, copy or symlink the desired script(s) to your Hammerspoon configuration directory, and add a line to your `init.lua` file to require the script(s). Reload your Hammerspoon configuration, and the scripts will start working automatically.

**Q:** Are these scripts free to use?

**A:** Yes, these scripts are free to use, modify, and distribute. If you find these scripts useful and want to support their development, consider sharing them with others, contributing improvements, or reporting any issues you encounter.
