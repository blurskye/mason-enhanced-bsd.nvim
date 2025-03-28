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

---@param source GitHubReleaseSource
---@param purl Purl
---@param opts PackageInstallOpts
function M.parse(source, purl, opts)
    -- Ensure we have the right target on FreeBSD+linuxlator
    if platform.cached_features.freebsd and platform.cached_features.linuxlator_working and not opts.target then
        opts = opts or {}
        opts.target = "linux_" .. platform.arch
        log.debug("FreeBSD: Setting GitHub release target to " .. opts.target)
    end

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
    end):on_failure(function(err)
        -- Special handling for platform unsupported errors on FreeBSD with linuxlator
        if err == "PLATFORM_UNSUPPORTED" and platform.cached_features.freebsd and platform.cached_features.linuxlator_working then
            log.debug("FreeBSD: Attempting Linux compatibility fallback for GitHub release")
            
            -- Try again with explicit Linux target
            opts = opts or {}
            opts.target = "linux_" .. platform.arch
            
            return M.parse(source, purl, opts)
        end
        return err
    end)
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

return M
