--[[
===============================================================================
 shared.lua
 Core logic for the Static ID system:
     * Framework abstraction (ESX / QBCore / Standalone)
     * Bidirectional caches: identifier <-> static_id, static_id <-> dynamic_id
     * Periodic refresh / pruning / persistence snapshot
     * One-time migration into separate static_ids table (optional)
     * Safe wrapper exports (uniform (ok,value,err))
     * Conflict detection scanning (multi-node consistency)
     * Bulk resolution & helper utilities

 Design goals:
     - Fast hot-path (cache first, DB only on scheduled refresh or misses)
     - Minimal coupling to framework internals
     - Graceful degradation (errors never fatal, corrupted snapshot ignored)
     - Extensibility (add locales, new exports, or alternate identifier strategies)
===============================================================================
]]
local Config = Config or require('config')

local ESX, QBCore

-- Auto framework detection (if configured)
if Config.Framework == 'auto' then
    local pref = (Config.AutoFramework and Config.AutoFramework.Priority) or { 'esx','qb','standalone' }
    local detected
    for _, fw in ipairs(pref) do
        if fw == 'esx' and exports['es_extended'] then
            local ok = pcall(function() return exports['es_extended']:getSharedObject() end)
            if ok then detected = 'esx' break end
        elseif fw == 'qb' and exports['qb-core'] then
            local ok = pcall(function() return exports['qb-core']:GetCoreObject() end)
            if ok then detected = 'qb' break end
        elseif fw == 'standalone' then
            detected = 'standalone'
            break
        end
    end
    if not detected then
        detected = (Config.AutoFramework and Config.AutoFramework.Fallback) or 'standalone'
    end
    if Config.AutoFramework and Config.AutoFramework.Log then
        print(('^2[StaticID] Auto framework detected: %s^0'):format(detected))
    end
    Config.Framework = detected
end

if Config.Framework == 'esx' then
    ESX = exports['es_extended'] and exports['es_extended']:getSharedObject()
elseif Config.Framework == 'qb' then
    QBCore = exports['qb-core'] and exports['qb-core']:GetCoreObject()
elseif Config.Framework == 'standalone' then
    -- no framework init required
    if not Config.DB.UseSeparateStaticTable then
        print('^3[StaticID] Standalone mode detected -> forcing UseSeparateStaticTable=true for data isolation.^0')
        Config.DB.UseSeparateStaticTable = true
    end
end
local Locales = Locales or {}
-- Active locale (defined in locales/*.lua)
local ActiveLocale = Config.Locale or 'en'

-- Helper: translation lookup
local function _U(key, ...)
    local pack = Locales[ActiveLocale] or Locales['en'] or {}
    local str = pack[key] or key
    if select('#', ...) > 0 then
        local ok, formatted = pcall(string.format, str, ...)
        if ok then return formatted end
    end
    return str
end

--[[
    Utility: Validate numeric input (can arrive as string). Returns number or nil.
]]
local function asNumber(v)
    if v == nil then return nil end
    local n = tonumber(v)
    if n and n >= 0 then return n end
    return nil
end

local function debugPrint(msg)
    if Config.Debug then
        print(('^3[StaticID][DEBUG]^0 %s'):format(msg))
    end
end

local function errorParam(msg)
    print(('^1[StaticID] %s^0'):format(_U('param_error', msg or 'Nil')))
end

local function sqlError(msg)
    print(('^1[StaticID] %s^0'):format(_U('sql_error', msg or ''))) 
end

--[[
    Internal: execute simple SQL query with error capture.
    query: string (with ? placeholders)
    params: table or nil
    returns: result table or nil
]]
local function runSql(query, params)
    local ok, res = pcall(function()
        return MySQL.query.await(query, params)
    end)
    if not ok then
        sqlError(res)
        return nil
    end
    if res and #res > 0 then return res end
    return nil
end

-- Simple scalar query helper (COUNT, etc.)
local function runScalar(query, params)
    local ok, res = pcall(function()
        return MySQL.scalar.await(query, params)
    end)
    if not ok then
        sqlError(res)
        return nil
    end
    return res
end

-- Forward helper (must be declared before first use in validateSchema)
local function usingSeparateTable()
    return Config.DB.UseSeparateStaticTable == true
end

--[[ Schema Validation ]]--
local function validateSchema()
    -- Basic presence checks; non-fatal but warn loudly.
    local okPrimary
    if usingSeparateTable() then
        -- Check separate table columns
        local rows = runSql(('SHOW COLUMNS FROM %s'):format(Config.DB.SeparateTableName), {})
        if not rows then
            print(('^1[StaticID] Schema WARN: separate table %s not reachable (SHOW COLUMNS failed).^0'):format(Config.DB.SeparateTableName))
            return
        end
        local havePK, haveIdent = false, false
        for _, c in ipairs(rows) do
            local field = c.Field or c.FIELD or c.column_name
            if field == Config.DB.SeparateTablePK then havePK = true end
            if field == Config.DB.SeparateTableIdentifier then haveIdent = true end
        end
        if not havePK then
            print(('^1[StaticID] Schema WARN: Column %s missing in %s.^0'):format(Config.DB.SeparateTablePK, Config.DB.SeparateTableName))
        end
        if not haveIdent then
            print(('^1[StaticID] Schema WARN: Column %s missing in %s.^0'):format(Config.DB.SeparateTableIdentifier, Config.DB.SeparateTableName))
        end
        okPrimary = havePK and haveIdent
    else
        -- Users table mode
        local rows = runSql(('SHOW COLUMNS FROM %s'):format(Config.DB.UsersTable), {})
        if not rows then
            print(('^1[StaticID] Schema WARN: users table %s not reachable (SHOW COLUMNS failed).^0'):format(Config.DB.UsersTable))
            return
        end
        local haveIdent, haveStatic = false, false
        for _, c in ipairs(rows) do
            local field = c.Field or c.FIELD or c.column_name
            if field == Config.DB.IdentifierColumn then haveIdent = true end
            if field == Config.DB.StaticIDColumn then haveStatic = true end
        end
        if not haveIdent then
            print(('^1[StaticID] Schema WARN: Identifier column %s missing in %s.^0'):format(Config.DB.IdentifierColumn, Config.DB.UsersTable))
        end
        if not haveStatic then
            print(('^1[StaticID] Schema WARN: Static ID column %s missing in %s.^0'):format(Config.DB.StaticIDColumn, Config.DB.UsersTable))
            if Config.Framework == 'qb' then
                print('^3[StaticID] Hint (QBCore): Consider UseSeparateStaticTable=true for a dedicated numeric static id.^0')
            end
        end
        okPrimary = haveIdent and haveStatic
    end
    if okPrimary then
        debugPrint('Schema validation OK')
    end
end
-- Separate Table Mode Helpers

local function selectStaticByIdentifier(identifier)
    if usingSeparateTable() then
        return runSql(('SELECT %s FROM %s WHERE %s = ? LIMIT 1'):format(
            Config.DB.SeparateTablePK, Config.DB.SeparateTableName, Config.DB.SeparateTableIdentifier), { identifier })
    else
        return runSql(('SELECT %s FROM %s WHERE %s = ? LIMIT 1'):format(
            Config.DB.StaticIDColumn, Config.DB.UsersTable, Config.DB.IdentifierColumn), { identifier })
    end
end

local function selectIdentifierByStatic(static_id)
    if usingSeparateTable() then
        return runSql(('SELECT %s FROM %s WHERE %s = ? LIMIT 1'):format(
            Config.DB.SeparateTableIdentifier, Config.DB.SeparateTableName, Config.DB.SeparateTablePK), { static_id })
    else
        return runSql(('SELECT %s FROM %s WHERE %s = ? LIMIT 1'):format(
            Config.DB.IdentifierColumn, Config.DB.UsersTable, Config.DB.StaticIDColumn), { static_id })
    end
end

-- One-time migration users -> static_ids (only if enabled and table empty/nearly empty)
local function migrateUsersToSeparate()
    if not usingSeparateTable() then return end
    if not (Config.DB.MigrateUsersOnFirstRun) then return end
    -- Prüfe ob Tabelle leer ist (oder extrem klein < 5 Einträge) umversehene Doppel-Migration vermeiden
    local count = runScalar(('SELECT COUNT(*) FROM %s'):format(Config.DB.SeparateTableName), {}) or 0
    if count > 5 then
        debugPrint('Migration skipped (table not empty)')
        return
    end
    print('^3[StaticID] Starting one-time migration users -> ' .. Config.DB.SeparateTableName .. ' ...^0')
    local rows = runSql(('SELECT %s AS identifier FROM %s LIMIT %d'):format(
        Config.DB.IdentifierColumn, Config.DB.UsersTable, Config.MaxRefreshRows), {})
    if not rows then
        print('^1[StaticID] Migration aborted: no users rows.^0')
        return
    end
    local inserted = 0
    for _, r in ipairs(rows) do
        local identifier = r.identifier and tostring(r.identifier)
        if identifier and identifier ~= '' then
            local okIns, _ = pcall(function()
                return MySQL.insert.await(('INSERT IGNORE INTO %s (%s) VALUES (?)'):format(
                    Config.DB.SeparateTableName, Config.DB.SeparateTableIdentifier), { identifier })
            end)
            if okIns then inserted = inserted + 1 end
        end
    end
    print(('^2[StaticID] Migration done. Insert attempts: %d (duplicates ignored). New count may differ.^0'):format(inserted))
end

local function insertStaticForIdentifier(identifier)
    if not usingSeparateTable() then return nil end
    local ok, res = pcall(function()
        return MySQL.insert.await(('INSERT IGNORE INTO %s (%s) VALUES (?)'):format(
            Config.DB.SeparateTableName, Config.DB.SeparateTableIdentifier), { identifier })
    end)
    if not ok then
        sqlError('Insert static id failed: ' .. tostring(res))
        return nil
    end
    local rows = selectStaticByIdentifier(identifier)
    if rows then
        local key = Config.DB.SeparateTablePK
        local newId = tonumber(rows[1][key])
        if newId and Config.Framework == 'standalone' then
            TriggerEvent('staticid:assigned', identifier, newId)
        end
        return newId
    end
    return nil
end

--[[ Cache structures ]]
local Cache = {
    -- identifier -> static_id
    identifierToStatic = {},
    -- static_id -> identifier
    staticToIdentifier = {},
    -- static_id -> dynamic_id (nur wenn online)
    staticToDynamic = {},
    -- dynamic_id -> static_id (nur wenn online)
    dynamicToStatic = {},
    -- Dirty flags für Persistenz
    _dirtyStatic = false,
    _dirtyDynamic = false
}

-- Timestamps for persistence events (os.time())
local _persistMeta = {
    lastSave = nil,
    lastLoad = nil
}

-- QBCore identifier index (identifier -> player source)
local QB_Index = {} -- only used when Framework == 'qb'

-- Persistence file name
local persistFile = (Config.PersistentCache and Config.PersistentCache.FileName) or 'cache_staticid.json'

-- Simple JSON helpers
local function fileExists(path)
    local f = io.open(path, 'r')
    if f then f:close() return true end
    return false
end

local function savePersistent()
    if not (Config.PersistentCache and Config.PersistentCache.Enabled) then return end
    if Config.PersistentCache.SkipIfClean and not Cache._dirtyStatic and (not Config.PersistentCache.IncludeDynamic or not Cache._dirtyDynamic) then
    return -- nothing changed
    end
    local data = {
        identifierToStatic = Cache.identifierToStatic,
        staticToIdentifier = Cache.staticToIdentifier
    }
    if Config.PersistentCache.IncludeDynamic then
        data.staticToDynamic = Cache.staticToDynamic
        data.dynamicToStatic = Cache.dynamicToStatic
    end
    local ok, encoded = pcall(json.encode, data)
    if not ok then
        sqlError('Persist encode fail')
        return
    end
    if Config.PersistentCache.UseChecksum then
        local function calcSum(str)
            local s = 0
            for i = 1, #str do
                s = (s + str:byte(i)) % 2147483647
            end
            return s
        end
    -- static portion
        local staticPayload = {
            identifierToStatic = data.identifierToStatic,
            staticToIdentifier = data.staticToIdentifier
        }
        local okS, encS = pcall(json.encode, staticPayload)
        if not okS then sqlError('Persist static encode fail') return end
        data.__checksum = calcSum(encS)
        if Config.PersistentCache.IncludeDynamic and Config.PersistentCache.SeparateDynamicChecksum then
            local dynPayload = {
                staticToDynamic = data.staticToDynamic,
                dynamicToStatic = data.dynamicToStatic
            }
            local okD, encD = pcall(json.encode, dynPayload)
            if okD then
                data.__checksum_dynamic = calcSum(encD)
            end
        end
        ok, encoded = pcall(json.encode, data)
        if not ok then
            sqlError('Persist encode checksum fail')
            return
        end
    end
    local f = io.open(persistFile, 'w+')
    if not f then
        sqlError('Cannot open persist file for writing')
        return
    end
    f:write(encoded)
    f:close()
    debugPrint(_U('persist_saved', persistFile))
    _persistMeta.lastSave = os.time()
    Cache._dirtyStatic = false
    Cache._dirtyDynamic = false
end

local function loadPersistent()
    if not (Config.PersistentCache and Config.PersistentCache.Enabled) then return end
    if not fileExists(persistFile) then return end
    local f = io.open(persistFile, 'r')
    if not f then return end
    local content = f:read('*a')
    f:close()
    local ok, decoded = pcall(json.decode, content)
    if not ok or type(decoded) ~= 'table' then
        sqlError('Persist decode fail')
        return
    end
    if Config.PersistentCache.UseChecksum and decoded.__checksum then
        local checksumStatic = decoded.__checksum
        local checksumDynamic = decoded.__checksum_dynamic
        decoded.__checksum = nil
        decoded.__checksum_dynamic = nil
        local staticPayload = {
            identifierToStatic = decoded.identifierToStatic,
            staticToIdentifier = decoded.staticToIdentifier
        }
        local okS, encS = pcall(json.encode, staticPayload)
        if not okS then sqlError('Checksum re-encode failed') return end
        local function calcSum(str)
            local s = 0
            for i = 1, #str do
                s = (s + str:byte(i)) % 2147483647
            end
            return s
        end
        if calcSum(encS) ~= checksumStatic then
            sqlError('Checksum mismatch, ignoring persisted cache')
            return
        end
        if Config.PersistentCache.IncludeDynamic and Config.PersistentCache.SeparateDynamicChecksum and checksumDynamic then
            local dynPayload = {
                staticToDynamic = decoded.staticToDynamic,
                dynamicToStatic = decoded.dynamicToStatic
            }
            local okD, encD = pcall(json.encode, dynPayload)
            if okD and calcSum(encD) ~= checksumDynamic then
                sqlError('Dynamic checksum mismatch, ignoring dynamic section')
                decoded.staticToDynamic = {}
                decoded.dynamicToStatic = {}
            end
        end
    elseif Config.PersistentCache.UseChecksum then
        sqlError('Checksum expected but missing, ignoring file')
        return
    end
    if decoded.identifierToStatic then
        for k,v in pairs(decoded.identifierToStatic) do
            Cache.identifierToStatic[k] = v
        end
    end
    if decoded.staticToIdentifier then
        for k,v in pairs(decoded.staticToIdentifier) do
            Cache.staticToIdentifier[tonumber(k) or k] = v
        end
    end
    if Config.PersistentCache.IncludeDynamic then
        if decoded.staticToDynamic then
            for k,v in pairs(decoded.staticToDynamic) do
                Cache.staticToDynamic[tonumber(k) or k] = v
            end
        end
        if decoded.dynamicToStatic then
            for k,v in pairs(decoded.dynamicToStatic) do
                Cache.dynamicToStatic[tonumber(k) or k] = v
            end
        end
    end
    debugPrint(_U('persist_loaded', persistFile))
    _persistMeta.lastLoad = os.time()
end

local function clearPersistent()
    if fileExists(persistFile) then
        os.remove(persistFile)
        debugPrint(_U('persist_cleared', persistFile))
    end
end

-- Cache Eintrag für online Spieler anlegen
local function extractIdentifierFromPlayer(p)
    if not p then return nil end
    if Config.Framework == 'esx' then
        return p.identifier
    elseif Config.Framework == 'qb' then
        local pd = p.PlayerData
        if not pd then return nil end
        local order = (Config.QB and Config.QB.IdentifierOrder) or { 'license', 'citizenid' }
        for _, key in ipairs(order) do
            local val = pd[key]
            if val and val ~= '' then return val end
        end
        return pd.license or pd.citizenid
    else -- standalone
        local src = p.source or p
        if not src then return nil end
        local order = Config.StandaloneIdentifierOrder or { 'license:' }
        local found = {}
        for i = 0, GetNumPlayerIdentifiers(src) - 1 do
            local ident = GetPlayerIdentifier(src, i)
            if ident then
                found[#found+1] = ident
            end
        end
        for _, pref in ipairs(order) do
            for _, ident in ipairs(found) do
                if ident:find(pref, 1, true) == 1 then
                    return ident
                end
            end
        end
        return found[1]
    end
end

local function getPlayerById(src)
    if Config.Framework == 'esx' then
        return ESX and ESX.GetPlayerFromId(src) or nil
    elseif Config.Framework == 'qb' then
        return QBCore and QBCore.Functions.GetPlayer(src) or nil
    else
        -- standalone: create a lightweight shim with .source for identifier extraction
        if GetPlayerName(src) then
            return { source = src }
        end
        return nil
    end
end

local function getPlayerByIdentifier(identifier)
    if not identifier then return nil end
    if Config.Framework == 'esx' then
        return ESX and ESX.GetPlayerFromIdentifier(identifier) or nil
    elseif Config.Framework == 'qb' then
        if not QBCore then return nil end
        local src = QB_Index[identifier]
        if src then
            local p = QBCore.Functions.GetPlayer(src)
            if p then return p end
            QB_Index[identifier] = nil
        end
        for _, id in pairs(QBCore.Functions.GetPlayers() or {}) do
            local p = QBCore.Functions.GetPlayer(id)
            if p then
                local iden = extractIdentifierFromPlayer(p)
                if iden then
                    QB_Index[iden] = id
                    if iden == identifier then
                        return p
                    end
                end
            end
        end
        return nil
    else
        -- standalone: brute force through connected players
        for _, id in ipairs(GetPlayers()) do
            id = tonumber(id) or id
            if GetPlayerName(id) then
                for i=0, GetNumPlayerIdentifiers(id)-1 do
                    local ident = GetPlayerIdentifier(id, i)
                    if ident == identifier then
                        return { source = id }
                    end
                end
            end
        end
        return nil
    end
end

local function cacheOnline(xPlayer)
    local identifier = extractIdentifierFromPlayer(xPlayer)
    if not identifier then return end
    -- Static ID laden, falls nicht vorhanden
    local static_id = Cache.identifierToStatic[identifier]
    if not static_id then
        local rows = selectStaticByIdentifier(identifier)
        if rows then
            local key = usingSeparateTable() and Config.DB.SeparateTablePK or Config.DB.StaticIDColumn
            static_id = tonumber(rows[1][key])
        elseif usingSeparateTable() then
            static_id = insertStaticForIdentifier(identifier)
        end
        if static_id then
            Cache.identifierToStatic[identifier] = static_id
            Cache.staticToIdentifier[static_id] = identifier
            Cache._dirtyStatic = true
        end
    end
    if static_id then
        local dyn
        if Config.Framework == 'esx' then
            dyn = xPlayer.playerId or xPlayer.source
        else
            dyn = (xPlayer.PlayerData and xPlayer.PlayerData.source) or xPlayer.source
        end
        if dyn then
            Cache.staticToDynamic[static_id] = dyn
            Cache.dynamicToStatic[dyn] = static_id
        end
    end
end

-- Spieler aus Online-Cache entfernen
local function uncacheDynamic(dynamicId)
    local static_id = Cache.dynamicToStatic[dynamicId]
    if static_id then
        Cache.dynamicToStatic[dynamicId] = nil
        Cache.staticToDynamic[static_id] = nil
    end
end

-- Vollständigen Cache (identifier <-> static) neu laden
local function refreshFullCache()
    if not Config.EnableCaching then return end
    debugPrint(_U('cache_refresh_start'))
    local rows
    if usingSeparateTable() then
        rows = runSql(('SELECT %s AS identifier, %s AS sid FROM %s LIMIT %d'):format(
            Config.DB.SeparateTableIdentifier, Config.DB.SeparateTablePK, Config.DB.SeparateTableName, Config.MaxRefreshRows), {})
    else
        rows = runSql(('SELECT %s AS identifier, %s AS sid FROM %s LIMIT %d'):format(
            Config.DB.IdentifierColumn, Config.DB.StaticIDColumn, Config.DB.UsersTable, Config.MaxRefreshRows), {})
    end
    if not rows then return end
    local count = 0
    for _, r in ipairs(rows) do
        local identifier = tostring(r.identifier)
        local static_id = tonumber(r.sid)
        if identifier and static_id then
            if Cache.identifierToStatic[identifier] ~= static_id then
                Cache.identifierToStatic[identifier] = static_id
                Cache._dirtyStatic = true
            end
            if Cache.staticToIdentifier[static_id] ~= identifier then
                Cache.staticToIdentifier[static_id] = identifier
                Cache._dirtyStatic = true
            end
            count = count + 1
        end
    end
    debugPrint(_U('cache_refresh_done', count))
end

-- Prune offline Mappings (dynamic)
local function pruneDynamicMappings()
    local removed = 0
    for dynamicId, static_id in pairs(Cache.dynamicToStatic) do
        if not GetPlayerName(dynamicId) then
            uncacheDynamic(dynamicId)
            removed = removed + 1
        end
    end
    if removed > 0 then
        debugPrint(_U('cache_prune_done', removed))
    end
end

-- Periodische Tasks
CreateThread(function()
    if not Config.EnableCaching then return end
    -- Validate schema before doing anything heavy
    validateSchema()
    -- Führe Migration (falls konfiguriert) sehr früh aus
    migrateUsersToSeparate()
    -- Lade persistente Daten bevor initialer Refresh
    loadPersistent()
    refreshFullCache()
    -- Conflict detection thread
    if Config.ConflictDetection and Config.ConflictDetection.Enabled then
        local interval = (Config.ConflictDetection.Interval or 180)
        CreateThread(function()
            while true do
                Wait(interval * 1000)
                local ok, err = pcall(runConflictScan)
                if not ok then
                    print(('^1[StaticID] Conflict scan error: %s^0'):format(err))
                end
            end
        end)
    end
    local refreshTimer = 0
    local pruneTimer = 0
    local saveTimer = 0
    while true do
        Wait(1000)
        refreshTimer = refreshTimer + 1
        pruneTimer = pruneTimer + 1
        saveTimer = saveTimer + 1
        if refreshTimer >= Config.CacheRefreshInterval then
            refreshTimer = 0
            refreshFullCache()
        end
        if pruneTimer >= Config.CachePruneInterval then
            pruneTimer = 0
            pruneDynamicMappings()
        end
        if Config.PersistentCache and Config.PersistentCache.Enabled and saveTimer >= Config.PersistentCache.SaveInterval then
            saveTimer = 0
            savePersistent()
        end
    end
end)

-- Event Hooks
if Config.Framework == 'esx' then
    AddEventHandler('esx:playerLoaded', function(playerId, xPlayer)
        if not Config.EnableCaching then return end
        if Config.InitialPlayerPreload then
            cacheOnline(xPlayer)
            local iden = extractIdentifierFromPlayer(xPlayer)
            debugPrint(_U('preload_player', playerId, iden or 'nil', (iden and Cache.identifierToStatic[iden]) or 'nil'))
        end
    end)
elseif Config.Framework == 'qb' then
    RegisterNetEvent('QBCore:Server:PlayerLoaded', function()
        if not Config.EnableCaching then return end
        if not QBCore then return end
        local src = source
        if Config.InitialPlayerPreload then
            local p = QBCore.Functions.GetPlayer(src)
            cacheOnline(p)
            local iden = extractIdentifierFromPlayer(p)
            debugPrint(_U('preload_player', src, iden or 'nil', (iden and Cache.identifierToStatic[iden]) or 'nil'))
        end
    end)
elseif Config.Framework == 'standalone' then
    AddEventHandler('playerJoining', function(oldId)
        if not Config.EnableCaching then return end
        if Config.InitialPlayerPreload then
            local src = source
            local p = getPlayerById(src)
            if p then
                cacheOnline(p)
                local iden = extractIdentifierFromPlayer(p)
                debugPrint(_U('preload_player', src, iden or 'nil', (iden and Cache.identifierToStatic[iden]) or 'nil'))
            end
        end
    end)
end

AddEventHandler('playerDropped', function()
    local src = source
    uncacheDynamic(src)
    if Config.Framework == 'qb' and QBCore then
    -- Clean index
        for identifier, s in pairs(QB_Index) do
            if s == src then
                QB_Index[identifier] = nil
            end
        end
    end
end)

--[[ Public API functions (use cache, fallback to DB) ]]

function GetClientStaticID(dynamic_id)
    local dyn = asNumber(dynamic_id)
    if not dyn then
        errorParam(_U('invalid_param_dyn'))
        return nil
    end
    if not GetPlayerName(dyn) then return nil end

    -- Try cache first
    local cached = Cache.dynamicToStatic[dyn]
    if cached then return cached end

    local xPlayer = getPlayerById(dyn)
    local identifier = extractIdentifierFromPlayer(xPlayer)
    if not identifier then return nil end

    local static_id = Cache.identifierToStatic[identifier]
    if static_id then
        Cache.dynamicToStatic[dyn] = static_id
        Cache.staticToDynamic[static_id] = dyn
        return static_id
    end

    -- DB lookup
    local rows = selectStaticByIdentifier(identifier)
    if not rows then return nil end
    static_id = tonumber(rows[1][usingSeparateTable() and Config.DB.SeparateTablePK or Config.DB.StaticIDColumn])
    if not static_id and usingSeparateTable() then
        static_id = insertStaticForIdentifier(identifier)
    end
    if static_id then
        Cache.identifierToStatic[identifier] = static_id
        Cache.staticToIdentifier[static_id] = identifier
        Cache.dynamicToStatic[dyn] = static_id
        Cache.staticToDynamic[static_id] = dyn
    end
    return static_id
end

function GetClientDynamicID(static_id)
    local sid = asNumber(static_id)
    if not sid then
        errorParam(_U('invalid_param_static'))
        return nil
    end

    -- Cache (static -> dynamic)
    local dyn = Cache.staticToDynamic[sid]
    if dyn and GetPlayerName(dyn) then return dyn end

    -- Check if identifier present in cache
    local identifier = Cache.staticToIdentifier[sid]
    if not identifier then
    -- Load from DB
        local rows = selectIdentifierByStatic(sid)
        if rows then
            local key = usingSeparateTable() and Config.DB.SeparateTableIdentifier or Config.DB.IdentifierColumn
            identifier = tostring(rows[1][key])
            if identifier then
                Cache.staticToIdentifier[sid] = identifier
                Cache.identifierToStatic[identifier] = sid
            end
        end
    end
    if not identifier then return nil end

        local xPlayer = getPlayerByIdentifier(identifier)
        if not xPlayer then return nil end
        if Config.Framework == 'esx' then
            dyn = xPlayer.playerId or xPlayer.source
        else
            dyn = (xPlayer.PlayerData and xPlayer.PlayerData.source) or xPlayer.source
        end
    if dyn then
        Cache.staticToDynamic[sid] = dyn
        Cache.dynamicToStatic[dyn] = sid
    end
    return dyn
end

function GetIdentifierFromStaticID(static_id)
    local sid = asNumber(static_id)
    if not sid then
        errorParam(_U('invalid_param_static'))
        return nil
    end
    local identifier = Cache.staticToIdentifier[sid]
    if identifier then return identifier end
    local rows = selectIdentifierByStatic(sid)
    if not rows then return nil end
    local key = usingSeparateTable() and Config.DB.SeparateTableIdentifier or Config.DB.IdentifierColumn
    identifier = tostring(rows[1][key])
    if identifier then
        Cache.staticToIdentifier[sid] = identifier
        Cache.identifierToStatic[identifier] = sid
    end
    return identifier
end

function CheckStaticIDValid(static_id)
    local sid = asNumber(static_id)
    if not sid then
        errorParam(_U('invalid_param_static'))
        return nil
    end
    if Cache.staticToIdentifier[sid] then return true end
    local rows
    if usingSeparateTable() then
        rows = runSql(('SELECT 1 FROM %s WHERE %s = ? LIMIT 1'):format(
            Config.DB.SeparateTableName, Config.DB.SeparateTablePK), { sid })
    else
        rows = runSql(('SELECT 1 FROM %s WHERE %s = ? LIMIT 1'):format(
            Config.DB.UsersTable, Config.DB.StaticIDColumn), { sid })
    end
    return rows ~= nil
end

function CheckDynamicIDOnline(dynamic_id)
    local dyn = asNumber(dynamic_id)
    if not dyn then
        errorParam(_U('invalid_param_dyn'))
        return nil
    end
    if not GetPlayerName(dyn) then return false end
        if Config.Framework == 'esx' then
            return ESX and ESX.GetPlayerFromId(dyn) ~= nil
        elseif Config.Framework == 'qb' then
            return QBCore and QBCore.Functions.GetPlayer(dyn) ~= nil
        else
            return GetPlayerName(dyn) ~= nil
        end
end

--[[ Additional helper (identifier based static lookup) ]]--
local function GetStaticIDFromIdentifier(identifier)
    if not identifier or identifier == '' then return nil end
    local sid = Cache.identifierToStatic[identifier]
    if sid then return sid end
    -- DB fallback
    local rows = selectStaticByIdentifier(identifier)
    if rows then
        local key = usingSeparateTable() and Config.DB.SeparateTablePK or Config.DB.StaticIDColumn
        sid = tonumber(rows[1][key])
        if sid then
            Cache.identifierToStatic[identifier] = sid
            Cache.staticToIdentifier[sid] = identifier
        end
    end
    return sid
end

local function SafeGetStaticIDFromIdentifier(identifier)
    if not identifier or identifier == '' then return false, nil, 'invalid_param' end
    local sid = GetStaticIDFromIdentifier(identifier)
    if not sid then return false, nil, 'not_found' end
    return true, sid, nil
end

-- Bulk resolution: accepts table of mixed numeric (dynamic/static) or identifier strings
-- Returns table of entries: { input=*, type='dynamic'|'static'|'identifier', staticId=number|nil, dynamicId=number|nil, identifier=string|nil, online=boolean|nil }
local function BulkResolveIDs(list)
    if type(list) ~= 'table' then return {} end
    local out = {}
    for _, raw in ipairs(list) do
        local entry = { input = raw }
        if type(raw) == 'number' or (type(raw) == 'string' and tonumber(raw)) then
            local num = tonumber(raw)
            -- Try as dynamic first
            local sid = GetClientStaticID(num)
            if sid then
                entry.type = 'dynamic'
                entry.staticId = sid
                entry.dynamicId = num
                entry.identifier = GetIdentifierFromStaticID(sid)
                local online = CheckDynamicIDOnline(num)
                entry.online = online == true
            else
                -- Try as static
                local dyn = GetClientDynamicID(num)
                local identifier = GetIdentifierFromStaticID(num)
                if identifier then
                    entry.type = 'static'
                    entry.staticId = num
                    entry.dynamicId = dyn
                    entry.identifier = identifier
                    if dyn then
                        local online = CheckDynamicIDOnline(dyn)
                        entry.online = online == true
                    end
                else
                    entry.type = 'unknown'
                end
            end
        elseif type(raw) == 'string' then
            -- treat as identifier string
            entry.type = 'identifier'
            local sid = GetStaticIDFromIdentifier(raw)
            if sid then
                entry.staticId = sid
                entry.identifier = raw
                local dyn = GetClientDynamicID(sid)
                if dyn then
                    entry.dynamicId = dyn
                    local online = CheckDynamicIDOnline(dyn)
                    entry.online = online == true
                end
            else
                entry.type = 'identifier'
            end
        else
            entry.type = 'unsupported'
        end
        table.insert(out, entry)
    end
    return out
end

-- Force refresh wrapper (returns true if executed)
local function StaticID_ForceRefresh()
    if not Config.EnableCaching then return false end
    refreshFullCache()
    return true
end

-- Expose core config flags (read-only clone)
local function StaticID_GetConfig()
    local copy = {}
    for k,v in pairs(Config) do
        copy[k] = v
    end
    return copy
end

-- Simple separate table status
local function IsUsingSeparateTable()
    return usingSeparateTable()
end

-- Cache statistics (sizes + dirty flags + last persistence timestamps)
local function GetCacheStats()
    return {
        identifiers = (function() local c=0 for _ in pairs(Cache.identifierToStatic) do c=c+1 end return c end)(),
        statics = (function() local c=0 for _ in pairs(Cache.staticToIdentifier) do c=c+1 end return c end)(),
        dynamicOnline = (function() local c=0 for _ in pairs(Cache.dynamicToStatic) do c=c+1 end return c end)(),
        dirtyStatic = Cache._dirtyStatic,
        dirtyDynamic = Cache._dirtyDynamic,
        lastSave = _persistMeta.lastSave,
        lastLoad = _persistMeta.lastLoad,
        separateTable = usingSeparateTable(),
        persistentEnabled = (Config.PersistentCache and Config.PersistentCache.Enabled) or false
    }
end
 
-- Conflict detection store & functions
local ConflictStore = {
    total = 0,
    records = {}
}

local function recordConflict(identifier, cacheSid, dbSid)
    ConflictStore.total = ConflictStore.total + 1
    table.insert(ConflictStore.records, {
        ts = os.time(),
        identifier = identifier,
        cacheStatic = cacheSid,
        dbStatic = dbSid
    })
    local maxR = (Config.ConflictDetection and Config.ConflictDetection.MaxRecord) or 50
    while #ConflictStore.records > maxR do
        table.remove(ConflictStore.records, 1)
    end
end

function runConflictScan()
    if not (Config.ConflictDetection and Config.ConflictDetection.Enabled) then return end
    local limit = Config.ConflictDetection.SampleSize or 500
    debugPrint(_U('conflict_scan_start', limit))
    local rows
    if usingSeparateTable() then
        rows = runSql(('SELECT %s AS identifier, %s AS sid FROM %s LIMIT %d'):format(
            Config.DB.SeparateTableIdentifier, Config.DB.SeparateTablePK, Config.DB.SeparateTableName, limit), {})
    else
        rows = runSql(('SELECT %s AS identifier, %s AS sid FROM %s LIMIT %d'):format(
            Config.DB.IdentifierColumn, Config.DB.StaticIDColumn, Config.DB.UsersTable, limit), {})
    end
    if not rows then return end
    local conflicts = 0
    local checked = 0
    for _, r in ipairs(rows) do
        local identifier = tostring(r.identifier)
        local dbSid = tonumber(r.sid)
        if identifier and dbSid then
            checked = checked + 1
            local cacheSid = Cache.identifierToStatic[identifier]
            if cacheSid and cacheSid ~= dbSid then
                conflicts = conflicts + 1
                recordConflict(identifier, cacheSid, dbSid)
                TriggerEvent('staticid:conflict', identifier, cacheSid, dbSid)
                print(('^1[StaticID] %s^0'):format(_U('conflict_detected', identifier, tostring(cacheSid), tostring(dbSid))))
            end
        end
    end
    debugPrint(_U('conflict_scan_done', conflicts, checked))
end

--[[
    Safe* Wrapper Layer
    Design Goals:
      * Never returns nil for success flag
      * Uniform tuple style: (ok, value, err)
      * ok:boolean   -> true on success, false on any failure / invalid param
      * value:any    -> resolved data when ok=true, else nil (or false for boolean probes)
      * err:string?  -> machine readable reason (e.g. 'invalid_param', 'offline', 'not_found')
]]

local function SafeGetClientStaticID(dynamic_id)
    local dyn = asNumber(dynamic_id)
    if not dyn then return false, nil, 'invalid_param' end
    if not GetPlayerName(dyn) then return false, nil, 'offline' end
    local sid = GetClientStaticID(dyn)
    if not sid then return false, nil, 'not_found' end
    return true, sid, nil
end

local function SafeGetClientDynamicID(static_id)
    local sid = asNumber(static_id)
    if not sid then return false, nil, 'invalid_param' end
    local dyn = GetClientDynamicID(sid)
    if not dyn then return false, nil, 'not_found_or_offline' end
    return true, dyn, nil
end

local function SafeGetIdentifierFromStaticID(static_id)
    local sid = asNumber(static_id)
    if not sid then return false, nil, 'invalid_param' end
    local identifier = GetIdentifierFromStaticID(sid)
    if not identifier then return false, nil, 'not_found' end
    return true, identifier, nil
end

local function SafeCheckStaticIDValid(static_id)
    local sid = asNumber(static_id)
    if not sid then return false, false, 'invalid_param' end
    local ok = CheckStaticIDValid(sid)
    if ok == nil then return false, false, 'error' end
    return true, ok and true or false, nil
end

local function SafeCheckDynamicIDOnline(dynamic_id)
    local dyn = asNumber(dynamic_id)
    if not dyn then return false, false, 'invalid_param' end
    local ok = CheckDynamicIDOnline(dyn)
    if ok == nil then return false, false, 'error' end
    return true, ok and true or false, nil
end

-- Exports registrieren
exports('GetClientStaticID', GetClientStaticID)
exports('GetClientDynamicID', GetClientDynamicID)
exports('CheckStaticIDValid', CheckStaticIDValid)
exports('CheckDynamicIDOnline', CheckDynamicIDOnline)
exports('GetIdentifierFromStaticID', GetIdentifierFromStaticID)
exports('GetStaticIDFromIdentifier', GetStaticIDFromIdentifier)
exports('SafeGetStaticIDFromIdentifier', SafeGetStaticIDFromIdentifier)
exports('BulkResolveIDs', BulkResolveIDs)
exports('StaticID_ForceRefresh', StaticID_ForceRefresh)
exports('StaticID_GetConfig', StaticID_GetConfig)
exports('IsUsingSeparateTable', IsUsingSeparateTable)
exports('GetCacheStats', GetCacheStats)
exports('GetConflictStats', GetConflictStats)
exports('ClearConflictStats', ClearConflictStats)

exports('SafeGetClientStaticID', SafeGetClientStaticID)
exports('SafeGetClientDynamicID', SafeGetClientDynamicID)
exports('SafeGetIdentifierFromStaticID', SafeGetIdentifierFromStaticID)
exports('SafeCheckStaticIDValid', SafeCheckStaticIDValid)
exports('SafeCheckDynamicIDOnline', SafeCheckDynamicIDOnline)
exports('SafeGetConflictStats', function()
    local ok, res = pcall(GetConflictStats)
    return wrapSafe(ok, res, ok and nil or res)
end)
exports('SafeClearConflictStats', function()
    local ok, res = pcall(ClearConflictStats)
    return wrapSafe(ok, res, ok and nil or res)
end)

exports('StaticID_SaveCache', savePersistent)
exports('StaticID_ClearPersist', clearPersistent)