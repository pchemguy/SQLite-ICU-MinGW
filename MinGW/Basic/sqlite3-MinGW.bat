@echo off

set Path=C:\dev\msys64\mingw32\bin;%Path%
set SRCDIR=.\src
set INCLUDES=-I. -I.\include
set LIBRARIES=-L. -L.\lib
set BINOUT=.\bin
set LIBOUT=.\lib
set LIBS=-lpthread -ldl -lm
set LIBNAME=sqlite3
set SHELLNAME=%LIBNAME%
if not "%~3" == "" set LIBNAME=%~3
if exist "%SRCDIR%\test_sqllog.c" set TEST_LOG="%SRCDIR%\test_sqllog.c"

rem Get ICU compile options
set CLI=pkg-config --cflags --libs --static icu-i18n
for /f "usebackq delims=" %%i in (`%CLI%`) do (set ICU_OPTIONS=%%i)


if /I "%~2" == "stdcall" (
  set STDCALL=1
  set ABI=^
    -DSQLITE_API=^__declspec^(dllexport^) ^
    -DSQLITE_APICALL=__stdcall
)

if /I "%~1" == "dll" (
  if not defined "%STDCALL%" (
    set SOURCES="%SRCDIR%\sqlite3.c" %TEST_LOG%
    if exist "%SRCDIR%\test_sqllog.c" set SQLLOG=-DSQLITE_ENABLE_SQLLOG
  ) else (
    set SOURCES="%SRCDIR%\sqlite3.c"
  )
  set BINNAM=lib%LIBNAME%-0.dll
  set SHARED=-shared
  set LIBFLAGS=-static-libgcc -static-libstdc++ -Wl,--subsystem,windows,--kill-at,--output-def,"%LIBOUT%\%LIBNAME%.def",--out-implib,"%LIBOUT%\lib%LIBNAME%.a"
)
if /I "%~1" == "exe" (
  if not defined "%STDCALL%" (
    set SOURCES="%SRCDIR%\shell.c" "%SRCDIR%\sqlite3.c" %TEST_LOG%
    if exist "%SRCDIR%\test_sqllog.c" set SQLLOG=-DSQLITE_ENABLE_SQLLOG
  ) else (
    set SOURCES="%SRCDIR%\shell.c" "%SRCDIR%\sqlite3.c"
  )
  set BINNAM=%SHELLNAME%.exe
  set LIBFLAGS=-static-libgcc -static-libstdc++
)
if /I "%~1" == "shell" (
  set SOURCES="%SRCDIR%\shell.c"
  set BINNAM=%SHELLNAME%.exe
  set LIBFLAGS=-static-libgcc -static-libstdc++
  set LIBS=%LIBS% -l%LIBNAME%
)

if /I "%~1" == "" (
  echo Build target must be specified
  exit /b 1
)


set FEATURES=^
-DSQLITE_DQS=0 ^
-DSQLITE_LIKE_DOESNT_MATCH_BLOBS ^
-DSQLITE_MAX_EXPR_DEPTH=0 ^
-DSQLITE_OMIT_DEPRECATED ^
-DSQLITE_DEFAULT_FOREIGN_KEYS=1 ^
-DSQLITE_DEFAULT_SYNCHRONOUS=1 ^
-DSQLITE_ENABLE_COLUMN_METADATA ^
-DSQLITE_ENABLE_DBPAGE_VTAB ^
-DSQLITE_ENABLE_DBSTAT_VTAB ^
-DSQLITE_ENABLE_EXPLAIN_COMMENTS ^
-DSQLITE_ENABLE_FTS3 ^
-DSQLITE_ENABLE_FTS3_PARENTHESIS ^
-DSQLITE_ENABLE_FTS3_TOKENIZER ^
-DSQLITE_ENABLE_FTS4 ^
-DSQLITE_ENABLE_FTS5 ^
-DSQLITE_ENABLE_GEOPOLY ^
-DSQLITE_ENABLE_MATH_FUNCTIONS ^
-DSQLITE_ENABLE_JSON1 ^
-DSQLITE_ENABLE_QPSG ^
-DSQLITE_ENABLE_RBU ^
-DSQLITE_ENABLE_ICU ^
-DSQLITE_ENABLE_RTREE ^
-DSQLITE_ENABLE_STMTVTAB ^
-DSQLITE_ENABLE_STAT4 ^
%SQLLOG% ^
-DSQLITE_SOUNDEX


gcc ^
  %INCLUDES% ^
  %LIBRARIES% ^
  %SOURCES% ^
  %LIBS% ^
  %ICU_OPTIONS% ^
  %ABI% ^
  %FEATURES% ^
  %SHARED% ^
  %LIBFLAGS% ^
  -Wall ^
  -o "%BINOUT%\%BINNAM%"

rem   -O2 ^
