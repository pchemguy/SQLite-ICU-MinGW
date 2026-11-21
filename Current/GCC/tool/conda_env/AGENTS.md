## Linux Conda environment

Use Bash on glibc-based x86-64 or AArch64 Linux with `curl` and `flock` available. Keep `Anaconda.sh` and its manifests together in a writable directory whose absolute path contains no whitespace. If the project does not supply them, copy the files from [Conda Bootstrap](https://github.com/pchemguy/Conda-Bootstrap/tree/main/linux).

| Manifest | What to put in it |
| --- | --- |
| `Anaconda_bootstrap.yml` | Required base packages. Keep `python`, `conda`, `mamba`, `micromamba`, and `uv`. Micromamba installs these when creating the prefix. |
| `Anaconda.yml` | Optional Conda project dependencies, applied first on a full run. |
| `Anaconda.txt` | Optional pip requirements, installed afterward with uv into the same prefix. |

From the directory containing `Anaconda.sh`, bootstrap, activate, and verify the adjacent `Anaconda/` prefix.

```bash
bash ./Anaconda.sh &&
    source ./Anaconda_activate.sh &&
    test "$CONDA_PREFIX" = "$(pwd -P)/Anaconda"
```

Use `bash ./Anaconda.sh --init` for the base alone. A subsequent full run reuses the base and applies the project manifests. Rerun the full command after editing `Anaconda.yml` or `Anaconda.txt`.

Source the generated launcher in each fresh Bash shell that runs project commands. Use its absolute path when working from another directory.
