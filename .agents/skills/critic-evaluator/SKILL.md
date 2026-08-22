---
name: critic-evaluator
description: >-
  Acts as an independent adversarial critic and evaluator based on Anthropic's Evaluator-Optimizer agentic pattern.
  Grades code, architectures, and solutions against a rigorous 10-point rubric and drives iterative self-improvement.
  Use when conducting deep adversarial reviews, stress-testing implementations, or running critic loops.
---

# Critic & Evaluator Skill (Anthropic Evaluator-Optimizer Pattern)

This skill operationalizes the official **Evaluator-Optimizer** workflow from Anthropic. It functions as an autonomous critic that prevents confirmation bias and enforces rigorous quality standards.

## 1. Evaluation Dimensions (Anthropic Rubric)
1. Strict Typing & Contracts (--!strict, parameter validation)
2. Boundary & Anti-Exploit (handling nil, -1, spoofed client packets)
3. Concurrency & Race-Safety (atomic operations, double-spend prevention)
4. Resource & Memory Cleanup (Maid/Janitor connection disconnection)
5. Clean Architecture & Modularity
