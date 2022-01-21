@echo off
::
:: Downloads Sed from SourceForge.
::
set BASEDIR=%~dp0
set BASEDIR=%BASEDIR:~0,-1%

if not exist "%BASEDIR%\distro" mkdir "%BASEDIR%\distro"
pushd "%BASEDIR%\distro"

set SedURLMain=https://downloads.sourceforge.net/project/gnuwin32/sed/4.2.1/sed-4.2.1-bin.zip
call "%~dp0DownloadFile.bat" %SedURLMain%
set SedArcMain=%FileName%
set SedURLDep=https://downloads.sourceforge.net/project/gnuwin32/sed/4.2.1/sed-4.2.1-dep.zip
call "%~dp0DownloadFile.bat" %SedURLDep%
set SedArcDep=%FileName%


:: Expand archive
if not exist "%BASEDIR%\dev\sed\sed.exe" (
  if exist "%BASEDIR%\dev\sed" rmdir /S /Q "%BASEDIR%\dev\sed" 2>nul
  if exist "%BASEDIR%\dev\tmp" rmdir /S /Q "%BASEDIR%\dev\tmp" 2>nul
  mkdir "%BASEDIR%\dev\tmp"
  call "%~dp0ExtractArchive.bat" %SedArcMain% "%BASEDIR%\dev\tmp"
  call "%~dp0ExtractArchive.bat" %SedArcDep% "%BASEDIR%\dev\tmp"
  move "%BASEDIR%\dev\tmp\bin" "%BASEDIR%\dev\sed"
  rmdir /S /Q "%BASEDIR%\dev\tmp" 2>nul
)


set Path=%BASEDIR%\dev\sed;%Path%

popd

exit /b 0
