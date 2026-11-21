# Sourced by sqlite_build.sh after the stock modules.
if (( SQLITE_ENABLE_ICUEX )); then
    project_source SQLiteICUex icuex ICUEX
    smoke_tests+=("SELECT str_casefold('ABC')='abc' AND 'A'='a' COLLATE UTF_CI")
fi
