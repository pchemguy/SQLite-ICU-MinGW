@echo off

set "USE_ICU=1"
set "USE_ZLIB=1"
set "SQLITE_EXTRA=1"

call "%~dp0sqlite_msbuild.bat"
