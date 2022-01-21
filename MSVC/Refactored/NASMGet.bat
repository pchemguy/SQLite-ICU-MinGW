@echo off
::
:: Downloads stable NASM binary release from https://nasm.us.
::
:: The script checks if "nasm" is in the path. If not, gets binaries in
:: "%dp0dev\nasm\x32" and "%dp0dev\nasm\x64".
::
:: The script enters the "%dp0distro" subdirectory (creates, if necessary).
:: Distro archives are downloaded, if not present, and saved in "%dp0distro".
:: Distro archives are expanded in "%dp0dev\nasm" and NASM is prepended to Path.
:: 
set BASEDIR=%~dp0
set BASEDIR=%BASEDIR:~0,-1%
set NASM_HOME=%BASEDIR%\dev\nasm

call "%~dp0GNUGet.bat"


if not exist "%BASEDIR%\distro" mkdir "%BASEDIR%\distro"
pushd "%BASEDIR%\distro"


set NASMURLPrefix=https://www.nasm.us/pub/nasm/stable
call "%~dp0DownloadFile.bat" "%NASMURLPrefix%/win32" "nasm-win32-info.txt"
set CommandText=grep.exe -o """nasm-[0-9.]*-win32.zip""" nasm-win32-info.txt 

for /f "Usebackq delims=" %%G in (`%CommandText%`) do (
  set NASM_VERSION=%%~G
  set NASM_VERSION=!NASM_VERSION:~5,-10!
  goto :VERSION_SET
)
:VERSION_SET

set URLx32=%NASMURLPrefix%/win32/nasm-%NASM_VERSION%-win32.zip
call "%~dp0DownloadFile.bat" %URLx32%
set NASMx32File=%FileName%
set URLx64=%NASMURLPrefix%/win64/nasm-%NASM_VERSION%-win64.zip
call "%~dp0DownloadFile.bat" %URLx64%
set NASMx64File=%FileName%


if not exist "%BASEDIR%\dev\nasm\x32\nasm.exe" (
  if exist "%BASEDIR%\dev\nasm" rmdir /S /Q "%BASEDIR%\dev\nasm" 2>nul
  mkdir "%BASEDIR%\dev\nasm"
  call "%~dp0ExtractArchive.bat" %NASMx32File% "%BASEDIR%\dev\nasm"
  move "%BASEDIR%\dev\nasm\nasm-%NASM_VERSION%" "%BASEDIR%\dev\nasm\x32"
  call "%~dp0ExtractArchive.bat" %NASMx64File% "%BASEDIR%\dev\nasm"
  move "%BASEDIR%\dev\nasm\nasm-%NASM_VERSION%" "%BASEDIR%\dev\nasm\x64"
)

if "/%VSCMD_ARG_TGT_ARCH%/" == "/x64/" (set ARCH=x64)
if "/%VSCMD_ARG_TGT_ARCH%/" == "/x86/" (set ARCH=x32)
if not defined ARCH set ARCH=x32

set Path=%BASEDIR%\dev\nasm\%ARCH%;%Path%

echo.
echo ============= NASM is ready. ============
echo.

popd

exit /b 0
