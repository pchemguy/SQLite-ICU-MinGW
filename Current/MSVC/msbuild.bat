@echo off

:: ============================================================================
:: Call from CMD with command extensions and delayed expansion enabled.
:: Verify an active x86/x64 MSVC environment or locate and call vcvars64.bat.
:: Final verification returns 0 on success or 1 on failure.
:: For SQLite builds, USE_ICU=1 also checks DLLs in the active Conda prefix.
:: See msbuild.md for discovery, linker collision recovery, and usage.
:: ============================================================================

:: ============================================================================ MAIN BEGIN
:: ============================================================================
:MAIN

set "EXIT_STATUS=0"

call :COLOR_SCHEME

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

set "EXIT_STATUS=0"
set "_VCVARS="
set "VCVARS64=VC\Auxiliary\Build\vcvars64.bat"

:: --- 1. Check if already activated ---

echo %INFO% MSBuild: Checking if MSBuild environment is already activated...
if defined VSINSTALLDIR (
    echo %INFO% MSBuild: VSINSTALLDIR points to "%VSINSTALLDIR%".
    echo %OKOK% MSBuild: MSBuild environment already active. Skipping activation.
    call :VERIFY_ACTIVATION
    set "EXIT_STATUS=!ERRORLEVEL!"
    goto :MAIN_EXIT
) else (
    echo %INFO% MSBuild: Proceeding to MSBuild search.
    echo:
)

:: --- 2. VCVARS_CHECK      - Check explicit environment variable VCVARS ---
:: --- 3. MSVS_LOCATIONS    - Check default and custom MSVS locations    ---
:: --- 4. MSBUILD_LOCATIONS - Check BuildTools locations                 ---

call :VCVARS_CHECK || call :MSVS_LOCATIONS || call :MSBUILD_LOCATIONS
if defined _VCVARS call :MSBUILD_ACTIVATION
call :VERIFY_ACTIVATION & (set "EXIT_STATUS=!ERRORLEVEL!")

:MAIN_EXIT

if not defined EXIT_STATUS (set "EXIT_STATUS=0")
exit /b %EXIT_STATUS%
:: ============================================================================
:: ============================================================================ MAIN END


:: ############################################################################
:: ############################################################################
:: ############################################################################


:: ============================================================================ VCVARS_CHECK BEGIN
:: ============================================================================
:VCVARS_CHECK

set "_EXIT_STATUS=0"

echo %INFO% MSBuild: Checking if VCVARS points to vcvarsall.bat or vcvars64.bat.
if not defined VCVARS (
    call :WHERE_CLI "vcvars64.bat" "VCVARS64_BAT" "True"
    set "VCVARS=!CLIPATH!"
)
if not exist "%VCVARS%" (exit /b 1)

echo %INFO% MSBuild: VCVARS = "%VCVARS%".

set "_VCVARS=%VCVARS:vcvarsall.bat=vcvars64.bat%"
if /i not "%_VCVARS:~-12%"=="vcvars64.bat" (set "_VCVARS=")

if exist "%_VCVARS%" (
    echo %INFO% MSBuild: Attempting activation...
    exit /b 0
) else (
    set "_VCVARS="
)

set "_EXIT_STATUS=1"

if not defined _EXIT_STATUS (set "_EXIT_STATUS=0")
exit /b %_EXIT_STATUS%
:: ============================================================================
:: ============================================================================ VCVARS_CHECK END


:: ============================================================================ MSVS_LOCATIONS BEGIN
:: ============================================================================
:MSVS_LOCATIONS

set "_EXIT_STATUS=0"

for %%P in (
    "%ProgramFiles%\Microsoft Visual Studio" 
    "%ProgramFiles(x86)%\Microsoft Visual Studio"
    "%~d0\dev\Microsoft Visual Studio"
) do (
    echo %INFO% MSBuild: Checking for VS editions in "%%~P\{VERSION}\{KIND}".
    for /f "usebackq delims=" %%Y in (`dir /b /ad /O:-N "%%~P" 2^>nul`) do (
        for /d %%E in ("%%~P\%%Y\*") do (
            if exist "%%~fE\%VCVARS64%" (
               set "_VCVARS=%%~fE\%VCVARS64%"
               exit /b 0
            )
        )
    )
)

set "_EXIT_STATUS=1"

if not defined _EXIT_STATUS (set "_EXIT_STATUS=0")
exit /b %_EXIT_STATUS%
:: ============================================================================
:: ============================================================================ MSVS_LOCATIONS END


:: ============================================================================ MSBUILD_LOCATIONS BEGIN
:: ============================================================================
:MSBUILD_LOCATIONS

set "_EXIT_STATUS=0"

echo %INFO% MSBuild: Checking if BUILDTOOLS or MSBUILDTOOLS or MSBUILD point to the "BuildTools" directory and fallback locations.

call :CHECK_VARS MSBUILDTOOLS BUILDTOOLS MSBUILD

for %%D in (
    "%~dp0..\MSBuildTools"
    "%~dp0..\BuildTools"
    "%~d0\dev\MSBuildTools"
    "%~d0\dev\BuildTools"
    "%MSBUILDTOOLS%"
    "%BUILDTOOLS%"
    "%MSBUILD%"
) do (
    if exist "%%~fD\%VCVARS64%" (
        set "_VCVARS=%%~fD\%VCVARS64%"
        exit /b 0
    )
)

set "_EXIT_STATUS=1"

if not defined _EXIT_STATUS (set "_EXIT_STATUS=0")
exit /b %_EXIT_STATUS%
:: ============================================================================
:: ============================================================================ MSBUILD_LOCATIONS END


:: ============================================================================ MSBUILD_ACTIVATION BEGIN
:: ============================================================================
:MSBUILD_ACTIVATION

set "_EXIT_STATUS=0"

set "VSCMD_SKIP_SENDTELEMETRY=1"
echo:
echo %WARN% MSBuild: Activating MS Build Tools.
echo %INFO% MSBuild: Calling "%_VCVARS%"
echo:
call "%_VCVARS%" || (
    echo ----------------------------------------------------------------------
    echo:
    echo %ERROR% MSBuild: "%_VCVARS%" returned an error.
    exit /b 1
) 
echo ----------------------------------------------------------------------
echo:

if not exist "%VCINSTALLDIR%" (
    echo %ERROR% MSBuild: MS Build Tools activation failed.
    set "_EXIT_STATUS=1"
) else (
    echo %INFO% MSBuild: MS Build Tools activation succeeded.
    echo %INFO% MSBuild: Staus pending verification.
    set "_EXIT_STATUS=0"
)

if not defined _EXIT_STATUS (set "_EXIT_STATUS=0")
exit /b %_EXIT_STATUS%
:: ============================================================================
:: ============================================================================ MSBUILD_ACTIVATION END


:: ============================================================================ VERIFY_ACTIVATION BEGIN
:: ============================================================================
:VERIFY_ACTIVATION

setlocal
set "EXIT_STATUS=0"

echo:
echo %WARN% Verifying activation.
echo:

if defined VisualStudioVersion (
    echo %INFO% VisualStudioVersion=%VisualStudioVersion%
    echo:
) else (
    echo %ERROR% VisualStudioVersion is not set.
    set "EXIT_STATUS=1"
)

set "PAD10=          "
set "WIDTH=15"
set "TOOL_LABEL=VCINSTALLDIR=%PAD10%%PAD10%%PAD10%%PAD10%"
set "TOOL_LABEL=!TOOL_LABEL:~0,%WIDTH%!"
if exist "%VCINSTALLDIR%" (
    echo %INFO% %TOOL_LABEL% %VCINSTALLDIR%
) else (
    echo %ERROR% VCINSTALLDIR is not set.
    set "EXIT_STATUS=1"
)

set "EXPECTED_MACHINE="
if /i "%VSCMD_ARG_TGT_ARCH%"=="x86" set "EXPECTED_MACHINE=14C"
if /i "%VSCMD_ARG_TGT_ARCH%"=="x64" set "EXPECTED_MACHINE=8664"
if not defined EXPECTED_MACHINE (
    echo %ERROR% VSCMD_ARG_TGT_ARCH must be x86 or x64; got "!VSCMD_ARG_TGT_ARCH!".
    set "EXIT_STATUS=1"
)

call :WHERE_CLI "nmake.exe"    "NMAKE_EXE"     || (set "EXIT_STATUS=!ERRORLEVEL!")
call :WHERE_CLI "cl.exe"       "CL_EXE"        || (set "EXIT_STATUS=!ERRORLEVEL!")
set "CL_EXE=%CLIPATH%"
call :WHERE_CLI "link.exe"     "LINK_EXE"      || (set "EXIT_STATUS=!ERRORLEVEL!")
set "LINK_EXE=%CLIPATH%"
call :WHERE_CLI "lib.exe"      "LIB_EXE"       || (set "EXIT_STATUS=!ERRORLEVEL!")
call :WHERE_CLI "dumpbin.exe"  "DUMPBIN_EXE"   || (set "EXIT_STATUS=!ERRORLEVEL!")
call :WHERE_CLI "curl.exe"     "CURL_EXE"      || (set "EXIT_STATUS=!ERRORLEVEL!")
call :WHERE_CLI "tclsh.exe"    "TCLSH_EXE"   "True"

if defined CL_EXE call :VERIFY_MS_LINKER "%CL_EXE%" "%LINK_EXE%" || set "EXIT_STATUS=1"

if not exist "%windir%\System32\tar.exe" (
    echo %ERROR% Windows tar is not found at "%windir%\System32\tar.exe".
    set "EXIT_STATUS=1"
)

if "%USE_ICU%"=="1" (
    call :CHECK_ICU_MACHINE || set "EXIT_STATUS=1"
)

echo:

if "%EXIT_STATUS%"=="0" (
    echo %OKOK% MSBuild: MS Build Tools are ready..
    echo %OKOK% MSBuild: VSINSTALLDIR points to "%VSINSTALLDIR%".
) else (
    echo %ERROR% MSBuild: MS Build Tools verification failed.
)

echo:
echo ------------------------------------------------------------------------------------
echo:

if not defined EXIT_STATUS (set "EXIT_STATUS=0")
endlocal & exit /b %EXIT_STATUS%
:: ============================================================================
:: ============================================================================ VERIFY_ACTIVATION END


:: ============================================================================ WHERE_CLI BEGIN
:: ============================================================================
:WHERE_CLI
:: ---------------------------------------------------------------------
:: %1 - Tool for `where` command, e.g., "link.exe"
:: %2 - Label for stdout message, e.g., "LINK_EXE"
:: %3 - If TRUE, treat as optional dependency {WARN, not ERROR}.
:: ---------------------------------------------------------------------

set "_EXIT_STATUS=0"
set "TOOL=%~1"
set "PAD10=          "
set "WIDTH=15"
set "TOOL_LABEL=%~2=%PAD10%%PAD10%%PAD10%%PAD10%"
set "TOOL_LABEL=!TOOL_LABEL:~0,%WIDTH%!"
if /i "%~3"=="TRUE" (
    set "LEVEL=%WARN%"
) else (
    set "LEVEL=%ERROR%"
)

set "CLIPATH="
set "CLIDIR="
for /f "usebackq delims=" %%I in (`where "%TOOL%" 2^>nul`) do (
    if "!CLIPATH!"=="" (
        set "CLIPATH=%%~I"
        set "CLIDIR=%%~dpI"
    )
)
if defined CLIPATH (
    echo %INFO% %TOOL_LABEL% %CLIPATH%
) else (
    echo %LEVEL% %TOOL_LABEL% is not found.
    set "_EXIT_STATUS=1"
)
if /i "%~3"=="TRUE" (set "_EXIT_STATUS=0")

if not defined _EXIT_STATUS (set "_EXIT_STATUS=0")
exit /b %_EXIT_STATUS%
:: ============================================================================
:: ============================================================================ WHERE_CLI END


:: ============================================================================ VERIFY_MS_LINKER BEGIN
:: ============================================================================
:VERIFY_MS_LINKER
:: ---------------------------------------------------------------------
:: %1 - cl.exe path.
:: %2 - link.exe path.
:: ---------------------------------------------------------------------

setlocal
set "EXIT_STATUS=0"

echo %WARN% Verifying MS linker.
echo:

set "_CL_EXE=%~f1"
set "_CL_DIR=%~dp1"

set "_LINK_EXE=%~f2"
set "_LINK_DIR=%~dp2"

echo:

link.exe /? 2>&1 | findstr.exe /i /c:"Microsoft (R) Incremental Linker" /c:"/INCREMENTAL" >nul
set "EXIT_STATUS=%ERRORLEVEL%"

if /i not "%_LINK_DIR%"=="%_CL_DIR%" (
    echo %WARN% MSBuild: link.exe directory does not match active cl.exe directory.
    echo %INFO% MSBuild: Resolved link.exe: "%_LINK_EXE%"
    echo %INFO% MSBuild: Active cl.exe:     "%_CL_EXE%"
)

if "%EXIT_STATUS%"=="0" (
    echo %INFO% Verified Microsoft linker.
    goto :VERIFY_MS_LINKER_EXIT
)

:: --- Issue a warning and attempt resolving collision ---

echo %ERROR% MSBuild: Linker collision detected: link.exe is not the Microsoft Incremental Linker.
echo %INFO% MSBuild: Executing link.exe resolved to "%_LINK_EXE%" -- likely MSYS/Git/GNU link.exe.
echo %INFO% MSBuild: Expected MSVC toolset directory: "%_CL_DIR%".
echo:

rem If the offending link.exe does not belong to a local conda environment
rem with the creator script having a matching name {Anaconda - Anaconda.bat}
rem sitting next to the environemnt directory, fail without renaming.
rem
if not exist "%_LINK_EXE:\Library\usr\bin\link.exe=%.bat" (
    echo %WARN% "%%_LINK_EXE:\Library\usr\bin\link.exe=%%.bat" is not a valid batch file.
    echo %INFO% Automatic reoslution of link.exe collision is not supported.
    echo %INFO% Consider manual rename if appropriate.
    goto :VERIFY_MS_LINKER_EXIT
)

echo %WARN% Renaming the offending linker.
ren "%_LINK_EXE%" "link_.exe" || (
    echo %ERROR% Failed to rename offending linker.
    goto :VERIFY_MS_LINKER_EXIT
)

call :WHERE_CLI "cl.exe" "CL_EXE"
set "CL_EXE=%CLIPATH%"
call :WHERE_CLI "link.exe" "LINK_EXE"
set "LINK_EXE=%CLIPATH%"

link.exe /? 2>&1 | findstr.exe /i /c:"Microsoft (R) Incremental Linker" /c:"/INCREMENTAL" >nul
set "EXIT_STATUS=%ERRORLEVEL%"

if not "%CL_EXE:cl.exe=%"=="%LINK_EXE:link.exe=%" (
    echo %ERROR% MSBuild: Linker and compiler are not in the same directory.
    set "EXIT_STATUS=1"
)

if "%EXIT_STATUS%"=="0" (
    echo %WARN% Renamed the offending link.exe to link_.exe and Verified Microsoft linker.
) else (
    echo %ERROR% Failed to resolve conflict by renaming the offending link.exe.
)

:VERIFY_MS_LINKER_EXIT

if not defined EXIT_STATUS (set "EXIT_STATUS=0")
endlocal & exit /b %EXIT_STATUS%
:: ============================================================================
:: ============================================================================ VERIFY_MS_LINKER END


:: ============================================================================ CHECK_ICU_MACHINE BEGIN
:: ============================================================================
:CHECK_ICU_MACHINE

if not defined CONDA_PREFIX (
    echo %ERROR% USE_ICU=1 requires CONDA_PREFIX pointing to an active Conda environment.
    exit /b 1
)
set "ICU_BIN=%CONDA_PREFIX%\Library\bin"
set "FOUND_ICU="
for /f "usebackq delims=" %%F in (`dir /b /a:-d "%ICU_BIN%\icuuc*.dll" 2^>nul ^| findstr /i /r /x "icuuc[0-9][0-9]*\.dll"`) do (
    set "FOUND_ICU=1"
    set "MACHINE=unknown"
    for /f "usebackq tokens=1,2" %%M in (`dumpbin.exe /nologo /headers "%ICU_BIN%\%%F" ^|^| echo unreadable machine`) do (
        if /i "%%N"=="machine" set "MACHINE=%%M"
    )
    if /i not "!MACHINE!"=="%EXPECTED_MACHINE%" (
        echo %ERROR% "%ICU_BIN%\%%F": expected %VSCMD_ARG_TGT_ARCH% [%EXPECTED_MACHINE%], observed !MACHINE!.
        exit /b 1
    )
    echo %OKOK% "%ICU_BIN%\%%F": PE machine !MACHINE! matches target %VSCMD_ARG_TGT_ARCH%.
)
if not defined FOUND_ICU (
    echo %ERROR% No versioned ICU common DLL found in "%ICU_BIN%".
    exit /b 1
)
exit /b 0
:: ============================================================================
:: ============================================================================ CHECK_ICU_MACHINE END


:: ============================================================================ CHECK_VARS BEGIN
:: ============================================================================
:CHECK_VARS
:: 
:: Accepts variable number of variable name candidates. For each name reports,
:: if the corresponding variable is undefined or its value, if defined.

setlocal

set "PAD10=          "
set "WIDTH=25"

echo:
echo ----------------------------------------------------------------------
echo Checking environment variables:
echo     %*
echo:

:NEXT_VAR

if "%~1"=="" goto :CHECK_VARS_EXIT

set "VAR_LABEL=%~1=%PAD10%%PAD10%%PAD10%%PAD10%"
set "VAR_LABEL=!VAR_LABEL:~0,%WIDTH%!"

if defined %~1 (
    echo %INFO% %VAR_LABEL% ''!%~1!''
) else (
    echo %WARN% %VAR_LABEL% not defined.
)
shift & goto :NEXT_VAR

:CHECK_VARS_EXIT

echo ----------------------------------------------------------------------
echo:

endlocal & exit /b 0
:: ============================================================================
:: ============================================================================ CHECK_VARS END


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
