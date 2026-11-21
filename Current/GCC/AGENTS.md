# Bash design

- Give each distinct workflow step its own function. In executable scripts, call the steps in order from `main()` and end the file with `main "$@"`.
- Put a brief purpose comment immediately above each function definition. Omit decorative fences.
- When declaring a list of command-line options, put one option per line.
- In executable scripts, apply these settings before sourcing helpers. Limit any override to the operation that needs it.

  ```bash
  set -euo pipefail
  export LC_ALL=C
  shopt -s nullglob
  ```
