# Bash design

- Give each distinct workflow step its own function.
- Keep step functions focused, coherent, while avoiding excessive fragmentation.
- Define `main()` at the top to coordinate workflow and end the file with `main "$@"`.
- Put a brief comment immediately above each non-trivial function describing its purpose or side effects.
- Store multi-flag option lists in arrays with one option (and its argument, if any) per line, e.g.:

```bash
local -a curl_opts=(
  --fail
  --silent
  --output "$dest"
)
```

- In executable scripts, apply these settings before sourcing helpers. Limit any override to the operation that needs it.

```bash
set -euo pipefail
export LC_ALL=C
shopt -s nullglob
```
