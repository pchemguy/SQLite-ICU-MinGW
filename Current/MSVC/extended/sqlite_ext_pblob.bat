@echo off


:: ================================ BEGIN MAIN ================================
if "%SQLITE_ENABLE_PBLOB%"=="0" (
    echo {INFO} PBLOB extension is disabled via SQLITE_ENABLE_PBLOB=0, skipping.
    exit /b 0
)
echo {INFO} PBLOB extension processing.

set "MAIN=%~dp0sqlite_msbuild.bat"

call :FP16_DOWNLOAD     || exit /b !ERRORLEVEL!
call :FP16_EXTRACT      || exit /b !ERRORLEVEL!
call :EXTRA_SRC_THIRD   || exit /b !ERRORLEVEL!

echo {INFO} PBLOB extension completed.

exit /b 0
:: ================================= END MAIN =================================


:: ============================================================================
:FP16_DOWNLOAD

setlocal
set "SECTION=FP16_DOWNLOAD"

set "DISTRO=%CACHEDIR%\fp16_master.zip"
set "URL=https://github.com/Maratyszcza/FP16/archive/refs/heads/master.zip"

call "%MAIN%" :DOWNLOAD__NAME_PATH_URL FP16 "%DISTRO%" "%URL%"
set "ERROR_STATUS=%ERRORLEVEL%"

echo ~~~~~ %SECTION% ~~~~~
echo:
endlocal && set "ERROR_STATUS=%ERROR_STATUS%" && exit /b %ERROR_STATUS%


:: ============================================================================
:FP16_EXTRACT

setlocal
set "SECTION=FP16_EXTRACT"

set "FLAG=%THIRDDIR%\FP16-master"
set "SRC=%CACHEDIR%\fp16_master.zip"
set "DST=%THIRDDIR%"

call "%MAIN%" :EXTRACT__NAME_FLAG_SRC_DST FP16 "%FLAG%" "%SRC%" "%DST%"
set "ERROR_STATUS=%ERRORLEVEL%"
if not "%ERROR_STATUS%"=="0" goto :FP16_EXTRACT_EXIT

echo {INFO} ========== Copy FP16 ===========

xcopy /H /Y /B /E /Q "%THIRDDIR%\FP16-master\include\*" "%TSRC%"
set "ERROR_STATUS=%ERRORLEVEL%"

:FP16_EXTRACT_EXIT

echo ~~~~~ %SECTION% ~~~~~
echo:
endlocal && set "ERROR_STATUS=%ERROR_STATUS%" && exit /b %ERROR_STATUS%


:: ============================================================================
:EXTRA_SRC_THIRD

set "SECTION=EXTRA_SRC_THIRD"

set OPT_XTRA=%OPT_XTRA% -DSQLITE_ENABLE_PBLOB

set SOURCES=^
    "%PROJDIR%\src\pblob.c"

set MISC_EXT=^
    "pblob.c"

echo {INFO} ========== Copy MISC_EXT ===========
"%TCLSH_CMD%" "%SQLITEDIR%\tool\cp.tcl" %SOURCES% "%TSRC%" || exit /b !ERRORLEVEL!

echo:

echo {INFO} ========== Patch MISC_EXT ===========
cd /d "%TSRC%"
"%TCLSH_CMD%" "%TOOLDIR%\patch_sqlite_misc_autoext.tcl" %MISC_EXT% || exit /b !ERRORLEVEL!

echo:

echo {INFO} ========== Bundle MISC_EXT ===========
"%TCLSH_CMD%" "%TOOLDIR%\bundle_extra_src.tcl" %MISC_EXT% || exit /b !ERRORLEVEL!

echo {INFO} ========== Set EXTRA_SRC for extended SQLite build ===========

set EXTRA_SRC=%EXTRA_SRC% ^
    ""%TSRC%\pblob.c""

echo ~~~~~ %SECTION% ~~~~~
echo:
exit /b %ERRORLEVEL%
