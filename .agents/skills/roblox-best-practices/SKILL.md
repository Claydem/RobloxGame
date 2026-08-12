---
name: roblox-best-practices
description: Industry-standard best practices, security guidelines, modern Luau optimizations, and Rojo architectural patterns for Roblox development.
---

# Roblox & Luau Development Best Practices

This skill provides the core architectural patterns, security guardrails, and coding conventions for building high-quality, performant, and secure Roblox experiences.

---

## 1. 🛡️ Server-Authoritative Architecture & Trust Boundary

### Golden Rule: Never Trust the Client
* **Server Authority:** The server has the final say on all gameplay state: currency, inventory, stats, health, damage, and level progression.
* **Client Role:** The client is purely for presentation: rendering UI, playing animations, emitting visual particles, playing sounds, and capturing user input.
* **Remote Security:**
  * Always validate arguments passed to `RemoteEvent` and `RemoteFunction` on the server (check types, non-nil, reasonable bounds).
  * Implement server-side debounce / cooldown checks on any actionable Remote (e.g. attack requests, purchases, item usage).
  * Never pass a currency amount or health value directly from the client to be applied by the server.

```lua
-- ❌ BAD: Client tells server how much damage it dealt
DamageRemote.OnServerEvent:Connect(function(player, targetHumanoid, damageAmount)
    targetHumanoid:TakeDamage(damageAmount)
end)

-- ✅ GOOD: Client requests attack action; server computes damage and validates
AttackRemote.OnServerEvent:Connect(function(player, targetUnitUUID, attackZone)
    if not canAttack(player) then return end
    local damage = calculateServerAuthoritativeDamage(player, targetUnitUUID, attackZone)
    applyDamage(targetUnitUUID, damage)
end)
```

---

## 2. ⚡ Modern Luau Standards & Performance

### Modern Task Library
* **Always use the `task` library:**
  * Use `task.wait(n)` instead of `wait(n)` (faster resumption, frame-aligned 60Hz/variable refresh).
  * Use `task.spawn(fn)` instead of `spawn(fn)` (no 1-2 frame delay, instant execution).
  * Use `task.delay(n, fn)` instead of `delay(n, fn)`.
  * Use `task.cancel(thread)` to abort background threads cleanly.

### Luau Typing & Code Quality
* Use type annotations where beneficial (`--!strict` or `--!nonstrict`).
* Define explicit type aliases for data structures (e.g., `type UnitData = { UUID: string, ItemId: string, Class: string, Level: number }`).
* Use `table.create(size)` or `table.clone(tbl)` for performance when dealing with large arrays.

### Memory Leak Prevention
* Always clean up `RBXScriptConnection` instances using `:Disconnect()` when objects or GUIs are destroyed.
* On respawn or UI reload, clean up duplicate or stale `ScreenGui` instances from `PlayerGui`.

---

## 3. 💾 DataStore Resilience & Session Caching

### Session-Based In-Memory Caching
* Keep active player state in a server-side Lua table (`sessionData[player]`).
* Read and modify state from memory synchronously during gameplay.
* Only communicate with `DataStoreService` on `PlayerAdded` (load), `PlayerRemoving` (save), and `game:BindToClose` (shutdown safety).

### Error Handling & Retries
* Always wrap DataStore calls (`GetAsync`, `SetAsync`, `UpdateAsync`) in `pcall`.
* Implement retry logic with exponential backoff for failed network requests.
* Use `game:BindToClose()` to ensure data is saved when the server shuts down or crashes.

```lua
game:BindToClose(function()
    for _, player in ipairs(Players:GetPlayers()) do
        saveData(player)
    end
end)
```

---

## 4. 📁 Rojo Project Structure & File Conventions

* **Server scripts:** Named `*.server.lua`, placed in `src/ServerScriptService/`.
* **Client scripts:** Named `*.client.lua`, placed in `src/StarterGui/` or `src/StarterPlayerScripts/`.
* **Shared modules:** Named `*.lua`, placed in `src/ReplicatedStorage/Modules/`.
* **Remote management:** Centralized in a single service initialization module or `ReplicatedStorage.Events` folder.
