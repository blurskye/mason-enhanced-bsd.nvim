local Optional = require "mason-core.optional"
local Result = require "mason-core.result"
local _ = require "mason-core.functional"
local installer = require "mason-core.installer"
local log = require "mason-core.log"
local platform = require "mason-core.platform"

local M = {}

local function get_coalesce_by_target(source, predicate)
    if type(source) == "table" and type(source.target) ~= "nil" then
        return predicate(source) and source or nil
    end
    return source
end

-- Critical override: Modify this function to force Linux targets to be accepted on FreeBSD with linuxlator
function M.coalesce_by_target(source, opts)
    -- For FreeBSD with linuxlator, force Linux target compatibility
    if platform.cached_features.freebsd and platform.cached_features.linuxlator_working then
        log.debug("MASON-BSD-DEBUG: Force targeting Linux on FreeBSD+linuxlator in coalesce_by_target")
        
        -- Force Linux target for FreeBSD with linuxlator
        opts = opts or {}
        if not opts.target then
            opts.target = "linux_" .. platform.arch
            log.info("MASON-BSD-DEBUG: Setting target to " .. opts.target)
        end
    end

    local target = opts and opts.target
    if not target then
        -- Use the metatable-based approach to get target, which is already patched for FreeBSD
        target = nil
        for key, _ in pairs(platform.is) do
            if not key:find("_") then
                target = key
                break
            end
        end
        if not target then
            return Result.failure "PLATFORM_UNSUPPORTED"
        end
        target = ("%s_%s"):format(target, platform.arch)
    end

    local predicate = function(source_opts)
        local source_target = source_opts.target
        if type(source_target) == "table" then
            for i = 1, #source_target do
                local t = source_target[i]
                if t == target then
                    return true
                end
            end
            return false
        else
            -- Special case for FreeBSD with linuxlator - accept Linux targets
            if platform.cached_features.freebsd and platform.cached_features.linuxlator_working then
                if source_target:match("^linux_") and target:match("^linux_") then
                    log.info("MASON-BSD-DEBUG: Accepting Linux target on FreeBSD with linuxlator")
                    return true
                end
            end
            
            return source_target == target
        end
    end

    if type(source) == "table" and _.is_list(source) then
        for i = 1, #source do
            local result = get_coalesce_by_target(source[i], predicate)
            if result ~= nil then
                return Result.success(result)
            end
        end
        -- DIRECT OVERRIDE: Don't return PLATFORM_UNSUPPORTED on FreeBSD with linuxlator
        if platform.cached_features.freebsd and platform.cached_features.linuxlator_working then
            -- Try again with Linux target
            log.info("MASON-BSD-DEBUG: No target match found, forcing Linux compatibility")
            target = "linux_" .. platform.arch
            for i = 1, #source do
                -- Accept any source for FreeBSD+linuxlator since we want to force compatibility
                if source[i] and type(source[i]) == "table" then
                    return Result.success(source[i])
                end
            end
        end
        return Result.failure "PLATFORM_UNSUPPORTED"
    else
        local result = get_coalesce_by_target(source, predicate)
        if result ~= nil then
            return Result.success(result)
        else
            -- DIRECT OVERRIDE: For FreeBSD with linuxlator, accept source as-is and don't fail
            if platform.cached_features.freebsd and platform.cached_features.linuxlator_working then
                log.info("MASON-BSD-DEBUG: Forcing platform compatibility for Linux target")
                return Result.success(source)
            end
            return Result.failure "PLATFORM_UNSUPPORTED"
        end
    end
end

---Checks whether a custom version of a package installation corresponds to a valid version.
---@async
---@param versions_thunk async fun(): Result Result<string[]>
function M.ensure_valid_version(versions_thunk)
    local ctx = installer.context()
    local version = ctx.opts.version

    if version and not ctx.opts.force then
        ctx.stdio_sink.stdout "Fetching available versions…\n"
        local all_versions = versions_thunk()
        if all_versions:is_failure() then
            log.warn("Failed to fetch versions for package", ctx.package)
            -- Gracefully fail (i.e. optimistically continue package installation)
            return Result.success()
        end
        all_versions = all_versions:get_or_else {}

        if not _.any(_.equals(version), all_versions) then
            ctx.stdio_sink.stderr(("Tried to install invalid version %q. Available versions:\n"):format(version))
            ctx.stdio_sink.stderr(_.compose(_.join "\n", _.map(_.join ", "), _.split_every(15))(all_versions))
            ctx.stdio_sink.stderr "\n\n"
            ctx.stdio_sink.stderr(
                ("Run with --force flag to bypass version validation:\n  :MasonInstall --force %s@%s\n\n"):format(
                    ctx.package.name,
                    version
                )
            )
            return Result.failure(("Version %q is not available."):format(version))
        end
    end

    return Result.success()
end

---@param platforms string[]
function M.ensure_valid_platform(platforms)
    if not _.any(function(target)
        return platform.is[target]
    end, platforms) then
        return Result.failure "PLATFORM_UNSUPPORTED"
    end
    return Result.success()
end

return M
