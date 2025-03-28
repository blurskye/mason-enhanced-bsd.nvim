local _ = require "mason-core.functional"
local log = require "mason-core.log"

local M = {}

local uname = vim.loop.os_uname()

---@alias Platform
---| '"darwin_arm64"'
---| '"darwin_x64"'
---| '"linux_arm"'
---| '"linux_arm64"'
---| '"linux_arm64_gnu"'
---| '"linux_arm64_openbsd"'
---| '"linux_arm_gnu"'
---| '"linux_x64"'
---| '"linux_x64_gnu"'
---| '"linux_x64_openbsd"'
---| '"linux_x86"'
---| '"linux_x86_gnu"'
---| '"freebsd_x64"'
---| '"freebsd_arm64"'
---| '"win_arm"'
---| '"win_arm64"'
---| '"win_x64"'
---| '"win_x86"'

local arch_aliases = {
    ["x86_64"] = "x64",
    ["i386"] = "x86",
    ["i686"] = "x86", -- x86 compat
    ["aarch64"] = "arm64",
    ["aarch64_be"] = "arm64",
    ["armv8b"] = "arm64", -- arm64 compat
    ["armv8l"] = "arm64", -- arm64 compat
}

M.arch = arch_aliases[uname.machine] or uname.machine
M.sysname = uname.sysname

M.is_headless = #vim.api.nvim_list_uis() == 0

local function system(args)
    if vim.fn.executable(args[1]) == 1 then
        local ok, output = pcall(vim.fn.system, args)
        if ok and (vim.v.shell_error == 0 or vim.v.shell_error == 1) then
            return true, output
        end
        return false, output
    end
    return false, args[1] .. " is not executable"
end

-- Check if directory exists
local function dir_exists(path)
    return vim.fn.isdirectory(path) == 1
end

-- Check if linuxlator is available and working on FreeBSD
---@type fun(): {available: boolean, working: boolean, version: string?}
local get_linuxlator_status = _.lazy(function()
    if uname.sysname ~= "FreeBSD" then
        return { available = false, working = false }
    end

    local status = { 
        available = false, 
        working = false, 
        version = nil 
    }
    
    -- Check if Linux compatibility layer exists
    local linux_root_path = "/compat/linux"
    local linux_compat_exists = dir_exists(linux_root_path)
    if linux_compat_exists then
        log.debug("FreeBSD: Linux compatibility layer found at " .. linux_root_path)
        status.available = true
    else
        return status
    end
    
    -- Detect Linux compatibility version
    if dir_exists("/compat/linux/etc") then
        local os_release_path = "/compat/linux/etc/os-release"
        local cat_ok, os_release = system { "cat", os_release_path }
        
        if cat_ok then
            if os_release:match("CentOS") or os_release:match("AlmaLinux") or os_release:match("Rocky Linux") then
                if os_release:match("VERSION=\"9") or os_release:match("VERSION_ID=\"9") then
                    status.version = "el9"
                elseif os_release:match("VERSION=\"8") or os_release:match("VERSION_ID=\"8") then
                    status.version = "el8"
                elseif os_release:match("VERSION=\"7") or os_release:match("VERSION_ID=\"7") then
                    status.version = "el7"
                end
            elseif os_release:match("Ubuntu") then
                status.version = "ubuntu"
            elseif os_release:match("Debian") then
                status.version = "debian"
            else
                status.version = "unknown-linux"
            end
        end
    end
    
    -- Test if linuxlator is actually working
    local linux_binaries = {
        "/compat/linux/bin/true",
        "/compat/linux/usr/bin/true",
    }
    
    for _, binary_path in ipairs(linux_binaries) do
        local test_ok, _ = system { binary_path }
        if test_ok then
            status.working = true
            log.debug("FreeBSD: Linuxlator is working - verified with " .. binary_path)
            break
        end
    end
    
    if not status.working then
        log.debug("FreeBSD: Linuxlator is installed but not working")
    end
    
    return status
end)

---@type fun(): ('"glibc"' | '"musl"' | '"freebsd"')?
local get_libc = _.lazy(function()
    -- FreeBSD has its own libc
    if uname.sysname == "FreeBSD" then
        return "freebsd"
    end
    
    local getconf_ok, getconf_output = system { "getconf", "GNU_LIBC_VERSION" }
    if getconf_ok and getconf_output:find "glibc" then
        return "glibc"
    end
    
    local ldd_ok, ldd_output = system { "ldd", "--version" }
    if ldd_ok then
        if ldd_output:find "musl" then
            return "musl"
        elseif ldd_output:find "GLIBC" or ldd_output:find "glibc" or ldd_output:find "GNU" then
            return "glibc"
        end
    end
end)

-- Get linuxlator status once for FreeBSD
local linuxlator_status = { available = false, working = false, version = nil }
if uname.sysname == "FreeBSD" then
    linuxlator_status = get_linuxlator_status()
    if linuxlator_status.working then
        log.info("FreeBSD: Linuxlator is available and working")
    end
end

-- Most of the code that calls into these functions executes outside of the main event loop, where API/fn functions are
-- disabled. We evaluate these immediately here to avoid issues with main loop synchronization.
M.cached_features = {
    ["win"] = vim.fn.has "win32" == 1,
    ["win32"] = vim.fn.has "win32" == 1,
    ["win64"] = vim.fn.has "win64" == 1,
    ["mac"] = vim.fn.has "mac" == 1,
    ["darwin"] = vim.fn.has "mac" == 1,
    ["unix"] = vim.fn.has "unix" == 1,
    ["linux"] = vim.fn.has "linux" == 1,
    ["nvim-0.11"] = vim.fn.has "nvim-0.11" == 1,
    
    -- BSD family detection
    ["freebsd"] = uname.sysname == "FreeBSD",
    ["openbsd"] = uname.sysname == "OpenBSD",
    ["netbsd"] = uname.sysname == "NetBSD",
    ["bsd"] = uname.sysname:find("BSD") ~= nil,
    
    -- Linuxlator status for FreeBSD
    ["linuxlator_available"] = linuxlator_status.available,
    ["linuxlator_working"] = linuxlator_status.working,
    ["linuxlator_version"] = linuxlator_status.version,
}

-- When on FreeBSD with working linuxlator, enable Linux compatibility
if M.cached_features.freebsd and M.cached_features.linuxlator_working then
    -- Enable Linux compatibility for FreeBSD with linuxlator
    M.cached_features.linux = true
    log.info("FreeBSD: Enabling Linux compatibility via linuxlator")
end

---@type fun(env: string): boolean
local check_env = _.memoize(_.cond {
    {
        _.equals "musl",
        function()
            return get_libc() == "musl"
        end,
    },
    {
        _.equals "gnu",
        function()
            return get_libc() == "glibc"
        end,
    },
    { _.equals "openbsd", _.always(uname.sysname == "OpenBSD") },
    { _.equals "freebsd", _.always(uname.sysname == "FreeBSD") },
    { _.equals "netbsd", _.always(uname.sysname == "NetBSD") },
    { _.T, _.F },
})

---Table that allows for checking whether the provided targets apply to the current system.
---Each key is a target tuple consisting of at most 3 targets, in the following order:
--- 1) OS (e.g. linux, unix, darwin, win) - Mandatory
--- 2) Architecture (e.g. arm64, x64) - Optional
--- 3) Environment (e.g. gnu, musl, openbsd) - Optional
---Each target is separated by a "_" character, like so: "linux_x64_musl".
---@type table<string, boolean>
M.is = setmetatable({}, {
    __index = function(__, key)
        local os, arch, env = unpack(vim.split(key, "_", { plain = true }))
        
        -- Special case: FreeBSD with linuxlator - allow Linux targets
        if os == "linux" and M.cached_features.freebsd and M.cached_features.linuxlator_working then
            if arch and arch ~= M.arch then
                return false
            end
            -- For Linux targets on FreeBSD with linuxlator, we're compatible
            log.debug("FreeBSD: Allowing Linux target: " .. key)
            return true
        end
        
        -- Special case for FreeBSD
        if os == "freebsd" and M.cached_features.freebsd then
            if arch and arch ~= M.arch then
                return false
            end
            return true
        end
        
        -- Normal platform check
        if not M.cached_features[os] or M.cached_features[os] ~= true then
            return false
        end
        if arch and arch ~= M.arch then
            return false
        end
        if env and not check_env(env) then
            return false
        end
        
        return true
    end,
})

---@generic T
---@param platform_table table<Platform, T>
---@return T
local function get_by_platform(platform_table)
    -- FreeBSD with working linuxlator: prioritize native BSD implementations
    if M.cached_features.freebsd and M.cached_features.linuxlator_working then
        -- First try native FreeBSD implementation
        if platform_table.freebsd then
            log.trace("Using native FreeBSD implementation")
            return platform_table.freebsd
        end
        
        -- Fall back to Linux implementation via linuxlator
        if platform_table.linux then
            log.trace("Using Linux implementation via linuxlator")
            return platform_table.linux
        end
        
        -- Last resort: generic Unix implementation
        if platform_table.unix then
            return platform_table.unix
        end
    -- FreeBSD without linuxlator: only allow BSD or Unix implementations
    elseif M.cached_features.freebsd then
        if platform_table.freebsd then
            return platform_table.freebsd
        end
        
        if platform_table.unix then
            return platform_table.unix
        end
    -- macOS handling
    elseif M.cached_features.darwin then
        return platform_table.darwin or platform_table.mac or platform_table.unix
    -- Linux handling
    elseif M.cached_features.linux then
        return platform_table.linux or platform_table.unix
    -- Other Unix variants
    elseif M.cached_features.unix then
        return platform_table.unix
    -- Windows handling
    elseif M.cached_features.win then
        return platform_table.win
    end
    
    return nil
end

function M.when(cases)
    local case = get_by_platform(cases)
    if case then
        return case()
    else
        error "Current platform is not supported."
    end
end

---@type async fun(): table
M.os_distribution = _.lazy(function()
    local parse_os_release = _.compose(_.from_pairs, _.map(_.split "="), _.split "\n")
    
    ---@param entries table<string, string>
    local function parse_ubuntu(entries)
        local version_id = entries.VERSION_ID:gsub([["]], "")
        local version_parts = vim.split(version_id, "%.")
        local major = tonumber(version_parts[1])
        local minor = tonumber(version_parts[2])

        return {
            id = "ubuntu",
            version_id = version_id,
            version = { major = major, minor = minor },
        }
    end

    ---@param entries table<string, string>
    local function parse_centos(entries)
        local version_id = entries.VERSION_ID:gsub([["]], "")
        local major = tonumber(version_id)

        return {
            id = "centos",
            version_id = version_id,
            version = { major = major },
        }
    end
    
    ---@param freebsd_version string
    local function parse_freebsd_version(freebsd_version)
        -- Parse FreeBSD version (e.g., "13.2-RELEASE" or "14.0-CURRENT")
        local major, minor = freebsd_version:match("(%d+)%.(%d+)")
        if not major then
            major = freebsd_version:match("(%d+)")
            minor = "0"
        end
        
        -- Create result with version info
        local result = {
            id = "freebsd",
            version_id = major .. "." .. (minor or "0"),
            version = { major = tonumber(major), minor = tonumber(minor or "0") },
        }
        
        -- Add linuxlator information if available
        if M.cached_features.linuxlator_available then
            result.linuxlator = {
                available = true,
                working = M.cached_features.linuxlator_working,
                version = M.cached_features.linuxlator_version,
            }
        end
        
        return result
    end

    ---Parses the provided contents of an /etc/*-release file and identifies the Linux distribution.
    local parse_linux_dist = _.cond {
        { _.prop_eq("ID", "ubuntu"), parse_ubuntu },
        { _.prop_eq("ID", [["centos"]]), parse_centos },
        { _.T, _.always { id = "linux-generic", version = {} } },
    }

    return M.when {
        linux = function()
            local spawn = require "mason-core.spawn"
            return spawn
                .bash({ "-c", "cat /etc/*-release" })
                :map_catching(_.compose(parse_linux_dist, parse_os_release, _.prop "stdout"))
                :recover(function()
                    return { id = "linux-generic", version = {} }
                end)
                :get_or_throw()
        end,
        freebsd = function()
            -- Detect FreeBSD version
            local ok, output = system { "freebsd-version" }
            if ok then
                return parse_freebsd_version(vim.trim(output))
            end
            
            -- Fallback if freebsd-version isn't available
            ok, output = system { "uname", "-r" }
            if ok then
                return parse_freebsd_version(vim.trim(output))
            end
            
            return { 
                id = "freebsd", 
                version = {},
                linuxlator = M.cached_features.linuxlator_working and {
                    available = true,
                    working = true,
                    version = M.cached_features.linuxlator_version
                } or nil
            }
        end,
        darwin = function()
            return { id = "macOS", version = {} }
        end,
        win = function()
            return { id = "windows", version = {} }
        end,
    }
end)

---@type async fun(): Result<string>
M.get_homebrew_prefix = _.lazy(function()
    assert(M.is.darwin, "Can only locate Homebrew installation on Mac systems.")
    local spawn = require "mason-core.spawn"
    return spawn
        .brew({ "--prefix" })
        :map_catching(function(result)
            return vim.trim(result.stdout)
        end)
        :map_err(function()
            return "Failed to locate Homebrew installation."
        end)
end)

---@async
function M.get_node_version()
    local spawn = require "mason-core.spawn"

    return spawn.node({ "--version" }):map(function(result)
        -- Parses output such as "v16.3.1" into major, minor, patch
        local _, _, major, minor, patch = _.head(_.split("\n", result.stdout)):find "v(%d+)%.(%d+)%.(%d+)"
        return { major = tonumber(major), minor = tonumber(minor), patch = tonumber(patch) }
    end)
end

-- PATH separator
M.path_sep = M.is.win and ";" or ":"

return M
