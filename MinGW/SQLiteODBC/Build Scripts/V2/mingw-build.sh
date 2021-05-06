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


SQLITE_DLLS="${SQLITE_DLLS:-}"
SQLITE3_DLL="${SQLITE3_DLL:-}"
ADD_CFLAGS="${ADD_CFLAGS:-}"
ADD_NSIS="${ADD_NSIS:-}"
SQLITE3_A10N_O="${SQLITE3_A10N_O:-}"
sqliteodbc_flags() {
  if [[ "${SQLITE_DLLS}" = "2" ]]; then
    ADD_CFLAGS="-DWITHOUT_SHELL=1 -DWITH_SQLITE_DLLS=2"
    ADD_NSIS="${ADD_NSIS} -DWITHOUT_SQLITE3_EXE"
  elif [[ -n "${SQLITE_DLLS}" ]]; then
    ADD_CFLAGS="-DWITHOUT_SHELL=1 -DWITH_SQLITE_DLLS=1"
    SQLITE3_DLL="-Lsqlite3 -lsqlite3"
    ADD_NSIS="${ADD_NSIS} -DWITHOUT_SQLITE3_EXE -DWITH_SQLITE_DLLS"
  else
    SQLITE3_A10N_O="sqlite3a10n.o"
    ADD_NSIS="${ADD_NSIS} -DWITHOUT_SQLITE3_EXE"
  fi

  export SQLITE3_A10N_O ADD_CFLAGS SQLITE3_DLL
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


gen_sqlite3_amalgamation() {
  echo "__________________________________"
  echo "Generating SQLite3 amalgamation..."
  echo "----------------------------------"
  make -C "${BUILDDIR}" sqlite3.c || EXITCODE=$?
  (( EXITCODE != 0 )) && echo "Error generating SQLite3 amalgamation" && exit 109
  return 0
}


patch_sqlite3_libshell_c() {
  echo "__________________________________________________________________"
  echo "Adjust names of the entry point and appendText in (lib)shell.c ..."
  echo "------------------------------------------------------------------"  
  cp "${BUILDDIR}/shell.c" "${BUILDDIR}/libshell.c" || EXITCODE=$?
  (( EXITCODE != 0 )) && echo "Error copying <shell.c>." && exit 110
  sed -e 's/^int SQLITE_CDECL main/int SQLITE_CDECL sqlite3_main/;' \
      -e 's/appendText/shAppendText/g;' \
      -i "${BUILDDIR}/libshell.c"
  return 0
}


extend_amalgamation() {
  echo "_________________________________"
  echo "Extending SQLite3 amalgamation..."
  echo "---------------------------------"
  cd "${BUILDDIR}/.."
  echo "/************************** Begin config.h ********************************/" >./sqlite3.c
  cat "${BUILDDIR}/config.h" >>./sqlite3.c
  echo "/************************** End config.h **********************************/" >>./sqlite3.c
  echo "/************************** Begin sqlite3.c *******************************/" >>./sqlite3.c
  cat "${BUILDDIR}/sqlite3.c" >>./sqlite3.c
  echo "/************************** Begin libshell.c ******************************/" >>./sqlite3.c
  cat "${BUILDDIR}/libshell.c" >>./sqlite3.c
  echo "/************************** End libshell.c ********************************/" >>./sqlite3.c

  return 0
}


build_odbc() {
  echo "==============================="
  echo "Building ODBC drivers and utils"
  echo "==============================="
  make -C "${BASEDIR}" -f Makefile_d.mingw all

  return 0
}


make_nsis() {
  echo "==========================="
  echo "Creating NSIS installer ..."
  echo "==========================="
  cd "${BASEDIR}"
  cp README readme.txt && cp license.terms license.txt || EXITCODE=$?
  (( EXITCODE != 0 )) && echo "Error copying nsis files." && exit 110
  IFS=$' \n\t'
  ADD_NSIS=(${ADD_NSIS})
  IFS=$'\n\t'
  makensis ${ADD_NSIS[@]} sqliteodbc.nsi  
  return 0
}


main() {
  LOG_FILE=${LOG_FILE:-makelog.log}
  echo "SQLITE_DLLS=${SQLITE_DLLS:-};" "$0" "$@" >>"${LOG_FILE}"
  echo "###############################################################" >>"${LOG_FILE}"
  echo "" >>"${LOG_FILE}"

  sqliteodbc_flags
  get_sqlite
  configure_sqlite
  gen_sqlite3_amalgamation
  patch_sqlite3_libshell_c
  extend_amalgamation
  build_odbc
  make_nsis

  return 0
}


main "$@"

exit 0







#-DSQLITE_ENABLE_ICU \


#make -f ../../mf-sqlite3.mingw32 exe

#sqlite3.c
#make "OPTS=$FEATURES $CFLAGS" dll

echo "=================================================="
exit



#VER=`sqlite3 -version | awk '{split($0, ver, " "); split(ver[1], v, "."); print(v[1] v[2] "0" v[3] "00")}'`
#wget -c https://sqlite.org/2021/sqlite-amalgamation-${VER}.zip \
#      --no-check-certificate -O sqlite3.zip
#rm -rf sqlite3
#rm -rf sqlite-amalgamation-${VER}
#unzip sqlite3.zip
#mv "sqlite-amalgamation-${VER}" sqlite3

#echo "======================================================="
#echo "Append shell.c entry point declaration to sqlite3.h ..."
#echo "======================================================="
#
#cat >>sqlite3/sqlite3.h <<'EOD'
#/************** Begin of libshell.h *************************************/
##ifndef LIBSHELL_H
##define LIBSHELL_H
#  
#int sqlite3_main(int argc, char **argv);
#
##endif /* LIBSHELL_H */
#/************** End of libshell.h ***************************************/
#EOD


#echo "============================================================="
#echo "Adjust names of the entry point and appendText in shell.c ..."
#echo "============================================================="
#
#sed -e 's/^int SQLITE_CDECL main/int SQLITE_CDECL sqlite3_main/;' \
#    -e 's/appendText/shAppendText/g;' \
#    -i ./sqlite3/shell.c
#  OPT_FEATURE_FLAGS=" \
#  -DSQLITE_DQS=0 \
#  -DSQLITE_LIKE_DOESNT_MATCH_BLOBS \
#  -DSQLITE_MAX_EXPR_DEPTH=0 \
#  -DSQLITE_OMIT_DEPRECATED \
#  -DSQLITE_DEFAULT_FOREIGN_KEYS=1 \
#  -DSQLITE_DEFAULT_SYNCHRONOUS=1 \
#  -DSQLITE_ENABLE_COLUMN_METADATA \
#  -DSQLITE_ENABLE_DBPAGE_VTAB \
#  -DSQLITE_ENABLE_DBSTAT_VTAB \
#  -DSQLITE_ENABLE_EXPLAIN_COMMENTS \
#  -DSQLITE_ENABLE_FTS3_PARENTHESIS \
#  -DSQLITE_ENABLE_FTS3_TOKENIZER \
#  -DSQLITE_ENABLE_QPSG \
#  -DSQLITE_ENABLE_RBU \
#  -DSQLITE_ENABLE_STMTVTAB \
#  -DSQLITE_ENABLE_STAT4 \
#  -DSQLITE_SOUNDEX \
#  -DSQLITE_ENABLE_OFFSET_SQL_FUNC\
#  "
#  
#  CFLAGS=" \
#  -static-libgcc \
#  -static-libstdc++ \
#  "
#  export CFLAGS OPT_FEATURE_FLAGS
#
#
exit
echo "==============================="
echo "Building ODBC drivers and utils"
echo "==============================="
make -f Makefile.mingw32 all_no2

