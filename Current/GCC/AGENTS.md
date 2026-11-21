# Bash design

Follow the [Google Shell Style Guide](https://google.github.io/styleguide/shellguide.html) for Bash code.

- In executable scripts, use `main()` to coordinate the workflow. Give each distinct step its own focused function and keep closely related operations together.
- In option arrays, put one option per line, with any separate argument on the same line.
- In executable scripts, apply these settings before sourcing helpers. Limit any override to the operation that needs it.

  ```bash
  set -euo pipefail
  export LC_ALL=C
  shopt -s nullglob
  ```
