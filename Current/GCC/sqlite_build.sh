#!/usr/bin/env bash
# Build SQLite and its selected built-ins from the canonical source tree.
set -euo pipefail
export LC_ALL=C
shopt -s nullglob

die() { printf 'sqlite_build: %s\n' "$*" >&2; exit 1; }
usage() {
    printf '%s\n' 'Usage: sqlite_build.sh [--preset bare|bare-icu|bare-icu-ext|full] [clean]' \
        'The default is full. OUT_DIR selects the local build and install root.'
}

preset=full
action=build
while (( $# )); do
    case $1 in
        --preset) (( $# >= 2 )) || die '--preset requires a name'; preset=$2; shift 2 ;;
        clean) action=clean; shift ;;
        -h|--help) usage; exit 0 ;;
        *) die "Unknown argument: $1" ;;
    esac
done
case $preset in
    bare)         icu=0; stock=0; extras=0 ;;
    bare-icu)     icu=1; stock=0; extras=0 ;;
    bare-icu-ext) icu=1; stock=1; extras=0 ;;
    full)         icu=1; stock=1; extras=1 ;;
    *) die "Unknown preset: $preset" ;;
esac

base=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
out=$(realpath -m -- "${OUT_DIR:-$base/out}")
[[ $out != / ]] || die 'OUT_DIR must identify a dedicated build root.'
if [[ $action == clean && ! -d $out ]]; then exit 0; fi
mkdir -p -- "$out"
exec {lockfd}>"$out/.sqlite-build.lock"
flock "$lockfd"
marker=$out/.sqlite-gcc-root
if [[ ! -f $marker ]]; then
    if [[ $action == clean ]]; then die "Unmanaged output directory: $out"; fi
    for managed in build sqlite .packages package bin include lib; do
        [[ ! -e $out/$managed && ! -L $out/$managed ]] || die "Existing unmanaged path: $out/$managed"
    done
    touch "$marker"
fi
if [[ $action == clean ]]; then
    rm -rf -- "${out:?}"/{build,sqlite,.packages,package,bin,include,lib}
    exit 0
fi
[[ $out != *' '* ]] || die 'SQLite configure requires a space-free OUT_DIR.'

: "${USE_ICU=$icu}" "${SQLITE_EXTRA=$stock}" "${USE_EXTRAS=$extras}"
: "${SQLITE_ENABLE_ICUEX=$USE_ICU}" "${SQLITE_ENABLE_PBLOB=1}" "${SQLITE_ENABLE_REGEXPMATCHES=$SQLITE_EXTRA}"
for flag in USE_ICU SQLITE_EXTRA USE_EXTRAS SQLITE_ENABLE_ICUEX SQLITE_ENABLE_PBLOB SQLITE_ENABLE_REGEXPMATCHES; do
    [[ ${!flag} =~ ^[01]$ ]] || die "$flag must be 0 or 1."
done
if (( USE_EXTRAS && SQLITE_ENABLE_ICUEX && !USE_ICU )); then die 'ICUex requires USE_ICU=1.'; fi
if (( USE_EXTRAS && SQLITE_ENABLE_REGEXPMATCHES && !SQLITE_EXTRA )); then die 'RegexpMatches requires SQLITE_EXTRA=1 (stock regexp.c).'; fi
: "${CC:=gcc}" "${CFLAGS:=-O2}" "${JOBS:=$(getconf _NPROCESSORS_ONLN)}"
[[ $JOBS =~ ^[1-9][0-9]*$ ]] || die 'JOBS must be a positive integer.'
export CC CFLAGS
source "$base/tool/dependencies.sh"
source "$base/tool/sources.sh"
ensure_dependencies

cache=$out/cache
src=$out/sqlite
build=$out/build
work=$(mktemp -d "$out/.work.XXXXXXXX")
trap 'rm -rf -- "$work"' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
mkdir -p -- "$cache"
sqlite_zip=$cache/sqlite.zip
download https://sqlite.org/src/zip/sqlite.zip "$sqlite_zip"
archive_hash=$(sha256sum < "$sqlite_zip")
archive_hash=${archive_hash%% *}
if [[ ! -f $src/.archive-sha256 || $(<"$src/.archive-sha256") != "$archive_hash" ]]; then
    unpacked=$(unpack_zip "$sqlite_zip" "$work/sqlite" configure main.mk tool/mksqlite3c.tcl)
    printf '%s\n' "$archive_hash" > "$unpacked/.archive-sha256"
    if [[ -e $src ]]; then mv -T -- "$src" "$work/previous-source"; fi
    mv -T -- "$unpacked" "$src"
fi

configure_args=(--prefix="$out" --enable-shared --enable-static --soname=legacy --disable-rpath
    --disable-tcl --enable-session --enable-fts3 --enable-fts4 --enable-fts5 --enable-rtree
    --enable-geopoly --enable-column-metadata --enable-dbpage --enable-dbstat --enable-carray)
options=(-DSQLITE_ENABLE_RBU -DSQLITE_ENABLE_API_ARMOR -DSQLITE_ENABLE_NORMALIZE
    -DSQLITE_ENABLE_FTS3_PARENTHESIS -DSQLITE_ENABLE_FTS3_TOKENIZER -DSQLITE_ENABLE_EXPLAIN_COMMENTS=1
    -DSQLITE_ENABLE_OFFSET_SQL_FUNC=1 -DSQLITE_ENABLE_QPSG -DSQLITE_ENABLE_STAT4 -DSQLITE_DQS=0
    -DSQLITE_LIKE_DOESNT_MATCH_BLOBS -DSQLITE_MAX_EXPR_DEPTH=100 -DSQLITE_MAX_ATTACHED=100
    -DSQLITE_OMIT_DEPRECATED -DSQLITE_DEFAULT_FOREIGN_KEYS=1 -DSQLITE_DEFAULT_SYNCHRONOUS=1
    -DSQLITE_USE_URI=1 -DSQLITE_SOUNDEX -DSQLITE_ENABLE_STMTVTAB -DSQLITE_ENABLE_BYTECODE_VTAB)
sources=() names=() macros=() hooks=()
header_archives=() prepare_steps=() smoke_tests=()
if (( USE_ICU )); then
    # Fedora declares the ICU libraries as private dependencies of icu-io.
    # Link the two C APIs SQLite uses directly on every distribution.
    icu_cflags=$(pkg-config --cflags icu-i18n icu-uc)
    configure_args+=("--with-icu-ldflags=$(pkg-config --libs icu-i18n icu-uc)"
        "--with-icu-cflags=$icu_cflags" --enable-icu-collations)
    export CPPFLAGS="${CPPFLAGS:-} $icu_cflags"
fi
if (( SQLITE_EXTRA )); then
    CPPFLAGS="${CPPFLAGS:-} $(pkg-config --cflags zlib)"
    LDFLAGS="${LDFLAGS:-} $(pkg-config --libs-only-L zlib)"
    export CPPFLAGS LDFLAGS
    for name in compress csv decimal fuzzer noop prefixes regexp remember rot13 series sha1 shathree sqlar uint uuid; do
        case $name in
            rot13) macro=ROT ;;
            sha1)  macro=SHA ;;
            *)     macro=${name^^} ;;
        esac
        add_source "$src/ext/misc/$name.c" "$macro"
    done
fi
if (( USE_EXTRAS )); then
    hooks=("$base"/sqlite_ext_*.sh)
    for hook in "${hooks[@]}"; do
        # shellcheck source=/dev/null
        source "$hook"
    done
fi

extra_src=()
if (( ${#names[@]} )); then
    options+=(-DSQLITE_EXTRA_AUTOEXT=sqlite3ExtraAutoExtInit "${macros[@]/#/-DSQLITE_ENABLE_}")
    extra_src=("${names[@]/#/tsrc/}" tsrc/misc_ext_init.c)
fi
printf 'Preset %s | ICU=%s stock=%s project hooks=%s | %s\n' "$preset" "$USE_ICU" "$SQLITE_EXTRA" "$USE_EXTRAS" "$out"
make_sqlite() {
    make -C "$build" -j "$JOBS" "OPTIONS=${options[*]}" "$@"
}

# Store the effective build inputs in readable form. A cache replacement or a
# change of compiler, flags, dependencies or hooks invalidates generated code.
inputs=$work/build-inputs.txt
{
    printf 'SQLite archive: %s\nCompiler: %s\n' "$archive_hash" "$(command -v "$CC")"
    "$CC" -dumpmachine
    "$CC" --version
    printf '%s\n' "${configure_args[@]}" "${options[@]}" "${extra_src[@]}"
    for var in CFLAGS CPPFLAGS LDFLAGS CPATH LIBRARY_PATH PKG_CONFIG_PATH PKG_CONFIG_LIBDIR PKG_CONFIG_SYSROOT_DIR; do
        printf '%s=%s\n' "$var" "${!var-}"
    done
    for module in zlib icu-i18n icu-uc; do
        if [[ $module == icu-* && $USE_ICU == 0 ]]; then continue; fi
        if command -v pkg-config >/dev/null && pkg-config --exists "$module"; then
            printf '%s: ' "$module"; pkg-config --modversion "$module"
            pkg-config --cflags --libs "$module"
        else
            printf '%s: no pkg-config metadata\n' "$module"
            if [[ $module == zlib ]] && printf '#include <zlib.h>\nint main(void){return !zlibVersion();}\n' |
                "$CC" -x c - -lz -o "$work/check-zlib" 2>/dev/null; then
                printf 'zlib: system headers and library found\n'
            fi
        fi
    done
    sha256sum -- "$base/sqlite_build.sh" "$base"/tool/*.sh "$base"/tool/*.tcl \
        "${hooks[@]}" "${sources[@]}" "${header_archives[@]}"
} > "$inputs"

if ! cmp -s "$inputs" "$build/build-inputs.txt"; then
    rm -rf -- "$build"
    mkdir -p -- "$build"
    (cd "$build" && "$src/configure" "${configure_args[@]}")
    if (( SQLITE_EXTRA )); then
        grep -Eq '^LDFLAGS\.zlib *=.*-lz' "$build/Makefile" || die 'SQLite configure did not find the required zlib.'
    fi
    cp -- "$inputs" "$build/build-inputs.txt"
fi
tsrc=$build/tsrc
if [[ ! -s $tsrc/sqlite3.h ]]; then rm -f -- "$build/.target_source"; fi
make_sqlite .target_source
for staged in "${extra_src[@]}"; do
    if [[ ! -s $build/$staged ]]; then rm -f -- "$tsrc/.extensions-ready"; break; fi
done
if (( ${#names[@]} )) && [[ ! -f $tsrc/.extensions-ready || $build/.target_source -nt $tsrc/.extensions-ready ]]; then
    cp -- "${sources[@]}" "$tsrc/"
    for prepare in "${prepare_steps[@]}"; do "$prepare"; done
    rm -f -- "$tsrc/misc_ext_init.c"
    if command -v tclsh >/dev/null; then
        tcl=$(command -v tclsh)
    else
        make_sqlite jimsh
        tcl=$build/jimsh
    fi
    (cd "$tsrc" && "$tcl" "$base/tool/patch_sqlite_misc_autoext.tcl" "${names[@]}")
    for macro in "${macros[@]}"; do
        grep -Fxq "#ifdef SQLITE_ENABLE_$macro" "$tsrc/misc_ext_init.c" || die "Missing dispatcher entry: $macro"
    done
    (cd "$tsrc" && BUNDLE_EXTRA_SRC_TRACE=${BUNDLE_EXTRA_SRC_TRACE:-0} "$tcl" "$base/tool/bundle_extra_src.tcl" "${names[@]}")
    touch "$tsrc/.extensions-ready"
fi
make_sqlite "EXTRA_SRC=${extra_src[*]}" sqlite3 libsqlite3.so libsqlite3.a

# Keep the last successful distribution visible until the new CLI, libraries,
# headers and consumer metadata are all staged and the packaged CLI starts.
stage=$work/prefix
version=$(<"$src/VERSION")
mkdir -p -- "$stage"/{bin,include,lib/pkgconfig} "$out/.packages"
install -m755 -- "$build/sqlite3" "$stage/bin/"
install -m755 -- "$build/libsqlite3.so" "$stage/lib/libsqlite3.so.$version"
ln -s "libsqlite3.so.$version" "$stage/lib/libsqlite3.so.0"
ln -s "libsqlite3.so.$version" "$stage/lib/libsqlite3.so"
install -m644 -- "$build/libsqlite3.a" "$stage/lib/"
install -m644 -- "$build"/{sqlite3.h,sqlite3ext.h,sqlite3session.h} "$stage/include/"
# pkg-config expands pcfiledir when the consumer locates the installed package.
# shellcheck disable=SC2016
sed 's|^prefix=.*|prefix=${pcfiledir}/../..|' "$build/sqlite3.pc" > "$stage/lib/pkgconfig/sqlite3.pc"
[[ $("$stage/bin/sqlite3" -batch -init /dev/null :memory: 'SELECT sqlite_version()') == "$version" ]] || die 'Packaged CLI verification failed.'
for query in "${smoke_tests[@]}"; do
    [[ $("$stage/bin/sqlite3" -batch -init /dev/null :memory: "$query") == 1 ]] || die "Packaged CLI check failed: $query"
done
for dir in bin include lib; do
    if [[ ! -e $out/$dir && ! -L $out/$dir ]]; then ln -s "package/$dir" "$out/$dir"; fi
    [[ $(readlink -- "$out/$dir") == "package/$dir" ]] || die "Unexpected package path: $out/$dir"
done
generation=".packages/prefix.${work##*.}"
mv -T -- "$stage" "$out/$generation"
ln -s "$generation" "$work/current"
mv -Tf -- "$work/current" "$out/package"
for old in "$out"/.packages/prefix.*; do
    if [[ $old != "$out/$generation" ]]; then rm -rf -- "$old"; fi
done
printf 'Built SQLite %s in %s\n' "$version" "$out"
