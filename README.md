# FiveM Static ID Resource

High‑performance, cache-first API for translating between ephemeral (dynamic) player IDs and stable (static/database) IDs. Supports ESX, QBCore, pure standalone mode, and oxmysql — with robust persistence, localization, and integrity tooling.

## Feature Highlights
- O(1) lookups via layered in‑memory cache: identifier ⇄ static_id ⇄ dynamic_id
- Periodic refresh (bounded) & pruning of stale dynamic mappings
- Preload on join for zero-latency first access
- Locales (EN / DE) – easily extend with your own
- Optional persistent snapshot (JSON + checksum) for fast cold starts
- Parameterized SQL everywhere (oxmysql) – minimal injection risk
- Clean, consistent exports & safe (error-coded) wrapper variants
- Modular configuration (`config.lua`) with documented sections
- Optional dedicated `static_ids` table + one-time migration helper
- ESX, QBCore, or fully standalone (identifier prefix priority)
- Conflict detection loop (multi-server divergence guard)
- Bulk resolution helper & rich admin/diagnostic commands
- Client HUD exports: `ShowStaticID` + safe tuple `SafeShowStaticID` + reactive `RegisterStaticIDListener`

## Quick Start
1. Drop the folder into `resources/` (optionally rename to `staticid`).
2. Ensure dependency order in `server.cfg`:
  ```
  ensure oxmysql
  ensure es_extended  # or qb-core
  ensure staticid
  ```
3. (Optional) Enable separate table mode for clean sequential IDs (recommended):
  ```lua
  -- config.lua
  Config.DB.UseSeparateStaticTable = true
  Config.DB.AutoCreateTable = true
  ```
4. In any server script:
  ```lua
  local sid = exports['FiveM-Static-ID']:GetClientStaticID(source)
  ```
5. In any client script (HUD):
  ```lua
  local ok, sid = exports['FiveM-Static-ID']:SafeShowStaticID()
  if ok then print('Static ID', sid) end
  ```
6. See detailed docs below for advanced features (persistence, conflict scan, migration).

For full change history see [`CHANGELOG.md`](./CHANGELOG.md).

## Files
```
fxmanifest.lua
config.lua
shared.lua
commands.lua
locales/de.lua
locales/en.lua
README.md
LICENSE
```

## Installation
1. Clone into your FiveM `resources` directory.
2. (Optional) Rename folder to `staticid` for brevity.
3. In `server.cfg` (adjust for framework actually used):
```
ensure oxmysql
ensure es_extended  # or qb-core if using QBCore
ensure staticid
```

## Server Exports
| Export | Description |
|--------|-------------|
| `GetClientStaticID(dynamicId)` | Returns static ID or nil |
| `GetClientDynamicID(staticId)` | Returns dynamic ID if player online else nil |
| `CheckStaticIDValid(staticId)` | true/false/nil (invalid param) |
| `CheckDynamicIDOnline(dynamicId)` | true/false/nil (invalid param) |
| `GetIdentifierFromStaticID(staticId)` | Returns framework identifier (license/citizenid or ESX identifier) |
| `GetStaticIDFromIdentifier(identifier)` | Returns static ID for a raw framework identifier (license/citizenid) or nil |
| `BulkResolveIDs(table)` | Batch resolve mixed list -> array of result objects |
| `StaticID_ForceRefresh()` | Force immediate cache refresh (returns true if executed) |
| `StaticID_GetConfig()` | Shallow copy of current config table |
| `IsUsingSeparateTable()` | true if separate static_ids table mode is active |
| `GetCacheStats()` | Table with counts, dirty flags, lastSave/lastLoad timestamps |
| `GetConflictStats()` | Conflict scan totals + recent conflict records |
| `ClearConflictStats()` | Clears stored conflict records and resets counter |

## Client Exports
| Export | Description |
|--------|-------------|
| `ShowStaticID()` | Returns cached static ID (number) or nil if not yet resolved |
| `SafeShowStaticID()` | Returns `(ok:boolean, staticId|nil)`; `ok=false` when not ready |
| `RegisterStaticIDListener(cb)` | (Local function) Register callback fired immediately if ID known & on future updates |

Listener notes:
- Register as early as possible (resource start) for immediate push.
- Safe polling fallback: call `SafeShowStaticID()` every second until `ok=true`.

### Safe Wrapper Exports
Uniform return contract: `(ok, value, err)`

| Export | Success (ok=true) value | Failure (ok=false) value | err values |
|--------|-------------------------|---------------------------|------------|
| `SafeGetClientStaticID(dynamicId)` | staticId (number) | nil | `invalid_param`, `offline`, `not_found` |
| `SafeGetClientDynamicID(staticId)` | dynamicId (number) | nil | `invalid_param`, `not_found_or_offline` |
| `SafeGetIdentifierFromStaticID(staticId)` | identifier (string) | nil | `invalid_param`, `not_found` |
| `SafeCheckStaticIDValid(staticId)` | boolean (true/false) | false | `invalid_param`, `error` |
| `SafeCheckDynamicIDOnline(dynamicId)` | boolean (true/false) | false | `invalid_param`, `error` |
| `SafeGetStaticIDFromIdentifier(identifier)` | staticId (number) | nil | `invalid_param`, `not_found` |
| `SafeGetConflictStats()` | stats table | nil | `error` |
| `SafeClearConflictStats()` | true | false | `error` |

Rules:
- `ok` strictly boolean.
- On failure: `value` = nil (or false where a boolean probe), `err` = short machine string.
- Legacy (non-safe) exports unchanged for backward compatibility.

Example (safe wrapper):
```lua
local ok, staticId, err = exports['FiveM-Static-ID']:SafeGetClientStaticID(source)
if not ok then
  if err == 'offline' then
    print('Player offline; cannot resolve static ID')
  else
    print('Static ID lookup failed reason =', err)
  end
else
  print('Static ID is', staticId)
end
```

Example (direct):
```lua
local staticId = exports['FiveM-Static-ID']:GetClientStaticID(source)
if staticId then
  print('Static ID:', staticId)
end
```

## Commands
| Command | Alias | Description |
|---------|-------|-------------|
| `/getstatic [DynID]` | `/gs` | Show static ID for a dynamic ID |
| `/getdynamic [StaticID]` | `/gd` | Show dynamic ID if player online |
| `/staticidhelp` | – | Print quick help to server console |
| `/staticidsave` | – | Force immediate persistent cache save |
| `/staticidclear` | – | Delete persistent cache file |
| `/whois [ID]` | – | Auto-detect dynamic or static and show mapping |
| `/resolve <id1,id2,...>` | – | Batch resolve several IDs (dyn or static) |
| `/staticidinfo` | – | Show framework/mode/persistence info |
| `/staticidconflicts` | – | Show conflict detection summary & recent conflicts (console/admin) |
| `/staticidconflictsclear` | – | Clear stored conflict stats (console/admin) |

## Adding a Locale
Create `locales/<lang>.lua`:
```lua
Locales = Locales or {}
Locales['fr'] = {
  cmd_usage_getstatic = 'Usage: /getstatic [ID dynamique]',
  -- weitere Keys …
}
```
Set `Config.Locale = 'fr'` in `config.lua`.

## Performance Notes
- Hot path fully in-memory (only misses go to DB during refresh cycles).
- Refresh queries capped by `MaxRefreshRows` to avoid large scans.
- Dynamic map pruner keeps memory lean for long runtimes.
- Persistent snapshot removes burst of queries after restart.
- Checksum rejects tampered / truncated snapshot files silently.

## Persistent Cache & Checksum
If enabled, snapshot loads before the first DB refresh (warm cache sooner).

Checksum flow:
1. Save: additive checksum stored under `__checksum` (+ optional dynamic section checksum).
2. Load: recompute & compare; mismatch → snapshot ignored (fails closed, no crash).

Manual save / clear:
```
/staticidsave
/staticidclear
```

`/whois <ID>` logic:
1. Assume dynamic first: resolve → show static, identifier, status.
2. If not a dynamic entry, treat as static ID → show identifier + dynamic (if present).

## Separate Static ID Mode
Default: `users.id` is the stable ID.
Separate mode: isolates static IDs from `users` auto-increment (safer during resets / migrations).

Configuration (`config.lua`):
```lua
Config.DB.UseSeparateStaticTable = true
Config.DB.SeparateTableName = 'static_ids'
Config.DB.SeparateTablePK = 'static_id'
Config.DB.SeparateTableIdentifier = 'identifier'
Config.DB.MigrateUsersOnFirstRun = true -- einmalige Migration (nur wenn Tabelle (fast) leer)
```

SQL migration (included under `sql/static_ids.sql`):
```sql
CREATE TABLE IF NOT EXISTS `static_ids` (
  `static_id` INT NOT NULL AUTO_INCREMENT,
  `identifier` VARCHAR(64) NOT NULL,
  PRIMARY KEY (`static_id`),
  UNIQUE KEY `uniq_identifier` (`identifier`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```

### One-time Migration
When enabled and table nearly empty (<=5 rows): bulk import all distinct identifiers via `INSERT IGNORE`.
After first success: set `MigrateUsersOnFirstRun = false` for faster startups.

Benefits:
- Immunity from `users` auto-increment churn & accidental resets.
- Stable anchor for cross-system references / audit logs.
- Lower coupling to framework schema changes.

Fallback behavior: new player -> row is auto-created lazily on first join.
Persistent cache semantics identical across both modes.

## Framework Switch (ESX / QBCore / Standalone)
In `config.lua` choose:
```lua
Config.Framework = 'esx' -- or 'qb' or 'standalone' or 'auto'
```
If you set `'auto'` the script will probe in priority order (default: ESX → QBCore) and fall back to standalone if neither framework is detected. See the next section "Auto Framework Detection" for details.

Notifications:
- ESX: `esx:showNotification`
- QBCore: `QBCore:Notify`
- Standalone: simple `chat:addMessage` fallback

Identifier extraction:
- ESX: `xPlayer.identifier`
- QBCore: ordered keys via `Config.QB.IdentifierOrder`
- Standalone: prefers `license:` identifier, else first available player identifier

Player lookup differences:
- ESX: `GetPlayerFromId` / `GetPlayerFromIdentifier`
- QBCore: indexed iteration + cache
- Standalone: raw FiveM player list & `GetPlayerIdentifier`

Join events:
- ESX: `esx:playerLoaded`
- QBCore: `QBCore:Server:PlayerLoaded`
- Standalone: `playerJoining`

Recommendation: In standalone mode strongly consider enabling the separate table for resiliency.

### Standalone Identifier Order
Priority list (first existing prefix match wins):
```lua
Config.StandaloneIdentifierOrder = { 'license:', 'fivem:', 'discord:', 'steam:' }
```
Common prefixes: `license:`, `steam:`, `fivem:`, `discord:`.

### Standalone Status Command
`/staticidwarn` prints standalone diagnostics (table mode + identifier order).

### Event: staticid:assigned
Standalone-only: emitted when a new static ID is issued:
```lua
AddEventHandler('staticid:assigned', function(identifier, staticId)
  print(('New static id %d for %s'):format(staticId, identifier))
end)
```

### Event: staticid:conflict
Emitted for every detected divergence (cache vs DB) during a scan:
```lua
AddEventHandler('staticid:conflict', function(identifier, cacheStatic, dbStatic)
  print(('Conflict: %s cache=%d db=%d'):format(identifier, cacheStatic, dbStatic))
end)
```

### QBCore Identifier Order
Config example:
```lua
Config.QB.IdentifierOrder = { 'license', 'citizenid' }
```
First existing wins.

## QBCore Schema Tips
QBCore core player storage often differs from the classic ESX `users` table. This resource only requires a stable numeric static ID and an identifier string.

Recommended approaches:
1. Easiest (portable): enable the separate static table (no schema edits to QB tables).
2. Reuse existing numeric PK: if you already added a custom auto-increment column to `players`, set `Config.DB.StaticIDColumn` to that field and keep `UseSeparateStaticTable=false`.
3. Hybrid migration: start with separate table; later (if you design a global identity table) migrate those static IDs there and just update config keys.

Why separate table is safer:
- Shields against accidental wipes / structure changes during core updates.
- Keeps static IDs monotonically growing and never reused.
- Lets you share the same mapping across ESX/QB/standalone without reassigning IDs.

Example (recommended) static table (already shown earlier):
```sql
CREATE TABLE IF NOT EXISTS `static_ids` (
  `static_id` INT NOT NULL AUTO_INCREMENT,
  `identifier` VARCHAR(64) NOT NULL,
  PRIMARY KEY (`static_id`),
  UNIQUE KEY `uniq_identifier` (`identifier`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```

If you insist on embedding into `players` (NOT advised unless you control migrations):
```sql
ALTER TABLE `players` ADD COLUMN `static_id` INT NOT NULL AUTO_INCREMENT UNIQUE FIRST;
```
Then set in `config.lua`:
```lua
Config.DB.UsersTable = 'players'
Config.DB.StaticIDColumn = 'static_id'
Config.DB.UseSeparateStaticTable = false
```

Diagnostics:
- On startup the script prints schema warnings if expected columns are missing.
- If you see a warning about missing static ID column under QBCore, either enable the separate table or add the column as above.

Migration from embedded to separate table later:
1. Create `static_ids` table.
2. Copy existing pairs: `INSERT INTO static_ids (static_id, identifier) SELECT static_id, license FROM players ON DUPLICATE KEY UPDATE identifier=VALUES(identifier);`
3. Switch config to `UseSeparateStaticTable=true` and remove `StaticIDColumn` reliance.

This keeps all previously assigned numbers intact.

## Auto Framework Detection
Set `Config.Framework = 'auto'` to let the resource decide at runtime which framework is active.

### How Detection Works
1. Reads `Config.AutoFramework.Priority` (default `{ 'esx', 'qb' }`).
2. For each entry it safely probes the corresponding global/export:
   - `esx`: checks the `es_extended` export (`exports['es_extended']`) and major helpers.
   - `qb`: checks the `qb-core` export (`exports['qb-core']`).
3. First successful probe wins → `Config.Framework` is rewritten internally.
4. If none found it uses `Config.AutoFramework.Fallback` (default `'standalone'`).
5. If `Config.AutoFramework.Log` is true a log line prints the decision.

### Example Config Block
```lua
Config.Framework = 'auto'
Config.AutoFramework = {
  Priority = { 'esx', 'qb' }, -- order matters
  Fallback = 'standalone',
  Log = true
}
```

### Overriding Manually
If you force a framework (e.g. `Config.Framework='qb'`) auto detection is skipped entirely.

### Why Use Auto Mode?
- One code artifact deployable across ESX, QBCore, or a lightweight standalone test server.
- Avoids misconfiguration when moving between environments.
- Clean fallback ensures the script still operates (standalone mode) even if a framework fails to load.

### Troubleshooting
If you expected ESX/QB but it falls back to standalone:
- Make sure the framework resource starts BEFORE this resource in `server.cfg`.
- Confirm the resource names (`es_extended`, `qb-core`) are not renamed; if they are, adjust detection (you can patch the code or simply specify the framework explicitly).
- Enable logging (`Config.AutoFramework.Log = true`) to see detection attempts.

If you run a *fork* of ESX/QBCore with different export names, set `Config.Framework` manually.

## Admin Info Command
`/staticidinfo` → framework, separate table flag, persistence state.

### Cache Statistics Example
```lua
local stats = exports['FiveM-Static-ID']:GetCacheStats()
print(('Static=%d Identifiers=%d DynamicOnline=%d Dirty(S/D)=%s/%s LastSave=%s LastLoad=%s Separate=%s Persist=%s')
  :format(
    stats.statics,
    stats.identifiers,
    stats.dynamicOnline,
    tostring(stats.dirtyStatic),
    tostring(stats.dirtyDynamic),
    tostring(stats.lastSave),
    tostring(stats.lastLoad),
    tostring(stats.separateTable),
    tostring(stats.persistentEnabled)
  ))
```

### Bulk Resolve Example
Mixed input set (dynamic, static, raw identifiers):
```lua
local results = exports['FiveM-Static-ID']:BulkResolveIDs({ 12, 77, 'license:1234', 150 })
for _, r in ipairs(results) do
  print(('[%s] type=%s static=%s dynamic=%s identifier=%s online=%s')
    :format(tostring(r.input), r.type, tostring(r.staticId), tostring(r.dynamicId), tostring(r.identifier), tostring(r.online)))
end
```

## Error Handling
- Invalid parameters produce consistent `[StaticID]` log lines.
- SQL failures trapped via pcall and logged (no hard crash).

## License
MIT – see `LICENSE`.

## Credits
Author: Simple

German locale included (`locales/de.lua`).
PRs, suggestions & issues welcome.

## Client HUD Integration (ShowStaticID / SafeShowStaticID)
The resource now exposes lightweight client exports for HUD/UI scripts.

### Quick Access
```lua
local sid = exports['FiveM-Static-ID']:ShowStaticID()
if sid then
  DrawTxt(('Static ID: %d'):format(sid), 0.50, 0.95)
end
```

### Safe Tuple Variant
```lua
local ok, sid = exports['FiveM-Static-ID']:SafeShowStaticID()
if ok then
  print('My static ID =', sid)
else
  print('Static ID not yet assigned (still loading?)')
end
```

### Change Listener (Reactive HUD Update)
Inside a client script in the SAME resource (or adapt with an event wrapper):
```lua
RegisterStaticIDListener(function(id)
  print('Static ID became available:', id)
  -- e.g. update NUI frame, set a global, etc.
end)
```

### Full Minimal HUD Example
Create a client script (or extend an existing one):
```lua
local display = ''

-- React as soon as the ID is known
RegisterStaticIDListener(function(id)
  display = ('Static ID: %d'):format(id)
end)

-- Fallback poll (in case listener registered after initial push)
CreateThread(function()
  local tries = 0
  while display == '' and tries < 30 do
    local ok, sid = exports['FiveM-Static-ID']:SafeShowStaticID()
    if ok then
      display = ('Static ID: %d'):format(sid)
      break
    end
    tries = tries + 1
    Wait(1000)
  end
end)

-- Simple 2D text draw helper
local function drawTxt(text, x, y)
  SetTextFont(0)
  SetTextProportional(1)
  SetTextScale(0.3, 0.3)
  SetTextColour(255, 255, 255, 180)
  SetTextEntry('STRING')
  SetTextCentre(true)
  AddTextComponentString(text)
  DrawText(x, y)
end

CreateThread(function()
  while true do
    Wait(0)
    if display ~= '' then
      drawTxt(display, 0.50, 0.95)
    end
  end
end)
```

### Implementation Details
- Server sends `staticid:client:set` with the player's static ID after first resolution.
- Client requests it on startup via `staticid:server:requestStaticID` for restart resilience.
- `ShowStaticID()` returns the cached number or `nil` if not assigned yet.
- `SafeShowStaticID()` normalizes to `(ok:boolean, value|nil)` for consistency with other Safe exports.

### Common Pitfalls
- If you call the export too early (before server push), you'll get `nil` / `ok=false` — use a listener or poll with a short backoff.
- Ensure this resource starts after your framework and oxmysql in `server.cfg`.
- Do NOT cache the return of `exports[...]` function itself; call it each time or store the numeric result.

### NUI Integration Sketch
In a NUI-focused resource, forward the value to JS once:
```lua
RegisterStaticIDListener(function(id)
  SendNUIMessage({ type = 'staticid', value = id })
end)
```
Then in your JS:
```js
window.addEventListener('message', (e) => {
  if (e.data.type === 'staticid') {
  document.getElementById('static-id').textContent = e.data.value;
  }
});
```

