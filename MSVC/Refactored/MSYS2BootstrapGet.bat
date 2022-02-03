@echo off
::
:: SHELL: CMD Or MSVC Build Tools
::


set BASEDIR=%~dp0
set BASEDIR=%BASEDIR:~0,-1%
set PKGDIR=%BASEDIR%\pkg
set DEVDIR=%BASEDIR%\dev
set PKGMSYS=%PKGDIR%\msys2
set HOMMSYS=%DEVDIR%\msys2
set ResultCode=0

if not exist "%PKGDIR%" mkdir "%PKGDIR%"
pushd "%PKGDIR%"

if exist "%HOMMSYS%\msys2.exe" goto :ADDTOPATH

set PKGS="base" ^
         "base-devel" ^
         "pactoys"

SetLocal
for %%G in (%PKGS%) do (
  call "%~dp0MSYS2pkgGet.bat" %%~G
  set ResultCode=!ErrorLevel!
  if not "/!ResultCode!/"=="/0/" (
    echo MSYS2pkgGet.bat error!
    echo ----------------------
    goto :EOS
  )
)
EndLocal

:ADDTOPATH
set MSYS_BIN=%HOMMSYS%\usr\bin
if "/!Path!/"=="/!Path:%MSYS_BIN%=!/" set Path=%MSYS_BIN%;%Path%


:EOS

:: Cleanup
set PKGMSYS=
set HOMMSYS=
set FileLen=
set FileName=
set FileSize=
set FileURL=
set Flag=
set Folder=
set ArchiveName=
set CommandText=
set InfoFile=

popd

exit /b %ResultCode%
