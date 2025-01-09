-- AutoDMG: A zero-click DMG installer for Hammerspoon.

function findVolumeMountLocation(commandOutput)
    local mountLocation = commandOutput:match("/Volumes/[^%s\"<]+")
    if mountLocation then
        hs.console.printStyledtext("Successfully mounted DMG at: " .. mountLocation)
        return mountLocation
    end
    return nil
end

function sendFileToTrash(fileLocation)
    local appleScript = string.format([[
        tell application "Finder"
            move POSIX file "%s" to trash
        end tell
    ]], fileLocation)

    local trashFile = hs.task.new("/usr/bin/osascript", function(exitCode, stdOut, stdErr)
        if exitCode == 0 then
            hs.console.printStyledtext("Cleaned up file by moving to trash: " .. fileLocation)
        else
            hs.console.printStyledtext("Cleanup failed when moving to trash: " .. (stdErr or "unknown error"))
        end
    end, {"-e", appleScript})
    trashFile:start()
end

function findPKGFile(diskLocation)
    local pkgFinder = hs.task.new("/usr/bin/find", nil, {diskLocation, "-name", "*.pkg", "-maxdepth", "1"})
    local commandOutput = ""
    pkgFinder:setCallback(function(exitCode, stdOut, stdErr)
        commandOutput = stdOut
    end)
    pkgFinder:start()
    pkgFinder:waitUntilExit()

    if commandOutput then
        local pkgPath = commandOutput:match("([^\n]+%.pkg)")
        if pkgPath then
            hs.console.printStyledtext("Found PKG file: " .. pkgPath)
            return pkgPath
        end
    end
    return nil
end

function installPKG(pkgPath)
    hs.console.printStyledtext("Starting PKG installation: " .. pkgPath)
    local installer = hs.task.new("/usr/sbin/installer", function(exitCode, stdOut, stdErr)
        if exitCode == 0 then
            hs.console.printStyledtext("PKG installed successfully")
            hs.alert("PKG installation completed successfully")
        else
            hs.console.printStyledtext("PKG installation failed: " .. (stdErr or "unknown error"))
            showInstallationError("PKG installation failed")
        end
    end, {"-pkg", pkgPath, "-target", "/"})
    installer:start()
end

function installApplicationToApps(diskLocation, originalDMG)
    local appFinder = hs.task.new("/usr/bin/find", function(exitCode, stdOut, stdErr)
        if exitCode == 0 and stdOut then
            local appLocation = stdOut:match("([^\n]+%.app)")
            if appLocation then
                hs.console.printStyledtext("Located application: " .. appLocation)
                local appName = appLocation:match("([^/]+)%.app$")
                local existingAppPath = "/Applications/" .. appName .. ".app"

                local removeOldVersion = hs.task.new("/bin/rm", function(rmExitCode, rmStdOut, rmStdErr)
                    local copyNewVersion = hs.task.new("/bin/cp", function(copyExitCode, copyStdOut, copyStdErr)
                        if copyExitCode == 0 then
                            hs.console.printStyledtext("Successfully installed app to Applications: " .. appName)
                            ejectDMG(diskLocation, originalDMG)
                            hs.alert(appName .. " has been installed successfully.")
                        else
                            hs.console.printStyledtext("Application installation failed: " .. (copyStdErr or "unknown error"))
                            showInstallationError("Failed to install application")
                        end
                    end, {"-Rf", appLocation, "/Applications/"})
                    copyNewVersion:start()
                end, {"-rf", existingAppPath})
                removeOldVersion:start()
            else
                -- Check for PKG if no app found
                local pkgPath = findPKGFile(diskLocation)
                if pkgPath then
                    installPKG(pkgPath)
                    ejectDMG(diskLocation, originalDMG)
                else
                    hs.console.printStyledtext("No installable app or PKG found in " .. diskLocation)
                    showInstallationError("No installable app or PKG found")
                end
            end
        else
            hs.console.printStyledtext("Error locating application: " .. (stdErr or "unknown error"))
            showInstallationError("Could not locate application")
        end
    end, {diskLocation, "-name", "*.app", "-maxdepth", "1"})
    appFinder:start()
end

function ejectDMG(diskLocation, originalDMG)
    local ejectDisk = hs.task.new("/usr/bin/hdiutil", function(exitCode, stdOut, stdErr)
        if exitCode == 0 then
            hs.console.printStyledtext("Successfully ejected DMG")
            sendFileToTrash(originalDMG)
        else
            hs.console.printStyledtext("Failed to eject DMG: " .. (stdErr or "unknown error"))
        end
    end, {"detach", diskLocation})
    ejectDisk:start()
end

function openDMG(dmgPath)
    hs.console.printStyledtext("Opening DMG: " .. dmgPath)

    local mountDisk = hs.task.new("/usr/bin/hdiutil", function(exitCode, stdOut, stdErr)
        if exitCode == 0 then
            hs.console.printStyledtext("Successfully opened DMG")
            local mountLocation = findVolumeMountLocation(stdOut)
            if mountLocation then
                installApplicationToApps(mountLocation, dmgPath)
            else
                showInstallationError("Could not access DMG contents")
            end
        else
            local dmgName = dmgPath:match("([^/]+)$")
            hs.console.printStyledtext("Could not open DMG: " .. dmgName)
            showInstallationError(dmgPath)
        end
    end, {"attach", dmgPath, "-plist", "-noautoopen", "-noautofsck", "-noverify", "-ignorebadchecksums", "-noidme"})
    mountDisk:start()
end

function showInstallationError(errorMessage)
    hs.alert("Installation failed: " .. errorMessage)
    hs.console.printStyledtext("Installation failed: " .. errorMessage)
end

local downloadsFolder = os.getenv("HOME") .. "/Downloads"
local handledDMGs = {}

function isDMGFile(filePath)
    return string.match(string.lower(filePath), "%.dmg$") ~= nil
end

function findDMGs(folderPath)
    local dmgFiles = {}
    local iterator, directoryObj = hs.fs.dir(folderPath)

    if iterator then
        for file in iterator, directoryObj do
            if isDMGFile(file) then
                local fullPath = folderPath .. "/" .. file
                local fileInfo = hs.fs.attributes(fullPath)
                if fileInfo and fileInfo.mode == "file" then
                    dmgFiles[fullPath] = fileInfo.modification
                end
            end
        end
    end

    return dmgFiles
end

function handleNewDMGs(newDMGs)
    for dmgPath, modificationTime in pairs(newDMGs) do
        if not handledDMGs[dmgPath] then
            hs.console.printStyledtext("Found new DMG: " .. dmgPath)
            openDMG(dmgPath)
            handledDMGs[dmgPath] = modificationTime
        end
    end
end

function scanDownloadsFolder()
    local currentDMGs = findDMGs(downloadsFolder)
    handleNewDMGs(currentDMGs)
end

scanDownloadsFolder()
downloadsFolderWatcher = hs.timer.doEvery(5, function()
    scanDownloadsFolder()
end)

hs.console.printStyledtext("AutoDMG is ready: watching Downloads folder for new DMGs")
