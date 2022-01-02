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
readonly DISTRO="sqliteodbc-0.9998"
readonly BASEDIR="$(dirname "$(realpath "$0")")/${DISTRO}"
readonly DBDIR="sqlite"
readonly BUILDDIR="${BASEDIR}/${DBDIR}/build"
readonly ODBCARC="${DISTRO}.tar.gz"


get_sqliteodbc() {
  local SQLiteODBC_URL="http://www.ch-werner.de/sqliteodbc/${ODBCARC}"
  if [[ ! -f "${ODBCARC}" ]]; then
    echo "_________________________________"
  	echo "Downloading SQLiteODBC sources..."
    echo "---------------------------------"
    wget -c "${SQLiteODBC_URL}" --no-check-certificate -O "${ODBCARC}" || EC=$?
    (( EC != 0 )) && echo "Error downloading SQLiteODBC ${EC}." && exit 102
  else
    echo "____________________________________________________"
  	echo "Using previously downloaded archive of SQLiteODBC..."
    echo "----------------------------------------------------"
  fi

  if [[ ! -f "${BASEDIR}/VERSION" ]]; then
    tar --exclude=source -xf "${ODBCARC}"
  fi
  return 0
}


get_sqlite() {
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

  if [[ ! -f "${BASEDIR}/${DBDIR}/configure" ]]; then
    tar xzf ./sqlite.tar.gz -C "${BASEDIR}"
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
      --enable-all --with-tcl="${MINGW_PREFIX}/lib" || EXITCODE=$?
    (( EXITCODE != 0 )) && echo "Error configuring SQLite" && exit 106
  else
    echo "____________________________________________"
  	echo "Makefile found. Skipping configuring SQLite3"
    echo "--------------------------------------------"
  fi

  return 0
}  


sqliteodbc_flags() {
  SQLITE_DLLS="${SQLITE_DLLS:-}"
  SQLITE3_DLL="${SQLITE3_DLL:-}"
  SQLITE3_A10N_O="${SQLITE3_A10N_O:-}"

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


set_icu() {
  readonly ICUVERSION="$(expr match "$(uconv -V)" '.*ICU \([0-9]*\).*')"
  cd "${BASEDIR}" \
    || ( echo "Cannot enter ${BASEDIR}" && exit 110 )
  cp "${MINGW_PREFIX}/bin/libicudt${ICUVERSION}.dll" ./
  cp "${MINGW_PREFIX}/bin/libicuin${ICUVERSION}.dll" ./
  cp "${MINGW_PREFIX}/bin/libicuuc${ICUVERSION}.dll" ./
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


update_sources() {
  echo "================"
  echo "Updating sources"
  echo "================"
  cd "${BASEDIR}/.."
  cp insta.c minshell.c Makefile.mingw sqliteodbc_w32w64.nsi "${BASEDIR}"

  return 0
}


build_odbc() {
  echo "==============================="
  echo "Building ODBC drivers and utils"
  echo "==============================="
  make -C "${BASEDIR}" -f Makefile.mingw USE_DLLTOOL=1 all

  return 0
}


move_binaries() {
  echo "___________________"
  echo "Moving binaries... "
  echo "-------------------"
  readonly BUILDBINDIR="${BASEDIR}/../bin"
  mkdir -p "${BUILDBINDIR}"

  cd "${BASEDIR}"
  rm -rf *.o
  mv *.exe "${BUILDBINDIR}"
  mv *.dll "${BUILDBINDIR}"
  mv *.a   "${BUILDBINDIR}"
  
  return 0
}


main() {
  LOG_FILE=${LOG_FILE:-makelog.log}
  { 
    echo "SQLITE_DLLS=${SQLITE_DLLS:-};" "$0" "$@";
    echo "###############################################################";
    echo "";
  } >>"${LOG_FILE}"

  get_sqliteodbc
  get_sqlite
  configure_sqlite

  ADD_CFLAGS="${ADD_CFLAGS:-}"
  ADD_LDFLAGS="${ADD_LDFLAGS:-}"
  ADD_NSIS="${ADD_NSIS:-}"
  sqliteodbc_flags
  set_icu
  export ADD_CFLAGS ADD_LDFLAGS ADD_NSIS
  update_sources
  build_odbc
  move_binaries

  return 0
}


main "$@"
