@echo off
setlocal EnableDelayedExpansion EnableExtensions

:: ============================================================================
::  Purpose:
::    Bootstraps a fully functional Conda/Micromamba-based Python environment.
::
::  Core YAML / Config files:
::      - <script>_bootstrap.yml   - minimal bootstrap environment
::                                   Python/Conda/Mamba/UV
::      - pyproject.toml           - Python version fallback when bootstrap
::                                   YAML is not provided
::      - requirements.txt         - pip-only environment
::      - <script>.txt             - pip-only environment
::      - <script>.yml             - main environment definition (optional)
::      - <script>_generated.yml   - generated full final resolved environment
::
::  Notes:
::      At least one of <script>_bootstrap.yml or pyproject.toml must be
::      provided.
::
::      When pyproject.toml only is provided:
::          pyproject.toml must contain:
::              requires-python = ">=3.10"
::          Attempts to bootstrap CPython from a NuGet package (no Conda).
::          Creates a minimal conda.bat and mamba.bat in condabin\ for
::          compatibility with conda_far.bat.
::
::  Exit Codes:
::      0  - Success
::      1+ - Failure during environment or dependency setup
::
::  Related Scripts:
::      conda_far.bat   - Initializes cache and activates full environment.
:: ============================================================================

set "FINAL_EXIT_CODE=1"

echo :========== ========== ========== ========== ==========:
echo  Bootstrapping Python Environment
echo :---------- ---------- ---------- ---------- ----------:
echo:         ----- %DATE% %TIME% -----
echo: CLI: "%~f0" %*
echo:

:: --- Escape sequence templates for color coded console output ---

call :COLOR_SCHEME

:: --- Parse arguments ---

call :PARSE_ARGS %*
if not "%ERRORLEVEL%"=="0" (
    set "FINAL_EXIT_CODE=%ERRORLEVEL%"
    echo %ERROR% Failed to parse arguments. Aborting...
    goto :CLEANUP
)

:: --- Re-apply color scheme in case /nocolor was passed ---

call :COLOR_SCHEME

:: --- Determine base components of environment path and check for existing Python ---

set "_ENV_PREFIX=%~dpn0"
if exist "%_ENV_PREFIX%\python.exe" (
    echo %WARN% Found existing "%_ENV_PREFIX%\python.exe". Skipping bootstrapping...
    set "FINAL_EXIT_CODE=0"
    goto :CLEANUP
)

:: --- Check prerequisites ---

call :PREREQUISITES
if not "%ERRORLEVEL%"=="0" (
    set "FINAL_EXIT_CODE=%ERRORLEVEL%"
    echo %ERROR% Failed prerequisite checks. See error above. Aborting...
    goto :CLEANUP
)

:: --------------------------------------------------------
:: BASE CONFIG
:: --------------------------------------------------------
set "PYPROJECT=%~dp0pyproject.toml"
if not exist "%PYPROJECT%" (
    echo %WARN% "%PYPROJECT%" not found. Skipping...
    set "PYPROJECT="
) else (
    echo %INFO% Using environment file "%PYPROJECT%".
)

set "YAML_BOOTSTRAP=%~dpn0_bootstrap.yml"
if not exist "%YAML_BOOTSTRAP%" (
    if defined PYPROJECT (
        echo %WARN% Conda bootstrap file "%YAML_BOOTSTRAP%" not found. Attempting to bootstrap CPython nupkg via "%PYPROJECT%".
        set "YAML_BOOTSTRAP="
    ) else (
        echo %ERROR% Neither bootstrap file "%YAML_BOOTSTRAP%" nor "%~dp0pyproject.toml" was found. Aborting...
        set "FINAL_EXIT_CODE=1"
        goto :CLEANUP
    )
) else (
    echo %INFO% Using bootstrap environment file "%YAML_BOOTSTRAP%".
)

set "YAML=%~dpn0.yml"
if not exist "%YAML%" (
    echo %WARN% Main environment file "%YAML%" not found. Skipping...
    set "YAML="
) else (
    echo %INFO% Using main environment file "%YAML%".
)

if not defined YAML if not defined PYPROJECT (
    set "FINAL_EXIT_CODE=1"
    echo %ERROR% Neither Conda environment "%~dpn0.yml" nor "%~dp0pyproject.toml" found. Aborting...
    goto :CLEANUP
)

set "PIP_REQ=%~dp0requirements.txt"
if not exist "%PIP_REQ%" (
    echo %WARN% "%PIP_REQ%" not found. Skipping...
    set "PIP_REQ="
) else (
    echo %INFO% Using environment file "%PIP_REQ%".
)

set "PIP_TXT=%~dpn0.txt"
if not exist "%PIP_TXT%" (
    echo %WARN% "%PIP_TXT%" not found. Skipping...
    set "PIP_TXT="
) else (
    echo %INFO% Using environment file "%PIP_TXT%".
)

:: --------------------------------------------------------
:: VERBOSITY
:: --------------------------------------------------------
if not defined _ARG_Q (
    set "VERBOSE=-v"
) else (
    set "VERBOSE="
)

:: --------------------------------------------------------
:: Initialize cache directory via conda_far.bat /cache
:: --------------------------------------------------------
call "%~dp0conda_far.bat" /cache
if not "%ERRORLEVEL%"=="0" (
    set "FINAL_EXIT_CODE=%ERRORLEVEL%"
    call :COLOR_SCHEME
    echo %ERROR% Failed to configure cache directory via conda_far.bat. Aborting...
    goto :CLEANUP
)
call :COLOR_SCHEME
if not defined _CACHE (
    echo %ERROR% Failed to set _CACHE directory. Aborting...
    set "FINAL_EXIT_CODE=1"
    goto :CLEANUP
)
echo:

:: --------------------------------------------------------
:: Download Micromamba
:: --------------------------------------------------------
call :MICROMAMBA_DOWNLOAD
if not "%ERRORLEVEL%"=="0" (
    set "FINAL_EXIT_CODE=%ERRORLEVEL%"
    echo %ERROR% Failed to download/verify Micromamba. Aborting...
    goto :CLEANUP
)

:: --------------------------------------------------------
:: Download UV
:: --------------------------------------------------------
call :UV_DOWNLOAD
if not "%ERRORLEVEL%"=="0" (
    set "FINAL_EXIT_CODE=%ERRORLEVEL%"
    echo %ERROR% Failed to download/verify UV. Aborting...
    goto :CLEANUP
)

:: --------------------------------------------------------
:: Bootstrap new Python/Conda/Mamba/UV environment
:: --------------------------------------------------------
if defined YAML_BOOTSTRAP (
    call :BOOTSTRAP_ENV
) else (
    call :CPYTHON_DOWNLOAD
)
if not "%ERRORLEVEL%"=="0" (
    set "FINAL_EXIT_CODE=%ERRORLEVEL%"
    echo %ERROR% Failed to bootstrap Python/Conda/Mamba/UV environment. Aborting...
    goto :CLEANUP
)

:: --------------------------------------------------------
:: Activate new Python/Conda/Mamba/UV environment
:: --------------------------------------------------------
call :ACTIVATE_ENV
if not "%ERRORLEVEL%"=="0" (
    set "FINAL_EXIT_CODE=%ERRORLEVEL%"
    echo %ERROR% Failed to activate the new Python/Conda/Mamba/UV environment. Aborting...
    goto :CLEANUP
)
if defined _ARG_INIT (
    echo %INFO% Init-only flag supplied. Exiting...
    set "FINAL_EXIT_CODE=0"
    goto :CLEANUP
)

:: --------------------------------------------------------
:: Import main environment
:: --------------------------------------------------------
if defined YAML (
    call :IMPORT_MAIN_ENV
    if not "!ERRORLEVEL!"=="0" (
        set "FINAL_EXIT_CODE=!ERRORLEVEL!"
        echo %ERROR% Failed to import main environment. Aborting...
        goto :CLEANUP
    )
)

:: --------------------------------------------------------
:: Import pip environment
:: --------------------------------------------------------
call :IMPORT_PIP_ENV
if not "%ERRORLEVEL%"=="0" (
    set "FINAL_EXIT_CODE=%ERRORLEVEL%"
    echo %ERROR% Failed to import pip environment. Aborting...
    goto :CLEANUP
)

:: --------------------------------------------------------
:: Export full environment
:: --------------------------------------------------------
call :EXPORT_FULL_ENV
if not "%ERRORLEVEL%"=="0" (
    set "FINAL_EXIT_CODE=%ERRORLEVEL%"
    echo %ERROR% Failed to export full environment. Aborting...
    goto :CLEANUP
)

echo:
echo:                 ----- %DATE% %TIME% -----
echo ===========================================================================
echo ===========================================================================
echo == %OKOK%                                                   %OKOK% ==
echo == %OKOK%   Environment created and verified successfully.  %OKOK% ==
echo == %OKOK%                                                   %OKOK% ==
echo ===========================================================================
echo ===========================================================================
echo:

set "FINAL_EXIT_CODE=0"
goto :CLEANUP
:: ============================================================================
:: ============================================================================
:: ============================================================================


:: ============================================================================ PARSE_ARGS BEGIN
:: ============================================================================
:PARSE_ARGS

set "_ARGS="
if not "%~1"=="" set "_ARGS=TRUE"

set "_ARG_INIT="
set "_ARG_NOCOLOR="
set "_ARG_Q="

:PARSE_NEXT_ARG

set "__ARG1=%~1"
if "%__ARG1%"=="" goto :PARSE_ARGS_DONE
if "%__ARG1:~0,2%"=="--" (
    set "__ARG1=%__ARG1:~2%"
    goto :PARSE_ARG_TOKEN
)
if "%__ARG1:~0,1%"=="/" (
    set "__ARG1=%__ARG1:~1%"
    goto :PARSE_ARG_TOKEN
)
if "%__ARG1:~0,1%"=="-" (
    set "__ARG1=%__ARG1:~1%"
    goto :PARSE_ARG_TOKEN
)

:PARSE_ARG_TOKEN

if /I "%__ARG1%"=="q" (
    set "_ARG_Q=1"
    shift
    goto :PARSE_NEXT_ARG
)
if /I "%__ARG1%"=="init" (
    set "_ARG_INIT=1"
    shift
    goto :PARSE_NEXT_ARG
)
if /I "%__ARG1%"=="nocolor" (
    set "_ARG_NOCOLOR=1"
    shift
    goto :PARSE_NEXT_ARG
)

echo %WARN% Skipping unknown argument "%~1".
shift
goto :PARSE_NEXT_ARG

:PARSE_ARGS_DONE
set "__ARG1="
exit /b 0
:: ============================================================================
:: ============================================================================ PARSE_ARGS END


:: ============================================================================ CLEANUP BEGIN
:: ============================================================================
:CLEANUP

set "_ARG_INIT="
set "_ARG_NOCOLOR="
set "_ARG_Q="

if not defined FINAL_EXIT_CODE set "FINAL_EXIT_CODE=1"
exit /b %FINAL_EXIT_CODE%
:: ============================================================================
:: ============================================================================ CLEANUP END


:: ============================================================================ COLOR_SCHEME BEGIN
:: ============================================================================
:COLOR_SCHEME

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


:: ============================================================================ MICROMAMBA_DOWNLOAD BEGIN
:: ============================================================================
:MICROMAMBA_DOWNLOAD

echo %WARN% Micromamba
set "RELEASE_URL=https://github.com/mamba-org/micromamba-releases/releases/latest/download/micromamba-win-64"
set "MAMBA_EXE=%_CACHE%\micromamba\micromamba.exe"

if exist "%MAMBA_EXE%" (
    echo %INFO% Micromamba: Using cached "%MAMBA_EXE%"
    goto :MICROMAMBA_DOWNLOAD_SKIP
)

if not exist "%_CACHE%\micromamba" (
    mkdir "%_CACHE%\micromamba"
    if not "!ERRORLEVEL!"=="0" (
        echo %ERROR% Failed to create "%_CACHE%\micromamba". Aborting...
        exit /b 1
    )
)

echo %INFO% Micromamba: Downloading: %RELEASE_URL%
echo %INFO% Micromamba: Destination: "%MAMBA_EXE%"
curl.exe --fail --retry 3 --retry-delay 2 -L -o "%MAMBA_EXE%" "%RELEASE_URL%"
set "EXIT_STATUS=%ERRORLEVEL%"
if not "%EXIT_STATUS%"=="0" (
    echo %ERROR% Micromamba: Download failure. Aborting bootstrapping...
    exit /b %EXIT_STATUS%
)

set "RELEASE_URL="
if not exist "%MAMBA_EXE%" (
    echo %ERROR% Micromamba: File "%MAMBA_EXE%" missing after download. Aborting...
    exit /b 1
)

:MICROMAMBA_DOWNLOAD_SKIP

echo %INFO% Micromamba: Basic test of "%MAMBA_EXE%": Attempt to query Micromamba version.
"%MAMBA_EXE%" --version
set "EXIT_STATUS=%ERRORLEVEL%"
if not "%EXIT_STATUS%"=="0" (
    echo %ERROR% Failure to execute "%MAMBA_EXE%". ERRORLEVEL: "%EXIT_STATUS%". Aborting...
    exit /b %EXIT_STATUS%
)

echo %OKOK% Micromamba: Completed
echo:

exit /b 0
:: ============================================================================
:: ============================================================================ MICROMAMBA_DOWNLOAD END


:: ============================================================================ UV_DOWNLOAD BEGIN
:: ============================================================================
:UV_DOWNLOAD

echo %WARN% UV
set "RELEASE_URL=https://github.com/astral-sh/uv/releases/latest/download/uv-x86_64-pc-windows-msvc.zip"
set "UV_ZIP=%_CACHE%\uv\uv-x86_64-pc-windows-msvc.zip"
set "UV_EXE=%_CACHE%\uv\uv.exe"

if exist "%UV_EXE%" (
    echo %INFO% UV: Using cached "%UV_EXE%"
    goto :UV_CHECK
)

if exist "%UV_ZIP%" (
    echo %INFO% UV: Using cached "%UV_ZIP%"
    goto :UV_EXTRACT_ZIP
)

if not exist "%_CACHE%\uv" (
    mkdir "%_CACHE%\uv"
    if not "!ERRORLEVEL!"=="0" (
        echo %ERROR% Failed to create "%_CACHE%\uv". Aborting...
        exit /b 1
    )
)

echo %INFO% UV: Downloading: %RELEASE_URL%
echo %INFO% UV: Destination: "%UV_ZIP%"
curl.exe --fail --retry 3 --retry-delay 2 -L -o "%UV_ZIP%" "%RELEASE_URL%"
set "EXIT_STATUS=%ERRORLEVEL%"
if not "%EXIT_STATUS%"=="0" (
    echo %ERROR% UV: Download failure. Aborting bootstrapping...
    exit /b %EXIT_STATUS%
)

set "RELEASE_URL="
if not exist "%UV_ZIP%" (
    echo %ERROR% UV: File "%UV_ZIP%" missing after download. Aborting...
    exit /b 1
)

:UV_EXTRACT_ZIP

tar.exe -C "%_CACHE%\uv" -xf "%UV_ZIP%"
set "EXIT_STATUS=%ERRORLEVEL%"
if not "%EXIT_STATUS%"=="0" (
    echo %ERROR% UV: Release extraction failure. Aborting bootstrapping...
    exit /b %EXIT_STATUS%
)
set "UV_ZIP="

:UV_CHECK

echo %INFO% UV: Basic test of "%UV_EXE%": Attempt to query UV version.
"%UV_EXE%" --version
set "EXIT_STATUS=%ERRORLEVEL%"
if not "%EXIT_STATUS%"=="0" (
    echo %ERROR% Failure to execute "%UV_EXE%". ERRORLEVEL: "%EXIT_STATUS%". Aborting...
    exit /b %EXIT_STATUS%
)

echo %OKOK% UV: Completed
echo:

exit /b 0
:: ============================================================================
:: ============================================================================ UV_DOWNLOAD END


:: ============================================================================ CPYTHON_DOWNLOAD BEGIN
:: ============================================================================
:CPYTHON_DOWNLOAD

set "PYTHON_EXE=%_ENV_PREFIX%\python.exe"
if exist "%PYTHON_EXE%" (
    echo %ERROR% CPython: Found existing "%PYTHON_EXE%". Aborting...
    exit /b 1
)
set "PYTHON_EXE="

:: --------------------------------------------------------
:: Get Python Version from pyproject.toml
:: --------------------------------------------------------
set "PY_V_PREFIX="
for /f "usebackq tokens=1,2 delims== " %%I in ("%PYPROJECT%") do (
    if /I "%%~I"=="requires-python" (
        set "PY_V_PREFIX=%%~J"
        set "PY_V_PREFIX=!PY_V_PREFIX:"=!"
        set "PY_V_PREFIX=!PY_V_PREFIX:'=!"
        set "PY_V_PREFIX=!PY_V_PREFIX:~2!"
        goto :CPYTHON_PY_V_PREFIX_DONE
    )
)
echo %ERROR% Line matching requires-python = ">=3.10" not found in "%PYPROJECT%".
exit /b 1

:CPYTHON_PY_V_PREFIX_DONE

echo %WARN% CPython
if not defined PY_V_PREFIX (
    echo %ERROR% CPython: Parsed PY_V_PREFIX is empty in "%PYPROJECT%". Aborting...
    exit /b 1
)

if not exist "%_CACHE%\Python" (
    mkdir "%_CACHE%\Python"
    if not "!ERRORLEVEL!"=="0" (
        echo %ERROR% Failed to create "%_CACHE%\Python". Aborting...
        exit /b 1
    )
)

set "META_URL=https://api.nuget.org/v3-flatcontainer/python/index.json"
set "PY_JSON=%_CACHE%\Python\python.json"

if exist "%PY_JSON%" (
    echo %INFO% CPython: Using cached metadata "%PY_JSON%".
    goto :CPYTHON_PY_V
)

echo %INFO% CPython: Downloading metadata from %META_URL%
curl.exe --fail --retry 3 --retry-delay 2 -L -o "%PY_JSON%" "%META_URL%"
set "EXIT_STATUS=%ERRORLEVEL%"
if not "%EXIT_STATUS%"=="0" (
    echo %ERROR% Failed to download CPython metadata from %META_URL%. Aborting...
    exit /b %EXIT_STATUS%
)
set "META_URL="

:CPYTHON_PY_V

echo %INFO% CPython: Searching for CPython version with prefix "%PY_V_PREFIX%".
set "PY_V="
for /f "usebackq tokens=1" %%I in ("%PY_JSON%") do (
    set "ITEM=%%~I"
    set "ITEM=!ITEM:,=!"
    set "ITEM=!ITEM:"=!"
    if "!ITEM:-=!"=="!ITEM!" (
        set "ITEM=$!ITEM!"
        if not "!ITEM:$%PY_V_PREFIX%=!"=="!ITEM!" (
            set "PY_V=!ITEM:~1!"
        )
    )
)
set "ITEM="

if not defined PY_V (
    echo %ERROR% Failed to determine CPython version matching "%PY_V_PREFIX%". Aborting...
    exit /b 1
)

:CPYTHON_NUGET

set "RELEASE_URL=https://nuget.org/api/v2/package/python/%PY_V%"
set "NUPKG=%_CACHE%\Python\python.%PY_V%.nupkg"
if exist "%NUPKG%" (
    echo %INFO% CPython: Using cached "%NUPKG%".
    goto :CPYTHON_EXTRACT
)

echo %INFO% CPython: Downloading CPython %PY_V% from "%RELEASE_URL%".
curl.exe --fail --retry 3 --retry-delay 2 -L -o "%NUPKG%" "%RELEASE_URL%"
set "EXIT_STATUS=%ERRORLEVEL%"
if not "%EXIT_STATUS%"=="0" (
    echo %ERROR% Downloading CPython nupkg failed. Aborting...
    exit /b %EXIT_STATUS%
)

if not exist "%NUPKG%" (
    echo %ERROR% CPython nupkg "%NUPKG%" not found after download. Aborting...
    exit /b 1
)
set "RELEASE_URL="
set "PY_V="

:CPYTHON_EXTRACT

echo %INFO% CPython: Extracting "%NUPKG%".
if not exist "%_ENV_PREFIX%" (
    mkdir "%_ENV_PREFIX%"
    if not "!ERRORLEVEL!"=="0" (
        echo %ERROR% Failed to create "%_ENV_PREFIX%". Aborting...
        exit /b 1
    )
)
tar.exe -C "%_ENV_PREFIX%" -xf "%NUPKG%" "tools"
set "EXIT_STATUS=%ERRORLEVEL%"
if not "%EXIT_STATUS%"=="0" (
    echo %ERROR% CPython: Release extraction failure. Aborting bootstrapping...
    exit /b %EXIT_STATUS%
)
set "NUPKG="

move /Y "%_ENV_PREFIX%\tools" "%_ENV_PREFIX%\_" >nul
if not "%ERRORLEVEL%"=="0" (
    echo %ERROR% CPython: Failed to move extracted tools folder. Aborting...
    exit /b 1
)
robocopy.exe "%_ENV_PREFIX%\_" "%_ENV_PREFIX%" /MOVE /E /NFL /NDL >nul
if %ERRORLEVEL% GEQ 8 (
    echo %ERROR% CPython: robocopy failed with exit code %ERRORLEVEL%. Aborting...
    exit /b 1
)
if exist "%_ENV_PREFIX%\_" rmdir /S /Q "%_ENV_PREFIX%\_"

:CPYTHON_POSTINSTALL

for %%D in (
    "%_ENV_PREFIX%\bin"
    "%_ENV_PREFIX%\Library\bin"
    "%_ENV_PREFIX%\Scripts"
    "%_ENV_PREFIX%\condabin"
) do if not exist "%%~D" (
    mkdir "%%~D"
    if not "!ERRORLEVEL!"=="0" (
        echo %ERROR% CPython: Failed to create directory "%%~D". Aborting...
        exit /b 1
    )
)

(
    echo @echo off
    echo:
    echo pushd "%%~dp0.."
    echo set "PYTHON_HOME=%%CD%%"
    echo set "CONDA_PREFIX=%%CD%%"
    echo popd
    echo set "Path=%%PYTHON_HOME%%;%%PYTHON_HOME%%\Library\bin;%%PYTHON_HOME%%\Scripts;%%Path%%;%%PYTHON_HOME%%\bin"
    echo:
    echo echo ========== CPython activated ==========
    echo python.exe --version
    echo echo ---------------------------------------
    echo:
) > "%_ENV_PREFIX%\condabin\conda.bat"

copy /Y "%_ENV_PREFIX%\condabin\conda.bat" "%_ENV_PREFIX%\condabin\mamba.bat" >nul
if not "%ERRORLEVEL%"=="0" (
    echo %ERROR% CPython: Failed to create "%_ENV_PREFIX%\condabin\mamba.bat". Aborting...
    exit /b 1
)

echo:
"%_ENV_PREFIX%\python.exe" -m pip install --upgrade --force-reinstall %VERBOSE% pip pipx setuptools wheel uv
set "EXIT_STATUS=%ERRORLEVEL%"
if not "%EXIT_STATUS%"=="0" (
    echo %ERROR% CPython: Initial pip package upgrade failed. Aborting bootstrapping...
    exit /b %EXIT_STATUS%
)

echo:
echo %OKOK% CPython: Bootstrap completed.
echo:

exit /b 0
:: ============================================================================
:: ============================================================================ CPYTHON_DOWNLOAD END


:: ============================================================================ BOOTSTRAP_ENV BEGIN
:: ============================================================================
:BOOTSTRAP_ENV

echo:
echo:                 ----- %DATE% %TIME% -----
echo ====================================================================================
echo ====================================================================================
echo == %WARN%                                                            %WARN% ==
echo == %WARN%           Bootstrapping new Python environment             %WARN% ==
echo == %WARN%           Python/Conda/Mamba/UV                            %WARN% ==
echo == %WARN%                                                            %WARN% ==
echo ====================================================================================
echo ====================================================================================
echo:

if exist "%APPDATA%\mamba" (
    echo %WARN% Removing "%APPDATA%\mamba" because Micromamba can hang when it exists.
    if not defined _ARG_Q (
        echo %WARN% Press any key to continue...
        pause
    )
    rmdir /Q /S "%APPDATA%\mamba"
    set "EXIT_STATUS=!ERRORLEVEL!"
    if not "!EXIT_STATUS!"=="0" (
        echo %ERROR% Failed to delete "%APPDATA%\mamba". ERRORLEVEL: !EXIT_STATUS!. Aborting...
        exit /b !EXIT_STATUS!
    )
)

echo %WARN% Creating new Python environment...
echo %INFO% Using command:
echo %INFO% === "%MAMBA_EXE%" create %VERBOSE% --yes --no-rc --use-uv -f "%YAML_BOOTSTRAP%" --prefix "%_ENV_PREFIX%" %PKGS% ===
echo %INFO%
echo:
call "%MAMBA_EXE%" create %VERBOSE% --yes --no-rc --use-uv -f "%YAML_BOOTSTRAP%" --prefix "%_ENV_PREFIX%" %PKGS%
set "EXIT_STATUS=%ERRORLEVEL%"
if not "%EXIT_STATUS%"=="0" (
    echo %ERROR% Failed to create a new environment. ERRORLEVEL: %EXIT_STATUS%. Aborting...
    exit /b %EXIT_STATUS%
)

echo %OKOK% New environment "%_ENV_PREFIX%" is bootstrapped from "%YAML_BOOTSTRAP%".
exit /b 0
:: ============================================================================
:: ============================================================================ BOOTSTRAP_ENV END


:: ============================================================================ ACTIVATE_ENV BEGIN
:: ============================================================================
:ACTIVATE_ENV

echo:
echo:                 ----- %DATE% %TIME% -----
echo ====================================================================================
echo ====================================================================================
echo == %WARN%                                                            %WARN% ==
echo == %WARN%            Activate development environment                %WARN% ==
echo == %WARN%                                                            %WARN% ==
echo ====================================================================================
echo ====================================================================================
echo:

set "_CONDA_PREFIX=%_ENV_PREFIX%"
call "%~dp0conda_far.bat" /preactivate
set "EXIT_STATUS=%ERRORLEVEL%"
call :COLOR_SCHEME
if not "%EXIT_STATUS%"=="0" (
    echo %ERROR% Failed to activate environment "%_ENV_PREFIX%". Aborting...
    exit /b %EXIT_STATUS%
)
set "_CONDA_PREFIX="

if not exist "%CONDA_PREFIX%\python.exe" (
    echo %ERROR% Python not found in "%CONDA_PREFIX%". Aborting...
    exit /b 1
)
call "%CONDA_PREFIX%\python.exe" --version
set "EXIT_STATUS=%ERRORLEVEL%"
if not "%EXIT_STATUS%"=="0" (
    echo %ERROR% Failed to call Python in "%_ENV_PREFIX%". Aborting...
    exit /b %EXIT_STATUS%
)

echo %OKOK% New environment "%_ENV_PREFIX%" is activated.
exit /b 0
:: ============================================================================
:: ============================================================================ ACTIVATE_ENV END


:: ============================================================================ IMPORT_MAIN_ENV BEGIN
:: ============================================================================
:IMPORT_MAIN_ENV

echo:
echo:                 ----- %DATE% %TIME% -----
echo ====================================================================================
echo ====================================================================================
echo == %WARN%                                                            %WARN% ==
echo == %WARN%           Importing main Python environment                %WARN% ==
echo == %WARN%                                                            %WARN% ==
echo ====================================================================================
echo ====================================================================================
echo:
echo %INFO% YAML:   "%YAML%"
echo %INFO% PREFIX: "%CONDA_PREFIX%"
echo %INFO%

call "%MAMBA_BAT%" env update %VERBOSE% --yes --no-rc --use-uv -f "%YAML%" --prefix "%CONDA_PREFIX%"
set "EXIT_STATUS=%ERRORLEVEL%"
echo:
if not "%EXIT_STATUS%"=="0" (
    echo %ERROR% Failed to import main environment "%_ENV_PREFIX%". Aborting...
    exit /b %EXIT_STATUS%
)

echo %OKOK% Imported main environment "%YAML%" to "%_ENV_PREFIX%".
exit /b 0
:: ============================================================================
:: ============================================================================ IMPORT_MAIN_ENV END


:: ============================================================================ IMPORT_PIP_ENV BEGIN
:: ============================================================================
:IMPORT_PIP_ENV

echo:
echo:                 ----- %DATE% %TIME% -----
echo ====================================================================================
echo ====================================================================================
echo == %WARN%                                                            %WARN% ==
echo == %WARN%           Importing pip Python environment                 %WARN% ==
echo == %WARN%                                                            %WARN% ==
echo ====================================================================================
echo ====================================================================================
echo:
echo %INFO% PREFIX: "%CONDA_PREFIX%"
echo %INFO%

for %%F in ("%~dp0*.req.txt") do (
    echo %INFO% Importing "%%~F"
    pip.exe install %VERBOSE% -r "%%~F"
    set "EXIT_STATUS=!ERRORLEVEL!"
    if not "!EXIT_STATUS!"=="0" (
        echo %ERROR% Failed to import pip environment "pip.exe install %VERBOSE% -r "%%~F"". Aborting...
        exit /b !EXIT_STATUS!
    )
)

if defined PIP_REQ (
    echo %INFO% Environment: "%PIP_REQ%"
    uv.exe pip install --system %VERBOSE% -r "%PIP_REQ%"
    set "EXIT_STATUS=!ERRORLEVEL!"
    if not "!EXIT_STATUS!"=="0" (
        echo %ERROR% Failed to import pip environment "uv.exe pip install --system -r "%PIP_REQ%"". Aborting...
        exit /b !EXIT_STATUS!
    )
    echo %OKOK% Imported "%PIP_REQ%" to "%_ENV_PREFIX%".
)

if defined PIP_TXT (
    echo %INFO% Environment: "%PIP_TXT%"
    uv.exe pip install --system %VERBOSE% -r "%PIP_TXT%"
    set "EXIT_STATUS=!ERRORLEVEL!"
    if not "!EXIT_STATUS!"=="0" (
        echo %ERROR% Failed to import pip environment "uv.exe pip install --system -r "%PIP_TXT%"". Aborting...
        exit /b !EXIT_STATUS!
    )
    echo %OKOK% Imported "%PIP_TXT%" to "%_ENV_PREFIX%".
)

echo:
exit /b 0
:: ============================================================================
:: ============================================================================ IMPORT_PIP_ENV END


:: ============================================================================ EXPORT_FULL_ENV BEGIN
:: ============================================================================
:EXPORT_FULL_ENV

echo:
echo:                 ----- %DATE% %TIME% -----
echo ====================================================================================
echo ====================================================================================
echo == %WARN%                                                            %WARN% ==
echo == %WARN%           Exporting final full environment file            %WARN% ==
echo == %WARN%                                                            %WARN% ==
echo ====================================================================================
echo ====================================================================================
echo:

set "ENV_CONDA=%~dpn0_generated.yml"
if defined YAML_BOOTSTRAP (
    echo %INFO% Exporting final full Conda environment file to "%ENV_CONDA%".
    call "%CONDA_BAT%" env export --no-builds > "%ENV_CONDA%"
    set "EXIT_STATUS=!ERRORLEVEL!"
    if not "!EXIT_STATUS!"=="0" (
        echo %ERROR% Failed to export Conda environment file. Aborting...
        exit /b !EXIT_STATUS!
    )
)

set "ENV_UV=%~dpn0.pip.txt"
echo %INFO% Exporting final pip package list to "%ENV_UV%".
call uv.exe pip list > "%ENV_UV%"
set "EXIT_STATUS=%ERRORLEVEL%"
if not "%EXIT_STATUS%"=="0" (
    echo %ERROR% Failed to export pip environment. Aborting...
    exit /b %EXIT_STATUS%
)

echo:
echo %OKOK% Exported full environment to "%ENV_CONDA%" and "%ENV_UV%".
echo:
set "ENV_CONDA="
set "ENV_UV="
exit /b 0
:: ============================================================================
:: ============================================================================ EXPORT_FULL_ENV END


:: ============================================================================ PREREQUISITES BEGIN
:: ============================================================================
:PREREQUISITES

echo:                     ----- %DATE% %TIME% -----
echo ====================================================================================
echo ====================================================================================
echo == %WARN%                                                            %WARN% ==
echo == %WARN% PREREQS: Checking prerequisites.                           %WARN% ==
echo == %WARN% PREREQS: Inspect results and make sure that all tests are  %WARN% ==
echo == %WARN%          OK and no ERRORs reported before continuing.      %WARN% ==
echo == %WARN%                                                            %WARN% ==
echo ====================================================================================
echo ====================================================================================
echo:

:: --------------------------------------------------------
:: NVIDIA GPU Driver Information
:: --------------------------------------------------------
echo %WARN% PREREQS - NVIDIA GPU

where.exe /q nvidia-smi.exe
if "%ERRORLEVEL%"=="0" (
    call nvidia-smi.exe
    set "EXIT_STATUS=!ERRORLEVEL!"
) else (
    set "EXIT_STATUS=-1"
)

if "%EXIT_STATUS%"=="0" (
    echo %OKOK% PREREQS - NVIDIA GPU: See GPU driver information above.
) else (
    if "%EXIT_STATUS%"=="-1" (
        echo %WARN% PREREQS - NVIDIA GPU: nvidia-smi.exe not found. Continuing without NVIDIA GPU...
    ) else (
        echo %WARN% PREREQS - NVIDIA GPU: Failed to query nvidia-smi.exe. Continuing...
    )
)
echo:

:: --------------------------------------------------------
:: Required scripts
:: --------------------------------------------------------
echo %WARN% PREREQS - Scripts

if exist "%~dp0conda_far.bat" (
    echo %OKOK% PREREQS - Scripts: Conda wrapper script found: "%~dp0conda_far.bat".
) else (
    echo %ERROR% PREREQS - Scripts: Conda wrapper script not found: "%~dp0conda_far.bat". Aborting...
    exit /b 1
)
echo:

call :COLOR_SCHEME
echo:

:: --------------------------------------------------------
:: curl and tar
:: --------------------------------------------------------
echo %WARN% PREREQS - Standard Tools

where.exe /q curl.exe
if "%ERRORLEVEL%"=="0" (
    echo %OKOK% PREREQS - Standard Tools: curl.exe is ok.
) else (
    echo %ERROR% PREREQS - Standard Tools: curl.exe is not found. Aborting...
    exit /b 1
)

where.exe /q tar.exe
if "%ERRORLEVEL%"=="0" (
    echo %OKOK% PREREQS - Standard Tools: tar.exe is ok.
) else (
    echo %ERROR% PREREQS - Standard Tools: tar.exe is not found. Aborting...
    exit /b 1
)
echo:

exit /b 0
:: ============================================================================
:: ============================================================================ PREREQUISITES END
