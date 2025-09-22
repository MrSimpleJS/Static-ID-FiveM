# FiveM-Static-ID Changelog

All notable changes to this resource will be documented in this file.

## [1.1.2] - 2025-09-22
### Added
- Client safe export `SafeShowStaticID` returning `(ok, value)` for parity with server Safe* style.
- README: Quick Start section, Client Exports table, HUD integration examples, NUI sketch.

### Changed
- Feature highlights updated to list client HUD exports & listener.

### Notes
- `SafeShowStaticID` returns `ok=false` while static ID not yet resolved (pre-push phase).
- No server logic changes required; piggybacks on existing push/request events.

## [1.1.1] - 2025-09-22
### Added
- Client helper script `client/staticid_client.lua` maintaining local `CurrentStaticID`.
- Server -> client push on first resolution plus on-demand request event `staticid:server:requestStaticID`.
- Client export `ShowStaticID` returning the player's static ID (or nil if not yet assigned).
- Lightweight listener registration function `RegisterStaticIDListener(cb)` for HUD scripts (fires immediately if ID already known).

### Usage
- From any client script: `local sid = exports['FiveM-Static-ID']:ShowStaticID()`
- Optionally register for updates (within same resource): `RegisterStaticIDListener(function(id) ... end)`

### Notes
- Static ID is pushed automatically after server-side `cacheOnline()` resolves it.
- Clients request the ID on resource start to cover restarts / late loads.

## [1.1.0] - 2025-09-22
### Added
- Config flags: `Config.DB.AutoCreateTable`, `Config.DB.ColorAssignLog`.
- Automatic creation of separate `static_ids` table (guarded by `AutoCreateTable`).
- Green console log for each new static ID (if `ColorAssignLog=true`).
- Export: `StaticID_ResetStaticTable` to truncate table, clear caches & persistent file.
- Admin command: `/staticidreset` (console or admin) to invoke reset export.
- Verbose persistent cache load log: shows file, counts, checksum status.
- Pretty-print option for persisted JSON (`Config.PersistentCache.PrettyPrint`).

### Changed
- Moved `shared.lua` to `server_scripts` to ensure oxmysql is loaded before schema validation.
- All internal comments unified to English for consistency.
- Improved assignment logging includes identifier and new static ID.
- Strengthened schema validation with optional auto table ensure block.

### Fixed
- Early "users table not reachable" warnings caused by load order (resolved by script relocation).
- Potential silent confusion around sequential ID guarantees by enabling separate table mode & explicit comments.

### Migration Notes
- To restart numbering: run `/staticidreset` (separate table mode only).
- If you previously relied on `users.id`, set `UseSeparateStaticTable=true` for deterministic sequential assignment.

### Integrity / Safety
- Reset export removes persisted file to avoid stale mappings after table truncate.
- Checksums still enforced on load; dynamic section optionally validated separately.


## [1.0.1] - 2025-09-21
### Fixed
- Lua syntax error in `config.lua` caused by executable code placed after `return Config` (moved QBCore auto-adjust block before return).
- Runtime error in `shared.lua` (`attempt to call a nil value (global 'usingSeparateTable')`) by defining `usingSeparateTable()` before first usage in `validateSchema`.

### Improved
- Added explanatory comment in `config.lua` clarifying why framework auto-adjust must occur before the return.
- Minor internal ordering for schema helper to avoid future nil global issues.

## [1.0.0] - 2025-09-20
### Added
- Initial release of Static ID system with:
  - Framework abstraction (ESX / QBCore / Standalone / Auto-detect)
  - Identifier <-> static ID cache & persistence (optional JSON snapshot with checksum)
  - Separate static ID table support & one-time migration helper
  - Conflict detection (optional periodic scan)
  - Public exports for resolving static/dynamic IDs and identifiers
  - Locale support (en/de scaffolding)
  - Admin / utility commands (`/getstatic`, `/getdynamic`, `/whois`, `/resolve`, `/staticidinfo`, etc.)