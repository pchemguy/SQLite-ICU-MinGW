#!/bin/bash
#
# Usage example (run from MinGW shell):
#   $ MAKEDEBUG=0 ./sqlite3.ref.sh "sqlite3.c sqlite3.h dll"
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
readonly BASEDIR="$(dirname "$(realpath "$0")")"
readonly DBDIR="sqlite"
readonly SRC="${BASEDIR}/${DBDIR}"
readonly LIBNAME="sqlite3.dll"
readonly SHNAME="sqlite3.exe"
readonly DEFNAME="sqlite3.def"
readonly BUILDDIR="build"
readonly WITH_EXTRA_EXT="${WITH_EXTRA_EXT:-1}"
readonly WITH_TEST_FIX="${WITH_TEST_FIX:-1}"
readonly USE_ICU="${USE_ICU:-1}"
readonly USE_ZLIB="${USE_ZLIB:-1}"
readonly USE_SQLAR="${USE_SQLAR:-1}"
CFLAGS_EXTRAS=""
LIBS=""
OPT_FEATURE_FLAGS=""
ADDRESS_SIZE=""


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
    [[ ! -r "${SRC}/configure" ]] && echo "Error accessing SQLite configure" \
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

    lt_cv_deplibs_check_method="pass_all" \
      "${SRC}/configure" ${CONFIGURE_OPTS[@]} || EXITCODE=$?
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
      -e 's|^\(dll:.*\)$|\1\nexe: sqlite3\$(TEXE)|;' \
      -e "s/' T ' | grep ' _sqlite3_'/-E '^.{${ADDRESS_SIZE}} (T|R|B) _?sqlite3'/;" \
      -e "s| _//' >>sqlite3.def$| _\\\\?sqlite3/    sqlite3/' >>sqlite3.def|;" \
      <Makefile.bak >Makefile

  pattern="\t\t-Wl,\"\?--strip-all\"\? \(\$(REAL_LIBOBJ)\)"
  replace="\t\t-Wl,--strip-all -Wl,--subsystem,windows,--kill-at \1 \$(LIBS)"
  sed -e "s|^${pattern}|${replace}|" \
      -i Makefile

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
  
  sed -e "s|*\(sqlite3_sourceid\)|*SQLITE_APICALL \1|;" \
      <mksqlite3c.tcl.bak >mksqlite3c.tcl

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
  
  if [[ "${USE_ICU}" -eq 1 ]]; then
    ICU_CFLAGS="$(icu-config --cflags --cppflags)"
    #ICU_CFLAGS="$("${BASEDIR}/icu/dist/bin/icu-config" --noverify --cflags --cppflags)"
    #ICU_LDFLAGS="$("${BASEDIR}/icu/dist/bin/icu-config" --noverify --ldflags)"
    #ICU_LDFLAGS="-Wl,-Bstatic $(./icu/dist/bin/icu-config --noverify --ldflags)"
    ICU_LDFLAGS="$(icu-config --ldflags)"
  fi
  if [[ "${USE_ZLIB}" -eq 1 ]]; then 
    ZLIB_CFLAGS="$(pkg-config --cflags zlib)"
    ZLIB_LDFLAGS="$(pkg-config --libs zlib)"
  fi
  CFLAGS_EXTRAS+=" ${ICU_CFLAGS:-} ${ZLIB_CFLAGS:-}"
  LIBS+=" ${ICU_LDFLAGS:-} ${ZLIB_LDFLAGS:-}"

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
    -DSQLITE_ENABLE_API_ARMOR=1
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
    -DSQLITE_ENABLE_QPSG
    -DSQLITE_ENABLE_RBU
    -DSQLITE_ENABLE_STMTVTAB
    -DSQLITE_ENABLE_STAT4
    -DSQLITE_USE_URI=1
    -DSQLITE_SOUNDEX
    -DNDEBUG
  )
  [[ "${USE_ICU}" -eq 1 ]] && FEATURES=(${FEATURES[@]} "-DSQLITE_ENABLE_ICU")
    
  if [[ "${WITH_EXTRA_EXT}" -eq 1 ]]; then
    if [[ "${USE_ZLIB}" -eq 1 ]]; then
      EXTRA_EXTS=(-DSQLITE_ENABLE_ZIPFILE)
      if [[ "${USE_SQLAR}" -eq 1 ]]; then
        EXTRA_EXTS=(${EXTRA_EXTS[@]} -DSQLITE_ENABLE_SQLAR)
      fi
    fi
    EXTRA_EXTS=(${EXTRA_EXTS[@]:-}
      -DSQLITE_ENABLE_CSV
      -DSQLITE_ENABLE_REGEXP
      -DSQLITE_ENABLE_SERIES
      -DSQLITE_ENABLE_SHA
      -DSQLITE_ENABLE_SHATHREE
      -DSQLITE_ENABLE_UINT
      -DSQLITE_ENABLE_UUID
    )
  fi
  OPT_FEATURE_FLAGS="${FEATURES[@]} ${EXTRA_EXTS[@]:-}"

  export CFLAGS_EXTRAS OPT_FEATURE_FLAGS LIBS
  return 0
}


extras() {
  cd "${BASEDIR}/extra/${BUILDDIR}" && \
    ls -1 *.ext | xargs -I{} cp {} "${BASEDIR}/${BUILDDIR}" \
    || ( echo "Cannot copy extras" && exit 109 )
  cd "${BASEDIR}/extra" && ls -1 *.tcl | xargs -I{} cp {} "${BASEDIR}" \
    || ( echo "Cannot copy extras" && exit 109 )
  cp -r "${BASEDIR}/extra/${DBDIR}" "${BASEDIR}" \
    || ( echo "Cannot copy extras" && exit 109 )

  TARGETDIR="${BASEDIR}/${BUILDDIR}"
  FILENAME="Makefile"
  echo "========== Patching ${FILENAME} ==========="
  "${BASEDIR}/addlines.tcl" "${FILENAME}" "${FILENAME}.ext" "${TARGETDIR}"
  cd "${TARGETDIR}" && mv makefile Makefile

  TARGETDIR="${BASEDIR}/${DBDIR}/tool"
  FILENAME="mksqlite3c.tcl"
  echo "========== Patching ${FILENAME} ==========="
  "${BASEDIR}/addlines.tcl" "${FILENAME}" "${FILENAME}.ext" "${TARGETDIR}"

  rm "${BASEDIR}/${BUILDDIR}/.target_source" || true
  rm -rf "${BASEDIR}/${BUILDDIR}/tsrc" || true
  make -C "${BASEDIR}/${BUILDDIR}" .target_source \
    || ( echo "Cannot make target_source" && exit 204 )

  cd "${BASEDIR}/extra" && ls -1 | xargs -I{} cp -r {} "${BASEDIR}" \
    || ( echo "Cannot copy extras" && exit 109 )


  TARGETDIR="${BASEDIR}/${BUILDDIR}/tsrc"
  cd "${TARGETDIR}" || ( echo "Cannot enter ${TARGETDIR}" && exit 204 )

  FILENAME="main.c"
  echo "========== Patching ${FILENAME} ==========="
  "${BASEDIR}/addlines.tcl" "${FILENAME}" "${FILENAME}.1.ext" "${TARGETDIR}"
  "${BASEDIR}/addlines.tcl" "${FILENAME}" "${FILENAME}.2.ext" "${TARGETDIR}"

  if [[ "${WITH_TEST_FIX}" -eq 1 ]]; then
    "${BASEDIR}/addlines.tcl" "${FILENAME}" "${FILENAME}.test" "${TARGETDIR}"

    FILENAME="sqlite3.h"
    echo "========== Patching ${FILENAME} ==========="
    "${BASEDIR}/addlines.tcl" "${FILENAME}" "${FILENAME}.test" "${TARGETDIR}"
  fi
  

  FILENAME="normalize.c"
  echo "========== Patching ${FILENAME} ==========="
  sed -e 's|^int main|int sqlite3_normalize_main|;' -e 's|CC_|CCN_|g;' \
      -e 's|CCN__|CC__|g;' -e 's|TK_|TKN_|g;' -e 's|aiClass|aiClassN|g;' \
      -e 's|sqlite3UpperToLower|sqlite3UpperToLowerN|g;' \
      -e 's|sqlite3CtypeMap|sqlite3CtypeMapN|g;' \
      -e 's|sqlite3GetToken|sqlite3GetTokenN|g;' -e 's|IdChar|IdCharN|g;' \
      -e 's|sqlite3I|sqlite3NI|g;' -e 's|sqlite3T|sqlite3NT|g;' \
      -i ${FILENAME}

  FILENAME="regexp.c"
  echo "========== Patching ${FILENAME} ==========="
  sed -e 's|<string.h>\$|<sqlite3ext.h>|;' \
      -e 's|"sqlite3ext.h"\$|<string.h>|;' \
      -i ${FILENAME}

  FILENAME="sha1.c"
  echo "========== Patching ${FILENAME} ==========="
  sed -e 's|hash_step_vformat|hash_step_vformat_sha1|g;' \
      -i ${FILENAME}

  FILENAME="zipfile.c"
  echo "========== Patching ${FILENAME} ==========="
  FLAG="SQLITE_ENABLE_ZIPFILE"
  sed -e 's|^static int zipfileRegister|int zipfileRegister|;' \
      -e "s|^#include .sqlite3ext.h.\$|#if defined(${FLAG})\n\n\0|;" \
      -i ${FILENAME}
  echo "" >>${FILENAME}
  echo "#endif /* defined(${FLAG}) */" >>${FILENAME}

  FLAG="CSV"      FILENAME=""       ext_patch_base
  FLAG="REGEXP"   FILENAME=""       ext_patch_base
  FLAG="SERIES"   FILENAME=""       ext_patch_base
  FLAG="UINT"     FILENAME=""       ext_patch_base
  FLAG="UUID"     FILENAME=""       ext_patch_base
  FLAG="SQLAR"    FILENAME=""       ext_patch_base
  FLAG="SHATHREE" FILENAME=""       ext_patch_base
  FLAG="SHA"      FILENAME="sha1.c" ext_patch_base

  return 0
}


# Before call, set
#   FLAG - SQLITE_ENABLE_XXX flag suffix (XXX)
#   FILENAME - name of the file or blank
#   TARGETDIR - file location
ext_patch_base() {
  [[ -z "${FILENAME}" ]] \
    && FILENAME="$(echo "${FLAG}" | tr '[:upper:]' '[:lower:]').c"
  FLAG="SQLITE_ENABLE_${FLAG}"
  echo "========== Patching ${FILENAME} ==========="

  sed -e "s|^#include .sqlite3ext.h.\$|#if defined(${FLAG})\n\n\0|;" \
      -i ${FILENAME}
  echo "" >>${FILENAME}
  echo "#endif /* defined(${FLAG}) */" >>${FILENAME}

  if [[ -f "./${FILENAME}.ext" ]]; then
    "${BASEDIR}/addlines.tcl" "${FILENAME}" "${FILENAME}.ext" "${TARGETDIR}"
  fi

  FILENAME=""

  return 0
}


collect_bins() {
  echo "_______________________"
  echo "Collecting binaries... "
  echo "-----------------------"
  readonly BUILDBINDIR="bin"
  readonly SRCBINDIR="${MSYSTEM_PREFIX}/bin"
  readonly ICUVERSION="$(expr match "$(uconv -V)" '.*ICU \([0-9]*\).*')"
  readonly ICUDLL=(
    libicudt${ICUVERSION}.dll
    libicuin${ICUVERSION}.dll
    libicuuc${ICUVERSION}.dll
  )
  readonly SYSDLL=(
    libgcc_s_*.dll
    libstdc++-6.dll
    libwinpthread-1.dll
  )

  mkdir -p "${BASEDIR}/${BUILDBINDIR}" && cd "${BASEDIR}/${BUILDBINDIR}"

  if [[ "${USE_ICU}" -eq 1 ]]; then
    for dependency in "${SYSDLL[@]}"; do
      dependency="$(ls -1 ${SRCBINDIR}/${dependency})"
      cp "${dependency}" . || ( echo "Cannot copy ${dependency}" && exit 109 )
    done

    for dependency in "${ICUDLL[@]}"; do
      cp "${SRCBINDIR}/${dependency}" . \
        || ( echo "Cannot copy ${dependency}" && exit 109 )
    done
  fi

  if [[ "${USE_ZLIB}" -eq 1 && "${WITH_EXTRA_EXT}" -eq 1 ]]; then
    cp ${SRCBINDIR}/zlib1.dll . || ( echo "Cannot copy zlib1.dll" && exit 109 )
  fi
  
  mv "${BASEDIR}/${BUILDDIR}/${LIBNAME}" . 2>/dev/null \
    || EXITCODE=$?
  mv "${BASEDIR}/${BUILDDIR}/${DEFNAME}" . 2>/dev/null \
    || EXITCODE=$?
  mv "${BASEDIR}/${BUILDDIR}/${SHNAME}" . 2>/dev/null \
    || EXITCODE=$?
  return 0
}


main() {
  readonly DEF_ARG=("dll")
  readonly TARGETS=("${@:-${DEF_ARG[@]}}")
  export LOG_FILE=${LOG_FILE:-${BASEDIR}/makelog.log}
  { 
    echo "$0" "$@";
    echo "###############################################################";
    echo "";
  } >>"${LOG_FILE}"

  [[ "${MSYSTEM}" == "MINGW64" ]] && ADDRESS_SIZE=16 || ADDRESS_SIZE=8

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
  patch_mksqlite3ctcl || EXITCODE=$?
  #patch_mksqlite3htcl || EXITCODE=$?

  set_sqlite3_extra_options || EXITCODE=$?
  [[ "${WITH_EXTRA_EXT}" -eq 1 ]] && extras

  echo "_____________________"
  echo "Patching complete... "
  echo "---------------------"

  cd "${BASEDIR}/${BUILDDIR}" \
    || ( echo "Cannot enter ./${BUILDDIR}" && exit 204 )
  echo "__________________"
  echo "Making targets... "
  echo "------------------"
  make ${MAKEFLAGS} ${TARGETS[@]}

  if [[ -f "${BASEDIR}/${BUILDDIR}/${LIBNAME}" || \
        -f "${BASEDIR}/${BUILDDIR}/${SHNAME}" ]]; then
    collect_bins || EXITCODE=$?
  fi
  return 0
}


main "$@"
