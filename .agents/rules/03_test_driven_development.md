# Test-Driven Development & Self-Verification for Roblox

## 1. TDD Workflow for Luau
- Write or update `.spec.luau` tests alongside code changes.
- Ensure RemoteEvents validate all edge cases (nil, -1, NaN, oversized strings).

## 2. LLM-as-a-Verifier Self-Verification Protocol
Apply and visibly report the 5-point verification check before completing every task:
1. **Contract & Types**: `--!strict` Luau annotations and runtime parameter assertions.
2. **Boundary Stress**: Zero, negative, nil, empty table, and rapid click spam resistance.
3. **Concurrency & Re-entrancy**: Race-condition protection, atomic mutations, no duplicate payouts.
4. **Memory Lifecycle**: All `RBXScriptConnection` signals cleaned up via Maid/Janitor.
5. **Terminal & Sync Status**: Clean Rojo sync and linter checks with zero warnings.

The agent MUST include a dedicated `### 🛡️ Результати самоверифікації (Self-Verification)` block in the delivery walkthrough.
