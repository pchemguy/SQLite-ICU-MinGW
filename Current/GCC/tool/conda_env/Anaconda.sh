#!/usr/bin/env bash
# Bootstrap a Conda base beside this script and generate its Bash launcher.
if [[ ${BASH_SOURCE[0]} != "$0" ]]; then
  printf '%s %s\n' 'Run this bootstrap as a script.' \
    'Source the generated activation script afterward.' >&2
  return 2
fi

set -euo pipefail
export LC_ALL=C
shopt -s nullglob

usage() {
  printf 'Usage: %s [--init]\n' "${0##*/}"
  printf '  --init   %s\n' \
    'Create or verify the base and its activation script only.'
}

fail() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

# Set main's mode variable, or exit after printing help or an argument error.
parse_args() {
  mode=full
  local arg
  for arg in "$@"; do
    case "${arg}" in
      --init) mode=init ;;
      -h|--help) usage; exit 0 ;;
      *) usage >&2; fail "Unknown argument: ${arg}" ;;
    esac
  done
}

# Validate the destination and required manifest before changing the filesystem.
check_inputs() {
  local prefix=$1
  local launcher="${prefix}_activate.sh"

  [[ $(uname -s) == Linux ]] || fail 'This bootstrap requires Linux.'
  if [[ ${prefix} == *[[:space:]]* ]]; then
    fail "Use a prefix without whitespace." \
      "Conda entry points embed the Python path: ${prefix}"
  fi
  if [[ -e ${launcher} || -L ${launcher} ]]; then
    [[ -f ${launcher} && -r ${launcher} ]] ||
      fail "Activation launcher is not a readable file: ${launcher}"
  fi
  [[ -f ${prefix}_bootstrap.yml ]] ||
    fail "Missing bootstrap manifest: ${prefix}_bootstrap.yml"
}

# Lock the script and arrange cleanup of the temporary directory at exit.
prepare_workspace() {
  local script=$1
  local lock_fd
  exec {lock_fd}<"${script}"
  flock -n "${lock_fd}" || fail "Another bootstrap is running for ${script%.sh}."

  # The EXIT trap runs after main's local variables go out of scope.
  BOOTSTRAP_WORK_DIR=$(mktemp -d -- "${script%/*}/.${script##*/}.XXXXXXXX")
  readonly BOOTSTRAP_WORK_DIR
  trap 'rm -rf -- "${BOOTSTRAP_WORK_DIR}"' EXIT
}

# Download the standalone Micromamba for this host into the temporary directory.
download_micromamba() {
  local dest=$1
  local arch platform
  arch=$(uname -m)
  case "${arch}" in
    x86_64) platform=linux-64 ;;
    aarch64|arm64) platform=linux-aarch64 ;;
    *) fail "Unsupported Linux architecture: ${arch}" ;;
  esac

  local releases='https://github.com/mamba-org/micromamba-releases/releases'
  local -a curl_opts=(
    --fail
    --location
    --retry 3
    --silent
    --show-error
    --output "${dest}"
  )
  curl "${curl_opts[@]}" "${releases}/latest/download/micromamba-${platform}"
  chmod +x "${dest}"
}

# Install the base from its manifest or reuse an existing Conda prefix.
bootstrap_base() {
  local prefix=$1
  if [[ -e ${prefix} || -L ${prefix} ]]; then
    [[ -f ${prefix}/conda-meta/history ]] ||
      fail "Existing path is not a Conda environment: ${prefix}"
    return 0
  fi

  local micromamba="${BOOTSTRAP_WORK_DIR}/micromamba"
  local -a install_opts=(
    --yes
    --no-rc
    --name base
    --file "${prefix}_bootstrap.yml"
  )
  printf 'Creating %s from %s\n' "${prefix}" "${prefix}_bootstrap.yml"
  download_micromamba "${micromamba}"
  "${micromamba}" install "${install_opts[@]}"
}

# Verify the base tools and persist settings for future activation.
configure_base() {
  local prefix=$1
  local tool
  for tool in python conda mamba micromamba uv; do
    [[ -x ${prefix}/bin/${tool} ]] ||
      fail "Missing ${prefix}/bin/${tool}." \
        "Check the bootstrap manifest and the installation."
  done
  [[ -r ${prefix}/bin/activate ]] ||
    fail "Missing Conda activation script under ${prefix}/bin."
  "${prefix}/bin/conda" env config vars set --prefix "${prefix}" \
    "MAMBA_ROOT_PREFIX=${prefix}" PYTHONNOUSERSITE=1
}

# Apply the optional Conda project manifest before activation.
update_conda_packages() {
  local prefix=$1
  [[ -f ${prefix}.yml ]] || return 0
  local -a update_opts=(
    --yes
    --no-rc
    --use-uv
    --prefix "${prefix}"
    --file "${prefix}.yml"
  )
  "${prefix}/bin/micromamba" env update "${update_opts[@]}"
}

# Load package hooks into this shell and check the selected interpreter.
activate_base() {
  local prefix=$1
  # Third-party activation hooks may read unset shell variables.
  set +u
  # shellcheck disable=SC1091
  source "${prefix}/bin/activate" "${prefix}"
  set -u
  [[ ${CONDA_PREFIX:-} == "${prefix}" ]] ||
    fail "Conda activated an unexpected prefix: ${CONDA_PREFIX:-<unset>}"
  "${prefix}/bin/python" --version
}

# Generate a sourceable launcher and preserve any existing customization.
write_launcher() {
  local prefix=$1
  local launcher="${prefix}_activate.sh"
  [[ -e ${launcher} || -L ${launcher} ]] && return 0
  {
    cat <<'LAUNCHER'
#!/usr/bin/env bash
# Source this file to activate the local Conda environment.
if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  echo "Source this script in Bash to activate the environment." >&2
  exit 2
fi
LAUNCHER
    printf 'source %q %q\n' "${prefix}/bin/activate" "${prefix}"
  } > "${BOOTSTRAP_WORK_DIR}/activate.sh"
  mv -- "${BOOTSTRAP_WORK_DIR}/activate.sh" "${launcher}"
}

# Install the optional pip requirements against the prefix's Python.
install_pip_packages() {
  local prefix=$1
  [[ -f ${prefix}.txt ]] || return 0
  local -a pip_opts=(
    --python "${prefix}/bin/python"
    --requirement "${prefix}.txt"
  )
  "${prefix}/bin/uv" pip install "${pip_opts[@]}"
}

# Collect both inventories before replacing the previous files.
export_inventories() {
  local prefix=$1
  "${prefix}/bin/conda" env export --prefix "${prefix}" --no-builds \
    > "${BOOTSTRAP_WORK_DIR}/environment.yml"
  "${prefix}/bin/uv" pip list --python "${prefix}/bin/python" \
    > "${BOOTSTRAP_WORK_DIR}/packages.txt"
  mv -- "${BOOTSTRAP_WORK_DIR}/environment.yml" "${prefix}_generated.yml"
  mv -- "${BOOTSTRAP_WORK_DIR}/packages.txt" "${prefix}.pip.txt"
}

main() {
  local mode
  parse_args "$@"

  local script_dir name prefix
  script_dir=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
  name=${BASH_SOURCE[0]##*/}
  prefix="${script_dir}/${name%.sh}"
  check_inputs "${prefix}"

  prepare_workspace "${script_dir}/${name}"

  unset PYTHONHOME PYTHONPATH
  export PYTHONNOUSERSITE=1
  export MAMBA_ROOT_PREFIX="${prefix}"

  bootstrap_base "${prefix}"
  configure_base "${prefix}"
  if [[ ${mode} == full ]]; then
    update_conda_packages "${prefix}"
  fi
  activate_base "${prefix}"
  write_launcher "${prefix}"
  if [[ ${mode} == full ]]; then
    install_pip_packages "${prefix}"
    export_inventories "${prefix}"
  fi
  printf 'Activate in Bash with: source %q\n' "${prefix}_activate.sh"
}

main "$@"
