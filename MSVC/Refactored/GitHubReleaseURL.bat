@echo off
::
:: Determines current GitHub release URL.
::
:: Set current directory to the distro download directory before calling.
::
:: Arguments:
::   %1 - Repo owner
::   %2 - Repo name
::   %3 - Release URL match pattern (the first matched asset URL will be used)
::
:: Sets:  
::   ReleaseURL to the target URL.
::
:: On failure:
::   ReleaseURL is undefined
::   ResultCode <> 0
::
:: Examples:
::   GitHubReleaseURL.bat unicode-org icu Win32-MSVC
::
echo.
echo ====================== Determine current GitHub release URL ======================
set ResultCode=0
set ReleaseURL=
set RepoOwner=%~1
if "/%RepoOwner%/"=="//" (
  echo Repo owner is not supplied.
  set ResultCode=1
)
set RepoName=%~2
if "/%RepoName%/"=="//" (
  echo Repo name is not supplied.
  set ResultCode=1
)
set PatternURL=%~3
if "/%PatternURL%/"=="//" (
  echo Pattern is not supplied.
  set ResultCode=1
)
if not %ResultCode% EQU 0 (
  echo Correct arguments have not been provided to determine current GitHub release URL.
  echo ----------------------------------------------------------------------------------
  echo.
  exit /b %ResultCode%
)

set ReleaseAPI=https://api.github.com/repos/%RepoOwner%/%RepoName%/releases/latest
set InfoFile=%RepoName%-Info.txt
if not exist "%InfoFile%" (
  curl -H "Accept: application/vnd.github.v3+json" %ReleaseAPI% -o "%InfoFile%"
)

set ResultCode=2
set CommandText=type "%InfoFile%"
for /f "Usebackq tokens=1,2 delims= " %%G in (`%CommandText%`) do (
  set AttrName=%%G
  set AttrName=!AttrName:~1,-2!
  set AttrValue=%%H
  set AttrValue=!AttrValue:~1,-1!
  if /I "/!AttrName!/"=="/browser_download_url/" (
    if /I not "/!AttrValue!/"=="/!AttrValue:%PatternURL%=!/" (
      set ReleaseURL=!AttrValue!
      set ResultCode=0
      echo Release URL: !ReleaseURL!
      echo ----------------------------------------------------------------------------------
      echo.
      goto :URL_SET
    )
  )
)
:URL_SET

exit /b %ResultCode%
