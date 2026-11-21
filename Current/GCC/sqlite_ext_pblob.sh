prepare_pblob() {
    local headers
    headers=$(unpack_zip "$fp16" "${work:?}/fp16" include/fp16/fp16.h include/fp16/bitcasts.h include/fp16/macros.h)
    cp -R -- "$headers/include/." "${tsrc:?}/"
    # The upstream unpacker returns JSON with sqlite3_result_subtype(). Its
    # registration must declare that capability for SQLite's strict CLI.
    sed -i -E 's/("pblob_unpack",[[:space:]]*1,[[:space:]]*flags)([[:space:]]*,)/\1 | SQLITE_RESULT_SUBTYPE\2/' "$tsrc/pblob.c"
}

if (( SQLITE_ENABLE_PBLOB )); then
    project_source SQLitePackedBlob pblob PBLOB
    fp16="${cache:?}/fp16_master.zip"
    download https://github.com/Maratyszcza/FP16/archive/refs/heads/master.zip "$fp16"
    header_archives+=("$fp16")
    prepare_steps+=(prepare_pblob)
    smoke_tests+=("SELECT json_array(pblob_unpack(pblob_pack('[1,2]'))) = '[[1.0,2.0]]'")
fi
