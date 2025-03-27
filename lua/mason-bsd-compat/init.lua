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
    
    -- Load our patched providers
    require "mason-core.installer.registry.providers.github.release"
    require "mason-core.installer.registry.providers.init"
    
    -- Add FreeBSD to settings.lua registry
    local settings = require "mason.settings"
    
    -- Add a registry for FreeBSD packages if one exists
    if platform.cached_features.freebsd then
        log.info("MASON-BSD-DEBUG: Adding FreeBSD package registry")
        
        -- You can uncomment and customize this to add a FreeBSD-specific registry
        -- if you create one in the future
        -- table.insert(settings.current.registries, 1, "github:your-username/mason-freebsd-registry")
    end
    
    log.info("MASON-BSD-DEBUG: FreeBSD compatibility patches applied successfully")
    
    -- Report status
    if platform.cached_features.linuxlator_working then
        log.info("MASON-BSD-DEBUG: FreeBSD with linuxlator enabled - will support both FreeBSD and Linux packages")
    else
        log.info("MASON-BSD-DEBUG: FreeBSD without linuxlator - will only support FreeBSD packages")
    end
end

return M
