@echo off
:: ============================================================================
:: Builds SQLite using Microsoft Visual C++ Build Tools (MSVC toolset).
:: MSVC toolset can be installed via a
::   - dedicated installer:
::       https://go.microsoft.com/fwlink/?LinkId=691126
::   - Visual Studio installer (including CE):
::       https://visualstudio.microsoft.com/downloads
:: TCL must also be available, as it is required by the building workflow.
:: ============================================================================


:: ============================= BEGIN DISPATCHER =============================
call :MAIN %*
exit /b 0
:: ============================= END   DISPATCHER =============================


:: ================================ BEGIN MAIN ================================
:MAIN
SetLocal

set ERROR_STATUS=0

set BASEDIR=%~dp0
set BASEDIR=%BASEDIR:~0,-1%
set STDOUTLOG=%BASEDIR%\stdout.log
set STDERRLOG=%BASEDIR%\stderr.log
del "%STDOUTLOG%" 2>nul
del "%STDERRLOG%" 2>nul

(
  call :SET_TARGETS %*
  call :ICU_OPTIONS
  call :TCL_OPTIONS
  call :ZLIB_OPTIONS
  call :BUILD_OPTIONS
) 1>"%STDOUTLOG%" 2>"%STDERRLOG%"

call :CHECK_PREREQUISITES
if %ERROR_STATUS% NEQ 0 exit /b 1

set DISTRODIR=%BASEDIR%\sqlite
call :DOWNLOAD_SQLITE
if %ERROR_STATUS% NEQ 0 exit /b 1
call :EXTRACT_SQLITE
if %ERROR_STATUS% NEQ 0 exit /b 1
if not exist "%DISTRODIR%" (
  echo Distro directory does not exists. Exiting
  exit /b 1
)

if %USE_ZLIB% EQU 1 (
  call :DOWNLOAD_ZLIB
  if %ERROR_STATUS% NEQ 0 exit /b 1
  call :EXTRACT_ZLIB
  if %ERROR_STATUS% NEQ 0 exit /b 1
)

set BUILDDIR=%BASEDIR%\build
if not exist "%BUILDDIR%" mkdir "%BUILDDIR%"
(
  copy /Y "%BASEDIR%\extra\build\*" "%BUILDDIR%"
  copy /Y "%BASEDIR%\extra\*.tcl" "%BASEDIR%"
  xcopy /H /Y /B /E /Q "%BASEDIR%\extra\sqlite" "%BASEDIR%\sqlite"
  cd /d "%BUILDDIR%
  
  pushd .
  call :MAKEFILE_MSC_TOP_AND_DEBUG
  call :MAKEFILE_MSC_ZLIB_STDCALL
)  1>>"%STDOUTLOG%" 2>>"%STDERRLOG%"

if %WITH_EXTRA_EXT% EQU 1 (
  call :EXT_ADD_SOURCES_TO_MAKEFILE_MSC
  call :EXT_ADD_SOURCES_TO_MKSQLITE3C_TCL
  popd

  ::TSRC
  nmake /nologo /f Makefile.msc .target_source

  pushd .
  xcopy /H /Y /B /E /Q "%BASEDIR%\extra\*" "%BASEDIR%"
  call :TEST_PATCH_MAIN_C_SQLITE3_H
  call :EXT_PATCH_MAIN_C
  call :EXT_PATCH_CSV_C
  if %USE_ZLIB% EQU 1 (call :EXT_PATCH_ZIPFILE_C)
) 1>>"%STDOUTLOG%" 2>>"%STDERRLOG%"

popd
nmake /nologo /f Makefile.msc zlib 1>>"%STDOUTLOG%" 2>>"%STDERRLOG%"
nmake /nologo /f Makefile.msc %TARGETS% 1>>"%STDOUTLOG%" 2>>"%STDERRLOG%"
cd ..
rem Leave BUILDDIR

if exist "%BUILDDIR%\sqlite3.dll" (call :COPY_BINARIES) 1>>"%STDOUTLOG%" 2>>"%STDERRLOG%"

EndLocal
exit /b 0
:: ================================= END MAIN =================================


:: ============================================================================
:SET_TARGETS
echo ===== Setting targets =====
set TARGETS=####%*
set TARGETS=%TARGETS:"=%
set TARGETS=%TARGETS:####=%
echo on
@if "/##%TARGETS%##/"=="/####/" (
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
:ICU_OPTIONS
:: In VBA6, it might be necessary to load individual libraries explicitly in the
:: correct order (dependencies must be loaded before the depending libraries.
set USE_ICU=1
if %USE_ICU% EQU 1 (
  if /%Platform%/==/x86/ (
    set ARCH=
  ) else (
    set ARCH=64
  )
  set ICUDIR=%ProgramFiles%\icu4c
  set ICUDIR=!ICUDIR: =!
  set ICUINCDIR=!ICUDIR!\include
  set ICULIBDIR=!ICUDIR!\lib!ARCH!
  set ICUBINDIR=!ICUDIR!\bin!ARCH!
)

set INCLUDE=%ICUINCDIR%;%INCLUDE%
set Path=%ICUBINDIR%;%Path%
set LIB=%ICULIBDIR%;%LIB%

exit /b 0


:: ============================================================================
:ZLIB_OPTIONS
set USE_ZLIB=1
:: Could not get static linking to work
set ZLIBLIB=zdll.lib
set ZLIBDIR=%DISTRODIR%\compat\zlib

exit /b 0


:: ============================================================================
:TCL_OPTIONS
set NO_TCL=1
set Path=%ProgramFiles%\TCL\bin;%Path%

exit /b 0


:: ============================================================================
:BUILD_OPTIONS
if "/%VSCMD_ARG_TGT_ARCH%/"=="/x86/" (
  set USE_STDCALL=1
) else (
  set USE_STDCALL=0
)
set SESSION=1
set RBU=1
set API_ARMOR=1
set SYMBOLS=0

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

if "%WITH_EXTRA_EXT%"=="" set WITH_EXTRA_EXT=1
if %WITH_EXTRA_EXT% EQU 1 (
  echo ========== EXTRA EXTENSIONS ARE ENABLED ==========
  echo ============ TEST FUNCTIONS ARE ENABLED ==========
  if %USE_ZLIB% EQU 1 (
    set EXT_FEATURE_FLAGS=^
      -DSQLITE_ENABLE_ZIPFILE ^
      !EXT_FEATURE_FLAGS!
  )
  set EXT_FEATURE_FLAGS=^
    -DSQLITE_ENABLE_CSV ^
    !EXT_FEATURE_FLAGS!
) else (
  echo ========== EXTRA EXTENSIONS ARE DISABLED =========
  echo ============ TEST FUNCTIONS ARE DISABLED =========
  set TARGETDIR=%DISTRODIR%\tool
  set FILENAME=mksqlite3c.tcl
  pushd "%TARGETDIR%"
  if exist "%FILENAME%.bak" (
    echo Resetting %FILENAME%
    copy /Y "%FILENAME%.bak" "%FILENAME%"
  )
  popd
)

exit /b 0


:: ============================================================================
:CHECK_PREREQUISITES
echo ===== Verifying environment =====
if "/%VisualStudioVersion%/"=="//" (
  echo %%VisualStudioVersion%% is not set. Run this script from an MSVC shell.
  set ERROR_STATUS=1
) else (
  echo VisualStudioVersion=%VisualStudioVersion%
)
if "/%VSINSTALLDIR%/"=="//" (
  echo %%VSINSTALLDIR%% is not set. Run this script from an MSVC shell.
  set ERROR_STATUS=1
) else (
  echo VSINSTALLDIR=%VSINSTALLDIR%
)
if "/%VCINSTALLDIR%/"=="//" (
  echo %%VSINSTALLDIR%% is not set. Run this script from an MSVC shell.
  set ERROR_STATUS=1
) else (
  echo VCINSTALLDIR=%VCINSTALLDIR%
)

set CommandLocation=
for /f "Usebackq delims=" %%i in (`where cl.exe 2^>nul`) do (
  if "/!CommandLocation!/"=="//" (
    set CommandLocation=%%i
  )
)
if "/%CommandLocation%/"=="//" (
  echo cl.exe is not found. Run this script from an MSVC shell.
  set ERROR_STATUS=1
) else (
  echo CL_EXE=%CommandLocation%
)

set CommandLocation=
for /f "Usebackq delims=" %%i in (`where nmake.exe 2^>nul`) do (
  if "/!CommandLocation!/"=="//" (
    set CommandLocation=%%i
  )
)
if "/%CommandLocation%/"=="//" (
  echo nmake.exe is not found. Run this script from an MSVC shell.
  set ERROR_STATUS=1
) else (
  echo NMAKE_EXE=%CommandLocation%
)

set CommandLocation=
for /f "Usebackq delims=" %%i in (`where tclsh.exe 2^>nul`) do (
  if "/!CommandLocation!/"=="//" (
    set CommandLocation=%%i
  )
)
if "/%CommandLocation%/"=="//" (
  echo tclsh.exe is not found. TCL is required and must be in the path.
  set ERROR_STATUS=1
) else (
  echo TCLSH_EXE=%CommandLocation%
)

if %ERROR_STATUS% EQU 0 (
  echo ----- Verified  environment -----
) else (
  echo ----- Environment is NOT OK -----
)

exit /b %ERROR_STATUS%


:: ============================================================================
:DOWNLOAD_SQLITE
set DISTRO=sqlite.zip
set URL=https://www.sqlite.org/src/zip/sqlite.zip

if not exist %DISTRO% (
  echo ===== Downloading current SQLite release =====
  curl %URL% --output "%DISTRO%"
  if %ErrorLevel% EQU 0 (
    echo ----- Downloaded  current SQLite release -----
  ) else (
    set ERROR_STATUS=%ErrorLevel%
    echo Error downloading SQLite distro.
    echo Errod code: !ERROR_STATUS!
  )
) else (
  echo ===== Using previously downloaded SQLite distro =====
)

exit /b %ERROR_STATUS%


:: ============================================================================
:EXTRACT_SQLITE
set DISTROFILE=sqlite.zip

if not exist "%DISTRODIR%" (
  echo ===== Extracting SQLite distro =====
  tar -xf %DISTROFILE%
  if %ErrorLevel% EQU 0 (
    echo ----- Extracted  SQLite distro -----
  ) else (
    set ERROR_STATUS=%ErrorLevel%
    echo Error extracting SQLite distro.
    echo Errod code: !ERROR_STATUS!
  )
) else (
  echo ===== Using previously extracted SQLite distro =====
)

exit /b %ERROR_STATUS%


:: ============================================================================
:DOWNLOAD_ZLIB
set DISTRO=zlib.zip
set URL=https://zlib.net/zlib1211.zip

if not exist %DISTRO% (
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

if not exist "%ZLIBDIR%\win32" (
  echo ===== Extracting zlib distro =====
  rmdir /S /Q "%ZLIBDIR%" 1>>"%STDOUTLOG%" 2>>"%STDERRLOG%"
  tar -xf %DISTROFILE%
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
:MAKEFILE_MSC_TOP_AND_DEBUG
set FILENAME=Makefile.msc
if exist "%FILENAME%" (
  nmake /nologo /f "%FILENAME%" clean
  del "%FILENAME%" 2>nul
)
echo ========== Patching "%FILENAME%" ===========
copy /Y "%DISTRODIR%\%FILENAME%" "%BUILDDIR%"
set OLDTEXT=TOP = .
set NEWTEXT=TOP = %DISTRODIR%
tclsh "%BASEDIR%\replace.tcl" "%OLDTEXT%" "%NEWTEXT%" "%FILENAME%"
type "%FILENAME%.debug" >>"%FILENAME%"
echo ---------- Patched  "%FILENAME%" -----------

exit /b 0


:: ============================================================================
:MAKEFILE_MSC_ZLIB_STDCALL
set FILENAME=Makefile.msc
echo ========== Patching "%FILENAME%" ===========
set OLDTEXT=win32\Makefile.msc clean
set NEWTEXT=win32\Makefile.msc LOC=""-DZLIB_WINAPI -DZLIB_DLL"" clean
tclsh "%BASEDIR%\replace.tcl" "%OLDTEXT%" "%NEWTEXT%" "%FILENAME%"
type "%FILENAME%.debug" >>"%FILENAME%"
echo ---------- Patched  "%FILENAME%" -----------

exit /b 0


:: ============================================================================
:EXT_ADD_SOURCES_TO_MAKEFILE_MSC
set TARGETDIR=%BUILDDIR%
set FILENAME=Makefile.msc
tclsh "%BASEDIR%\addlines.tcl" "%FILENAME%" "%FILENAME%.ext" "%TARGETDIR%"

exit /b 0


:: ============================================================================
:EXT_ADD_SOURCES_TO_MKSQLITE3C_TCL
set TARGETDIR=%DISTRODIR%\tool
set FILENAME=mksqlite3c.tcl
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
:TEST_PATCH_MAIN_C_SQLITE3_H
set TARGETDIR=%BUILDDIR%\tsrc
set FILENAME=main.c
tclsh "%BASEDIR%\addlines.tcl" "%FILENAME%" "%FILENAME%.test" "%TARGETDIR%"
set FILENAME=sqlite3.h
tclsh "%BASEDIR%\addlines.tcl" "%FILENAME%" "%FILENAME%.test" "%TARGETDIR%"

exit /b 0


:: ============================================================================
:EXT_PATCH_MAIN_C
set TARGETDIR=%BUILDDIR%\tsrc
set FILENAME=main.c
tclsh "%BASEDIR%\addlines.tcl" "%FILENAME%" "%FILENAME%.1.ext" "%TARGETDIR%"
tclsh "%BASEDIR%\addlines.tcl" "%FILENAME%" "%FILENAME%.2.ext" "%TARGETDIR%"

exit /b 0


:: ============================================================================
:EXT_PATCH_CSV_C
set TARGETDIR=%BUILDDIR%\tsrc
set FILENAME=csv.c
tclsh "%BASEDIR%\addlines.tcl" "%FILENAME%" "%FILENAME%.ext" "%TARGETDIR%"
pushd "%TARGETDIR%"
set FLAG=SQLITE_ENABLE_CSV
set OLDTEXT=#include ^<sqlite3ext.h^>
set NEWTEXT=#if defined(%FLAG%)\n\n#include ^<sqlite3ext.h^>
tclsh "%BASEDIR%\replace.tcl" "%OLDTEXT%" "%NEWTEXT%" "%FILENAME%"
echo. >>"%FILENAME%"
echo #endif /* defined^(%FLAG%^) */ >>"%FILENAME%"
popd

exit /b 0


:: ============================================================================
:EXT_PATCH_ZIPFILE_C
set TARGETDIR=%BUILDDIR%\tsrc
set FILENAME=zipfile.c
pushd "%TARGETDIR%"
set FLAG=SQLITE_ENABLE_ZIPFILE
set OLDTEXT=#include \"sqlite3ext.h\"
set NEWTEXT=#if defined(%FLAG%)\n\n#include \"sqlite3ext.h\"
tclsh "%BASEDIR%\replace.tcl" "%OLDTEXT%" "%NEWTEXT%" "%FILENAME%"
echo. >>"%FILENAME%"
echo #endif /* defined^(%FLAG%^) */ >>"%FILENAME%"
popd

exit /b 0


:: ============================================================================
:COPY_BINARIES
echo ========== Copying binaries ===========
set BINDIR=%~dp0bin
if not exist "%BINDIR%" mkdir "%BINDIR%"
del /Q bin\* 2>nul
copy "%BUILDDIR%\sqlite3.dll" "%BINDIR%"
if exist "%BUILDDIR%\sqlite3.exe" copy "%BUILDDIR%\sqlite3.exe" "%BINDIR%"
if %USE_ICU%  EQU 1 copy /Y "%ICUBINDIR%\icu*.dll" "%BINDIR%"
if %USE_ZLIB% EQU 1 copy /Y "%ZLIBDIR%\zlib1.dll"  "%BINDIR%"
echo ---------- Copied  binaries -----------

exit /b 0
