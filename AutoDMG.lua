-- AutoDMG: A zero-click DMG installer for Hammerspoon

local downloadsFolder = os.getenv("HOME") .. "/Downloads"
local handledDMGs = {}
local fileStates = {}
local activeTasks = {}

local function runTask(cmd, args, callback)
    local task = hs.task.new(cmd, function(exitCode, stdOut, stdErr)
        if callback then callback(exitCode, stdOut, stdErr) end
    end, args)
    table.insert(activeTasks, task)
    task:start()
end

local function cleanup(diskLocation, originalDMG)
    hs.console.printStyledtext("Cleaning up...")
    runTask("/usr/bin/hdiutil", { "detach", diskLocation, "-force" }, function(exitCode)
        if exitCode == 0 then
            local success = os.remove(originalDMG)
            if success then
                hs.console.printStyledtext("Done. Deleted " .. originalDMG)
            else
                hs.execute("rm -f '" .. originalDMG .. "'")
                hs.console.printStyledtext("Done. Force deleted " .. originalDMG)
            end
        else
            hs.console.printStyledtext("Failed to detach DMG. File kept for safety.")
        end
    end)
end

local function runAdminScript(shellCmd)
    local script = string.format('do shell script "%s" with administrator privileges', shellCmd)
    return hs.osascript.applescript(script)
end

local function installPKG(pkgPath, diskLocation, originalDMG)
    hs.console.printStyledtext("Found PKG. Prompting for Admin Password...")
    local safePkgPath = pkgPath:gsub('"', '\\"')
    local installCmd = string.format("/usr/sbin/installer -pkg \\\"%s\\\" -target /", safePkgPath)

    local success, _ = runAdminScript(installCmd)
    if success then
        hs.alert("PKG Installed Successfully")
        cleanup(diskLocation, originalDMG)
    else
        hs.alert("PKG Installation Cancelled")
    end
end

function installContents(diskLocation, originalDMG)
    hs.console.printStyledtext("Scanning DMG contents...")

    -- Find .APP
    local outputApp = hs.execute("find '" .. diskLocation .. "' -name '*.app' -maxdepth 1")
    local appLocation = (outputApp and outputApp:gsub("^%s*(.-)%s*$", "%1")) or ""
    appLocation = appLocation:match("[^\n]+")

    if appLocation and appLocation ~= "" then
        -- .APP Found
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
            runTask("/bin/cp", { "-Rf", appLocation, "/Applications/" }, function(exitCode, stdOut, stdErr)
                if exitCode == 0 then
                    hs.execute("xattr -dr com.apple.quarantine '" .. targetPath .. "'")
                    hs.alert(appName .. " Installed Successfully")
                    cleanup(diskLocation, originalDMG)
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
                cleanup(diskLocation, originalDMG)
            else
                hs.alert("Admin Install Cancelled")
            end
        end
    else
        local outputPkg = hs.execute("find '" .. diskLocation .. "' -name '*.pkg' -maxdepth 1")
        local pkgLocation = (outputPkg and outputPkg:gsub("^%s*(.-)%s*$", "%1")) or ""
        pkgLocation = pkgLocation:match("[^\n]+")

        if pkgLocation and pkgLocation ~= "" then
            installPKG(pkgLocation, diskLocation, originalDMG)
        else
            hs.alert("Empty or unsupported DMG")
        end
    end
end

function openDMG(dmgPath)
    hs.console.printStyledtext("Processing: " .. dmgPath)
    runTask("/usr/bin/hdiutil",
        { "attach", dmgPath, "-plist", "-nobrowse", "-noautoopen", "-noverify", "-ignorebadchecksums" },
        function(exitCode, stdOut)
            if exitCode == 0 then
                local mountPoint = stdOut:match("<key>mount%-point</key>%s*<string>([^<]+)</string>")
                if mountPoint then
                    installContents(mountPoint, dmgPath)
                else
                    hs.alert("Failed to mount DMG")
                end
            else
                hs.alert("Failed to open DMG")
            end
        end)
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
        if fullPath:match("%.dmg$") and not handledDMGs[fullPath] then
            if not (fullPath:match("%.part$") or fullPath:match("%.download$")) then
                if checkFileStability(fullPath) then
                    handledDMGs[fullPath] = os.time()
                    fileStates[fullPath] = nil
                    openDMG(fullPath)
                end
            end
        end
    end
end

downloadsFolderWatcher = hs.timer.doEvery(5, scanDownloadsFolder)
hs.console.printStyledtext("AutoDMG Ready")
