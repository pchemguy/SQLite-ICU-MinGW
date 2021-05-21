#!/bin/sh
#
set -euo pipefail
IFS=$'\n\t'

cleanup_EXIT() { 
  echo "EXIT clean up: $?" 
}
trap cleanup_EXIT EXIT

cleanup_TERM() {
  echo "TERM clean up: $?"
}
trap cleanup_TERM TERM

cleanup_ERR() {
  echo "ERR clean up: $?"
}
trap cleanup_ERR ERR

EXITCODE=0
EC=0
BASEDIR="$(dirname "$(realpath "$0")")"
readonly BASEDIR
readonly ICU_ROOT="${BASEDIR}/icu"
readonly SRC="${ICU_ROOT}/source"
readonly BLD="${ICU_ROOT}/build"
readonly DST="${ICU_ROOT}/dist"
readonly VERSION="68.2"


get_icu() {
  local readonly SRC_ARC="icu4c-${VERSION/./_}-src.tgz"
  cd "${BASEDIR}" || ( echo "Cannot enter ${BASEDIR}" && exit 101 )
  local ICU_URL="https://github.com/unicode-org/icu/releases/download/release-${VERSION/./-}/${SRC_ARC}"
  if [[ ! -f ./${SRC_ARC} ]]; then
    echo "_____________________________"
    echo "Downloading ICU ${VERSION}..."
    echo "-----------------------------"
    wget -c "${ICU_URL}" --no-check-certificate -O ${SRC_ARC} \
      || EC=$?
    (( EC != 0 )) && echo "Error downloading ICU ${EC}." && exit 102
  else
    echo "_____________________________________________"
    echo "Using previously downloaded archive of ICU..."
    echo "---------------------------------------------"
  fi

  if [[ ! -f "./${SRC}/configure" ]]; then
    tar xzf ./${SRC_ARC}
  fi
  return 0
}


configure_icu() {
  local readonly CONFIGURE_FLAGS=(
    --disable-extras
    --disable-tests
    --disable-samples
    --disable-static
    --enable-shared
  )
  #LIBS=(-static)
  #LIBS="${LIBS[@]}" 

  mkdir -p "${BLD}"
  mkdir -p "${DST}"
  cd "${BLD}" || ( echo "Cannot enter ${BLD}" && exit 101 )

  if [[ ! -f ./Makefile ]]; then
    [[ ! -r "${SRC}/configure" ]] && echo "Cannot access configure" && exit 102
    echo "__________________"
    echo "Configuring ICU..."
    echo "------------------"
    "${SRC}/runConfigureICU" MinGW --prefix="${DST}" ${CONFIGURE_FLAGS[@]} || EXITCODE=$?
    (( EXITCODE != 0 )) && echo "Error configuring ICU" && exit 103
  else
    echo "____________________________________________"
  	echo "Makefile found. Skipping configuring ICU"
    echo "--------------------------------------------"
  fi
    
  return 0
}  


patch_icu_makefile() {
  cd "${BLD}" || ( echo "Cannot enter ${BLD}" && exit 104 )

  local DEFAULT_LIBS=(
    -Wl,--allow-multiple-definition
    -static-libgcc
    -static-libstdc++
    -Wl,-Bstatic -lpthread -Wl,--whole-archive -lwinpthread -Wl,-Bdynamic,--no-whole-archive
    -ldl -lm
  )
  readonly DEFAULT_LIBS="${DEFAULT_LIBS[@]}"

  echo "________________________"
  echo "Patching ICU Makefile..."
  echo "------------------------"
  sed -e "s/^DEFAULT_LIBS = .*$/DEFAULT_LIBS = ${DEFAULT_LIBS}/;" \
      -i icudefs.mk
  return 0
}


main() {
  get_icu || EXITCODE=$?
  (( EXITCODE != 0 )) && echo "Error downloading ICU" && exit 201
  configure_icu || EXITCODE=$?
  (( EXITCODE != 0 )) && echo "Error configuring ICU" && exit 202
  patch_icu_makefile || EXITCODE=$?

  VERBOSE=1 make -j6
  make install

  return 0
}


main "$@"
