local path = require "mason-core.path"
local platform = require "mason-core.platform"
local settings = require "mason.settings"
local log = require "mason-core.log"

local M = {}

local function setup_autocmds()
    vim.api.nvim_create_autocmd("VimLeavePre", {
        callback = function()
            require("mason-core.terminator").terminate(5000)
        end,
        once = true,
    })
end

-- Initialize FreeBSD compatibility platform support if needed
local function init_freebsd_support()
    if not platform.cached_features.freebsd then
        return
    end

    if platform.cached_features.linuxlator_working then
        log.info("FreeBSD: Initializing linuxlator compatibility layer")
        
        -- Force platform overrides to load if we're on FreeBSD with linuxlator
        local registry_path = "mason-core.installer.registry"
        package.loaded[registry_path .. ".platform_override"] = nil
        require(registry_path .. ".platform_override")
    else
        log.info("FreeBSD: Native FreeBSD support only (no linuxlator)")
    end
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

    -- Initialize FreeBSD support before setting up commands
    init_freebsd_support()

    require "mason.api.command"
    setup_autocmds()
    require("mason-registry.sources").set_registries(settings.current.registries)
    M.has_setup = true
end

return M
