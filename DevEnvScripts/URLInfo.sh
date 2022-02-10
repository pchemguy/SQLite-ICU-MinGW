#!/bin/bash
#
# Verifies URL.
# 
# The script uses cURL to verify that the given URL returns "HTTP/1.1 200 OK"
# (follows any redirects). The script also attempts to determine the file size
# and final URL (if redirected).
# 
# Sets:
#   "FileLen" - file size (this value, if set, is likely meaningless for a web
#               page).
#   "ResURL"  - final URL.
# 
# Arguments:
#   ${1} - URL
# 
# On failure:
#   EXITCODE <> 0
# 
# Examples:
#   URLInfo.bat https://github.com/unicode-org/icu/releases/download/release-70-1/icu4c-70_1-Win32-MSVC2019.zip
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
ResCod=200
ResLen=0
ResURL=""


check_args() {
  if [[ -z "${1}" ]]; then
    echo "URL is not supplied."
    EXITCODE=1
  fi
  (( EXITCODE != 0 )) \
    && echo "Correct arguments have not been provided to get URL info." \
    && exit ${EXITCODE}

  EXITCODE=0
  return ${EXITCODE}
}


url_info() {
  local URL="${1}"
  stdout=""
  stdout=($(curl -Is -L ${URL})) || EXITCODE=$?
  (( EXITCODE != 0 )) || [[ -z "${stdout}" ]] \
    && echo "----- URL fetching error #${EXITCODE} -----" \
    && exit ${EXITCODE}

  IFS='~'
  for line in "${stdout[@]}"; do
    line="${line/ /"~"}"
    Fields=(${line})
    FieldName="${Fields[0]}"
    FieldValue="${Fields[1]:-}"

    case "${FieldName,,}" in
      http/[1-9.]*)
        ResCod=${FieldValue:0:3}
        ;;
      location:)
        ResURL="${FieldValue}"
        ;;
      content-length:)
        FileLen=${FieldValue}
        ;;
    esac
  done
  IFS=$'\n\t'

  if [[ "${ResCod}" -eq 404 ]]; then
    echo "----- URL not found: ${URL} -----"
    exit 1
  fi

  return 0
}


main() {
  check_args $@ || EXITCODE=$?
  url_info ${1} || EXITCODE=$?

  return ${EXITCODE}
}


main "$@"


# trim() {
#   # Determine if 'extglob' is currently on.
#   local extglobWasOff=1
#   shopt extglob >/dev/null && extglobWasOff=0 
#   (( extglobWasOff )) && shopt -s extglob # Turn 'extglob' on, if currently turned off.
#   # Trim leading and trailing whitespace
#   local var=$1
#   var=${var##+([[:space:]])}
#   var=${var%%+([[:space:]])}
#   (( extglobWasOff )) && shopt -u extglob # If 'extglob' was off before, turn it back off.
#   echo -n "$var"  # Output trimmed string.
# }
