#!/bin/bash
#
set -euo pipefail
IFS=$'\n\t'

cleanup_EXIT() { 
  echo "EXIT clean up: $?" 
}
trap cleanup_EXIT EXIT

cleanup_TERM() {
  echo "TERM clean up: $?"
}
trap cleanup_TERM TERM

cleanup_ERR() {
  echo "ERR clean up: $?"
}
trap cleanup_ERR ERR

EXITCODE=0
EC=0
readonly BASEDIR="$(dirname "$(realpath "$0")")"
readonly BLDDIR="${BASEDIR}/libspatialite/build"
MSYS_ROOT="$(cygpath -m /)"
readonly MSYS_ROOT="${MSYS_ROOT%/}"
TARGETS=""

clean_paths() {
  local readonly CMD1="s|${MSYS_ROOT}||g"
  # Normalize path: recursively remove "dirname/../"
  local readonly CMD2="s|(${MINGW_PREFIX}(/[^/ ]*)*?)(/[^/ ]*[^.]/\.\.)|\1|"
  sed -E "${CMD1}; :loop; ${CMD2}; tloop;" \
      -i "$1"
    return 0
}


collect_files() {
  IFS=$' \n\t'
  TARGETS=($(find "${BLDDIR}" -name 'Makefile'))
  TARGETS+=("${BLDDIR}/libtool" "${BLDDIR}/Makefile"
            "${BLDDIR}/spatialite.pc" "${BLDDIR}/config.status" )
  IFS=$'\n\t'
}


main() {
  collect_files
  for TARGET in "${TARGETS[@]}"; do
    clean_paths "${TARGET}"
  done  
  return 0
}


main "$@"
