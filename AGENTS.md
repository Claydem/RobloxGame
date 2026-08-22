# Agent Operational Rules & Standards for Roblox (Brainrot Case Fight Club)

## Mandatory 5-Phase Operating Pipeline
Whenever receiving a user request, you MUST ALWAYS follow this exact pipeline:
1. **Phase 1: Prompt Specification & Formulation**:
   - Stop and transform the user's raw prompt into a structured XML specification (`<goal>`, `<context>`, `<constraints>`, `<invariants>`).
   - Present this specification directly to the user and **WAIT for explicit user approval ("Апрув", "ОК", "Так") before making any code modifications**.
2. **Phase 2: Clean Implementation**:
   - Write strict Luau (`--!strict`), server-authoritative logic, RemoteEvent parameter validation, ProfileService/DataStore2 transaction safety.
3. **Phase 3: Autonomous Critic & Evaluator Loop**:
   - Run the Critic Evaluator against the 10-point Anthropic rubric (checking for race conditions, exploit vulnerabilities, memory leaks via Maid/Janitor). Auto-fix if score < 9/10.
4. **Phase 4: Self-Verification (LLM-as-a-Verifier)**:
   - Perform 5-point invariant checks (nil/empty stress testing, boundary values, non-regression).
5. **Phase 5: Final Delivery**:
   - Deliver verified code ready for synchronization via `rojo serve`.
