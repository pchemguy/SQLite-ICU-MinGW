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

patch_sqlite3_makefile() {
  cd "${BASEDIR}/${BUILDDIR}" \
    || ( echo "Cannot enter ./${BUILDDIR}" && exit 108 )
  echo "____________________________"
  echo "Patching SQLite3 Makefile..."
  echo "----------------------------"
  sed -e 's|^CFLAGS =\(.*\)$|CFLAGS :=\1 \$(CFLAGS)|;' \
      -e 's|^OPT_FEATURE_FLAGS =\(.*\)$|OPT_FEATURE_FLAGS :=\1 \$(OPT_FEATURE_FLAGS)|;' \
      -e "s|^TOP = \(.*\)$|TOP = ${BASEDIR}/${DBDIR}|;" \
      -i Makefile
  return 0
}

sys_lib_path=""
libtool_sys_lib_path() {
  cd "${BASEDIR}/${BUILDDIR}" \
    || ( echo "Cannot enter ./${BUILDDIR}" && exit 107 )
  echo "_____________________________________"
  echo "Cleaning up libtool's sys_lib_path..."
  echo "-------------------------------------"
  local msys_root
  msys_root="$(cygpath -m /)"
  msys_root="${msys_root%/}"
  local folders
  IFS=$' \n\t'
  read -r -a folders <<< \
    "$(grep -oP '(?<=^sys_lib_search_path_spec=" =)(.*)(?="$)' ./libtool)"
  IFS=$'\n\t'
  sys_lib_path=":"
  local folder
  for folder in "${folders[@]}"; do
    folder="$(realpath "${folder}" || true)"
    if [[ -n "${folder}" ]]; then
      folder="${folder#${msys_root}}"
      if [[ -n "${sys_lib_path##*${folder}:*}" ]]; then
        sys_lib_path+="${folder}:"
      fi
    fi
  done

  sys_lib_path="${sys_lib_path%:}"
  sys_lib_path="${sys_lib_path#:}"
  sys_lib_path="${sys_lib_path//:/ }"
  return 0
}

patch_sqlite3_libtool() {
  cd "${BASEDIR}/${BUILDDIR}" \
    || ( echo "Cannot enter ./${BUILDDIR}" && exit 108 )
  echo "___________________________"
  echo "Patching SQLite3 libtool..."
  echo "---------------------------"
  local mingw_ld="$(which ld.exe)"
  sed -e 's|^\(deplibs_check_method=\)"file_magic\(.*\)$|#\0\n\1"pass_all"|;' \
      -e "s|^LD=\(.*\)\$|LD=\"${mingw_ld}\"|;" \
      -e "s|^\(sys_lib_search_path_spec=\)\(.*\)\$|\1\"${sys_lib_path}\"|;" \
      -i libtool
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
  patch_sqlite3_makefile || EXITCODE=$?
  if [[ -n "${MINGW_PREFIX:-}" ]]; then
    echo "___________________________________"
    echo "MINGW detected. Patching libtool..."
    echo "-----------------------------------"
    libtool_sys_lib_path || EXITCODE=$?
    patch_sqlite3_libtool || EXITCODE=$?
    (( EXITCODE != 0 )) && echo "Error patching <libtool>" && exit 203
  fi

  cp "${BASEDIR}/sqlite3.ref.mk" "${BASEDIR}/${BUILDDIR}" \
    || ( echo "Cannot copy make file" && exit 204 )
  make -C "${BASEDIR}/${BUILDDIR}" -f "sqlite3.ref.mk" all
  return 0
}

main "$@"