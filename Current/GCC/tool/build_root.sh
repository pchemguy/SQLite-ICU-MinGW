# Shared output paths, locking and ownership for the GCC build drivers.

# Resolve the dedicated output root and the paths owned by the build harness.
resolve_output_root() {
  out=$(realpath -m -- "${OUT_DIR:-${base}/out}")
  [[ ${out} != / ]] || die 'OUT_DIR must identify a dedicated build root.'
  managed_paths=("${out}/build" "${out}/sqlite" "${out}/.packages" "${out}/package"
                 "${out}/bin" "${out}/include" "${out}/lib")
}

# Create and lock the build root, then establish ownership of its output paths.
open_build_root() {
  mkdir -p -- "${out}"
  lock_output_root
  check_output_ownership "$1"
  [[ ${out} != *' '* ]] || die 'SQLite configure requires a space-free OUT_DIR.'
}

# Reuse the wrapper's open lock descriptor or acquire the lock for a standalone build.
lock_output_root() {
  local inherited=${SQLITE_BUILD_LOCK_FD:-}
  if [[ ${inherited} =~ ^[0-9]+$ && /dev/fd/${inherited} -ef ${out}/.sqlite-build.lock ]]; then
    lockfd=${inherited}
  else
    exec {lockfd}>"${out}/.sqlite-build.lock"
  fi
  flock "${lockfd}"
}

# A fresh wrapper build also owns the two outputs it explicitly replaces.
check_output_ownership() {
  local marker=${out}/.sqlite-gcc-root path
  if [[ -f ${marker} ]]; then return 0; fi
  if [[ $1 == clean ]]; then die "Unmanaged output directory: ${out}"; fi
  for path in "${managed_paths[@]}"; do
    if [[ $1 == rebuild && ( ${path} == "${out}/bin" || ${path} == "${out}/build" ) ]]; then
      continue
    fi
    [[ ! -e ${path} && ! -L ${path} ]] || die "Existing unmanaged path: ${path}"
  done
  touch "${marker}"
}
