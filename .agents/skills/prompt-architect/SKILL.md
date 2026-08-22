---
name: prompt-architect
description: >-
  Transforms raw user requirements into state-of-the-art structured prompts using Anthropic's XML-tagging methodology.
  Always presents the optimized prompt to the user for explicit review and approval before execution.
  Use when designing prompts for AI features, system prompts, or complex multi-step reasoning workflows.
---

# Prompt Architect Skill (Anthropic Standard)

This skill designs production-grade, highly structured prompts optimized for modern reasoning models following the official Anthropic Claude Academy guidelines.

> [!IMPORTANT]
> **Approval Rule**: The agent MUST NEVER execute the generated prompt immediately.
> 1. Formulate the complete XML-structured prompt.
> 2. Present it clearly to the user under a dedicated `# Запропонований структурований промпт` section.
> 3. WAIT for user approval/refinement before applying it.
