@echo off
:: =============================================================================
:: SCRIPT
::   sqlite_MSVC_Cpp_Build_Tools.ext.bat
::
:: PURPOSE
::   Builds and packages a customized SQLite distribution on Windows using
::   MSVC and SQLite's Makefile.msc.
::
::   The workflow manages SQLite and optional dependency downloads, x86/x64
::   builds, ZLIB and ICU integration, FP16 staging, stock SQLite ext/misc
::   modules, project-specific integrated extensions, dedicated test builds,
::   DLL export/import-library generation, and final artifact collection.
::
::   Principal outputs are written under:
::
::     out\bin
::     out\include
::     out\lib\import
::     out\lib\static
::
::   Build behavior is controlled primarily by:
::
::     USE_ICU
::     USE_ZLIB
::     SQLITE_EXTRA
::
::   Run from an initialized MSVC x86 or x64 developer command prompt.
::
:: DOCUMENTATION
::   See sqlite_MSVC_Cpp_Build_Tools.ext.md for the complete build-system
::   documentation, including prerequisites, configuration, directory layout,
::   build stages, extension integration, test-build guidance, outputs, caching,
::   cleaning, architecture handling, and reproducibility notes.
:: =============================================================================

:: ============================= BEGIN DISPATCHER =============================
call :MAIN %*

exit /b %ERRORLEVEL%
:: ============================= END   DISPATCHER =============================


:: ================================ BEGIN MAIN ================================
:MAIN

SetLocal EnableExtensions EnableDelayedExpansion

set "ERROR_STATUS=0"

call :CORE_ENV             || exit /b !ERRORLEVEL!

if "%USE_ICU%"=="1" (
    call :ICU_OPTIONS      || exit /b !ERRORLEVEL!
)                          
call :ZLIB_OPTIONS         || exit /b !ERRORLEVEL!
call :TCL_OPTIONS          || exit /b !ERRORLEVEL!
call :BUILD_OPTIONS        || exit /b !ERRORLEVEL!

call :CHECK_PREREQUISITES  || exit /b !ERRORLEVEL!

call :MAKE_DEBUG %*        || exit /b !ERRORLEVEL!

call :SQLITE_DOWNLOAD      || exit /b !ERRORLEVEL!
call :SQLITE_EXTRACT       || exit /b !ERRORLEVEL!

if "%USE_ZLIB%"=="1" (     
    call :ZLIB_DOWNLOAD    || exit /b !ERRORLEVEL!
    call :ZLIB_EXTRACT     || exit /b !ERRORLEVEL!
    call :ZLIB_BUILD       || exit /b !ERRORLEVEL!
)                          

if "%USE_ICU%"=="1" (      
    call :ICU_DOWNLOAD     || exit /b !ERRORLEVEL!
    call :ICU_EXTRACT      || exit /b !ERRORLEVEL!
    call :ICU_BUILD        || exit /b !ERRORLEVEL!
)                          

call :SQLITE_BUILD_INIT    || exit /b !ERRORLEVEL!

if "%SQLITE_EXTRA%"=="1" (
    call :EXTRA_SRC_STOCK  || exit /b !ERRORLEVEL!
)

call :SQLITE_BUILD %*      || exit /b !ERRORLEVEL!
call :COLLECT_BINARIES

EndLocal

echo:
exit /b 0
:: ================================= END MAIN =================================


:: ============================================================================
:MKDIR__DIR

:: Creates directory or fails with feedback.
::
:: %~1 - Full target directory path.
::
:: Attempts creating target directory if not exist.
:: Fails if creation fails or directory does not exist after creation.

setlocal
set "SECTION=MKDIR__DIR"

if "%~1"=="" (
    set "ERROR_STATUS=1"
    echo {ERROR} Missing required target directory.
    echo {INFO}  USAGE: call :MKDIR__DIR "{FULL TARGET DIRECTORY PATH}"
    goto :MKDIR__DIR_EXIT
)

set "TARGETDIR=%~1"
set "MKDIR_FAILED="
set "ERROR_STATUS=0"

if exist "%TARGETDIR%" (
    echo {INFO} "%TARGETDIR%" already exists.
    goto :MKDIR__DIR_EXIT
)

cmd /c mkdir "%TARGETDIR%" || set "MKDIR_FAILED=1"
if not exist "%TARGETDIR%"   (set "MKDIR_FAILED=1")

if defined MKDIR_FAILED (
    set "ERROR_STATUS=1"
    echo {ERROR} Failed to create "%TARGETDIR%"
    goto :MKDIR__DIR_EXIT
)

echo {INFO} Created "%TARGETDIR%".

:MKDIR__DIR_EXIT

echo ~~~~~ %SECTION% ~~~~~
echo:
endlocal && set "ERROR_STATUS=%ERROR_STATUS%" && exit /b %ERROR_STATUS%


:: ============================================================================
:DOWNLOAD__NAME_PATH_URL

:: Downloads component.
::
:: %~1 - Name.
:: %~2 - Full download path.
:: %~3 - Download URL.

setlocal
set "SECTION=DOWNLOAD__NAME_PATH_URL"

if "%~3"=="" (
    set "ERROR_STATUS=1"
    echo {ERROR} Missing required parameters.
    echo {INFO}  USAGE: call :DOWNLOAD__NAME_PATH_URL "%NAME%" "%DISTRO%" "%URL%"
    goto :DOWNLOAD_EXIT
)

set "NAME=%~1"
set "TARGET=%~2"
set "URL=%~3"
set "ERROR_STATUS=0"

if not exist "%TARGET%" (
    echo {INFO} ===== Downloading %NAME% =====
    curl.exe -fL --retry 3 --output "%TARGET%" %URL%
    set "ERROR_STATUS=!ERRORLEVEL!"
    if "!ERROR_STATUS!"=="0" (
        echo {INFO} ----- Downloaded %NAME% -----
        echo {INFO} "%TARGET%"
    ) else (
        echo {ERROR} %NAME% download failed. Error Code: !ERROR_STATUS!.
    )
) else (
    echo {INFO} ===== Using previously downloaded %NAME% =====
)

:DOWNLOAD_EXIT

echo ~~~~~ %SECTION% ~~~~~
echo:
endlocal && set "ERROR_STATUS=%ERROR_STATUS%" && exit /b %ERROR_STATUS%


:: ============================================================================
:EXTRACT__NAME_FLAG_SRC_DST

:: Extracts archive using Windows Tar.
::
:: %~1 - Name.
:: %~2 - Flag - file or directory. If exists, use previously extracted files.
:: %~3 - Archive path - MUST exist.
:: %~4 - Extraction directory path - MUST exist.

setlocal
set "SECTION=EXTRACT__NAME_FLAG_SRC_DST"

if "%~4"=="" (
    set "ERROR_STATUS=1"
    echo {ERROR} Missing required parameters.
    set "CLI=call :EXTRACT__NAME_FLAG_SRC_DST "%NAME%" "%FLAG%" "%SRC%" "%DST%""
    echo {INFO}  USAGE: !CLI!
    goto :EXTRACT_EXIT
)

set "NAME=%~1"
set "FLAG=%~2"
set "SRC=%~3"
set "DST=%~4"
set "ERROR_STATUS=0"

if not exist "%SRC%" (
    set "ERROR_STATUS=1"
    echo {ERROR} Archive "%SRC%" not found.
    goto :EXTRACT_EXIT
)

if not exist "%DST%" (
    set "ERROR_STATUS=1"
    echo {ERROR} Directory "%DST%" not found.
    goto :EXTRACT_EXIT
)

if not exist "%FLAG%" (
    echo {INFO} ===== Extracting %NAME% =====
    cd /d "%DST%"
    "%TAR%" -xf "%SRC%"
    set "ERROR_STATUS=!ERRORLEVEL!"
    if "!ERROR_STATUS!"=="0" (
        echo {INFO} ----- Extracted %NAME% -----
    ) else (
        echo {ERROR} Failed to extract %NAME%. Error Code: !ERROR_STATUS!.
    )
) else (
    echo {INFO} ===== Using previously extracted %NAME% =====
)

:EXTRACT_EXIT

echo ~~~~~ %SECTION% ~~~~~
echo:
endlocal && set "ERROR_STATUS=%ERROR_STATUS%" && exit /b %ERROR_STATUS%
:: ============================================================================


:CORE_ENV

set "SECTION=CORE_ENV"

set "TAR=%windir%\System32\tar.exe"

set "TOOLDIR="
if exist "%~dp0patch_sqlite_misc_autoext.tcl" (
    set "TOOLDIR=%~dp0"
    set "TOOLDIR=%TOOLDIR:~0,-1%"
) else if exist "%~dp0tool\patch_sqlite_misc_autoext.tcl" (
    set "TOOLDIR=%~dp0tool"
) else if exist "%~dp0tools\patch_sqlite_misc_autoext.tcl" (
    set "TOOLDIR=%~dp0tools"
) else if exist "%~dp0extra\patch_sqlite_misc_autoext.tcl" (
    set "TOOLDIR=%~dp0extra"
)
if not defined TOOLDIR (
    echo {ERROR} Failed to locate patch_sqlite_misc_autoext.tcl.
    exit /b 1
)
echo {INFO} TOOLDIR: %TOOLDIR%.

cd /d "%TOOLDIR%\.."
set "PROJDIR=%CD%"
echo {INFO} PROJDIR: %PROJDIR%.

set "OPT_XTRA="
if not defined USE_ICU      (set "USE_ICU=1")
if not defined USE_ZLIB     (set "USE_ZLIB=1")
if not defined SQLITE_EXTRA (set "SQLITE_EXTRA=1")

set "MSG=USE_ICU:      %USE_ICU% - ICU is"
if "%USE_ICU%"=="0" (
    set "MSG=%MSG% OFF."
) else (
    set "MSG=%MSG% ON."
)
echo %MSG%

set "MSG=USE_ZLIB:     %USE_ZLIB% - ZLIB is"
if "%USE_ZLIB%"=="0" (
    set "MSG=%MSG% OFF."
) else (
    set "MSG=%MSG% ON."
)
echo %MSG%

set "MSG=SQLITE_EXTRA: %SQLITE_EXTRA% - Misc SQLite Extensions Extra is"
if "%SQLITE_EXTRA%"=="0" (
    set "MSG=%MSG% OFF."
) else (
    set "MSG=%MSG% ON."
)
echo %MSG%

set "OUT=%PROJDIR%\out"
call :MKDIR__DIR "%OUT%" || exit /b !ERRORLEVEL!
set "STDOUTLOG=%OUT%\stdout.log"
set "STDERRLOG=%OUT%\stderr.log"
del /Q "%STDOUTLOG%" 2>nul
del /Q "%STDERRLOG%" 2>nul
set "CACHEDIR=%OUT%\cache"
call :MKDIR__DIR "%CACHEDIR%" || exit /b !ERRORLEVEL!
set "SQLITEDIR=%OUT%\sqlite"
call :MKDIR__DIR "%SQLITEDIR%" || exit /b !ERRORLEVEL!
set "THIRDDIR=%SQLITEDIR%\compat"
call :MKDIR__DIR "%THIRDDIR%" || exit /b !ERRORLEVEL!
set "BUILDDIR=%OUT%\build"
if "%USE_TEST%"=="1" (set "BUILDDIR=%BUILDDIR%_test")
call :MKDIR__DIR "%BUILDDIR%" || exit /b !ERRORLEVEL!
set "TSRC=%BUILDDIR%\tsrc"
call :MKDIR__DIR "%TSRC%" || exit /b !ERRORLEVEL!
set "INCDIR=%OUT%\include"
call :MKDIR__DIR "%INCDIR%" || exit /b !ERRORLEVEL!
set "LIBDIR_IMPORT=%OUT%\lib\import"
call :MKDIR__DIR "%LIBDIR_IMPORT%" || exit /b !ERRORLEVEL!
set "LIBDIR_STATIC=%OUT%\lib\static"
call :MKDIR__DIR "%LIBDIR_STATIC%" || exit /b !ERRORLEVEL!
set "BINDIR=%OUT%\bin"
call :MKDIR__DIR "%BINDIR%" || exit /b !ERRORLEVEL!

echo ~~~~~ %SECTION% ~~~~~
echo:
exit /b 0


:: ============================================================================
:ZLIB_OPTIONS

set "SECTION=ZLIB_OPTIONS"

set "ZLIBDIR=%THIRDDIR%\zlib"

echo ~~~~~ %SECTION% ~~~~~
echo:
exit /b 0


:: ============================================================================
:ICU_OPTIONS

set "SECTION=ICU_OPTIONS"

if /I "%VSCMD_ARG_TGT_ARCH%"=="x64" (set "ARCH=64") else (set "ARCH=")
set "ICUDIR=%THIRDDIR%\icu"
set "ICUINCDIR=%ICUDIR%\include"
set "ICULIBDIR=%ICUDIR%\lib%ARCH%"
set "ICUBINDIR=%ICUDIR%\bin%ARCH%"

set OPT_XTRA=%OPT_XTRA% -DSQLITE_ENABLE_ICU_COLLATIONS

echo ~~~~~ %SECTION% ~~~~~
echo:
exit /b 0


:: ============================================================================
:TCL_OPTIONS

set "SECTION=TCL_OPTIONS"

set "TCLBIN="
for /f "usebackq delims=" %%P in (`where tclsh.exe 2^>nul`) do (
    set "TCLBIN=%%~P"
)
if exist "%TCLBIN%" (
    set "TCL_HOME=%TCLBIN:\bin\tclsh.exe=%"
    echo Using TCL on Path.
    goto :TCL_FOUND
) else (set "TCLBIN=")
if exist "%TCL_HOME%\bin\tclsh.exe" (
    echo Using TCL on Path.
    goto :TCL_FOUND
)

if exist "%systemDrive%\dev\TCL\bin\tclsh.exe" (
    set "TCL_HOME=%systemDrive%\dev\TCL"
) else if exist "%ProgramFiles%\TCL\bin\tclsh.exe" (
    set "TCL_HOME=%ProgramFiles%\TCL"
) else if exist "C:\dev\TCL\bin\tclsh.exe" (
    set "TCL_HOME=C:\dev\TCL"
) else if exist "G:\dev\TCL\bin\tclsh.exe" (
    set "TCL_HOME=G:\dev\TCL"
) else if exist "H:\dev\TCL\bin\tclsh.exe" (
    set "TCL_HOME=H:\dev\TCL"
)

if not exist "%TCL_HOME%\bin\tclsh.exe" (
    echo TCL not found.
    set "ERROR_STATUS=1"
    exit /b !ERROR_STATUS!
)

:TCL_FOUND

echo TCL found. TCL_HOME: "%TCL_HOME%"
if not defined TCLBIN (
    set "Path=%TCL_HOME%\bin;%Path%"
    echo Added TCL to PATH.
)
set "TCLSH_CMD=%TCL_HOME%\bin\tclsh.exe"
echo TCLSH_CMD = __%TCLSH_CMD%__
echo puts "TCL version: [info patchlevel]" | "%TCLSH_CMD%"
set "TCLSH_CMD="%TCLSH_CMD%""
set "TCLDIR=%TCL_HOME%"

echo ~~~~~ %SECTION% ~~~~~
echo:
exit /b 0


:: ============================================================================
:BUILD_OPTIONS

set "SECTION=BUILD_OPTIONS"

set "SQLITE_MAKEFILE=%SQLITEDIR%\Makefile.msc"
set "SESSION=1"
set "RBU=1"
set "API_ARMOR=1"
set "SYMBOLS=0"
set "WITHOUT_JIMSH=1"
set "EXTRA_SRC="

set OPT_XTRA=%OPT_XTRA% ^
    -DSQLITE_ENABLE_NORMALIZE ^
    -DSQLITE_ENABLE_FTS4=1 ^
    -DSQLITE_ENABLE_FTS3_PARENTHESIS ^
    -DSQLITE_ENABLE_FTS3_TOKENIZER ^
    -DSQLITE_ENABLE_EXPLAIN_COMMENTS=1 ^
    -DSQLITE_ENABLE_OFFSET_SQL_FUNC=1 ^
    -DSQLITE_ENABLE_QPSG ^
    -DSQLITE_ENABLE_STAT4 ^
    -DSQLITE_DQS=0 ^
    -DSQLITE_LIKE_DOESNT_MATCH_BLOBS ^
    -DSQLITE_MAX_EXPR_DEPTH=100 ^
    -DSQLITE_OMIT_DEPRECATED ^
    -DSQLITE_DEFAULT_FOREIGN_KEYS=1 ^
    -DSQLITE_DEFAULT_SYNCHRONOUS=1 ^
    -DSQLITE_USE_URI=1 ^
    -DSQLITE_SOUNDEX

echo ~~~~~ %SECTION% ~~~~~
echo:
exit /b 0


:: ============================================================================
:MAKE_DEBUG

setlocal
set "SECTION=MAKE_DEBUG"

set "TARGET="
if "%~1"=="env"      (set "TARGET=%~1")
if "%~1"=="tcl-test" (set "TARGET=%~1")
if "%~1"=="tcl-env"  (set "TARGET=%~1")

if defined TARGET (
    nmake "TOP=%SQLITEDIR%" /f "%SQLITEDIR%\Makefile.msc" %TARGET%
    exit /b 100
)

echo ~~~~~ %SECTION% ~~~~~
echo:
endlocal && exit /b 0


:: ============================================================================
:CHECK_PREREQUISITES

setlocal
set "SECTION=CHECK_PREREQUISITES"

echo ===== Verifying environment =====

if "/%VisualStudioVersion%/"=="//" (
    echo %%VisualStudioVersion%% is not set. Run this script from an MSVC shell.
    set "ERROR_STATUS=1"
) else (
    echo VisualStudioVersion=%VisualStudioVersion%
)

if "/%VSINSTALLDIR%/"=="//" (
    echo %%VSINSTALLDIR%% is not set. Run this script from an MSVC shell.
    set "ERROR_STATUS=1"
) else (
    echo VSINSTALLDIR="%VSINSTALLDIR%"
)

if "/%VCINSTALLDIR%/"=="//" (
    echo %%VSINSTALLDIR%% is not set. Run this script from an MSVC shell.
    set "ERROR_STATUS=1"
) else (
    echo VCINSTALLDIR=%VCINSTALLDIR%
)

set "CommandLocation="
for /f "usebackq delims=" %%I in (`where cl.exe 2^>nul`) do (
    if "/!CommandLocation!/"=="//" (set "CommandLocation=%%~I")
)
if "/%CommandLocation%/"=="//" (
    echo cl.exe is not found. Run this script from an MSVC shell.
    set "ERROR_STATUS=1"
) else (
    echo CL_EXE=%CommandLocation%
)

set "CommandLocation="
for /f "usebackq delims=" %%I in (`where nmake.exe 2^>nul`) do (
    if "/!CommandLocation!/"=="//" (set "CommandLocation=%%~i")
)
if "/%CommandLocation%/"=="//" (
    echo nmake.exe is not found. Run this script from an MSVC shell.
    set "ERROR_STATUS=1"
) else (
    echo NMAKE_EXE=%CommandLocation%
)

set "CommandLocation="
for /f "usebackq delims=" %%I in (`where tclsh.exe 2^>nul`) do (
    if "/!CommandLocation!/"=="//" (set "CommandLocation=%%I")
)
if "/%CommandLocation%/"=="//" (
    echo tclsh.exe is not found. TCL is required and must be in the path.
    set "ERROR_STATUS=1"
) else (
    echo TCLSH_EXE=%CommandLocation%
)

if "%ERROR_STATUS%"=="0" (
    echo ----- Verified  environment -----
) else (
    echo ----- Environment is NOT OK -----
)

echo ~~~~~ %SECTION% ~~~~~
echo:
endlocal && set "ERROR_STATUS=%ERROR_STATUS%" && exit /b %ERROR_STATUS%


:: ============================================================================
:SQLITE_DOWNLOAD

setlocal
set "SECTION=SQLITE_DOWNLOAD"

set "DISTRO=%CACHEDIR%\sqlite.zip"
set "URL=https://sqlite.org/src/zip/sqlite.zip"

call :DOWNLOAD__NAME_PATH_URL SQLite "%DISTRO%" "%URL%"
set "ERROR_STATUS=%ERRORLEVEL%"

echo ~~~~~ %SECTION% ~~~~~
echo:
endlocal && set "ERROR_STATUS=%ERROR_STATUS%" && exit /b %ERROR_STATUS%


:: ============================================================================
:SQLITE_EXTRACT

setlocal
set "SECTION=SQLITE_EXTRACT"

set "FLAG=%SQLITE_MAKEFILE%"
set "SRC=%CACHEDIR%\sqlite.zip"
set "DST=%OUT%"

call :EXTRACT__NAME_FLAG_SRC_DST SQLite "%FLAG%" "%SRC%" "%DST%"
set "ERROR_STATUS=%ERRORLEVEL%"

echo ~~~~~ %SECTION% ~~~~~
echo:
endlocal && set "ERROR_STATUS=%ERROR_STATUS%" && exit /b %ERROR_STATUS%


:: ============================================================================
:ZLIB_DOWNLOAD

setlocal
set "SECTION=ZLIB_DOWNLOAD"

set "DISTRO=%CACHEDIR%\zlib.tar.gz"
set "URL=https://zlib.net/current/zlib.tar.gz"

call :DOWNLOAD__NAME_PATH_URL ZLIB "%DISTRO%" "%URL%"
set "ERROR_STATUS=%ERRORLEVEL%"

echo ~~~~~ %SECTION% ~~~~~
echo:
endlocal && set "ERROR_STATUS=%ERROR_STATUS%" && exit /b %ERROR_STATUS%


:: ============================================================================
:ZLIB_EXTRACT

setlocal
set "SECTION=ZLIB_EXTRACT"

set "FLAG=%ZLIBDIR%\win32\Makefile.msc"
set "SRC=%CACHEDIR%\zlib.tar.gz"
set "DST=%THIRDDIR%"

call :EXTRACT__NAME_FLAG_SRC_DST ZLIB "%FLAG%" "%SRC%" "%DST%"
set "ERROR_STATUS=%ERRORLEVEL%"
if "%ERROR_STATUS%"=="0" (
    move /Y "%THIRDDIR%\zlib-*" "%THIRDDIR%\zlib"
)

echo ~~~~~ %SECTION% ~~~~~
echo:
endlocal && set "ERROR_STATUS=%ERROR_STATUS%" && exit /b %ERROR_STATUS%


:: ============================================================================
:ZLIB_BUILD

setlocal
set "SECTION=ZLIB_BUILD"

if not exist "%ZLIBDIR%\zlib1.dll" (
    echo {INFO} ===== Building ZLIB =====
    cd /d "%SQLITEDIR%"
    nmake /nologo "TOP=%SQLITEDIR%" "ZLIBLIB=all" /f "%SQLITE_MAKEFILE%" zlib
    set "ERROR_STATUS=!ERRORLEVEL!"
    if "!ERROR_STATUS!"=="0" (
        echo {INFO} ----- Built ZLIB -----
    ) else (
        echo {ERROR} Failed to build ZLIB. Error Code: !ERROR_STATUS!.
    )
) else (
    echo {INFO} ===== Using previously built ZLIB =====
)

echo ~~~~~ %SECTION% ~~~~~
echo:
endlocal && set "ERROR_STATUS=%ERROR_STATUS%" && exit /b %ERROR_STATUS%


:: ============================================================================
:ICU_DOWNLOAD

setlocal
set "SECTION=ICU_DOWNLOAD"

set "DISTRO=%CACHEDIR%\icu4c-X-sources.zip"
set "URL="

set "ICU_REPO_META=%CACHEDIR%\icu_repo_meta.json"
if not exist "%ICU_REPO_META%" (
    curl.exe -s --output "%ICU_REPO_META%" ^
             https://api.github.com/repos/unicode-org/icu/releases/latest
)
set "ERROR_STATUS=%ERRORLEVEL%"
if "!ERROR_STATUS!"=="0" (
    echo ----- Downloaded ICU release meta -----
) else (
    del /Q "%ICU_REPO_META%"
    echo {ERROR} Failed to download ICU release meta.
    goto :ICU_DOWNLOAD_EXIT
)

set "CLI=findstr /R /C:"browser_download_url.*icu4c-.*-s.*rc.*\.zip" "%ICU_REPO_META%""
for /f "usebackq tokens=2" %%I in (`%CLI%`) do (
    set "BUFFER=%%~I"
    if "!BUFFER:~-3!"=="zip" (set "URL=!BUFFER!")
    set "BUFFER="
)
if defined URL (
    echo {INFO} ICU release URL: %URL%
) else (
    set "ERROR_STATUS=1"
    echo {ERROR} Failed to locate ICU release URL.
    goto :ICU_DOWNLOAD_EXIT
)

call :DOWNLOAD__NAME_PATH_URL ICU "%DISTRO%" "%URL%"
set "ERROR_STATUS=%ERRORLEVEL%"

:ICU_DOWNLOAD_EXIT

echo ~~~~~ %SECTION% ~~~~~
echo:
endlocal && set "ERROR_STATUS=%ERROR_STATUS%" && exit /b %ERROR_STATUS%


:: ============================================================================
:ICU_EXTRACT

setlocal
set "SECTION=ICU_EXTRACT"

set "FLAG=%ICUDIR%\source\allinone\allinone.sln"
set "SRC=%CACHEDIR%\icu4c-X-sources.zip"
set "DST=%THIRDDIR%"

call :EXTRACT__NAME_FLAG_SRC_DST ICU "%FLAG%" "%SRC%" "%DST%"
set "ERROR_STATUS=%ERRORLEVEL%"

echo ~~~~~ %SECTION% ~~~~~
echo:
endlocal && set "ERROR_STATUS=%ERROR_STATUS%" && exit /b %ERROR_STATUS%


:: ============================================================================
:ICU_BUILD

setlocal
set "SECTION=ICU_BUILD"

if not exist "%ICUBINDIR%\icuinfo.exe" (
    echo {INFO} ===== Building ICU =====
    cd /d "%ICUDIR%"
    msbuild "%ICUDIR%\source\allinone\allinone.sln" ^
            /m /p:Configuration=Release /p:SkipUWP=true 1>>"%STDOUTLOG%" 2>>"%STDERRLOG%"
    set "ERROR_STATUS=!ERRORLEVEL!"
    if "!ERROR_STATUS!"=="0" (
        echo {INFO} ----- Built ICU -----
    ) else if exist "%ICUBINDIR%\icuinfo.exe" (
        echo {INFO} ----- Built ICU -----
        set "ERROR_STATUS=0"
    ) else (
        echo {ERROR} Failed to build ICU. Error Code: !ERROR_STATUS!.
    )
) else (
    echo {INFO} ===== Using previously built ICU =====
)

echo ~~~~~ %SECTION% ~~~~~
echo:
endlocal && set "ERROR_STATUS=%ERROR_STATUS%" && exit /b %ERROR_STATUS%


:: ============================================================================
:SQLITE_BUILD_INIT

set "SECTION=SQLITE_BUILD_INIT"

cd /d "%BUILDDIR%" || exit /b !ERRORLEVEL!

nmake /nologo "TOP=%SQLITEDIR%" /f "%SQLITE_MAKEFILE%" .target_source
set "ERROR_STATUS=%ERRORLEVEL%"

echo ~~~~~ %SECTION% ~~~~~
echo:
exit /b %ERROR_STATUS%


:: ============================================================================
:EXTRA_SRC_STOCK

set "SECTION=EXTRA_SRC_STOCK"

set OPT_XTRA=%OPT_XTRA%^
    -DSQLITE_EXTRA_AUTOEXT=sqlite3ExtraAutoExtInit ^
    -DSQLITE_ENABLE_COMPRESS ^
    -DSQLITE_ENABLE_CSV      ^
    -DSQLITE_ENABLE_DECIMAL  ^
    -DSQLITE_ENABLE_FUZZER   ^
    -DSQLITE_ENABLE_NOOP     ^
    -DSQLITE_ENABLE_PREFIXES ^
    -DSQLITE_ENABLE_REGEXP   ^
    -DSQLITE_ENABLE_REMEMBER ^
    -DSQLITE_ENABLE_ROT      ^
    -DSQLITE_ENABLE_SERIES   ^
    -DSQLITE_ENABLE_SHA      ^
    -DSQLITE_ENABLE_SHATHREE ^
    -DSQLITE_ENABLE_SQLAR    ^
    -DSQLITE_ENABLE_UINT     ^
    -DSQLITE_ENABLE_UUID     

cd /d "%SQLITEDIR%\ext\misc"

set MISC_EXT=^
    "compress.c"  ^
    "csv.c"       ^
    "decimal.c"   ^
    "fuzzer.c"    ^
    "noop.c"      ^
    "prefixes.c"  ^
    "regexp.c"    ^
    "remember.c"  ^
    "rot13.c"     ^
    "series.c"    ^
    "sha1.c"      ^
    "shathree.c"  ^
    "sqlar.c"     ^
    "uint.c"      ^
    "uuid.c"

echo {INFO} ========== Copy MISC_EXT ===========
"%TCLSH_CMD%" "%SQLITEDIR%\tool\cp.tcl" %MISC_EXT% "%TSRC%" || exit /b !ERRORLEVEL!

echo:

echo {INFO} ========== Patch MISC_EXT ===========
cd /d "%TSRC%"
"%TCLSH_CMD%" "%TOOLDIR%\patch_sqlite_misc_autoext.tcl" %MISC_EXT% || exit /b !ERRORLEVEL!

echo:

echo {INFO} ========== Bundle MISC_EXT ===========
"%TCLSH_CMD%" "%TOOLDIR%\bundle_extra_src.tcl" %MISC_EXT% || exit /b !ERRORLEVEL!

echo {INFO} ========== Set EXTRA_SRC for extended SQLite build ===========

set EXTRA_SRC=%EXTRA_SRC% ^
    ""%TSRC%\compress.c""      ^
    ""%TSRC%\csv.c""           ^
    ""%TSRC%\decimal.c""       ^
    ""%TSRC%\fuzzer.c""        ^
    ""%TSRC%\noop.c""          ^
    ""%TSRC%\prefixes.c""      ^
    ""%TSRC%\regexp.c""        ^
    ""%TSRC%\remember.c""      ^
    ""%TSRC%\rot13.c""         ^
    ""%TSRC%\series.c""        ^
    ""%TSRC%\sha1.c""          ^
    ""%TSRC%\shathree.c""      ^
    ""%TSRC%\sqlar.c""         ^
    ""%TSRC%\uint.c""          ^
    ""%TSRC%\uuid.c""          ^
    ""%TSRC%\misc_ext_init.c""

echo ~~~~~ %SECTION% ~~~~~
echo:
exit /b %ERRORLEVEL%


:: ============================================================================
:SQLITE_BUILD

set "SECTION=SQLITE_BUILD"

cd /d "%BUILDDIR%" || exit /b !ERRORLEVEL!

nmake /nologo "EXTRA_SRC=%EXTRA_SRC%" "TOP=%SQLITEDIR%" /f "%SQLITE_MAKEFILE%" sqlite3.def
if not "%ERRORLEVEL%"=="0" (
    echo {ERROR} Error creating sqlite3.def
    exit /b %ERRORLEVEL%
)

:: ----- Replace sqlite3.def -----

echo EXPORTS >"%BUILDDIR%\sqlite3.def"

set "PATTERN=^[ ]*[0-9][0-9]*[ ]*[A-Za-z0-9][A-Za-z0-9]*_"
for /f "usebackq tokens=2 delims=@ " %%A in (
    `dumpbin /linkermember:2 libsqlite3.lib ^| findstr /R /C:"%PATTERN%"`
) do (
    echo %%A
) >>"%BUILDDIR%\exports.txt"
if not "%ERRORLEVEL%"=="0" (
    echo {ERROR} Error updating sqlite3.def
    exit /b %ERRORLEVEL%
)
type "%BUILDDIR%\exports.txt" | sort >>"%BUILDDIR%\sqlite3.def"
del /Q "%BUILDDIR%\exports.txt"

nmake /nologo "EXTRA_SRC=%EXTRA_SRC%" "TOP=%SQLITEDIR%" /f "%SQLITE_MAKEFILE%" %*
if not "%ERRORLEVEL%"=="0" (
    echo {ERROR} Error building SQLite.
    exit /b %ERRORLEVEL%
)

:: ----- Replace sqlite3.lib -----

lib /def:"%BUILDDIR%\sqlite3.def" /out:"%BUILDDIR%\sqlite3.lib" /machine:%VSCMD_ARG_TGT_ARCH%
if not "%ERRORLEVEL%"=="0" (
    echo {ERROR} Error updating static SQLite lib.
    exit /b %ERRORLEVEL%
)

echo ~~~~~ %SECTION% ~~~~~
echo:
exit /b %ERRORLEVEL%


:: ============================================================================
:COLLECT_BINARIES

set "SECTION=COLLECT_BINARIES"

echo ========== Collecting binaries ===========
del /Q "%BINDIR%\*" 2>nul
if exist "%BUILDDIR%\sqlite3.dll"    copy /Y "%BUILDDIR%\sqlite3.dll"    "%BINDIR%"
if exist "%BUILDDIR%\sqlite3.exe"    copy /Y "%BUILDDIR%\sqlite3.exe"    "%BINDIR%"
if exist "%BUILDDIR%\sqlite3.def"    copy /Y "%BUILDDIR%\sqlite3.def"    "%LIBDIR_IMPORT%"
if exist "%BUILDDIR%\sqlite3.lib"    copy /Y "%BUILDDIR%\sqlite3.lib"    "%LIBDIR_IMPORT%"
if exist "%BUILDDIR%\libsqlite3.lib" copy /Y "%BUILDDIR%\libsqlite3.lib" "%LIBDIR_STATIC%"
copy /Y "%BUILDDIR%\sqlite3*.h" "%INCDIR%"
copy /Y "%PROJDIR%\src\*.h" "%INCDIR%"
if "%USE_ICU%"=="1" (copy /Y "%ICUBINDIR%\icu*.dll" "%BINDIR%")
if "%USE_ZLIB%"=="1" (if exist "%ZLIBDIR%\zlib1.dll" copy /Y "%ZLIBDIR%\zlib1.dll" "%BINDIR%")
echo ---------- Copied  binaries -----------

echo ~~~~~ %SECTION% ~~~~~
echo:
exit /b 0
