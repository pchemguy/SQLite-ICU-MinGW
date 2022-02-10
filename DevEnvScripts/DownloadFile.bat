@echo off
::
:: Downloads file via cURL.
::
:: The script uses cURL to download a file and verifies file size (via URLInfo.bat).
::
:: Arguments:
::   %1 - URL
::   %2 - File name (optional; if not provided, tries to extract the last part of the URL)
::
:: On failure:
::   ResultCode <> 0
::
:: Examples:
::   DownloadFile.bat https://github.com/unicode-org/icu/releases/download/release-70-1/icu4c-70_1-Win32-MSVC2019.zip icu4c-70_1-Win32-MSVC2019.zip
::   DownloadFile.bat https://github.com/unicode-org/icu/releases/download/release-70-1/icu4c-70_1-Win32-MSVC2019.zip
::
:: SHELL: CMD Or MSVC Build Tools
::
echo.
echo ==================== Downloading file ====================
set ResultCode=0
set FileURL=%~1
if "/%FileURL%/"=="//" (
  echo File URL is not supplied.
  set ResultCode=1
)
if not %ResultCode% EQU 0 (
  echo Correct arguments have not been provided to download file.
  echo ----------------------------------------------------------
  echo.
  exit /b %ResultCode%
)
set FileName=%~2
if "/%FileName%/"=="//" (call :EXTRACT_FILENAME %FileURL%)

:: Before downloading %FileName% file, check if %FileName%.size file exists.
:: If not, get file size via URLInfo.bat and save it to %FileName%.size.
::
if exist "%FileName%.size" (
  for /f "Usebackq delims=" %%G in ("%FileName%.size") do (
    set FileLen=%%G
  )
) else (
  call "%~dp0URLInfo.bat" %FileURL%
  set ResultCode=%ErrorLevel%
  if not !ResultCode! EQU 0 (
    echo ----- URL error -----
    exit /b !ResultCode!
  )
  if not "/!FileLen!/"=="//" echo !FileLen!>"%FileName%.size"
)

:: If the %FileName% file has been downloaded and saved previously, its size
:: should be in the %FileName%.size file. If the actual file size does not
:: match the associated meta value, the cached copy is deleted.
::
if exist "%FileName%" (
  if "/%FileLen%/"=="//" (
    echo ========= Using previously downloaded %FileName% =========
    echo Warning: file size information is not available.
    echo ----------------------------------------------------------
    exit /b 0
  )
  call :SET_FILESIZE "%FileName%"
  if "/!FileSize!/"=="/%FileLen%/" (
    echo ========= Using previously downloaded %FileName% =========
    echo ----------------------------------------------------------
    exit /b 0
  ) else (
    echo ----- File size saved in file "%FileName%.size" does not match the size of cached copy: -----
    echo Saved file size:     ==%FileLen%==
    echo Size of cached copy: ==%FileSize%==
    echo Dowloading again.
    echo.
    del /Q "%FileName%"
  )
)

:: Download the file
::
echo ===== Downloading %FileName% =====
curl -L %FileURL% --output "%FileName%"
set ResultCode=%ErrorLevel%
if %ResultCode% NEQ 0 (
  echo Error downloading %FileName%.
  exit /b !ResultCode!
)

:: Verify that the size of the downloaded file matches the saved value. If not,
:: both the target file and its companion holding the size are renamed as invalid.
:: Skip check if size information is not available.
::
if "/%FileLen%/"=="/0/" (
  set "FileLen="
  echo.>"%FileName%.size"
)
if "/%FileLen%/"=="//" (
  echo Warning: file size information is not available.
  set FileSize=
) else (
  call :SET_FILESIZE "%FileName%"
)

if "/!FileSize!/"=="/%FileLen%/" (
  echo ----- Downloaded %FileName%  -----
) else (
  echo Error downloading %FileName% - file size mismatch. Run the processes again.
  echo File renamed to %FileName%.$$$.
  echo.
  move "%FileName%" "%FileName%.$$$" 1>nul
  move "%FileName%.size" "%FileName%.size.$$$" 1>nul
  set ResultCode=1
)
echo ----------------------------------------------------------
echo.

exit /b %ResultCode%


:: ============================================================================
:: Extracts file name from a URL [the last part of the URL].
:: This routine expects a full URL including protocol. The "://" is replaced
:: with the space, so that when the resulting string is passed as a paramter
:: via "call" to :SET_FILENAME, the latter recieves the part without protocol
:: as a second parameter. If the URL contains GET parameters [?...], this part
:: is also separated from the URL [? is replaced with space].
::
:EXTRACT_FILENAME
set URL=%~1
set URL=%URL:://= %
set URL=%URL:?= %
call :SET_FILENAME %URL%
exit /b 0

:SET_FILENAME
set FileName=%~nx2
exit /b 0

:SET_FILESIZE
set FileSize=%~z1
exit /b 0
