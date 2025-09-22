Config = {}

--[[
 =============================================================================
    CORE FRAMEWORK MODE
    'esx'        -> uses ESX xPlayer.identifier
    'qb'         -> uses QBCore PlayerData (order defined below)
    'standalone' -> pure FiveM (license:/steam:/discord:/fivem:) – no ESX/QB dependency
    'auto'       -> detect at runtime (es_extended export? -> ESX, qb-core export? -> QB, else standalone)
 =============================================================================
]]
Config.Framework = 'esx' -- set to 'auto' to enable automatic detection

-- Auto framework detection preferences (only used when Config.Framework == 'auto')
Config.AutoFramework = {
    Priority = { 'esx', 'qb', 'standalone' }, -- order to test
    Log = true,          -- print detection result
    Fallback = 'standalone' -- fallback if none found
}

-- QBCore: priority order for picking the stable identifier from PlayerData.
-- First existing entry wins. Keep list short & deterministic.
Config.QB = {
    IdentifierOrder = { 'license', 'citizenid' }
}

-- Standalone: ordered prefix list (first match wins). Adjust to your environment.
-- Common prefixes: 'license:', 'fivem:', 'discord:', 'steam:'
Config.StandaloneIdentifierOrder = { 'license:', 'fivem:', 'discord:', 'steam:' }

--[[
 =============================================================================
  CONFLICT DETECTION (Multi-server safety)
  Periodically samples DB rows and compares with in-memory cache to spot
  divergent mappings (e.g., two nodes assigning different static IDs).
 =============================================================================
]]
Config.ConflictDetection = {
    Enabled = false,      -- master switch for scanning
    Interval = 180,       -- seconds between scans
    SampleSize = 500,     -- max DB rows sampled per scan (LIMIT)
    MaxRecord = 50        -- store only last N detected conflicts in memory
}

--[[
 =============================================================================
  CACHE & REFRESH SETTINGS
 =============================================================================
]]
Config.EnableCaching = true            -- disable only for debugging / fallback
Config.InitialPlayerPreload = true     -- resolve static ID as soon as player loads
Config.CacheRefreshInterval = 60       -- full identifier/static mapping refresh cadence
Config.CachePruneInterval = 300        -- prune dynamic (online) mappings for disconnected players
Config.Debug = false                   -- verbose internal logging

-- Locale: 'en' or 'de' (extendable via locales/*.lua)
Config.Locale = 'en'

-- Notification default display time (ms) for frameworks supporting duration
Config.NotifyDuration = 3500

-- Safety cap: maximum rows fetched per periodic refresh
Config.MaxRefreshRows = 5000

--[[
 =============================================================================
  PERSISTENT CACHE (Disk snapshot to reduce cold-start DB hits)
 =============================================================================
  Enabled: writes a JSON file containing identifier<->static mappings.
  IncludeDynamic: rarely needed; dynamic (online session) data is volatile.
  UseChecksum: simple additive checksum to reject corrupted files automatically.
  SkipIfClean: avoids disk writes when nothing changed.
 =============================================================================
]]
Config.PersistentCache = {
    Enabled = true,
    FileName = 'resources/FiveM-Static-ID/cache_staticid.json', -- relative to resource root
    SaveInterval = 120,               -- seconds between auto-saves
    IncludeDynamic = false,           -- persist dynamic (session) mappings too
    UseChecksum = true,
    SkipIfClean = true,
    SeparateDynamicChecksum = true    -- independent checksum section if dynamic stored
}

--[[
 =============================================================================
  DATABASE SCHEMA
  Default assumes ESX-style `users` table where `id` is the static ID.
    QBCore: by default you typically store core identifiers (license / citizenid)
    in its own player tables (e.g. `players` or `players_meta`). This script only
    needs a stable numeric static ID; you can either:
        * Re-use an existing numeric primary key (if guaranteed not to reset), OR
        * Enable the separate static table below (recommended for portability).

    Separate table mode decouples static IDs from user auto-increment resets and
    makes migrations safer across frameworks (ESX <-> QBCore <-> standalone).

    QBCore Example (if enabling separate table):
        CREATE TABLE IF NOT EXISTS `static_ids` (
            `static_id` INT NOT NULL AUTO_INCREMENT,
            `identifier` VARCHAR(64) NOT NULL,
            PRIMARY KEY (`static_id`),
            UNIQUE KEY `uniq_identifier` (`identifier`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
 =============================================================================
]]
Config.DB = {
    UsersTable = 'users',
    IdentifierColumn = 'identifier',
    StaticIDColumn = 'id',

    -- Separate static ID table mode (enabled to guarantee clean sequential assignment 1,2,3,...)
    UseSeparateStaticTable = false,
    SeparateTableName = 'static_ids',
    SeparateTablePK = 'static_id',
    SeparateTableIdentifier = 'identifier',
    -- Automatically create the separate table if missing on startup
    AutoCreateTable = false,
    -- Print an additional green colored console line for each new static ID assignment (besides debugPrint)
    ColorAssignLog = true,

    -- One-time migration (only when table is near-empty). Copies unique identifiers
    -- from UsersTable into SeparateTable. Disable after initial adoption.
    MigrateUsersOnFirstRun = true
}
--[[
 Auto-adjustment note:
 If QBCore is selected and the default ESX table name is still present, switch to
 the conventional 'players' table. Warn if no numeric static ID column likely exists.
 (Must run BEFORE the final return; Lua does not allow statements after a top-level return.)
]]
if Config.Framework == 'qb' and not Config.DB.UseSeparateStaticTable then
    if Config.DB.UsersTable == 'users' then
        Config.DB.UsersTable = 'players'
        print('^3[StaticID] QBCore detected: set Config.DB.UsersTable="players" (was "users").^0')
    end
    if Config.DB.StaticIDColumn == 'id' then
        print('^3[StaticID] QBCore note: default players table usually has no numeric "id" column. Enable UseSeparateStaticTable=true OR add a numeric column and update Config.DB.StaticIDColumn.^0')
    end
end

return Config
