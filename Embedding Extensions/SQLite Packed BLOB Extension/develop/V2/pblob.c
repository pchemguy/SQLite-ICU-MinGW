/*
** pblob.c
**
** Packed Blob SQLite auto-extension.
**
** SQL interface:
**
**   pblob_pack(json_vector)
**   pblob_pack(json_vector, format)
**   pblob_unpack(blob_data)
**
** Supported formats:
**
**   <f2   IEEE binary16, little-endian
**   >f2   IEEE binary16, big-endian
**   <f4   IEEE binary32, little-endian
**   >f4   IEEE binary32, big-endian
**
** The one-argument pblob_pack() form defaults to >f2.
**
** Packed BLOB layout:
**
**   [packed payload][4-byte trailer]
**
** Trailer metadata format
**
**   Four equal bytes, each encoding:
**
**     bit 0     reserved, must be 1
**     bit 1     endian: 0 = little, 1 = big
**     bit 2     type:   0 = f2,     1 = f4
**     bits 3-7  reserved, must be 0
**
**     001 = f2 LE
**     011 = f2 BE
**     101 = f4 LE
**     111 = f4 BE
**
** This source is intended to be incorporated into the SQLite amalgamation
** after json.c.  It deliberately uses SQLite JSON implementation internals
** that are not part of the public extension API.
*/

#ifndef SQLITE_OMIT_JSON

#include <stdint.h>
#include <string.h>

#include <fp16/fp16.h>


#define PBLOB_TRAILER_SIZE 4

typedef enum PBlobFormat {
    PBLOB_F16_LE = 0x01010101,
    PBLOB_F16_BE = 0x03030303,
    PBLOB_F32_LE = 0x05050505,
    PBLOB_F32_BE = 0x07070707
} PBlobFormat;

typedef struct PBlobFormatInfo {
    PBlobFormat format;
    u8 tag;
    u8 elementSize;
    u8 bigEndian;
    u8 isF32;
} PBlobFormatInfo;


/*
** Set a pblob-specific SQL error and return SQLITE_ERROR.
*/
static int pblobError(sqlite3_context *ctx, const char *zMsg) {
    sqlite3_result_error(ctx, zMsg, -1);
    return SQLITE_ERROR;
}

/*
** Decode a valid one-byte format tag.
*/
static int pblobFormatFromTag(
    sqlite3_context *ctx,
    u8 tag,
    PBlobFormatInfo *pInfo
) {
    switch(tag) {
        case 0x01:
            pInfo->format = PBLOB_F16_LE;
            pInfo->tag = tag;
            pInfo->elementSize = 2;
            pInfo->bigEndian = 0;
            pInfo->isF32 = 0;
            return SQLITE_OK;

        case 0x03:
            pInfo->format = PBLOB_F16_BE;
            pInfo->tag = tag;
            pInfo->elementSize = 2;
            pInfo->bigEndian = 1;
            pInfo->isF32 = 0;
            return SQLITE_OK;

        case 0x05:
            pInfo->format = PBLOB_F32_LE;
            pInfo->tag = tag;
            pInfo->elementSize = 4;
            pInfo->bigEndian = 0;
            pInfo->isF32 = 1;
            return SQLITE_OK;

        case 0x07:
            pInfo->format = PBLOB_F32_BE;
            pInfo->tag = tag;
            pInfo->elementSize = 4;
            pInfo->bigEndian = 1;
            pInfo->isF32 = 1;
            return SQLITE_OK;

        default:
            return pblobError(ctx, "invalid pblob format metadata");
    }
}

/*
** Parse the SQL format argument.
**
** Accepted values are exactly: <f2, >f2, <f4, >f4.
*/
static int pblobParseFormatArg(
    sqlite3_context *ctx,
    sqlite3_value *pValue,
    PBlobFormatInfo *pInfo
) {
    const unsigned char *z;
    int n;
    u8 tag;

    if (sqlite3_value_type(pValue) != SQLITE_TEXT) {
        return pblobError(ctx, "pblob format must be TEXT");
    }

    z = sqlite3_value_text(pValue);
    if (z == 0) {
        sqlite3_result_error_nomem(ctx);
        return SQLITE_NOMEM;
    }
    n = sqlite3_value_bytes(pValue);

    if (n != 3) {
        return pblobError(ctx, "invalid pblob format");
    }

    if (z[0] == '<' && z[1] == 'f' && z[2] == '2') {
        tag = 0x01;
    } else if (z[0] == '>' && z[1] == 'f' && z[2] == '2') {
        tag = 0x03;
    } else if (z[0] == '<' && z[1] == 'f' && z[2] == '4') {
        tag = 0x05;
    } else if (z[0] == '>' && z[1] == 'f' && z[2] == '4') {
        tag = 0x07;
    } else {
        return pblobError(ctx, "invalid pblob format");
    }

    return pblobFormatFromTag(ctx, tag, pInfo);
}

/*
** Validate and decode the four-byte trailer.
*/
static int pblobParseTrailer(
    sqlite3_context *ctx,
    const u8 *aBlob,
    sqlite3_uint64 nBlob,
    PBlobFormatInfo *pInfo
) {
    const u8 *p;

    if (nBlob < PBLOB_TRAILER_SIZE) {
        return pblobError(ctx, "pblob BLOB is too short");
    }

    p = &aBlob[nBlob-PBLOB_TRAILER_SIZE];

    if (p[0] != p[1] || p[0] != p[2] || p[0] != p[3]) {
        return pblobError(ctx, "invalid pblob format trailer");
    }

    return pblobFormatFromTag(ctx, p[0], pInfo);
}


/*
** Store an unsigned 16-bit value using explicit byte order.
*/
static void pblobWriteU16(u8 *p, uint16_t v, int bigEndian) {
    if (bigEndian) {
        p[0] = (u8)(v >> 8);
        p[1] = (u8)v;
    } else {
        p[0] = (u8)v;
        p[1] = (u8)(v >> 8);
    }
}

/*
** Load an unsigned 16-bit value using explicit byte order.
*/
static uint16_t pblobReadU16(const u8 *p, int bigEndian) {
    if (bigEndian) {
        return (uint16_t)(
            ((uint16_t)p[0] << 8) | (uint16_t)p[1]
        );
    } else {
        return (uint16_t)(
            (uint16_t)p[0] | ((uint16_t)p[1] << 8)
        );
    }
}

/*
** Store an unsigned 32-bit value using explicit byte order.
*/
static void pblobWriteU32(u8 *p, uint32_t v, int bigEndian) {
    if (bigEndian) {
        p[0] = (u8)(v >> 24);
        p[1] = (u8)(v >> 16);
        p[2] = (u8)(v >> 8);
        p[3] = (u8)v;
    } else {
        p[0] = (u8)v;
        p[1] = (u8)(v >> 8);
        p[2] = (u8)(v >> 16);
        p[3] = (u8)(v >> 24);
    }
}

/*
** Load an unsigned 32-bit value using explicit byte order.
*/
static uint32_t pblobReadU32(const u8 *p, int bigEndian) {
    if (bigEndian) {
        return
              ((uint32_t)p[0] << 24)
            | ((uint32_t)p[1] << 16)
            | ((uint32_t)p[2] << 8)
            |  (uint32_t)p[3];
    } else {
        return
               (uint32_t)p[0]
            | ((uint32_t)p[1] << 8)
            | ((uint32_t)p[2] << 16)
            | ((uint32_t)p[3] << 24);
    }
}


/*
** Convert a canonical JSON numeric node into a C double.
**
** Only JSONB_INT and JSONB_FLOAT are accepted.  JSON5 numeric node types
** are rejected by the caller before iteration and are rejected here as a
** second line of defense.
*/
static int pblobJsonNumberToDouble(
    sqlite3_context *ctx,
    JsonParse *pParse,
    u32 iNode,
    double *pValue
) {
    sqlite3 *db;
    u32 nHdr;
    u32 nPayload;
    u8 eType;
    char *z;
    int rc;

    nHdr = jsonbPayloadSize(pParse, iNode, &nPayload);
    if (nHdr == 0) {
        return pblobError(ctx, "malformed JSON");
    }

    eType = pParse->aBlob[iNode] & 0x0f;
    if (eType != JSONB_INT && eType != JSONB_FLOAT) {
        return pblobError(ctx, "JSON array must contain only ordinary numbers");
    }

    if (nPayload == 0) {
        return pblobError(ctx, "malformed JSON number");
    }

    db = sqlite3_context_db_handle(ctx);
    z = sqlite3DbStrNDup(
        db,
        (const char*)&pParse->aBlob[iNode+nHdr],
        (int)nPayload
    );
    if (z == 0) {
        sqlite3_result_error_nomem(ctx);
        return SQLITE_NOMEM;
    }

    rc = sqlite3AtoF(z, pValue);
    sqlite3DbFree(db, z);

    if (rc <= 0) {
        return pblobError(ctx, "malformed JSON number");
    }

    return SQLITE_OK;
}


/*
** Write one double value into the packed payload according to pInfo.
**
** Return SQLITE_OK on success.  Values that narrow to infinity or NaN are
** rejected so that pblob_unpack() can always produce ordinary JSON numbers.
*/
static int pblobEncodeValue(
    sqlite3_context *ctx,
    u8 *pOut,
    double x,
    const PBlobFormatInfo *pInfo
) {
    float f;
    uint32_t u32bits;

    f = (float)x;

    if (pInfo->isF32) {
        u32bits = fp32_to_bits(f);

        /* IEEE binary32 exponent all-ones means infinity or NaN. */
        if ((u32bits & UINT32_C(0x7f800000)) == UINT32_C(0x7f800000)) {
            return pblobError(ctx, "numeric value out of range for pblob format");
        }

        pblobWriteU32(pOut, u32bits, pInfo->bigEndian);
    } else {
        uint16_t u16bits = fp16_ieee_from_fp32_value(f);

        /* IEEE binary16 exponent all-ones means infinity or NaN. */
        if ((u16bits & UINT16_C(0x7c00)) == UINT16_C(0x7c00)) {
            return pblobError(ctx, "numeric value out of range for pblob format");
        }

        pblobWriteU16(pOut, u16bits, pInfo->bigEndian);
    }

    return SQLITE_OK;
}


/*
** Decode one packed payload element into a C double.
*/
static double pblobDecodeValue(
    const u8 *pIn,
    const PBlobFormatInfo *pInfo
) {
    float f;

    if (pInfo->isF32) {
        uint32_t bits = pblobReadU32(pIn, pInfo->bigEndian);
        f = fp32_from_bits(bits);
    } else {
        uint16_t bits = pblobReadU16(pIn, pInfo->bigEndian);
        f = fp16_ieee_to_fp32_value(bits);
    }

    return (double)f;
}


/*
** SQL function:
**
**   pblob_pack(json_vector)
**   pblob_pack(json_vector, format)
**
** The one-argument form defaults to >f2.
*/
static void pblobPackFunc(
    sqlite3_context *ctx,
    int argc,
    sqlite3_value **argv
) {
    PBlobFormatInfo info;
    JsonParse *pParse = 0;
    u8 *aOut = 0;
    u32 nRootHdr;
    u32 nRootPayload;
    u32 iNode;
    u32 iEnd;
    u32 nElem;
    u32 iElem;
    sqlite3_uint64 nPayloadOut;
    sqlite3_uint64 nResult;
    int rc = SQLITE_OK;

    assert(argc == 1 || argc == 2);

    if (sqlite3_value_type(argv[0]) == SQLITE_NULL) {
        return;
    }

    if (sqlite3_value_type(argv[0]) != SQLITE_TEXT) {
        sqlite3_result_error(ctx, "pblob_pack() JSON argument must be TEXT", -1);
        return;
    }

    if (argc == 1) {
        rc = pblobFormatFromTag(ctx, 0x03, &info);  /* >f2 */
    } else {
        if (sqlite3_value_type(argv[1]) == SQLITE_NULL) {
            sqlite3_result_error(ctx, "pblob format must not be NULL", -1);
            return;
        }
        rc = pblobParseFormatArg(ctx, argv[1], &info);
    }
    if (rc != SQLITE_OK) {
        return;
    }

    pParse = jsonParseFuncArg(ctx, argv[0], 0);
    if (pParse == 0) {
        return;
    }

    /*
    ** SQLite's JSON parser accepts JSON5, but pblob accepts canonical numeric
    ** JSON only.  Reject any non-standard syntax even if it was normalized
    ** internally to JSONB_INT or JSONB_FLOAT.
    */
    if (pParse->hasNonstd) {
        sqlite3_result_error(ctx, "pblob_pack() requires canonical JSON", -1);
        goto pack_cleanup;
    }

    if ((pParse->aBlob[0] & 0x0f) != JSONB_ARRAY) {
        sqlite3_result_error(ctx, "pblob_pack() expects a JSON array", -1);
        goto pack_cleanup;
    }

    nElem = jsonbArrayCount(pParse, 0);

    nRootHdr = jsonbPayloadSize(pParse, 0, &nRootPayload);
    if (nRootHdr == 0) {
        sqlite3_result_error(ctx, "malformed JSON", -1);
        goto pack_cleanup;
    }

    /*
    ** nElem is u32 and elementSize <= 4, but perform all output-size
    ** arithmetic in sqlite3_uint64 and honor the connection length limit.
    */
    nPayloadOut = (sqlite3_uint64)nElem * (sqlite3_uint64)info.elementSize;
    nResult = nPayloadOut + PBLOB_TRAILER_SIZE;

    if (nResult > (sqlite3_uint64)sqlite3_limit(
                   sqlite3_context_db_handle(ctx), SQLITE_LIMIT_LENGTH, -1
                  )
    ) {
        sqlite3_result_error_toobig(ctx);
        goto pack_cleanup;
    }

    aOut = sqlite3_malloc64(nResult);
    if (aOut == 0) {
        sqlite3_result_error_nomem(ctx);
        goto pack_cleanup;
    }

    iNode = nRootHdr;
    iEnd = nRootHdr + nRootPayload;
    iElem = 0;

    while (iNode < iEnd) {
        u32 nHdr;
        u32 nPayload;
        double x;

        nHdr = jsonbPayloadSize(pParse, iNode, &nPayload);
        if (nHdr == 0 || iNode+nHdr+nPayload>iEnd) {
            sqlite3_result_error(ctx, "malformed JSON", -1);
            goto pack_cleanup;
        }

        rc = pblobJsonNumberToDouble(ctx, pParse, iNode, &x);
        if (rc != SQLITE_OK) {
            goto pack_cleanup;
        }

        rc = pblobEncodeValue(
            ctx,
            &aOut[(sqlite3_uint64)iElem * info.elementSize],
            x,
            &info
        );
        if (rc != SQLITE_OK) {
            goto pack_cleanup;
        }

        iElem++;
        iNode += nHdr + nPayload;
    }

    if (iNode != iEnd || iElem != nElem) {
        sqlite3_result_error(ctx, "malformed JSON array", -1);
        goto pack_cleanup;
    }

    /* Append the four identical trailer bytes. */
    aOut[nPayloadOut+0] = info.tag;
    aOut[nPayloadOut+1] = info.tag;
    aOut[nPayloadOut+2] = info.tag;
    aOut[nPayloadOut+3] = info.tag;

    sqlite3_result_blob64(ctx, aOut, nResult, SQLITE_DYNAMIC);
    aOut = 0;

pack_cleanup:
    sqlite3_free(aOut);
    jsonParseFree(pParse);
}


/*
** SQL function:
**
**   pblob_unpack(blob_data)
*/
static void pblobUnpackFunc(
    sqlite3_context *ctx,
    int argc,
    sqlite3_value **argv
) {
    PBlobFormatInfo info;
    const u8 *aBlob;
    sqlite3_uint64 nBlob;
    sqlite3_uint64 nPayload;
    sqlite3_uint64 nElem;
    sqlite3_uint64 i;
    JsonString out;
    int rc;

    assert(argc == 1);
    UNUSED_PARAMETER(argc);

    if (sqlite3_value_type(argv[0]) == SQLITE_NULL) {
        return;
    }

    if (sqlite3_value_type(argv[0]) != SQLITE_BLOB) {
        sqlite3_result_error(ctx, "pblob_unpack() argument must be BLOB", -1);
        return;
    }

    nBlob = (sqlite3_uint64)sqlite3_value_bytes(argv[0]);
    aBlob = (const u8*)sqlite3_value_blob(argv[0]);

    if (nBlob>0 && aBlob == 0) {
        sqlite3_result_error_nomem(ctx);
        return;
    }

    rc = pblobParseTrailer(ctx, aBlob, nBlob, &info);
    if (rc != SQLITE_OK) {
        return;
    }

    nPayload = nBlob - PBLOB_TRAILER_SIZE;

    if (nPayload % info.elementSize != 0) {
        sqlite3_result_error(ctx, "invalid pblob payload size", -1);
        return;
    }

    nElem = nPayload / info.elementSize;

    jsonStringInit(&out, ctx);
    jsonAppendChar(&out, '[');

    for (i=0; i < nElem; i++) {
        const u8 *pIn = &aBlob[i * info.elementSize];
        double x = pblobDecodeValue(pIn, &info);

        /*
        ** pblob_pack() never emits non-finite values.  Detect malformed or
        ** externally constructed payloads here as well.
        */
        if (info.isF32) {
            uint32_t bits = pblobReadU32(pIn, info.bigEndian);
            if ((bits & UINT32_C(0x7f800000)) == UINT32_C(0x7f800000)) {
                sqlite3_result_error(ctx, "pblob contains non-finite value", -1);
                jsonStringReset(&out);
                return;
            }
        } else {
            uint16_t bits = pblobReadU16(pIn, info.bigEndian);
            if ((bits & UINT16_C(0x7c00)) == UINT16_C(0x7c00)) {
                sqlite3_result_error(ctx, "pblob contains non-finite value", -1);
                jsonStringReset(&out);
                return;
            }
        }

        jsonAppendSeparator(&out);
        jsonPrintf(100, &out, "%!0.17g", x);
    }

    jsonAppendChar(&out, ']');
    jsonReturnString(&out, 0, 0);
    sqlite3_result_subtype(ctx, JSON_SUBTYPE);
}


/*
** Register SQL functions.
*/
static int pblobRegister(sqlite3 *db) {
    const int flags = SQLITE_UTF8 | SQLITE_DETERMINISTIC | SQLITE_INNOCUOUS;
    int rc;

    rc = sqlite3_create_function_v2(
        db, "pblob_pack", 1, flags, 0,
        pblobPackFunc, 0, 0, 0
    );
    if (rc != SQLITE_OK) {
        return rc;
    }

    rc = sqlite3_create_function_v2(
        db, "pblob_pack", 2, flags, 0,
        pblobPackFunc, 0, 0, 0
    );
    if (rc != SQLITE_OK) {
        return rc;
    }

    return sqlite3_create_function_v2(
        db, "pblob_unpack", 1, flags, 0,
        pblobUnpackFunc, 0, 0, 0
    );
}


/*
** Standard SQLite extension initializer.
**
** In an amalgamation/auto-extension build, this function can be registered
** with sqlite3_auto_extension() or invoked from the project's aggregate
** auto-extension initializer.
*/
#ifdef _WIN32
__declspec(dllexport)
#endif
int sqlite3_pblob_init(
    sqlite3 *db,
    char **pzErrMsg,
    const sqlite3_api_routines *pApi
) {
    UNUSED_PARAMETER(pzErrMsg);
    UNUSED_PARAMETER(pApi);
return pblobRegister(db);
}

#endif /* SQLITE_OMIT_JSON */
