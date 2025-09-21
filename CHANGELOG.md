# FiveM-Static-ID Changelog

All notable changes to this resource will be documented in this file.

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