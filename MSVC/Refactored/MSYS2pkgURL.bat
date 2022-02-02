@echo off
::
:: Determines the URL of a package from the MSYS/MSYS2 repo.
::
:: Arguments:
::   %1 - Package name
::   %2 - Architecture - x32/x86 or x64/AMD64
::     (optional; uses %ARCH% then %PROCESSOR_ARCHITECTURE% by default).
::
:: Sets:  
::   PKGURL to the target URL.
::
:: On failure:
::   PKGURL is undefined
::   ResultCode <> 0
::
:: Examples:
::   MSYS2pkgURL.bat bash
::
call "%~dp0GNUGet.bat"
if not "/%ErrorLevel%/"=="/0/" (set ResultCode=%ErrorLevel%)

echo.
echo ======================= Determine current MSYS2 package URL ======================
set ResultCode=0
set PKGURL=
set PKGNAM=%~1
if "/%PKGNAM%/"=="//" (
  echo Package name is not supplied.
  set ResultCode=1
)
if not %ResultCode% EQU 0 (
  echo Correct arguments have not been provided to determine current MSYS2 package URL.
  echo --------------------------------------------------------------------------------
  echo.
  exit /b %ResultCode%
)

if not "/%~2/"=="//" (
  set ARCHMSYS=%~2
) else (
  set ARCHMSYS=%ARCH%
)
if "/%ARCHMSYS%/"=="//" set "ARCHMSYS=%PROCESSOR_ARCHITECTURE%"
set ARCHMSYS=%ARCHMSYS:AMD=x%
set ARCHMSYS=%ARCHMSYS:86=32%

set PKGPage=https://packages.msys2.org/package/%PKGNAM%?repo=msys^^^&variant=x86_64
set InfoFile=MSYSx64-%PKGNAM%-Info.txt
if not exist "%InfoFile%" (
  curl %PKGPage% -o "%InfoFile%"
)

set PatternURL="href..https://mirror.msys2.org/msys/x86_64/%PKGNAM%.*?-x86_64.pkg.tar.[a-z]*"
set CommandText=grep.exe -m 1 -Po "%PatternURL%" "%InfoFile%"
for /f "Usebackq delims=" %%G in (`%CommandText%`) do (
  set PKGURL=%%G
  set PKGURL=!PKGURL:"=!
)

if not "/%PKGURL%/"=="//" (
  set PKGURL=%PKGURL:~5%
) else (
  set ResultCode=1
  echo Failed to get package [%PKGNAM%] URL.
  exit /b %ResultCode%
)

if /I "/%ARCHMSYS%/"=="/x32/" (
  set PKGURL=%PKGURL:x86_64=i686%
)

echo ----------------------------------------------------------------------------------
echo.

:: Cleanup
set ARCHMSYS=

exit /b %ResultCode%
