@echo off

cd /d "%~dp0.."
set "PROJDIR=%CD%"

python "%PROJDIR%\tool\generate_test_api.py" ^
    --source "%PROJDIR%\src\alphabet.c" ^
    --ctypes "%PROJDIR%\pytestenv\src\pytestenv\_native_generated.py" ^
    --clang-arg=-I"%PROJDIR%\out\build_test" ^
    --msvc-env ^
    --verbose ^
    --clang-arg=-x ^
    --clang-arg=c ^
    --clang-arg=-std=c11 ^
    --clang-arg=--target=x86_64-pc-windows-msvc ^
    --clang-arg=-fms-extensions ^
    --clang-arg=-fms-compatibility ^
    --clang-arg=-DSQLITE_CORE ^
    --clang-arg=-DPYTEST_C_API
