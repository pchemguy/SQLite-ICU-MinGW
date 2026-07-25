@echo off
:: =============================================================================
:: SCRIPT
::   build_sqlite_msvc.bat
::
:: PURPOSE
::   Downloads, prepares, builds, and packages a customized SQLite distribution
::   on Windows using the Microsoft Visual C++ toolchain and SQLite's
::   Makefile.msc build system.
::
::   The build may include:
::
::     - the SQLite command-line shell;
::     - sqlite3.dll and its module-definition file;
::     - ZLIB support;
::     - ICU collation support;
::     - selected SQLite ext/misc modules compiled directly into the SQLite
::       library and registered as automatic extensions;
::     - additional compile-time SQLite features configured through OPT_XTRA.
::
::   Build artifacts and required runtime DLLs are collected into a dedicated
::   bin directory after a successful build.
::
:: REQUIREMENTS
::   Run this script from a Microsoft Visual C++ developer command prompt whose
::   architecture matches the desired output architecture.
::
::   Required tools:
::
::     cl.exe
::       Microsoft C/C++ compiler.
::
::     nmake.exe
::       Microsoft Program Maintenance Utility used by Makefile.msc.
::
::     msbuild.exe
::       Required when ICU is enabled.
::
::     tclsh.exe
::       Required by SQLite's source-generation workflow and by the custom Tcl
::       scripts that prepare the embedded ext/misc modules.
::
::     curl.exe
::       Used to download SQLite, ZLIB, ICU release metadata, and ICU sources.
::
::     tar.exe
::       The Windows system tar implementation is used to extract archives.
::
::   Microsoft Visual C++ Build Tools may be installed using either:
::
::     - the standalone Build Tools installer:
::         https://go.microsoft.com/fwlink/?LinkId=691126
::
::     - the Visual Studio installer, including Visual Studio Community:
::         https://visualstudio.microsoft.com/downloads
::
::   Tcl must either:
::
::     - be available through PATH;
::     - be identified by TCL_HOME; or
::     - be installed in one of the fallback locations recognized by
::       :TCL_OPTIONS.
::
:: INVOCATION
::   From an initialized MSVC developer command prompt:
::
::     build_sqlite_msvc.cmd [NMAKE_TARGET_OR_OPTION ...]
::
::   Arguments not handled as special diagnostic targets are forwarded to the
::   final SQLite nmake invocation.
::
::   Examples:
::
::     build_sqlite_msvc.bat
::
::       Performs the default configured SQLite build.
::
::     build_sqlite_msvc.cmd clean
::
::       Passes "clean" to the final Makefile.msc invocation.
::
::     build_sqlite_msvc.cmd sqlite3.dll
::
::       Requests the named Makefile.msc target.
::
:: SPECIAL DIAGNOSTIC TARGETS
::   The following first arguments are executed immediately against SQLite's
::   Makefile.msc and then terminate the script without running the download,
::   dependency-build, packaging, or normal SQLite-build stages:
::
::     env
::     tcl-env
::
:: DIRECTORY LAYOUT
::   All paths are derived from the directory containing this script.
::
::     <script directory>\
::       build_sqlite_msvc.bat
::       extra\
::         patch_sqlite_misc_autoext.tcl
::         bundle_extra_src.tcl
::
::       sqlite.zip
::       zlib.tar.gz
::       icu4c-X-sources.zip
::       icu_release_meta.json
::
::       sqlite\
::         Makefile.msc
::         compat\
::           zlib\
::           icu\
::         ext\
::           misc\
::
::       build\
::         Intermediate SQLite build products.
::
::       bin\
::         Final executables, libraries, definition files, and dependency DLLs.
::
:: DOWNLOAD SOURCES
::   SQLite:
::
::     https://sqlite.org/src/zip/sqlite.zip
::
::   The URL currently refers to a source-tree snapshot rather than a
::   version-numbered release archive. Once downloaded, sqlite.zip is reused
::   until it is manually deleted.
::
::   ZLIB:
::
::     https://zlib.net/current/zlib.tar.gz
::
::   ICU:
::
::     The script queries the latest ICU GitHub release metadata:
::
::       https://api.github.com/repos/unicode-org/icu/releases/latest
::
::     It extracts the ICU4C source ZIP URL from that metadata and stores the
::     downloaded archive under the stable local name:
::
::       icu4c-X-sources.zip
::
:: BUILD CONFIGURATION
::   Configuration is controlled primarily through environment variables set
::   near the beginning of :MAIN and in the option subroutines.
::
::   USE_ICU
::     Enables ICU download, extraction, compilation, SQLite ICU integration,
::     and collection of ICU runtime DLLs.
::
::     Default: 1
::
::     Set to 0 before the ICU stages are evaluated to omit ICU.
::
::   USE_ZLIB
::     Enables SQLite Makefile.msc ZLIB integration and collection of
::     zlib1.dll.
::
::     Default: 1
::
::   USE_SQLAR
::     Enables SQLite's SQL archive integration where supported by
::     Makefile.msc.
::
::     Default: 1
::
::   SQLITE_EXTRA
::     Controls preparation and inclusion of the selected ext/misc modules.
::
::     Default: 1
::
::     Set to 0 to skip :EXTRA_SRC_PREPARE.
::
::   OPT_XTRA
::     Accumulates preprocessor definitions passed through SQLite's
::     Makefile.msc build.
::
::   EXTRA_SRC
::     Contains additional C translation units to be included in SQLite's
::     source-generation and compilation workflow.
::
:: SQLITE BUILD OPTIONS
::   The script enables the following SQLite Makefile.msc options:
::
::     SESSION=1
::     RBU=1
::     API_ARMOR=1
::     SYMBOLS=0
::     NO_TCL=1
::     WITHOUT_JIMSH=1
::
::   NO_TCL disables the SQLite Tcl extension as a final build product. Tcl is
::   nevertheless still required as a build-time tool.
::
:: EMBEDDED EXT/MISC MODULES
::   When SQLITE_EXTRA is nonzero, :EXTRA_SRC_PREPARE prepares selected
::   SQLite ext/misc modules for static inclusion. The preparation process has
::   two stages:
::
::     1. patch_sqlite_misc_autoext.tcl
::
::        Adapts the selected loadable-extension sources for compilation inside
::        SQLite and generates the aggregate automatic-extension initializer.
::
::     2. bundle_extra_src.tcl
::
::        Expands local source dependencies so the prepared modules can
::        participate in SQLite's generated-source and amalgamation workflow.
::
::   The generated aggregate initializer is selected with:
::
::     SQLITE_EXTRA_AUTOEXT=sqlite3ExtraAutoExtInit
::
::   The corresponding module feature definitions are also appended to OPT_XTRA.
::
::   The prepared source files and misc_ext_init.c are supplied through
::   EXTRA_SRC to the final nmake invocation.
::
:: BUILD STAGES
::   The normal workflow performs the following stages in order:
::
::     1. Initialize ICU, Tcl, ZLIB, and SQLite build options.
::     2. Recognize and execute an optional diagnostic Makefile.msc target.
::     3. Download sqlite.zip when it is not already present.
::     4. Extract SQLite when sqlite\Makefile.msc is not already present.
::     5. Download and extract ZLIB when required files are absent.
::     6. Build zlib1.dll through SQLite's Makefile.msc ZLIB target.
::     7. When ICU is enabled:
::          - obtain current ICU release metadata;
::          - locate the ICU4C source archive;
::          - download and extract ICU;
::          - build ICU using its allinone Visual Studio solution.
::     8. When SQLITE_EXTRA is enabled:
::          - patch the selected ext/misc modules;
::          - bundle their local includes;
::          - construct EXTRA_SRC.
::     9. Run SQLite's Makefile.msc from the separate build directory.
::    10. Move primary SQLite artifacts and copy dependency DLLs into bin.
::
:: ARCHITECTURE
::   ICU output directories are selected from VSCMD_ARG_TGT_ARCH.
::     VSCMD_ARG_TGT_ARCH=x64
::       ICU libraries and binaries are expected in lib64 and bin64.
::     Any other value
::       ICU libraries and binaries are expected in lib and bin.
::
::   The script therefore must be launched from the correct x86 or x64 MSVC
::   developer environment before building.
::
:: INCREMENTAL AND REUSE BEHAVIOR
::   The workflow reuses existing downloads, extracted source trees, and built
::   dependencies when their expected marker files are present.
::
::   Important marker files include:
::
::     sqlite\Makefile.msc
::     sqlite\compat\zlib\win32\Makefile.msc
::     sqlite\compat\zlib\zlib1.dll
::     sqlite\compat\icu\source\allinone\allinone.sln
::     <ICU binary directory>\icuinfo.exe
::
::   To force a fresh operation, remove the corresponding archive, extracted
::   directory, build output, or marker file before rerunning the script.
::
::   The custom ext/misc preparation scripts are expected to be safe for the
::   source state in which this build invokes them. Reusing an already modified
::   SQLite source tree depends on those scripts preserving their documented
::   idempotency guarantees.
::
:: OUTPUT
::   The final bin directory may contain:
::
::     sqlite3.dll
::     sqlite3.exe
::     sqlite3.def
::     zlib1.dll
::     ICU runtime DLLs matching icu*.dll
::
::   Existing files in bin are deleted before newly built artifacts are collected.
::
:: ERROR HANDLING
::   Each major stage returns its command status through ERRORLEVEL.
::
::   The main routine stops at the first failing stage and exits with that
::   nonzero status. Successful completion returns exit code 0.
::
::   Commands executed inside parenthesized blocks use delayed expansion where
::   required so the current ERRORLEVEL is propagated correctly.
::
::   :COLLECT_BINARIES is intentionally invoked without a fatal error check;
::   individual move and copy commands are conditional on their source files
::   being present.
::
:: OPERATIONAL NOTES
::   - Run the script from MSVC CMD shell, not by invoking it through a
::     noninitialized ordinary command prompt.
::
::   - The script changes its working directory during several stages. Paths
::     used by the workflow are therefore constructed as absolute paths rooted
::     at the script directory.
::
::   - Downloaded archives are deliberately cached. Delete them manually when
::     a newer upstream source archive is required.
::
::   - The SQLite URL used here tracks the upstream source tree. For a strictly
::     reproducible build, replace it with a version-pinned archive and retain
::     that archive with the build inputs.
::
::   - The ICU release lookup depends on the current GitHub release metadata
::     format and on the expected ICU4C source-archive naming convention.
::
::   - ICU is built in Release configuration with UWP projects skipped.
::
::   - sqlite3.exe and sqlite3.dll are built from the same configured SQLite
::     source tree, but the exact Makefile.msc targets produced depend on the
::     arguments forwarded to nmake.
::
:: =============================================================================

:: ============================= BEGIN DISPATCHER =============================
call :MAIN %*

exit /b 0
:: ============================= END   DISPATCHER =============================


:: ================================ BEGIN MAIN ================================
:MAIN

SetLocal EnableExtensions EnableDelayedExpansion

set "ERROR_STATUS=0"

set "TAR=%windir%\System32\tar.exe"
set "BASEDIR=%~dp0"
set "BASEDIR=%BASEDIR:~0,-1%"
set "DISTRODIR=%BASEDIR%\sqlite"
set "SQLITE_MAKEFILE=%DISTRODIR%\Makefile.msc"
set "TOP=%DISTRODIR%"
set "BUILDDIR=%BASEDIR%\build"
set "THIRDDIR=%DISTRODIR%\compat"
set "STDOUTLOG=%BASEDIR%\stdout.log"
set "STDERRLOG=%BASEDIR%\stderr.log"
del "%STDOUTLOG%" 2>nul
del "%STDERRLOG%" 2>nul

set "OPT_XTRA="
if not defined USE_ICU      (set "USE_ICU=1")
if not defined USE_ZLIB     (set "USE_ZLIB=1")
if not defined USE_SQLAR    (set "USE_SQLAR=1")
if not defined SQLITE_EXTRA (set "SQLITE_EXTRA=1")
if not exist "%THIRDDIR%" (cmd /c mkdir "%THIRDDIR%" || exit /b !ERRORLEVEL!)

(
    call :ICU_OPTIONS       || exit /b !ERRORLEVEL!
    call :TCL_OPTIONS       || exit /b !ERRORLEVEL!
    call :BUILD_OPTIONS     || exit /b !ERRORLEVEL!
) 1>>"%STDOUTLOG%" 2>>"%STDERRLOG%"

call :CHECK_PREREQUISITES   || exit /b !ERRORLEVEL!

call :MAKE_DEBUG %*         || exit /b !ERRORLEVEL!
call :SQLITE_DOWNLOAD       || exit /b !ERRORLEVEL!
call :SQLITE_EXTRACT        || exit /b !ERRORLEVEL!
if not "%USE_ZLIB%"=="0" (
    call :ZLIB_DOWNLOAD     || exit /b !ERRORLEVEL!
    call :ZLIB_EXTRACT      || exit /b !ERRORLEVEL!
    call :ZLIB_BUILD        || exit /b !ERRORLEVEL!
)
if not "%USE_ICU%"=="0" (
    call :ICU_DOWNLOAD      || exit /b !ERRORLEVEL!
    call :ICU_EXTRACT       || exit /b !ERRORLEVEL!
    call :ICU_BUILD         || exit /b !ERRORLEVEL!
)
call :FP16_DOWNLOAD         || exit /b !ERRORLEVEL!
call :FP16_EXTRACT          || exit /b !ERRORLEVEL!
if not "%SQLITE_EXTRA%"=="0" (
    call :EXTRA_SRC_PREPARE || exit /b !ERRORLEVEL!
)
call :SQLITE_BUILD %*       || exit /b !ERRORLEVEL!
call :COLLECT_BINARIES

EndLocal

echo:
exit /b 0
:: ================================= END MAIN =================================


:: ============================================================================
:ICU_OPTIONS

if "/%VSCMD_ARG_TGT_ARCH%/" == "/x64/" (set "ARCH=64") else (set "ARCH=")
set "ICUDIR=%THIRDDIR%\icu"
set "ICUINCDIR=%ICUDIR%\include"
set "ICULIBDIR=%ICUDIR%\lib%ARCH%"
set "ICUBINDIR=%ICUDIR%\bin%ARCH%"

set OPT_XTRA=%OPT_XTRA% ^
    -DSQLITE_ENABLE_ICU_COLLATIONS

echo:
exit /b 0


:: ============================================================================
:TCL_OPTIONS

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

echo:
exit /b 0


:: ============================================================================
:BUILD_OPTIONS

set "SESSION=1"
set "RBU=1"
set "API_ARMOR=1"
set "SYMBOLS=0"
set "NO_TCL=1"
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

if not exist "%BUILDDIR%" (mkdir "%BUILDDIR%" || exit /b !ERRORLEVEL!)

echo:
exit /b 0


:: ============================================================================
:MAKE_DEBUG

set "TARGET="
if "%~1"=="env"      (set "TARGET=%~1")
if "%~1"=="tcl-test" (set "TARGET=%~1")
if "%~1"=="tcl-env"  (set "TARGET=%~1")

if defined TARGET (
    nmake "TOP=%DISTRODIR%" /f "%DISTRODIR%\Makefile.msc" %TARGET%
    exit /b 1
)

echo:
exit /b 0


:: ============================================================================
:CHECK_PREREQUISITES

echo ===== Verifying environment =====

if "/%VisualStudioVersion%/"=="//" (
    echo %%VisualStudioVersion%% is not set. Run this script from an MSVC shell.
  set "ERROR_STATUS=1"
)   else (
  echo VisualStudioVersion=%VisualStudioVersion%
)

if "/%VSINSTALLDIR%/"=="//" (
    echo %%VSINSTALLDIR%% is not set. Run this script from an MSVC shell.
  set "ERROR_STATUS=1"
) else (
    echo VSINSTALLDIR=%VSINSTALLDIR%
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

echo:
exit /b %ERROR_STATUS%


:: ============================================================================
:SQLITE_DOWNLOAD

set "DISTRO=sqlite.zip"
set "URL=https://sqlite.org/src/zip/sqlite.zip"

if not exist "%BASEDIR%\%DISTRO%" (
    echo ===== Downloading current SQLite release =====
    curl.exe -fL --retry 3 --output "%BASEDIR%\%DISTRO%" %URL%
    set "ERROR_STATUS=!ERRORLEVEL!"
    if "!ERROR_STATUS!"=="0" (
        echo ----- Downloaded current SQLite release -----
    ) else (
        echo Error downloading SQLite.
        echo Errod code: !ERROR_STATUS!
    )
) else (echo ===== Using previously downloaded SQLite =====)

echo:
exit /b %ERROR_STATUS%


:: ============================================================================
:SQLITE_EXTRACT

set "DISTROFILE=sqlite.zip"

if not exist "%DISTRODIR%\Makefile.msc" (
    echo ===== Extracting SQLite =====
    "%TAR%" -xf "%BASEDIR%\%DISTROFILE%"
    set "ERROR_STATUS=!ERRORLEVEL!"
    if "!ERROR_STATUS!"=="0" (
        echo ----- Extracted SQLite -----
    ) else (
        echo Error extracting SQLite.
        echo Errod code: !ERROR_STATUS!
    )
) else (echo ===== Using previously extracted SQLite =====)

echo:
exit /b %ERROR_STATUS%


:: ============================================================================
:ZLIB_DOWNLOAD

set "DISTRO=zlib.tar.gz"
set "URL=https://zlib.net/current/zlib.tar.gz"

if not exist "%BASEDIR%\%DISTRO%" (
    echo ===== Downloading ZLIB =====
    curl.exe -fL --retry 3 --output "%BASEDIR%\%DISTRO%" %URL%
    set "ERROR_STATUS=!ERRORLEVEL!"
    if "!ERROR_STATUS!"=="0" (
        echo ----- Downloaded ZLIB -----
    ) else (
        echo Error downloading ZLIB.
        echo Errod code: !ERROR_STATUS!
    )
) else (echo ===== Using previously downloaded ZLIB =====)

echo:
exit /b %ERROR_STATUS%


:: ============================================================================
:ZLIB_EXTRACT

set "DISTROFILE=zlib.tar.gz"
set "ZLIBDIR=%THIRDDIR%\zlib"

if not exist "%ZLIBDIR%\win32\Makefile.msc" (
    echo ===== Extracting ZLIB =====
    cmd /c rmdir /S /Q "%ZLIBDIR%" 1>>"%STDOUTLOG%" 2>>"%STDERRLOG%"
    "%TAR%" -xf "%BASEDIR%\%DISTROFILE%"
    set "ERROR_STATUS=!ERRORLEVEL!"
    if "!ERROR_STATUS!"=="0" (
        echo ----- Extracted ZLIB -----
        mkdir "%THIRDDIR%" 2>nul
        move /Y "%BASEDIR%\zlib-*" "%BASEDIR%\zlib" 1>>"%STDOUTLOG%" 2>>"%STDERRLOG%"
        move /Y "%BASEDIR%\zlib" "%THIRDDIR%" 1>>"%STDOUTLOG%" 2>>"%STDERRLOG%"
    ) else (
        echo Error extracting ZLIB.
        echo Errod code: !ERROR_STATUS!
    )
) else (echo ===== Using previously extracted ZLIB =====)

echo:
exit /b %ERROR_STATUS%


:: ============================================================================
:ZLIB_BUILD

if not exist "%ZLIBDIR%\zlib1.dll" (
    echo ===== Building ZLIB =====
    cd /d "%DISTRODIR%"
    nmake /nologo "TOP=%DISTRODIR%" "ZLIBLIB=all" /f "%SQLITE_MAKEFILE%" zlib
    set "ERROR_STATUS=!ERRORLEVEL!"
    if "!ERROR_STATUS!"=="0" (
        echo ----- Built ZLIB -----
    ) else (
        echo Error building ZLIB.
        echo Errod code: !ERROR_STATUS!
    )
) else (echo ===== Using previously built ZLIB =====)

echo:
exit /b %ERROR_STATUS%


:: ============================================================================
:ICU_DOWNLOAD

set "DISTRO=icu4c-X-sources.zip"
set "URL="

set "ICU_RELEASE_META=%BASEDIR%\icu_release_meta.json"
if not exist "%ICU_RELEASE_META%" (
    curl.exe -s https://api.github.com/repos/unicode-org/icu/releases/latest >"%ICU_RELEASE_META%"
)
set "ERROR_STATUS=%ERRORLEVEL%"
if "!ERROR_STATUS!"=="0" (
    echo ----- Downloaded ICU release meta -----
) else (
    del /Y /Q "%ICU_RELEASE_META%"
    echo Error downloading ICU release meta.
    exit /b %ERROR_STATUS%
)

for /f "usebackq tokens=2" %%I in (`findstr /R /C:"browser_download_url.*icu4c-.*-s.*rc.*\.zip" "%ICU_RELEASE_META%"`) do (
    set "BUFFER=%%~I"
    if "!BUFFER:~-3!"=="zip" (set "URL=!BUFFER!")
    set "BUFFER="
)
if defined URL (
    echo {INFO} ICU release URL: %URL%
) else (
    set "ERROR_STATUS=1"
    echo {ERROR} Failed to locate ICU release URL.
    exit /b %ERROR_STATUS%
)

if not exist "%BASEDIR%\%DISTRO%" (
    echo ===== Downloading ICU =====
    curl.exe -fL --retry 3 --output "%BASEDIR%\%DISTRO%" %URL%
    set "ERROR_STATUS=!ERRORLEVEL!"
    if "!ERROR_STATUS!"=="0" (
        echo ----- Downloaded ICU -----
    ) else (
        echo Error downloading ICU.
        echo Errod code: !ERROR_STATUS!
    )
) else (echo ===== Using previously downloaded ICU =====)

echo:
exit /b %ERROR_STATUS%


:: ============================================================================
:ICU_EXTRACT

set "DISTROFILE=icu4c-X-sources.zip"
set "ICUDIR=%THIRDDIR%\icu"

if not exist "%ICUDIR%\source\allinone\allinone.sln" (
    echo ===== Extracting ICU =====
    cd /d "%THIRDDIR%"
    "%TAR%" -xf "%BASEDIR%\%DISTROFILE%"
    set "ERROR_STATUS=!ERRORLEVEL!"
    if "!ERROR_STATUS!"=="0" (
        echo ----- Extracted ICU -----
    ) else (
        echo Error extracting ICU.
        echo Errod code: !ERROR_STATUS!
    )
) else (echo ===== Using previously extracted ICU =====)

echo:
exit /b %ERROR_STATUS%


:: ============================================================================
:ICU_BUILD

if not exist "%ICUBINDIR%\icuinfo.exe" (
    echo ===== Building ICU =====
    cd /d "%ICUDIR%"
    msbuild "%ICUDIR%\source\allinone\allinone.sln" /m /p:Configuration=Release /p:SkipUWP=true
    set "ERROR_STATUS=!ERRORLEVEL!"
    if "!ERROR_STATUS!"=="0" (
        echo ----- Built ICU -----
    ) else (
        echo Error building ICU.
        echo Errod code: !ERROR_STATUS!
        if exist "%ICUBINDIR%\icuinfo.exe" (
           echo ----- Built ICU -----
           set "ERROR_STATUS=0"
        )
    )
) else (echo ===== Using previously built ICU =====)

echo:
exit /b %ERROR_STATUS%


:: ============================================================================
:FP16_DOWNLOAD

set "DISTRO=fp16_master.zip"
set "URL=https://github.com/Maratyszcza/FP16/archive/refs/heads/master.zip"

if not exist "%BASEDIR%\%DISTRO%" (
    echo ===== Downloading FP16 =====
    curl.exe -fL --retry 3 --output "%BASEDIR%\%DISTRO%" %URL%
    set "ERROR_STATUS=!ERRORLEVEL!"
    if "!ERROR_STATUS!"=="0" (
        echo ----- Downloaded FP16 -----
    ) else (
        echo Error downloading FP16.
        echo Errod code: !ERROR_STATUS!
    )
) else (echo ===== Using previously downloaded FP16 =====)

echo:
exit /b %ERROR_STATUS%


:: ============================================================================
:FP16_EXTRACT

set "DISTROFILE=fp16_master.zip"
set "SRCDIR=%THIRDDIR%\FP16-master"

if not exist "%SRCDIR%" (
    echo ===== Extracting FP16 =====
    cd /d "%THIRDDIR%"
    "%TAR%" -xf "%BASEDIR%\%DISTROFILE%"
    set "ERROR_STATUS=!ERRORLEVEL!"
    if "!ERROR_STATUS!"=="0" (
        echo ----- Extracted FP16 -----
    ) else (
        echo Error extracting FP16.
        echo Errod code: !ERROR_STATUS!
    )
) else (echo ===== Using previously extracted FP16 =====)

if not "%ERROR_STATUS%"=="0" (exit /b %ERROR_STATUS%)
echo:

echo ========== Copy FP16 ===========

if not exist "%BUILDDIR%\tsrc" (cmd /c mkdir "%BUILDDIR%\tsrc")
cd /d "%BUILDDIR%\tsrc"

tclsh "%BASEDIR%\extra\copy_here.tcl" "%THIRDDIR%\FP16-master\include\*"
set "ERROR_STATUS=%ERRORLEVEL%"

echo:
exit /b %ERROR_STATUS%


:: ============================================================================
:EXTRA_SRC_PREPARE

set OPT_XTRA=%OPT_XTRA%^
    -DSQLITE_EXTRA_AUTOEXT=sqlite3ExtraAutoExtInit ^
    -DSQLITE_ENABLE_COMPRESS ^
    -DSQLITE_ENABLE_CSV      ^
    -DSQLITE_ENABLE_DECIMAL  ^
    -DSQLITE_ENABLE_FUZZER   ^
    -DSQLITE_ENABLE_NOOP     ^
    -DSQLITE_ENABLE_PREFIXES ^
    -DSQLITE_ENABLE_REGEXP   ^
    -DSQLITE_ENABLE_ROT      ^
    -DSQLITE_ENABLE_SERIES   ^
    -DSQLITE_ENABLE_SHA      ^
    -DSQLITE_ENABLE_SHATHREE ^
    -DSQLITE_ENABLE_SQLAR    ^
    -DSQLITE_ENABLE_UINT     ^
    -DSQLITE_ENABLE_UUID     

cd /d "%DISTRODIR%\ext\misc"

set MISC_EXT=^
    "compress.c"  ^
    "csv.c"       ^
    "decimal.c"   ^
    "fuzzer.c"    ^
    "noop.c"      ^
    "prefixes.c"  ^
    "regexp.c"    ^
    "rot13.c"     ^
    "series.c"    ^
    "sha1.c"      ^
    "shathree.c"  ^
    "sqlar.c"     ^
    "uint.c"      ^
    "uuid.c"

echo ========== Patch MISC_EXT ===========
tclsh "%BASEDIR%\extra\patch_sqlite_misc_autoext.tcl" %MISC_EXT% || exit /b !ERRORLEVEL!

echo:

echo ========== Bundle MISC_EXT ===========
tclsh "%BASEDIR%\extra\bundle_extra_src.tcl" %MISC_EXT% || exit /b !ERRORLEVEL!

echo ========== Set EXTRA_SRC for extended SQLite build ===========

set EXTRA_SRC=%EXTRA_SRC% ^
    ""%DISTRODIR%\ext\misc\compress.c""      ^
    ""%DISTRODIR%\ext\misc\csv.c""           ^
    ""%DISTRODIR%\ext\misc\decimal.c""       ^
    ""%DISTRODIR%\ext\misc\fuzzer.c""        ^
    ""%DISTRODIR%\ext\misc\noop.c""          ^
    ""%DISTRODIR%\ext\misc\prefixes.c""      ^
    ""%DISTRODIR%\ext\misc\regexp.c""        ^
    ""%DISTRODIR%\ext\misc\rot13.c""         ^
    ""%DISTRODIR%\ext\misc\series.c""        ^
    ""%DISTRODIR%\ext\misc\sha1.c""          ^
    ""%DISTRODIR%\ext\misc\shathree.c""      ^
    ""%DISTRODIR%\ext\misc\sqlar.c""         ^
    ""%DISTRODIR%\ext\misc\uint.c""          ^
    ""%DISTRODIR%\ext\misc\uuid.c""          ^
    ""%DISTRODIR%\ext\misc\misc_ext_init.c""

echo:
exit /b %ERRORLEVEL%


:: ============================================================================
:SQLITE_BUILD

cd /d "%BUILDDIR%" || exit /b !ERRORLEVEL!

nmake /nologo "EXTRA_SRC=%EXTRA_SRC%" "TOP=%DISTRODIR%" /f "%DISTRODIR%\Makefile.msc" %*

echo:
exit /b %ERRORLEVEL%


:: ============================================================================
:COLLECT_BINARIES

echo ========== Collecting binaries ===========
set BINDIR=%~dp0bin
if not exist "%BINDIR%" mkdir "%BINDIR%"
del /Q bin\* 2>nul
if exist "%BUILDDIR%\sqlite3.dll" copy /Y "%BUILDDIR%\sqlite3.dll" "%BINDIR%"
if exist "%BUILDDIR%\sqlite3.exe" copy /Y "%BUILDDIR%\sqlite3.exe" "%BINDIR%"
if exist "%BUILDDIR%\sqlite3.def" copy /Y "%BUILDDIR%\sqlite3.def" "%BINDIR%"
if "%USE_ICU%"=="1" (copy /Y "%ICUBINDIR%\icu*.dll" "%BINDIR%")
if "%USE_ZLIB%"=="1" (copy /Y "%ZLIBDIR%\zlib1.dll"  "%BINDIR%")
echo ---------- Copied  binaries -----------

echo:
exit /b 0


:: ============================================================================
rem :PATCH_NORMALIZE_C
rem 
rem set "FILENAME=%BUILDDIR%\tsrc\normalize.c"
rem echo ========== Patch "%FILENAME%" ===========
rem 
rem tclsh "%BASEDIR%\extra\replace.tcl" "%FILENAME%"  ^
rem     "int main" "int sqlite3_normalize_main"       ^
rem     "aiClass" "ai_ClassN"                         ^
rem     "sqlite3UpperToLower" "sqlite3_UpperToLowerN" ^
rem     "sqlite3CtypeMap" "sqlite3_CtypeMapN"         ^
rem     "sqlite3GetToken" "sqlite3_GetTokenN"         ^
rem     "IdChar(" "Id_CharN("                         ^
rem     "sqlite3I" "sqlite3_IN"                       ^
rem     "sqlite3T" "sqlite3_TN"                       ^
rem     "TK_" "TKN_"                                  ^
rem     "CC_" "CCN_"
rem 
rem tclsh "%BASEDIR%\extra\replace.tcl" "%FILENAME%" ^
rem     "__GCCN__" "__GCC__"
rem 
rem echo:
rem exit /b %ERRORLEVEL%
