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

set ERROR_STATUS=0
if not defined DEVDIR (set DEVDIR=C:\dev)
if "/%VSCMD_ARG_TGT_ARCH%/" == "/x64/" (set ARCH=x64)
if "/%VSCMD_ARG_TGT_ARCH%/" == "/x86/" (set ARCH=x32)
if not defined USE_STDCALL (
  if "/%ARCH%/"=="/x32/" (set USE_STDCALL=1) else (set USE_STDCALL=0)
)

set BASEDIR=%~dp0
set BASEDIR=%BASEDIR:~0,-1%
set MAINDISTRO=sqlcipher
set DISTRODIR=%BASEDIR%\%MAINDISTRO%
set STDOUTLOG=%BASEDIR%\stdout.log
set STDERRLOG=%BASEDIR%\stderr.log
del "%STDOUTLOG%" 2>nul
del "%STDERRLOG%" 2>nul

call :SET_TARGETS %*
call :SETENV 1>"%STDOUTLOG%" 2>"%STDERRLOG%"

call :DOWNLOAD_SQLCIPHER
if %ERROR_STATUS% NEQ 0 exit /b 1
call :EXTRACT_SQLCIPHER
if %ERROR_STATUS% NEQ 0 exit /b 1
if not exist "%DISTRODIR%" (
  echo Distro directory does not exists. Exiting
  exit /b 1
)

if %WITH_EXTRA_EXT% EQU 1 (
  if %USE_ZLIB% EQU 1 (
    call :DOWNLOAD_ZLIB
    if %ERROR_STATUS% NEQ 0 exit /b 1
    call :EXTRACT_ZLIB
    if %ERROR_STATUS% NEQ 0 exit /b 1
  )
)

call :DOWNLOAD_OPENSSL
if %ERROR_STATUS% NEQ 0 exit /b 1
call :EXTRACT_OPENSSL
if %ERROR_STATUS% NEQ 0 exit /b 1
call :BUILD_OPENSSL 1>"%STDOUTLOG%" 2>"%STDERRLOG%"

set BUILDDIR=%BASEDIR%\build
if not exist "%BUILDDIR%" mkdir "%BUILDDIR%"
(
  copy /Y "%BASEDIR%\extra\build\*" "%BUILDDIR%"
  copy /Y "%BASEDIR%\extra\*.tcl" "%BASEDIR%"
  xcopy /H /Y /B /E /Q "%BASEDIR%\extra\%MAINDISTRO%" "%BASEDIR%\%MAINDISTRO%"
  cd /d "%BUILDDIR%"
  
  pushd .
  call :MAKEFILE_MSC_TOP_AND_DEBUG_ZLIB_STDCALL
  call :RESET_BAK
)  1>>"%STDOUTLOG%" 2>>"%STDERRLOG%"

if %WITH_EXTRA_EXT% EQU 1 (
  call :EXT_ADD_SOURCES_TO_MAKEFILE_MSC
  call :EXT_ADD_SOURCES_TO_MKSQLITE3C_TCL
) 1>>"%STDOUTLOG%" 2>>"%STDERRLOG%"

(call :CRYPT_MAKEFILE_MSC_MKSQLITE3C_TCL) 1>>"%STDOUTLOG%" 2>>"%STDERRLOG%"
::TSRC
popd
nmake /nologo /f Makefile.msc .target_source 1>>"%STDOUTLOG%" 2>>"%STDERRLOG%"

(call :CRYPT_CRYPTO_OPENSSL) 1>>"%STDOUTLOG%" 2>>"%STDERRLOG%"

if %WITH_EXTRA_EXT% EQU 1 (
  set TARGETDIR=%BUILDDIR%\tsrc
  pushd "%BUILDDIR%\tsrc"
  xcopy /H /Y /B /E /Q "%BASEDIR%\extra\*" "%BASEDIR%"
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
) 1>>"%STDOUTLOG%" 2>>"%STDERRLOG%"

if %USE_LIBSHELL% EQU 1 call :LIBSHELL

popd
if %USE_ZLIB% EQU 1 (
  nmake /nologo /f Makefile.msc zlib
) 1>>"%STDOUTLOG%" 2>>"%STDERRLOG%"
echo ===== Making TARGETS ----- %TARGETS% -----
nmake /nologo /f Makefile.msc sqlite3.c 1>>"%STDOUTLOG%" 2>>"%STDERRLOG%"

:: There is a problem with integration of fileio properly resulting in
:: '_stat' related errors. But bypassing the amalgmation generation tool
:: works.
if %WITH_EXTRA_EXT% EQU 1 (
  call :EXT_WINDIRENT
) 1>>"%STDOUTLOG%" 2>>"%STDERRLOG%"

if %USE_LIBSHELL% EQU 1 (
  nmake /nologo /f Makefile.msc %LIBSHELLOBJ%
) 1>>"%STDOUTLOG%" 2>>"%STDERRLOG%"
nmake /nologo /f Makefile.msc %TARGETS% 1>>"%STDOUTLOG%" 2>>"%STDERRLOG%"
cd ..
rem Leave BUILDDIR

set COPY_BINARIES=0
if exist "%BUILDDIR%\sqlite3.dll" (set COPY_BINARIES=1)
if exist "%BUILDDIR%\sqlite3.exe" (set COPY_BINARIES=1)
if %COPY_BINARIES% EQU 1 (call :COLLECT_BINARIES) 1>>"%STDOUTLOG%" 2>>"%STDERRLOG%"

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
call :ICU_OPTIONS
call :TCL_OPTIONS
call :ZLIB_OPTIONS
call :NASM_OPTIONS
call :PERL_OPTIONS
call :OPENSSL_OPTIONS
call :BUILD_OPTIONS
call :SQLCIPHER_OPTIONS

exit /b 0


:: ============================================================================
:ICU_OPTIONS
:: In VBA6, it might be necessary to load individual libraries explicitly in the
:: correct order (dependencies must be loaded before the depending libraries.
if not defined USE_ICU (set USE_ICU=1)
if not %USE_ICU% EQU 1 (exit /b 0)
if "/%VSCMD_ARG_TGT_ARCH%/" == "/x64/" (set ARCHX=x64)
if "/%VSCMD_ARG_TGT_ARCH%/" == "/x86/" (set ARCHX=x32)
if not defined ICU_HOME (set ICU_HOME=%DEVDIR%\icu4c)
call :CHECKTOOL uconv "%ICU_HOME%\bin%ARCHX%"

if "/%TOOLPATH%/"=="//" (
  echo ICU binaries not found, disabling the ICU extension.
  set USE_ICU=0
  exit /b 0
)
echo Found ICU binaries.

set ICU_HOME=!TOOLPATH:\bin%ARCHX%\uconv.exe=!
set ICUBIN=%ICU_HOME%\bin%ARCHX%
set ICUINC=%ICU_HOME%\include
set ICULIB=%ICU_HOME%\lib%ARCHX%

if "/%LIB%/"=="/!LIB:%ICULIB%=!/" (set "LIB=%ICULIB%;%LIB%")
if "/%Path%/"=="/!Path:%ICUBIN%=!/" (set "Path=%ICUBIN%;%Path%")
if "/%INCLUDE%/"=="/!INCLUDE:%ICUINC%=!/" (set "INCLUDE=%ICUINC%;%INCLUDE%")

set ICUBIN=
set ICUINC=
set ICULIB=

exit /b 0


:: ============================================================================
:ZLIB_OPTIONS
if not "/%WITH_EXTRA_EXT%/"=="/1/" (
  set USE_ZLIB=0
  set USE_SQLAR=0
  exit /b 0
)
if not defined USE_ZLIB set USE_ZLIB=1
if not defined USE_SQLAR (set USE_SQLAR=1)
if not %USE_ZLIB% EQU 1 (exit /b 0)
:: Could not get static linking to work
set ZLIBLIB=zdll.lib
set ZLIBDIR=%DISTRODIR%\compat\zlib
if %USE_STDCALL% EQU 1 (set ZLIBLOC="-DZLIB_WINAPI -DZLIB_DLL")

exit /b 0


:: ============================================================================
:TCL_OPTIONS
if not defined TCL_HOME (set TCL_HOME=%DEVDIR%\TCL)
call :CHECKTOOL tclsh "%TCL_HOME%\bin"

if "/%TOOLPATH%/"=="//" (
  echo TCL not found.
  exit /b 1
)

echo TCL found.
set TCLBIN=%TOOLPATH:\tclsh.exe=%
if "/%Path%/"=="/!Path:%TCLBIN%=!/" (set "Path=%TCLBIN%;%Path%")
set TCLBIN=

exit /b 0


:: ============================================================================
:NASM_OPTIONS
:: https://nasm.us
if not defined NASM_HOME (set NASM_HOME=%DEVDIR%\NASM)
call :CHECKTOOL nasm "%NASM_HOME%\%ARCH%"

if "/%TOOLPATH%/"=="//" (
  echo NASM not found.
  exit /b 1
)

echo NASM found.
set NASMBIN=!TOOLPATH:\nasm.exe=!
if "/%Path%/"=="/!Path:%NASMBIN%=!/" (set "Path=%NASMBIN%;%Path%")
set NASMBIN=

exit /b 0


:: ============================================================================
:PERL_OPTIONS
:: E.g., https://strawberryperl.com
if not defined PERL_HOME (set PERL_HOME=%DEVDIR%\PERL)
call :CHECKTOOL perl "%PERL_HOME%\bin

if "/%TOOLPATH%/"=="//" (
  echo PERL not found.
  exit /b 1
)

echo PERL found.
set PERLBIN=!TOOLPATH:\perl.exe=!
if "/%Path%/"=="/!Path:%PERLBIN%=!/" (set "Path=%PERLBIN%;%Path%")
set PERLBIN=

exit /b 0


:: ============================================================================
:OPENSSL_OPTIONS
set OPENSSL_DISTRO=%BASEDIR%\openssl
set OPENSSL_BUILD=%BASEDIR%\tools\build\openssl\%ARCH%
set OPENSSL_PREFIX=%BASEDIR%\tools\OpenSSL\%ARCH%
set OPENSSL_DIR=%BASEDIR%\tools\SSL\%ARCH%
if "/%ARCH%/"=="/x32/" (set OPENSSLARCH=VC-WIN32)
if "/%ARCH%/"=="/x64/" (set OPENSSLARCH=VC-WIN64A)

exit /b 0


:: ============================================================================
:BUILD_OPTIONS
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

if not defined USE_LIBSHELL set USE_LIBSHELL=0
if not defined WITH_EXTRA_EXT set WITH_EXTRA_EXT=1
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
  set TARGETDIR=%DISTRODIR%\tool
  set FILENAME=mksqlite3c.tcl
  pushd "!TARGETDIR!"
  if exist "!FILENAME!.bak" (
    echo Resetting !FILENAME!
    copy /Y "!FILENAME!.bak" "!FILENAME!"
  )
  popd
)

exit /b 0


:: ============================================================================
:SQLCIPHER_OPTIONS
set EXT_FEATURE_FLAGS=^
-DSQLITE_HAS_CODEC ^
-DSQLITE_TEMP_STORE=2 ^
`-I%OPENSSL_PREFIX%\include` ^
%EXT_FEATURE_FLAGS%

set EXT_FEATURE_FLAGS=%EXT_FEATURE_FLAGS:`="%

set LTLIBS=libcrypto.lib %LTLIBS%
set LTLIBPATHS="/LIBPATH:%OPENSSL_PREFIX%\lib" %LTLIBPATHS%

exit /b 0


:: ============================================================================
:DOWNLOAD_SQLCIPHER
set DISTRO=sqlcipher.zip
set PKGNAME=SQLCipher
set REPO=sqlcipher/sqlcipher
set URL=https://github.com/%REPO%/archive/refs/heads/master.zip

if not exist "%DISTRO%" (
  echo ===== Downloading current %PKGNAME% release =====
  curl -L %URL% --output "%DISTRO%"
  if %ErrorLevel% EQU 0 (
    echo ----- Downloaded  current %PKGNAME% release -----
  ) else (
    set ERROR_STATUS=%ErrorLevel%
    echo Error downloading %PKGNAME% distro.
    echo Errod code: !ERROR_STATUS!
  )
) else (
  echo ===== Using previously downloaded %PKGNAME% distro =====
)

exit /b %ERROR_STATUS%


:: ============================================================================
:EXTRACT_SQLCIPHER
set DISTROFILE=sqlcipher.zip
set SRCDIR=%DISTROFILE:.zip=%
set PKGNAME=SQLCipher
set PROBEFILE=Makefile.msc

if not exist "%SRCDIR%\%PROBEFILE%" (
  echo ===== Extracting %PKGNAME% distro =====
  tar -xf "%DISTROFILE%"
  if %ErrorLevel% EQU 0 (
    echo ----- Extracted  %PKGNAME% distro -----
  ) else (
    set ERROR_STATUS=%ErrorLevel%
    echo Error extracting %PKGNAME% distro.
    echo Errod code: !ERROR_STATUS!
  )
  rmdir /S /Q "%SRCDIR%" 2>nul
  move "%SRCDIR%-master" "%SRCDIR%"
) else (
  echo ===== Using previously extracted %PKGNAME% distro =====
)

if not exist "%SRCDIR%" (
  echo Distro directory does not exists. Exiting
  exit /b 1
)

exit /b %ERROR_STATUS%


:: ============================================================================
:DOWNLOAD_OPENSSL
set DISTRO=openssl.zip
set PKGNAME=OpenSSL
set REPO=openssl/openssl
set URL=https://github.com/%REPO%/archive/refs/heads/master.zip

if not exist "%DISTRO%" (
  echo ===== Downloading current %PKGNAME% release =====
  curl -L %URL% --output "%DISTRO%"
  if %ErrorLevel% EQU 0 (
    echo ----- Downloaded  current %PKGNAME% release -----
  ) else (
    set ERROR_STATUS=%ErrorLevel%
    echo Error downloading %PKGNAME% distro.
    echo Errod code: !ERROR_STATUS!
  )
) else (
  echo ===== Using previously downloaded %PKGNAME% distro =====
)

exit /b %ERROR_STATUS%


:: ============================================================================
:EXTRACT_OPENSSL
set DISTROFILE=openssl.zip
set SRCDIR=%DISTROFILE:.zip=%
set PKGNAME=OpenSSL
set PROBEFILE=Configure

if not exist "%SRCDIR%\%PROBEFILE%" (
  echo ===== Extracting %PKGNAME% distro =====
  tar -xf "%DISTROFILE%"
  if %ErrorLevel% EQU 0 (
    echo ----- Extracted  %PKGNAME% distro -----
  ) else (
    set ERROR_STATUS=%ErrorLevel%
    echo Error extracting %PKGNAME% distro.
    echo Errod code: !ERROR_STATUS!
  )
  rmdir /S /Q "%SRCDIR%" 2>nul
  move "%SRCDIR%-master" "%SRCDIR%"
) else (
  echo ===== Using previously extracted %PKGNAME% distro =====
)

if not exist "%SRCDIR%" (
  echo Distro directory does not exists. Exiting
  exit /b 1
)

exit /b %ERROR_STATUS%


:: ============================================================================
:DOWNLOAD_ZLIB
set DISTRO=zlib.zip
set URL=https://zlib.net/zlib1211.zip

if not exist "%DISTRO%" (
  echo ===== Downloading zlib =====
  curl %URL% --output "%DISTRO%"
  if %ErrorLevel% EQU 0 (
    echo ----- Downloaded  ZLIB -----
  ) else (
    set ERROR_STATUS=%ErrorLevel%
    echo Error downloading zlib distro.
    echo Errod code: !ERROR_STATUS!
  )
) else (
  echo ===== Using previously downloaded zlib =====
)

exit /b %ERROR_STATUS%


:: ============================================================================
:EXTRACT_ZLIB
set DISTROFILE=zlib.zip
set ZLIBDIR=%DISTRODIR%\compat\zlib

if not exist "%ZLIBDIR%\win32\Makefile.msc" (
  echo ===== Extracting zlib distro =====
  rmdir /S /Q "%ZLIBDIR%" 1>>"%STDOUTLOG%" 2>>"%STDERRLOG%"
  tar -xf "%DISTROFILE%"
  if %ErrorLevel% EQU 0 (
    echo ----- Extracted  zlib distro -----
    mkdir "%DISTRODIR%\compat" 2>nul
    move /Y zlib-* zlib 1>>"%STDOUTLOG%" 2>>"%STDERRLOG%"
    move /Y zlib "%DISTRODIR%\compat" 1>>"%STDOUTLOG%" 2>>"%STDERRLOG%"
  ) else (
    set ERROR_STATUS=%ErrorLevel%
    echo Error extracting zlib distro.
    echo Errod code: !ERROR_STATUS!
  )
) else (echo ===== Using previously  extracted zlib =====)

exit /b %ERROR_STATUS%


:: ============================================================================
:BUILD_OPENSSL
set ERROR_STATUS=0
mkdir "%OPENSSL_BUILD%" 2>nul
pushd "%OPENSSL_BUILD%"

if not exist "makefile" (
  echo ===== Configuring OpenSSL =====
  perl "%OPENSSL_DISTRO%\Configure" %OPENSSLARCH% ^
    --prefix="%OPENSSL_PREFIX%" --openssldir="%OPENSSL_DIR%" 
  if %ErrorLevel% EQU 0 (
    echo ----- Configured OpenSSL -----
  ) else (
    set ERROR_STATUS=%ErrorLevel%
    echo Error configuring OpenSSL
    echo Errod code: !ERROR_STATUS!
  )
) else (
  echo ===== Using previously configured OpenSSL setup =====
)
if not exist "%OPENSSL_PREFIX%\lib\libcrypto.lib" (
  echo ===== Making OpenSSL =====
  nmake
  nmake install
  echo ----- Made OpenSSL -----
) else (
  echo ===== Using previously made OpenSSL =====
)
popd

exit /b %ERROR_STATUS%


:: ============================================================================
:MAKEFILE_MSC_TOP_AND_DEBUG_ZLIB_STDCALL
set FILENAME=Makefile.msc
if exist "%FILENAME%" (
  nmake /nologo /f "%FILENAME%" clean
  del "%FILENAME%" 2>nul
)
copy /Y "%DISTRODIR%\%FILENAME%" .

set MAPLIST=^
`TOP = .` `TOP = %DISTRODIR%` ^
`win32\Makefile.msc clean` `win32\Makefile.msc LOC=$(ZLIBLOC) clean`

set MAPLIST=%MAPLIST:`="%
tclsh "%BASEDIR%\replace_multi.tcl" "%FILENAME%" %MAPLIST%

if %USE_LIBSHELL% EQU 1 call (
  tclsh "%BASEDIR%\addlines.tcl" "%FILENAME%" "%FILENAME%.libshell" %BUILDDIR%
)

type "%FILENAME%.debug" >>"%FILENAME%"

exit /b 0


:RESET_BAK
:: ============================================================================
set TARGETDIR=%DISTRODIR%\tool
set FILENAME=mksqlite3c.tcl
pushd "%TARGETDIR%"
if not exist "%FILENAME%.bak" (
  copy /Y "%FILENAME%" "%FILENAME%.bak"
) else (
  copy /Y "%FILENAME%.bak" "%FILENAME%"
)
popd

exit /b 0


:CRYPT_MAKEFILE_MSC_MKSQLITE3C_TCL
:: ============================================================================
set FILENAME=Makefile.msc
echo ========== Patching "%FILENAME%" ===========
tclsh "%BASEDIR%\addlines.tcl" "%FILENAME%" "%FILENAME%.crypt" "%BUILDDIR%"

set OLDTEXT=LIBOBJS1 = sqlite3.lo
set NEWTEXT=LIBOBJS1 = sqlite3.lo crypto_openssl_p.lo
tclsh "%BASEDIR%\replace.tcl" "%OLDTEXT%" "%NEWTEXT%" "%FILENAME%"
ren "%FILENAME%" "%FILENAME%" 

set TARGETDIR=%DISTRODIR%\tool
set FILENAME=mksqlite3c.tcl
echo ========== Patching "%FILENAME%" ===========

tclsh "%BASEDIR%\addlines.tcl" "%FILENAME%" "%FILENAME%.crypt" "%TARGETDIR%"

exit /b 0


:CRYPT_CRYPTO_OPENSSL
:: ============================================================================
copy /Y "%BASEDIR%\extra\build\tsrc\crypto_openssl_p.*" "%BUILDDIR%\tsrc"
tclsh "%BUILDDIR%\tsrc\crypto_openssl_p.tcl"

exit /b 0


:: ============================================================================
:EXT_ADD_SOURCES_TO_MKSQLITE3C_TCL
set TARGETDIR=%DISTRODIR%\tool
set FILENAME=mksqlite3c.tcl
echo ========== Patching "%FILENAME%" ===========
tclsh "%BASEDIR%\addlines.tcl" "%FILENAME%" "%FILENAME%.ext" "%TARGETDIR%"

exit /b 0


:: ============================================================================
:EXT_ADD_SOURCES_TO_MAKEFILE_MSC
set TARGETDIR=%BUILDDIR%
set FILENAME=Makefile.msc
echo ========== Patching "%FILENAME%" ===========
tclsh "%BASEDIR%\addlines.tcl" "%FILENAME%" "%FILENAME%.ext" "%TARGETDIR%"
ren "%FILENAME%" "%FILENAME%" 

exit /b 0


:: ============================================================================
:EXT_ADD_SOURCES_TO_MKSQLITE3C_TCL
set TARGETDIR=%DISTRODIR%\tool
set FILENAME=mksqlite3c.tcl
echo ========== Patching "%FILENAME%" ===========
pushd "%TARGETDIR%"
if not exist "%FILENAME%.bak" (
  copy /Y "%FILENAME%" "%FILENAME%.bak"
) else (
  copy /Y "%FILENAME%.bak" "%FILENAME%"
)
popd
tclsh "%BASEDIR%\addlines.tcl" "%FILENAME%" "%FILENAME%.ext" "%TARGETDIR%"

exit /b 0


:: ============================================================================
:TEST_MAIN_C_SQLITE3_H
set FILENAME=main.c
echo ========== Patching "%FILENAME%" ===========
tclsh "%BASEDIR%\addlines.tcl" "%FILENAME%" "%FILENAME%.test" "%TARGETDIR%"
set FILENAME=sqlite3.h
echo ========== Patching "%FILENAME%" ===========
tclsh "%BASEDIR%\addlines.tcl" "%FILENAME%" "%FILENAME%.test" "%TARGETDIR%"

exit /b 0


:: ============================================================================
:EXT_MAIN
set FILENAME=main.c
echo ========== Patching "%FILENAME%" ===========
tclsh "%BASEDIR%\addlines.tcl" "%FILENAME%" "%FILENAME%.1.ext" "%TARGETDIR%"
tclsh "%BASEDIR%\addlines.tcl" "%FILENAME%" "%FILENAME%.2.ext" "%TARGETDIR%"

exit /b 0


:: ============================================================================
:EXT_NORMALIZE
set FILENAME=normalize.c
echo ========== Patching "%FILENAME%" ===========

set MAPLIST=^
`int main` `int sqlite3_normalize_main` ^
`CC_` `CCN_` ^
`TK_` `TKN_` ^
`aiClass` `aiClassN` ^
`sqlite3UpperToLower` `sqlite3UpperToLowerN` ^
`sqlite3CtypeMap` `sqlite3CtypeMapN` ^
`sqlite3GetToken` `sqlite3GetTokenN` ^
`IdChar(` `IdCharN(` ^
`sqlite3I` `sqlite3NI` ^
`sqlite3T` `sqlite3NT` ^
`CCN__` `CC__`

set MAPLIST=%MAPLIST:`="%
tclsh "%BASEDIR%\replace_multi.tcl" "%FILENAME%" %MAPLIST%

exit /b 0


:: ============================================================================
:EXT_SHA1
set FILENAME=sha1.c
set OLDTEXT=hash_step_vformat
set NEWTEXT=hash_step_vformat_sha1
tclsh "%BASEDIR%\replace.tcl" "%OLDTEXT%" "%NEWTEXT%" "%FILENAME%"
call :EXT_BASE_PATCH SHA sha1.c

exit /b 0


:: ============================================================================
:EXT_REGEXP
set FILENAME=regexp.c
set OLDTEXT=#include ^<string.h^>
set NEWTEXT=#include ^<sqlite3ext.h^>
tclsh "%BASEDIR%\replace.tcl" "%OLDTEXT%" "%NEWTEXT%" "%FILENAME%"
set OLDTEXT=#include \"sqlite3ext.h\"
set NEWTEXT=#include ^<string.h^>
tclsh "%BASEDIR%\replace.tcl" "%OLDTEXT%" "%NEWTEXT%" "%FILENAME%"
call :EXT_BASE_PATCH REGEXP

exit /b 0


:: ============================================================================
:EXT_WINDIRENT
if %USE_LIBSHELL% EQU 0 (
  copy tsrc\test_windirent.c .
  copy tsrc\test_windirent.h .
  copy tsrc\fileio.c .
  set FILENAME=test_windirent.c
  echo ========== Patching "!FILENAME!" ===========
  tclsh "%BASEDIR%\expandinclude.tcl" "!FILENAME!" "test_windirent.h" .
  (
    echo #include "test_windirent.c"
    echo #include "fileio.c"
  ) >>sqlite3.c
  tclsh "%BASEDIR%\expandinclude.tcl" "sqlite3.c" "test_windirent.c" .
  tclsh "%BASEDIR%\expandinclude.tcl" "sqlite3.c" "fileio.c" .
)

exit /b 0


:: ============================================================================
:EXT_ZIPFILE
set FLAG=SQLITE_ENABLE_ZIPFILE
set FILENAME=zipfile.c
echo ========== Patching "%FILENAME%" ===========
set OLDTEXT=static int zipfileRegister
set NEWTEXT=int zipfileRegister
tclsh "%BASEDIR%\replace.tcl" "%OLDTEXT%" "%NEWTEXT%" "%FILENAME%"
set OLDTEXT=#include \"sqlite3ext.h\"
set NEWTEXT=#if defined(%FLAG%)\n\n#include \"sqlite3ext.h\"
tclsh "%BASEDIR%\replace.tcl" "%OLDTEXT%" "%NEWTEXT%" "%FILENAME%"
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
  tclsh "%BASEDIR%\addlines.tcl" "%FILENAME%" "%FILENAME%.ext" .
)
set OLDTEXT=#include ^<sqlite3ext.h^>
set NEWTEXT=#include \"sqlite3ext.h\"
tclsh "%BASEDIR%\replace.tcl" "%OLDTEXT%" "%NEWTEXT%" "%FILENAME%"
set OLDTEXT=#include \"sqlite3ext.h\"
set NEWTEXT=#if defined(%FLAG%)\n\n#include \"sqlite3ext.h\"
tclsh "%BASEDIR%\replace.tcl" "%OLDTEXT%" "%NEWTEXT%" "%FILENAME%"
echo. >>"%FILENAME%"
echo #endif /* defined^(%FLAG%^) */ >>"%FILENAME%"

exit /b 0


:: ============================================================================
:LIBSHELL
set FLAG=SQLITE_ENABLE_LIBSHELL
set FILENAME=libshell.c
echo ========== Patching "%FILENAME%" ===========

pushd "%BUILDDIR%"
nmake /nologo /f Makefile.msc shell.c

echo #if ^^!defined^^(LIBSHELL_C^^) ^&^& defined^^(%FLAG%^^) >%FILENAME%
echo #define LIBSHELL_C >>%FILENAME%
type shell.c >>%FILENAME%

set MAPLIST=^
`int SQLITE_CDECL main` `int SQLITE_CDECL libshell_main` ^
`appendText` `shAppendText`

set MAPLIST=%MAPLIST:`="%
tclsh "%BASEDIR%\replace_multi.tcl" "%FILENAME%" %MAPLIST%

echo. >>%FILENAME%
echo. >>%FILENAME%
type libshell.c.ext >>%FILENAME%
echo. >>%FILENAME%
echo. >>%FILENAME%
echo #endif /* ^^!defined^^(LIBSHELL_C^^) ^&^& defined^^(%FLAG%^^) */ >>%FILENAME%

popd

exit /b 0


:: ============================================================================
:COLLECT_BINARIES
echo ========== Collecting binaries ===========
set BINDIR=%~dp0bin
if not exist "%BINDIR%" mkdir "%BINDIR%"
del /Q bin\* 2>nul
if exist "%BUILDDIR%\sqlite3.dll" move "%BUILDDIR%\sqlite3.dll" "%BINDIR%"
if exist "%BUILDDIR%\sqlite3.exe" move "%BUILDDIR%\sqlite3.exe" "%BINDIR%"
if exist "%BUILDDIR%\sqlite3.def" move "%BUILDDIR%\sqlite3.def" "%BINDIR%"
if %USE_ICU%  EQU 1 copy /Y "%ICUBINDIR%\icu*.dll" "%BINDIR%"
if %USE_ZLIB% EQU 1 copy /Y "%ZLIBDIR%\zlib1.dll"  "%BINDIR%"
echo ---------- Copied  binaries -----------

exit /b 0


:: ============================================================================
:CHECKTOOL
:: Checks if the tool %1 is in the Path.
::
:: Call this sub with argument(s):
::   - %1 - Tool executable name
::   - %2 - CD before check
::
set CommandText=where "%~1" 2^^^>nul
set Output=
for /f "Usebackq delims=" %%i in (`%CommandText%`) do (
  if "/!Output!/"=="//" (
    set Output=%%i
  )
)
if not "/%Output%/"=="//" (
  set ErrorStatus=0
  echo %~1=%Output%
  set TOOLPATH=%Output%
  exit /b %ErrorStatus%
) else if not exist "%~2" (
  set ErrorStatus=1
  set TOOLPATH=
  echo "%~1" not found.
  exit /b %ErrorStatus%
)

pushd "%~2"
for /f "Usebackq delims=" %%i in (`%CommandText%`) do (
  if "/!Output!/"=="//" (
    set Output=%%i
  )
)
popd

if not "/%Output%/"=="//" (
  set ErrorStatus=0
  echo %~1=%Output%
  set TOOLPATH=%Output%
) else (
  set ErrorStatus=1
  set TOOLPATH=
  echo "%~1" not found.
)

exit /b %ErrorStatus%
