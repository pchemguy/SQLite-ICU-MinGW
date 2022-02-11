#!/bin/bash
#
# Downloads file via cURL.
#
# The script uses cURL to download a file and verifies file size (via URLInfo.bat).
#
# Arguments:
#   %1 - URL
#   %2 - File name (optional; if not provided, tries to extract the last part of the URL)
#
# On failure:
#   ResultCode <> 0
#
# Examples:
#   DownloadFile.bat https://github.com/unicode-org/icu/releases/download/release-70-1/icu4c-70_1-Win32-MSVC2019.zip icu4c-70_1-Win32-MSVC2019.zip
#   DownloadFile.bat https://github.com/unicode-org/icu/releases/download/release-70-1/icu4c-70_1-Win32-MSVC2019.zip
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
readonly BASEDIR="$(dirname "$(realpath "$0")")"
FileURL=""
FileName=""
FileSize=""


check_args() {
  EXITCODE=0
  FileURL="${1}"
  if [[ -z "${FileURL}" ]]; then
    echo "File URL is not supplied."
    EXITCODE=1
  fi
  (( EXITCODE != 0 )) \
    && echo "Correct arguments have not been provided to download file." \
    && exit ${EXITCODE}
  FileName="${2}"
  [[ -z "${FileName}" ]] && FileName="$(basename "${FileURL}")"

  return 0
}


# Before downloading ${FileName} file, check if ${FileName}.size file exists.
# If not, get file size via URLInfo.sh and save it to ${FileName}.size.
# 
check_meta() {
  EXITCODE=0
  if [[ -f "${FileName}.size" ]]; then
    read -r FileLen <"${FileName}.size"
  else
    . "${BASEDIR}/URLInfo.bat" ${FileURL} || EXITCODE=$?
    (( EXITCODE != 0 )) && echo "----- URL error -----" && exit ${EXITCODE}
    [[ ! -z "${FileLen}" ]] && echo "${FileLen}" >"${FileName}.size"
  fi

  return 0
}


# If the ${FileName} file has been downloaded and saved previously, its size
# should be in the ${FileName}.size file. If the actual file size does not
# match the associated meta value, the cached copy is deleted.
#
check_cache() {
  if [[ -f "${FileName}" ]]; then
    if [[ -z "${FileLen}" ]]; then
      echo "========= Using previously downloaded ${FileName} ========="
      echo "Warning: file size information is not available."
      echo "-----------------------------------------------------------"
      return 0
    fi
    FileSize=$(stat -c %s "${FileName}")
    if [[ ${FileSize} -eq ${FileLen} ]]; then
      echo "========= Using previously downloaded ${FileName} ========="
      echo "-----------------------------------------------------------"
      return 0
    else
      echo "----- File size saved in file \"${FileName}.size\" does not match the size of cached copy: -----"
      echo "Saved file size:     ==${FileLen}=="
      echo "Size of cached copy: ==${FileSize}=="
      echo -e "Dowloading again.\n"
      rm -f "${FileName}"
    fi
  fi

  return 0
}


download_file() {
  EXITCODE=0
  echo "===== Downloading ${FileName} ====="
  curl -L ${FileURL} --output "${FileName}" || EXITCODE=$?
  (( EXITCODE != 0 )) && echo "----- Download error -----" && exit ${EXITCODE}

  # Verify that the size of the downloaded file matches the saved value. If not,
  # both the target file and its companion holding the size are renamed as invalid.
  # Skip check if size information is not available.
  [[ ${FileLen} -eq 0 ]] && FileLen="" && echo "" >"${FileName}.size"
  if [[ -z "${FileLen}" ]]; then
    echo "Warning: file size information is not available."
    FileSize=""
  else
    FileSize=$(stat -c %s "${FileName}")
  fi

  if [[ ${FileSize} -eq ${FileLen} ]]; then
    echo "----- Downloaded ${FileName}  -----"
  else
    echo "Error downloading ${FileName} - file size mismatch. Run the processes again."
    echo -e "File renamed to ${FileName}.$$$.\n"
    mv "${FileName}" "${FileName}.$$$" 1>/dev/null
    mv "${FileName}.size" "${FileName}.size.$$$" 1>/dev/null
    EXITCODE=1
  fi
  echo -e "----------------------------------------------------------\n"

  return ${EXITCODE}
}


main() {
  echo ""
  echo "==================== Downloading file ===================="

  check_args || EXITCODE=$?
  check_cache || EXITCODE=$?
  download_file || EXITCODE=$?

  return ${EXITCODE}
}


main "$@"
