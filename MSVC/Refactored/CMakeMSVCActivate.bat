@echo off
::
:: Check if CMake is in Path. If not, check default MSVC location. If found, add
:: to Path, else return an error.
::
:: SHELL: MSVC Build Tools
::
call :CHECKTOOL cmake 1>nul
set ResultCode=%ErrorLevel%
if %ResultCode% NEQ 0 (
  set CMAKE_MSVC_PATH=%VCIDEInstallDir:~0,-4%\CommonExtensions\Microsoft\CMake\CMake\bin
  call :CHECKTOOL cmake "!CMAKE_MSVC_PATH!" 1>nul
)
set ResultCode=%ErrorLevel%
if %ResultCode% EQU 0 (
  echo CMAKE is OK.
  set "Path=%CMAKE_MSVC_PATH%;%Path%"
) else (
  echo CMAKE not found. Check installed components of Visual Studio.
)
set CMAKE_MSVC_PATH=

exit /b %ResultCode%


:: ============================================================================
:CHECKTOOL
:: Call this sub with argument(s):
::   - %1 - Tool executable name
::   - %2 - CD before check
::
SetLocal

set TOOLEXE=%~1
if exist "%~2" (set TARGETDIR=%~2) else (set TARGETDIR=.)
pushd "%TARGETDIR%"

set CommandText=where "%TOOLEXE%" 2^^^>nul
set Output=
for /f "Usebackq delims=" %%i in (`%CommandText%`) do (
  if "/!Output!/"=="//" (
    set Output=%%i
  )
)

if "/%Output%/"=="//" (
  set ResultCode=1
  echo "%TOOLEXE%" not found.
) else (
  set ResultCode=0
  echo %TOOLEXE% location: %Output%
)

popd
EndLocal & set "TOOLPATH=%Output%" & exit /b %ResultCode%
