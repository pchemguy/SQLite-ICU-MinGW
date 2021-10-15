#!/bin/sh
#
# Usage example (run from MinGW shell):
#   $ USEAPI=1 ABI=STDCALL MAKEDEBUG=0 ./sqlite3.ref.sh "sqlite3.c sqlite3.h dll"
#
# USEAPI:
#   0/1 - don't/do add SQLITE_API and SQLITE_APICALL to SQLiteAPI
#
# ABI:
#   calling convention, e.g., STDCALL means adding "__stdcall"
#
# MAKEDEBUG:
#   0/1 - add "-j6"/"-n" flags to make command ("-n" - debug print only)
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

  pattern="\t\t-Wl,\"\?--strip-all\"\? \(\$(REAL_LIBOBJ)\)"
  replace="\t\t-Wl,--strip-all -Wl,--subsystem,windows,--kill-at \1 \$(LIBS)"
  sed -e "s|^${pattern}|${replace}|" \
      -i Makefile

  if [[ "${USEAPI:-}" != "" ]]; then
    echo "Enabling ABI conventions for SQLite API."
    readonly USEAPIFLAG="--useapicall"
    patternh="\(^\t\$(TCLSH_CMD) \$(TOP)/tool/mksqlite3h.tcl \$(TOP)\) \(.sqlite3.h\)"
    replaceh="\1 ${USEAPIFLAG} \2"
    sed -e "s|^${patternh}|${replaceh}|;" \
        -e "s|^\(\t\$(TCLSH_CMD) \$(TOP)/tool/mksqlite3c.tcl\)|\1 ${USEAPIFLAG}|;" \
        -e  '/^SHELL_OPT = -D/a SHELL_OPT += -DSQLITE_API=__declspec\\\\(dllimport\\\\)' \
        -i Makefile

    readonly DAPI="-DSQLITE_API=__declspec\\\\(dllexport\\\\)"
    sed -e "/^sqlite3.lo:\tsqlite3.c$/i sqlite3.lo: DAPI = ${DAPI}" \
        -e "s|\(\$(TEMP_STORE) -c sqlite3.c\)$|\$(DAPI) \1|;" \
        -i Makefile
  fi

  return 0
}


patch_mksqlite3ctcl() {
  cd "${BASEDIR}/${DBDIR}/tool" \
    || ( echo "Cannot enter ${BASEDIR}/${DBDIR}/tool" && exit 110 )
  echo "____________________________"
  echo "Patching mksqlite3c.tcl ... "
  echo "----------------------------"

  if [[ ! -f "mksqlite3c.tcl.bak" ]]; then
    cp "mksqlite3c.tcl" "mksqlite3c.tcl.bak" \
      || ( echo "Cannot copy mksqlite3c.tcl" && exit 111 )
  fi
  
  if [[ "${USEAPI:-}" != "" ]]; then
    sed -e "s|*\(sqlite3_sourceid\)|*SQLITE_APICALL \1|;" \
      <mksqlite3c.tcl.bak >mksqlite3c.tcl
  fi

  return 0
}


patch_mksqlite3htcl() {
  cd "${BASEDIR}/${DBDIR}/tool" \
    || ( echo "Cannot enter ${BASEDIR}/${DBDIR}/tool" && exit 112 )
  echo "____________________________"
  echo "Patching mksqlite3h.tcl ... "
  echo "----------------------------"

  if [[ ! -f "mksqlite3h.tcl.bak" ]]; then
    cp "mksqlite3h.tcl" "mksqlite3h.tcl.bak" \
      || ( echo "Cannot copy mksqlite3h.tcl" && exit 113 )
  fi
  
  # SQLite3RBU API is missing from SQLite3.h
  sed -e '/sqlite3rebaser_/a \
         \nset declpattern6 \\\n    {^ *([a-zA-Z][a-zA-Z_0-9 ]+ \\**)(sqlite3rbu_[_a-zA-Z0-9]+)(\\(.*)$}' \
      -e '/TOP\/ext\/fts5\/fts5.h$/a \  $TOP/ext/rbu/sqlite3rbu.h' \
      -e 's/\(all rettype funcname rest]\)\} {$/\1 || \\\
          [regexp $declpattern6 $line all rettype funcname rest]} {/;' \
    <mksqlite3h.tcl.bak >mksqlite3h.tcl

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
    -DSQLITE_ENABLE_NORMALIZE
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

  if [[ "${ABI}" == "STDCALL" ]]; then
    echo "Using Stdcall ABI"
    FEATURES=("${FEATURES[@]}" "${ABI_STDCALL[@]}")
  fi

  OPT_FEATURE_FLAGS="${FEATURES[@]}"
  
  export CFLAGS_EXTRAS OPT_FEATURE_FLAGS LIBS
  return 0
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

  # Build STDCALL version:
  # $ USEAPI=1 ABI=STDCALL MAKEDEBUG=0 ./sqlite3.ref.sh
  readonly USEAPI="${USEAPI:-}"
  readonly ABI="${ABI:-}"

  get_sqlite || EXITCODE=$?
  (( EXITCODE != 0 )) && echo "Error downloading SQLite3" && exit 201
  configure_sqlite || EXITCODE=$?
  (( EXITCODE != 0 )) && echo "Error configuring SQLite3" && exit 202
  patch_sqlite3_makefile || EXITCODE=$?
  patch_mksqlite3ctcl || EXITCODE=$?
  #patch_mksqlite3htcl || EXITCODE=$?

  echo "_____________________"
  echo "Patching complete... "
  echo "---------------------"

  set_sqlite3_extra_options || EXITCODE=$?

  cd "${BASEDIR}/${BUILDDIR}" \
    || ( echo "Cannot enter ./${BUILDDIR}" && exit 204 )
  echo "__________________"
  echo "Making targets... "
  echo "------------------"
  make ${MAKEFLAGS} ${TARGETS[@]}

  if [[ -f "${BASEDIR}/${BUILDDIR}/${LIBNAME}" ]]; then
    copy_dependencies || EXITCODE=$?
  fi
  return 0
}


main "$@"
