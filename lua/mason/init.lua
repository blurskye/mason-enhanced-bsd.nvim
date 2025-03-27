local path = require "mason-core.path"
local platform = require "mason-core.platform"
local settings = require "mason.settings"

local M = {}

-- Load BSD compatibility module as early as possible
if platform.cached_features and platform.cached_features.freebsd then
    local bsd_compat = require "mason-bsd-compat"
    bsd_compat.setup()
end

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

    require "mason.api.command"
    setup_autocmds()
    require("mason-registry.sources").set_registries(settings.current.registries)
    M.has_setup = true
end

-- Store the original setup function
local original_setup = M.setup

-- Override the setup function to include our FreeBSD compatibility patches
function M.setup(opts)
    -- Load and apply FreeBSD compatibility patches
    local bsd_compat = require "mason-bsd-compat"
    bsd_compat.setup()
    
    -- Call the original setup function with the provided options
    if original_setup then
        return original_setup(opts)
    end
end

return M
