#!/bin/sh
#
set -euo pipefail
IFS=$'\n\t'

cleanup_EXIT() { 
  echo "EXIT clean up: $?" 
}
trap cleanup_EXIT EXIT

cleanup_TERM() {
  echo "TERM clean up"
}
trap cleanup_TERM TERM

cleanup_ERR() {
  echo "ERR clean up"
}
trap cleanup_ERR ERR


EXITCODE=0
EC=0
BASEDIR="$(dirname "$(realpath "$0")")"
readonly BASEDIR
readonly DBDIR="sqlite3"
readonly BUILDDIR="${BASEDIR}/${DBDIR}/build"
ADD_CFLAGS="${ADD_CFLAGS:-}"
ADD_LDFLAGS="${ADD_LDFLAGS:-}"


SQLITE_DLLS="${SQLITE_DLLS:-}"
SQLITE3_DLL="${SQLITE3_DLL:-}"
ADD_NSIS="${ADD_NSIS:-}"
SQLITE3_A10N_O="${SQLITE3_A10N_O:-}"
sqliteodbc_flags() {
  if [[ "${SQLITE_DLLS}" = "2" ]]; then
    ADD_CFLAGS=" -DWITHOUT_SHELL=1 -DWITH_SQLITE_DLLS=2"
    ADD_NSIS+=" -DWITHOUT_SQLITE3_EXE"
  elif [[ -n "${SQLITE_DLLS}" ]]; then
    ADD_CFLAGS=" -DWITHOUT_SHELL=1 -DWITH_SQLITE_DLLS=1"
    SQLITE3_DLL=" -Lsqlite3 -lsqlite3"
    ADD_NSIS+=" -DWITHOUT_SQLITE3_EXE -DWITH_SQLITE_DLLS"
  else
    SQLITE3_A10N_O="sqlite3a10n.o"
    ADD_NSIS+=" -DWITHOUT_SQLITE3_EXE"
  fi

  export SQLITE3_A10N_O SQLITE3_DLL
  return 0
}


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


SQLITE_CFLAGS=""
configure_sqlite() {
  mkdir -p "${BUILDDIR}"
  cd "${BUILDDIR}" \
    || ( echo "Cannot enter ${BUILDDIR}" && exit 104 )
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

  IFS=$' \n\t'
  SQLITE_CFLAGS=(
    -D_HAVE_SQLITE_CONFIG_H
    -DSQLITE_DQS=0
    -DSQLITE_LIKE_DOESNT_MATCH_BLOBS
    -DSQLITE_MAX_EXPR_DEPTH=0
    -DSQLITE_DEFAULT_FOREIGN_KEYS=1
    -DSQLITE_DEFAULT_SYNCHRONOUS=1
    -DSQLITE_ENABLE_COLUMN_METADATA
    -DSQLITE_ENABLE_DBPAGE_VTAB
    -DSQLITE_ENABLE_DBSTAT_VTAB
    -DSQLITE_ENABLE_EXPLAIN_COMMENTS
    -DSQLITE_ENABLE_FTS3
    -DSQLITE_ENABLE_FTS3_PARENTHESIS
    -DSQLITE_ENABLE_FTS3_TOKENIZER
    -DSQLITE_ENABLE_FTS4
    -DSQLITE_ENABLE_FTS5
    -DSQLITE_ENABLE_GEOPOLY
    -DSQLITE_ENABLE_MATH_FUNCTIONS
    -DSQLITE_ENABLE_JSON1
    -DSQLITE_ENABLE_QPSG
    -DSQLITE_ENABLE_RBU
    -DSQLITE_ENABLE_ICU
    -DSQLITE_ENABLE_RTREE
    -DSQLITE_ENABLE_STMTVTAB
    -DSQLITE_ENABLE_STAT4
    -DSQLITE_SOUNDEX
    -DNDEBUG
  )
  IFS=$'\n\t'

  ADD_CFLAGS+=${SQLITE_CFLAGS[@]}

  return 0
}  


gen_sqlite3_amalgamation() {
  echo "__________________________________"
  echo "Generating SQLite3 amalgamation..."
  echo "----------------------------------"
  cp "${BASEDIR}/Makefile.mingw" "${BUILDDIR}/"
  make -C "${BUILDDIR}" -f Makefile.mingw all_sqlite3

  return 0
}  


set_icu() {
  cd "${BASEDIR}"
  cp "${MINGW_PREFIX}/bin/libicudt68.dll" ./
  cp "${MINGW_PREFIX}/bin/libicuin68.dll" ./
  cp "${MINGW_PREFIX}/bin/libicuuc68.dll" ./
  cp "${MINGW_PREFIX}/bin/libwinpthread-1.dll" ./
  cp "${MINGW_PREFIX}/bin/libstdc++-6.dll" ./
  cp "${MINGW_PREFIX}/bin/libgcc_s_dw2-1.dll" ./ \
    || cp "${MINGW_PREFIX}/bin/libgcc_s_seh-1.dll" ./

  ICU_CFLAGS="$(icu-config --cflags --cppflags)"
  ICU_LDFLAGS="$(icu-config --ldflags --ldflags-system)"
  ADD_CFLAGS+=" ${ICU_CFLAGS}"
  ADD_LDFLAGS+=" ${ICU_LDFLAGS}"
  ADD_NSIS+=" -DWITH_ICU"

  return 0
}


build_odbc() {
  echo "==============================="
  echo "Building ODBC drivers and utils"
  echo "==============================="
  make -C "${BASEDIR}" -f Makefile.mingw all

  return 0
}


make_nsis() {
  echo "==========================="
  echo "Creating NSIS installer ..."
  echo "==========================="
  cd "${BASEDIR}"
  cp README readme.txt && cp license.terms license.txt
  IFS=$' \n\t'
  ADD_NSIS=(${ADD_NSIS})
  IFS=$'\n\t'
  makensis ${ADD_NSIS[@]} sqliteodbc_w32w64.nsi
  return 0
}


main() {
  LOG_FILE=${LOG_FILE:-makelog.log}
  { 
    echo "SQLITE_DLLS=${SQLITE_DLLS:-};" "$0" "$@";
    echo "###############################################################";
    echo "";
  } >>"${LOG_FILE}"

  sqliteodbc_flags
  get_sqlite
  configure_sqlite
  gen_sqlite3_amalgamation
  set_icu
  export ADD_CFLAGS ADD_LDFLAGS
  build_odbc
  make_nsis

  return 0
}


main "$@"

exit 0
