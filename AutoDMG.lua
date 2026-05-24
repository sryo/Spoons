-- AutoDMG: A zero-click installer for Hammerspoon
-- Supports: DMG, ISO, IMG, CDR, SPARSEIMAGE, PKG, MPKG

local downloadsFolder = os.getenv("HOME") .. "/Downloads"
local handledFiles = {}
local fileStates = {}
local activeTasks = {}

local supportedExtensions = {
    ["dmg"] = "image",
    ["iso"] = "image",
    ["cdr"] = "image",
    ["img"] = "image",
    ["sparseimage"] = "image",
    ["sparsebundle"] = "image",

    ["pkg"] = "package",
    ["mpkg"] = "package"
}

local function getFileType(filename)
    local ext = filename:match("%.([^%.]+)$")
    if ext then
        return supportedExtensions[ext:lower()]
    end
    return nil
end

local function runTask(cmd, args, inputData, callback)
    local task = hs.task.new(cmd, function(exitCode, stdOut, stdErr)
        if callback then callback(exitCode, stdOut, stdErr) end
    end, args)

    if inputData then
        task:setInput(inputData)
    end

    table.insert(activeTasks, task)
    task:start()
end

local function runAdminScript(shellCmd)
    local script = string.format('do shell script "%s" with administrator privileges', shellCmd)
    return hs.osascript.applescript(script)
end

local function cleanup(mountPoint, sourceFile)
    hs.console.printStyledtext("Cleaning up...")

    local function deleteSource()
        local success = os.remove(sourceFile)
        local fileName = sourceFile:match("[^/]+$")
        if success then
            hs.console.printStyledtext("Done. Deleted " .. fileName)
            hs.alert("AutoDMG: Cleaned up " .. fileName)
        else
            hs.execute("rm -f '" .. sourceFile .. "'")
            hs.console.printStyledtext("Done. Force deleted " .. fileName)
        end
    end

    if mountPoint then
        runTask("/usr/bin/hdiutil", { "detach", mountPoint, "-force" }, nil, function(exitCode)
            if exitCode == 0 then
                deleteSource()
            else
                hs.console.printStyledtext("Failed to detach volume. File kept for safety.")
            end
        end)
    else
        deleteSource()
    end
end

local function installPKG(pkgPath, mountPoint, sourceFile)
    hs.console.printStyledtext("Installing PKG: " .. pkgPath)
    hs.console.printStyledtext("Prompting for Admin Password...")

    local safePkgPath = pkgPath:gsub('"', '\\"')
    local installCmd = string.format("/usr/sbin/installer -pkg \\\"%s\\\" -target /", safePkgPath)

    local success, _ = runAdminScript(installCmd)
    if success then
        hs.alert("PKG Installed Successfully")
        cleanup(mountPoint, sourceFile)
    else
        hs.alert("PKG Installation Cancelled")
    end
end

function installContents(mountPoint, sourceFile)
    hs.console.printStyledtext("Scanning volume contents...")

    local outputApp = hs.execute("find '" .. mountPoint .. "' -name '*.app' -maxdepth 1")
    local appLocation = (outputApp and outputApp:gsub("^%s*(.-)%s*$", "%1")) or ""
    appLocation = appLocation:match("[^\n]+")

    if appLocation and appLocation ~= "" then
        local appName = appLocation:match("([^/]+)%.app$")
        local targetPath = "/Applications/" .. appName .. ".app"
        hs.console.printStyledtext("Found App: " .. appName)

        local appObj = hs.application.get(appName)
        if appObj and appObj.kill9 and appObj:isRunning() then
            hs.console.printStyledtext("Force quitting running instance of " .. appName .. "...")
            appObj:kill9()
            hs.timer.usleep(500000)
        end

        local _, _, _, rmCode = hs.execute("rm -rf '" .. targetPath .. "'")

        if rmCode == 0 then
            runTask("/bin/cp", { "-Rf", appLocation, "/Applications/" }, nil, function(exitCode, stdOut, stdErr)
                if exitCode == 0 then
                    hs.execute("xattr -dr com.apple.quarantine '" .. targetPath .. "'")
                    hs.alert(appName .. " Installed Successfully")
                    cleanup(mountPoint, sourceFile)
                else
                    hs.alert("Installation Failed: " .. (stdErr or "Unknown Error"))
                end
            end)
        else
            hs.console.printStyledtext("Standard install failed. Escalating to Admin...")
            local safeTarget = targetPath:gsub('"', '\\"')
            local safeSource = appLocation:gsub('"', '\\"')
            local fullCmd = string.format(
                'rm -rf \\"%s\\" && cp -Rf \\"%s\\" /Applications/ && xattr -dr com.apple.quarantine \\"%s\\"',
                safeTarget, safeSource, safeTarget
            )

            local success, _ = runAdminScript(fullCmd)
            if success then
                hs.alert(appName .. " Installed (Admin)")
                cleanup(mountPoint, sourceFile)
            else
                hs.alert("Admin Install Cancelled")
            end
        end
    else
        local outputPkg = hs.execute("find '" .. mountPoint .. "' -name '*.pkg' -maxdepth 1")
        local pkgLocation = (outputPkg and outputPkg:gsub("^%s*(.-)%s*$", "%1")) or ""
        pkgLocation = pkgLocation:match("[^\n]+")

        if pkgLocation and pkgLocation ~= "" then
            installPKG(pkgLocation, mountPoint, sourceFile)
        else
            hs.alert("Empty or unsupported Image")
        end
    end
end

function openDiskImage(imagePath)
    hs.console.printStyledtext("Processing Image: " .. imagePath)

    local args = {
        "attach", imagePath, "-plist", "-nobrowse", "-noautoopen",
        "-noverify", "-ignorebadchecksums", "-noidme"
    }

    runTask("/usr/bin/hdiutil", args, "Y\n", function(exitCode, stdOut)
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
            end
        else
            hs.alert("AutoDMG: Failed to mount")
        end
    end)
end

function processFile(fullPath)
    local type = getFileType(fullPath)

    if type == "image" then
        openDiskImage(fullPath)
    elseif type == "package" then
        installPKG(fullPath, nil, fullPath)
    end
end

function checkFileStability(filePath)
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

function scanDownloadsFolder()
    for file in hs.fs.dir(downloadsFolder) do
        local fullPath = downloadsFolder .. "/" .. file
        local fType = getFileType(file)

        if fType and not handledFiles[fullPath] then
            if not (fullPath:match("%.part$") or fullPath:match("%.download$") or fullPath:match("%.crdownload$")) then
                if checkFileStability(fullPath) then
                    handledFiles[fullPath] = os.time()
                    fileStates[fullPath] = nil
                    processFile(fullPath)
                end
            end
        end
    end
end

downloadsFolderWatcher = hs.timer.doEvery(3, scanDownloadsFolder)
hs.console.printStyledtext("AutoDMG (Images + PKGs) Ready")
