---
name: self-verifier
description: >-
  Executes fine-grained self-verification, criteria decomposition, and adversarial sanity checks
  based on the LLM-as-a-Verifier framework (SOTA benchmark on Terminal-Bench & SWE-Bench).
  Use before completing tasks, during complex refactorings, or when validating mission-critical logic.
---

# LLM-as-a-Verifier & Self-Verification Skill

This skill applies the **LLM-as-a-Verifier** methodology to validate agent solutions, eliminate silent regressions, and systematically catch edge-case bugs without human intervention.

## 1. The 3 Pillars of Verification Scaling
- Criteria Decomposition (Functional, Boundary, State, Security)
- Adversarial Self-Refutation (Probing hidden bugs)
- Empirical Terminal Verification (Running real commands & exit codes)

## 2. Verification Protocol
1. **Contract Invariant**: Do outputs, return types, and exceptions match the exact specification under all input domains?
2. **Boundary Stress**: What happens when input is empty ("", [], nil, {}), maximum size, negative, malformed, or concurrent?
3. **Execution State Integrity**: Are database transactions rolled back on error? Are memory buffers, file descriptors, and connections closed?
4. **Non-Regression**: Does this change break any existing caller or API consumer?
