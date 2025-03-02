local Optional = require "mason-core.optional"
local Result = require "mason-core.result"
local _ = require "mason-core.functional"
local log = require "mason-core.log"

---@class LuaRegistrySourceSpec
---@field id string
---@field mod string

---@class LuaRegistrySource : RegistrySource
---@field private spec LuaRegistrySourceSpec
local LuaRegistrySource = {}
LuaRegistrySource.__index = LuaRegistrySource

---@param spec LuaRegistrySourceSpec
function LuaRegistrySource:new(spec)
    ---@type LuaRegistrySource
    local instance = {}
    setmetatable(instance, LuaRegistrySource)
    instance.id = spec.id
    instance.spec = spec
    return instance
end

---@param pkg_name string
---@return Package?
function LuaRegistrySource:get_package(pkg_name)
    local index = require(self.spec.mod)
    if index[pkg_name] then
        local ok, mod = pcall(require, index[pkg_name])
        if ok then
            return mod
        else
            log.fmt_warn("Unable to load %s from %s: %s", pkg_name, self, mod)
        end
    end
end

function LuaRegistrySource:install()
    return Result.pcall(require, self.spec.mod)
end

---@return string[]
function LuaRegistrySource:get_all_package_names()
    local index = require(self.spec.mod)
    return vim.tbl_keys(index)
end

---@return RegistryPackageSpec[]
function LuaRegistrySource:get_all_package_specs()
    return _.filter_map(function(name)
        return Optional.of_nilable(self:get_package(name)):map(_.prop "spec")
    end, self:get_all_package_names())
end

function LuaRegistrySource:is_installed()
    local ok = pcall(require, self.spec.mod)
    return ok
end

function LuaRegistrySource:get_display_name()
    if self:is_installed() then
        return ("require(%q)"):format(self.spec.mod)
    else
        return ("require(%q) [uninstalled]"):format(self.spec.mod)
    end
end

function LuaRegistrySource:__tostring()
    return ("LuaRegistrySource(mod=%s)"):format(self.spec.mod)
end

return LuaRegistrySource
