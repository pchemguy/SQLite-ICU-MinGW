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
:: https://strawberryperl.com/download/5.32.1.1/strawberry-perl-5.32.1.1-64bit.zip
:: https://strawberryperl.com/download/5.32.1.1/strawberry-perl-5.32.1.1-32bit.msi
:: 
set BASEDIR=%~dp0
set BASEDIR=%BASEDIR:~0,-1%
set PKGDIR=%BASEDIR%\pkg
set BLDDIR=%BASEDIR%\bld
set DEVDIR=%BASEDIR%\dev
set HOMPERL=%DEVDIR%\perl
set ResultCode=0

call "%~dp0GNUGet.bat"
if not "/%ErrorLevel%/"=="/0/" (set ResultCode=%ErrorLevel%)

if not exist "%PKGDIR%" mkdir "%PKGDIR%"
pushd "%PKGDIR%"


set PerlURLPrefix=https://strawberryperl.com
call "%~dp0DownloadFile.bat" "%PerlURLPrefix%" "perl-info.txt"
if not "/%ErrorLevel%/"=="/0/" (set ResultCode=%ErrorLevel%)
set CommandText=grep.exe -o -m 1 "/download/[0-9.]*/strawberry-perl-[0-9.]*-32bit.msi" perl-info.txt 
for /f "Usebackq delims=" %%G in (`%CommandText%`) do (
  set URLx32=%%~G
  set URLx32=%PerlURLPrefix%!URLx32:msi=zip!
)

call "%~dp0DownloadFile.bat" %URLx32%
if not "/%ErrorLevel%/"=="/0/" exit /b %ErrorLevel%
set Perlx32File=%FileName%

if not exist "%HOMPERL%\bin\perl.exe" (
  if exist "%HOMPERL%" rmdir /S /Q "%HOMPERL%" 2>nul
  set TARPATTERN=perl
  call "%~dp0ExtractArchive.bat" %Perlx32File% "%HOMPERL%\.."
  if not "/%ErrorLevel%/"=="/0/" exit /b %ErrorLevel%
)

if "/!Path!/"=="/!Path:%HOMPERL%\bin=!/" set Path=%HOMPERL%\bin;%Path%

echo.
echo ============= Perl installation is complete. ============
echo ResultCode: %ResultCode% (^>0 - errors occured). Check the log files for errors. 
echo.

:: Cleanup
set HOMPERL=
set PERLURLPrefix=
set URLx32=
set Perlx32File=
set URL=
set FileLen=
set FileName=
set FileSize=
set FileURL=
set Flag=
set Folder=
set ArchiveName=
set CommandText=

popd

exit /b %ResultCode%
