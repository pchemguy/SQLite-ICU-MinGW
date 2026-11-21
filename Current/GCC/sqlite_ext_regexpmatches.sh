# This source uses the private definitions in stock regexp.c and SQLite JSON.
if [[ $SQLITE_ENABLE_REGEXPMATCHES == 1 ]]; then
    project_source SQLiteRegexpMatches regexpmatches REGEXPMATCHES
    smoke_tests+=("SELECT json_array(regexp_matches('[0-9]+','a12b3'))='[[\"12\",\"3\"]]'")
fi
