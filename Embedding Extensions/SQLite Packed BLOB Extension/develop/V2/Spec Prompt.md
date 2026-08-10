---
url: https://chatgpt.com/c/6a79c755-5a4c-83eb-b039-2804fac50575
---

Create specification for the Packed Blob "pblob" SQLite C auto extension. Specification must be comprehensive, but concise.

Extension will register two SQL functions:

```text
pblob_pack(json_vector: SQL_TEXT, format: SQL_TEXT) -> blob_data: SQL_BLOB
pblob_unpack(blob_data: SQL_BLOB) -> json_vector: SQL_TEXT
```

"pblob_pack" converts a JSON text, containing a 1D array of SQLite JSONB_INT | JSONB_FLOAT, representing and embedding vector into a packed binary blob (essentially a 1D C array).

The second argument defines type and storage format of individual elements and might be:

- `<f2`
- `>f2`
- `<f4`
- `>f4`

The core array data is appended a 4-byte metadata, encoding format:

```c
/*
** Trailer metadata format
**
** 4 equal bytes each encoding size and endianness:
**
** bit 0     reserved, must be 1
** bit 1     endian
** bit 2     type
** bits 3-7  reserved
** 
** 001 = f2 LE
** 011 = f2 BE
** 101 = f4 LE
** 111 = f4 BE
*/

typedef enum PBlobFormat {
    PBLOB_F16_LE = 0x01010101,
    PBLOB_F16_BE = 0x03030303,
    PBLOB_F32_LE = 0x05050505,
    PBLOB_F32_BE = 0x07070707
} PBlobFormat;
```

That is

```text
[payload ...][01 01 01 01]   <f2
[payload ...][03 03 03 03]   >f2
[payload ...][05 05 05 05]   <f4
[payload ...][07 07 07 07]   >f4
```

`pblob_unpack` performs inverse operation.

Also register SQL function variant

```text
pblob_pack(json_vector: SQL_TEXT) -> blob_data: SQL_BLOB
```

with default format `>f2`.

Develop a detailed step-by-step transformation algorithms for each function, indicating specific functions or macros to be used from `json.c` or the `FP16` library or indicating suggested helper prototypes and their specs.

Adapt and integrate all relevant pieces:

``````
For `pblob_pack()` the flow would be:

```text
SQLITE_TEXT
   ↓
SQLite JSON parser machinery
   ↓
iterate numeric array elements
   ↓
temporary C double per element
   ↓
convert to float16 / float32
   ↓
write bytes in requested endian order
   ↓
sqlite3_result_blob()
```

For `pblob_unpack()`:

```text
SQLITE_BLOB
   ↓
interpret chunks according to format
   ↓
float16 / float32 -> temporary double
   ↓
SQLite JsonString machinery
   ↓
JSON numeric array text
   ↓
sqlite3_result_text()
```

So yes, the outer interfaces can borrow directly from SQLite JSON’s established patterns:

* argument validation via `sqlite3_value_type()`
* obtaining input using `sqlite3_value_text()` / `sqlite3_value_blob()`
* allocation using SQLite allocators
* returning ownership through `sqlite3_result_blob()` / `sqlite3_result_text*()`
* NULL propagation
* SQLite-style error reporting through `sqlite3_result_error*()`

And internally you reuse the pieces we identified from `json.c`:

```text
PACK
jsonParseFuncArg()
jsonbPayloadSize()
jsonbArrayCount()
sqlite3AtoF()
```

and:

```text
UNPACK
JsonString
jsonStringInit()
jsonAppendChar()
jsonAppendSeparator()
jsonPrintf()
jsonReturnString()
```

I would also make `format` parsing a tiny independent helper:

```c
typedef enum PBlobFormat {
    PBLOB_F16_LE = 0x01010101,
    PBLOB_F16_BE = 0x03030303,
    PBLOB_F32_LE = 0x05050505,
    PBLOB_F32_BE = 0x07070707
} PBlobFormat;
```

with:

```c
static int pblobParseFormat(
    sqlite3_context *ctx,
    sqlite3_value *pValue,
    PblobFormat *pFormat
);
```

Then the two SQL functions stay structurally simple.

The resulting architecture is effectively:

```text
pblob_pack()
    ├── pblobParseFormat()
    ├── SQLite JSON parse machinery
    ├── JSON-number -> double
    └── double -> encoded f16/f32 bytes

pblob_unpack()
    ├── pblobParseFormat()
    ├── encoded f16/f32 bytes -> double
    └── SQLite JSON text-generation machinery
```

---
---

```sql
pblob_unpack(blob)
```

does:

```text
read final 4 bytes
     ↓
validate repeated tag
     ↓
determine f2/f4 + LE/BE
     ↓
payload_size = blob_size - 4
     ↓
validate payload_size % element_size == 0
     ↓
decode elements
     ↓
JSON TEXT
```
---
---

For f2, after:

```c
uint16_t h = fp16_ieee_from_fp32_value((float)x);
```

write bytes yourself.

Little-endian:

```c
pOut[0] = (unsigned char)(h);
pOut[1] = (unsigned char)(h >> 8);
```

Big-endian:

```c
pOut[0] = (unsigned char)(h >> 8);
pOut[1] = (unsigned char)(h);
```

For f4, first get the IEEE-754 bit pattern:

```c
uint32_t u = fp32_to_bits((float)x);
```

Then little-endian:

```c
pOut[0] = (unsigned char)(u);
pOut[1] = (unsigned char)(u >> 8);
pOut[2] = (unsigned char)(u >> 16);
pOut[3] = (unsigned char)(u >> 24);
```

Big-endian:

```c
pOut[0] = (unsigned char)(u >> 24);
pOut[1] = (unsigned char)(u >> 16);
pOut[2] = (unsigned char)(u >> 8);
pOut[3] = (unsigned char)(u);
```

This is independent of the machine's native endianness.

The reverse is symmetrical. For example, read f4 little-endian as:

```c
uint32_t u =
    ((uint32_t)pIn[0]      ) |
    ((uint32_t)pIn[1] <<  8) |
    ((uint32_t)pIn[2] << 16) |
    ((uint32_t)pIn[3] << 24);

float f = fp32_from_bits(u);
```

and big-endian as:

```c
uint32_t u =
    ((uint32_t)pIn[0] << 24) |
    ((uint32_t)pIn[1] << 16) |
    ((uint32_t)pIn[2] <<  8) |
    ((uint32_t)pIn[3]);

float f = fp32_from_bits(u);
```

---
---

For **f8 ↔ f4**, ordinary C casts are the right operation:

```c
float  f4 = (float)f8;
double f8 = (double)f4;
```

The `double -> float` direction performs the normal IEEE-754 narrowing/rounding supported by the implementation; `float -> double` is exact for all finite binary32 values.

For **f4 ↔ f2**, from the FP16 library you attached, use exactly these two functions:

```c
uint16_t fp16_ieee_from_fp32_value(float f);
float    fp16_ieee_to_fp32_value(uint16_t h);
```

Those are the intended value-level IEEE binary16 conversion APIs. 

So your conversion chain becomes:

```c
/* f8 -> f4 */
float f4 = (float)f8;

/* f4 -> f2 bits */
uint16_t f2 = fp16_ieee_from_fp32_value(f4);

/* f2 bits -> f4 */
float f4 = fp16_ieee_to_fp32_value(f2);

/* f4 -> f8 */
double f8 = (double)f4;
```

For your `pblob_pack()` path, where SQLite's JSON parser gives you a `double`, the f2 case is therefore simply:

```c
double x = ...;  /* parsed JSON value */

uint16_t h = fp16_ieee_from_fp32_value((float)x);
```

and f4:

```c
float f = (float)x;
```

For `pblob_unpack()`:

```c
/* f2 */
float f = fp16_ieee_to_fp32_value(h);
double x = (double)f;

/* f4 */
double x = (double)f;
```

Then feed `x` to the JSON formatter.

### Important distinction for your BLOB

`fp16_ieee_from_fp32_value()` returns a `uint16_t` containing the **binary16 bit pattern**, not a native C half type. That is exactly what you want for `<f2` / `>f2`. 

Similarly, for f4, use the supplied bitcast helper:

```c
uint32_t bits = fp32_to_bits(f);
```

and reverse with:

```c
float f = fp32_from_bits(bits);
```

That gives you a particularly clean implementation for endianness:

```text
double
  |
  +-- f4 --> (float) --> fp32_to_bits() ------------> uint32_t --> bytes
  |
  +-- f2 --> (float) --> fp16_ieee_from_fp32_value() -> uint16_t --> bytes
```

and on unpack:

```text
bytes --> uint32_t --> fp32_from_bits() ------------> float --> double
bytes --> uint16_t --> fp16_ieee_to_fp32_value() ---> float --> double
```

---
---

```c
static void json2double_array(
  sqlite3_context *ctx,
  int argc,
  sqlite3_value **argv
){
  JsonParse *p;
  sqlite3 *db;
  double *aOut;
  u32 nHdr, nPayload;
  u32 i, iEnd;
  u32 nElem, iElem;

  assert( argc==1 );
  UNUSED_PARAMETER(argc);

  if( sqlite3_value_type(argv[0])==SQLITE_NULL ){
    return;
  }

  p = jsonParseFuncArg(ctx, argv[0], 0);
  if( p==0 ){
    return;
  }

  if( (p->aBlob[0] & 0x0f)!=JSONB_ARRAY ){
    sqlite3_result_error(ctx, "expected JSON array", -1);
    jsonParseFree(p);
    return;
  }

  nElem = jsonbArrayCount(p, 0);

  if( nElem==0 ){
    sqlite3_result_zeroblob(ctx, 0);
    jsonParseFree(p);
    return;
  }

  db = sqlite3_context_db_handle(ctx);
  aOut = sqlite3DbMallocRaw(
      db,
      (sqlite3_uint64)nElem * sizeof(double)
  );
  if( aOut==0 ){
    sqlite3_result_error_nomem(ctx);
    jsonParseFree(p);
    return;
  }

  nHdr = jsonbPayloadSize(p, 0, &nPayload);
  i = nHdr;
  iEnd = i + nPayload;
  iElem = 0;

  while( i<iEnd ){
    u32 n;
    u32 sz;
    u8 eType;
    char *z;
    double r;

    n = jsonbPayloadSize(p, i, &sz);
    if( n==0 || i+n+sz>iEnd ){
      goto error;
    }

    eType = p->aBlob[i] & 0x0f;

    if( eType!=JSONB_INT && eType!=JSONB_FLOAT ){
      goto error;
    }

    z = sqlite3DbStrNDup(
        db,
        (const char*)&p->aBlob[i+n],
        (int)sz
    );
    if( z==0 ){
      sqlite3DbFree(db, aOut);
      jsonParseFree(p);
      sqlite3_result_error_nomem(ctx);
      return;
    }

    if( sqlite3AtoF(z, &r)<=0 ){
      sqlite3DbFree(db, z);
      goto error;
    }

    sqlite3DbFree(db, z);

    aOut[iElem++] = r;
    i += n + sz;
  }

  sqlite3_result_blob64(
      ctx,
      aOut,
      (sqlite3_uint64)nElem * sizeof(double),
      SQLITE_DYNAMIC
  );

  jsonParseFree(p);
  return;

error:
  sqlite3DbFree(db, aOut);
  jsonParseFree(p);
  sqlite3_result_error(
      ctx,
      "JSON array must contain only ordinary numbers",
      -1
  );
}
```

And the reverse direction is already essentially ideal:

```c
static void double2json_array(
  sqlite3_context *ctx,
  int argc,
  sqlite3_value **argv
){
  const double *a;
  sqlite3_uint64 nByte;
  sqlite3_uint64 nElem;
  sqlite3_uint64 i;
  JsonString jx;

  assert( argc==1 );
  UNUSED_PARAMETER(argc);

  if( sqlite3_value_type(argv[0])==SQLITE_NULL ){
    return;
  }

  if( sqlite3_value_type(argv[0])!=SQLITE_BLOB ){
    sqlite3_result_error(ctx, "expected double-array BLOB", -1);
    return;
  }

  nByte = sqlite3_value_bytes(argv[0]);

  if( nByte % sizeof(double)!=0 ){
    sqlite3_result_error(ctx, "invalid double-array BLOB size", -1);
    return;
  }

  nElem = nByte / sizeof(double);
  a = (const double*)sqlite3_value_blob(argv[0]);

  jsonStringInit(&jx, ctx);
  jsonAppendChar(&jx, '[');

  for(i=0; i<nElem; i++){
    jsonAppendSeparator(&jx);
    jsonPrintf(100, &jx, "%!0.17g", a[i]);
  }

  jsonAppendChar(&jx, ']');
  jsonReturnString(&jx, 0, 0);
  sqlite3_result_subtype(ctx, JSON_SUBTYPE);
}
```

---
---

For **JSON text → packed doubles**, the relevant path is:

```c
jsonParseFuncArg()
```

This parses the incoming SQLite value and gives you a `JsonParse *`. For text JSON, it ultimately goes through `jsonConvertTextToBlob()` / `jsonTranslateTextToBlob()`. 

Then verify the root is an array:

```c
(p->aBlob[0] & 0x0f) == JSONB_ARRAY
```

Count elements with:

```c
jsonbArrayCount(p, 0)
```

SQLite itself uses exactly that combination in `jsonArrayLengthFunc()`. 

To walk the elements, use:

```c
jsonbPayloadSize()
```

The same primitive underlies `json_each`; it advances through array elements by `header_size + payload_size`. 

For each element, the existing numeric conversion logic you want is in:

```c
jsonReturnFromBlob()
```

Specifically, its `JSONB_FLOAT` / `JSONB_FLOAT5` branch copies the numeric literal and calls:

```c
sqlite3AtoF(z, &r);
```

while its integer branch uses `sqlite3DecOrHexToI64()` and converts oversized integers to `double` where necessary. 

So the practical implementation is essentially:

```c
JsonParse *p = jsonParseFuncArg(ctx, argv[0], 0);

/* require JSONB_ARRAY */

n = jsonbArrayCount(p, 0);
allocate n * sizeof(double);

for each array node:
    inspect JSONB_INT / JSONB_FLOAT;
    convert using SQLite's existing numeric conversion code;
```

The unfortunate part is that `jsonReturnFromBlob()` writes to a `sqlite3_context`; it does **not** return a C `double`. So you cannot directly call:

```c
double x = jsonReturnFromBlob(...);   /* no */
```

You would reuse/copy the small numeric-conversion portion from that function, not reinvent JSON parsing.

For the opposite direction, **packed doubles → JSON text**, the reusable machinery is even cleaner:

```c
JsonString
jsonStringInit()
jsonAppendChar()
jsonPrintf()
jsonReturnString()
```

and SQLite's canonical double formatting is already:

```c
jsonPrintf(100, &jx, "%!0.17g", value);
```

That exact formatting is used by `jsonAppendSqlValue()` for `SQLITE_FLOAT`. 

`jsonArrayFunc()` shows exactly how SQLite constructs an array:

```c
jsonStringInit(&jx, ctx);
jsonAppendChar(&jx, '[');

for(...){
    jsonAppendSeparator(&jx);
    ...
}

jsonAppendChar(&jx, ']');
jsonReturnString(&jx, 0, 0);
```

So for your case the actual implementation can be approximately:

```c
JsonString jx;

jsonStringInit(&jx, ctx);
jsonAppendChar(&jx, '[');

for(i=0; i<n; i++){
    jsonAppendSeparator(&jx);
    jsonPrintf(100, &jx, "%!0.17g", a[i]);
}

jsonAppendChar(&jx, ']');
jsonReturnString(&jx, 0, 0);
```

That direction is basically already solved.

So the answer I should have given initially is:

| Direction              | SQLite `json.c` machinery                                                                                                |
| ---------------------- | ------------------------------------------------------------------------------------------------------------------------ |
| `double[]` → JSON text | `JsonString` + `jsonStringInit()` + `jsonAppendSeparator()` + `jsonPrintf("%!0.17g")` + `jsonReturnString()`             |
| JSON text → `double[]` | `jsonParseFuncArg()` + `jsonbArrayCount()` + `jsonbPayloadSize()` + numeric conversion logic from `jsonReturnFromBlob()` |
``````
