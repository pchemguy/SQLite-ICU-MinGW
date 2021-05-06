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
readonly BUILDDIR=${DBDIR}/build


setenv_sqliteodbc() {
  SQLITE_DLLS=${SQLITE_DLLS:-}
  ADD_NSIS=${ADD_NSIS:-}

  if [[ "${SQLITE_DLLS}" == "2" ]]; then
    # turn on -DSQLITE_DYNLOAD in sqlite3odbc.c
    export ADD_CFLAGS="-DWITHOUT_SHELL=1 -DWITH_SQLITE_DLLS=2"
    ADD_NSIS="${ADD_NSIS} -DWITHOUT_SQLITE3_EXE"
  elif [[ -n "${SQLITE_DLLS}" ]]; then
    export ADD_CFLAGS="-DWITHOUT_SHELL=1 -DWITH_SQLITE_DLLS=1"
    export SQLITE3_DLL="-Lsqlite3 -lsqlite3"
    ADD_NSIS="${ADD_NSIS} -DWITHOUT_SQLITE3_EXE -DWITH_SQLITE_DLLS"
  else
    export SQLITE3_A10N_O="sqlite3.o"
    ADD_NSIS="${ADD_NSIS} -DWITHOUT_SQLITE3_EXE"
  fi

  export NO_SQLITE2=1
  export NO_TCCEXT=1
  export ADD_NSIS

  return 0
}  


main() {
  LOG_FILE=${LOG_FILE:-makelog.log}
  echo "SQLITE_DLLS=${SQLITE_DLLS:-};" "$0" "$@" >>"${LOG_FILE}"
  echo "###############################################################" >>"${LOG_FILE}"
  echo "" >>"${LOG_FILE}"

  "${BASEDIR}/sqlite3.ref.sh" all || EXITCODE=$?
  (( EXITCODE != 0 )) && echo "Error preparing SQLite3" && exit 201
  cp "${DBDIR}/build/sqlite3.o" "${BASEDIR}" \
    || ( echo "Cannot copy SQLite3 binaries" && exit 202 )
  setenv_sqliteodbc || EXITCODE=$?
  (( EXITCODE != 0 )) && echo "Error setting env for SQLiteODBC" && exit 201

  echo "================================================"
  echo "Building ODBC drivers, utils, and NSIS installer"
  echo "================================================"
  make -C "${BASEDIR}" -f Makefile_d.mingw all

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

echo "==========================="
echo "Creating NSIS installer ..."
echo "==========================="
cp -p README readme.txt
unix2dos < license.terms > license.txt || todos < license.terms > license.txt
makensis $ADD_NSIS sqlite3odbc_w32.nsi
