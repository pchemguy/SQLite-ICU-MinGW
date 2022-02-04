@echo off
::
:: Downloads stable NASM binary release from https://nasm.us.
::
:: The script checks if "nasm" is in the path. If not, gets binaries in
:: "%dp0dev\nasm\x32" and "%dp0dev\nasm\x64".
::
:: The script enters the "%dp0pkg" subdirectory (creates, if necessary).
:: Distro archives are downloaded, if not present, and saved in "%dp0pkg".
:: Distro archives are expanded in "%dp0dev\nasm" and NASM is prepended to Path.
:: 
:: SHELL: CMD Or MSVC Build Tools
::
set ResultCode=0
if not defined GNUWIN32 (
  call "%~dp0GNUGet.bat" 1>nul
  set ResultCode=!ErrorLevel!
  if not "/!ResultCode!/"=="/0/" (
    echo GNUGet.bat error.
    echo -----------------
    goto :EOS
  )
)

set BASEDIR=%~dp0
set BASEDIR=%BASEDIR:~0,-1%
set PKGDIR=%BASEDIR%\pkg
set BLDDIR=%BASEDIR%\bld
set DEVDIR=%BASEDIR%\dev
set HOMNASM=%DEVDIR%\nasm
set ResultCode=0

if not exist "%PKGDIR%" mkdir "%PKGDIR%"
pushd "%PKGDIR%"


set NASMURLPrefix=https://www.nasm.us/pub/nasm/stable
if not exist "nasm-win32-info.txt" (
  call "%~dp0DownloadFile.bat" "%NASMURLPrefix%/win32" "nasm-win32-info.txt"
)

set CommandText=grep.exe -o """nasm-[0-9.]*-win32.zip""" nasm-win32-info.txt
for /f "Usebackq delims=" %%G in (`%CommandText%`) do (
  set NASM_VERSION=%%~G
  set NASM_VERSION=!NASM_VERSION:~5,-10!
  goto :VERSION_SET
)
:VERSION_SET

set URLx32=%NASMURLPrefix%/win32/nasm-%NASM_VERSION%-win32.zip
call "%~dp0DownloadFile.bat" %URLx32%
if not "/%ErrorLevel%/"=="/0/" exit /b %ErrorLevel%
set NASMx32File=%FileName%
set URLx64=%NASMURLPrefix%/win64/nasm-%NASM_VERSION%-win64.zip
call "%~dp0DownloadFile.bat" %URLx64%
if not "/%ErrorLevel%/"=="/0/" exit /b %ErrorLevel%
set NASMx64File=%FileName%


if not exist "%HOMNASM%\x32\nasm.exe" (
  if exist "%HOMNASM%" rmdir /S /Q "%HOMNASM%" 1>nul
  mkdir "%HOMNASM%" 1>nul
  call "%~dp0ExtractArchive.bat" %NASMx32File% "%HOMNASM%"
  if not "/!ErrorLevel!/"=="/0/" exit /b !ErrorLevel!
  move "%HOMNASM%\nasm-%NASM_VERSION%" "%HOMNASM%\x32"
  call "%~dp0ExtractArchive.bat" %NASMx64File% "%HOMNASM%"
  if not "/!ErrorLevel!/"=="/0/" exit /b !ErrorLevel!
  move "%HOMNASM%\nasm-%NASM_VERSION%" "%HOMNASM%\x64"
)

if "/%VSCMD_ARG_TGT_ARCH%/"=="/x64/" (set ARCH=x64)
if "/%VSCMD_ARG_TGT_ARCH%/"=="/x86/" (set ARCH=x32)
if not defined ARCH set ARCH=x32

if "/!Path!/"=="/!Path:%HOMNASM%\%ARCH%=!/" set Path=%HOMNASM%\%ARCH%;%Path%
set NASM=1

echo.
echo ============= NASM installation is complete. ============
echo ResultCode: %ResultCode% (^>0 - errors occured). Check the log files for errors. 
echo.

:EOS

:: Cleanup
set HOMNASM=
set NASMURLPrefix=
set URLx32=
set NASMx32File=
set URLx64=
set NASMx64File=
set URL=
set FileLen=
set FileName=
set FileSize=
set FileURL=
set Flag=
set Folder=
set ArchiveName=
set CommandText=
set NASM_VERSION=

popd

exit /b 0
