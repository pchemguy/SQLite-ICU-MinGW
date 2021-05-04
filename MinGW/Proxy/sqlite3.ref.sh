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
    [[ ! -r ../configure ]] && echo "Error accessing SQLite configure" \
      && exit 105
    echo "______________________"
    echo "Configuring SQLite3..."
    echo "----------------------"

    local msys_root
    msys_root="$(cygpath -m /)"
    msys_root="${msys_root%/}"
    local readline_inc
    readline_inc=$(pkg-config --cflags --static readline)
    readline_inc=${readline_inc//${msys_root}/}
    local readline_lib
    readline_lib=$(pkg-config --libs --static readline)
    readline_lib=${readline_lib//${msys_root}/}
    
    local CONFIGURE_OPTS
    CONFIGURE_OPTS=(
      --enable-all
      --enable-fts3
      --enable-memsys5
      --enable-update-limit
      --with-tcl=${MINGW_PREFIX}/lib
      --with-readline-lib="${readline_lib}"
      --with-readline-inc="${readline_inc}"
    )

    lt_cv_deplibs_check_method="pass_all" ../configure ${CONFIGURE_OPTS[@]} \
      || EXITCODE=$?
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
  
  FEATURES=(
    -D_HAVE_SQLITE_CONFIG_H
    -DSQLITE_DQS=0
    -DSQLITE_LIKE_DOESNT_MATCH_BLOBS
    -DSQLITE_MAX_EXPR_DEPTH=0
    -DSQLITE_OMIT_DEPRECATED
    -DSQLITE_DEFAULT_FOREIGN_KEYS=1
    -DSQLITE_DEFAULT_SYNCHRONOUS=1
    -DSQLITE_ENABLE_COLUMN_METADATA
    -DSQLITE_ENABLE_DBPAGE_VTAB
    -DSQLITE_ENABLE_DBSTAT_VTAB
    -DSQLITE_ENABLE_EXPLAIN_COMMENTS
    -DSQLITE_ENABLE_FTS3
    -DSQLITE_ENABLE_FTS3_PARENTHESIS
    -DSQLITE_ENABLE_FTS3_TOKENIZER
    -DSQLITE_ENABLE_MATH_FUNCTIONS
    -DSQLITE_ENABLE_QPSG
    -DSQLITE_ENABLE_RBU
    -DSQLITE_ENABLE_ICU
    -DSQLITE_ENABLE_STMTVTAB
    -DSQLITE_ENABLE_STAT4
    -DSQLITE_SOUNDEX
    -DNDEBUG
  )
    
  ABI_STDCALL=(
    -DSQLITE_CDECL=__cdecl
    -DSQLITE_APICALL=__stdcall
    -DSQLITE_CALLBACK=__stdcall
    -DSQLITE_SYSAPI=__stdcall
    -DSQLITE_TCLAPI=__cdecl
  )

  if [[ "${ABI:-}" == "STDCALL" ]]; then
    echo "Using Stdcall ABI"
    FEATURES=("${FEATURES[@]}" "${ABI_STDCALL[@]}")
  fi

  SERVER_API="-DSQLITE_API=__declspec(dllexport)"
  CLIENT_API="-DSQLITE_API=__declspec(dllimport)"

  OPT_FEATURE_FLAGS="${FEATURES[@]}"
  
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

  set_sqlite3_extra_options || EXITCODE=$?

  cd "${BASEDIR}/${BUILDDIR}" \
    || ( echo "Cannot enter ./${BUILDDIR}" && exit 204 )
  make -j6 ${1:-all dll}
  return 0
}


main "$@"
