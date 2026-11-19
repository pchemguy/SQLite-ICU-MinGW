@echo off

::
:: Checks MSBuild environment.
::

:: ============================================================================ MAIN BEGIN
:: ============================================================================
:MAIN

SetLocal EnableExtensions EnableDelayedExpansion

set "ERROR_STATUS=0"

call :COLOR_SCHEME

echo:
echo --------------------------------------------------------------------------------
echo %WARN% Checking MSBuild environment.
echo:

if "%VisualStudioVersion%"=="" (
    echo %ERROR% %%VisualStudioVersion%% is not set. Run this script from an MSVC shell.
    set "ERROR_STATUS=1"
) else (
    echo %INFO% VisualStudioVersion=%VisualStudioVersion%
)

if "%VCINSTALLDIR%"=="" (
    echo %ERROR% %%VSINSTALLDIR%% is not set. Run this script from an MSVC shell.
    set "ERROR_STATUS=1"
) else (
    echo %INFO% VCINSTALLDIR=%VCINSTALLDIR%
)

set "CommandLocation="
for /f "usebackq delims=" %%I in (`where cl.exe 2^>nul`) do (
    if "!CommandLocation!"=="" (set "CommandLocation=%%~I")
)
if "%CommandLocation%"=="" (
    echo %ERROR% cl.exe is not found. Run this script from an MSVC shell.
    set "ERROR_STATUS=1"
) else (
    echo %INFO% CL_EXE=      %CommandLocation%
)

set "CommandLocation="
for /f "usebackq delims=" %%I in (`where nmake.exe 2^>nul`) do (
    if "!CommandLocation!"=="" (set "CommandLocation=%%~I")
)
if "%CommandLocation%"=="" (
    echo %ERROR% nmake.exe is not found. Run this script from an MSVC shell.
    set "ERROR_STATUS=1"
) else (
    echo %INFO% NMAKE_EXE=   %CommandLocation%
)

set "CommandLocation="
for /f "usebackq delims=" %%I in (`where tclsh.exe 2^>nul`) do (
    if "!CommandLocation!"=="" (set "CommandLocation=%%I")
)
if "%CommandLocation%"=="" (
    echo %WARN% tclsh.exe was not found on PATH. Continuing without external Tcl.
) else (
    echo %INFO% TCLSH_EXE=   %CommandLocation%
)

echo:
if "%ERROR_STATUS%"=="0" (
    echo %OKOK% Environment is OK
) else (
    echo %ERROR% Environment is NOT OK
)

echo:
echo %WARN% Completed MSBuild environment check.
echo --------------------------------------------------------------------------------
echo:

endlocal && exit /b %ERROR_STATUS%
:: ============================================================================
:: ============================================================================ MAIN END


:: ############################################################################
:: ############################################################################
:: ############################################################################


:: ============================================================================ COLOR_SCHEME BEGIN
:: ============================================================================
:COLOR_SCHEME
:: ---------------------------------------------------------------------
:: Color Scheme (with NOCOLOR fallback)
:: ---------------------------------------------------------------------

if defined _ARG_NOCOLOR set "NOCOLOR=1"
if defined NO_COLOR set "NOCOLOR=1"
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
