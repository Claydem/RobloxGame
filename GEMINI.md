# Google Antigravity Master Engineering Directives

> **Scope**: Applies to all conversations, autonomous agents, and subagent orchestrations within this workspace.

---

## 1. Core Operating Principles

1. **Zero Hallucination & Fact Grounding**:
   - Always verify facts, file paths, API contracts, and command outputs before making assertions or edits.
   - If a detail is missing or ambiguous, check the codebase or official documentation; do not invent APIs or schemas.

2. **Defensive Programming & Precision**:
   - Every modification must be minimal, complete, and non-destructive.
   - Preserve existing architecture, formatting, comments, and style conventions unless explicitly instructed otherwise.
   - Never replace whole files when targeted replacements (`replace_file_content` / `multi_replace_file_content`) are appropriate.

3. **Autonomous Self-Verification (LLM-as-a-Verifier Protocol)**:
   - Apply fine-grained criteria decomposition (Contract Invariants, Boundary Stress, State Integrity, Security).
   - Perform adversarial self-refutation before declaring completion.
   - Run the project's tests, linters, and type checkers in the terminal. Never mark a task as completed with failing tests, broken types, or unverified edge cases.

4. **Progressive Disclosure & Context Economy**:
   - Avoid dumping large files or whole directory trees into context when specific lookups (`grep_search`, `view_file` with line slices) suffice.
   - Use specialized skills on-demand rather than preloading all reference docs into active prompt context.

5. **Subagent Specialization**:
   - Offload heavy research, isolated test fixing, or parallel evaluations to specialized subagents using appropriate models (`flash` for light search/reads, `pro` for architectural planning and multi-file refactoring).

---

## 2. Standard Default Operating Workflow (MANDATORY FOR ALL TASKS)

```
[User Request] 
      │
      ▼
[Phase 1: Prompt Architecture & Formulation] ──► (Formulate clear XML spec with constraints & STOP to ask for User Approval)
      │
      ▼ (User Approves / Adjusts)
[Phase 2: Execution & Clean Implementation] ──► (Apply clean, targeted, anti-exploit code changes in Luau/Rojo)
      │
      ▼
[Phase 3: Autonomous Critic & Evaluator Loop] ──► (Run Critic Evaluator 10-point rubric; auto-fix if < 9/10)
      │
      ▼
[Phase 4: Self-Verification (LLM-as-a-Verifier)] ──► (5-point boundary stress test & terminal verification)
      │
      ▼
[Phase 5: Final Delivery & Walkthrough] ──► (Document verified changes, diffs, and validation results)
```

---

## 3. Tool Usage Policy

- **File Modifications**: Always use precise file editing tools with exact character matching.
- **Terminal Execution**: Use explicit, non-interactive commands. Never run blocking interactive commands without appropriate flags or background handlers.
- **Artifacts**: Use structured Markdown artifacts (`.md`) for plans, architecture blueprints, research reports, and walkthroughs.

---

## 4. Hierarchy of Rules & Overrides

1. Active User Instructions (Current Prompt)
2. Workspace / Project Rules (`.agents/rules/*.md`)
3. Root Rules (`GEMINI.md` / `AGENTS.md`)
4. Global Antigravity Defaults
