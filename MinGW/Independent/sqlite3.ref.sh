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
readonly DBDIR="sqlite"
readonly LIBNAME="sqlite3.dll"
readonly BUILDDIR="${DBDIR}/build"


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
  fi
  return 0
}


configure_sqlite() {
  mkdir -p "./${BUILDDIR}"
  cd "${BASEDIR}/${BUILDDIR}" \
    || ( echo "Cannot enter ./${BUILDDIR}" && exit 104 )

  if [[ ! -f ./Makefile ]]; then
    [[ ! -r ../configure ]] && echo "Error accessing SQLite configure" \
      && exit 105
    echo "______________________"
    echo "Configuring SQLite3..."
    echo "----------------------"

    local msys_root
    msys_root="$(cygpath -m /)"
    msys_root="${msys_root%/}"
    local readline_inc
    readline_inc="$(pkg-config --cflags --static readline)"
    readline_inc="${readline_inc//${msys_root}/}"
    local readline_lib
    readline_lib="$(pkg-config --libs --static readline)"
    readline_lib="${readline_lib//${msys_root}/}"
    
    local CONFIGURE_OPTS
    CONFIGURE_OPTS=(
      --enable-all
      --enable-fts3
      --enable-memsys5
      --enable-update-limit
      --with-tcl="${MINGW_PREFIX}/lib"
      --with-readline-lib="${readline_lib}"
      --with-readline-inc="${readline_inc}"
    )

    ../configure ${CONFIGURE_OPTS[@]} || EXITCODE=$?
    (( EXITCODE != 0 )) && echo "Error configuring SQLite" && exit 106
  else
    echo "____________________________________________"
    echo "Makefile found. Skipping configuring SQLite3"
    echo "--------------------------------------------"
  fi
  return 0
}  


copy_dependencies() {
  echo "________________________"
  echo "Copying dependencies... "
  echo "------------------------"
  readonly BUILDBINDIR=${BUILDDIR}/bin
  readonly SRCBINDIR=${MSYSTEM_PREFIX}/bin
  readonly ICUVERSION="$(expr match "$(uconv -V)" '.*ICU \([0-9]*\).*')"
  readonly DEPENDENCIES=(
    libgcc_s_*.dll
    libicudt${ICUVERSION}.dll
    libicuin${ICUVERSION}.dll
    libicuuc${ICUVERSION}.dll
    libstdc++-6.dll
    libwinpthread-1.dll
  )

  mkdir -p "${BASEDIR}/${BUILDBINDIR}"

  for dependency in "${DEPENDENCIES[@]}"; do
    dependency="$(ls ${SRCBINDIR}/${dependency})"
    cp "${dependency}" "${BASEDIR}/${BUILDBINDIR}" \
      || ( echo "Cannot copy ${dependency}" && exit 109 )
  done
  cp "${BASEDIR}/${BUILDDIR}/${LIBNAME}" "${BASEDIR}/${BUILDBINDIR}" \
    || ( echo "Cannot copy ${LIBNAME}" && exit 110 )
  
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
    || ( echo "Cannot copy make file" && exit 204 )
  make -C "${BASEDIR}/${BUILDDIR}" -f "sqlite3.ref.mk" ${1:-all}

  if [[ -f "${BASEDIR}/${BUILDDIR}/${LIBNAME}" ]]; then
    copy_dependencies || EXITCODE=$?
  fi
return 0
}


main "$@"
