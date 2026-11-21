## Bash design

Follow the [Google Shell Style Guide](https://google.github.io/styleguide/shellguide.html) for Bash code.

- In executable scripts, use `main()` to coordinate the workflow. Give each distinct step its own focused function and keep closely related operations together.
- In option arrays, put one option per line, with any separate argument on the same line.
- In executable scripts, apply these settings before sourcing helpers. Limit any override to the operation that needs it.

  ```bash
  set -euo pipefail
  export LC_ALL=C
  shopt -s nullglob
  ```

## Conda Python with custom SQLite

From `Current/GCC`, build the requested preset and activate the environment in the current Bash shell. Use `full` for all project extensions.

```bash
./sqlite_build_conda.sh --preset full && source out/conda_activate.sh
```

For scripts and tests, invoke `out/conda/bin/python` directly. Rerunning the wrapper reuses the environment, removes `out/bin` and `out/build`, and verifies that the prefix's Python loads the rebuilt SQLite. [Setup and extension checks](README.md#use-the-build-from-conda-python)
