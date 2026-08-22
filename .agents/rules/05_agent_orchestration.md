# Multi-Agent Orchestration & Subagent Delegation Directives for Roblox

## 1. Mandatory Visible Critic & Review (Phase 3)
For every feature implementation, script update, or bug fix:
- The primary agent MUST explicitly invoke a visible Critic subagent (`invoke_subagent` with `Role: "Critic Evaluator"`, `TypeName: "self"`, `Model: "inherit"`).
- The Critic subagent evaluates the Luau code against:
  1. Client-Server Security & Anti-Exploit (strict argument validation on RemoteEvents)
  2. Memory Leaks (Maid / Janitor connection disconnection)
  3. DataStore / ProfileService transactional safety
  4. Luau `--!strict` typing
  5. Clean modular architecture
- Score must be >= 9/10 before task delivery.

## 2. Model Selection Guidelines
- **Strict User Preference (`Model: "inherit"`)**: All subagents run on the exact model chosen by the user in the UI selector (Gemini Flash High, Claude Opus, Gemini Pro).
