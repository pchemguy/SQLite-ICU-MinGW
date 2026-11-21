#!/usr/bin/env bash
# Build SQLite and install its verified shared library in the local Conda prefix.
set -euo pipefail
export LC_ALL=C
shopt -s nullglob

# Bootstrap the prefix, rebuild the selected preset, and verify it from Python.
main() {
  local preset=full base out lockfd
  local -a managed_paths=()
  if [[ ${1:-} == --help || ${1:-} == -h ]]; then
    usage
    return
  fi
  if (( $# )); then
    [[ $# == 2 && $1 == --preset ]] || { usage >&2; return 2; }
    preset=$2
  fi

  base=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
  "${base}/sqlite_build.sh" --check-preset "${preset}"
  # shellcheck source=tool/build_root.sh
  source "${base}/tool/build_root.sh"
  resolve_output_root
  open_build_root rebuild

  local prefix="${out}/conda"
  ensure_conda_python "${prefix}" "${base}/tool/conda_env"
  rebuild_sqlite "${preset}"
  install_conda_sqlite "${prefix}" "${out}/lib/libsqlite3.so.0"
}

# Report an error and stop the wrapper.
die() {
  printf 'sqlite_build_conda: %s\n' "$*" >&2
  exit 1
}

# Show the wrapper's command line.
usage() {
  printf 'Usage: %s [--preset NAME]\n' "${0##*/}"
  printf 'Build a SQLite preset (default: full) for the Python in OUT_DIR/conda.\n'
}

# Stage the bootstrap under the basename that selects this prefix. Each output
# root gets its own script inode for the bootstrap's flock.
run_conda_bootstrap() (
  local template_dir=$1 prefix=$2 suffix input dest
  local -a staged=()
  trap 'rm -f -- "${staged[@]}"' EXIT
  for suffix in .sh _bootstrap.yml .yml .txt; do
    input="${template_dir}/Anaconda${suffix}"
    dest="${prefix}${suffix}"
    if [[ -e ${dest} || -L ${dest} ]]; then
      if [[ ! -f ${dest} || ! -f ${input} ]] || ! cmp -s -- "${input}" "${dest}"; then
        die "Conflicting bootstrap input: ${dest}"
      fi
    elif [[ -f "${input}" ]]; then
      staged+=("${dest}")
      cp -- "${input}" "${dest}"
    fi
  done
  bash "${prefix}.sh"
)

# Run both Conda manifests on first use. Retry an interrupted bootstrap even
# if the base installation had already produced Python.
ensure_conda_python() {
  local prefix=$1 template_dir=$2 pending="${1}.bootstrap-pending"
  if [[ -x "${prefix}/bin/python" && ! -e "${pending}" ]]; then
    return
  fi
  if [[ -e "${pending}" && -d "${prefix}" && ! -f "${prefix}/conda-meta/history" ]]; then
    local saved
    saved=$(mktemp -d -- "${prefix}.incomplete.XXXXXXXX")
    mv -T -- "${prefix}" "${saved}/prefix"
    printf 'Saved incomplete Conda prefix in %s\n' "${saved}/prefix" >&2
  fi
  if [[ ! -e "${prefix}" || -f "${prefix}/conda-meta/history" ]]; then
    touch -- "${pending}"
  fi
  run_conda_bootstrap "${template_dir}" "${prefix}"
  [[ -x "${prefix}/bin/python" ]] || die "Bootstrap did not install ${prefix}/bin/python"
  rm -f -- "${pending}"
}

# Unlink bin without following its package symlink. Keep the source and download
# cache, and pass the held output lock to the regular build driver.
rebuild_sqlite() (
  local preset=$1
  # Keep the previous published CLI reachable if the new build fails.
  trap 'if [[ -d ${out}/package/bin && ! -e ${out}/bin && ! -L ${out}/bin ]]; then
          ln -s -- package/bin "${out}/bin"
        fi' EXIT
  rm -rf -- "${out:?}/bin" "${out}/build"
  OUT_DIR="${out}" SQLITE_BUILD_LOCK_FD="${lockfd}" \
    "${base}/sqlite_build.sh" --preset "${preset}"
)

# Query SQLite in a fresh prefix Python, check its actual Linux mappings and
# compare the installed library byte for byte with the published build.
verify_conda_sqlite() {
  local prefix=$1 target=$2 built=$3
  "${prefix}/bin/python" -I - "${prefix}" "${target}" "${built}" <<'PY'
import filecmp
import os
from pathlib import Path
import sqlite3
import sys

prefix, target, built = map(Path, sys.argv[1:])
if not prefix.samefile(sys.prefix):
    sys.exit(f"Unexpected Python prefix: {sys.prefix}")
with sqlite3.connect(":memory:") as db:
    version, source_id = db.execute("SELECT sqlite_version(), sqlite_source_id()").fetchone()
with open("/proc/self/maps", "rb") as maps:
    rows = (line.rstrip(b"\n").split(None, 5) for line in maps)
    loaded = {os.fsdecode(row[5]) for row in rows
              if len(row) == 6 and os.path.basename(row[5]).startswith(b"libsqlite3.so")}
if loaded != {str(target)}:
    sys.exit(f"Expected Python to load {target}, found {sorted(loaded)}")
if not filecmp.cmp(built, target, shallow=False):
    sys.exit(f"Loaded library differs from {built}")
print(f"{sys.executable} loaded {target}\nSQLite {version} ({source_id})")
PY
}

# Replace the real SONAME target by rename to preserve Conda's library symlinks
# and package-cache hardlinks. Restore the original if verification fails.
install_conda_sqlite() (
  local prefix=$1 built=$2 lib target work
  lib=$(realpath -e -- "${prefix}/lib")
  target=$(realpath -e -- "${lib}/libsqlite3.so.0")
  [[ ${lib} == "${prefix}"/* && ${target%/*} == "${lib}" && -f ${target} ]] ||
    die "SQLite library resolves outside the Conda lib directory: ${target}"
  work=$(mktemp -d -- "${lib}/.sqlite-install.XXXXXXXX")
  trap 'if [[ -f ${work}/original && ! ${work}/original -ef ${target} ]]; then
          mv -fT -- "${work}/original" "${target}"
        fi
        rm -rf -- "${work}"' EXIT
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM
  install -m 755 -- "${built}" "${work}/replacement"
  ln -- "${target}" "${work}/original"
  mv -fT -- "${work}/replacement" "${target}"
  verify_conda_sqlite "${prefix}" "${target}" "${built}"
  rm -- "${work}/original"
)

main "$@"
