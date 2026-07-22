@echo off

set ARGS=%~1
:NEXT_ARG
  for /F "tokens=1* delims= " %%G in ("%ARGS%") do (
    echo %%G
    set ARGS=%%H
  )
if defined ARGS goto NEXT_ARG
