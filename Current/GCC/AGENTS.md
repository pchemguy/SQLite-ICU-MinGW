# Bash design

- Give each distinct workflow step its own focused function. Keep closely related operations together.
- In executable scripts, make `main()` the first function definition, use it to coordinate the workflow, and end the file with `main "$@"`.
- Put a brief comment immediately above any function whose purpose or side effects are unclear from its name.
- Store lists of command-line options in arrays, with one option per line and any separate argument on the same line. The example uses a local array inside a function.

  ```bash
  local -a curl_opts=(
    --fail
    --silent
    --show-error
    --output "$dest"
  )
  curl "${curl_opts[@]}" "$url"
  ```

- In executable scripts, apply these settings before sourcing helpers. Limit any override to the operation that needs it.

  ```bash
  set -euo pipefail
  export LC_ALL=C
  shopt -s nullglob
  ```
