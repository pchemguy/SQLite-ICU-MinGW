# ============================================================================ PREPARE_PBLOB BEGIN
# Prepare PBLOB's FP16 headers and SQLite result-subtype registration in tsrc.
prepare_pblob() {
    stage_fp16_headers
    declare_pblob_result_subtype
}
# ============================================================================ PREPARE_PBLOB END

# ============================================================================ STAGE_FP16_HEADERS BEGIN
# Extract the FP16 archive recorded by this hook and install its headers in tsrc.
stage_fp16_headers() {
    local headers
    headers=$(unpack_zip "$fp16" "${work:?}/fp16" include/fp16/fp16.h include/fp16/bitcasts.h include/fp16/macros.h)
    cp -R -- "$headers/include/." "${tsrc:?}/"
}
# ============================================================================ STAGE_FP16_HEADERS END

# ============================================================================ DECLARE_PBLOB_RESULT_SUBTYPE BEGIN
# Declare that the staged unpacker returns JSON subtypes for SQLite's strict CLI.
declare_pblob_result_subtype() {
    sed -i -E 's/("pblob_unpack",[[:space:]]*1,[[:space:]]*flags)([[:space:]]*,)/\1 | SQLITE_RESULT_SUBTYPE\2/' "$tsrc/pblob.c"
}
# ============================================================================ DECLARE_PBLOB_RESULT_SUBTYPE END

if (( SQLITE_ENABLE_PBLOB )); then
    project_source SQLitePackedBlob pblob PBLOB
    # The deferred preparation callback also uses this archive path.
    fp16="${cache:?}/fp16_master.zip"
    download https://github.com/Maratyszcza/FP16/archive/refs/heads/master.zip "$fp16"
    header_archives+=("$fp16")
    prepare_steps+=(prepare_pblob)
    smoke_tests+=("SELECT json_array(pblob_unpack(pblob_pack('[1,2]'))) = '[[1.0,2.0]]'")
fi
