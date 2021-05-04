#!/bin/sh
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
BASEDIR="$(dirname "$(realpath "$0")")"
readonly BASEDIR
readonly DBDIR="sqlite3"
readonly BUILDDIR=${DBDIR}/build


get_sqlite() {
  cd "${BASEDIR}" || ( echo "Cannot enter ${BASEDIR}" && exit 101 )
  local SQLite_URL="https://www.sqlite.org/src/tarball/sqlite.tar.gz?r=release"
  if [[ ! -f ./sqlite.tar.gz ]]; then
    echo "____________________________________________"
  	echo "Downloading the current release of SQLite..."
    echo "--------------------------------------------"
    wget -c "${SQLite_URL}" --no-check-certificate -O sqlite.tar.gz \
      || EC=$?
    (( EC != 0 )) && echo "Error downloading SQLite ${EC}." && exit 102
  else
    echo "________________________________________________"
  	echo "Using previously downloaded archive of SQLite..."
    echo "------------------------------------------------"
  fi

  if [[ ! -f "./${DBDIR}/configure" ]]; then
    tar xzf ./sqlite.tar.gz
    mv ./sqlite "${DBDIR}"
  fi
  return 0
}


configure_sqlite() {
  mkdir -p "./${BUILDDIR}"
  cd "${BASEDIR}/${BUILDDIR}" \
    || ( echo "Cannot enter ./${BUILDDIR}" && exit 104 )
  [[ ! -r ../configure ]] && echo "Error accessing SQLite configure" && exit 105

  if [[ ! -f ./Makefile ]]; then
    echo "______________________"
  	echo "Configuring SQLite3..."
    echo "----------------------"
    ../configure --enable-fts3 --enable-memsys5 --enable-update-limit \
      --enable-all --with-tcl="${MINGW_PREFIX}/lib/tcl8" || EXITCODE=$?
    (( EXITCODE != 0 )) && echo "Error configuring SQLite" && exit 106
  else
    echo "____________________________________________"
  	echo "Makefile found. Skipping configuring SQLite3"
    echo "--------------------------------------------"
  fi
  return 0
}  


main() {
  export LOG_FILE=${LOG_FILE:-${BASEDIR}/makelog.log}
  echo "$0" "$@" >>"${LOG_FILE}"
  echo "###############################################################" >>"${LOG_FILE}"
  echo "" >>"${LOG_FILE}"

  get_sqlite || EXITCODE=$?
  (( EXITCODE != 0 )) && echo "Error downloading SQLite3" && exit 201
  configure_sqlite || EXITCODE=$?
  (( EXITCODE != 0 )) && echo "Error configuring SQLite3" && exit 202

  cp "${BASEDIR}/sqlite3.ref.mk" "${BASEDIR}/${BUILDDIR}" \
    || ( echo "Cannot copy make file" && exit 203 )
  make -C "${BASEDIR}/${BUILDDIR}" -f "sqlite3.ref.mk" ${1:-all}
  return 0
}


main "$@"
