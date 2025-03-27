local platform = require "mason-core.platform"
local log = require "mason-core.log"

local M = {}

-- Function to explicitly check if a target is compatible with the current system
-- This is more permissive for FreeBSD systems with linuxlator
function M.is_supported_on_platform(target)
    -- FreeBSD with linuxlator should support both FreeBSD and Linux packages
    if platform.cached_features.freebsd and platform.cached_features.linuxlator_working then
        -- Allow Linux targets on FreeBSD with linuxlator
        if target:match("^linux_") then
            log.debug("MASON-BSD-DEBUG: Allowing Linux target on FreeBSD with linuxlator: " .. target)
            return true
        end
        
        -- Allow FreeBSD targets
        if target:match("^freebsd_") or target:match("^unix_") then
            return true
        end
    end
    
    -- Fall back to standard platform check
    return platform.is[target]
end

-- Patch the platform.is table to use our override
local original_index = getmetatable(platform.is).__index
getmetatable(platform.is).__index = function(t, key)
    -- Always check our override first
    if M.is_supported_on_platform(key) then
        return true
    end
    
    -- Fall back to original behavior
    return original_index(t, key)
end

return M
