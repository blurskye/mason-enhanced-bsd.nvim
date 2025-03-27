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
        if target:match("^linux_") then
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

-- Provide a safe way to detect platform unsupported errors
local function is_platform_unsupported_error(result)
    -- Try to detect platform unsupported failures without relying on specific error methods
    if result:is_failure() then
        -- For safety, if we're on FreeBSD with linuxlator, we'll just assume
        -- all failures might be platform-related and give it a try
        return platform.cached_features.freebsd and platform.cached_features.linuxlator_working
    end
    return false
end

-- Monkey patch the parse function to use our enhanced platform checks
local original_parse = require("mason-core.installer.registry.providers.github").parse
require("mason-core.installer.registry.providers.github").parse = function(source, purl, opts)
    -- Log the current operation for debugging
    log.debug(string.format("GitHub provider parsing for %s with FreeBSD compatibility", purl.name or "unknown package"))
    
    -- Call the original parser
    local result = original_parse(source, purl, opts)
    
    -- Handle possible platform unsupported errors more safely
    if is_platform_unsupported_error(result) then
        log.info("MASON-BSD-DEBUG: Trying to handle possible platform issues for GitHub provider on FreeBSD")
        
        -- Try to adapt the source for FreeBSD with linuxlator by treating it as Linux
        if source.asset then
            -- Modify the source table to make it compatible
            local modified_source = vim.deepcopy(source)
            
            -- Create modified options based on architecture
            local modified_opts = vim.deepcopy(opts or {})
            modified_opts.target = "linux_" .. platform.arch
            
            log.info(string.format("MASON-BSD-DEBUG: Trying with target=%s for package %s", 
                modified_opts.target, purl.name or "unknown"))
            
            -- Try again with Linux target
            return original_parse(modified_source, purl, modified_opts)
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
