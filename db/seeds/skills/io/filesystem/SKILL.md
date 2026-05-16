---
name: filesystem
description: Read and write files in the workspace, list directories.
category: io
triggers:
  - "read the file"
  - "list the directory"
  - "open the file"
  - "save to disk"
security_level: safe
allowed_tools:
  - read_file
  - write_file
  - list_dir
---

# Filesystem

You can read and write files inside the workspace using the `read_file`,
`write_file`, and `list_dir` tools. Prefer relative paths anchored at the
workspace root; never escape it with `..` segments or absolute paths
outside the workspace.

When asked to modify a file, read it first to confirm its current contents
before writing — overwrites are not journaled. When listing directories,
limit the depth you walk; the workspace can grow large.
