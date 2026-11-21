# Bootstrap and activate a Linux Conda environment

Run `Anaconda.sh` to install a complete Conda **base** environment in the adjacent `Anaconda/` directory. Python, Conda, Mamba, Micromamba, uv, and the project packages live under that prefix. The script downloads a temporary Micromamba binary to start the installation. No preinstalled Python or Conda is required.

Use Bash on glibc-based x86-64 or AArch64 Linux, with `curl`, `flock` (util-linux), standard GNU utilities, and write access to the script directory. Choose an installation path without whitespace. Linux entry points installed by Micromamba can embed that path directly in their interpreter lines. The initial installation needs access to GitHub and conda-forge. The shipped pip requirements also use PyPI. Builds that need a C compiler use the configured system toolchain. Conda and uv use their normal package caches.

## Build and use the environment

From the repository root, run these commands.

```bash
./linux/Anaconda.sh
source ./linux/Anaconda_activate.sh
python --version
conda info --base
conda deactivate
```

The build runs in its own process. Sourcing the generated launcher activates the exact prefix in the current Bash shell, including package activation hooks. Both `conda info --base` and `python -c 'import sys; print(sys.prefix)'` should resolve to the adjacent `linux/Anaconda` directory. No shell startup file needs editing.

For automation, invoke the installed Conda directly. This example runs Python in the environment from a fresh shell.

```bash
prefix="$PWD/linux/Anaconda"
"$prefix/bin/conda" run --prefix "$prefix" python -c 'import numpy; print(numpy.__version__)'
```

## Build the base first, then add project packages

```bash
./linux/Anaconda.sh --init
source ./linux/Anaconda_activate.sh
conda --version
conda deactivate
./linux/Anaconda.sh
```

`--init` installs or checks the base and creates the launcher. It skips the main YAML, pip requirements, and inventories. A later full run reuses the base and applies the project dependencies. Run it again after editing the main YAML or requirements. Removing a package from a manifest does not uninstall it from an existing environment.

| Input or output | Role |
| --- | --- |
| [Anaconda_bootstrap.yml](Anaconda_bootstrap.yml) | Required. On first installation, Micromamba installs these packages into its root prefix as the base environment. Include `python`, `conda`, `mamba`, `micromamba`, and `uv` when customizing this file. An existing base is checked and reused. |
| [Anaconda.yml](Anaconda.yml) | Optional. A full run uses the prefix's Micromamba to apply this Conda manifest first. Put Conda-distributed project dependencies here. |
| [Anaconda.txt](Anaconda.txt) | Optional. After activation, the prefix's uv installs these requirements against the prefix's Python. |
| `Anaconda_activate.sh` | Sibling Bash launcher generated on the first successful activation. An existing launcher is preserved. |
| `Anaconda_generated.yml` | Conda environment export without build strings. Written on a full run. |
| `Anaconda.pip.txt` | Package/version table from `uv pip list` for the same Python. Written on a full run. |

Paths follow the script's location and basename. For example, `Project.sh` reads `Project_bootstrap.yml`, `Project.yml`, and `Project.txt`, installs into `Project/`, and generates `Project_activate.sh` beside it. An ordinary directory at the target path is rejected. If a failed bootstrap leaves an incomplete installation, move the partial prefix aside before retrying. Rebuild at the destination if the project moves, since Conda packages and the launcher can contain absolute paths.

## Local Java and other activation settings

To use a prefix-local JDK, add `openjdk` to `dependencies` in `Anaconda.yml`, rerun the full bootstrap, and source the launcher in a fresh shell. The conda-forge OpenJDK package supplies an activation hook that sets `JAVA_HOME` to `$CONDA_PREFIX/lib/jvm`. Check the selected Java in that shell.

```bash
source ./linux/Anaconda_activate.sh
printf '%s\n' "$JAVA_HOME"
command -v java
"$JAVA_HOME/bin/java" --version
```

For a fixed project variable, Conda can store the value in this environment. For example, with a manually installed JDK under `$CONDA_PREFIX/opt/jdk`, run `conda env config vars set JAVA_HOME="$CONDA_PREFIX/opt/jdk"` while the environment is active, then deactivate and source the launcher again.

For settings that need shell logic, use paired Bash scripts under `$CONDA_PREFIX/etc/conda/activate.d/` and `deactivate.d/`. The activation hook applies the setting and its deactivation counterpart can restore the previous value. The bootstrap uses Conda's environment variables to select this prefix as Micromamba's root and to disable Python's user-site packages while activated.
