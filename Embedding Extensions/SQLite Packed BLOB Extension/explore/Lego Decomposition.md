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

## 📗 Modeling After `json()` and `jsonb()`

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

---
---

## 📗 Format Conversion - Size and Endianness

> [!NOTE] Prompt
> 
> For f8 <-> f4 I simply use C typecasting?
> For f4 <-> f2 which FP 16 functions do I use? 
> ---
> FP16 attachments:
> - bitcasts.h
> - fp16.h
> - macros.h

Yes.

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

So I would **not** byte-swap a `float` object itself. Convert to integer bits first, then explicitly emit/read the integer bytes according to `<` or `>`.

Also, use the `ieee` functions, not the `alt` functions. The `fp16_alt_*` family implements ARM's alternative half-precision format, which is not the standard IEEE binary16 representation you mean by `f2`. 

The library also automatically selects native F16C/ARM conversion paths where available and otherwise falls back to its portable implementation. 

---
---

## 📗 Default Endianness

> [!NOTE] Prompt
> 
> What is endianness of C float and uint16_t? If I actually do not care about endianness now, which one I use?

For ordinary C objects, the byte order of both `float` and `uint16_t` is the platform’s native endianness.

So on a typical x86/x64 machine:

```text
uint16_t 0x1234  -> bytes 34 12
float    1.0f    -> IEEE-754 bits 0x3f800000 -> bytes 00 00 80 3f
```

That is little-endian.

If you **do not care about endianness now**, use native representation directly. For your current Windows/x64 target, that means effectively little-endian.

For f4 packing, simplest is:

```c
float f = (float)x;
memcpy(pOut, &f, sizeof(f));
```

For f2:

```c
uint16_t h = fp16_ieee_from_fp32_value((float)x);
memcpy(pOut, &h, sizeof(h));
```

And unpack symmetrically:

```c
float f;
memcpy(&f, pIn, sizeof(f));
double x = (double)f;
```

and:

```c
uint16_t h;
memcpy(&h, pIn, sizeof(h));
double x = (double)fp16_ieee_to_fp32_value(h);
```

That is the simplest and cleanest approach if portability of the stored BLOB across big-endian machines is not currently a requirement.

I would then simplify your format names to just:

```text
f2
f4
```

and add explicit `<f2`, `>f2`, etc. only if you later decide the BLOB format must have defined cross-platform byte order.

---
---

## 📗 Endianness Handling

> [!NOTE] Prompt
> 
> So, if native endianness is platform dependent, how do I ensure in C that I return result in specific endianness?

You ensure it by **serializing bytes explicitly**, rather than copying the native object representation directly.

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

So the rule is:

```text
numeric value
   ↓
integer bit pattern
   ↓
explicit byte order
   ↓
BLOB
```

That is the cleanest way to guarantee `<f2`, `>f2`, `<f4`, `>f4` regardless of host architecture.

---
---

## 📗 Endianness Clarification

> [!NOTE] Prompt
> 
> Is ieee byte order platform independent?
> Are you sure fp16_ieee_from_fp32_value and fp32_to_bits return byte order independent of native?
> You use fp32_to_bits, but not fp16_to_bits - why?
> fp16_ieee_to_fp32_value return native order?

1. **IEEE-754 defines the bit layout of binary16/binary32/binary64 values, but not the byte order used to store those bits in memory.** Byte order is a platform/ABI property.

So, for example, the binary32 value `1.0f` has the IEEE bit pattern:

```text
0x3f800000
```

That bit pattern is platform-independent as a 32-bit integer value. Its **memory bytes** are not:

```text
little-endian memory: 00 00 80 3f
big-endian memory:    3f 80 00 00
```

2. Yes, `fp32_to_bits()` is byte-order independent in the sense that it returns the **integer bit pattern**, not a byte sequence.

Your attached implementation is effectively a bitcast:

```c
static inline uint32_t fp32_to_bits(float f)
```

and returns a `uint32_t` whose numeric value is the IEEE-754 representation of `f`. 

For `1.0f`:

```c
uint32_t u = fp32_to_bits(1.0f);

/* u == 0x3f800000 */
```

That numeric integer value is the same on little- and big-endian machines.

Only when you inspect:

```c
(unsigned char *)&u
```

does native endianness enter the picture.

3. `fp16_ieee_from_fp32_value()` works the same way conceptually:

```c
uint16_t h = fp16_ieee_from_fp32_value(f);
```

It returns the **16-bit IEEE binary16 bit pattern as a `uint16_t` integer value**. 

For example, binary16 `1.0` has:

```text
0x3c00
```

so:

```c
uint16_t h = fp16_ieee_from_fp32_value(1.0f);

/* h == 0x3c00 */
```

regardless of host byte order.

Again, if you `memcpy()` `h` into a BLOB, the bytes will follow native endianness. If you explicitly shift `h`, you control the serialized byte order.

4. There is no need for an `fp16_to_bits()` function because **the FP16 library already represents binary16 as bits**.

This API:

```c
uint16_t fp16_ieee_from_fp32_value(float f);
```

does not return a C half-float object. It returns:

```c
uint16_t
```

containing the binary16 encoding itself.

So:

```text
float value
    ↓
fp16_ieee_from_fp32_value()
    ↓
uint16_t bit pattern
```

There is nothing left to bitcast.

By contrast, `float` is a floating-point C object, so to get its binary representation you need:

```c
fp32_to_bits(float)
```

Hence the asymmetry:

```c
float
  -> fp32_to_bits()
  -> uint32_t

float
  -> fp16_ieee_from_fp32_value()
  -> uint16_t
```

The latter operation includes both **precision conversion and conversion to bits**.

5. `fp16_ieee_to_fp32_value()` returns a normal C `float` value:

```c
float fp16_ieee_to_fp32_value(uint16_t h);
```

It does **not** return anything in an endian-specific order. “Endianness” does not meaningfully apply to the abstract numeric value returned by a C expression.

After:

```c
float f = fp16_ieee_to_fp32_value(0x3c00);
```

you have:

```text
f == 1.0f
```

The compiler/platform decides how that `float` object is stored in memory.

If you subsequently need the IEEE binary32 bit pattern:

```c
uint32_t u = fp32_to_bits(f);
```

then:

```text
u == 0x3f800000
```

independent of native byte order.

So for your code, keep these three concepts separate:

```text
numeric value        bit pattern          serialized bytes
-------------        -----------          ----------------
float 1.0f       ->  uint32 0x3f800000 -> 00 00 80 3f   LE
                                          3f 80 00 00   BE

float 1.0f       ->  uint16 0x3c00     -> 00 3c         LE
                                          3c 00         BE
```

The FP16/bitcast functions get you from **numeric value ↔ integer bit pattern**. Your byte-writing code determines **endianness**.

---
---

## 📗 Format header

> [!NOTE] Prompt
> 
> I actually want prepend each vector with one extra element to indicate size and endianness. Is this an established approach?

Yes, **prefixing binary payloads with a small header describing the representation is an established binary-format pattern**. What is *not* particularly established is pretending that header is another floating-point vector element.

For your format, I would treat it as:

```text
+-------------+-----------------------------+
| format tag  | packed floating-point data  |
+-------------+-----------------------------+
```

rather than conceptually:

```text
float[N+1]
```

The payload remains a bare homogeneous array; the first 1–2 bytes are metadata.

For what you need, a **single byte is enough**. You have only four formats:

```text
0x00   <f2
0x01   >f2
0x02   <f4
0x03   >f4
```

Then:

```text
<f2:  [00] [2-byte value] [2-byte value] ...
>f2:  [01] [2-byte value] [2-byte value] ...
<f4:  [02] [4-byte value] [4-byte value] ...
>f4:  [03] [4-byte value] [4-byte value] ...
```

The vector length does **not need to be stored** because SQLite already gives you the BLOB byte length. Once the format byte tells you element width:

```c
count = (blob_size - 1) / element_size;
```

and you validate:

```c
(blob_size - 1) % element_size == 0
```

### I would probably make the tag bit-oriented

For example:

```text
bit 0     endianness: 0 = little, 1 = big
bits 1-2  element type:
          0 = f2
          1 = f4
          2 = reserved f8
          3 = reserved
bits 3-7  reserved
```

Then:

```c
#define PBLOB_F2_LE  0x00
#define PBLOB_F2_BE  0x01
#define PBLOB_F4_LE  0x02
#define PBLOB_F4_BE  0x03
#define PBLOB_F8_LE  0x04
#define PBLOB_F8_BE  0x05
```

This gives you room to extend without changing the format.

### One concern: alignment

Once you put a one-byte header in front:

```text
header byte | f4 | f4 | f4 ...
             ^
             offset 1
```

the f4 payload is no longer naturally aligned. That's completely fine **if you treat this as serialized bytes**, which you already should because of explicit endianness.

Do not do:

```c
const float *a = (const float *)(blob + 1);
```

Instead decode from bytes / integer bit patterns as discussed earlier.

Likewise for f2.

### An alternative: one element-sized header

If by "one extra element" you literally mean:

```text
f2 format -> 2-byte header + N × 2-byte values
f4 format -> 4-byte header + N × 4-byte values
```

that gives you natural alignment, but now you have a chicken-and-egg problem: **you need to know the element size before you know how large the header is**.

You can solve that, but it makes the format unnecessarily awkward.

I'd therefore prefer:

```text
1-byte format tag
N packed values
```

This is essentially the minimal version of the standard **header + payload** binary-format pattern. It makes your BLOB self-describing while adding exactly one byte of overhead.

And it has another nice consequence: your SQL API can eventually simplify from:

```sql
pblob_unpack(blob, '<f4')
```

to simply:

```sql
pblob_unpack(blob)
```

because the BLOB itself says what it contains. For `pblob_pack()`, the format argument still selects what to create.

---
---

## 📗 Suffix Header

> [!NOTE] Prompt
> 
> Not good. Header MUST NOT screw alignment regardless. I guess, the simplest option is to have a fixed 4-byte header (I do not store f8, only f4 or f2. Vector length in practice is several hundreds, so 2 extra elements for even for 100 f2 is 2% overhead. In practice it will be probably less than 1%. Because I know blob size, the header shall be APPENDED to the vector, not PRE-. There is no good reason to deal with freaking off by 1 index.

Yes. A **fixed 4-byte trailer** is cleaner for your case.

Layout:

```text
+-----------------------------+------------------+
| packed f2/f4 vector payload | 4-byte metadata  |
+-----------------------------+------------------+
```

That preserves payload alignment automatically:

* f2 payload starts at offset 0, aligned to 2
* f4 payload starts at offset 0, aligned to 4
* metadata is out of the way at the end
* no payload indexing offset
* `count` derives from `(blob_size - 4) / element_size`

So for f4:

```text
[value0][value1][value2]...[valueN-1][meta4]
```

and for f2:

```text
[value0][value1][value2]...[valueN-1][meta4]
```

The validation becomes trivial:

```c
if( nBlob < 4 ){
    error;
}

meta = pBlob + nBlob - 4;

element_size = ...from metadata...;

payload_size = nBlob - 4;

if( payload_size % element_size != 0 ){
    error;
}

count = payload_size / element_size;
```

A 4-byte metadata word also gives you plenty of room. For example:

```text
byte 0: format/version marker
byte 1: element type   2=f2, 4=f4
byte 2: endianness     0=LE, 1=BE
byte 3: reserved
```

or, more compactly, define the whole trailer as one fixed `uint32_t` tag space:

```c
#define PBLOB_F2_LE  ...
#define PBLOB_F2_BE  ...
#define PBLOB_F4_LE  ...
#define PBLOB_F4_BE  ...
```

I would slightly prefer the latter if the format is intentionally tiny and closed.

One more point: since the trailer itself is metadata, **its own endianness should not need interpretation**. Easiest is to make the four trailer bytes literal tag bytes, not a native `uint32_t` written with `memcpy()`. Then the payload endianness can vary while trailer parsing remains platform-independent.

So yes: **payload first, fixed 4-byte trailer last** is a very reasonable design here, and better than a 1-byte prefix for your alignment-sensitive use case.

---
---

## 📗 Symmetric Trailer

> [!NOTE] Prompt
> 
> So, this is fine
> ```text
> bit 0     endianness: 0 = little, 1 = big
> bits 1-2  element type:
>           0 = f2
>           1 = f4
>           2 = reserved f8
>           3 = reserved
> bits 3-7  reserved
> ```
> 
> Then:
> 
> ```c
> #define PBLOB_F2_LE  0x00000000
> #define PBLOB_F2_BE  0x01010101
> #define PBLOB_F4_LE  0x02020202
> #define PBLOB_F4_BE  0x03030303
> #define PBLOB_F8_LE  0x04040404
> #define PBLOB_F8_BE  0x05050505
> ```

Yes. That is internally consistent, and the repeated-byte 32-bit trailer is actually a useful trick.

Your 8-bit encoding is:

```text
bits 1-2  type
bit 0     endian

000 = f2 LE
001 = f2 BE
010 = f4 LE
011 = f4 BE
100 = f8 LE
101 = f8 BE
```

So the corresponding byte values are exactly `0x00` through `0x05` as you show.

Repeating that byte four times:

```c
#define PBLOB_F2_LE  UINT32_C(0x00000000)
#define PBLOB_F2_BE  UINT32_C(0x01010101)
#define PBLOB_F4_LE  UINT32_C(0x02020202)
#define PBLOB_F4_BE  UINT32_C(0x03030303)
#define PBLOB_F8_LE  UINT32_C(0x04040404)
#define PBLOB_F8_BE  UINT32_C(0x05050505)
```

has a nice property: **the trailer itself is endian-independent even if you write/read it as a native `uint32_t`**, because reversing four identical bytes changes nothing:

```text
0x03030303

LE memory: 03 03 03 03
BE memory: 03 03 03 03
```

So you can safely do something like:

```c
uint32_t format = PBLOB_F4_LE;
memcpy(pOut + payload_size, &format, sizeof(format));
```

without caring about host endianness.

Likewise, reading:

```c
uint32_t format;
memcpy(&format, pBlob + nBlob - 4, sizeof(format));
```

produces the same constant on either endian architecture.

There is also some useful redundancy: you can interpret the trailer as four format bytes and require all four to agree. A malformed trailer such as:

```text
02 02 03 02
```

is immediately invalid.

One caveat is `PBLOB_F2_LE == 0`. Therefore four zero bytes at the end of an arbitrary BLOB accidentally constitute a valid-looking trailer. If `pblob` BLOBs are always produced and consumed by your own functions, that may be perfectly acceptable. If you want stronger identification of arbitrary/corrupt BLOBs, you could eventually spend some of those reserved bits on a marker/version.

But as a **minimal four-byte format trailer**, this design is simple, alignment-safe, endian-safe, and easy to decode. I would use it.

---
---

## 📗 Adjusted Marker Encoding

> [!NOTE] Prompt
> 
> Change to 
> 
> ```text
> bit 0     reserved, must be 1
> bit 1     endian
> bit 2     type
> 
> 001 = f2 LE
> 011 = f2 BE
> 101 = f4 LE
> 111 = f4 BE
> ```

Yes. That is cleaner.

```text
bit 0     reserved, must be 1
bit 1     endian
bit 2     type

001 = f2 LE
011 = f2 BE
101 = f4 LE
111 = f4 BE
```

So:

```c
#define PBLOB_F2_LE  UINT32_C(0x01010101)
#define PBLOB_F2_BE  UINT32_C(0x03030303)
#define PBLOB_F4_LE  UINT32_C(0x05050505)
#define PBLOB_F4_BE  UINT32_C(0x07070707)
```

This is better than starting at zero because an all-zero trailer is now automatically invalid.

Decoding one trailer byte is trivial:

```c
uint8_t tag = pTrailer[0];

if( (tag & 0x01)==0 ){
    /* invalid */
}

int big_endian = (tag >> 1) & 0x01;
int is_f4      = (tag >> 2) & 0x01;
```

And with the repeated-byte trailer, you can additionally require:

```c
pTrailer[0] == pTrailer[1] &&
pTrailer[0] == pTrailer[2] &&
pTrailer[0] == pTrailer[3]
```

before interpreting it.

That gives you four valid encodings only:

```text
01 01 01 01   f2 LE
03 03 03 03   f2 BE
05 05 05 05   f4 LE
07 07 07 07   f4 BE
```

I would use exactly this scheme.

---
---

## 📗 Revised API

> [!NOTE] Prompt
> 
> So, If I use trailer, I would have to have 
> 
> ```sql
> pblob_pack(json_vector, format) -> BLOB
> pblob_unpack(blob_data) -> TEXT
> ```

Exactly.

With the 4-byte trailer carrying both **element type** and **endianness**, `unpack` no longer needs a format argument:

```sql
pblob_pack(json_vector, format) -> BLOB
pblob_unpack(blob_data)         -> TEXT
```

For example:

```sql
pblob_pack('[1.23, 4.56, -7.89]', '<f4')
pblob_pack('[1.23, 4.56, -7.89]', '>f2')
```

produce:

```text
[payload ...][01 01 01 01]   <f2
[payload ...][03 03 03 03]   >f2
[payload ...][05 05 05 05]   <f4
[payload ...][07 07 07 07]   >f4
```

Then:

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

This also gives you a useful invariant:

```c
nBlob >= 4
```

and:

```c
count = (nBlob - 4) / element_size;
```

So yes, the trailer makes the BLOB **self-describing**, and the asymmetric SQL API is the natural result: `pack` needs to be told what representation to create; `unpack` discovers the representation from the BLOB itself.
