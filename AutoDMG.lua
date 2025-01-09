-- AutoDMG: A zero-click DMG installer for Hammerspoon.

function parseOutputForMountPath(output)
    local mountPoint = output:match("/Volumes/[^%s\"<]+")
    if mountPoint then
        hs.console.printStyledtext("Found mount point: " .. mountPoint)
        return mountPoint
    end
    return nil
end

function copyAppToApplications(mountPoint, originalDMGPath)
    local findTask = hs.task.new("/usr/bin/find", function(exitCode, stdOut, stdErr)
        if exitCode == 0 and stdOut then
            local appPath = stdOut:match("([^\n]+%.app)")
            if appPath then
                hs.console.printStyledtext("Found app: " .. appPath)
                local appName = appPath:match("([^/]+)%.app$")
                local existingApp = "/Applications/" .. appName .. ".app"

                local removeExisting = hs.task.new("/bin/rm", function(rmExitCode, rmStdOut, rmStdErr)
                    local copyTask = hs.task.new("/bin/cp", function(copyExitCode, copyStdOut, copyStdErr)
                        if copyExitCode == 0 then
                            hs.console.printStyledtext("App copied successfully to /Applications: " .. appName)
                            unmountDiskImage(mountPoint, originalDMGPath)
                            hs.alert(appName .. " installed successfully.")
                        else
                            hs.console.printStyledtext("Failed to copy app: " .. (copyStdErr or "unknown error"))
                            handleFailure("Failed to copy app")
                        end
                    end, {"-Rf", appPath, "/Applications/"})
                    copyTask:start()
                end, {"-rf", existingApp})
                removeExisting:start()
            else
                hs.console.printStyledtext("No .app file found in " .. mountPoint)
                handleFailure("No .app file found")
            end
        else
            hs.console.printStyledtext("Error finding app: " .. (stdErr or "unknown error"))
            handleFailure("Error finding app")
        end
    end, {mountPoint, "-name", "*.app", "-maxdepth", "1"})
    findTask:start()
end

function unmountDiskImage(mountPoint, originalDMGPath)
    local task = hs.task.new("/usr/bin/hdiutil", function(exitCode, stdOut, stdErr)
        if exitCode == 0 then
            hs.console.printStyledtext("Disk image unmounted successfully")
            local removeTask = hs.task.new("/bin/rm", function(rmExitCode, rmStdOut, rmStdErr)
                if rmExitCode == 0 then
                    hs.console.printStyledtext("DMG file deleted successfully: " .. originalDMGPath)
                else
                    hs.console.printStyledtext("Failed to delete DMG file: " .. (rmStdErr or "unknown error"))
                    hs.alert("Installation completed but couldn't delete DMG.")
                end
            end, {originalDMGPath})
            removeTask:start()
        else
            hs.console.printStyledtext("Failed to unmount disk image: " .. (stdErr or "unknown error"))
        end
    end, {"detach", mountPoint})
    task:start()
end

function mountDiskImage(diskImagePath)
    hs.console.printStyledtext("Attempting to mount disk image: " .. diskImagePath)

    local task = hs.task.new("/usr/bin/hdiutil", function(exitCode, stdOut, stdErr)
        if exitCode == 0 then
            hs.console.printStyledtext("Disk image mounted successfully")
            local mountPoint = parseOutputForMountPath(stdOut)
            if mountPoint then
                copyAppToApplications(mountPoint, diskImagePath)
            else
                handleFailure("Could not find mount point")
            end
        else
            local diskImageName = diskImagePath:match("([^/]+)$")  -- Extracts the name of the disk image
            hs.console.printStyledtext("Failed to mount disk image: " .. diskImageName)
            handleFailure(diskImagePath)
        end
    end, {"attach", diskImagePath, "-plist", "-noautoopen", "-noautofsck", "-noverify", "-ignorebadchecksums", "-noidme"})
    task:start()
end

function handleFailure(errorMsg)
    hs.alert("Installation failed: " .. errorMsg)
    hs.console.printStyledtext("Installation failed: " .. errorMsg)
end

local downloadPath = os.getenv("HOME") .. "/Downloads"
local processedDMGs = {}

function isDMGFile(filePath)
    return string.match(string.lower(filePath), "%.dmg$") ~= nil
end

function getDMGFiles(dirPath)
    local dmgFiles = {}
    local iter, dir_obj = hs.fs.dir(dirPath)

    if iter then
        for file in iter, dir_obj do
            if isDMGFile(file) then
                local fullPath = dirPath .. "/" .. file
                local attrs = hs.fs.attributes(fullPath)
                if attrs and attrs.mode == "file" then
                    dmgFiles[fullPath] = attrs.modification
                end
            end
        end
    end

    return dmgFiles
end

function processNewDMGs(newDMGs)
    for dmgPath, modTime in pairs(newDMGs) do
        if not processedDMGs[dmgPath] then
            hs.console.printStyledtext("New DMG found: " .. dmgPath)
            mountDiskImage(dmgPath)
            processedDMGs[dmgPath] = modTime
        end
    end
end

function checkDownloadsFolder()
    local currentDMGs = getDMGFiles(downloadPath)
    processNewDMGs(currentDMGs)
end

checkDownloadsFolder()
checkDownloadsFolderTimer = hs.timer.doEvery(5, function()
    checkDownloadsFolder()
end)

hs.console.printStyledtext("AutoDMG initialized: watching Downloads folder and ready for manual operations")
