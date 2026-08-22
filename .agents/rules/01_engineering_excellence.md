# Engineering Excellence for Roblox & Luau

## 1. Zero Trust & Anti-Exploit Principles
- Never trust client inputs. Validate all RemoteEvent and RemoteFunction arguments on the server.
- Enforce strict server-side rate limits on remote calls.
- Currency, inventory additions, teleportation, and stat mutations must ONLY occur on the server.

## 2. Type Safety & Clean Code
- Add `--!strict` to the top of all Luau scripts.
- Use explicit type annotations for tables, signals, and service return types.
- Follow single responsibility principle per module.

## 3. Data Persistence
- Use ProfileService / DataStore2 with session-locking.
- Wrap all DataStore operations in `pcall` and exponential backoff handlers.
