# Shared Bash call notation and driver diagnostics.

# ============================================================================ CALL BEGIN
# Invoke 'name()' with zero arguments in the current shell and return its status.
call() {
    if (( $# != 1 )) || [[ $1 != ?*'()' ]]; then
        die "Expected a zero-argument call such as call 'resolve_paths()'."
    fi
    "${1%'()'}"
}
# ============================================================================ CALL END

# ============================================================================ DIE BEGIN
# Write a diagnostic to standard error and stop the build.
die() {
    printf 'sqlite_build: %s\n' "$*" >&2
    exit 1
}
# ============================================================================ DIE END
