@echo off
::
:: Downloads, builds, and installs TCL/TK.
::
:: SHELL: MSVC Build Tools
::
set BASEDIR=%~dp0
set BASEDIR=%BASEDIR:~0,-1%
set PKGDIR=%BASEDIR%\pkg
set BLDDIR=%BASEDIR%\bld
set DEVDIR=%BASEDIR%\dev
set HOMTCL=%DEVDIR%\tcl
set OUTTCL="%BLDDIR%\stdout.log"
set ERRTCL="%BLDDIR%\stderr.log"
del %OUTTCL% 2>nul
del %ERRTCL% 2>nul
set ResultCode=0

if not exist "%PKGDIR%" mkdir "%PKGDIR%"

:: Download
cd /d "%PKGDIR%"
set TCLVER=8.6.12
set TCLURL=https://prdownloads.sourceforge.net/tcl/tcl%TCLVER%-src.tar.gz
call "%~dp0DownloadFile.bat" %TCLURL%
if not "/%ErrorLevel%/"=="/0/" (set ResultCode=%ErrorLevel%)
set TCLARC=%FileName%
set TKURL=%TCLURL:tcl/tcl=tcl/tk%
call "%~dp0DownloadFile.bat" %TKURL%
if not "/%ErrorLevel%/"=="/0/" (set ResultCode=%ErrorLevel%)
set TKARC=%FileName%

:: Extract
if not exist "%BLDDIR%\tcl\win\makefile.vc" (
  cd /d "%PKGDIR%"
  set PkgName=%TCLARC%
  rmdir /S /Q "%BLDDIR%\tcl" 2>nul
  call "%~dp0ExtractArchive.bat" !PkgName! "%BLDDIR%"
  if not "/!ErrorLevel!/"=="/0/" (set ResultCode=!ErrorLevel!)
  cd /d "%BLDDIR%"
  move "%TCLARC:~0,-11%" "tcl"
) 1>>%OUTTCL% 2>>%ERRTCL%

if not exist "%BLDDIR%\tk\win\makefile.vc" (
  cd /d "%PKGDIR%"
  set PkgName=%TKARC%
  rmdir /S /Q "%BLDDIR%\tk%" 2>nul
  call "%~dp0ExtractArchive.bat" !PkgName! "%BLDDIR%"
  if not "/!ErrorLevel!/"=="/0/" (set ResultCode=!ErrorLevel!)
  cd /d "%BLDDIR%"
  move "%TKARC:~0,-11%" "tk"
) 1>>%OUTTCL% 2>>%ERRTCL%

:: Build
echo ============= Making TCL ============
cd /d "%BLDDIR%\tcl\win"
set CommandText=dir /B /A:D 2^^^>nul
for /f "Usebackq delims=" %%G in (`%CommandText%`) do (
  set TMPDIR=%%G
)
if not exist "%TMPDIR%\tclConfig.sh" (
  echo ============= Making TCL ============
  set TMPDIR=
  nmake -f makefile.vc release
  if not "/!ErrorLevel!/"=="/0/" (set ResultCode=!ErrorLevel!)
) 1>>%OUTTCL% 2>>%ERRTCL%

echo ============= Installing TCL ============
if not exist "%HOMTCL%\bin\tclsh.exe" (
  echo ============= Installing TCL ============
  nmake -f makefile.vc install INSTALLDIR="%HOMTCL%"
  if not "/!ErrorLevel!/"=="/0/" (set ResultCode=!ErrorLevel!)
  cd /d "%HOMTCL%\bin"
  (echo.>>_tclsh.exe) & xcopy /Y tclsh*.exe _tclsh.exe & move _tclsh.exe tclsh.exe
) 1>>%OUTTCL% 2>>%ERRTCL%

echo ============= Making TK ============
cd /d "%BLDDIR%\tk\win"
set CommandText=dir /B /A:D 2^^^>nul
for /f "Usebackq delims=" %%G in (`%CommandText%`) do (
  set TMPDIR=%%G
)
if not exist "%TMPDIR%\pkgIndex.tcl" (
  echo ============= Making TK ============
  nmake -f makefile.vc release TCLDIR="%BLDDIR%\tcl"
  if not "/!ErrorLevel!/"=="/0/" (set ResultCode=!ErrorLevel!)
) 1>>%OUTTCL% 2>>%ERRTCL%

echo ============= Installing TK ============
if not exist "%HOMTCL%\bin\wish.exe" (
  echo ============= Installing TK ============
  nmake -f makefile.vc install INSTALLDIR="%HOMTCL%" TCLDIR="%BLDDIR%\tcl"
  if not "/!ErrorLevel!/"=="/0/" (set ResultCode=!ErrorLevel!)
  cd /d "%HOMTCL%\bin"
  (echo.>>_wish.exe) & xcopy /Y wish*.exe _wish.exe & move _wish.exe wish.exe
) 1>>%OUTTCL% 2>>%ERRTCL%

if "/!Path!/"=="/!Path:%HOMTCL%\bin=!/" set Path=%HOMTCL%\bin;%Path%
cd /d "%BASEDIR%"

echo.
echo ============= TCL/TK building is complete. ============
echo ResultCode: %ResultCode% (^>0 - errors occured) . Check the log files for errors. 
echo.

:: For SQLite\Makefile.msc
set TCLDIR=%HOMTCL%

:: Cleanup
set TCLVER=
set PkgName=
set TCLURL=
set TCLARC=
set TKURL=
set TKARC=
set HOMTCL=
set OUTTCL=
set ERRTCL=
set URL=
set FileLen=
set FileName=
set FileSize=
set FileURL=
set Flag=
set Folder=
set ArchiveName=
set CommandText=
set TMPDIR=

exit /b 0
