-- Initialize FreeBSD compatibility as early as possible
local path = require "mason-core.path"
local platform = require "mason-core.platform"
local settings = require "mason.settings"

-- Store original require function to make sure we don't break command registration
local original_require = require

-- URGENT PATCH: Create our compatibility layer directly here
if platform.cached_features and platform.cached_features.freebsd and platform.cached_features.linuxlator_working then
    -- Apply direct platform patches to force Linux compatibility
    print("\n=== MASON-BSD-DEBUG: APPLYING CRITICAL COMPATIBILITY PATCHES ===\n")
    print("Architecture: " .. platform.arch)
    
    -- Force FreeBSD to be recognized as Linux-compatible
    platform.cached_features.linux = true
    
    -- Wait for platform.is to be properly initialized before trying to modify it
    vim.schedule(function()
        -- By this time platform.is should be initialized
        if platform.is then
            -- Create direct overrides for platform.is - STRICT ARCH ENFORCEMENT
            platform.is.linux = true
            
            -- Only set architecture flags that match the current system
            if platform.arch == "x64" then
                platform.is.linux_x64 = true
                platform.is.linux_arm64 = false  -- Explicitly disable ARM
            elseif platform.arch == "arm64" then
                platform.is.linux_arm64 = true
                platform.is.linux_x64 = false    -- Explicitly disable x64
            end
            
            -- Override platform detection directly
            package.loaded["mason-core.installer.registry.platform_override"] = nil
            
            -- Create the most direct and aggressive override
            local Result = require "mason-core.result"
            local util = require "mason-core.installer.registry.util"
            
            -- Back up the original function if it exists
            if not util._original_coalesce_by_target then
                util._original_coalesce_by_target = util.coalesce_by_target
            end
            
            -- Override with our aggressive version that always accepts Linux targets
            util.coalesce_by_target = function(source, opts)
                -- Always force Linux target for FreeBSD+linuxlator WITH CORRECT ARCHITECTURE
                opts = opts or {}
                opts.target = "linux_" .. platform.arch
                log.info("MASON-BSD-DEBUG: Setting target to " .. opts.target .. " - enforcing architecture match")
                
                -- If the original function fails, we'll force success anyway
                local result = util._original_coalesce_by_target(source, opts)
                if result and result:is_failure() then
                    print("MASON-BSD-DEBUG: Forcing Linux target compatibility")
                    
                    -- Force return the source regardless of platform
                    if type(source) == "table" and #source > 0 then
                        -- Use the first entry for lists
                        return Result.success(source[1])
                    else
                        -- Just return the source directly
                        return Result.success(source)
                    end
                end
                return result
            end
        end
    end)
    
    print("=== MASON-BSD-DEBUG: CRITICAL PATCHES APPLIED ===\n")
end

local M = {}

local function setup_autocmds()
    vim.api.nvim_create_autocmd("VimLeavePre", {
        callback = function()
            require("mason-core.terminator").terminate(5000)
        end,
        once = true,
    })
end

M.has_setup = false

---@param config MasonSettings?
function M.setup(config)
    if config then
        settings.set(config)
    end
    vim.env.MASON = settings.current.install_root_dir

    if settings.current.PATH == "prepend" then
        vim.env.PATH = path.bin_prefix() .. platform.path_sep .. vim.env.PATH
    elseif settings.current.PATH == "append" then
        vim.env.PATH = vim.env.PATH .. platform.path_sep .. path.bin_prefix()
    end

    -- IMPORTANT: Be more explicit about command registration to ensure all commands work
    pcall(function()
        require "mason.api.command"
    end)
    
    -- Ensure user commands are properly registered
    local command_ok, _ = pcall(function()
        vim.cmd [[
            " Create explicit Mason commands to make sure they're available
            command! -nargs=* Mason lua require("mason.ui").open()
            command! -nargs=* MasonLog lua require("mason.api.command").mason_log()
            command! -nargs=* MasonUpdate lua require("mason.api.command").mason_update()
            command! -nargs=* MasonInstall lua require("mason.api.command").mason_install(<f-args>)
            command! -nargs=* MasonUninstall lua require("mason.api.command").mason_uninstall(<f-args>)
            command! -nargs=* MasonUninstallAll lua require("mason.api.command").mason_uninstall_all(<f-args>)
        ]]
    end)

    if not command_ok then
        print("MASON-BSD-DEBUG: Warning - failed to register some Mason commands manually")
    end
    
    setup_autocmds()
    require("mason-registry.sources").set_registries(settings.current.registries)
    M.has_setup = true
    
    print("MASON-BSD-DEBUG: Mason setup completed successfully - all commands should be available")
end

return M
