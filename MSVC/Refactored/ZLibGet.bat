@echo off
::
:: Prepares the zlib library
::
:: Set current directory to the distro download directory before calling. 
:: If exists .\distro, enter it.

set BASEDIR=%~dp0
set BASEDIR=%BASEDIR:~0,-1%
if exist "%BASEDIR%\distro" (pushd "%BASEDIR%\distro") else (pushd "%CD%")

set ChangeLogURL=https://zlib.net/ChangeLog.txt
call "%~dp0DownloadFile.bat" %ChangeLogURL%

set CommandText=type %FileName%
for /f "Usebackq tokens=1,3 skip=2 delims= " %%G in (`%CommandText%`) do (
  if "/%%G/"=="/Changes/" (
    set ZLibVersion=%%H
    goto :VERSION_SET
  )
)

:VERSION_SET
set DistroName=zlib-%ZLibVersion%.tar.gz
set ReleaseURL=https://zlib.net/%DistroName%
call "%~dp0DownloadFile.bat" %ReleaseURL%
if not exist "zlib\Makefile" (
  rmdir /S /Q "zlib" 2>nul
  call "%~dp0ExtractArchive.bat" %DistroName%
  move "zlib-%ZLibVersion%" "zlib"
)

cd /d "zlib"
if "%/USE_STDCALL/%"=="/1/" (set ZLIBLOC=-DZLIB_WINAPI)
nmake -f win32/Makefile.msc LOC="%ZLIBLOC%"

popd

exit /b 0
