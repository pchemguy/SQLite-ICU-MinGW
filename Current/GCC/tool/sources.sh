# Shared by the driver and the sqlite_ext_*.sh hooks.

download() {
    local url=$1 target=$2 response code media
    if [[ -s $target && -f $target ]]; then return; fi
    mkdir -p -- "$(dirname -- "$target")"
    printf 'Fetching %s\n' "$url" >&2
    response=$(curl --fail --location --retry 3 --silent --show-error \
        --output "${work:?}/download.part" --write-out '%{http_code} %{content_type}' -- "$url") ||
        die "Download failed: $url"
    code=${response%% *}
    media=${response#* }
    media=${media,,}
    if [[ $code != 200 || $media =~ ^[[:space:]]*text/html([[:space:]]*\;|[[:space:]]*$) || ! -s $work/download.part ]]; then
        die "Invalid download ($response): $url"
    fi
    mv -fT -- "$work/download.part" "$target"
}

unpack_zip() {
    local archive=$1 destination=$2
    shift 2
    local -a roots
    local expected
    mkdir -p -- "$destination" || die "Cannot create $destination"
    unzip -qo "$archive" -d "$destination" || die "Cannot extract $archive"
    roots=("$destination"/*)
    [[ ${#roots[@]} == 1 && -d ${roots[0]} ]] || die "Expected a single source directory in $archive"
    for expected in "$@"; do
        [[ -s ${roots[0]}/$expected ]] || die "Missing $expected in $archive"
    done
    printf '%s\n' "${roots[0]}"
}

add_source() {
    sources+=("$1")
    names+=("${1##*/}")
    macros+=("$2")
}

project_source() {
    local repo=$1 name=$2 macro=$3
    local file="${cache:?}/$repo/src/$name.c"
    download "https://raw.githubusercontent.com/pchemguy/$repo/refs/heads/main/src/$name.c" "$file"
    add_source "$file" "$macro"
}
