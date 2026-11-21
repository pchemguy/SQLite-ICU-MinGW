# Bash design

- Keep `main()` in `sqlite_build.sh` readable as a sequence of calls such as `select_preset "$preset"` and `resolve_paths`. Give each distinct workflow step its own function.
- Put a brief purpose comment immediately above every function definition. Omit `BEGIN`/`END` fences.
- Use bare variable names in expressions where `$` is optional, as in `(( USE_ICU ))`.
- In `set_sqlite_defaults`, put each configure argument and each compiler flag on its own line.
