@echo off


echo :========== ========== ========== ========== ==========:
echo  Bootstrapping Micromamba
echo :---------- ---------- ---------- ---------- ----------:


:: --------------------------------------------------------
:: BASE CONFIG
:: --------------------------------------------------------
set "YAML=%~n0"
set "YAML=%YAML:_yml=_generated%.yml"
set "_ENV_PREFIX=%~dpn0"
set "_ENV_PREFIX=%_ENV_PREFIX:~0,-4%"

echo [INFO] Using prefix "%_ENV_PREFIX%".


:: --------------------------------------------------------
:: Determine cache directory
:: --------------------------------------------------------
if exist "%~d0\CACHE" (
  set "_CACHE=%~d0\CACHE"
  echo [INFO] Using "!_CACHE!" cache directory.
) else (
  if exist "%~dp0CACHE" (
    set "_CACHE=%~dp0CACHE"
    echo [INFO] Using "!_CACHE!" cache directory.
  ) else (
    set "_CACHE=%TEMP%"
    echo [INFO] Cache directory "!_CACHE!" does not exist. Will use TEMP instead.
  )
)

set "MAMBA_BAT=%_ENV_PREFIX%\condabin\mamba.bat"
set "CONDA_BAT=%_ENV_PREFIX%\condabin\conda.bat"
if not exist "%MAMBA_BAT%" (
  echo [ERROR] Mamba "%MAMBA_BAT%" not found.
  exit /b 1
)

if exist "%APPDATA%\mamba" (
  echo [WARN] Warning: I am about to delete "%APPDATA%\mamba". Press any key to continue.
  pause
  rmdir /Q /S "%APPDATA%\mamba"
)

rem "%MAMBA_BAT%" env export --yes --no-md5 --no-build --offline --from-history --prefix "%_ENV_PREFIX%" >"%YAML%"
rem "%MAMBA_BAT%" env export --yes --no-md5 --no-build --offline --prefix "%_ENV_PREFIX%" >"%YAML%"
call "%CONDA_BAT%" activate
call "%CONDA_BAT%" env export --no-builds > "%YAML%"

