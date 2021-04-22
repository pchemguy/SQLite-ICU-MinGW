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
CFLAGS_EXTRAS=""
LIBS=""
OPT_FEATURE_FLAGS=""
SERVER_API=""
CLIENT_API=""


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

  if [[ ! -f ./Makefile ]]; then
    [[ ! -r ../configure ]] && echo "Error accessing SQLite configure"
      && exit 105
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
  sed -e "s|^TOP = \(.*\)$|TOP = ${BASEDIR}/${DBDIR}|;" \
      -e 's|^CFLAGS =\(.*\)$|CFLAGS :=\1 \${CFLAGS}|;' \
      -e 's|^\(TCC = \${CC} \${CFLAGS}\)\( [^$]\)|\1 \${CFLAGS_EXTRAS}\2|;' \
      -e 's|^OPT_FEATURE_FLAGS =\(.*\)$|OPT_FEATURE_FLAGS :=\1 \$(OPT_FEATURE_FLAGS)|;' \
      -e 's|\(--strip-all.*\$(REAL_LIBOBJ)\)\( \$(LIBS)\)*|\1 \$(LIBS)|;' \
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
  local msys_rot
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
    folder="$(realpath -q "${folder}" || true)"
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
  local mingw_ld
  mingw_ld="$(which ld.exe)"
  sed -e 's|^\(deplibs_check_method=\)"file_magic\(.*\)$|#\0\n\1"pass_all"|;' \
      -e "s|^LD=\(.*\)\$|LD=\"${mingw_ld}\"|;" \
      -e "s|^\(sys_lib_search_path_spec=\)\(.*\)\$|\1\"${sys_lib_path}\"|;" \
      -i libtool
  return 0
}


set_sqlite3_extra_options() {
  DEFAULT_LIBS="-lpthread -lm -ldl"
  LIBOPTS="-static-libgcc -static-libstdc++"
  LIBS+="${LIBOPTS}"
  
  ICU_CFLAGS="$(icu-config --cflags --cppflags)"
  CFLAGS_EXTRAS+="${ICU_CFLAGS}"
  ICU_LDFLAGS="$(icu-config --ldflags --ldflags-system)"
  LIBS+="${ICU_LDFLAGS}"
  local libraries
  IFS=$' \n\t'
    libraries=( ${DEFAULT_LIBS} )
  IFS=$'\n\t'
  local library
  for library in "${libraries[@]}"; do
    if [[ -n "${LIBS##*${library}*}" ]]; then
      LIBS+=" ${library}"
    fi
  done
  
  FEATURES=" \
    -D_HAVE_SQLITE_CONFIG_H \
    -DSQLITE_DQS=0 \
    -DSQLITE_LIKE_DOESNT_MATCH_BLOBS \
    -DSQLITE_MAX_EXPR_DEPTH=0 \
    -DSQLITE_OMIT_DEPRECATED \
    -DSQLITE_DEFAULT_FOREIGN_KEYS=1 \
    -DSQLITE_DEFAULT_SYNCHRONOUS=1 \
    -DSQLITE_ENABLE_COLUMN_METADATA \
    -DSQLITE_ENABLE_DBPAGE_VTAB \
    -DSQLITE_ENABLE_DBSTAT_VTAB \
    -DSQLITE_ENABLE_EXPLAIN_COMMENTS \
    -DSQLITE_ENABLE_FTS3 \
    -DSQLITE_ENABLE_FTS3_PARENTHESIS \
    -DSQLITE_ENABLE_FTS3_TOKENIZER \
    -DSQLITE_ENABLE_FTS4 \
    -DSQLITE_ENABLE_FTS5 \
    -DSQLITE_ENABLE_GEOPOLY \
    -DSQLITE_ENABLE_MATH_FUNCTIONS \
    -DSQLITE_ENABLE_JSON1 \
    -DSQLITE_ENABLE_QPSG \
    -DSQLITE_ENABLE_RBU \
    -DSQLITE_ENABLE_ICU \
    -DSQLITE_ENABLE_RTREE \
    -DSQLITE_ENABLE_STMTVTAB \
    -DSQLITE_ENABLE_STAT4 \
    -DSQLITE_SOUNDEX \
    -DNDEBUG"
    
  ABI_STDCALL=" \
    -DSQLITE_CDECL=__cdecl \
    -DSQLITE_APICALL=__stdcall \
    -DSQLITE_CALLBACK=__stdcall \
    -DSQLITE_SYSAPI=__stdcall \
    -DSQLITE_TCLAPI=__cdecl"

  if [[ "${ABI:-}" == "STDCALL" ]]; then
    echo "Using Stdcall ABI"
    FEATURES+="${ABI_STDCALL}"
  fi

  SERVER_API="-DSQLITE_API=__declspec(dllexport)"
  CLIENT_API="-DSQLITE_API=__declspec(dllimport)"

  OPT_FEATURE_FLAGS="${FEATURES//    /}"
  
  export CFLAGS_EXTRAS OPT_FEATURE_FLAGS LIBS
  return 0
}


main() {
  export LOG_FILE=${LOG_FILE:-${BASEDIR}/makelog.log}
  { 
    echo "$0" "$@";
    echo "###############################################################";
    echo "";
  } >>"${LOG_FILE}"

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

  set_sqlite3_extra_options || EXITCODE=$?

  cd "${BASEDIR}/${BUILDDIR}" \
    || ( echo "Cannot enter ./${BUILDDIR}" && exit 204 )
  make -j6 all dll
  return 0
}


main "$@"
