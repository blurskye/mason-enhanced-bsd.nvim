local _ = require "mason-core.functional"
local log = require "mason-core.log"

--[[
  ███╗   ███╗ █████╗ ███████╗ ██████╗ ███╗   ██╗      ██████╗ ███████╗██████╗ 
  ████╗ ████║██╔══██╗██╔════╝██╔═══██╗████╗  ██║      ██╔══██╗██╔════╝██╔══██╗
  ██╔████╔██║███████║███████╗██║   ██║██╔██╗ ██║█████╗██████╔╝███████╗██║  ██║
  ██║╚██╔╝██║██╔══██║╚════██║██║   ██║██║╚██╗██║╚════╝██╔══██╗╚════██║██║  ██║
  ██║ ╚═╝ ██║██║  ██║███████║╚██████╔╝██║ ╚████║      ██████╔╝███████║██████╔╝
  ╚═╝     ╚═╝╚═╝  ╚═╝╚══════╝ ╚═════╝ ╚═╝  ╚═══╝      ╚═════╝ ╚══════╝╚═════╝ 
                                                                             
  FreeBSD Enhanced Support with Linuxlator Detection
]]

local M = {}

-----------------------------------------------------------------------
-- Platform detection fundamentals
-----------------------------------------------------------------------

-- Get system information
local uname = vim.loop.os_uname()
local machine = uname.machine

-- Architecture normalization
local arch_aliases = {
    ["x86_64"] = "x64",
    ["i386"] = "x86",
    ["i686"] = "x86", -- x86 compat
    ["aarch64"] = "arm64",
    ["aarch64_be"] = "arm64",
    ["armv8b"] = "arm64", -- arm64 compat
    ["armv8l"] = "arm64", -- arm64 compat
}

M.arch = arch_aliases[machine] or machine
M.sysname = uname.sysname

M.is_headless = #vim.api.nvim_list_uis() == 0

-----------------------------------------------------------------------
-- Helper functions
-----------------------------------------------------------------------

-- Safe system command execution
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

-- File and directory existence checks
local function dir_exists(path)
    return vim.fn.isdirectory(path) == 1
end

-----------------------------------------------------------------------
-- BSD-specific detection with debug output
-----------------------------------------------------------------------

-- Check if linuxlator is available and working on FreeBSD
---@type fun(): {available: boolean, working: boolean, version: string?}
local get_linuxlator_status = _.lazy(function()
    if uname.sysname ~= "FreeBSD" then
        return { available = false, working = false }
    end

    -- Debug banner that's easy to spot and remove
    print("\n======== MASON-BSD-DEBUG: CHECKING LINUXLATOR STATUS ========\n")
    
    local status = { 
        available = false, 
        working = false, 
        version = nil 
    }
    
    -- Check if Linux kernel module is loaded
    local linux_ko_loaded = false
    local kldstat_ok, kldstat_output = system { "kldstat" }
    if kldstat_ok then
        if kldstat_output:match("linux64%.ko") then
            linux_ko_loaded = true
            print("MASON-BSD-DEBUG: linux64.ko module detected")
        elseif kldstat_output:match("linux%.ko") then
            linux_ko_loaded = true
            print("MASON-BSD-DEBUG: linux.ko module detected")
        else
            print("MASON-BSD-DEBUG: No Linux kernel module detected")
        end
    end
    
    -- Check if Linux compatibility layer exists
    local linux_root_path = "/compat/linux"
    local linux_compat_exists = dir_exists(linux_root_path)
    if linux_compat_exists then
        print("MASON-BSD-DEBUG: Linux compatibility layer found at " .. linux_root_path)
        status.available = true
    else
        print("MASON-BSD-DEBUG: Linux compatibility layer not found at " .. linux_root_path)
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
                    print("MASON-BSD-DEBUG: Linuxlator using CentOS/RHEL 9 (el9)")
                elseif os_release:match("VERSION=\"8") or os_release:match("VERSION_ID=\"8") then
                    status.version = "el8"
                    print("MASON-BSD-DEBUG: Linuxlator using CentOS/RHEL 8 (el8)")
                elseif os_release:match("VERSION=\"7") or os_release:match("VERSION_ID=\"7") then
                    status.version = "el7"
                    print("MASON-BSD-DEBUG: Linuxlator using CentOS/RHEL 7 (el7)")
                end
            elseif os_release:match("Ubuntu") then
                status.version = "ubuntu"
                print("MASON-BSD-DEBUG: Linuxlator using Ubuntu")
            elseif os_release:match("Debian") then
                status.version = "debian"
                print("MASON-BSD-DEBUG: Linuxlator using Debian")
            else
                status.version = "unknown-linux"
                print("MASON-BSD-DEBUG: Linuxlator using unknown Linux distribution")
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
            print("MASON-BSD-DEBUG: Linuxlator is WORKING - verified by running " .. binary_path)
            break
        end
    end
    
    if not status.working then
        print("MASON-BSD-DEBUG: Linuxlator is installed but NOT WORKING")
    end
    
    print("\n======== MASON-BSD-DEBUG: LINUXLATOR STATUS SUMMARY ========")
    print("Available: " .. tostring(status.available))
    print("Working:   " .. tostring(status.working))
    print("Version:   " .. (status.version or "unknown"))
    print("==========================================================\n")
    
    return status
end)

-----------------------------------------------------------------------
-- libc detection
-----------------------------------------------------------------------

---@type fun(): ('"glibc"' | '"musl"' | '"freebsd"')?
local get_libc = _.lazy(function()
    -- FreeBSD has its own libc
    if uname.sysname == "FreeBSD" then
        return "freebsd"
    end
    
    -- Standard Linux libc detection
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
    
    return nil
end)

-----------------------------------------------------------------------
-- Platform feature caching
-----------------------------------------------------------------------

-- Get linuxlator status once for FreeBSD
local linuxlator_status = { available = false, working = false, version = nil }
if uname.sysname == "FreeBSD" then
    linuxlator_status = get_linuxlator_status()
end

-- Cache features to avoid expensive checks
M.cached_features = {
    -- OS detection
    ["win"] = vim.fn.has "win32" == 1,
    ["win32"] = vim.fn.has "win32" == 1,
    ["win64"] = vim.fn.has "win64" == 1,
    ["mac"] = vim.fn.has "mac" == 1,
    ["darwin"] = vim.fn.has "mac" == 1,
    ["unix"] = vim.fn.has "unix" == 1,
    ["linux"] = vim.fn.has "linux" == 1,
    
    -- BSD family detection
    ["freebsd"] = uname.sysname == "FreeBSD",
    ["openbsd"] = uname.sysname == "OpenBSD",
    ["netbsd"] = uname.sysname == "NetBSD",
    ["bsd"] = uname.sysname:find("BSD") ~= nil,
    
    -- Linuxlator status for FreeBSD
    ["linuxlator_available"] = linuxlator_status.available,
    ["linuxlator_working"] = linuxlator_status.working,
    ["linuxlator_version"] = linuxlator_status.version,
    
    -- Neovim version detection
    ["nvim-0.11"] = vim.fn.has "nvim-0.11" == 1,
}

-- When on FreeBSD with working linuxlator, enable Linux compatibility
if M.cached_features.freebsd and M.cached_features.linuxlator_working then
    -- Force Linux compatibility for FreeBSD with linuxlator
    M.cached_features.linux = true
    
    print("\n======== MASON-BSD-DEBUG: FreeBSD with working linuxlator detected ========")
    print("LINUX PACKAGES WILL BE SUPPORTED ON THIS FREEBSD SYSTEM")
    print("NATIVE BSD PACKAGES WILL BE PREFERRED WHEN AVAILABLE")
    print("================================================================\n")
elseif M.cached_features.freebsd then
    print("\n======== MASON-BSD-DEBUG: FreeBSD without working linuxlator detected ========")
    print("ONLY NATIVE BSD PACKAGES WILL BE SUPPORTED ON THIS SYSTEM")
    print("INSTALL LINUXLATOR FOR BROADER PACKAGE SUPPORT")
    print("===================================================================\n")
end

-----------------------------------------------------------------------
-- Platform targeting
-----------------------------------------------------------------------

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
        
        -- Special case: FreeBSD with linuxlator - ALWAYS allow Linux targets
        -- regardless of the specific error or context
        if os == "linux" and M.cached_features.freebsd and M.cached_features.linuxlator_working then
            if arch and arch ~= M.arch then
                return false
            end
            -- For Linux targets on FreeBSD with linuxlator, we're always compatible
            log.debug("MASON-BSD-DEBUG: FreeBSD with linuxlator allowing Linux target: " .. key)
            return true
        end
        
        -- Special case for FreeBSD
        if os == "freebsd" and M.cached_features.freebsd then
            if arch and arch ~= M.arch then
                return false
            end
            -- For FreeBSD targets on FreeBSD, we're always compatible
            return true
        end
        
        -- Normal platform check for all other cases
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

-- ONLY NOW that M.is exists, we can apply direct overrides
if M.cached_features.freebsd and M.cached_features.linuxlator_working then
    -- Create direct global override - this is a heavy hammer but will ensure compatibility
    print("\n======== MASON-BSD-DEBUG: APPLYING DIRECT PLATFORM OVERRIDE ========")
    
    -- Create and apply direct platform compatibility overrides
    local linux_targets = {
        "linux", "linux_x64", "linux_arm64", "linux_x86",
        "linux_x64_gnu", "linux_x64_musl", "linux_arm64_gnu", "linux_arm64_musl"
    }
    
    -- Force all Linux targets to be true directly
    for _, target in ipairs(linux_targets) do
        -- We use rawset to avoid the metatable __index function
        -- This ensures we're not causing an infinite loop
        if target:match("^linux") then
            -- Filter by architecture
            local target_arch = target:match("_(%w+)")
            if not target_arch or target_arch == M.arch then
                print("MASON-BSD-DEBUG: Forcing compatibility with " .. target)
                rawset(M.is, target, true)
            end
        end
    end
    
    print("MASON-BSD-DEBUG: FreeBSD+linuxlator direct platform patching complete")
    print("=========================================================")
end

-----------------------------------------------------------------------
-- Platform selection for commands
-----------------------------------------------------------------------

---@generic T
---@param platform_table table<Platform, T>
---@return T
local function get_by_platform(platform_table)
    -- FreeBSD with working linuxlator: prioritize native BSD implementations
    if M.cached_features.freebsd and M.cached_features.linuxlator_working then
        -- First try native FreeBSD implementation
        if platform_table.freebsd then
            log.trace("Using native FreeBSD implementation")
            print("MASON-BSD-DEBUG: Selected native FreeBSD implementation")
            return platform_table.freebsd
        end
        
        -- Fall back to Linux implementation via linuxlator
        if platform_table.linux then
            log.trace("Using Linux implementation via linuxlator")
            print("MASON-BSD-DEBUG: Selected Linux implementation via linuxlator")
            return platform_table.linux
        end
        
        -- Last resort: generic Unix implementation
        if platform_table.unix then
            print("MASON-BSD-DEBUG: Selected generic Unix implementation")
            return platform_table.unix
        end
    -- FreeBSD without linuxlator: only allow BSD or Unix implementations
    elseif M.cached_features.freebsd then
        if platform_table.freebsd then
            print("MASON-BSD-DEBUG: Selected native FreeBSD implementation")
            return platform_table.freebsd
        end
        
        if platform_table.unix then
            print("MASON-BSD-DEBUG: Selected generic Unix implementation")
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

-----------------------------------------------------------------------
-- OS distribution detection
-----------------------------------------------------------------------

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

-----------------------------------------------------------------------
-- Utility functions
-----------------------------------------------------------------------

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
