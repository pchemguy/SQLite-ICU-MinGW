#!/usr/bin/env bash
# Build and package native Linux SQLite with the selected built-in extensions.
set -euo pipefail
export LC_ALL=C
shopt -s nullglob

# Command-line selection and defaults that environment switches may override.
preset=full
action=build
declare preset_icu preset_stock preset_extras

# Paths shared by build phases, sourced hooks, and the process-level exit trap.
declare base out cache src build tsrc work inputs stage sqlite_zip extension_stamp
declare -a managed_paths=()
declare lockfd archive_hash tcl version

# Configure and Make arguments, ordered extension sources, and hook registrations.
declare -a configure_args=() options=() extra_src=()
declare -a sources=() names=() macros=() hooks=()
declare -a header_archives=() prepare_steps=() smoke_tests=()

# ============================================================================ MAIN BEGIN
# Run the requested action and publish the SQLite package after verification.
main() {
    load_build_helpers "${BASH_SOURCE[0]}"
    parse_arguments "$@"
    if [[ $action == help ]]; then
        call 'usage()'
        return 0
    fi

    select_preset "$preset"
    call 'resolve_paths()'
    if [[ $action == clean ]]; then
        call 'clean_output_root()'
        return
    fi

    call 'open_build_root()'
    call 'resolve_build_settings()'
    call 'ensure_dependencies()'
    call 'create_workspace()'
    call 'prepare_sqlite_source()'

    call 'set_build_options()'
    call 'collect_extensions()'
    call 'report_build_settings()'
    call 'write_build_inputs()'
    call 'configure_sqlite_if_needed()'
    call 'prepare_target_sources()'
    call 'compile_sqlite()'

    call 'stage_package()'
    call 'verify_package()'
    call 'publish_package()'
    call 'report_success()'
}
# ============================================================================ MAIN END

# ============================================================================ LOAD_BUILD_HELPERS BEGIN
# Locate the driver from $1 and load the procedure, dependency, and source helpers.
load_build_helpers() {
    base=$(cd -- "$(dirname -- "$1")" && pwd -P)
    # shellcheck source=tool/procedures.sh
    source "$base/tool/procedures.sh"
    # shellcheck source=tool/dependencies.sh
    source "$base/tool/dependencies.sh"
    # shellcheck source=tool/sources.sh
    source "$base/tool/sources.sh"
}
# ============================================================================ LOAD_BUILD_HELPERS END

# ============================================================================ PARSE_ARGUMENTS BEGIN
# Record the requested action and preset, stopping at the first help option.
parse_arguments() {
    while (( $# )); do
        case $1 in
            --preset)
                (( $# >= 2 )) || die '--preset requires a name'
                preset=$2
                shift 2
                ;;
            clean)
                action=clean
                shift
                ;;
            -h|--help)
                action=help
                return 0
                ;;
            *) die "Unknown argument: $1" ;;
        esac
    done
}
# ============================================================================ PARSE_ARGUMENTS END

# ============================================================================ USAGE BEGIN
# Print the supported command-line forms to standard output.
usage() {
    printf '%s\n' 'Usage: sqlite_build.sh [--preset bare|bare-icu|bare-icu-ext|full] [clean]' \
        'The default is full. OUT_DIR selects the local build and install root.'
}
# ============================================================================ USAGE END

# ============================================================================ SELECT_PRESET BEGIN
# Set the default ICU, stock-module, and project-hook switches for preset $1.
select_preset() {
    case $1 in
        bare)         preset_icu=0; preset_stock=0; preset_extras=0 ;;
        bare-icu)     preset_icu=1; preset_stock=0; preset_extras=0 ;;
        bare-icu-ext) preset_icu=1; preset_stock=1; preset_extras=0 ;;
        full)         preset_icu=1; preset_stock=1; preset_extras=1 ;;
        *) die "Unknown preset: $1" ;;
    esac
}
# ============================================================================ SELECT_PRESET END

# ============================================================================ RESOLVE_PATHS BEGIN
# Resolve the output paths, including the entries owned by clean.
resolve_paths() {
    out=$(realpath -m -- "${OUT_DIR:-$base/out}")
    [[ $out != / ]] || die 'OUT_DIR must identify a dedicated build root.'
    cache=$out/cache
    src=$out/sqlite
    build=$out/build
    tsrc=$build/tsrc
    sqlite_zip=$cache/sqlite.zip
    extension_stamp=$tsrc/.extensions-ready
    managed_paths=("$build" "$src" "$out/.packages" "$out/package" "$out/bin" "$out/include" "$out/lib")
}
# ============================================================================ RESOLVE_PATHS END

# ============================================================================ CLEAN_OUTPUT_ROOT BEGIN
# Lock an existing managed root and remove its build outputs, retaining the cache.
clean_output_root() {
    if [[ ! -d $out ]]; then return 0; fi
    call 'lock_output_root()'
    call 'check_output_ownership()'
    rm -rf -- "${managed_paths[@]}"
}
# ============================================================================ CLEAN_OUTPUT_ROOT END

# ============================================================================ OPEN_BUILD_ROOT BEGIN
# Create and lock the build root, then establish ownership of its output paths.
open_build_root() {
    mkdir -p -- "$out"
    call 'lock_output_root()'
    call 'check_output_ownership()'
    [[ $out != *' '* ]] || die 'SQLite configure requires a space-free OUT_DIR.'
}
# ============================================================================ OPEN_BUILD_ROOT END

# ============================================================================ LOCK_OUTPUT_ROOT BEGIN
# Hold the output directory's exclusive lock until this driver exits.
lock_output_root() {
    exec {lockfd}>"$out/.sqlite-build.lock"
    flock "$lockfd"
}
# ============================================================================ LOCK_OUTPUT_ROOT END

# ============================================================================ CHECK_OUTPUT_OWNERSHIP BEGIN
# Recognize a marked root or claim an unused build root while holding its lock.
check_output_ownership() {
    local marker=$out/.sqlite-gcc-root path
    if [[ -f $marker ]]; then return 0; fi
    if [[ $action == clean ]]; then die "Unmanaged output directory: $out"; fi
    for path in "${managed_paths[@]}"; do
        [[ ! -e $path && ! -L $path ]] || die "Existing unmanaged path: $path"
    done
    touch "$marker"
}
# ============================================================================ CHECK_OUTPUT_OWNERSHIP END

# ============================================================================ RESOLVE_BUILD_SETTINGS BEGIN
# Apply preset defaults to unset feature switches and resolve the toolchain.
resolve_build_settings() {
    : "${USE_ICU=$preset_icu}" "${SQLITE_EXTRA=$preset_stock}" "${USE_EXTRAS=$preset_extras}"
    : "${SQLITE_ENABLE_ICUEX=$USE_ICU}" "${SQLITE_ENABLE_PBLOB=1}" "${SQLITE_ENABLE_REGEXPMATCHES=$SQLITE_EXTRA}"
    call 'validate_features()'
    call 'set_toolchain_defaults()'
}
# ============================================================================ RESOLVE_BUILD_SETTINGS END

# ============================================================================ VALIDATE_FEATURES BEGIN
# Check Boolean feature switches and the prerequisites of each enabled hook.
validate_features() {
    local flag
    for flag in USE_ICU SQLITE_EXTRA USE_EXTRAS SQLITE_ENABLE_ICUEX SQLITE_ENABLE_PBLOB SQLITE_ENABLE_REGEXPMATCHES; do
        [[ ${!flag} =~ ^[01]$ ]] || die "$flag must be 0 or 1."
    done
    if [[ $USE_EXTRAS == 1 && $SQLITE_ENABLE_ICUEX == 1 && $USE_ICU == 0 ]]; then
        die 'ICUex requires USE_ICU=1.'
    fi
    if [[ $USE_EXTRAS == 1 && $SQLITE_ENABLE_REGEXPMATCHES == 1 && $SQLITE_EXTRA == 0 ]]; then
        die 'RegexpMatches requires SQLITE_EXTRA=1 (stock regexp.c).'
    fi
}
# ============================================================================ VALIDATE_FEATURES END

# ============================================================================ SET_TOOLCHAIN_DEFAULTS BEGIN
# Select the compiler, optimization flags, and positive Make parallelism.
set_toolchain_defaults() {
    : "${CC:=gcc}" "${CFLAGS:=-O2}" "${JOBS:=$(getconf _NPROCESSORS_ONLN)}"
    [[ $JOBS =~ ^[1-9][0-9]*$ ]] || die 'JOBS must be a positive integer.'
    export CC CFLAGS
}
# ============================================================================ SET_TOOLCHAIN_DEFAULTS END

# ============================================================================ CREATE_WORKSPACE BEGIN
# Create the per-run staging directory, install cleanup traps, and open the cache.
create_workspace() {
    work=$(mktemp -d "$out/.work.XXXXXXXX")
    trap 'cleanup_workspace "$?"' EXIT
    trap 'exit 129' HUP
    trap 'exit 130' INT
    trap 'exit 143' TERM
    inputs=$work/build-inputs.txt
    stage=$work/prefix
    mkdir -p -- "$cache"
}
# ============================================================================ CREATE_WORKSPACE END

# ============================================================================ CLEANUP_WORKSPACE BEGIN
# Remove temporary files on exit and preserve a failed build or signal status.
cleanup_workspace() {
    local status=$1 cleanup_status=0
    rm -rf -- "${work:?}" || cleanup_status=$?
    if [[ $status -ne 0 ]]; then exit "$status"; fi
    exit "$cleanup_status"
}
# ============================================================================ CLEANUP_WORKSPACE END

# ============================================================================ PREPARE_SQLITE_SOURCE BEGIN
# Acquire the canonical archive and make its matching source tree available.
prepare_sqlite_source() {
    call 'fetch_sqlite_archive()'
    call 'refresh_sqlite_source()'
}
# ============================================================================ PREPARE_SQLITE_SOURCE END

# ============================================================================ FETCH_SQLITE_ARCHIVE BEGIN
# Populate the SQLite archive cache and record the digest of the selected ZIP.
fetch_sqlite_archive() {
    download https://sqlite.org/src/zip/sqlite.zip "$sqlite_zip"
    archive_hash=$(sha256sum < "$sqlite_zip")
    archive_hash=${archive_hash%% *}
}
# ============================================================================ FETCH_SQLITE_ARCHIVE END

# ============================================================================ REFRESH_SQLITE_SOURCE BEGIN
# Replace the extracted SQLite tree when its recorded archive digest differs.
refresh_sqlite_source() {
    local unpacked
    if [[ -f $src/.archive-sha256 && $(<"$src/.archive-sha256") == "$archive_hash" ]]; then
        return 0
    fi
    unpacked=$(unpack_zip "$sqlite_zip" "$work/sqlite" configure main.mk tool/mksqlite3c.tcl)
    printf '%s\n' "$archive_hash" > "$unpacked/.archive-sha256"
    if [[ -e $src ]]; then mv -T -- "$src" "$work/previous-source"; fi
    mv -T -- "$unpacked" "$src"
}
# ============================================================================ REFRESH_SQLITE_SOURCE END

# ============================================================================ SET_BUILD_OPTIONS BEGIN
# Assemble the default SQLite options and flags for the selected dependencies.
set_build_options() {
    call 'set_sqlite_defaults()'
    if [[ $USE_ICU == 1 ]]; then call 'add_icu_flags()'; fi
    if [[ $SQLITE_EXTRA == 1 ]]; then call 'add_zlib_flags()'; fi
}
# ============================================================================ SET_BUILD_OPTIONS END

# ============================================================================ SET_SQLITE_DEFAULTS BEGIN
# Initialize the upstream configure arguments and SQLite compile-time options.
set_sqlite_defaults() {
    configure_args=(--prefix="$out" --enable-shared --enable-static --soname=legacy --disable-rpath
        --disable-tcl --enable-session --enable-fts3 --enable-fts4 --enable-fts5 --enable-rtree
        --enable-geopoly --enable-column-metadata --enable-dbpage --enable-dbstat --enable-carray)
    options=(-DSQLITE_ENABLE_RBU -DSQLITE_ENABLE_API_ARMOR -DSQLITE_ENABLE_NORMALIZE
        -DSQLITE_ENABLE_FTS3_PARENTHESIS -DSQLITE_ENABLE_FTS3_TOKENIZER -DSQLITE_ENABLE_EXPLAIN_COMMENTS=1
        -DSQLITE_ENABLE_OFFSET_SQL_FUNC=1 -DSQLITE_ENABLE_QPSG -DSQLITE_ENABLE_STAT4 -DSQLITE_DQS=0
        -DSQLITE_LIKE_DOESNT_MATCH_BLOBS -DSQLITE_MAX_EXPR_DEPTH=100 -DSQLITE_MAX_ATTACHED=100
        -DSQLITE_OMIT_DEPRECATED -DSQLITE_DEFAULT_FOREIGN_KEYS=1 -DSQLITE_DEFAULT_SYNCHRONOUS=1
        -DSQLITE_USE_URI=1 -DSQLITE_SOUNDEX -DSQLITE_ENABLE_STMTVTAB -DSQLITE_ENABLE_BYTECODE_VTAB)
}
# ============================================================================ SET_SQLITE_DEFAULTS END

# ============================================================================ ADD_ICU_FLAGS BEGIN
# Link ICU's common and internationalization C APIs and enable ICU collations.
add_icu_flags() {
    local cflags libs
    cflags=$(pkg-config --cflags icu-i18n icu-uc)
    libs=$(pkg-config --libs icu-i18n icu-uc)
    configure_args+=("--with-icu-ldflags=$libs" "--with-icu-cflags=$cflags" --enable-icu-collations)
    export CPPFLAGS="${CPPFLAGS:-} $cflags"
}
# ============================================================================ ADD_ICU_FLAGS END

# ============================================================================ ADD_ZLIB_FLAGS BEGIN
# Give configure the zlib headers and library search paths for the stock modules.
add_zlib_flags() {
    CPPFLAGS="${CPPFLAGS:-} $(pkg-config --cflags zlib)"
    LDFLAGS="${LDFLAGS:-} $(pkg-config --libs-only-L zlib)"
    export CPPFLAGS LDFLAGS
}
# ============================================================================ ADD_ZLIB_FLAGS END

# ============================================================================ COLLECT_EXTENSIONS BEGIN
# Register stock sources first, then project hooks, and finalize the Make inputs.
collect_extensions() {
    if [[ $SQLITE_EXTRA == 1 ]]; then call 'register_stock_extensions()'; fi
    if [[ $USE_EXTRAS == 1 ]]; then call 'load_project_hooks()'; fi
    call 'finalize_extension_list()'
}
# ============================================================================ COLLECT_EXTENSIONS END

# ============================================================================ REGISTER_STOCK_EXTENSIONS BEGIN
# Register the 15 stock sources and their build macros in amalgamation order.
register_stock_extensions() {
    local name macro
    for name in compress csv decimal fuzzer noop prefixes regexp remember rot13 series sha1 shathree sqlar uint uuid; do
        case $name in
            rot13) macro=ROT ;;
            sha1)  macro=SHA ;;
            *)     macro=${name^^} ;;
        esac
        add_source "$src/ext/misc/$name.c" "$macro"
    done
}
# ============================================================================ REGISTER_STOCK_EXTENSIONS END

# ============================================================================ LOAD_PROJECT_HOOKS BEGIN
# Source each project hook in filename order so it can register sources and callbacks.
load_project_hooks() {
    local hook
    hooks=("$base"/sqlite_ext_*.sh)
    for hook in "${hooks[@]}"; do
        # shellcheck source=/dev/null
        source "$hook"
    done
}
# ============================================================================ LOAD_PROJECT_HOOKS END

# ============================================================================ FINALIZE_EXTENSION_LIST BEGIN
# Set the selected extension macros and append the dispatcher to EXTRA_SRC.
finalize_extension_list() {
    if (( ${#names[@]} )); then
        options+=(-DSQLITE_EXTRA_AUTOEXT=sqlite3ExtraAutoExtInit "${macros[@]/#/-DSQLITE_ENABLE_}")
        extra_src=("${names[@]/#/tsrc/}" tsrc/misc_ext_init.c)
    fi
}
# ============================================================================ FINALIZE_EXTENSION_LIST END

# ============================================================================ REPORT_BUILD_SETTINGS BEGIN
# Display the effective preset switches and output root.
report_build_settings() {
    printf 'Preset %s | ICU=%s stock=%s project hooks=%s | %s\n' "$preset" "$USE_ICU" "$SQLITE_EXTRA" "$USE_EXTRAS" "$out"
}
# ============================================================================ REPORT_BUILD_SETTINGS END

# ============================================================================ WRITE_BUILD_INPUTS BEGIN
# Write the compiler, dependency, and source records used to detect stale builds.
write_build_inputs() {
    {
        call 'write_toolchain_inputs()'
        call 'write_dependency_inputs()'
        call 'write_input_digests()'
    } > "$inputs"
}
# ============================================================================ WRITE_BUILD_INPUTS END

# ============================================================================ WRITE_TOOLCHAIN_INPUTS BEGIN
# Emit the SQLite archive identity, compiler identity, flags, and search paths.
write_toolchain_inputs() {
    local var
    printf 'SQLite archive: %s\nCompiler: %s\n' "$archive_hash" "$(command -v "$CC")"
    "$CC" -dumpmachine
    "$CC" --version
    printf '%s\n' "${configure_args[@]}" "${options[@]}" "${extra_src[@]}"
    for var in CFLAGS CPPFLAGS LDFLAGS CPATH LIBRARY_PATH PKG_CONFIG_PATH PKG_CONFIG_LIBDIR PKG_CONFIG_SYSROOT_DIR; do
        printf '%s=%s\n' "$var" "${!var-}"
    done
}
# ============================================================================ WRITE_TOOLCHAIN_INPUTS END

# ============================================================================ WRITE_DEPENDENCY_INPUTS BEGIN
# Record dependency versions and flags, probing optional zlib when metadata is absent.
write_dependency_inputs() {
    local module
    for module in zlib icu-i18n icu-uc; do
        if [[ $module == icu-* && $USE_ICU == 0 ]]; then continue; fi
        if command -v pkg-config >/dev/null && pkg-config --exists "$module"; then
            printf '%s: ' "$module"
            pkg-config --modversion "$module"
            pkg-config --cflags --libs "$module"
        else
            printf '%s: no pkg-config metadata\n' "$module"
            if [[ $module == zlib ]] && call 'system_zlib_available()'; then
                printf 'zlib: system headers and library found\n'
            fi
        fi
    done
}
# ============================================================================ WRITE_DEPENDENCY_INPUTS END

# ============================================================================ SYSTEM_ZLIB_AVAILABLE BEGIN
# Return success if the compiler can link a trivial program against system zlib.
system_zlib_available() {
    printf '#include <zlib.h>\nint main(void){return !zlibVersion();}\n' |
        "$CC" -x c - -lz -o "$work/check-zlib" 2>/dev/null
}
# ============================================================================ SYSTEM_ZLIB_AVAILABLE END

# ============================================================================ WRITE_INPUT_DIGESTS BEGIN
# Emit SHA-256 records for the build scripts, registered sources and header archives.
write_input_digests() {
    sha256sum -- "$base/sqlite_build.sh" "$base"/tool/*.sh "$base"/tool/*.tcl \
        "${hooks[@]}" "${sources[@]}" "${header_archives[@]}"
}
# ============================================================================ WRITE_INPUT_DIGESTS END

# ============================================================================ CONFIGURE_SQLITE_IF_NEEDED BEGIN
# Reconfigure on a manifest change and record inputs after all configure checks succeed.
configure_sqlite_if_needed() {
    if cmp -s "$inputs" "$build/build-inputs.txt"; then return 0; fi
    call 'configure_sqlite()'
    if [[ $SQLITE_EXTRA == 1 ]]; then call 'verify_configured_zlib()'; fi
    cp -- "$inputs" "$build/build-inputs.txt"
}
# ============================================================================ CONFIGURE_SQLITE_IF_NEEDED END

# ============================================================================ CONFIGURE_SQLITE BEGIN
# Recreate the out-of-tree build directory and run SQLite configure in it.
configure_sqlite() {
    rm -rf -- "${build:?}"
    mkdir -p -- "$build"
    (cd "$build" && "$src/configure" "${configure_args[@]}")
}
# ============================================================================ CONFIGURE_SQLITE END

# ============================================================================ VERIFY_CONFIGURED_ZLIB BEGIN
# Require configure to have found zlib before compiling the stock extensions.
verify_configured_zlib() {
    grep -Eq '^LDFLAGS\.zlib *=.*-lz' "$build/Makefile" || die 'SQLite configure did not find the required zlib.'
}
# ============================================================================ VERIFY_CONFIGURED_ZLIB END

# ============================================================================ PREPARE_TARGET_SOURCES BEGIN
# Generate the target source tree and restage selected extensions when needed.
prepare_target_sources() {
    call 'prepare_target_tree()'
    if call 'extensions_need_staging()'; then
        call 'invalidate_extension_stamp()'
        call 'copy_extension_sources()'
        call 'run_extension_prepare_hooks()'
        call 'select_tcl_interpreter()'
        call 'generate_extension_dispatcher()'
        call 'verify_dispatcher_entries()'
        call 'bundle_extension_headers()'
        call 'mark_extensions_ready()'
    fi
}
# ============================================================================ PREPARE_TARGET_SOURCES END

# ============================================================================ PREPARE_TARGET_TREE BEGIN
# Run the upstream target-source rule, forcing regeneration for a missing header.
prepare_target_tree() {
    if [[ ! -s $tsrc/sqlite3.h ]]; then rm -f -- "$build/.target_source"; fi
    make_sqlite .target_source
}
# ============================================================================ PREPARE_TARGET_TREE END

# ============================================================================ EXTENSIONS_NEED_STAGING BEGIN
# Return success when selected source files or their preparation stamp are stale.
extensions_need_staging() {
    local staged
    if (( ${#names[@]} == 0 )); then return 1; fi
    if [[ ! -f $extension_stamp || $build/.target_source -nt $extension_stamp ]]; then return 0; fi
    for staged in "${extra_src[@]}"; do
        if [[ ! -s $build/$staged ]]; then return 0; fi
    done
    return 1
}
# ============================================================================ EXTENSIONS_NEED_STAGING END

# ============================================================================ INVALIDATE_EXTENSION_STAMP BEGIN
# Leave staging retryable if a copy, project callback, or Tcl step fails.
invalidate_extension_stamp() {
    rm -f -- "$extension_stamp"
}
# ============================================================================ INVALIDATE_EXTENSION_STAMP END

# ============================================================================ COPY_EXTENSION_SOURCES BEGIN
# Copy the selected stock and project C sources into the target tree.
copy_extension_sources() {
    cp -- "${sources[@]}" "$tsrc/"
}
# ============================================================================ COPY_EXTENSION_SOURCES END

# ============================================================================ RUN_EXTENSION_PREPARE_HOOKS BEGIN
# Run the preparation callbacks registered by the selected project hooks.
run_extension_prepare_hooks() {
    local prepare
    for prepare in "${prepare_steps[@]}"; do
        call "${prepare}()"
    done
}
# ============================================================================ RUN_EXTENSION_PREPARE_HOOKS END

# ============================================================================ SELECT_TCL_INTERPRETER BEGIN
# Select system Tcl when available, otherwise build SQLite's bundled Jim.
select_tcl_interpreter() {
    if command -v tclsh >/dev/null; then
        tcl=$(command -v tclsh)
    else
        make_sqlite jimsh
        tcl=$build/jimsh
    fi
}
# ============================================================================ SELECT_TCL_INTERPRETER END

# ============================================================================ GENERATE_EXTENSION_DISPATCHER BEGIN
# Patch extension initializers and generate a fresh misc_ext_init.c in the target tree.
generate_extension_dispatcher() {
    rm -f -- "$tsrc/misc_ext_init.c"
    (cd "$tsrc" && "$tcl" "$base/tool/patch_sqlite_misc_autoext.tcl" "${names[@]}")
}
# ============================================================================ GENERATE_EXTENSION_DISPATCHER END

# ============================================================================ VERIFY_DISPATCHER_ENTRIES BEGIN
# Require one generated dispatcher entry for every registered build macro.
verify_dispatcher_entries() {
    local macro
    for macro in "${macros[@]}"; do
        grep -Fxq "#ifdef SQLITE_ENABLE_$macro" "$tsrc/misc_ext_init.c" || die "Missing dispatcher entry: $macro"
    done
}
# ============================================================================ VERIFY_DISPATCHER_ENTRIES END

# ============================================================================ BUNDLE_EXTENSION_HEADERS BEGIN
# Inline local extension headers in the staged C sources using the selected Tcl.
bundle_extension_headers() {
    (cd "$tsrc" && BUNDLE_EXTRA_SRC_TRACE=${BUNDLE_EXTRA_SRC_TRACE:-0} "$tcl" "$base/tool/bundle_extra_src.tcl" "${names[@]}")
}
# ============================================================================ BUNDLE_EXTENSION_HEADERS END

# ============================================================================ MARK_EXTENSIONS_READY BEGIN
# Mark the fully prepared target sources as available for the next build.
mark_extensions_ready() {
    touch "$extension_stamp"
}
# ============================================================================ MARK_EXTENSIONS_READY END

# ============================================================================ COMPILE_SQLITE BEGIN
# Compile the CLI, shared library, and static archive with the selected sources.
compile_sqlite() {
    make_sqlite "EXTRA_SRC=${extra_src[*]}" sqlite3 libsqlite3.so libsqlite3.a
}
# ============================================================================ COMPILE_SQLITE END

# ============================================================================ MAKE_SQLITE BEGIN
# Run GNU Make in the configured tree with the effective options and supplied targets.
make_sqlite() {
    make -C "$build" -j "$JOBS" "OPTIONS=${options[*]}" "$@"
}
# ============================================================================ MAKE_SQLITE END

# ============================================================================ STAGE_PACKAGE BEGIN
# Assemble a complete distribution under the private staging prefix.
stage_package() {
    version=$(<"$src/VERSION")
    mkdir -p -- "$stage"/{bin,include,lib/pkgconfig} "$out/.packages"
    call 'stage_cli()'
    call 'stage_libraries()'
    call 'stage_headers()'
    call 'write_pkgconfig()'
}
# ============================================================================ STAGE_PACKAGE END

# ============================================================================ STAGE_CLI BEGIN
# Install the SQLite command-line executable in the staged bin directory.
stage_cli() {
    install -m755 -- "$build/sqlite3" "$stage/bin/"
}
# ============================================================================ STAGE_CLI END

# ============================================================================ STAGE_LIBRARIES BEGIN
# Install the versioned SQLite library, its linker and SONAME links, and the archive.
stage_libraries() {
    local library_file="libsqlite3.so.$version"
    install -m755 -- "$build/libsqlite3.so" "$stage/lib/$library_file"
    ln -s "$library_file" "$stage/lib/libsqlite3.so.0"
    ln -s "$library_file" "$stage/lib/libsqlite3.so"
    install -m644 -- "$build/libsqlite3.a" "$stage/lib/"
}
# ============================================================================ STAGE_LIBRARIES END

# ============================================================================ STAGE_HEADERS BEGIN
# Install the public SQLite and session headers in the staged include directory.
stage_headers() {
    install -m644 -- "$build"/{sqlite3.h,sqlite3ext.h,sqlite3session.h} "$stage/include/"
}
# ============================================================================ STAGE_HEADERS END

# ============================================================================ WRITE_PKGCONFIG BEGIN
# Write a sqlite3.pc whose prefix follows the location of the packaged file.
write_pkgconfig() {
    # shellcheck disable=SC2016
    sed 's|^prefix=.*|prefix=${pcfiledir}/../..|' "$build/sqlite3.pc" > "$stage/lib/pkgconfig/sqlite3.pc"
}
# ============================================================================ WRITE_PKGCONFIG END

# ============================================================================ VERIFY_PACKAGE BEGIN
# Verify the staged CLI version and run every SQL check registered by the hooks.
verify_package() {
    local query
    local -a cli=("$stage/bin/sqlite3" -batch -init /dev/null :memory:)
    [[ $("${cli[@]}" 'SELECT sqlite_version()') == "$version" ]] || die 'Packaged CLI verification failed.'
    for query in "${smoke_tests[@]}"; do
        [[ $("${cli[@]}" "$query") == 1 ]] || die "Packaged CLI check failed: $query"
    done
}
# ============================================================================ VERIFY_PACKAGE END

# ============================================================================ PUBLISH_PACKAGE BEGIN
# Expose the verified generation atomically and then retire previous generations.
publish_package() {
    local generation=".packages/prefix.${work##*.}"
    call 'ensure_package_links()'
    switch_package_generation "$generation"
    prune_old_generations "$generation"
}
# ============================================================================ PUBLISH_PACKAGE END

# ============================================================================ ENSURE_PACKAGE_LINKS BEGIN
# Establish and validate the public bin, include and lib links through package/.
ensure_package_links() {
    local dir
    for dir in bin include lib; do
        if [[ ! -e $out/$dir && ! -L $out/$dir ]]; then ln -s "package/$dir" "$out/$dir"; fi
        [[ $(readlink -- "$out/$dir") == "package/$dir" ]] || die "Unexpected package path: $out/$dir"
    done
}
# ============================================================================ ENSURE_PACKAGE_LINKS END

# ============================================================================ SWITCH_PACKAGE_GENERATION BEGIN
# Move the staged prefix to relative path $1 and atomically switch the package link.
switch_package_generation() {
    local generation=$1
    mv -T -- "$stage" "$out/$generation"
    ln -s "$generation" "$work/current"
    mv -Tf -- "$work/current" "$out/package"
}
# ============================================================================ SWITCH_PACKAGE_GENERATION END

# ============================================================================ PRUNE_OLD_GENERATIONS BEGIN
# Remove obsolete generations, retaining the published relative path supplied as $1.
prune_old_generations() {
    local keep="$out/$1" old
    for old in "$out"/.packages/prefix.*; do
        if [[ $old != "$keep" ]]; then rm -rf -- "$old"; fi
    done
}
# ============================================================================ PRUNE_OLD_GENERATIONS END

# ============================================================================ REPORT_SUCCESS BEGIN
# Report the SQLite version and output root of the successful build.
report_success() {
    printf 'Built SQLite %s in %s\n' "$version" "$out"
}
# ============================================================================ REPORT_SUCCESS END

# ============================================================================ DISPATCHER BEGIN
main "$@"
# ============================================================================ DISPATCHER END
