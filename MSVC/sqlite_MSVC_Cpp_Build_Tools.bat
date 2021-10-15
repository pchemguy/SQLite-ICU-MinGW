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
call :MAIN %* 1>stdout.log 2>stderr.log
exit /b 0
:: ============================= END   DISPATCHER =============================


:: ================================ BEGIN MAIN ================================
:MAIN
SetLocal

set ERROR_STATUS=0

call :CHECK_PREREQUISITES
if %ERROR_STATUS%==1 exit /b 1

call :SET_TARGETS "%~1"
call :BUILD_OPTIONS
call :ICU_OPTIONS

set DISTRODIR=%~dp0sqlite
call :DOWNLOAD_SQLITE
if %ERROR_STATUS%==1 exit /b 1
call :EXTRACT_SQLITE
if %ERROR_STATUS%==1 exit /b 1
if not exist "%DISTRODIR%" (
  echo Distro directory does not exists. Exiting
  exit /b 1
)

set BUILDDIR=%~dp0build
if not exist "%BUILDDIR%" mkdir "%BUILDDIR%"

call :GENERATE_SPLITLINE_BAT
if %ErrorLevel% NEQ 0 (
  set ERROR_STATUS=%ErrorLevel%
  echo Failed to generate "splitline.bat"
  echo Errod code: !ERROR_STATUS!
  exit /b !ERROR_STATUS!
)

rem Enter BUILDDIR
cd /d "%BUILDDIR%" 2>nul
if %ErrorLevel% NEQ 0 (
  set ERROR_STATUS=%ErrorLevel%
  echo Cannot enter directory "%BUILDDIR%"
  echo Errod code: !ERROR_STATUS!
  exit /b !ERROR_STATUS!
)

call :PATCH_MAKEFILE_MSC
if %ErrorLevel% NEQ 0 (
  set ERROR_STATUS=%ErrorLevel%
  echo Make file patch error.
  echo Errod code: !ERROR_STATUS!
  exit /b !ERROR_STATUS!
)

if exist "sqlite3.c" nmake /nologo /f Makefile.msc clean
nmake /nologo /f Makefile.msc %TARGETS%
cd ..
rem Leave BUILDDIR

if exist "%BUILDDIR%\sqlite3.dll" goto :COPY_BINARIES

EndLocal
exit /b 0
:: ================================= END MAIN =================================


:: ============================================================================
:: ============================================================================
:SET_TARGETS
echo ===== Setting targets =====
if not "/%~1/"=="//" (
  set TARGETS=%~1
) else (
  echo.
  echo WARNING: no targets have been specified. Expected
  echo a space-separated list of targets as the first quoted
  echo script parameter. Nmake will produce debug output only.
  pause
  set TARGETS=echoconfig
)
echo ----- Set     targets -----

exit /b 0
:: ============================================================================


:CHECK_PREREQUISITES
echo ===== Verifying environment =====
if /%VisualStudioVersion%/==// (
  echo %%VisualStudioVersion%% is not set. Run this script from an MSVC shell.
  set ERROR_STATUS=1
) else (
  echo VisualStudioVersion=%VisualStudioVersion%
)
if /%VSINSTALLDIR%/==// (
  echo %%VSINSTALLDIR%% is not set. Run this script from an MSVC shell.
  set ERROR_STATUS=1
) else (
  echo VSINSTALLDIR=%VSINSTALLDIR%
)
if /%VCINSTALLDIR%/==// (
  echo %%VSINSTALLDIR%% is not set. Run this script from an MSVC shell.
  set ERROR_STATUS=1
) else (
  echo VCINSTALLDIR=%VCINSTALLDIR%
)

set CommandLocation=
for /f "Usebackq delims=" %%i in (`where cl.exe 2^>nul`) do (
  if /!CommandLocation!/==// (
    set CommandLocation=%%i
  )
)
if /%CommandLocation%/==// (
  echo cl.exe is not found. Run this script from an MSVC shell.
  set ERROR_STATUS=1
) else (
  echo CL_EXE=%CommandLocation%
)

set CommandLocation=
for /f "Usebackq delims=" %%i in (`where nmake.exe 2^>nul`) do (
  if /!CommandLocation!/==// (
    set CommandLocation=%%i
  )
)
if /%CommandLocation%/==// (
  echo nmake.exe is not found. Run this script from an MSVC shell.
  set ERROR_STATUS=1
) else (
  echo NMAKE_EXE=%CommandLocation%
)

set CommandLocation=
for /f "Usebackq delims=" %%i in (`where tclsh.exe 2^>nul`) do (
  if /!CommandLocation!/==// (
    set CommandLocation=%%i
  )
)
if /%CommandLocation%/==// (
  echo tclsh.exe is not found. TCL is required and must be in the path.
  set ERROR_STATUS=1
) else (
  echo TCLSH_EXE=%CommandLocation%
)

if %ERROR_STATUS%==0 (
  echo ----- Verified  environment -----
) else (
  echo ----- Environment is NOT OK -----
)

exit /b %ERROR_STATUS%


:: ============================================================================
:BUILD_OPTIONS
if "/%VSCMD_ARG_TGT_ARCH%/"=="/x86/" (
  set USE_STDCALL=1
) else (
  set USE_STDCALL=0
)
set SESSION=1
set RBU=1
set NO_TCL=1

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
-DSQLITE_SOUNDEX

exit /b 0


:ICU_OPTIONS
:: In VBA6, it might be necessary to load individual libraries explicitly in the
:: correct order (dependencies must be loaded before the depending libraries.
set USE_ICU=1
if %USE_ICU%==1 (
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

set USE_ZLIB=0
if %USE_ZLIB%==1 (
  set ZLIBDIR=..\zlib
)

exit /b 0


:: ============================================================================
:DOWNLOAD_SQLITE
set DISTROFILE=sqlite.zip
set URL=https://www.sqlite.org/src/zip/sqlite.zip

if not exist %DISTROFILE% (
  echo ===== Downloading current SQLite release =====
  set PSCMD=Invoke-WebRequest -Uri '%URL%' -OutFile '%DISTROFILE%'
  PowerShell -Command "& {!PSCMD!}"
  if %ErrorLevel% NEQ 0 (
    set ERROR_STATUS=%ErrorLevel%
    echo Error downloading SQLite distro.
    echo Errod code: !ERROR_STATUS!
  ) else (
    echo ----- Downloaded  current SQLite release -----
    rem curl %URL% --output "%DISTRO%"
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
  set PSCMD=Expand-Archive -Path '%DISTROFILE%' -DestinationPath '%~dp0'
  PowerShell -Command "& {!PSCMD!}"
  if %ErrorLevel% NEQ 0 (
    set ERROR_STATUS=%ErrorLevel%
    echo Error extracting SQLite distro.
    echo Errod code: !ERROR_STATUS!
  ) else (
    echo ----- Extracted  SQLite distro -----
  )
) else (
  echo ===== Using previously extracted SQLite distro =====
)

exit /b %ERROR_STATUS%


:: ============================================================================
:GENERATE_SPLITLINE_BAT
:: Generates "splitline.bat" script.
:: "splitline.bat" takes one quoted argument, splits it on the
:: space character, and outputs each part on a separate line.
echo ========== Generating "splitline.bat" ==========
set OUTPUT="splitline.bat"
(
  echo @echo off
) 1>%OUTPUT%
(
  echo.
  echo set ARGS=%%~1
  echo :NEXT_ARG
  echo   for /F "tokens=1* delims= " %%%%G in ^("%%ARGS%%"^) do ^(
  echo     echo %%%%G
  echo     set ARGS=%%%%H
  echo   ^)
  echo if defined ARGS goto NEXT_ARG
) 1>>%OUTPUT%
echo ---------- Generated  "splitline.bat" ----------

exit /b 0


:: ============================================================================
:PATCH_MAKEFILE_MSC
echo ========== Patching "Makefile.msc" ===========
copy /Y "%DISTRODIR%\Makefile.msc" "Makefile.msc" 1>nul

Powershell.exe Invoke-Command -scriptblock { ^
  "" ^
  $file = 'Makefile.msc'; ^
  $regex = '^TOP = .$'; ^
  $patch = 'TOP = %DISTRODIR%'; ^
  (Get-Content $file) -replace $regex, $patch ^| Set-Content $file; ^
  "" ^
}

set OUTPUT="Makefile.msc"
set "TAB=	"
(
  echo.
  echo echoconfig:
  echo %TAB%@echo --------------------------------
  echo %TAB%@echo REQ_FEATURE_FLAGS
  echo %TAB%@..\splitline.bat "$(REQ_FEATURE_FLAGS)"
  echo %TAB%@echo --------------------------------
  echo %TAB%@echo OPT_FEATURE_FLAGS
  echo %TAB%@..\splitline.bat "$(OPT_FEATURE_FLAGS)"
  echo %TAB%@echo --------------------------------
  echo %TAB%@echo EXT_FEATURE_FLAGS
  echo %TAB%@..\splitline.bat "$(EXT_FEATURE_FLAGS)"
  echo %TAB%@echo --------------------------------
  echo %TAB%@echo TCC
  echo %TAB%@..\splitline.bat "$(TCC)"
  echo %TAB%@echo --------------------------------
  echo %TAB%@echo USE_STDCALL=$^(USE_STDCALL^)
  echo %TAB%@echo USE_ZLIB=$^(USE_ZLIB^)
  echo %TAB%@echo USE_ICU=$^(USE_ICU^)
  echo %TAB%@echo FOR_WIN10=$^(FOR_WIN10^)
  echo %TAB%@echo DEBUG=$^(DEBUG^)
  echo %TAB%@echo SESSION=$^(SESSION^)
  echo %TAB%@echo RBU=$^(RBU^)
  echo %TAB%@echo ICUDIR=$^(ICUDIR^)
  echo %TAB%@echo ICUINCDIR=$^(ICUINCDIR^)
  echo %TAB%@echo ICULIBDIR=$^(ICULIBDIR^)
  echo %TAB%@echo ZLIBDIR=$^(ZLIBDIR^)
) 1>>%OUTPUT%
echo ---------- Patched  "Makefile.msc" -----------

exit /b 0


:: ============================================================================
:COPY_BINARIES
echo ========== Copying binaries ===========
set BINDIR=%~dp0bin
if not exist "%BINDIR%" mkdir "%BINDIR%"
del bin\*.dll 2>nul
copy "%BUILDDIR%\sqlite3.dll" "%BINDIR%"
if exist "%ICUBINDIR%\icuinfo.exe" copy "%ICUBINDIR%\icu*.dll" "%BINDIR%"
echo ---------- Copied  binaries -----------

exit /b 0
