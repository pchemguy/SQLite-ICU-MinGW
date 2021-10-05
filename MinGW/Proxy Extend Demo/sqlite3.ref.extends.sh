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
readonly AMALNAME="sqlite3.c"
readonly LIBNAME="sqlite3.dll"
readonly BUILDDIR=${DBDIR}/build
CFLAGS_EXTRAS=""
LIBS=""
OPT_FEATURE_FLAGS=""


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

  if [[ ! -f "Makefile.bak" ]]; then
    cp "Makefile" "Makefile.bak" || ( echo "Cannot copy Makefile" && exit 109 )
  fi
  
  sed -e "s|^TOP = \(.*\)$|TOP = ${BASEDIR}/${DBDIR}|;" \
      -e 's|^CFLAGS =\(.*\)$|CFLAGS :=\1 \${CFLAGS}|;' \
      -e 's|^\(TCC = \${CC} \${CFLAGS}\)\( [^$]\)|\1 \${CFLAGS_EXTRAS}\2|;' \
      -e 's|^OPT_FEATURE_FLAGS =\(.*\)$|OPT_FEATURE_FLAGS :=\1 \$(OPT_FEATURE_FLAGS)|;' \
      -e "s| _//' >>sqlite3.def$|sqlite3_/sqlite3_/' >>sqlite3.def|;" \
      -e "s/' T ' | grep ' _sqlite3_'/-E ' T .?sqlite3_'/;" \
      <Makefile.bak >Makefile

  readonly DAPI="-DSQLITE_API=__declspec\\\\(dllexport\\\\)"
  sed -e "/^sqlite3.lo:\tsqlite3.c$/i sqlite3.lo: DAPI = ${DAPI}" \
      -e "s|\(\$(TEMP_STORE) -c sqlite3.c\)$|\$(DAPI) \1|;" \
      -i Makefile

  readonly WlExtra="-Wl,--strip-all -Wl,--subsystem,windows,--kill-at"
  pattern="\(\nsqlite3.dll: [^\n]*def\n\)\(\t[^\n]*def \)\\\\\n[\t ]*-Wl[^ ]* \([^\n]*\)"
  replace="\nsqlite3.dll: WlExtra = ${WlExtra}\1\2\$(WlExtra) \3 \$(LIBS)"
  sed -z "s|${pattern}|${replace}|;" \
      -i Makefile
  
  return 0
}


set_sqlite3_extra_options() {
  DEFAULT_LIBS="-lpthread -lm -ldl"
  #LIBOPTS="-static"
  LIBOPTS="-static-libgcc -static-libstdc++"
  LIBS+=" ${LIBOPTS}"
  
  ICU_CFLAGS="$(icu-config --cflags --cppflags)"
  #ICU_CFLAGS="$("${BASEDIR}/icu/dist/bin/icu-config" --noverify --cflags --cppflags)"
  CFLAGS_EXTRAS+=" ${ICU_CFLAGS}"
  #ICU_LDFLAGS="$("${BASEDIR}/icu/dist/bin/icu-config" --noverify --ldflags)"
  #ICU_LDFLAGS="-Wl,-Bstatic $(./icu/dist/bin/icu-config --noverify --ldflags)"
  ICU_LDFLAGS="$(icu-config --ldflags)"
  LIBS+=" ${ICU_LDFLAGS}"
  local libraries
  IFS=$' \n\t'
    libraries=(${DEFAULT_LIBS})
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
    -DSQLITE_APICALL=__stdcall
    -DSQLITE_CDECL=__cdecl
  )

  FEATURES=("${FEATURES[@]}" "${ABI_STDCALL[@]}")

  OPT_FEATURE_FLAGS="${FEATURES[@]}"
  
  export CFLAGS_EXTRAS OPT_FEATURE_FLAGS LIBS
  return 0
}


append_demo_to_sqlite3c() {
  cd "${BASEDIR}/${BUILDDIR}" \
    || ( echo "Cannot enter ./${BUILDDIR}" && exit 115 )
  echo "_______________________________"
  echo "Appending demo to sqlite3.c... "
  echo "-------------------------------"

  outfile="${AMALNAME}"
  
  pattern="\(\n/[*]\+ End of sqlite3.c [*]\+/\n\).*"
  replace="\1"
  sed -z "s|${pattern}|${replace}|;" \
      -i "${outfile}"
  
  printf "%s\n\n" "" >>"${outfile}"
(
cat <<'EOD'
/************************ Begin file demo.h *********************************/
#ifndef DEMO_H
#define DEMO_H

#ifdef __cplusplus
extern "C"
{
#endif

SQLITE_API int SQLITE_APICALL demo_sqlite3_extension_adapter(int);

#ifdef __cplusplus
} // __cplusplus defined.
#endif

#endif /* DEMO_H */
/************************ End of demo.h *************************************/


/************************ Begin file demo.c *********************************/
/* #include "demo.h" */

SQLITE_API int SQLITE_APICALL demo_sqlite3_extension_adapter(int dummy){
  return sqlite3_libversion_number() + dummy;
}
/************************ End of demo.c *************************************/
EOD
) >>"${outfile}"
}


copy_dependencies() {
  echo "________________________"
  echo "Copying dependencies... "
  echo "------------------------"
  readonly BUILDBINDIR=${BUILDDIR}/bin
  readonly SRCBINDIR=${MSYSTEM_PREFIX}/bin
  readonly DEPENDENCIES=(
    libgcc_s_dw2-1.dll
    libicudt68.dll
    libicuin68.dll
    libicuuc68.dll
    libstdc++-6.dll
    libwinpthread-1.dll
  )

  mkdir -p "${BASEDIR}/${BUILDBINDIR}"

  for dependency in "${DEPENDENCIES[@]}"; do
    cp "${SRCBINDIR}/${dependency}" "${BASEDIR}/${BUILDBINDIR}" \
      || ( echo "Cannot copy ${dependency}" && exit 109 )
  done
  cp "${BASEDIR}/${BUILDDIR}/${LIBNAME}" "${BASEDIR}/${BUILDBINDIR}" \
    || ( echo "Cannot copy ${LIBNAME}" && exit 110 )
  
  return 0
}


main() {
  readonly TARGETS=(${@:-all dll})
  export LOG_FILE=${LOG_FILE:-${BASEDIR}/makelog.log}
  { 
    echo "$0" "$@";
    echo "###############################################################";
    echo "";
  } >>"${LOG_FILE}"

  readonly MAKEDEBUG="${MAKEDEBUG:-}"
  if [[ "${MAKEDEBUG}" != "1" ]]; then
    readonly MAKEFLAGS="-j6"
  else
    readonly MAKEFLAGS="-n"
  fi

  get_sqlite || EXITCODE=$?
  (( EXITCODE != 0 )) && echo "Error downloading SQLite3" && exit 201
  configure_sqlite || EXITCODE=$?
  (( EXITCODE != 0 )) && echo "Error configuring SQLite3" && exit 202
  patch_sqlite3_makefile || EXITCODE=$?

  echo "_____________________"
  echo "Patching complete... "
  echo "---------------------"

  set_sqlite3_extra_options || EXITCODE=$?

  cd "${BASEDIR}/${BUILDDIR}" \
    || ( echo "Cannot enter ./${BUILDDIR}" && exit 204 )
  echo "__________________"
  echo "Making targets... "
  echo "------------------"
  make ${MAKEFLAGS} "${AMALNAME}"
  append_demo_to_sqlite3c || EXITCODE=$?
  make ${MAKEFLAGS} ${TARGETS[@]}

  if [[ -f "${BASEDIR}/${BUILDDIR}/${LIBNAME}" ]]; then
    copy_dependencies || EXITCODE=$?
  fi
  return 0
}


main "$@"
