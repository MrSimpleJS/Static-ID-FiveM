fx_version 'cerulean'
lua54 'on'
game 'gta5'

author 'Simple'
description 'Statische ID Abfrage API'
version '1.1.2'
license 'MIT'

-- Client Scripts
client_scripts {
    'client/staticid_client.lua'
}

shared_scripts {
    '@es_extended/imports.lua',
    'config.lua',
    'locales/de.lua',
    'locales/en.lua'
}

-- NOTE: shared.lua moved to server_scripts to ensure oxmysql loads BEFORE schema validation.
-- This prevents early "users table not reachable" warnings caused by MySQL global not existing yet.
server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'shared.lua',
    'commands.lua'
}

-- Core direct exports
server_export 'GetClientStaticID'
server_export 'GetClientDynamicID'
server_export 'CheckStaticIDValid'
server_export 'CheckDynamicIDOnline'
server_export 'GetIdentifierFromStaticID'
server_export 'GetStaticIDFromIdentifier'
server_export 'BulkResolveIDs'
server_export 'StaticID_ForceRefresh'
server_export 'StaticID_GetConfig'
server_export 'IsUsingSeparateTable'
server_export 'GetCacheStats'
server_export 'GetConflictStats'
server_export 'ClearConflictStats'
server_export 'StaticID_ResetStaticTable'

-- Safe wrapper exports (return ok,value,err)
server_export 'SafeGetClientStaticID'
server_export 'SafeGetClientDynamicID'
server_export 'SafeCheckStaticIDValid'
server_export 'SafeCheckDynamicIDOnline'
server_export 'SafeGetIdentifierFromStaticID'
server_export 'SafeGetStaticIDFromIdentifier'
server_export 'SafeGetConflictStats'
server_export 'SafeClearConflictStats'

-- (Optional) allow accessing from client scripts if ever needed
export 'GetClientStaticID'
export 'GetClientDynamicID'
export 'CheckStaticIDValid'
export 'CheckDynamicIDOnline'
export 'GetIdentifierFromStaticID'
export 'GetStaticIDFromIdentifier'
export 'BulkResolveIDs'
export 'GetCacheStats'
export 'GetConflictStats'
export 'SafeGetClientStaticID'
export 'SafeGetClientDynamicID'
export 'SafeCheckStaticIDValid'
export 'SafeCheckDynamicIDOnline'
export 'SafeGetIdentifierFromStaticID'
export 'SafeGetStaticIDFromIdentifier'
export 'SafeGetConflictStats'
export 'ShowStaticID'
export 'SafeShowStaticID'
