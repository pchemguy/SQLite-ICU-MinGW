@echo off
::
:: Downloads and installs TCL/TK.
::
set BASEDIR=%~dp0
set BASEDIR=%BASEDIR:~0,-1%
set DISTRODIR=%BASEDIR%\distro
set BUILDDIR=%BASEDIR%\build
set INSTALLDIR=%BASEDIR%\dev\tcl
set STDOUTLOG=%BASEDIR%\stdouttcl.log
set STDERRLOG=%BASEDIR%\stderrtcl.log
del "%STDOUTLOG%" 2>nul
del "%STDERRLOG%" 2>nul
set ResultCode=0

if not exist "%DISTRODIR%" mkdir "%DISTRODIR%"

:: Download
(
  cd /d "%DISTRODIR%"
  set TCL_VERSION=8.6.12
  set TCLURL=https://prdownloads.sourceforge.net/tcl/tcl!TCL_VERSION!-src.tar.gz
  call "%~dp0DownloadFile.bat" !TCLURL!
  if not "/%ErrorLevel%/"=="/0/" (set ResultCode=%ErrorLevel%)
  set TCLARC=!FileName!
  set TKURL=https://prdownloads.sourceforge.net/tcl/tk!TCL_VERSION!-src.tar.gz
  call "%~dp0DownloadFile.bat" !TKURL!
  if not "/%ErrorLevel%/"=="/0/" (set ResultCode=%ErrorLevel%)
  set TKARC=!FileName!
) 1>>"%STDOUTLOG%" 2>>"%STDERRLOG%"

:: Extract
if not exist "%BUILDDIR%\tcl\win\makefile.vc" (
  cd /d "%DISTRODIR%"
  set DistroName=%TCLARC%
  rmdir /S /Q "%BUILDDIR%\tcl" 2>nul
  call "%~dp0ExtractArchive.bat" !DistroName! "%BUILDDIR%"
  if not "/%ErrorLevel%/"=="/0/" (set ResultCode=%ErrorLevel%)
  cd /d "%BUILDDIR%"
  move "%TCLARC:~0,-11%" "tcl"
) 1>>"%STDOUTLOG%" 2>>"%STDERRLOG%"

if not exist "%BUILDDIR%\tk\win\makefile.vc" (
  cd /d "%DISTRODIR%"
  set DistroName=%TKARC%
  rmdir /S /Q "%BUILDDIR%\tk%" 2>nul
  call "%~dp0ExtractArchive.bat" !DistroName! "%BUILDDIR%"
  if not "/%ErrorLevel%/"=="/0/" (set ResultCode=%ErrorLevel%)
  cd /d "%BUILDDIR%"
  move "%TKARC:~0,-11%" "tk"
) 1>>"%STDOUTLOG%" 2>>"%STDERRLOG%"

:: Build
echo ============= Making TCL ============
cd /d "%BASEDIR%\build\tcl\win"
set CommandText=dir /B /A:D 2^^^>nul
for /f "Usebackq delims=" %%G in (`%CommandText%`) do (
  set TMPDIR=%%G
)
if not exist "%TMPDIR%\tclConfig.sh" (
  echo ============= Making TCL ============
  set TMPDIR=
  nmake -f makefile.vc release
  if not "/%ErrorLevel%/"=="/0/" (set ResultCode=%ErrorLevel%)
) 1>>"%STDOUTLOG%" 2>>"%STDERRLOG%"

echo ============= Installing TCL ============
if not exist "%INSTALLDIR%\bin\tclsh.exe" (
  echo ============= Installing TCL ============
  nmake -f makefile.vc install INSTALLDIR="%INSTALLDIR%"
  if not "/%ErrorLevel%/"=="/0/" (set ResultCode=%ErrorLevel%)
  cd /d "%INSTALLDIR%\bin"
  (echo.>>_tclsh.exe) & xcopy /Y tclsh*.exe _tclsh.exe & move _tclsh.exe tclsh.exe
) 1>>"%STDOUTLOG%" 2>>"%STDERRLOG%"

echo ============= Making TK ============
cd /d "%BASEDIR%\build\tk\win"
set CommandText=dir /B /A:D 2^^^>nul
for /f "Usebackq delims=" %%G in (`%CommandText%`) do (
  set TMPDIR=%%G
)
if not exist "%TMPDIR%\pkgIndex.tcl" (
  echo ============= Making TK ============
  nmake -f makefile.vc release TCLDIR="%BASEDIR%\build\tcl"
  if not "/%ErrorLevel%/"=="/0/" (set ResultCode=%ErrorLevel%)
) 1>>"%STDOUTLOG%" 2>>"%STDERRLOG%"

echo ============= Installing TK ============
if not exist "%INSTALLDIR%\bin\wish.exe" (
  echo ============= Installing TK ============
  nmake -f makefile.vc install INSTALLDIR="%INSTALLDIR%" TCLDIR="%BASEDIR%\build\tcl"
  if not "/%ErrorLevel%/"=="/0/" (set ResultCode=%ErrorLevel%)
  cd /d "%INSTALLDIR%\bin"
  (echo.>>_wish.exe) & xcopy /Y wish*.exe _wish.exe & move _wish.exe wish.exe
) 1>>"%STDOUTLOG%" 2>>"%STDERRLOG%"

set Path=%INSTALLDIR%\bin;%Path%
cd /d "%BASEDIR%"

echo.
echo ============= TCL/TK building is complete. ============
echo ResultCode: %ResultCode% (^>0 - errors occured) . Check the log files for errors. 
echo.

:: Cleanup
set TCL_VERSION=
set DistroName=
set TCLURL=
set TCLARC=
set TKURL=
set TKARC=
set BASEDIR=
set DISTRODIR=
set BUILDDIR=
set INSTALLDIR=
set ResultCode=
set STDOUTLOG=
set STDERRLOG=

exit /b 0
