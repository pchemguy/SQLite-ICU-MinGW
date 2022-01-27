@echo off
:: ============================================================================
:: Builds SQLite using Microsoft Visual C++ Build Tools (MSVC toolset).
:: MSVC toolset can be installed via a
::   - dedicated installer:
::       https://go.microsoft.com/fwlink/?LinkId=691126
::   - Visual Studio installer (including CE):
::       https://visualstudio.microsoft.com/downloads
:: TCL must also be available, as it is required by the building workflow.
::
:: Usage: run the script with "/?" or see :SHOW_HELP at the end.
:: ===========================================================================


:: ============================= BEGIN DISPATCHER =============================
call :MAIN %*

exit /b 0
:: ============================= END   DISPATCHER =============================


:: ================================ BEGIN MAIN ================================
:MAIN
SetLocal EnableExtensions EnableDelayedExpansion

if "/%VSCMD_ARG_TGT_ARCH%/"=="/x64/" (set ARCH=x64)
if "/%VSCMD_ARG_TGT_ARCH%/"=="/x86/" (set ARCH=x32)
if /I not "/%DBENG:~0,3%/"=="/sql/" set DBENG=sqlite

set BASEDIR=%~dp0
set BASEDIR=%BASEDIR:~0,-1%
set PKGDIR=%BASEDIR%\pkg
set BLDDIR=%BASEDIR%\bld
set DEVDIR=%BASEDIR%\dev
set BINSQL=%BASEDIR%\dev\%DBENG%\%ARCH%
set BLDSQL=%BASEDIR%\bld\%DBENG%\%ARCH%
set SRCSQL=%BASEDIR%\bld\%DBENG%\src

set OUTSQL="%BLDSQL%\sqlout.log"
set ERRSQL="%BLDSQL%\sqlerr.log"
del %OUTSQL% 2>nul
del %ERRSQL% 2>nul
set ResultCode=0
set ERROR_STATUS=0

if not defined USE_STDCALL (
  if "/%ARCH%/"=="/x32/" (set USE_STDCALL=1) else (set USE_STDCALL=0)
)

if not exist "%BLDSQL%" mkdir "%BLDSQL%"
call :SET_TARGETS %*
call :SETENV 1>>%OUTSQL% 2>>%ERRSQL%
echo Building %DBENG%-%ARCH% ...
echo WITH_EXTRA_EXT=%WITH_EXTRA_EXT%
echo USE_STDCALL=%USE_STDCALL%
echo USE_ZLIB=%USE_ZLIB%
echo USE_SQLAR=%USE_SQLAR%
echo USE_LIBSHELL=%USE_LIBSHELL%

call "%~dp0SQLiteCipherSourceGet.bat" %DBENG%
if %ErrorLevel% NEQ 0 exit /b 1
if not exist "%BLDSQL%" (
  echo Distro directory does not exists. Exiting
  exit /b 1
)

(
  copy /Y "%BASEDIR%\scripts\build\*" "%BLDSQL%" 1>nul
  xcopy /H /Y /B /E /Q "%BASEDIR%\scripts\distro" "%SRCSQL%" 1>nul

  call :MAKEFILE_MSC_TOP_AND_DEBUG_ZLIB_STDCALL

  call :RESET_BAK
) 1>>%OUTSQL% 2>>%ERRSQL%

if %WITH_EXTRA_EXT% EQU 1 (
  call :EXT_ADD_SOURCES_TO_MAKEFILE_MSC
  call :EXT_ADD_SOURCES_TO_MKSQLITE3C_TCL
) 1>>%OUTSQL% 2>>%ERRSQL%

(
  echo ==================== MAKING .target_source ====================
  cd /d "%BLDSQL%"
  nmake /nologo /f Makefile.msc .target_source
  echo ~~~~~~~~~~~~~~~~~~~~ MADE  .target_source ~~~~~~~~~~~~~~~~~~~~~
  echo ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
) 1>>%OUTSQL% 2>>%ERRSQL%

if /I "/%DBENG%/"=="/sqlcipher/" if %USE_STDCALL% EQU 1 (
  call :CRYPT_OPENSSL
) 1>>%OUTSQL% 2>>%ERRSQL%

if %WITH_EXTRA_EXT% EQU 1 (
  set TARGETDIR=%BLDSQL%\tsrc
  pushd "%TARGETDIR%"
  xcopy /H /Y /B /E /Q "%BASEDIR%\scripts\build\*" "%BLDSQL%" 1>nul
  call :TEST_MAIN_C_SQLITE3_H
  call :EXT_MAIN
  call :EXT_NORMALIZE
  call :EXT_REGEXP
  call :EXT_SHA1
  call :EXT_BASE_PATCH CSV
  call :EXT_BASE_PATCH SERIES
  call :EXT_BASE_PATCH FILEIO
  call :EXT_BASE_PATCH UINT
  call :EXT_BASE_PATCH UUID
  call :EXT_BASE_PATCH SHATHREE
  if %USE_ZLIB%  EQU 1 (call :EXT_ZIPFILE)
  if %USE_SQLAR% EQU 1 (call :EXT_BASE_PATCH SQLAR)
) 1>>%OUTSQL% 2>>%ERRSQL%

if %USE_LIBSHELL% EQU 1 (
  echo WARNING: Use libshell or shelldll as the target instead of dll!
  call :LIBSHELL
)

popd
echo ===== Making TARGETS ----- %TARGETS% -----
echo ===== Making TARGETS ----- %TARGETS% ----- 1>>%OUTSQL% 2>>%ERRSQL%
cd /d "%BLDSQL%"
nmake /nologo /f Makefile.msc sqlite3.c 1>>%OUTSQL% 2>>%ERRSQL%

:: There is a problem with integration of fileio properly resulting in
:: '_stat' related errors. But bypassing the amalgmation generation tool
:: works.
if %WITH_EXTRA_EXT% EQU 1 (
  call :EXT_WINDIRENT
) 1>>%OUTSQL% 2>>%ERRSQL%

if %USE_LIBSHELL% EQU 1 (
  nmake /nologo /f Makefile.msc %LIBSHELLOBJ%
) 1>>%OUTSQL% 2>>%ERRSQL%

nmake /nologo /f Makefile.msc %TARGETS% 1>>%OUTSQL% 2>>%ERRSQL%
cd ..
rem Leave BUILDDIR

set COPY_BINARIES=0
if exist "%BLDSQL%\sqlite3.dll" (set COPY_BINARIES=1)
if exist "%BLDSQL%\sqlite3.exe" (set COPY_BINARIES=1)
if %COPY_BINARIES% EQU 1 (call :COLLECT_BINARIES) 1>>%OUTSQL% 2>>%ERRSQL%

EndLocal

exit /b 0
:: ================================= END MAIN =================================


:: ============================================================================
:SET_TARGETS
echo ===== Setting targets =====
set TARGETS=####%*
set TARGETS=!TARGETS:"=!
set TARGETS=!TARGETS:####=!
if "/##%TARGETS%##/"=="/####/" (
  echo.
  echo WARNING: no targets have been specified. Expected
  echo a space-separated list of targets as the first quoted
  echo script parameter. Nmake will produce debug output only.
  pause
  set TARGETS=echoconfig
)
@echo off
echo ----- Set     targets -----

exit /b 0


:: ============================================================================
:SETENV
echo ===== Setting options =====
:: TCL/Tk
call "%~dp0TCLTkGet.bat"
if not "/%ErrorLevel%/"=="/0/" exit /b %ErrorLevel%
:: ICU
if not defined USE_ICU (set USE_ICU=1)
call "%~dp0ICUGet.bat"
if not "/%ErrorLevel%/"=="/0/" exit /b %ErrorLevel%

if not defined WITH_EXTRA_EXT set WITH_EXTRA_EXT=1
if %WITH_EXTRA_EXT% EQU 1 (
  if not defined USE_ZLIB set USE_ZLIB=1
  if not defined USE_SQLAR (set USE_SQLAR=1)
) else (
  set USE_ZLIB=0
  set USE_SQLAR=0
)
if not defined USE_LIBSHELL set USE_LIBSHELL=0

::ZLIB_OPTIONS
echo ===== Setting ZLIB options =====
if %USE_ZLIB% EQU 1 (
  set BUILD_ZLIB=0
  call "%~dp0ZLibGet.bat"
  if not "/!ErrorLevel!/"=="/0/" exit /b !ErrorLevel!
  set ZLIBLIB=!ZLIB_LIBIMPORT!
)

call :BUILD_OPTIONS

if /I "/%DBENG%/"=="/sqlcipher/" call :SQLCIPHER_OPTIONS

exit /b 0


:: ============================================================================
:SQLCIPHER_OPTIONS
:: NASM
call "%~dp0NASMGet.bat"
if not "/%ErrorLevel%/"=="/0/" exit /b %ErrorLevel%
:: PERL
call "%~dp0OpenSSLGet.bat"
if not "/%ErrorLevel%/"=="/0/" exit /b %ErrorLevel%

::OPENSSL_OPTIONS
echo ===== Setting OpenSSL options =====
call "%~dp0OpenSSLGet.bat"
if not "/%ErrorLevel%/"=="/0/" exit /b %ErrorLevel%
set CCOPTS=%CCOPTS% -I"%OSSL_INCLUDE%"
set LTLIBPATHS=%LTLIBPATHS% /LIBPATH:"%OSSL_LIBPATH%"
set LTLIBS=%LTLIBS% %OSSL_LIBIMPORT%

echo ===== Setting SQLCIPHER options =====
set DSQLITE_TEMP_STORE=2
set EXT_FEATURE_FLAGS=-DSQLITE_HAS_CODEC %EXT_FEATURE_FLAGS%

exit /b 0


:: ============================================================================
:BUILD_OPTIONS
echo ===== Setting BUILD options =====
set SESSION=1
set RBU=1
set API_ARMOR=1
if not defined SYMBOLS set SYMBOLS=0
if %SYMBOLS% EQU 1 (echo SYMBOLS=1 means the DLL is about 50% larger.)

set EXT_FEATURE_FLAGS=^
-DSQLITE_ENABLE_NORMALIZE ^
-DSQLITE_ENABLE_FTS3_PARENTHESIS ^
-DSQLITE_ENABLE_FTS3_TOKENIZER ^
-DSQLITE_ENABLE_FTS4=1 ^
-DSQLITE_ENABLE_FTS5=1 ^
-DSQLITE_SYSTEM_MALLOC=1 ^
-DSQLITE_OMIT_LOCALTIME=1 ^
-DSQLITE_DQS=0 ^
-DSQLITE_LIKE_DOESNT_MATCH_BLOBS ^
-DSQLITE_MAX_EXPR_DEPTH=100 ^
-DSQLITE_OMIT_DEPRECATED ^
-DSQLITE_DEFAULT_FOREIGN_KEYS=1 ^
-DSQLITE_DEFAULT_SYNCHRONOUS=1 ^
-DSQLITE_ENABLE_EXPLAIN_COMMENTS ^
-DSQLITE_ENABLE_OFFSET_SQL_FUNC=1 ^
-DSQLITE_ENABLE_QPSG ^
-DSQLITE_ENABLE_STMTVTAB ^
-DSQLITE_ENABLE_STAT4 ^
-DSQLITE_ENABLE_SESSION ^
-DSQLITE_ENABLE_PREUPDATE_HOOK ^
-DSQLITE_USE_URI=1 ^
-DSQLITE_SOUNDEX

if %WITH_EXTRA_EXT% EQU 1 (
  echo ========== EXTRA EXTENSIONS ARE ENABLED ==========
  echo ============ TEST FUNCTIONS ARE ENABLED ==========
  if %USE_LIBSHELL% EQU 1 (
    set EXT_FEATURE_FLAGS=^
      -DSQLITE_ENABLE_LIBSHELL ^
      !EXT_FEATURE_FLAGS!
    set LIBSHELL=libshell.c
    set LIBSHELLOBJ=libshell.lo
  ) else (
    if %USE_ZLIB% EQU 1 (
      set EXT_FEATURE_FLAGS=^
        -DSQLITE_ENABLE_ZIPFILE ^
        !EXT_FEATURE_FLAGS!
      if %USE_SQLAR% EQU 1 (
        set EXT_FEATURE_FLAGS=^
          -DSQLITE_ENABLE_SQLAR ^
          !EXT_FEATURE_FLAGS!
      )
    )
    set EXT_FEATURE_FLAGS=^
      -DSQLITE_ENABLE_FILEIO ^
      -DSQLITE_ENABLE_REGEXP ^
      -DSQLITE_ENABLE_SERIES ^
      -DSQLITE_ENABLE_SHATHREE ^
      -DSQLITE_ENABLE_UINT ^
      !EXT_FEATURE_FLAGS!
  )

  set EXT_FEATURE_FLAGS=^
    -DSQLITE_ENABLE_CSV ^
    -DSQLITE_ENABLE_SHA ^
    -DSQLITE_ENABLE_UUID ^
    !EXT_FEATURE_FLAGS!
) else (
  echo ========== EXTRA EXTENSIONS ARE DISABLED =========
  echo ============ TEST FUNCTIONS ARE DISABLED =========
  popd
)

exit /b 0


:: ============================================================================
:MAKEFILE_MSC_TOP_AND_DEBUG_ZLIB_STDCALL
if not defined DSQLITE_TEMP_STORE (set DSQLITE_TEMP_STORE=1)

set FILENAME=%BLDSQL%\Makefile.msc
if %USE_LIBSHELL% EQU 1 (
  set LIBSHELLEXT="/shell:\s*\$.SQLITE3EXE.$/r %FILENAME%.libshell"
) else (set LIBSHELLEXT=";")
sed -e "s/^TOP = .$/TOP = %SRCSQL:\=\\%/" ^
    -e "s/\(DSQLITE_TEMP_STORE=\)1/\1%DSQLITE_TEMP_STORE%/g" ^
    -e "s/\(win32\\Makefile.msc\) clean/\1 LOC=$(ZLIBLOC) clean/" ^
    -e %LIBSHELLEXT% ^
    <"%SRCSQL%\Makefile.msc" ^
    >"%FILENAME%"

set LIBSHELLEXT=

type "%FILENAME%.debug" >>"%FILENAME%"

exit /b 0


:RESET_BAK
:: ============================================================================
set FILENAME=mksqlite3c.tcl
cd /d "%SRCSQL%\tool"
if not exist "%FILENAME%.bak" (
  copy /Y "%FILENAME%" "%FILENAME%.bak" 1>nul
) else (
  copy /Y "%FILENAME%.bak" "%FILENAME%" 1>nul
)

exit /b 0


:CRYPT_OPENSSL
:: ============================================================================
pushd "%OSSL_INCLUDE%\openssl"

set HDRS=^
  "evp.h"^
  "rand.h"^
  "objects.h"^
  "hmac.h"

for %%G in (%HDRS%) do (
  set FILENAME=%%G
  if not exist "!FILENAME!.bak" (
    copy /Y "!FILENAME!" "!FILENAME!.bak"
  ) else (
    copy /Y "!FILENAME!.bak" "!FILENAME!"
  )
)

set FILENAME=objects.h
sed -e "s/\*\(OBJ_nid2sn(int\)/*__cdecl \1/" ^
    -i "%FILENAME%"

set FILENAME=rand.h
sed -e "s/^void RAND_add(/void __cdecl RAND_add(/" ^
    -e "s/^int RAND_bytes(/int __cdecl RAND_bytes(/" ^
    -i "%FILENAME%"

set FILENAME=hmac.h
sed -e "s/HMAC_CTX \*HMAC_CTX_new(/HMAC_CTX *__cdecl HMAC_CTX_new(/" ^
    -e "s/void HMAC_CTX_free(/void __cdecl HMAC_CTX_free(/" ^
    -e "s/int HMAC_/int __cdecl HMAC_/g" ^
    -i "%FILENAME%"

set FILENAME=evp.h
sed -e "s/int PKCS5_PBKDF2_HMAC(/int __cdecl PKCS5_PBKDF2_HMAC(/" ^
    -e "s/int EVP_/int __cdecl EVP_/g" ^
    -e "s/void \(EVP_CIPHER_CTX_free(\)/void __cdecl \1/" ^
    -e "s/^const EVP_MD \*EVP_sha/const EVP_MD *__cdecl EVP_sha/g" ^
    -e "s/\(EVP_CIPHER \*\)\(EVP_aes_256_cbc(\)/\1__cdecl \2/" ^
    -e "s/\(EVP_CIPHER_CTX \*\)\(EVP_CIPHER_CTX_new(\)/\1__cdecl \2/" ^
    -i "%FILENAME%"

popd

exit /b 0


:: ============================================================================
:EXT_ADD_SOURCES_TO_MKSQLITE3C_TCL

set FILENAME=%SRCSQL%\tool\mksqlite3c.tcl
echo ========== Patching "%FILENAME%" ===========
sed -i "%FILENAME%" -e "/^   rtree.c$/r %FILENAME%.ext"

exit /b 0


:: ============================================================================
:EXT_ADD_SOURCES_TO_MAKEFILE_MSC
set FILENAME=%BLDSQL%\Makefile.msc
echo ========== Patching "%FILENAME%" ===========
sed -i "%FILENAME%" -e "/^  \$(TOP)\\ext\\rtree\\rtree.c \\$/r %FILENAME%.ext"

exit /b 0


:: ============================================================================
:TEST_MAIN_C_SQLITE3_H
set FILENAME=%BLDSQL%\tsrc\main.c
echo ========== Patching "%FILENAME%" ===========
sed -i "%FILENAME%" -e "/^int sqlite3_libversion_number/r %FILENAME%.test"
set FILENAME=%BLDSQL%\tsrc\sqlite3.h
echo ========== Patching "%FILENAME%" ===========
sed -i "%FILENAME%" -e "/^typedef sqlite_uint64/r %FILENAME%.test"

exit /b 0


:: ============================================================================
:EXT_MAIN
set FILENAME=%BLDSQL%\tsrc\main.c
echo ========== Patching "%FILENAME%" ===========
sed -i "%FILENAME%" -e "/^int sqlite3Json1Init/r %FILENAME%.1.ext"
sed -i "%FILENAME%" -e "/^  sqlite3RtreeInit,$/r %FILENAME%.2.ext"

exit /b 0


:: ============================================================================
:EXT_NORMALIZE
set FILENAME=%BLDSQL%\tsrc\normalize.c
echo ========== Patching "%FILENAME%" ===========
sed -e "s/^int main/int sqlite3_normalize_main/" ^
    -e "s/\([^G]CC\)_/\1N_/g" ^
    -e "s/TK_/TKN_/g" ^
    -e "s/aiClass/aiClassN/g" ^
    -e "s/IdChar(/IdCharN(/g" ^
    -e "s/sqlite3\([A-Z]\)/sqlite3N\1/g" ^
    -i "%FILENAME%"

exit /b 0


:: ============================================================================
:EXT_SHA1
cd /d "%BLDSQL%\tsrc"
set FILENAME=sha1.c
set OLDTEXT=hash_step_vformat
set NEWTEXT=hash_step_vformat_sha1
tclsh "%BASEDIR%\scripts\replace.tcl" "%OLDTEXT%" "%NEWTEXT%" "%FILENAME%"
call :EXT_BASE_PATCH SHA sha1.c

exit /b 0


:: ============================================================================
:EXT_REGEXP
cd /d "%BLDSQL%\tsrc"
set FILENAME=regexp.c
set OLDTEXT=#include ^<string.h^>
set NEWTEXT=#include ^<sqlite3ext.h^>
tclsh "%BASEDIR%\scripts\replace.tcl" "%OLDTEXT%" "%NEWTEXT%" "%FILENAME%"
set OLDTEXT=#include \"sqlite3ext.h\"
set NEWTEXT=#include ^<string.h^>
tclsh "%BASEDIR%\scripts\replace.tcl" "%OLDTEXT%" "%NEWTEXT%" "%FILENAME%"
call :EXT_BASE_PATCH REGEXP

exit /b 0


:: ============================================================================
:EXT_WINDIRENT
cd /d "%BLDSQL%"
if %USE_LIBSHELL% EQU 0 (
  copy tsrc\test_windirent.c .
  copy tsrc\test_windirent.h .
  copy tsrc\fileio.c .
  set FILENAME=test_windirent.c
  echo ========== Patching "!FILENAME!" ===========
  tclsh "%BASEDIR%\scripts\expandinclude.tcl" "!FILENAME!" "test_windirent.h" .
  (
    echo #include "test_windirent.c"
    echo #include "fileio.c"
  ) >>sqlite3.c
  tclsh "%BASEDIR%\scripts\expandinclude.tcl" "sqlite3.c" "test_windirent.c" .
  tclsh "%BASEDIR%\scripts\expandinclude.tcl" "sqlite3.c" "fileio.c" .
)

exit /b 0


:: ============================================================================
:EXT_ZIPFILE
cd /d "%BLDSQL%\tsrc"
set FLAG=SQLITE_ENABLE_ZIPFILE
set FILENAME=zipfile.c
echo ========== Patching "%FILENAME%" ===========
set OLDTEXT=static int zipfileRegister
set NEWTEXT=int zipfileRegister
tclsh "%BASEDIR%\scripts\replace.tcl" "%OLDTEXT%" "%NEWTEXT%" "%FILENAME%"
set OLDTEXT=#include \"sqlite3ext.h\"
set NEWTEXT=#if defined(%FLAG%)\n\n#include \"sqlite3ext.h\"
tclsh "%BASEDIR%\scripts\replace.tcl" "%OLDTEXT%" "%NEWTEXT%" "%FILENAME%"
echo. >>"%FILENAME%"
echo #endif /* defined^(%FLAG%^) */ >>"%FILENAME%"

exit /b 0


:: ============================================================================
:EXT_BASE_PATCH
:: Call this sub with two arguments:
::   - %1 - FLAG suffix
::   - %2 - FILENAME (if omitted, use %1.c)
set FLAG=SQLITE_ENABLE_%~1
if "/%~2/"=="//" (set FILENAME=%~1.c) else (set FILENAME=%~2)
echo ========== Patching "%FILENAME%" ===========
if exist "%FILENAME%.ext" (
  tclsh "%BASEDIR%\scripts\addlines.tcl" "%FILENAME%" "%FILENAME%.ext" .
)
set OLDTEXT=#include ^<sqlite3ext.h^>
set NEWTEXT=#include \"sqlite3ext.h\"
tclsh "%BASEDIR%\scripts\replace.tcl" "%OLDTEXT%" "%NEWTEXT%" "%FILENAME%"
set OLDTEXT=#include \"sqlite3ext.h\"
set NEWTEXT=#if defined(%FLAG%)\n\n#include \"sqlite3ext.h\"
tclsh "%BASEDIR%\scripts\replace.tcl" "%OLDTEXT%" "%NEWTEXT%" "%FILENAME%"
echo. >>"%FILENAME%"
echo #endif /* defined^(%FLAG%^) */ >>"%FILENAME%"

exit /b 0


:: ============================================================================
:LIBSHELL
set FLAG=SQLITE_ENABLE_LIBSHELL
set FILENAME=libshell.c
echo ========== Patching "%FILENAME%" ===========

pushd "%BLDSQL%"
nmake /nologo /f Makefile.msc shell.c

echo #if ^^!defined^^(LIBSHELL_C^^) ^&^& defined^^(%FLAG%^^) >%FILENAME%
echo #define LIBSHELL_C >>%FILENAME%
type shell.c >>%FILENAME%

set MAPLIST=^
`int SQLITE_CDECL main` `int SQLITE_CDECL libshell_main` ^
`appendText` `shAppendText`

set MAPLIST=%MAPLIST:`="%
tclsh "%BASEDIR%\scripts\replace_multi.tcl" "%FILENAME%" %MAPLIST%

echo. >>%FILENAME%
echo. >>%FILENAME%
type libshell.c.ext >>%FILENAME%
echo. >>%FILENAME%
echo. >>%FILENAME%
echo #endif /* ^^!defined^^(LIBSHELL_C^^) ^&^& defined^^(%FLAG%^^) */ >>%FILENAME%

if /I "/%TARGETS%/"=="/dll/" (set TARGETS=shelldll) else (
if /I "/%TARGETS:~0,4%/"=="/dll /" (set TARGETS=shell%TARGETS%) else (
if /I not "/%TARGETS%/"=="/%TARGETS: dll=%/" (set TARGETS=%TARGETS: dll= shelldll%)))
popd

exit /b 0


:: ============================================================================
:COLLECT_BINARIES
echo ========== Collecting binaries ===========
if not exist "%BINSQL%" mkdir "%BINSQL%" 1>nul
del /Q "%BINSQL%\*" 2>nul
cd /d "%BINSQL%"
if exist "%BLDSQL%\sqlite3.dll" move "%BLDSQL%\sqlite3.dll" .
if exist "%BLDSQL%\sqlite3.exe" move "%BLDSQL%\sqlite3.exe" .
if exist "%BLDSQL%\sqlite3.def" move "%BLDSQL%\sqlite3.def" .
if %USE_ICU%  EQU 1 copy /Y "%ICUBIN%\icu*.dll" .
if %USE_ZLIB% EQU 1 copy /Y "%ZLIBDIR%\zlib1.dll" .
copy /Y "%OPENSSL_PREFIX%\bin\libcrypto*.dll" .
echo ---------- Copied  binaries -----------

exit /b 0
