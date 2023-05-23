These Hammerspoon scripts are designed to enhance the usability and productivity of macOS by providing various workspace management features. The scripts currently help display time near the mouse cursor, prevent the menu bar from appearing, automatically tile windows of whitelisted applications, and open URLs in different browsers.

# ⏱️↖️ TimeTrail
`TimeTrail.lua` displays the current time near the mouse pointer as you move it across the screen. The text color of the time display changes based on the battery percentage and charging status, providing you with a visual cue to stay aware of your device's battery life.

# 🚫🍔 Menunator
`Menunator.lua` declutters your workspace by stopping the menu bar from appearing at the top of the screen when you move your mouse there. It also includes commented-out code that can be used to prevent the Dock from appearing when the mouse is at the bottom edge of the screen, further reducing distractions.

# 🪄🧩 FlexTiles
`FlexTiles.lua` automatically tiles windows of whitelisted applications, creating a clean and organized workspace for increased productivity. The script efficiently handles tiling non-collapsed and collapsed windows separately and raises non-focused windows from the same application when a new application is focused, allowing for seamless multitasking.

# 🌐🔀 Linkmaster
`Linkmaster.lua` intercepts clicked URLs and presents a chooser that allows you to open the link in a specific browser (including incognito or private browsing mode) or copy the link to your clipboard.

# 🕳️🐁 MouseTunnel

`MouseTunnel.lua` allows your mouse cursor to seamlessly "tunnel" from one edge of your screen to the other, creating a limitless workspace.

## FAQ

**Q:** How do I use these scripts?

**A:** To use these scripts, you need to have Hammerspoon installed on your macOS system. Once you have Hammerspoon installed, clone this repository to your local machine, copy or symlink the desired script(s) to your Hammerspoon configuration directory, and add a line to your `init.lua` file to require the script(s). Reload your Hammerspoon configuration, and the scripts will start working automatically.

**Q:** Are these scripts free to use?

**A:** Yes, these scripts are free to use, modify, and distribute. If you find these scripts useful and want to support their development, consider sharing them with others, contributing improvements, or reporting any issues you encounter.
