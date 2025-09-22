--[[
===============================================================================
 commands.lua
 User & admin command layer (server-side):
     /getstatic, /getdynamic, /whois, /resolve, /staticidinfo
     /staticidsave, /staticidclear (persistence controls)
     /staticidwarn (standalone diagnostics)
     /staticidconflicts, /staticidconflictsclear (conflict detection stats)

 Responsibilities:
     - Argument parsing & basic validation
     - Locale-based messaging (delegates translation to locales/*.lua)
     - Framework-aware notification dispatch (ESX, QBCore, standalone fallback)
     - Keeps business logic inside shared.lua via exports

 Non-goals:
     - Direct DB access (always use exports)
     - Heavy formatting / pagination (keep output concise)
===============================================================================
]]
-- Central notification handling
local Config = Config or require('config')
local Locales = Locales or {}
local ActiveLocale = Config.Locale or 'en'

local function _U(key, ...)
    local pack = Locales[ActiveLocale] or Locales['en'] or {}
    local str = pack[key] or key
    if select('#', ...) > 0 then
        local ok, formatted = pcall(string.format, str, ...)
        if ok then return formatted end
    end
    return str
end

-- Framework aware notification dispatch
local function notify(src, text, nType, dur)
    if src == 0 then
        print('[StaticID] ' .. tostring(text))
        return
    end
    if Config.Framework == 'qb' then
        TriggerClientEvent('QBCore:Notify', src, tostring(text), nType or 'primary', tonumber(dur) or Config.NotifyDuration)
    elseif Config.Framework == 'esx' then
        TriggerClientEvent('esx:showNotification', src, tostring(text))
    else
        -- standalone: simple chat message fallback
        TriggerClientEvent('chat:addMessage', src, { args = { 'StaticID', tostring(text) } })
    end
end

local function getstatic(source, args)
    local dyn = args and args[1] and tonumber(args[1]) or nil
    if not dyn then
        return notify(source, _U('cmd_usage_getstatic'))
    end
    local static_id = GetClientStaticID(dyn)
    if static_id then
        notify(source, _U('static_id_result', dyn, static_id))
    else
        notify(source, _U('static_id_not_found', dyn))
    end
end

local function getdynamic(source, args)
    local sid = args and args[1] and tonumber(args[1]) or nil
    if not sid then
        return notify(source, _U('cmd_usage_getdynamic'))
    end
    local dynamic_id = GetClientDynamicID(sid)
    if dynamic_id then
        notify(source, _U('dynamic_id_result', sid, dynamic_id))
    else
        notify(source, _U('dynamic_id_not_found', sid))
    end
end

RegisterCommand('getstatic', function(src, args)
    getstatic(src, args)
end, true)
RegisterCommand('gs', function(src, args)
    getstatic(src, args)
end, true)

RegisterCommand('getdynamic', function(src, args)
    getdynamic(src, args)
end, true)
RegisterCommand('gd', function(src, args)
    getdynamic(src, args)
end, true)

-- Prints a short help overview to server console
RegisterCommand('staticidhelp', function(source)
    print(_U('help_header'))
    print(_U('help_getstatic'))
    print(_U('help_getdynamic'))
end, true)

-- Optional: list all registered commands (server console)
RegisterCommand('allcommands', function(source)
    print('All registered commands:')
    for _, command in ipairs(GetRegisteredCommands()) do
        print(command.name)
    end
end, true)

-- Persistence commands (server console or admin)
RegisterCommand('staticidsave', function(src)
    if not (Config.PersistentCache and Config.PersistentCache.Enabled) then
        print(_U('persist_cmd_disabled'))
        return
    end
    -- Use export so that logic stays centralized in shared.lua
    local ok = pcall(function() exports['FiveM-Static-ID']:StaticID_SaveCache() end)
    if ok then
        print(_U('persist_cmd_save'))
    end
end, true)

RegisterCommand('staticidclear', function(src)
    if not (Config.PersistentCache and Config.PersistentCache.Enabled) then
        print(_U('persist_cmd_disabled'))
        return
    end
    local ok = pcall(function() exports['FiveM-Static-ID']:StaticID_ClearPersist() end)
    if ok then
        print(_U('persist_cmd_clear'))
    end
end, true)

-- /whois command: accepts either dynamic or static ID and resolves details
RegisterCommand('whois', function(source, args)
    local input = args and args[1]
    if not input then
        return notify(source, _U('whois_usage'))
    end
    local num = tonumber(input)
    if not num then
    return notify(source, _U('whois_not_numeric'))
    end

    -- Try as dynamic ID first
    local staticId = GetClientStaticID(num)
    if staticId then
        local identifier = GetIdentifierFromStaticID(staticId) or 'n/a'
        local online = CheckDynamicIDOnline(num)
        local status = online and 'online' or 'offline'
        return notify(source, _U('whois_dyn', num, staticId, identifier, status))
    end

    -- If not found, try as static ID
    local dyn = GetClientDynamicID(num)
    local identifier = GetIdentifierFromStaticID(num) or 'n/a'
    if identifier then
        local status = (dyn and CheckDynamicIDOnline(dyn)) and 'online' or 'offline'
        if dyn then
            return notify(source, _U('whois_static_full', num, dyn, identifier, status))
        else
            return notify(source, _U('whois_static_no_dyn', num, identifier, status))
        end
    end

    notify(source, _U('whois_not_found', num))
end, true)

-- /resolve id1,id2,id3  (each element may be dynamic or static)
RegisterCommand('resolve', function(source, args)
    local list = args and args[1]
    if not list then
        return notify(source, _U('resolve_usage'))
    end
    local out = {}
    for entry in string.gmatch(list, '([^,]+)') do
        local raw = entry:gsub('%s+', '')
        local num = tonumber(raw)
        if num then
            local staticId = GetClientStaticID(num)
            if staticId then
                local identifier = GetIdentifierFromStaticID(staticId) or 'n/a'
                table.insert(out, _U('resolve_prefix_dyn', num, staticId, identifier))
            else
                local dyn = GetClientDynamicID(num)
                if dyn then
                    local identifier = GetIdentifierFromStaticID(num) or 'n/a'
                    table.insert(out, _U('resolve_prefix_static', num, dyn, identifier))
                else
                    table.insert(out, _U('resolve_unknown', raw))
                end
            end
        else
            table.insert(out, _U('resolve_unknown', raw))
        end
    end
    notify(source, table.concat(out, _U('resolve_result_joiner')))
end, true)

-- Info command: basic runtime info
RegisterCommand('staticidinfo', function(source)
    local fw = Config.Framework
    local separate = Config.DB.UseSeparateStaticTable and 'on' or 'off'
    local persist = (Config.PersistentCache and Config.PersistentCache.Enabled) and 'on' or 'off'
    -- (Cache stats not exported; only high-level info for now)
    local counts = {}
    local ok, res = pcall(function() return true end)
    notify(source, _U('info_summary', fw, separate, persist))
end, true)

-- Standalone warning / status command
RegisterCommand('staticidwarn', function(source)
    if Config.Framework ~= 'standalone' then
        notify(source, 'Not in standalone mode.')
        return
    end
    print('[StaticID] ' .. _U('standalone_warn_header'))
    if Config.DB.UseSeparateStaticTable then
        print('[StaticID] ' .. _U('standalone_warn_table_on'))
    else
        print('[StaticID] ' .. _U('standalone_warn_table_off'))
    end
    local order = Config.StandaloneIdentifierOrder or {}
    print('[StaticID] ' .. _U('standalone_warn_ident_order', table.concat(order, ', ')))
end, true)

-- Conflict stats command
RegisterCommand('staticidconflicts', function(source)
    local stats = exports[GetCurrentResourceName()]:GetConflictStats()
    local header = _U('conflict_cmd_header', tostring(stats.total), tostring(#stats.recent))
    if source == 0 then
        print(('^3[StaticID] %s^0'):format(header))
    else
        notify(source, '^3' .. header)
    end
    if #stats.recent == 0 then
        local none = _U('conflict_none')
        if source == 0 then
            print(('^2[StaticID] %s^0'):format(none))
        else
            notify(source, '^2' .. none)
        end
        return
    end
    for _, rec in ipairs(stats.recent) do
        local line = _U('conflict_detected', rec.identifier, tostring(rec.cacheStatic), tostring(rec.dbStatic))
        if source == 0 then
            print(('^1[StaticID] %s^0'):format(line))
        else
            notify(source, '^1' .. line)
        end
    end
end, true)

RegisterCommand('staticidconflictsclear', function(source)
    local cleared = exports[GetCurrentResourceName()]:ClearConflictStats()
    if source == 0 then
        print(('^2[StaticID] Conflict stats cleared: %s^0'):format(tostring(cleared)))
    else
        notify(source, '^2Conflict stats cleared')
    end
end, true)

-- Admin reset command: wipes static_ids table & cache (separate table mode only)
RegisterCommand('staticidreset', function(source)
    local ok, res = pcall(function()
        return exports[GetCurrentResourceName()]:StaticID_ResetStaticTable()
    end)
    if not ok or res == false then
        local msg = res or 'Reset failed'
        if source == 0 then
            print(('^1[StaticID] Reset failed: %s^0'):format(tostring(msg)))
        else
            notify(source, '^1Reset fehlgeschlagen: ' .. tostring(msg))
        end
        return
    end
    if source == 0 then
    print('^2[StaticID] StaticID table & cache reset.^0')
    else
    notify(source, '^2StaticID table & cache reset')
    end
end, true)