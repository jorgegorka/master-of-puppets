---
name: code_review
description: Review code for correctness, style, and clarity.
category: review
triggers:
  - "review this code"
  - "code review"
  - "what do you think of this diff"
security_level: safe
allowed_tools:
  - read_file
  - list_dir
---

# Code review

Read the target files end-to-end before commenting. Use `read_file` to
pull each file at the revision the user pointed at, and `list_dir` to
locate related modules, tests, and call sites.

Report findings as a structured list with three buckets:
  1. Correctness — bugs, race conditions, off-by-ones, missing tests.
  2. Style — naming, organization, idioms for the language at hand.
  3. Clarity — comments, dead code, public API ergonomics.

Quote the offending lines verbatim with a file:line reference. Suggest a
concrete patch when you can. Do not invent issues to fill space — say
"looks good" when it does.
