#!/bin/sh
#
# 
# Generation of sqlite3.(dll|exe) is not implemented in this version, that is
# only ${SQLITE_DLLS} = "" is supported.
# It requires just a few extra lines, but I do not see the point in having it.
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
    SQLITE3_DLL="-Lsqlite3 -lsqlite3"
    SQLITE3_EXE="sqlite3.exe"
    ADD_NSIS+=" -DWITH_SQLITE_DLLS"
  else
    SQLITE3_A10N_O="sqlite3a10n.o"
    SQLITE3_EXE="sqlite3.exe"
  fi

  export SQLITE3_A10N_O SQLITE3_DLL SQLITE3_EXE
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

  return 0
}  


set_icu() {
  cd "${BASEDIR}"
  cp "${MINGW_PREFIX}/bin/libicudt68.dll" ./
  cp "${MINGW_PREFIX}/bin/libicuin68.dll" ./
  cp "${MINGW_PREFIX}/bin/libicuuc68.dll" ./
  cp "${MINGW_PREFIX}/bin/libwinpthread-1.dll" ./
  cp "${MINGW_PREFIX}/bin/libstdc++-6.dll" ./
  [[ "${MSYSTEM}" == "MINGW32" ]] \
    && cp "${MINGW_PREFIX}/bin/libgcc_s_dw2-1.dll" ./ \
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
  make -C "${BASEDIR}" -f Makefile.mingw USE_DLLTOOL=1 all

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
  set_icu
  export ADD_CFLAGS ADD_LDFLAGS ADD_NSIS
  build_odbc

  return 0
}


main "$@"
