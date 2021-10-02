@echo off
rem Build SQLite using MSVC toolset

SetLocal

set ERROR_STATUS=0

call :CHECK_PREREQUISITES
if %ERROR_STATUS%==1 exit /b 1

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

call :GENERATE_SPLITLINE_BAT
if %ErrorLevel% NEQ 0 (
  set ERROR_STATUS=%ErrorLevel%
  echo Failed to generate "splitline.bat"
  echo Errod code: !ERROR_STATUS!
  exit /b !ERROR_STATUS!
)

cd /d "%DISTRODIR%" 2>nul
if %ErrorLevel% NEQ 0 (
  set ERROR_STATUS=%ErrorLevel%
  echo Cannot enter directory "%~dp0sqlite"
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

if not /%~1/==// (
  set TARGET=%~1
) else (
  echo.
  echo WARNING: no targets have been specified. Nmake will produce debug output only.
  pause
  set TARGET=echoconfig
)
if exist "sqlite3.c" nmake /nologo /f Makefile.msc clean
nmake /nologo /f Makefile.msc %TARGET%
cd ..


EndLocal
exit /b 0


rem ============================================================================
rem ============================================================================
rem ============================================================================
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
  echo CL_HOME=%CommandLocation%
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
  echo NMAKE_HOME=%CommandLocation%
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
  echo TCL_HOME=%CommandLocation%
)

if %ERROR_STATUS%==0 (
  echo ----- Verified  environment -----
) else (
  echo ----- Environment is NOT OK -----
)
exit /b %ERROR_STATUS%


rem ============================================================================
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
rem For now ICU is disabled.
rem Compilation against precompiled MSVC 2019 binaries completes OK, but
rem the resulting library could not be loaded (ICU dll's are placed in
rem the same folder as the library). Attempt to compile ICU from source
rem failed. Further investigation of these issues is necessary.
rem 
set USE_ICU=0
rem if /%Platform%/==/x86/ (
rem   set ARCH=
rem ) else (
rem   set ARCH=64
rem )
rem set ICUDIR=%ProgramFiles%\icu4c
rem set ICUDIR=%ICUDIR: =%
rem set ICUINCDIR=%ICUDIR%\include
rem set ICULIBDIR=%ICUDIR%\lib%ARCH%

REM set USE_ZLIB=1
REM set ZLIBDIR=..\zlib

exit /b 0


rem ============================================================================
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
    exit /b !ERROR_STATUS!
  )
  echo ----- Downloaded  current SQLite release -----
  rem curl %URL% --output "%DISTRO%"
) else (
  echo ===== Using previously downloaded SQLite distro =====
)

exit /b 0


rem ============================================================================
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
    exit /b !ERROR_STATUS!
  )
  echo ----- Extracted  SQLite distro -----
) else (
  echo ===== Using previously extracted SQLite distro =====
)

exit /b 0


rem ============================================================================
:GENERATE_SPLITLINE_BAT
rem Generates "splitline.bat" script.
rem "splitline.bat" takes one quoted argument, splits it on the
rem space character, and outputs each part on a separate line.
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


rem ============================================================================
:PATCH_MAKEFILE_MSC
echo ========== Patching "Makefile.msc" ===========
if not exist Makefile.msc.bak (
  copy Makefile.msc Makefile.msc.bak
) else (
  copy /Y Makefile.msc.bak Makefile.msc 1>nul
)

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