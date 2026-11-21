# SQLite GCC harness

`./sqlite_build.sh` builds the SQLite CLI and shared and static libraries on Linux. The `./sqlite_ext_*.sh` hooks register project extensions. Build helpers live in `./tool/`, the Conda bootstrap in `./tool/conda_env/`, and preset tests in `./tests/`.

## Conda Python with custom SQLite

Install and verify the requested preset in `./out/conda` with [./sqlite_build_conda.sh](./sqlite_build_conda.sh). Select `full` for all project extensions.

```bash
./sqlite_build_conda.sh --preset full && source ./out/conda_activate.sh
```

Use `./out/conda/bin/python` directly for scripts and tests. [Setup and extension checks](./README.md#use-the-build-from-conda-python)

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
