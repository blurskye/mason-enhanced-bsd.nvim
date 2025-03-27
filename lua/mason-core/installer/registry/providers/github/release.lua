-- This file contains fixes for the GitHub Release provider to properly support FreeBSD with linuxlator

local Result = require "mason-core.result"
local _ = require "mason-core.functional"
local common = require "mason-core.installer.managers.common"
local expr = require "mason-core.installer.registry.expr"
local providers = require "mason-core.providers"
local settings = require "mason.settings"
local util = require "mason-core.installer.registry.util"
local platform = require "mason-core.platform"
local log = require "mason-core.log"

---@class GitHubReleaseSource : RegistryPackageSource
---@field asset FileDownloadSpec | FileDownloadSpec[]

local M = {}

-- Add a helper function to properly detect FreeBSD with linuxlator for GitHub releases
local function is_compatible_with_platform(target, current_opts)
    -- Special case for FreeBSD with linuxlator - treat as compatible with Linux targets
    if platform.cached_features.freebsd and platform.cached_features.linuxlator_working then
        if target == "linux_x64" or target == "linux_arm64" then
            log.debug(string.format("FreeBSD with linuxlator detected - treating %s as compatible", target))
            return true
        end
    end
    
    -- Standard platform check
    return platform.is[target]
end

-- Replace the standard coalesce_target function with our enhanced version
local coalesce_target = function(source, opts)
    if type(source.target) == "string" then
        return is_compatible_with_platform(source.target, opts) and source.target or nil
    elseif type(source.target) == "table" then
        for i = 1, #source.target do
            local target = source.target[i]
            if is_compatible_with_platform(target, opts) then
                return target
            end
        end
    end
    return nil
end

---@param source GitHubReleaseSource
---@param purl Purl
---@param opts PackageInstallOpts
function M.parse(source, purl, opts)
    return Result.try(function(try)
        local expr_ctx = { version = purl.version }
        ---@type FileDownloadSpec
        local asset = try(util.coalesce_by_target(try(expr.tbl_interpolate(source.asset, expr_ctx)), opts))

        local downloads = common.parse_downloads(asset, function(file)
            return settings.current.github.download_url_template:format(
                ("%s/%s"):format(purl.namespace, purl.name),
                purl.version,
                file
            )
        end)

        ---@class ParsedGitHubReleaseSource : ParsedPackageSource
        local parsed_source = {
            repo = ("%s/%s"):format(purl.namespace, purl.name),
            asset = common.normalize_files(asset),
            downloads = downloads,
        }
        return parsed_source
    end)
end

-- Monkey patch the parse function to use our enhanced platform checks
local original_parse = require("mason-core.installer.registry.providers.github").parse
require("mason-core.installer.registry.providers.github").parse = function(source, purl, opts)
    -- Log the current operation for debugging
    log.debug(string.format("GitHub provider parsing for %s with FreeBSD compatibility", purl.name or "unknown package"))
    
    -- Call the original parser but intercept PLATFORM_UNSUPPORTED errors for FreeBSD systems
    local result = original_parse(source, purl, opts)
    
    if result:is_failure() and result:err_or("") == "PLATFORM_UNSUPPORTED" and
       platform.cached_features.freebsd and platform.cached_features.linuxlator_working then
        log.info("MASON-BSD-DEBUG: Trying to handle PLATFORM_UNSUPPORTED for GitHub provider on FreeBSD")
        
        -- Try to adapt the source for FreeBSD with linuxlator by treating it as Linux
        if source.asset and source.asset.target then
            -- Modify the source table to make it compatible
            local modified_source = vim.deepcopy(source)
            
            -- Check what architecture we're running
            local arch_suffix = platform.arch == "x64" and "x86_64" or 
                                platform.arch == "arm64" and "aarch64" or
                                platform.arch
            
            -- Try to find a compatible Linux target
            if type(modified_source.asset.target) == "table" then
                for _, target in ipairs(modified_source.asset.target) do
                    if target == "linux_x64" and platform.arch == "x64" or
                       target == "linux_arm64" and platform.arch == "arm64" then
                        log.info(string.format("MASON-BSD-DEBUG: Adapting %s target for FreeBSD+linuxlator", target))
                        return original_parse(modified_source, purl, { target = target })
                    end
                end
            end
        end
    end
    
    return result
end

---@async
---@param ctx InstallContext
---@param source ParsedGitHubReleaseSource
function M.install(ctx, source)
    return common.download_files(ctx, source.downloads)
end

---@async
---@param purl Purl
function M.get_versions(purl)
    return providers.github.get_all_release_versions(("%s/%s"):format(purl.namespace, purl.name))
end

-- Return the original module to maintain compatibility
return M
