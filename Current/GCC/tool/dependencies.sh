# Package operations are limited to missing requirements of the selected build.

# Install the supplied APT or DNF packages, refreshing the APT index once per run.
install_packages() {
    local deb_names=$1 rpm_names=$2
    local -a command elevate=() packages
    if command -v apt-get >/dev/null; then
        read -ra packages <<< "$deb_names"
        command=(apt-get install -y --no-install-recommends)
    elif command -v dnf >/dev/null; then
        read -ra packages <<< "$rpm_names"
        command=(dnf install -y)
    else
        die "Install the development packages for this build ($deb_names on Debian or $rpm_names on Fedora), then rerun."
    fi
    if (( EUID != 0 )); then
        command -v sudo >/dev/null || die "Administrator privileges required. Run: ${command[*]} ${packages[*]}"
        elevate=(sudo)
    fi
    if [[ ${command[0]} == apt-get && $apt_updated == 0 ]]; then
        "${elevate[@]}" apt-get update || die "apt-get update failed while preparing ${packages[*]}."
        apt_updated=1
    fi
    "${elevate[@]}" "${command[@]}" "${packages[@]}" || die "Failed to run: ${command[*]} ${packages[*]}"
}

# Probe the selected ICU and zlib modules, install missing packages, and verify them.
ensure_dependencies() {
    local apt_updated=0
    local -a deb=() rpm=() modules=()
    if (( !USE_ICU && !SQLITE_EXTRA )); then return; fi
    if ! command -v pkg-config >/dev/null; then
        install_packages pkg-config pkgconf-pkg-config
    fi
    if (( USE_ICU )); then
        modules+=(icu-i18n icu-uc)
        if ! pkg-config --exists icu-i18n icu-uc; then
            deb+=(libicu-dev)
            rpm+=(libicu-devel)
        fi
    fi
    if (( SQLITE_EXTRA )); then
        modules+=(zlib)
        if ! pkg-config --exists zlib; then
            deb+=(zlib1g-dev)
            rpm+=('pkgconfig(zlib)')
        fi
    fi
    if (( ${#deb[@]} )); then install_packages "${deb[*]}" "${rpm[*]}"; fi
    pkg-config --print-errors --exists "${modules[@]}" || die "Missing pkg-config modules: ${modules[*]}"
}
