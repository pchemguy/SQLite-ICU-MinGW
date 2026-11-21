# Bash design

- Give each distinct workflow step its own function. Call the steps in order from the script's entry-point function.
- Put a brief purpose comment immediately above each function definition. Omit decorative fences.
- Use bare variable names in expressions where `$` is optional.
- When declaring a list of command-line options, put one option per line.
