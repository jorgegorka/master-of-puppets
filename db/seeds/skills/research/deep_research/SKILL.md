---
name: deep_research
description: Multi-step research with cited sources.
category: research
triggers:
  - "research this topic"
  - "do a deep dive on"
  - "investigate and summarize"
security_level: medium
allowed_tools:
  - web_search
  - read_file
---

# Deep research

Run multi-step investigations that combine web search with local notes.

Workflow:
  1. Plan — sketch 3-7 sub-questions before searching anything.
  2. Gather — call `web_search` for each sub-question; pull workspace
     notes with `read_file` when the user has prior context.
  3. Cross-check — corroborate every non-trivial claim with at least
     two independent sources. Note disagreements explicitly.
  4. Synthesize — produce a structured answer with inline citations
     (URL or workspace path) on every factual sentence.

Stop and ask the user when a sub-question is ambiguous or when sources
contradict each other in a way you cannot resolve.
