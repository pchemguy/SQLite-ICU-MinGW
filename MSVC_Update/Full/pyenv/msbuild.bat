@echo off

:: ============================================================================
::  Purpose:
::    Detects and activates Microsoft Build Tools (MSVC) environment if needed.
::    This script is idempotent and can be safely re-run.
::
::  Behavior:
::    - If MS Build Tools already active (VSINSTALLDIR set), exits successfully.
::    - Otherwise, searches standard and custom installation paths.
::    - Activates 64-bit environment via vcvars64.bat when found.
::
::  Preconditions:
::    - The CALLER's environment must have delayed expansion enabled
::      *prior* to calling this script.
::    - NOCOLOR: If set, gracefully falls back to no color.
::
::  Exit codes:
::    0 = success
::    1 = activation failed or not found
:: ============================================================================

:: --- Escape sequence templates for color coded console output ---

call :COLOR_SCHEME

:: --- MS Build Tools environment is activated? ---
::
:: Assume that activated shell must have variable VSINSTALLDIR set and
:: main activation script present in
:: "%VSINSTALLDIR%\VC\Auxiliary\Build\vcvarsall.bat"

echo:
echo ====================================================================================
echo ====================================================================================
echo == %WARN%                                                            %WARN% ==
echo == %WARN%                    MS Build Tools Check                    %WARN% ==
echo == %WARN%                                                            %WARN% ==
echo == %WARN% CLI: "%~f0" %*
echo ====================================================================================
echo ====================================================================================
echo:

set "EXIT_STATUS=1"

:: --- Check if already activated ---

echo %INFO% MSBuild: Checking if already activated...
set "_VCVARS=%VSINSTALLDIR%\VC\Auxiliary\Build\vcvarsall.bat"
if defined VSINSTALLDIR if exist "%_VCVARS%" (
  echo %INFO% MSBuild: VSINSTALLDIR points to "%VSINSTALLDIR%".
  echo %OKOK% MSBuild: Environment already active. Skipping activation.
  set "EXIT_STATUS=0"
  goto :MSBUILD_ACTIVATED
)

:: --- Check for default locations of VS editions ---

set "_MSVS=%ProgramFiles%\Microsoft Visual Studio"
echo %INFO% MSBuild: Checking for default locations of VS editions in "%_MSVS%\{VERSION}\{KIND}".
if exist "%_MSVS%" (
    for /f "usebackq delims=" %%Y in (`dir /b /O:-N "%_MSVS%"`) do (
        for /d %%E in ("%_MSVS%\%%Y\*") do (
            set "_VCVARS=%%E\VC\Auxiliary\Build\vcvarsall.bat"
            if exist "!_VCVARS!" goto :MSBUILD_ACTIVATION
            set "_VCVARS="
        )
    )
)

:: --- Check for custom locations of VS editions in dev ---

set "_MSVS=%~dp0..\Microsoft Visual Studio"
echo %INFO% MSBuild: Checking for custom locations of VS editions in "%_MSVS%\{VERSION}\{KIND}".
if exist "%_MSVS%" (
    for /f "usebackq delims=" %%Y in (`dir /b /O:-N "%_MSVS%"`) do (
        for /d %%E in ("%_MSVS%\%%Y\*") do (
            set "_VCVARS=%%E\VC\Auxiliary\Build\vcvarsall.bat"
            if exist "!_VCVARS!" goto :MSBUILD_ACTIVATION
            set "_VCVARS="
        )
    )
)

:: --- Check if VCVARS is defined ---

echo %INFO% MSBuild: Checking if VCVARS points to vcvarsall.bat.
if defined VCVARS if exist "%VCVARS%" (
  set "_VCVARS=%VCVARS%"
  echo %INFO% MSBuild: VCVARS points to "%VCVARS%". Attempting activation...
  goto :MSBUILD_ACTIVATION
)

:: --- vcvarsall.bat on the PATH? ---

echo %INFO% MSBuild: Checking if vcvarsall.bat is on the PATH.
set "_VCVARS="
for /f "usebackq tokens=* delims=" %%A in (`where vcvarsall.bat 2^>nul`) do (
  if exist "%%~A" (
    set "_VCVARS=%%~A"
    echo %INFO% MSBuild: Found vcvarsall.bat on the PATH: "!_VCVARS!". Attempting activation...
    goto :MSBUILD_ACTIVATION
  )
)

:: --- BuildTools or its parent on the PATH? ---
::
:: If BuildTools are in
::   "C:\Program Files\Microsoft Visual Studio\2022\BuildTools"
:: and the main BuildTools environment setting script in 
::   "C:\Program Files\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvarsall.bat",
:: add either
::   "C:\Program Files\Microsoft Visual Studio\2022"
::   "C:\Program Files\Microsoft Visual Studio\2022\BuildTools"
:: to the PATH.

echo %INFO% MSBuild: Checking if "BuildTools" or its parent are on the PATH.
set "_PATH=%Path:"=%"
set "_PATH="%_PATH:;=";"%""

:: Iterates over individual PATH components.

for %%A in (%_PATH%) do (
  set "_VCVARS=%%~A\VC\Auxiliary\Build\vcvarsall.bat"
  if exist "%_VCVARS%" goto :MSBUILD_ACTIVATION
  set "_VCVARS=%%~A\BuildTools\VC\Auxiliary\Build\vcvarsall.bat"
  if exist "%_VCVARS%" goto :MSBUILD_ACTIVATION
)
set "_VCVARS="
set "_PATH="

:: --- Check custom env variables ---
::
:: Set either BUILDTOOLS or MSBUILDTOOLS to point to BuildTools (same as VSINSTALLDIR after
:: MS Build Tools environment is activated), i.e., main script should be
::   %BUILDTOOLS%\VC\Auxiliary\Build\vcvarsall.bat%

echo %INFO% MSBuild: Checking if BUILDTOOLS or MSBUILDTOOLS point to the "BuildTools" directory.
set "_VCVARS=%BUILDTOOLS%\VC\Auxiliary\Build\vcvarsall.bat"
if exist "%_VCVARS%" goto :MSBUILD_ACTIVATION
set "_VCVARS=%MSBUILDTOOLS%\VC\Auxiliary\Build\vcvarsall.bat"
if exist "%_VCVARS%" goto :MSBUILD_ACTIVATION

:: --- Directory junction MSBuildTools or BuildTools fallback ---
::
:: This script's project might be placed under some "dev" directory also containing
:: directory junction, pointing to MSVS BuildTools directory (see above) called either
::   BuildTools
::   MSBuildTools
:: Final check - the same directory junction might be under "dev" directory
:: created in the root of the current drive.

echo %INFO% MSBuild: Checking custom fallback locations for BuildTools.
set "_VCVARS=%~dp0..\MSBuildTools\VC\Auxiliary\Build\vcvarsall.bat"
if exist "%_VCVARS%" goto :MSBUILD_ACTIVATION
set "_VCVARS=%~dp0..\BuildTools\VC\Auxiliary\Build\vcvarsall.bat"
if exist "%_VCVARS%" goto :MSBUILD_ACTIVATION
set "_VCVARS=%~d0\dev\MSBuildTools\VC\Auxiliary\Build\vcvarsall.bat"
if exist "%_VCVARS%" goto :MSBUILD_ACTIVATION
set "_VCVARS=%~d0\dev\BuildTools\VC\Auxiliary\Build\vcvarsall.bat"
if exist "%_VCVARS%" goto :MSBUILD_ACTIVATION

:: --- MSBuildTools not found ---

set "EXIT_STATUS=1"
echo %ERROR% MSBuild: MS Build Tools activation script not found.
echo %ERROR% MSBuild: If MS Build Tools are installed, either
echo %ERROR% MSBuild:   - start this script from a preactivated MS Build Tools shell
echo %ERROR% MSBuild:   - see script notes above regarding checked locations and variables
echo %ERROR% MSBuild: See this accepted SO answer https://stackoverflow.com/a/64262038/17472988
echo %ERROR% MSBuild: regarding MS Build Tools installation.
echo:
goto :MSBUILD_ACTIVATED

:MSBUILD_ACTIVATION

::--- MSBuildTools found ---

if not exist "%_VCVARS:all.bat=64.bat%" (
  echo %ERROR% MSBuild: 64-bit activation script not found at "%_VCVARS:all.bat=64.bat%".
  set "EXIT_STATUS=1"
  goto :MSBUILD_ACTIVATED
)

set "VSCMD_SKIP_SENDTELEMETRY=1"
echo:
echo %WARN% MSBuild: Activating MS Build Tools.
echo %INFO% MSBuild: Calling "%_VCVARS:all.bat=64.bat%"
echo:
call "%_VCVARS:all.bat=64.bat%"
set "EXIT_STATUS=%ERRORLEVEL%"
echo:
if not "%EXIT_STATUS%"=="0" (
  echo %ERROR% MSBuild: vcvars64.bat returned an error.
  set "EXIT_STATUS=1"
  goto :MSBUILD_ACTIVATED
)

if not defined VSINSTALLDIR (
  echo %ERROR% MSBuild: Activation returned success, but VSINSTALLDIR is missing. Aborting...
  set "EXIT_STATUS=1"
  goto :MSBUILD_ACTIVATED
)

if exist "%VSINSTALLDIR%VC\Auxiliary\Build\vcvarsall.bat" (
  set "EXIT_STATUS=0"
) else (
  set "EXIT_STATUS=1"
)
if "%EXIT_STATUS%"=="0" (
  echo %OKOK% MSBuild: MS Build Tools activation succeeded.
  echo %OKOK% MSBuild: VSINSTALLDIR points to "%VSINSTALLDIR:~0,-1%".
) else (
  echo %ERROR% MSBuild: MS Build Tools activation failed.
  echo %ERROR% MSBuild: Used script "%_VCVARS:all.bat=64.bat%".
)

:MSBUILD_ACTIVATED

set  "INFO="
set  "OKOK="
set  "WARN="
set "ERROR="
set "_MSVS="
set "_VCVARS="

exit /b %EXIT_STATUS%


:: ============================================================================ COLOR_SCHEME BEGIN
:: ============================================================================
:COLOR_SCHEME
:: ---------------------------------------------------------------------
:: Color Scheme (with NOCOLOR fallback)
:: ---------------------------------------------------------------------

if defined NOCOLOR (
  set  "INFO= [INFO]  "
  set  "OKOK= [-OK-]  "
  set  "WARN= [WARN]  "
  set "ERROR= [ERROR] "
) else (
  set  "INFO=[100;92m [INFO]  [0m"
  set  "OKOK=[103;94m [-OK-]  [0m"
  set  "WARN=[106;35m [WARN]  [0m"
  set "ERROR=[105;34m [ERROR] [0m"
)

exit /b 0
:: ============================================================================ 
:: ============================================================================ COLOR_SCHEME END
