@echo off
setlocal EnableDelayedExpansion EnableExtensions

:: ============================================================================
::  Purpose:
::    Bootstraps a fully functional Conda/Micromamba-based Python environment.
::
::  Core YAML files:
::      - <script>_bootstrap.yml   - minimal bootstrap environment
::                                   Python/Conda/Mamba/UV
::      - pyproject.toml           - only Python version is used
::      - requirements.txt         - pip-only environemnt
::      - <script>.txt             - pip-only environemnt
::      - <script>.yml             - main environment definition (optional)
::      - <script>_generated.yml   - generated full final resolved environment
::
::  Notes:
::      At least one of <script>_bootstrap.yml or pyproject.toml must be
::      provided.
::
::      pyproject.toml only is provided:
::          pyproject.toml must contain (only if alone)
::              requires-python = ">=3.10"
::          WARNING: Parsing is basic:
::              - spaces around "=" are mandatory;
::              - version format "==3.10" (two char prefix is mandatory,
::                will install the latest matching version; prefix is not
::                analyzed - "<3.10" will fail).
::          Attempting to bootstrap CPython from a nupkg, no conda.
::          In this case, a "dummy" conda.bat is created to be called by 
::          conda_far.bat when activating this environment resulting in 
::          a minimalistic activation (PATH and PYTHON_HOME).
::
::  Exit Codes:
::      0  - Success
::      1+ - Failure during environment or dependency setup
::
::  Related Scripts:
::      conda_far.bat   – Initializes and activates full Conda environment.
:: ============================================================================

echo :========== ========== ========== ========== ==========:
echo  Bootstrapping Python Environment
echo :---------- ---------- ---------- ---------- ----------:
rem           ----- Mon 10/20/2025 21:03:09.88 -----
echo:         ----- %DATE% %TIME% -----
echo: CLI: "%~f0" %*
echo:

:: --- Parse arguments and preserve top-level context ---

call :PARSE_ARGS %*

:: --- Escape sequence templates for color coded console output ---

call :COLOR_SCHEME

:: --- Determine base components of environment path and check for existing Python ---

set "_ENV_PREFIX=%~dpn0"
if exist "%_ENV_PREFIX%\python.exe" (
  echo %WARN% Found existing "%_ENV_PREFIX%\python.exe". Skip bootstrapping...
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
set "YAML_BOOTSTRAP=%~dpn0_bootstrap.yml"
if not exist "%YAML_BOOTSTRAP%" (
  if exist "%YAML_PIP%" (
    echo %WARN% Conda bootstrap file "%YAML_BOOTSTRAP%" not found . Attempting boostrapping CPython nupkg.
    set "YAML_BOOTSTRAP="
  ) else (
    echo %ERROR% Bootstrap environment files "%YAML_BOOTSTRAP%" or "%YAML_PIP%" not found. Aborting...
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

set "PYPROJECT=%~dp0pyproject.toml"
if not exist "%PYPROJECT%" (
  echo %WARN% "%PYPROJECT%" not found. Skipping...
  set "PYPROJECT="
) else (
  echo %INFO% Using environment file "%PYPROJECT%".
)

if not defined YAML if not defined PYPROJECT (
  set "FINAL_EXIT_CODE=1"
  echo %ERROR% Neither Conda environment nor pyproject.toml found.
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
:: Determine cache directory
:: --------------------------------------------------------
if not defined _CACHE (
  call :CACHE_DIR
  set "EXIT_STATUS=!ERRORLEVEL!"
) else (
  set "EXIT_STATUS=0"
)
if not defined _CACHE (
  echo %ERROR% Failed to set CACHE directory. Aborting...
  set "FINAL_EXIT_CODE=1"
  goto :CLEANUP
)
echo:
pause

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
  call :BOOTSRTAP_ENV
) else (
  call :CPYTHON_DOWNLOAD
)
if not "%ERRORLEVEL%"=="0" (
  set "FINAL_EXIT_CODE=%ERRORLEVEL%"
  echo %ERROR% Failed to bootsrap Python/Conda/Mamba/UV environment. Aborting...
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
if not "!ERRORLEVEL!"=="0" (
  set "FINAL_EXIT_CODE=!ERRORLEVEL!"
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
rem                   ----- Mon 10/20/2025 21:03:09.88 -----
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
:: --- Parse arguments ---
:: Because "shift" destroys %0, original context is preserved by destroying this.

:: --- Parsing arguments ---

:PARSE_ARGS

if not "%~1"=="" (
  set "_ARGS=TRUE"
) else (
  set "_ARGS="
  goto :PARSE_ARGS_DONE
)

set "_ARG_INIT="
set "_ARG_NOCOLOR="
set "_ARG_Q="

:PARSE_NEXT_ARG

if /I "%~1"=="" goto :PARSE_ARGS_DONE
if /I "%~1"=="/q"         set "_ARG_Q=1"
if /I "%~1"=="/init"      set "_ARG_INIT=1"
if /I "%~1"=="/nocolor"   set "_ARG_NOCOLOR=1"
shift
goto :PARSE_NEXT_ARG

:PARSE_ARGS_DONE
exit /b 0
:: ============================================================================ 
:: ============================================================================ PARSE_ARGS END


:: ============================================================================ CLEANUP BEGIN
:: ============================================================================
:: --- Clean up; prefer as the primary script exit point ---
:: To exit script, set FINAL_EXIT_CODE and goto CLEANUP
:CLEANUP

set "_ARG_INIT="
set "_ARG_NOCOLOR="
set "_ARG_Q="

:: --- Ensure a valid exit code is always returned ---

if not defined FINAL_EXIT_CODE set "FINAL_EXIT_CODE=1"
exit /b %FINAL_EXIT_CODE%
:: ============================================================================ 
:: ============================================================================ CLEANUP END


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


:: ============================================================================ CACHE_DIR BEGIN
:: ============================================================================
:CACHE_DIR
:: --------------------------------------------------------
:: Temp directory
:: --------------------------------------------------------
echo:
if exist "%~d0\Temp" (
  set "TEMP=%~d0\Temp"
  set "TMP=%~d0\Temp"
  echo %INFO% TEMP: "!TEMP!"
  echo %INFO% TMP:  "!TMP!"
)

:: --------------------------------------------------------
:: Determine cache directory
:: --------------------------------------------------------
if exist "%_CACHE%" (
  goto :CACHE_DIR_SET
)

if exist "%~d0\Downloads" (
  set "_CACHE=%~d0\Downloads"
) else (
  set "_CACHE=%USERPROFILE%\Downloads"
)

if exist "%_CACHE%\CACHE" (
  set "_CACHE=%_CACHE%\CACHE"
  goto :CACHE_DIR_SET
)

if exist "%~d0\CACHE" (
  set "_CACHE=%~d0\CACHE"
  goto :CACHE_DIR_SET
)

:CACHE_DIR_SET
:: --------------------------------------------------------
:: Verify file system access
:: --------------------------------------------------------
set "_DUMMY=%_CACHE%\$$$_DELETEME_ACCESS_CHECK_$$$"
if exist "%_DUMMY%" (cmd /c rmdir /Q /S "%_DUMMY%")
set "EXIT_STATUS=%ERRORLEVEL%"
if exist "%_DUMMY%" (set "EXIT_STATUS=1")
if not "%EXIT_STATUS%"=="0" (
  echo %ERROR% Failed to delete test directory "%_DUMMY%".
  echo %ERROR% Expected a full-access at this location "%_CACHE%".
  echo %ERROR% Aborting...
  set "_CACHE="
  exit /b %EXIT_STATUS%
)

md "%_DUMMY%"
set "EXIT_STATUS=%ERRORLEVEL%"
if not exist "%_DUMMY%" (set "EXIT_STATUS=1")
if not "%EXIT_STATUS%"=="0" (
  echo %ERROR% Failed to create test directory "%_DUMMY%".
  echo %ERROR% Expected a full-access at this location "%_CACHE%".
  echo %ERROR% Aborting...
  set "_CACHE="
  exit /b %EXIT_STATUS%
)

:: --------------------------------------------------------
:: CONDA_PKGS_DIRS
:: --------------------------------------------------------
set "_PKGS_DIR=%_CACHE%\Python\pkgs"

if not defined CONDA_PKGS_DIRS (
  set "CONDA_PKGS_DIRS=%_PKGS_DIR%"
) else (
  set "_PKGS_DIR=%CONDA_PKGS_DIRS%"
)
if not exist "%CONDA_PKGS_DIRS%" md "%CONDA_PKGS_DIRS%"
if not "%ERRORLEVEL%"=="0" (
  echo %ERROR% Failed to create directory "%CONDA_PKGS_DIRS%".
  set "_CACHE="
  exit /b %EXIT_STATUS%
)

:: --------------------------------------------------------
:: PIP_CACHE_DIR and UV_CACHE_DIR
:: --------------------------------------------------------
set "PIP_CACHE_DIR=%_CACHE%\Python\pip\cache"
set "UV_CACHE_DIR=%_CACHE%\Python\uv\cache"
if not exist "%PIP_CACHE_DIR%" (cmd /c mkdir "%PIP_CACHE_DIR%")
if not exist "%UV_CACHE_DIR%"  (cmd /c mkdir "%UV_CACHE_DIR%")

echo %INFO% CACHE           directory: "%_CACHE%".
echo %INFO% CONDA_PKGS_DIRS directory: "%CONDA_PKGS_DIRS%".
echo %INFO% PIP_CACHE_DIR   directory: "%PIP_CACHE_DIR%".
echo %INFO% UV_CACHE_DIR    directory: "%UV_CACHE_DIR%".

set "SRC=%PIP_CACHE_DIR%"
set "DST=%LOCALAPPDATA%\pip"
if exist "%DST%" (cmd /c rmdir /S /Q "%DST%")
mkdir "%DST%"
mklink /j "%DST%\cache" "%SRC%" && (
  echo %INFO% Profile pip cache dir is linked: "%DST%\cache".
)

set "SRC=%UV_CACHE_DIR%"
set "DST=%LOCALAPPDATA%\uv"
if exist "%DST%" (cmd /c rmdir /S /Q "%DST%")
mkdir "%DST%"
mklink /j "%DST%\cache" "%SRC%" && (
  echo %INFO% Profile uv cache dir is linked: "%DST%\cache".
)

:: --------------------------------------------------------
:: Git
:: --------------------------------------------------------

set "GIT_CACHE=H:\GitHub"
if not exist "%GIT_CACHE%" (
  set "GIT_CACHE=%~d0\GitHub"
)
if not exist "%GIT_CACHE%" (
  set "GIT_CACHE=%_CACHE%\GitHub"
)
if not exist "%GIT_CACHE%" (mkdir "%GIT_CACHE%")
echo %INFO% GIT_CACHE                directory: "%GIT_CACHE%".

:: --------------------------------------------------------
:: Node, npm, pnpm, Electron, etc.
:: --------------------------------------------------------
set "NPM_CONFIG_CACHE=%_CACHE%\npm"
if not exist "%NPM_CONFIG_CACHE%" (mkdir "%NPM_CONFIG_CACHE%")
echo %INFO% NPM_CONFIG_CACHE         directory: "%NPM_CONFIG_CACHE%".

set "ELECTRON_CACHE=%_CACHE%\electron"
if not exist "%ELECTRON_CACHE%" (mkdir "%ELECTRON_CACHE%")
echo %INFO% ELECTRON_CACHE           directory: "%ELECTRON_CACHE%".

set "ELECTRON_BUILDER_CACHE=%_CACHE%\electron-builder"
if not exist "%ELECTRON_BUILDER_CACHE%" (mkdir "%ELECTRON_BUILDER_CACHE%")
echo %INFO% ELECTRON_BUILDER_CACHE   directory: "%ELECTRON_BUILDER_CACHE%".

set "PLAYWRIGHT_BROWSERS_PATH=%_CACHE%\playwright"
if not exist "%PLAYWRIGHT_BROWSERS_PATH%" (mkdir "%PLAYWRIGHT_BROWSERS_PATH%")
echo %INFO% PLAYWRIGHT_BROWSERS_PATH directory: "%PLAYWRIGHT_BROWSERS_PATH%".

set "PNPM_HOME=%_CACHE%\pnpm"
if not exist "%PNPM_HOME%" (mkdir "%PNPM_HOME%")
echo %INFO% PNPM_HOME                directory: "%PNPM_HOME%".

set "XDG_CACHE_HOME=%_CACHE%\pnpm-cache"
if not exist "%XDG_CACHE_HOME%" (mkdir "%XDG_CACHE_HOME%")
echo %INFO% XDG_CACHE_HOME           directory: "%XDG_CACHE_HOME%".

exit /b 0
:: ============================================================================
:: ============================================================================ CACHE_DIR END


:: ============================================================================ MICROMAMBA_DOWNLOAD BEGIN
:: ============================================================================
:MICROMAMBA_DOWNLOAD

:: --------------------------------------------------------
:: Download Micromamba
:: --------------------------------------------------------
echo %WARN% Micromamba
set "RELEASE_URL=https://github.com/mamba-org/micromamba-releases/releases/latest/download/micromamba-win-64"
set "MAMBA_EXE=%_CACHE%\micromamba\micromamba.exe"

if exist "%MAMBA_EXE%" (
  echo %INFO% Micromamba: Using cached "%MAMBA_EXE%"
  goto :MICROMAMBA_DOWNLOAD_SKIP
) 

if not exist "%_CACHE%\micromamba" md "%_CACHE%\micromamba"
set "EXIT_STATUS=%ERRORLEVEL%"
if not "%EXIT_STATUS%"=="0" (
  echo %ERROR% Creating "%_CACHE%\micromamba". Aborting...
  exit /b %EXIT_STATUS%
)

echo %INFO% Micromamba: Downloading: %RELEASE_URL%
echo %INFO% Micromamba: Destination: %MAMBA_EXE%
curl --fail --retry 3 --retry-delay 2 -L -o "%MAMBA_EXE%" "%RELEASE_URL%"
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

:: --------------------------------------------------------
:: Download UV
:: --------------------------------------------------------
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

if not exist "%_CACHE%\uv" (md "%_CACHE%\uv")
set "EXIT_STATUS=%ERRORLEVEL%"
if not "%EXIT_STATUS%"=="0" (
  echo %ERROR% Creating "%_CACHE%\uv". Aborting...
  exit /b %EXIT_STATUS%
)

echo %INFO% UV: Downloading: %RELEASE_URL%
echo %INFO% UV: Destination: "%UV_ZIP%"
curl --fail --retry 3 --retry-delay 2 -L -o "%UV_ZIP%" "%RELEASE_URL%"
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

tar -C "%_CACHE%\uv" -xf "%UV_ZIP%"
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

:: --------------------------------------------------------
:: Check Python Version
:: --------------------------------------------------------
set "PYTHON_EXE=%_ENV_PREFIX%\python.exe"
if exist "%PYTHON_EXE%" (
  echo %ERROR% CPython: Found "%PYTHON_EXE%". Aborting...
  exit /b 1
)
set "PYTHON_EXE="

:: --------------------------------------------------------
:: Get Python Version
:: --------------------------------------------------------
:: pyproject.toml must contain (only if alone)
::     requires-python = ">=3.10"
:: WARNING: Parsing is basic:
::     - spaces around "=" are mandatory;
::     - version format "==3.10" (two char prefix is mandatory,
::       will install the latest matching version; prefix is not
::       analyzed - "<3.10" will fail)).

set "PY_V_PREFIX="
for /f "usebackq tokens=1,3 delim=, " %%I in ("%PYPROJECT%") do (
  set "TOK1=%%~I"
  if "!TOK1:~0,15!"=="requires-python" (
    set "PY_V_PREFIX=%%~J"
    set "PY_V_PREFIX=!PY_V_PREFIX:~2!"
    goto :CPYTHON_PY_V_PREFIX_DONE
  )
)
echo %ERROR% Line like {requires-python = "==3.10"} not found in "%PYPROJECT%".
exit /b 1

:CPYTHON_PY_V_PREFIX_DONE

:: --------------------------------------------------------
:: Download CPython
:: --------------------------------------------------------
echo %WARN% CPython

if not defined PY_V_PREFIX (
  echo %INFO% CPython: PY_V_PREFIX is not defined. Using the latest stable version.
  goto :CPYTHON_NUGET
)

set "META_URL=https://api.nuget.org/v3-flatcontainer/python/index.json"
set "PY_JSON=%_CACHE%\Python\python.json"

if exist "%PY_JSON%" (
  echo %INFO% CPython: Using cached metadata.
  goto :CPYTHON_PY_V
)

echo %INFO% CPython: Donwloading metadata from %META_URL%
curl --fail --retry 3 --retry-delay 2 -L -o "%PY_JSON%" "%META_URL%"
set "EXIT_STATUS=%ERRORLEVEL%"
if not "%EXIT_STATUS%"=="0" (
  echo %ERROR% Downloading CPython meta from %META_URL%. Aborting...
  exit /b %EXIT_STATUS%
)
set "META_URL="

:CPYTHON_PY_V

echo %INFO% CPython: Searching for CPython version with prefix "%PY_V_PREFIX%".
for /f "usebackq tokens=1" %%I in ("%PY_JSON%") do (
  set "ITEM=%%I"
  set "ITEM=$!ITEM:~1,-2!"
  if not "!ITEM:$%PY_V_PREFIX%=!"=="!ITEM!" (set "PY_V=!ITEM!")
)
set "PY_V=%PY_V:~1%"
set "ITEM="

if not defined PY_V (
  echo %ERROR% Failed to determine CPython version. Aborting...
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
curl --fail --retry 3 --retry-delay 2 -L -o "%NUPKG%" "%RELEASE_URL%"
set "EXIT_STATUS=%ERRORLEVEL%"
if not "%EXIT_STATUS%"=="0" (
  echo %ERROR% Downloading CPython nupkg failed. Aborting...
  exit /b %EXIT_STATUS%
)

if not exist "%NUPKG%" (
  echo %ERROR% Downloading CPython nupkg failed. Aborting...
  exit /b %EXIT_STATUS%
)
set "RELEASE_URL="
set "PY_V="

:CPYTHON_EXTRACT

echo %INFO% CPython: Extracting "%NUPKG%".
if not exist "%_ENV_PREFIX%" (mkdir "%_ENV_PREFIX%")
tar -C "%_ENV_PREFIX%" -xf "%NUPKG%" "tools"
set "EXIT_STATUS=%ERRORLEVEL%"
if not "%EXIT_STATUS%"=="0" (
  echo %ERROR% CPython: Release extraction failure. Aborting bootstrapping...
  exit /b %EXIT_STATUS%
)
set "NUPKG="

move "%_ENV_PREFIX%\tools" "%_ENV_PREFIX%\_"
robocopy "%_ENV_PREFIX%\_" "%_ENV_PREFIX%" /MOVE /E /NFL /NDL

:CPYTHON_POSTINSTALL

if not exist "%_ENV_PREFIX%\bin" (cmd /c mkdir "%_ENV_PREFIX%\bin")
if not exist "%_ENV_PREFIX%\Library\bin" (cmd /c mkdir "%_ENV_PREFIX%\Library\bin")
if not exist "%_ENV_PREFIX%\Scripts" (cmd /c mkdir "%_ENV_PREFIX%\Scripts")
if not exist "%_ENV_PREFIX%\condabin" (cmd /c mkdir "%_ENV_PREFIX%\condabin")
(
  echo @echo off
  echo:
  echo cd /d "%%~dp0.."
  echo:
  echo set "PYTHON_HOME=%%CD%%"
  echo set "Path=%%PYTHON_HOME%%;%%PYTHON_HOME%%\Library\bin;%%PYTHON_HOME%%\Scripts;%%Path%%;%%PYTHON_HOME%%\bin"
  echo:
  echo echo ========== CPython activated ==========
  echo python --version
  echo echo ---------------------------------------
  echo:

) >> "%_ENV_PREFIX%\condabin\conda.bat"
copy /Y "%_ENV_PREFIX%\condabin\conda.bat" "%_ENV_PREFIX%\condabin\mamba.bat"

echo:
rem call "%_ENV_PREFIX%\condabin\conda.bat"
echo:

cd /d "%_ENV_PREFIX%"
set "PYTHON_HOME=%CD%"
python -m pip install --upgrade --force-reinstall %VERBOSE% pip pipx setuptools wheel uv
set "EXIT_STATUS=%ERRORLEVEL%"
if not "%EXIT_STATUS%"=="0" (
  echo %ERROR% CPython: Python activation failure. Aborting bootstrapping...
  exit /b %EXIT_STATUS%
)
cd /d "%~dp0"
set "PYTHON_HOME="

echo:
echo %OKOK% CPython: Bootstrap completed.
echo:

exit /b 0
:: ============================================================================
:: ============================================================================ CPYTHON_DOWNLOAD END


:: ============================================================================ BOOTSRTAP_ENV BEGIN
:: ============================================================================
:BOOTSRTAP_ENV

:: --------------------------------------------------------
:: Bootstrap new Python/Conda/Mamba/UV environment
:: --------------------------------------------------------
echo:
rem                   ----- Mon 10/20/2025 21:03:09.88 -----
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
rem set "PKGS=mamba conda uv %_PYTHON_PKG%"

if exist "%APPDATA%\mamba" (
  echo %WARN% Warning: I am about to delete "%APPDATA%\mamba". Press any key to continue.
  echo %WARN% Somehow, Micromamba tends to hang when this directory exists.
  pause
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
:: ============================================================================ BOOTSRTAP_ENV END


:: ============================================================================ ACTIVATE_ENV BEGIN
:: ============================================================================
:ACTIVATE_ENV

echo:
rem                   ----- Mon 10/20/2025 21:03:09.88 -----
echo:                 ----- %DATE% %TIME% -----
echo ====================================================================================
echo ====================================================================================
echo == %WARN%                                                            %WARN% ==
echo == %WARN%            Activate development environment.               %WARN% ==
echo == %WARN%                                                            %WARN% ==
echo ====================================================================================
echo ====================================================================================
echo:

set "_CONDA_PREFIX=%_ENV_PREFIX%"
call "%~dp0conda_far.bat" /preactivate
set "EXIT_STATUS=%ERRORLEVEL%"
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
call :COLOR_SCHEME

echo %OKOK% New environment "%_ENV_PREFIX%" is activated.
exit /b 0
:: ============================================================================
:: ============================================================================ ACTIVATE_ENV END


:: ============================================================================ IMPORT_MAIN_ENV BEGIN
:: ============================================================================
:IMPORT_MAIN_ENV
:: --------------------------------------------------------
:: Import main environment
:: --------------------------------------------------------
echo:
rem                   ----- Mon 10/20/2025 21:03:09.88 -----
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
:: --------------------------------------------------------
:: Import pip environment
:: --------------------------------------------------------
echo:
rem                   ----- Mon 10/20/2025 21:03:09.88 -----
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

:: --------------------------------------------------------
:: Import custom pip environments
:: --------------------------------------------------------
for %%F in ("%~dp0*.req.txt") do (
  echo %INFO% Importing "%%~F"
  pip install %VERBOSE% -r "%%~F"
  set "EXIT_STATUS=!ERRORLEVEL!"
  if not "!EXIT_STATUS!"=="0" (
    echo %ERROR% Failed to import pip environment "pip install %VERBOSE% -r "%%~F"". Aborting...
    exit /b !EXIT_STATUS!
  )
)

if defined PIP_REQ (
  echo %INFO% Environment: "%PIP_REQ%"
  uv pip install --system %VERBOSE% -r "%PIP_REQ%"
  set "EXIT_STATUS=!ERRORLEVEL!"
  if not "!EXIT_STATUS!"=="0" (
    echo %ERROR% Failed to import pip environment "uv pip install --system -r "%PIP_REQ%"". Aborting...
    exit /b !EXIT_STATUS!
  )
  echo %OKOK% Imported "%PIP_REQ%" to "%_ENV_PREFIX%".
)

if defined PIP_TXT (
  echo %INFO% Environment: "%PIP_TXT%"
  uv pip install --system %VERBOSE% -r "%PIP_TXT%"
  set "EXIT_STATUS=!ERRORLEVEL!"
  if not "!EXIT_STATUS!"=="0" (
    echo %ERROR% Failed to import pip environment "uv pip install --system -r "%PIP_TXT%"". Aborting...
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
rem                   ----- Mon 10/20/2025 21:03:09.88 -----
echo:                 ----- %DATE% %TIME% -----
echo ====================================================================================
echo ====================================================================================
echo == %WARN%                                                            %WARN% ==
echo == %WARN%           Exporting final full environment file            %WARN% ==
echo == %WARN%                                                            %WARN% ==
echo ====================================================================================
echo ====================================================================================
echo:

set "ENV_CONDA=%YAML:.yml=_generated.yml%"
echo %INFO% Exporting final full environment file to "%ENV_CONDA%".
call "%CONDA_BAT%" env export --no-builds > "%ENV_CONDA%"
set "EXIT_STATUS=%ERRORLEVEL%"
if not "%EXIT_STATUS%"=="0" (
  echo %ERROR% Failed to export environment file. Aborting...
  exit /b %EXIT_STATUS%
)

set "ENV_UV=%YAML:.yml=.pip.zxt%"
call uv pip list > "%ENV_UV%"
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
:: --------------------------------------------------------
:: CHECK Prerequisites
:: --------------------------------------------------------
:PREREQUISITES

rem                       ----- Mon 10/20/2025 21:03:09.88 -----
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
:: NVidia GPU Driver Information
:: --------------------------------------------------------
echo %WARN% PREREQS - NVIDIA GPU

where nvidia-smi.exe 1>nul 2>&1
set "EXIT_STATUS=%ERRORLEVEL%"
if "%EXIT_STATUS%"=="0" (
  call nvidia-smi.exe
  set "EXIT_STATUS=!ERRORLEVEL!"
) else (
  set "EXIT_STATUS=-1"
)

if "!EXIT_STATUS!"=="0" (
  echo %OKOK% PREREQS - NVIDIA GPU: See GPU driver information above.
) else (
  if "!EXIT_STATUS!"=="-1" (
    echo %ERROR% PREREQS - NVIDIA GPU: nvidia-smi.exe not found. Check NVidia driver installation and environment.
  ) else (
    echo %ERROR% PREREQS - NVIDIA GPU: Failed to obtain NVidia driver information via nvidia-smi.exe.
  )
)
echo:

:: --------------------------------------------------------
:: Required scripts
:: --------------------------------------------------------
echo %WARN% PREREQS - Scripts

:: --- conda_far.bat ---

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

where curl.exe 1>nul 2>&1
if "%ERRORLEVEL%"=="0" (
  echo %OKOK% PREREQS - Standard Tools: curl is ok.
) else (
  echo %ERROR% PREREQS - Standard Tools: curl is not found.
  exit /b 1
)

where tar.exe 1>nul 2>&1
if "%ERRORLEVEL%"=="0" (
  echo %OKOK% PREREQS - Standard Tools: tar is ok.
) else (
  echo %ERROR% PREREQS - Standard Tools: tar is not found.
  exit /b 1
)
echo:

exit /b 0
:: ============================================================================ 
:: ============================================================================ PREREQUISITES END
