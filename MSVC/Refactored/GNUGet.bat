@echo off
set BASEDIR=%~dp0
set BASEDIR=%BASEDIR:~0,-1%

if not exist "%BASEDIR%\distro" mkdir "%BASEDIR%\distro"
pushd "%BASEDIR%\distro"

set GNUURLMain=https://downloads.sourceforge.net/project/gnuwin32/sed/4.2.1/sed-4.2.1-bin.zip
call "%~dp0DownloadFile.bat" %GNUURLMain%
set GNUArcMain=%FileName%
set GNUURLDep=https://downloads.sourceforge.net/project/gnuwin32/sed/4.2.1/sed-4.2.1-dep.zip
call "%~dp0DownloadFile.bat" %GNUURLDep%
set GNUArcDep=%FileName%


:: Expand archive
if not exist "%BASEDIR%\dev\gnu\sed.exe" (
  if exist "%BASEDIR%\dev\tmp" rmdir /S /Q "%BASEDIR%\dev\tmp" 2>nul
  mkdir "%BASEDIR%\dev\tmp"
  call "%~dp0ExtractArchive.bat" %GNUArcMain% "%BASEDIR%\dev\tmp"
  call "%~dp0ExtractArchive.bat" %GNUArcDep% "%BASEDIR%\dev\tmp"
  move "%BASEDIR%\dev\tmp\bin" "%BASEDIR%\dev\tmp\gnu"
  move "%BASEDIR%\dev\tmp\gnu\*" "%BASEDIR%\dev\gnu"
  rmdir /S /Q "%BASEDIR%\dev\tmp" 2>nul
)


set GNUURLMain=https://downloads.sourceforge.net/project/gnuwin32/grep/2.5.4/grep-2.5.4-bin.zip
call "%~dp0DownloadFile.bat" %GNUURLMain%
set GNUArcMain=%FileName%
set GNUURLDep=https://downloads.sourceforge.net/project/gnuwin32/grep/2.5.4/grep-2.5.4-dep.zip
call "%~dp0DownloadFile.bat" %GNUURLDep%
set GNUArcDep=%FileName%


:: Expand archive
if not exist "%BASEDIR%\dev\gnu\grep.exe" (
  if exist "%BASEDIR%\dev\tmp" rmdir /S /Q "%BASEDIR%\dev\tmp" 2>nul
  mkdir "%BASEDIR%\dev\tmp"
  call "%~dp0ExtractArchive.bat" %GNUArcMain% "%BASEDIR%\dev\tmp"
  call "%~dp0ExtractArchive.bat" %GNUArcDep% "%BASEDIR%\dev\tmp"
  move "%BASEDIR%\dev\tmp\bin" "%BASEDIR%\dev\tmp\gnu"
  move "%BASEDIR%\dev\tmp\gnu\*" "%BASEDIR%\dev\gnu"
  rmdir /S /Q "%BASEDIR%\dev\tmp" 2>nul
)

set Path=%BASEDIR%\dev\gnu;%Path%

popd

exit /b 0
