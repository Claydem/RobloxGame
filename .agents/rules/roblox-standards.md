# Roblox / Luau Development Rules

## Core Guidelines for AI Assistant:

1. **Security (Server-Authoritative):**
   - Never trust client inputs. Always validate and sanitize parameters passed through `RemoteEvent` and `RemoteFunction`.
   - Never allow the client to dictate currency amounts, health changes, or inventory states directly.

2. **Modern Luau Practices:**
   - Always use `task.wait()`, `task.spawn()`, and `task.delay()` instead of deprecated `wait()`, `spawn()`, `delay()`.
   - Use `pcall` on all external/engine service calls (DataStoreService, InsertService, HttpService).
   - Write clean, modular Luau code following single-responsibility principles.

3. **DataStore Resilience:**
   - Always use session-based caching (`sessionData[player]`) for active player sessions.
   - Always bind shutdown handlers via `game:BindToClose()` to save state for all online players before server termination.

4. **UI & Lifecycle Hygiene:**
   - Manage duplicate UI instances on character respawn (clean up duplicate `ScreenGui` elements).
   - Clean up event connections (`:Disconnect()`) when destroying UI components to prevent memory leaks.

5. **Rojo Compatibility:**
   - Respect `.server.lua`, `.client.lua`, and `.lua` extension conventions.
   - Ensure all module require paths align with `default.project.json`.
