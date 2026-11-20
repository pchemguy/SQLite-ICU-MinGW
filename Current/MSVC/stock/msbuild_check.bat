@echo off

::
:: Checks the MSVC/NMake environment and, when USE_ICU=1, the Conda ICU DLL architecture.
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
    echo %ERROR% %%VCINSTALLDIR%% is not set. Run this script from an MSVC shell.
    set "ERROR_STATUS=1"
) else (
    echo %INFO% VCINSTALLDIR=%VCINSTALLDIR%
)

set "EXPECTED_MACHINE="
if /i "%VSCMD_ARG_TGT_ARCH%"=="x86" set "EXPECTED_MACHINE=14C"
if /i "%VSCMD_ARG_TGT_ARCH%"=="x64" set "EXPECTED_MACHINE=8664"
if not defined EXPECTED_MACHINE (
    echo %ERROR% VSCMD_ARG_TGT_ARCH must be x86 or x64; got "!VSCMD_ARG_TGT_ARCH!".
    set "ERROR_STATUS=1"
)

set "CLIPATH="
for /f "usebackq delims=" %%I in (`where cl.exe 2^>nul`) do (
    if "!CLIPATH!"=="" (set "CLIPATH=%%~I")
)
if "%CLIPATH%"=="" (
    echo %ERROR% cl.exe is not found. Run this script from an MSVC shell.
    set "ERROR_STATUS=1"
) else (
    echo %INFO% CL_EXE=      %CLIPATH%
)

set "CLIPATH="
for /f "usebackq delims=" %%I in (`where nmake.exe 2^>nul`) do (
    if "!CLIPATH!"=="" (set "CLIPATH=%%~I")
)
if "%CLIPATH%"=="" (
    echo %ERROR% nmake.exe is not found. Run this script from an MSVC shell.
    set "ERROR_STATUS=1"
) else (
    echo %INFO% NMAKE_EXE=   %CLIPATH%
)

for %%T in (dumpbin.exe lib.exe curl.exe) do (
    where /q %%T || (
        echo %ERROR% %%T is not found on PATH.
        set "ERROR_STATUS=1"
    )
)
if not exist "%windir%\System32\tar.exe" (
    echo %ERROR% Windows tar is not found at "%windir%\System32\tar.exe".
    set "ERROR_STATUS=1"
)

set "CLIPATH="
for /f "usebackq delims=" %%I in (`where tclsh.exe 2^>nul`) do (
    if "!CLIPATH!"=="" (set "CLIPATH=%%I")
)
if "%CLIPATH%"=="" (
    echo %WARN% tclsh.exe was not found on PATH. Continuing without external Tcl.
) else (
    echo %INFO% TCLSH_EXE=   %CLIPATH%
)

if "%USE_ICU%"=="1" if "%ERROR_STATUS%"=="0" (
    call :CHECK_ICU_MACHINE || set "ERROR_STATUS=1"
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


:: ============================================================================ CHECK_ICU_MACHINE BEGIN
:: ============================================================================
:CHECK_ICU_MACHINE

if not defined CONDA_PREFIX (
    echo %ERROR% USE_ICU=1 requires an active Conda environment.
    exit /b 1
)
set "ICU_BIN=!CONDA_PREFIX!\Library\bin"
set "FOUND_ICU="
for /f "usebackq delims=" %%F in (`dir /b /a:-d "!ICU_BIN!\icuuc*.dll" 2^>nul ^| findstr /i /r /x "icuuc[0-9][0-9]*\.dll"`) do (
    set "FOUND_ICU=1"
    set "MACHINE=unknown"
    for /f "usebackq tokens=1,2" %%M in (`dumpbin.exe /nologo /headers "!ICU_BIN!\%%F" ^|^| echo unreadable machine`) do (
        if /i "%%N"=="machine" set "MACHINE=%%M"
    )
    if /i not "!MACHINE!"=="%EXPECTED_MACHINE%" (
        echo %ERROR% "!ICU_BIN!\%%F": expected %VSCMD_ARG_TGT_ARCH% [%EXPECTED_MACHINE%], observed !MACHINE!.
        exit /b 1
    )
    echo %OKOK% "!ICU_BIN!\%%F": PE machine !MACHINE! matches target %VSCMD_ARG_TGT_ARCH%.
)
if not defined FOUND_ICU (
    echo %ERROR% No versioned ICU common DLL found in "!ICU_BIN!".
    exit /b 1
)
exit /b 0
:: ============================================================================
:: ============================================================================ CHECK_ICU_MACHINE END


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
