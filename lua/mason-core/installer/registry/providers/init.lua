-- Enhanced registry provider loader with FreeBSD compatibility

local _ = require "mason-core.functional"
local log = require "mason-core.log"
local platform = require "mason-core.platform"
local Result = require "mason-core.result"

local M = {}

-- Load our patched GitHub provider for FreeBSD compatibility
if platform.cached_features.freebsd then
    log.info("MASON-BSD-DEBUG: Loading FreeBSD-enhanced GitHub provider")
    -- Make sure our patched version is loaded
    require "mason-core.installer.registry.providers.github.release"
end

-- Register all standard providers
M.cargo = _.lazy_require "mason-core.installer.registry.providers.cargo"
M.composer = _.lazy_require "mason-core.installer.registry.providers.composer"
M.gem = _.lazy_require "mason-core.installer.registry.providers.gem"
M.generic = _.lazy_require "mason-core.installer.registry.providers.generic"
M.github = _.lazy_require "mason-core.installer.registry.providers.github"
M.golang = _.lazy_require "mason-core.installer.registry.providers.golang"
M.luarocks = _.lazy_require "mason-core.installer.registry.providers.luarocks"
M.npm = _.lazy_require "mason-core.installer.registry.providers.npm"
M.nuget = _.lazy_require "mason-core.installer.registry.providers.nuget"
M.opam = _.lazy_require "mason-core.installer.registry.providers.opam"
M.openvsx = _.lazy_require "mason-core.installer.registry.providers.openvsx"
M.pypi = _.lazy_require "mason-core.installer.registry.providers.pypi"

-- We need to ensure registry is properly loaded
local registry = require "mason-core.installer.registry"

-- Override registry.init.lua's parse function to handle FreeBSD+linuxlator special case
local original_parse = registry.parse

-- Add FreeBSD+Linuxlator support to the registry parser - FIX THE ERROR
registry.parse = function(spec, opts)
    local result = original_parse(spec, opts)
    
    -- The error was here - we need to properly check for PLATFORM_UNSUPPORTED errors
    if result:is_failure() then
        -- Get the error message safely
        local err = result:err()
        
        -- Check if it's a platform unsupported error and we're on FreeBSD with linuxlator
        if err == "PLATFORM_UNSUPPORTED" and
           platform.cached_features.freebsd and platform.cached_features.linuxlator_working then
            
            log.info("MASON-BSD-DEBUG: Package failed with PLATFORM_UNSUPPORTED, trying Linux compatibility mode")
            
            -- Create modified options that override the target to Linux
            local modified_opts = vim.deepcopy(opts or {})
            modified_opts.target = "linux_" .. platform.arch
            
            -- Try again with Linux target
            log.info(string.format("MASON-BSD-DEBUG: Retrying with target=%s", modified_opts.target))
            return original_parse(spec, modified_opts)
        end
    end
    
    return result
end

return M
