-- AutoDMG: A zero-click installer for Hammerspoon
-- Supports: DMG, ISO, IMG, CDR, SPARSEIMAGE, PKG, MPKG
-- Bundle types (sparsebundle) aren't supported: size-stability check
-- doesn't work on package directories.

local downloadsFolder = os.getenv("HOME") .. "/Downloads"
local handledFiles = {}
local fileStates = {}
local activeTasks = {}
local debounceTimer
local downloadsFolderWatcher

local supportedExtensions = {
    ["dmg"] = "image",
    ["iso"] = "image",
    ["cdr"] = "image",
    ["img"] = "image",
    ["sparseimage"] = "image",

    ["pkg"] = "package",
    ["mpkg"] = "package"
}

local function shQuote(s)
    return "'" .. s:gsub("'", "'\\''") .. "'"
end

local function getFileType(filename)
    local ext = filename:match("%.([^%.]+)$")
    if ext then
        return supportedExtensions[ext:lower()]
    end
    return nil
end

local function runTask(cmd, args, inputData, callback)
    local task
    task = hs.task.new(cmd, function(exitCode, stdOut, stdErr)
        activeTasks[task] = nil
        if callback then callback(exitCode, stdOut, stdErr) end
    end, args)

    if inputData then
        task:setInput(inputData)
    end

    activeTasks[task] = true
    task:start()
end

local function runAdminScript(shellCmd)
    local script = 'do shell script "' .. shellCmd:gsub('"', '\\"') .. '" with administrator privileges'
    return hs.osascript.applescript(script)
end

local installContents, openDiskImage, processFile, checkFileStability, scanDownloadsFolder

local function cleanup(mountPoint, sourceFile)
    hs.console.printStyledtext("Cleaning up...")

    local function deleteSource()
        local success = os.remove(sourceFile)
        local fileName = sourceFile:match("[^/]+$")
        if success then
            hs.console.printStyledtext("Done. Deleted " .. fileName)
            hs.alert("AutoDMG: Cleaned up " .. fileName)
        else
            hs.execute("rm -f " .. shQuote(sourceFile))
            hs.console.printStyledtext("Done. Force deleted " .. fileName)
        end
    end

    if mountPoint then
        runTask("/usr/bin/hdiutil", { "detach", mountPoint, "-force" }, nil, function(exitCode, _, stdErr)
            if exitCode == 0 then
                deleteSource()
            else
                handledFiles[sourceFile] = nil
                hs.console.printStyledtext("[AutoDMG] detach failed: " .. (stdErr or ""))
                hs.alert("AutoDMG: Couldn't unmount; will retry")
            end
        end)
    else
        deleteSource()
    end
end

local function installPKG(pkgPath, mountPoint, sourceFile)
    hs.console.printStyledtext("Installing PKG: " .. pkgPath)
    hs.console.printStyledtext("Prompting for Admin Password...")

    local installCmd = "/usr/sbin/installer -pkg " .. shQuote(pkgPath) .. " -target /"

    local success, _ = runAdminScript(installCmd)
    if success then
        hs.alert("PKG Installed Successfully")
        cleanup(mountPoint, sourceFile)
    else
        hs.alert("PKG Installation Cancelled")
    end
end

local function gracefulQuit(appName, onDone)
    local app = hs.application.get(appName)
    if not (app and app:isRunning()) then return onDone() end
    app:kill()
    local deadline = hs.timer.secondsSinceEpoch() + 3
    local poll
    poll = hs.timer.doEvery(0.2, function()
        local still = hs.application.get(appName)
        if not (still and still:isRunning()) then
            poll:stop(); onDone(); return
        end
        if hs.timer.secondsSinceEpoch() > deadline then
            poll:stop()
            still:kill9()
            hs.timer.doAfter(0.3, onDone)
        end
    end)
end

local function promptAndQuit(appName, onProceed)
    local choice = hs.dialog.blockAlert(
        "AutoDMG: Install update for " .. appName .. "?",
        appName .. " is running. Quit it to replace with the new version?",
        "Quit & Install", "Cancel")
    if choice == "Quit & Install" then
        gracefulQuit(appName, function() onProceed(true) end)
    else
        onProceed(false)
    end
end

local function findAllApps(mountPoint)
    local out = hs.execute("find " .. shQuote(mountPoint) .. " -name '*.app' -maxdepth 1")
    local apps = {}
    if out then
        for line in out:gmatch("[^\n]+") do
            line = line:gsub("^%s*(.-)%s*$", "%1")
            if line ~= "" then table.insert(apps, line) end
        end
    end
    return apps
end

local function copyAppToApplications(appLocation, mountPoint, sourceFile)
    local appName = appLocation:match("([^/]+)%.app$")
    local targetPath = "/Applications/" .. appName .. ".app"

    local function doInstall()
        local _, _, _, rmCode = hs.execute("rm -rf " .. shQuote(targetPath))
        if rmCode == 0 then
            runTask("/bin/cp", { "-Rf", appLocation, "/Applications/" }, nil, function(exitCode, _, stdErr)
                if exitCode == 0 then
                    hs.execute("xattr -dr com.apple.quarantine " .. shQuote(targetPath))
                    hs.alert(appName .. " Installed Successfully")
                    cleanup(mountPoint, sourceFile)
                else
                    hs.alert("Installation Failed: " .. (stdErr or "Unknown Error"))
                    hs.console.printStyledtext("[AutoDMG] copy failed: " .. (stdErr or ""))
                end
            end)
        else
            hs.console.printStyledtext("Standard install failed. Escalating to Admin...")
            local fullCmd = string.format(
                "rm -rf %s && cp -Rf %s /Applications/ && xattr -dr com.apple.quarantine %s",
                shQuote(targetPath), shQuote(appLocation), shQuote(targetPath)
            )
            local success, _ = runAdminScript(fullCmd)
            if success then
                hs.alert(appName .. " Installed (Admin)")
                cleanup(mountPoint, sourceFile)
            else
                hs.alert("Admin Install Cancelled")
            end
        end
    end

    local appObj = hs.application.get(appName)
    if appObj and appObj:isRunning() then
        hs.console.printStyledtext("Found running instance of " .. appName .. "; prompting user")
        promptAndQuit(appName, function(ok)
            if ok then doInstall()
            else hs.alert("AutoDMG: Install cancelled for " .. appName) end
        end)
    else
        doInstall()
    end
end

local function pickAppAndInstall(apps, mountPoint, sourceFile)
    if #apps == 1 then
        local appLocation = apps[1]
        local appName = appLocation:match("([^/]+)%.app$")
        hs.console.printStyledtext("Found App: " .. appName)
        copyAppToApplications(appLocation, mountPoint, sourceFile)
        return
    end

    local choices = {}
    for _, p in ipairs(apps) do
        local n = p:match("([^/]+)%.app$")
        table.insert(choices, { text = n, subText = p, location = p })
    end
    local chooser = hs.chooser.new(function(choice)
        if choice then
            hs.console.printStyledtext("User chose: " .. choice.text)
            copyAppToApplications(choice.location, mountPoint, sourceFile)
        else
            hs.alert("AutoDMG: No app chosen; unmounting")
            runTask("/usr/bin/hdiutil", { "detach", mountPoint, "-force" }, nil, function() end)
        end
    end)
    chooser:choices(choices)
    chooser:placeholderText("Multiple apps in image — choose one to install")
    chooser:show()
end

installContents = function(mountPoint, sourceFile)
    hs.console.printStyledtext("Scanning volume contents...")
    local apps = findAllApps(mountPoint)
    if #apps > 0 then
        pickAppAndInstall(apps, mountPoint, sourceFile)
        return
    end

    local outputPkg = hs.execute("find " .. shQuote(mountPoint) .. " -name '*.pkg' -maxdepth 1")
    local pkgLocation = (outputPkg and outputPkg:gsub("^%s*(.-)%s*$", "%1")) or ""
    pkgLocation = pkgLocation:match("[^\n]+")

    if pkgLocation and pkgLocation ~= "" then
        installPKG(pkgLocation, mountPoint, sourceFile)
    else
        hs.alert("Empty or unsupported Image")
    end
end

openDiskImage = function(imagePath)
    hs.console.printStyledtext("Processing Image: " .. imagePath)

    local args = {
        "attach", imagePath, "-plist", "-nobrowse", "-noautoopen",
        "-noverify", "-ignorebadchecksums", "-noidme"
    }

    runTask("/usr/bin/hdiutil", args, nil, function(exitCode, stdOut, stdErr)
        if exitCode == 0 then
            local plistData = hs.plist.readString(stdOut)
            local mountPoint = nil

            if plistData and plistData["system-entities"] then
                for _, entity in ipairs(plistData["system-entities"]) do
                    if entity["mount-point"] then
                        mountPoint = entity["mount-point"]
                        break
                    end
                end
            end

            if mountPoint then
                hs.console.printStyledtext("Mounted at: " .. mountPoint)
                installContents(mountPoint, imagePath)
            else
                hs.alert("AutoDMG: Mount failed (No path)")
                handledFiles[imagePath] = nil
            end
        else
            if stdErr and (stdErr:match("authentication") or stdErr:match("password")) then
                hs.alert("AutoDMG: Encrypted image — mount manually")
                handledFiles[imagePath] = nil
            else
                hs.alert("AutoDMG: Failed to mount")
                hs.console.printStyledtext("[AutoDMG] mount failed: " .. (stdErr or ""))
            end
        end
    end)
end

processFile = function(fullPath)
    local type = getFileType(fullPath)

    if type == "image" then
        openDiskImage(fullPath)
    elseif type == "package" then
        installPKG(fullPath, nil, fullPath)
    end
end

checkFileStability = function(filePath)
    local attrs = hs.fs.attributes(filePath)
    if not attrs then return false end
    local currentSize = attrs.size

    if not fileStates[filePath] then
        fileStates[filePath] = { size = currentSize, checks = 0 }
        return false
    end

    if fileStates[filePath].size == currentSize then
        fileStates[filePath].checks = fileStates[filePath].checks + 1
        if fileStates[filePath].checks >= 3 then return true end
    else
        fileStates[filePath].size = currentSize
        fileStates[filePath].checks = 0
    end
    return false
end

scanDownloadsFolder = function()
    local pending = false
    for file in hs.fs.dir(downloadsFolder) do
        local fullPath = downloadsFolder .. "/" .. file
        local fType = getFileType(file)

        if fType then
            local stamp = handledFiles[fullPath]
            if stamp and (os.time() - stamp) > 86400 then
                handledFiles[fullPath] = nil
            end
            if not handledFiles[fullPath] then
                if not (fullPath:match("%.part$") or fullPath:match("%.download$") or fullPath:match("%.crdownload$")) then
                    if checkFileStability(fullPath) then
                        handledFiles[fullPath] = os.time()
                        fileStates[fullPath] = nil
                        processFile(fullPath)
                    else
                        pending = true
                    end
                end
            end
        end
    end
    if pending then
        if debounceTimer then debounceTimer:stop() end
        debounceTimer = hs.timer.doAfter(3, scanDownloadsFolder)
    end
end

local function onFsEvent()
    if debounceTimer then debounceTimer:stop() end
    debounceTimer = hs.timer.doAfter(0.5, scanDownloadsFolder)
end

downloadsFolderWatcher = hs.pathwatcher.new(downloadsFolder, onFsEvent):start()
scanDownloadsFolder()
hs.console.printStyledtext("AutoDMG (Images + PKGs) Ready")

return { handledFiles = handledFiles, fileStates = fileStates }
