---
url: https://chatgpt.com/c/6a78e25b-3040-83eb-96bb-ad2a02e1face
---

## 📗 SQLite `json.c`

> [!NOTE] Prompt
> 
> Is there a straightforward clear transform between an array of doubles and JSON array of doubles? I want switch between binary and human readable vectors. Tell me, this function from `json.c` transforms in one direction, that in the opposite. 

Yes. Looking specifically at the supplied `json.c`, there is **not** a single ready-made internal function named “JSON array → `double[]`” or “`double[]` → JSON array”. But almost all of the machinery already exists, and the glue you would need is very small.

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

The only real missing abstraction in `json.c` is something like `jsonNodeToDouble(JsonParse*, i, double*)`. Everything else you need is already there.

---
---

## 📗 Implementation Strategy

> [!NOTE] Prompt
> 
> So, you are ready to code json2double_array and double2json_array?

Yes.

I’m ready to implement both directly against SQLite’s internal `json.c` machinery:

```c
int json2double_array(
    sqlite3_context *ctx,
    sqlite3_value *value,
    double **array,
    sqlite3_uint64 *count
);

int double2json_array(
    sqlite3_context *ctx,
    const double *array,
    sqlite3_uint64 count
);
```

The implementation would use:

* `json2double_array()`:
  `jsonParseFuncArg()` → require `JSONB_ARRAY` → `jsonbArrayCount()` → iterate nodes with `jsonbPayloadSize()` → accept numeric JSON nodes only → convert with the same `sqlite3DecOrHexToI64()` / `sqlite3AtoF()` logic already used by `jsonReturnFromBlob()`. 
* `double2json_array()`:
  `JsonString` → `jsonStringInit()` → `[` → `jsonPrintf(..., "%!0.17g", value)` with separators → `]` → `jsonReturnString()`. That follows the existing `jsonArrayFunc()` / `jsonAppendSqlValue()` machinery. 

I would also make `json2double_array()` reject `null`, strings, objects, nested arrays, booleans, etc., rather than silently coercing them.

And yes: at this point this is implementation work, not more architectural discussion.

---
---

## 📗 Binary Format

> [!NOTE] Prompt
> 
> The binary form is just a bare C array

Yes. Then the binary side is even simpler: **no header, no count, no metadata, no custom encoding** — just contiguous native C `double` values.

So the intended pair is effectively:

```c
int json2double_array(
    sqlite3_context *ctx,
    sqlite3_value *value,
    double **array,
    sqlite3_uint64 *count
);

void double2json_array(
    sqlite3_context *ctx,
    const double *array,
    sqlite3_uint64 count
);
```

`json2double_array()` allocates `count * sizeof(double)` and fills it from a JSON numeric array.

`double2json_array()` takes an existing bare `double[]` plus its element count and emits JSON text.

If this array is stored as an SQLite BLOB, then the BLOB payload is literally:

```c
(double *)sqlite3_value_blob(...)
```

with:

```c
count = sqlite3_value_bytes(...) / sizeof(double);
```

subject only to validating that the byte count is divisible by `sizeof(double)`.

No serialization layer is needed on the binary side.

---
---

## 📗 Implementation Draft

> [!NOTE] Prompt
> 
> Create both functions

Yes. Given your actual objective—**SQLite TEXT JSON array ⇄ SQLite BLOB containing nothing but contiguous C `double` values**—I would make them SQL-function implementations directly.

The JSON side below reuses `jsonParseFuncArg()`, `jsonbPayloadSize()`, `JsonString`, `jsonPrintf()` and `jsonReturnString()` from your supplied `json.c`. SQLite already uses `jsonParseFuncArg()` for parsing and `jsonbPayloadSize()` for walking nodes, while its floating output uses `%!0.17g`.   

```c
/*
** json2double_array(JSON)
**
** Convert a JSON array containing only numeric values into a BLOB whose
** content is a bare contiguous C array of double values.
**
** Examples:
**
**   [1.0, 2.5, -3.0]
**
** becomes the byte representation of:
**
**   double a[] = { 1.0, 2.5, -3.0 };
**
** No header, element count, type code, or other metadata is included.
*/
static void json2double_array(
  sqlite3_context *ctx,
  int argc,
  sqlite3_value **argv
){
  JsonParse *p;
  sqlite3 *db;
  double *aOut = 0;
  u32 nHdr, nPayload;
  u32 i;
  u32 iEnd;
  u32 nElem;
  u32 iElem;

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

  if( (sqlite3_uint64)nElem >
      SQLITE_MAX_LENGTH/(sqlite3_uint64)sizeof(double) ){
    sqlite3_result_error_toobig(ctx);
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
  if( nHdr==0 ){
    goto malformed;
  }

  i = nHdr;
  iEnd = i + nPayload;
  iElem = 0;

  while( i<iEnd ){
    u32 n;
    u32 sz;
    u8 eType;
    const char *zNum;
    char *z;
    double r;
    int rc;

    n = jsonbPayloadSize(p, i, &sz);
    if( n==0 || i+n+sz>iEnd ){
      goto malformed;
    }

    eType = p->aBlob[i] & 0x0f;

    switch( eType ){
      case JSONB_INT:
      case JSONB_FLOAT:
      case JSONB_FLOAT5: {
        if( sz==0 ){
          goto malformed;
        }

        zNum = (const char*)&p->aBlob[i+n];
        z = sqlite3DbStrNDup(db, zNum, (int)sz);
        if( z==0 ){
          goto oom;
        }

        rc = sqlite3AtoF(z, &r);
        sqlite3DbFree(db, z);

        if( rc<=0 ){
          goto malformed;
        }

        aOut[iElem] = r;
        break;
      }

      case JSONB_INT5: {
        sqlite3_int64 iRes = 0;
        sqlite3_uint64 uRes;
        int bNeg = 0;
        u32 j = n;
        u32 nNum = sz;

        if( nNum==0 ){
          goto malformed;
        }

        if( p->aBlob[i+j]=='-' ){
          bNeg = 1;
          j++;
          nNum--;
          if( nNum==0 ){
            goto malformed;
          }
        }

        zNum = (const char*)&p->aBlob[i+j];
        z = sqlite3DbStrNDup(db, zNum, (int)nNum);
        if( z==0 ){
          goto oom;
        }

        rc = sqlite3DecOrHexToI64(z, &iRes);
        sqlite3DbFree(db, z);

        if( rc==0 ){
          if( iRes<0 ){
            memcpy(&uRes, &iRes, sizeof(uRes));
            r = (double)uRes;
          }else{
            r = (double)iRes;
          }
          if( bNeg ){
            r = -r;
          }
        }else if( rc==3 && bNeg ){
          r = (double)SMALLEST_INT64;
        }else{
          /*
          ** Fall back to SQLite's floating-point parser, matching the
          ** strategy used by jsonReturnFromBlob().
          */
          zNum = (const char*)&p->aBlob[i+n];
          z = sqlite3DbStrNDup(db, zNum, (int)sz);
          if( z==0 ){
            goto oom;
          }

          rc = sqlite3AtoF(z, &r);
          sqlite3DbFree(db, z);

          if( rc<=0 ){
            goto malformed;
          }
        }

        aOut[iElem] = r;
        break;
      }

      default: {
        sqlite3_result_error(
            ctx,
            "JSON array must contain only numbers",
            -1
        );
        sqlite3DbFree(db, aOut);
        jsonParseFree(p);
        return;
      }
    }

    iElem++;
    i += n + sz;
  }

  if( i!=iEnd || iElem!=nElem ){
    goto malformed;
  }

  /*
  ** sqlite3DbMallocRaw() memory is compatible with SQLITE_DYNAMIC
  ** when returned by SQLite itself.
  */
  sqlite3_result_blob64(
      ctx,
      aOut,
      (sqlite3_uint64)nElem * sizeof(double),
      SQLITE_DYNAMIC
  );

  jsonParseFree(p);
  return;

oom:
  sqlite3DbFree(db, aOut);
  jsonParseFree(p);
  sqlite3_result_error_nomem(ctx);
  return;

malformed:
  sqlite3DbFree(db, aOut);
  jsonParseFree(p);
  sqlite3_result_error(ctx, "malformed JSON array", -1);
}


/*
** double2json_array(BLOB)
**
** Interpret BLOB as a bare contiguous C array of double values and return
** the corresponding JSON text array.
**
** The BLOB size must be an exact multiple of sizeof(double).
*/
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

  nByte = (sqlite3_uint64)sqlite3_value_bytes(argv[0]);

  if( nByte % sizeof(double)!=0 ){
    sqlite3_result_error(
        ctx,
        "invalid double-array BLOB size",
        -1
    );
    return;
  }

  nElem = nByte / sizeof(double);
  a = (const double*)sqlite3_value_blob(argv[0]);

  if( nByte>0 && a==0 ){
    sqlite3_result_error_nomem(ctx);
    return;
  }

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

The numeric parsing deliberately follows the machinery in `jsonReturnFromBlob()`: SQLite parses `JSONB_FLOAT`/`FLOAT5` with `sqlite3AtoF()` and handles integer nodes separately via `sqlite3DecOrHexToI64()`.  

For the reverse transform, the implementation mirrors `jsonArrayFunc()`, except the elements come directly from the packed `double[]`; SQLite itself formats floating values with `jsonPrintf(..., "%!0.17g", ...)`.  

One thing I would change before dropping this into your extension: since your intended input is **ordinary canonical JSON text**, I would probably reject `JSONB_INT5` and `JSONB_FLOAT5` entirely. That removes a substantial chunk of `json2double_array()` and makes its numeric loop essentially just `JSONB_INT | JSONB_FLOAT → sqlite3AtoF()`.

---
---

## 📗 `JSONB_INT5` and `JSONB_FLOAT5`

> [!NOTE] Prompt
> 
> Explain `JSONB_INT5` and `JSONB_FLOAT5`  

`JSONB_INT5` and `JSONB_FLOAT5` are SQLite-internal node types used to preserve **JSON5-style numeric syntax** that is not valid canonical RFC 8259 JSON.

In your `json.c`:

```c
#define JSONB_INT      3   /* RFC-8259 integer literal */
#define JSONB_INT5     4   /* JSON5 integer literal */
#define JSONB_FLOAT    5   /* RFC-8259 floating point literal */
#define JSONB_FLOAT5   6   /* JSON5 floating point literal */
```



`JSONB_INT5` is primarily for JSON5 integer forms such as hexadecimal integers:

```text
0x10
-0x20
```

The parser specifically recognizes `0x` / `0X` and marks the resulting node as the JSON5 integer type. Later, when converting that node back to canonical JSON text, SQLite converts the hexadecimal value to decimal. 

So conceptually:

```text
0x10
  ↓ parse
JSONB_INT5
  ↓ canonical rendering
16
```

`JSONB_FLOAT5` is for floating-point literals accepted by JSON5 but not by canonical JSON, particularly forms with omitted digits adjacent to the decimal point:

```text
.5
1.
-.5
```

The code explicitly describes it as:

```c
case JSONB_FLOAT5: { /* Float literal missing digits beside "." */
```

and canonicalizes these when rendering:

```text
.5   -> 0.5
1.   -> 1.0
-.5  -> -0.5
```



There are other nonstandard numeric forms handled by the parser—such as `+1`, `Infinity`, `NaN`, etc.—but SQLite may normalize some of those immediately into ordinary `JSONB_FLOAT` or `JSONB_NULL` rather than retaining them specifically as `FLOAT5`. 

For **your `json2double_array()`**, this distinction is almost irrelevant. All four types represent numbers:

```c
JSONB_INT
JSONB_INT5
JSONB_FLOAT
JSONB_FLOAT5
```

and your destination is simply a `double`.

So I would **accept all four**. There is no useful reason to reject `INT5`/`FLOAT5` unless you deliberately want your function to accept only strict RFC-8259 JSON. SQLite's normal JSON parser already accepts JSON5, so accepting all four is the more natural behavior.

---
---

## 📗 Format Scope

> [!NOTE] Prompt
> 
> I need 1.23 <-> {double}. I just need to see the simplest NORMAL reals. I do not need hexa- I do not need ternary, I NEED to INSPECT components of an AI generated vector and store it as either plain JSON or packed blob

Then the scope should be **strictly this**:

```text
JSON text:   [1.23, -4.5, 0.0]
               ⇅
C memory:    double[]
               ⇅
SQLite BLOB: raw bytes of that double[]
```

No JSON5. No hex. No NaN/Infinity. No coercion. No nested arrays. No metadata.

For parsing, accept only ordinary JSON numeric nodes that represent decimal integers/reals:

```c
JSONB_INT
JSONB_FLOAT
```

and convert both to `double`.

So `json2double_array()` becomes much simpler:

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

This is the right level for your use case: **inspect AI embedding/vector components as ordinary decimal JSON when needed; otherwise store exactly the same values as a compact raw `double[]` BLOB.** 

---
---

## 📗 Float32 and Float16

> [!NOTE] Prompt
> 
> I haven't studied your json2double_array solution. How difficult would it be to integrate further transforms of double to float32 and float16 blobs, possibly with or without creating double blob?

Not difficult. Architecturally, I would **not** make `json2double_array()` the center of the design if you already know you may want `float32` and `float16` blobs.

The clean design is:

```text
JSON text
   |
   v
parse numeric elements once
   |
   +--> double[]  BLOB
   +--> float[]   BLOB
   +--> fp16[]    BLOB
```

That means the JSON parser should expose each parsed numeric value as a C `double` during iteration, and the destination writer decides how to store it.

So instead of:

```c
json2double_array(...)
```

being the low-level primitive, I would factor out something conceptually like:

```c
json_array_foreach_number(...)
```

or a small internal loop that does:

```c
JSONB_INT / JSONB_FLOAT
    -> sqlite3AtoF(...)
    -> double r
```

Then:

```c
double_blob[i] = r;
float_blob[i]  = (float)r;
fp16_blob[i]   = convert_double_to_fp16(r);
```

### You do not need an intermediate double BLOB

For:

```text
JSON -> float32 BLOB
```

you can parse each JSON number to a temporary C `double`:

```c
double r;
sqlite3AtoF(z, &r);
aOut[i] = (float)r;
```

The `double` exists only as a scalar temporary. There is no reason to allocate a complete `double[]` first.

Likewise:

```text
JSON -> float16 BLOB
```

can be:

```c
double r;
sqlite3AtoF(z, &r);
aOut[i] = double_to_fp16(r);
```

So memory use stays approximately:

```text
JSON -> double:   N * 8 bytes
JSON -> float32:  N * 4 bytes
JSON -> float16:  N * 2 bytes
```

plus the existing SQLite JSON parse representation.

### If you want multiple representations at once

Suppose one operation needs all three:

```text
JSON
 ├─ double[]
 ├─ float32[]
 └─ float16[]
```

You still only parse the JSON **once**. For every component:

```c
double x = ...;

a64[i] = x;
a32[i] = (float)x;
a16[i] = fp16_from_double(x);
```

That's preferable to:

```text
JSON -> double BLOB -> float BLOB -> fp16 BLOB
```

because the latter allocates unnecessary intermediate storage and performs extra passes.

### The natural decomposition

I would probably factor the code into three levels:

```c
/* Parse one JSON numeric node. */
static int jsonNumberToDouble(
    JsonParse *p,
    u32 i,
    double *pValue
);
```

Then allocation/conversion functions:

```c
static void json2double_array(...);
static void json2float_array(...);
static void json2float16_array(...);
```

All three share essentially the same loop:

```c
while( i<iEnd ){
    double x;

    ...
    jsonNumberToDouble(p, i, &x);

    /* only this line differs */
    aOut[iElem] = ...;

    i += n + sz;
}
```

For `double`:

```c
aOut[iElem] = x;
```

For `float32`:

```c
aOut[iElem] = (float)x;
```

For FP16:

```c
aOut[iElem] = fp16_from_double(x);
```

The same decomposition also works in the opposite direction:

```text
double BLOB  ─┐
float32 BLOB ─┼─> JSON text
float16 BLOB ─┘
```

The common JSON formatter accepts a `double`, so:

```c
double x = a64[i];
double x = (double)a32[i];
double x = fp16_to_double(a16[i]);

jsonPrintf(100, &jx, "%!0.17g", x);
```

For float32/float16 you could later choose shorter formatting appropriate to their precision, but that is an output-format preference, not an architectural problem.

So I would **refactor before finalizing `json2double_array()`**. The JSON traversal and numeric decoding should be common; `double`, `float32`, and `float16` should just be three destination encodings. That keeps the implementation small and avoids ever needing an intermediate `double` BLOB.

---
---

## 📗 API Draft

> [!NOTE] Prompt
> 
> I need one representation. The second arg will select dest size f2 vs f4 and endianness

Then I would collapse this to **one conversion function** selected by the second argument.

Conceptually:

```sql
json2array(json, format)
```

where `format` encodes both element width and byte order, for example:

```text
f2le
f2be
f4le
f4be
f8le
f8be
```

If you only need f2/f4 now, omit f8.

The important architectural point is: **JSON is parsed only once and no intermediate double array/BLOB is created.** Each JSON component is parsed by SQLite into a temporary C `double`, then immediately encoded into the requested destination representation:

```c
double x = ...;  /* parsed JSON number */

switch( format ){
  case F4_NATIVE:
    ((float *)aOut)[i] = (float)x;
    break;

  case F2_NATIVE:
    ... convert x to binary16 ...
    break;
}
```

For explicit endianness, I would actually avoid treating the output buffer as `float *` or `uint16_t *`. Generate the required bit representation and write its bytes explicitly:

```text
JSON 1.23
   ↓
double x              // temporary parser result only
   ↓
float32 / float16 bits
   ↓
requested byte order
   ↓
BLOB
```

Thus the output allocation is known immediately from the JSON array count:

```c
nByte = nElem * element_size;
```

with:

```c
element_size = 2;   /* f2 */
element_size = 4;   /* f4 */
```

and each element goes directly to:

```c
aOut + i * element_size
```

### I would separate two concerns internally

Not separate SQL functions—just helpers:

```c
static int jsonNumberToDouble(
    JsonParse *p,
    u32 i,
    double *pValue
);
```

and something like:

```c
static void storeFloat32(
    unsigned char *p,
    double value,
    int bigEndian
);

static void storeFloat16(
    unsigned char *p,
    double value,
    int bigEndian
);
```

Then `json2array()` itself stays very simple:

```c
for each JSON element {
    double x;

    if( jsonNumberToDouble(p, i, &x) ){
        error;
    }

    if( eType==F2 ){
        storeFloat16(&aOut[iElem * 2], x, bigEndian);
    }else{
        storeFloat32(&aOut[iElem * 4], x, bigEndian);
    }
}
```

For **f4**, conversion is trivial: `(float)x`, obtain its 32-bit representation, and emit its four bytes in the requested order.

For **f2**, the only substantive extra component is binary16 conversion. If you already intend to use FP16 or another established implementation for half conversion, that helper should be used rather than implementing IEEE-754 binary16 rounding manually.

One thing I would change from the earlier interface: call it something like **`json2float_array()` or `json2blob()`**, not `json2double_array()`, because once argument 2 selects `f2`/`f4`, `double` is merely the internal parsing type and no longer describes the result.

---
---

## 📗 API Draft

> [!NOTE] Prompt
> 
> I do not care about Jsonb blob format! I need to garther Lego pieces. JSON can take a blob and return JSON text. Jsonb then can take JSON text and return blob. I do not care if any function does end-to-end, I guess, there is no such thing. 
> 
> So I will have something like SQL  
> 
> - pblob_pack(json_vector: SQLITE_TEXT, format: SQLITE_TEXT) -> SQLITE_BLOB
> - pblob_unpack(blob_data: SQLITE_BLOB, format: SQLITE_TEXT) -> SQLITE_TEXT
> 
> format: `>f2`, `<f2`, `>f4`, `<f4`  
> The interfaces between these functions and SQLite can be modeled after jsonb() and json() directly, including memory management. Then inside implementation function will be the code you presented earlier.

Yes. That decomposition is clean, and your “Lego pieces” framing is the right one.

You can model the **SQL-facing wrapper behavior** after SQLite’s `json()` / `jsonb()` functions, while your actual payload conversion is completely different.

Your public SQL API:

```sql
pblob_pack(json_vector, format) -> BLOB
pblob_unpack(blob_data, format) -> TEXT
```

with:

```text
>f2
<f2
>f4
<f4
```

is coherent.

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
typedef enum {
  PBLOB_F16_LE,
  PBLOB_F16_BE,
  PBLOB_F32_LE,
  PBLOB_F32_BE
} PblobFormat;
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

That is substantially cleaner than trying to force an end-to-end SQLite JSON function to do something it was never designed to do.
