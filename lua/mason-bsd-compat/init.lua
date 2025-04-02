-- Mason FreeBSD Compatibility Module
-- This module patches Mason to properly support FreeBSD systems with linuxlator

local platform = require "mason-core.platform"
local log = require "mason-core.log"

local M = {}

function M.setup()
    -- Only apply patches on FreeBSD systems
    if not platform.cached_features.freebsd then
        return
    end
    
    log.info("MASON-BSD-DEBUG: Initializing FreeBSD compatibility patches")
    
    -- Load our platform override first - this is critical
    if platform.cached_features.linuxlator_working then
        package.loaded["mason-core.installer.registry.platform_override"] = nil
        require "mason-core.installer.registry.platform_override"
        log.info("MASON-BSD-DEBUG: Applied platform override for FreeBSD + linuxlator")
    end
    
    -- Load our patched providers
    package.loaded["mason-core.installer.registry.providers.github.release"] = nil
    require "mason-core.installer.registry.providers.github.release"
    
    package.loaded["mason-core.installer.registry.providers.init"] = nil
    require "mason-core.installer.registry.providers.init"
    
    -- Add FreeBSD to settings.lua registry if needed
    local settings = require "mason.settings"
    
    -- Report status and confirm patching
    if platform.cached_features.linuxlator_working then
        log.info("MASON-BSD-DEBUG: FreeBSD with linuxlator enabled - will support both FreeBSD and Linux packages")
        -- Force Linux mode to be enabled regardless of other checks
        platform.cached_features.linux = true
        
        -- Apply a monkey patch to force platform.is to report linux=true
        local mt = getmetatable(platform.is)
        local original_index = mt.__index
        mt.__index = function(t, k)
            -- Special override for linux targets on FreeBSD+linuxlator
            if k:match("^linux") and platform.cached_features.freebsd and platform.cached_features.linuxlator_working then
                local parts = vim.split(k, "_", { plain = true })
                local arch = parts[2]
                if not arch or arch == platform.arch then
                    return true
                end
            end
            return original_index(t, k)
        end
    else
        log.info("MASON-BSD-DEBUG: FreeBSD without linuxlator - will only support FreeBSD packages")
    end
    
    log.info("MASON-BSD-DEBUG: FreeBSD compatibility patches applied successfully")
end

return M
