--[[
===============================================================================
 staticid_client.lua
 Lightweight client helper for HUD / UI scripts needing the player's static ID.

 Responsibilities:
   * Maintain a local cached copy of the player's static ID (CurrentStaticID)
   * Expose a simple export: ShowStaticID() -> number|nil
   * Allow listeners to register for change events (RegisterStaticIDListener(cb))
   * Request initial static ID from server when resource starts / player spawns

 Design Notes:
   * Server pushes static ID proactively after cacheOnline() via event
     'staticid:client:set'. This keeps client updated on first join.
   * Clients can also call exports['FiveM-Static-ID']:ShowStaticID() anytime.
   * Listener API is optional syntactic sugar for HUD scripts wanting a callback.
===============================================================================
]]

local CurrentStaticID = nil
local Listeners = {}

-- Public registration helper (not exported explicitly; require via events or exports if needed)
function RegisterStaticIDListener(cb)
    if type(cb) == 'function' then
        Listeners[#Listeners+1] = cb
        -- Fire immediately if we already have the ID
        if CurrentStaticID then
            pcall(cb, CurrentStaticID)
        end
    end
end

local function setStaticId(newId)
    if newId ~= nil then
        local num = tonumber(newId)
        if num then
            CurrentStaticID = num
            for _, cb in ipairs(Listeners) do
                pcall(cb, num)
            end
        end
    end
end

-- Event from server delivering static ID
RegisterNetEvent('staticid:client:set', function(staticId)
    setStaticId(staticId)
end)

-- Initial fetch (in case server didn't push yet or resource restarted)
CreateThread(function()
    TriggerServerEvent('staticid:server:requestStaticID')
end)

-- Export for HUD usage
exports('ShowStaticID', function()
    return CurrentStaticID
end)

-- Safe style export: returns (ok, value)
exports('SafeShowStaticID', function()
    if CurrentStaticID == nil then
        return false, nil
    end
    return true, CurrentStaticID
end)
