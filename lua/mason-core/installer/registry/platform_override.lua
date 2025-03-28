local platform = require "mason-core.platform"
local log = require "mason-core.log"

local M = {}

-- Store the original __index method
local original_index = getmetatable(platform.is).__index

-- Function to explicitly check if a target is compatible with the current system
-- This is more permissive for FreeBSD systems with linuxlator
function M.is_supported_on_platform(target)
    -- FreeBSD with linuxlator should support both FreeBSD and Linux packages
    if platform.cached_features.freebsd and platform.cached_features.linuxlator_working then
        -- Allow Linux targets on FreeBSD with linuxlator
        if target:match("^linux_") then
            log.debug("FreeBSD: Allowing Linux target on FreeBSD with linuxlator: " .. target)
            return true
        end
        
        -- Allow FreeBSD targets
        if target:match("^freebsd_") or target:match("^unix_") then
            return true
        end
    end
    
    -- Call the original __index method directly to avoid recursion
    return original_index(platform.is, target)
end

-- Patch the platform.is table to use our override
getmetatable(platform.is).__index = function(t, key)
    -- Direct implementation without recursion
    if platform.cached_features.freebsd and platform.cached_features.linuxlator_working then
        -- Allow Linux targets on FreeBSD with linuxlator
        if key:match("^linux_") then
            local parts = vim.split(key, "_", { plain = true })
            local arch = parts[2]
            if not arch or arch == platform.arch then
                log.debug("FreeBSD: Allowing Linux target on FreeBSD with linuxlator: " .. key)
                return true
            end
        end
        
        -- Allow FreeBSD targets
        if key:match("^freebsd_") or key:match("^unix_") then
            return true
        end
    end
    
    -- Fall back to original behavior
    return original_index(t, key)
end

return M