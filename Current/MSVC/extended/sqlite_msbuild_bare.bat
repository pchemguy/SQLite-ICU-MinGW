@echo off

set "USE_ICU=0"
set "USE_ZLIB=0"
set "SQLITE_EXTRA=0"
set "USE_EXTRAS=0"

call "%~dp0sqlite_msbuild.bat"
