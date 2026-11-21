# Bash design

- Give each distinct workflow step its own function. In executable scripts, call the steps in order from `main()` and end the file with `main "$@"`.
- Put a brief purpose comment immediately above each function definition. Omit decorative fences.
- When declaring a list of command-line options, put one option per line.
