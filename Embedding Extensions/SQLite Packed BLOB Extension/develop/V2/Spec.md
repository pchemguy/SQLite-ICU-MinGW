---
url: https://chatgpt.com/c/6a79c755-5a4c-83eb-b039-2804fac50575
---

# Packed Blob (`pblob`) SQLite Auto-Extension Specification

## 1. Purpose

`pblob` is a SQLite C auto-extension for converting one-dimensional numeric JSON vectors between:

* human-readable JSON text; and
* compact packed IEEE floating-point BLOB storage.

The extension supports IEEE binary16 (`f2`) and binary32 (`f4`) payload elements with explicitly defined little- or big-endian byte order.

The packed representation consists of:

```text
[payload ...][4-byte format trailer]
```

The payload begins at BLOB offset `0`; the trailer is appended so that the packed array remains naturally aligned for both 2-byte and 4-byte element sizes.

The BLOB contains no stored element count. Element count is derived from BLOB size and format metadata.

---

## 2. SQL API

Register three deterministic scalar function variants:

```text
pblob_pack(json_vector: SQL_TEXT, format: SQL_TEXT) -> blob_data: SQL_BLOB
pblob_pack(json_vector: SQL_TEXT)                   -> blob_data: SQL_BLOB
pblob_unpack(blob_data: SQL_BLOB)                   -> json_vector: SQL_TEXT
```

The one-argument `pblob_pack()` variant is equivalent to:

```sql
pblob_pack(json_vector, '>f2')
```

Supported format strings are exactly:

```text
<f2
>f2
<f4
>f4
```

No other aliases or case variants are accepted.

SQL `NULL` input propagates to SQL `NULL`.

---

## 3. JSON Input Contract

`pblob_pack()` accepts a JSON text value whose top-level value is a one-dimensional array.

Every array element must be represented internally by SQLite JSON parsing as one of:

```c
JSONB_INT
JSONB_FLOAT
```

No other JSON node type is accepted.

In particular, reject:

```text
null
true / false
strings
arrays
objects
JSON5 integer forms
JSON5 floating forms
NaN
Infinity
hexadecimal numbers
```

Thus typical accepted input is:

```json
[1.23, -4.5, 0, 17, 0.003125]
```

SQLite's JSON parser represents canonical integer and floating literals as `JSONB_INT` and `JSONB_FLOAT`; their payloads are textual numeric literals. `jsonParseFuncArg()`, `jsonbPayloadSize()`, and `jsonbArrayCount()` provide the required parse and traversal machinery.

An empty array is valid.

---

## 4. Packed BLOB Format

### 4.1 General Layout

```text
+-------------------------------+----------------------+
| packed floating-point payload | 4-byte format trailer|
+-------------------------------+----------------------+
```

For `N` elements:

```text
f2 BLOB size = N * 2 + 4
f4 BLOB size = N * 4 + 4
```

An empty vector therefore produces a 4-byte BLOB containing only the trailer.

### 4.2 Trailer Encoding

The trailer consists of four identical bytes.

Each byte encodes:

```text
bit 0     reserved, must be 1
bit 1     endian: 0 = little, 1 = big
bit 2     type:   0 = f2,     1 = f4
bits 3-7  reserved, must be 0
```

Valid byte tags are:

```text
001 = f2 LE = 0x01
011 = f2 BE = 0x03
101 = f4 LE = 0x05
111 = f4 BE = 0x07
```

Define:

```c
typedef enum PBlobFormat {
    PBLOB_F16_LE = 0x01010101,
    PBLOB_F16_BE = 0x03030303,
    PBLOB_F32_LE = 0x05050505,
    PBLOB_F32_BE = 0x07070707
} PBlobFormat;
```

Physical layouts are therefore:

```text
[payload ...][01 01 01 01]   <f2
[payload ...][03 03 03 03]   >f2
[payload ...][05 05 05 05]   <f4
[payload ...][07 07 07 07]   >f4
```

Because all four trailer bytes are equal, the 32-bit trailer value itself is invariant under host byte-order reversal.

On unpack, require all four bytes to be identical and require the byte value to be exactly one of:

```text
0x01
0x03
0x05
0x07
```

---

## 5. Internal Format Description

Use a small decoded descriptor internally, for example:

```c
typedef struct PBlobFormatInfo {
    PBlobFormat format;
    int element_size;     /* 2 or 4 */
    int big_endian;       /* 0 or 1 */
    int is_f32;           /* 0 = f16, 1 = f32 */
} PBlobFormatInfo;
```

Suggested helpers:

```c
static int pblobParseFormatArg(
    sqlite3_context *ctx,
    sqlite3_value *value,
    PBlobFormatInfo *info
);

static int pblobParseTrailer(
    sqlite3_context *ctx,
    const unsigned char *blob,
    sqlite3_uint64 blob_size,
    PBlobFormatInfo *info
);
```

`pblobParseFormatArg()` parses `<f2`, `>f2`, `<f4`, or `>f4`.

`pblobParseTrailer()` validates and decodes the final four bytes.

Return non-zero on failure after setting the SQLite error result.

---

## 6. Byte Encoding Helpers

Serialization must not depend on host endianness.

Do not serialize floating objects using raw `memcpy()` when the requested BLOB byte order is explicit.

Suggested helpers:

```c
static void pblobWriteU16(
    unsigned char *dst,
    uint16_t value,
    int big_endian
);

static uint16_t pblobReadU16(
    const unsigned char *src,
    int big_endian
);

static void pblobWriteU32(
    unsigned char *dst,
    uint32_t value,
    int big_endian
);

static uint32_t pblobReadU32(
    const unsigned char *src,
    int big_endian
);
```

Little-endian `uint16_t` serialization:

```c
dst[0] = (unsigned char)value;
dst[1] = (unsigned char)(value >> 8);
```

Big-endian:

```c
dst[0] = (unsigned char)(value >> 8);
dst[1] = (unsigned char)value;
```

Little-endian `uint32_t` serialization:

```c
dst[0] = (unsigned char)value;
dst[1] = (unsigned char)(value >> 8);
dst[2] = (unsigned char)(value >> 16);
dst[3] = (unsigned char)(value >> 24);
```

Big-endian:

```c
dst[0] = (unsigned char)(value >> 24);
dst[1] = (unsigned char)(value >> 16);
dst[2] = (unsigned char)(value >> 8);
dst[3] = (unsigned char)value;
```

Reading performs the inverse shift/OR operations.

---

## 7. Floating-Point Conversion

### 7.1 JSON Numeric Value

SQLite JSON numeric literals are decoded into a temporary C `double`.

This `double` is an intermediate scalar only. No intermediate `double[]` is allocated.

Suggested helper:

```c
static int pblobJsonNumberToDouble(
    sqlite3_context *ctx,
    JsonParse *parse,
    u32 node_offset,
    double *value
);
```

Requirements:

1. Call `jsonbPayloadSize()` for the node.
2. Require node type to be exactly `JSONB_INT` or `JSONB_FLOAT`.
3. Copy the textual numeric payload to a temporary NUL-terminated buffer with `sqlite3DbStrNDup()`.
4. Convert using:

```c
sqlite3AtoF(z, value)
```

5. Free temporary storage.
6. Treat conversion failure as malformed/unsupported vector input.

SQLite itself uses `sqlite3AtoF()` when converting JSON floating nodes to SQL double values.

### 7.2 `double` ↔ `float`

Use ordinary C conversions:

```c
float f = (float)x;
double x = (double)f;
```

`double -> float` performs binary32 narrowing.

`float -> double` is used before JSON text generation.

### 7.3 `float` ↔ IEEE binary16

Use the FP16 library value-level IEEE functions:

```c
uint16_t fp16_ieee_from_fp32_value(float f);
float fp16_ieee_to_fp32_value(uint16_t h);
```

`fp16_ieee_from_fp32_value()` returns the binary16 encoding as a `uint16_t` bit pattern, not a native half-float C object. `fp16_ieee_to_fp32_value()` performs the inverse conversion.

Do not use the `fp16_alt_*` ARM alternative-format functions.

### 7.4 `float` ↔ IEEE binary32 Bits

Use:

```c
uint32_t fp32_to_bits(float f);
float fp32_from_bits(uint32_t bits);
```

These helpers convert between a C `float` value and its 32-bit representation without treating native memory byte order as serialized byte order.

---

## 8. `pblob_pack()` Algorithm

Implement one SQL callback handling both arities:

```c
static void pblobPackFunc(
    sqlite3_context *ctx,
    int argc,
    sqlite3_value **argv
);
```

Valid `argc` values are `1` and `2`.

### 8.1 Input and Format

1. If `argv[0]` is SQL `NULL`, return SQL `NULL`.
2. Require `argv[0]` to be `SQLITE_TEXT`.
3. If `argc == 1`, select `PBLOB_F16_BE`.
4. Otherwise parse `argv[1]` with `pblobParseFormatArg()`.
5. A NULL or invalid explicit format is an error.

### 8.2 Parse JSON

Parse:

```c
JsonParse *p = jsonParseFuncArg(ctx, argv[0], 0);
```

If it returns `NULL`, propagate the error/NULL behavior established by SQLite JSON.

Require:

```c
(p->aBlob[0] & 0x0f) == JSONB_ARRAY
```

Otherwise return an error.

Determine element count:

```c
u32 count = jsonbArrayCount(p, 0);
```

Determine the array payload bounds with:

```c
jsonbPayloadSize(p, 0, &payload_size)
```

SQLite uses the same JSONB representation and traversal primitives for array processing.

### 8.3 Allocate Result

Calculate:

```text
payload_bytes = count * element_size
result_bytes  = payload_bytes + 4
```

Check all multiplication/addition for overflow and SQLite maximum BLOB length before allocating.

Allocate using an SQLite allocator compatible with result ownership, for example:

```c
sqlite3DbMallocRaw(...)
```

The result buffer layout is:

```text
[0 .. payload_bytes-1]       packed values
[payload_bytes .. +3]        trailer
```

### 8.4 Iterate JSON Elements

Start at the first child node of the root array.

For each element:

1. Obtain its header length and payload length with `jsonbPayloadSize()`.
2. Verify it lies entirely inside the root-array payload.
3. Require node type `JSONB_INT` or `JSONB_FLOAT`.
4. Convert the node to temporary:

```c
double x;
```

using `pblobJsonNumberToDouble()`.

5. Encode directly into the final output buffer.

No intermediate vector allocation is permitted.

### 8.5 Encode f4

Convert:

```c
float f = (float)x;
uint32_t bits = fp32_to_bits(f);
```

Then serialize `bits` with `pblobWriteU32()` according to requested endianness.

Destination offset:

```text
i * 4
```

### 8.6 Encode f2

Convert:

```c
float f = (float)x;
uint16_t bits = fp16_ieee_from_fp32_value(f);
```

Then serialize `bits` with `pblobWriteU16()` according to requested endianness.

Destination offset:

```text
i * 2
```

The FP16 library may internally select native or portable conversion implementations; that selection is controlled by its own macros and is not part of the pblob format.

### 8.7 Append Trailer

Write the four identical format bytes immediately after the payload.

For example:

```text
<f2 -> 01 01 01 01
>f2 -> 03 03 03 03
<f4 -> 05 05 05 05
>f4 -> 07 07 07 07
```

Prefer explicit byte assignment rather than relying on native `uint32_t` storage, even though the repeated-byte representation is endian invariant.

### 8.8 Return

Return the allocated buffer as:

```c
sqlite3_result_blob64(
    ctx,
    output,
    result_bytes,
    SQLITE_DYNAMIC
);
```

Release `JsonParse` with:

```c
jsonParseFree(p);
```

Follow SQLite JSON's ownership/error conventions: transferred result memory must not subsequently be freed by the function.

---

## 9. `pblob_unpack()` Algorithm

Implement:

```c
static void pblobUnpackFunc(
    sqlite3_context *ctx,
    int argc,
    sqlite3_value **argv
);
```

`argc` is exactly `1`.

### 9.1 Input Validation

1. If `argv[0]` is SQL `NULL`, return SQL `NULL`.
2. Require exact type `SQLITE_BLOB`.
3. Obtain:

```c
const unsigned char *blob =
    sqlite3_value_blob(argv[0]);

sqlite3_uint64 blob_size =
    sqlite3_value_bytes(argv[0]);
```

4. Require:

```text
blob_size >= 4
```

### 9.2 Decode Trailer

Set:

```text
trailer = blob + blob_size - 4
```

Require:

```text
trailer[0] == trailer[1]
trailer[0] == trailer[2]
trailer[0] == trailer[3]
```

Require the tag to be one of:

```text
0x01
0x03
0x05
0x07
```

Decode:

```text
element size
endianness
f2/f4
```

with `pblobParseTrailer()`.

### 9.3 Validate Payload

Calculate:

```text
payload_size = blob_size - 4
```

Require:

```text
payload_size % element_size == 0
```

Then:

```text
count = payload_size / element_size
```

The payload begins at `blob[0]`; there is no header offset.

### 9.4 Initialize JSON Output

Use SQLite JSON's own text construction machinery:

```c
JsonString out;

jsonStringInit(&out, ctx);
jsonAppendChar(&out, '[');
```

SQLite's `jsonArrayFunc()` follows this same construction pattern, and floating SQL values are rendered with `%!0.17g`.

### 9.5 Decode Each f4 Element

For each 4-byte element:

```c
uint32_t bits = pblobReadU32(src, big_endian);
float f = fp32_from_bits(bits);
double x = (double)f;
```

### 9.6 Decode Each f2 Element

For each 2-byte element:

```c
uint16_t bits = pblobReadU16(src, big_endian);
float f = fp16_ieee_to_fp32_value(bits);
double x = (double)f;
```

### 9.7 Emit JSON Number

For every decoded value:

```c
jsonAppendSeparator(&out);
jsonPrintf(100, &out, "%!0.17g", x);
```

SQLite uses `%!0.17g` for JSON rendering of floating SQL values.

Finish:

```c
jsonAppendChar(&out, ']');
jsonReturnString(&out, 0, 0);
sqlite3_result_subtype(ctx, JSON_SUBTYPE);
```

The result must therefore be canonical JSON text generated through SQLite's JSON string machinery.

---

## 10. Error Handling

Use SQLite result APIs consistently.

Expected error classes include:

```text
wrong SQL argument type
invalid format string
malformed JSON
top-level JSON value is not an array
array contains unsupported JSON node type
invalid numeric conversion
allocation failure
packed BLOB shorter than trailer
invalid trailer redundancy
unknown trailer tag
payload size not divisible by element width
result too large
```

Use:

```c
sqlite3_result_error()
sqlite3_result_error_nomem()
sqlite3_result_error_toobig()
```

as appropriate.

All error paths must release any locally owned allocations and any owned `JsonParse`.

---

## 11. Suggested Internal Decomposition

Keep the extension small. Suggested helpers are:

```c
static int pblobParseFormatArg(
    sqlite3_context *,
    sqlite3_value *,
    PBlobFormatInfo *
);

static int pblobParseTrailer(
    sqlite3_context *,
    const unsigned char *,
    sqlite3_uint64,
    PBlobFormatInfo *
);

static int pblobJsonNumberToDouble(
    sqlite3_context *,
    JsonParse *,
    u32,
    double *
);

static void pblobWriteU16(
    unsigned char *,
    uint16_t,
    int
);

static uint16_t pblobReadU16(
    const unsigned char *,
    int
);

static void pblobWriteU32(
    unsigned char *,
    uint32_t,
    int
);

static uint32_t pblobReadU32(
    const unsigned char *,
    int
);

static void pblobPackFunc(
    sqlite3_context *,
    int,
    sqlite3_value **
);

static void pblobUnpackFunc(
    sqlite3_context *,
    int,
    sqlite3_value **
);
```

Do not create generic vector abstractions or intermediate `double[]`, `float[]`, or FP16 arrays.

Conversion must stream element-by-element from the parsed JSON representation directly into the final BLOB and from the BLOB directly into `JsonString`.

---

## 12. SQL Function Registration

Register:

```text
pblob_pack/1
pblob_pack/2
pblob_unpack/1
```

as UTF-8 deterministic scalar functions.

Use SQLite's normal extension registration API:

```c
sqlite3_create_function_v2(...)
```

or the corresponding internal registration mechanism appropriate to the amalgamation integration.

The extension is intended to operate as an auto-extension in the customized SQLite amalgamation build.

Registration failure must be propagated from the extension initialization function.

---

## 13. Required Dependencies

The implementation depends on SQLite core internals from `json.c`, specifically:

```c
JsonParse
JsonString

JSONB_INT
JSONB_FLOAT
JSONB_ARRAY
JSON_SUBTYPE

jsonParseFuncArg()
jsonParseFree()
jsonbPayloadSize()
jsonbArrayCount()

jsonStringInit()
jsonAppendChar()
jsonAppendSeparator()
jsonPrintf()
jsonReturnString()

sqlite3AtoF()
```

The JSON implementation confirms that canonical numeric nodes use `JSONB_INT` and `JSONB_FLOAT`, that their JSONB payloads contain textual numeric literals, and that `jsonParseFuncArg()` owns the parsed representation returned to its caller until `jsonParseFree()` is invoked.

FP16 dependencies:

```c
fp16_ieee_from_fp32_value()
fp16_ieee_to_fp32_value()
```

from `fp16.h`.

Binary32 bitcast dependencies:

```c
fp32_to_bits()
fp32_from_bits()
```

from `bitcasts.h`.

---

## 14. Core Invariants

An implementation is conforming only if all of the following hold:

1. Payload begins at BLOB offset `0`.
2. Trailer is always exactly four bytes.
3. All four trailer bytes are identical.
4. Only tags `01`, `03`, `05`, and `07` are valid.
5. Payload contains only IEEE binary16 or binary32 values.
6. Payload byte order is defined by the trailer, not by host architecture.
7. BLOB element count is inferred, never stored.
8. JSON input is a one-dimensional array containing only `JSONB_INT | JSONB_FLOAT`.
9. Packing does not construct an intermediate floating-point array.
10. Unpacking does not construct an intermediate floating-point array.
11. `pblob_pack(JSON)` means `pblob_pack(JSON, '>f2')`.
12. `pblob_unpack()` requires no format argument because the BLOB is self-describing.
