---
url: https://chatgpt.com/c/6a61e127-7f24-83eb-9bcf-31c5a900a6a4
---

## 📗 SQLite Packed Numeric BLOB Extension Specification - Part 1: Design and Conversion Workflows

> [!NOTE] Prompt
> 
> Let's prepare a detailed implementation spec, part 1, for the coding agent. part 1 will focus on design and part 2 will focus on testing (I will combine the texts later).
> 
> The specification should be generally based on our conversation history in this chat.  
> SQL API  
> - pblob_pack(json_array, format) -> BLOB
> - pblob_unpack(blob, format) -> JSON text
> 
> The spec should, among other expected things enumerate workflows for different data types and edge cases. For each workflow define a logical step-by-step algo. For each step indicate, which specific json.c or fp16 call will be used or the need for original code.
> 
> This is off the top of my head. I expect you to use your knowledge to create a pro spec. If necessary, ask me clarifying questions first.

### 1. Purpose

Implement an amalgamation-only SQLite auto-extension that converts between:

1. A flat JSON array containing numeric scalars.
2. A raw, headerless BLOB containing the same values in one explicitly selected packed representation.

The extension exposes only these SQL scalar functions:

```sql
pblob_pack(json_array, format) -> BLOB
pblob_unpack(blob, format) -> JSON text
```

The extension has no public C API. All implementation helpers are private to the amalgamation.

The initial supported packed formats are:

```text
int8
<f2
>f2
<f4
>f4
```

Where:

* `int8` means signed two’s-complement 8-bit integer.
* `f2` means IEEE 754 binary16.
* `f4` means IEEE 754 binary32.
* `<` means little-endian byte order.
* `>` means big-endian byte order.
* Endianness is irrelevant for `int8` and therefore is not included in its format name.

The extension must minimize new parsing and numeric-conversion code by reusing:

* SQLite `json.c` for JSON parsing, validation, JSONB traversal primitives, decimal/hexadecimal numeric parsing, JSON text construction, allocation error handling, and JSON result subtype handling.
* The vendored FP16 module for IEEE binary16 ↔ binary32 conversion.
* Small original helpers only where SQLite and FP16 do not provide the required operation.

---

### 2. Build and integration model

#### 2.1 Amalgamation-only implementation

The extension is compiled solely as part of the SQLite amalgamation.

It is not:

* a general loadable extension;
* compiled against `sqlite3ext.h`;
* distributed as an independent binary;
* required to preserve compatibility with arbitrary SQLite releases;
* required to expose a stable C ABI.

The implementation may directly call `static` functions and access private structures from `json.c`, provided the packed-blob source is inserted later in the same amalgamation translation unit.

Required source ordering:

```text
SQLite core
json.c
FP16 headers or their bundled expansion
packed-blob implementation
auto-extension dispatcher
```

The implementation is version-coupled to the specific `json.c` incorporated into the amalgamation.

#### 2.2 Conditional compilation

Compile and register the implementation only when JSON support is enabled:

```c
#ifndef SQLITE_OMIT_JSON
/* implementation */
#endif
```

There is no JSON-disabled fallback and no stub implementation.

#### 2.3 FP16 integration

The FP16 module consists of header-only static inline code. Its public top-level header includes `fp16/fp16.h`, which in turn includes its bitcast and configuration headers.
The source bundling process may expand those local includes into the packed-blob source before amalgamation generation. No runtime dependency is introduced.

The implementation must use only the IEEE conversion functions:

```c
fp16_ieee_from_fp32_value()
fp16_ieee_to_fp32_value()
```

Do not use the ARM alternative-half functions.

#### 2.4 Auto-extension registration

Provide one internal initializer callable by the project’s existing auto-extension dispatcher:

```c
int sqlite3PblobInit(sqlite3 *db);
```

The exact name may be adjusted to project naming conventions, but it must not be a public extension entry point such as:

```c
sqlite3_extension_init
```

The initializer registers both SQL functions and returns a normal SQLite result code.

Recommended registration flags:

```c
SQLITE_UTF8
| SQLITE_DETERMINISTIC
| SQLITE_INNOCUOUS
| SQLITE_RESULT_SUBTYPE
```

`SQLITE_RESULT_SUBTYPE` is required because `pblob_unpack()` sets the JSON result subtype. It may be included for both registrations for a uniform registration table, although only `pblob_unpack()` produces a subtype.

Do not use `SQLITE_DIRECTONLY`. These functions should remain usable in:

* CHECK constraints;
* generated columns;
* views;
* triggers;
* expression indexes, where otherwise legal.

---

### 3. Public SQL contract

#### 3.1 `pblob_pack`

```sql
pblob_pack(json_array, format) -> BLOB
```

Converts one JSON text array into a raw packed BLOB.

##### Argument 1

The first argument must be SQL `TEXT` containing valid JSON or SQLite-supported JSON5 input whose top-level value is an array.

This function intentionally accepts **TEXT JSON only**.

Caller-supplied JSONB is not part of the contract. A BLOB first argument must be rejected even when it contains valid SQLite JSONB.

Rationale:

1. `jsonParseFuncArg()` fully parses and validates text JSON.
2. Larger caller-supplied JSONB is initially checked only superficially by `jsonArgIsJsonb()`.
3. Restricting the public contract to TEXT therefore gives a simple and robust validation guarantee.
4. The caller can convert any upstream representation to JSON text using SQLite’s existing JSON functions before invoking `pblob_pack()`.

Accepted examples:

```sql
SELECT pblob_pack('[1,2,-3]', 'int8');
SELECT pblob_pack('[1.0,2.5,-3.25]', '<f2');
SELECT pblob_pack(json('[1,2,3]'), '<f4');
```

Rejected:

```sql
SELECT pblob_pack(jsonb('[1,2,3]'), 'int8');
```

because `jsonb()` returns a BLOB.

##### Argument 2

The second argument must be SQL `TEXT` equal to one of the five exact, case-sensitive format strings.

No aliases, surrounding whitespace, case folding, or native-endian forms are accepted.

Rejected examples:

```text
INT8
i8
f2
float16
<f16
=f4
native-f4
 <f2
<f2 
```

#### 3.2 `pblob_unpack`

```sql
pblob_unpack(blob, format) -> JSON text
```

Converts a raw packed BLOB into compact canonical JSON text.

##### Argument 1

The first argument must be SQL `BLOB`.

No implicit conversion from TEXT is allowed.

A zero-length BLOB is valid for every supported format and returns:

```json
[]
```

##### Argument 2

The second argument follows the same exact format rules as `pblob_pack()`.

##### Result

The result is:

* SQL `TEXT`;
* compact JSON with no unnecessary whitespace;
* marked with `JSON_SUBTYPE` using `sqlite3_result_subtype()`;
* composed only of JSON numeric literals;
* valid canonical JSON, not JSON5.

#### 3.3 NULL propagation

For either function, if either argument is SQL `NULL`, return SQL `NULL` without error.

Examples:

```sql
pblob_pack(NULL, '<f2')  -> NULL
pblob_pack('[1]', NULL)  -> NULL
pblob_unpack(NULL, '<f2') -> NULL
pblob_unpack(x'003C', NULL) -> NULL
```

NULL propagation must occur before strict type checks.

---

### 4. Packed BLOB representation

#### 4.1 General layout

The BLOB is raw and headerless.

It contains:

```text
element 0 bytes
element 1 bytes
...
element N-1 bytes
```

It contains no:

* type identifier;
* byte-order marker;
* element count;
* dimensionality;
* version;
* checksum;
* quantization scale;
* zero point;
* compression header;
* padding;
* alignment bytes.

The caller and database schema are responsible for retaining the format and any external quantization metadata.

#### 4.2 `int8`

Each element occupies one byte.

The mathematical range is:

```text
-128 through 127
```

Stored bytes use two’s-complement encoding:

```text
-128 -> 0x80
-1   -> 0xFF
0    -> 0x00
127  -> 0x7F
```

#### 4.3 Binary16

Each element occupies two bytes.

The 16-bit word uses IEEE 754 binary16:

```text
1 sign bit
5 exponent bits
10 fraction bits
```

For `<f2`, the least-significant byte is stored first.

For `>f2`, the most-significant byte is stored first.

#### 4.4 Binary32

Each element occupies four bytes.

The 32-bit word uses IEEE 754 binary32:

```text
1 sign bit
8 exponent bits
23 fraction bits
```

For `<f4`, the least-significant byte is stored first.

For `>f4`, the most-significant byte is stored first.

---

### 5. Format descriptor

Parse the format argument once before processing any data.

Use a private descriptor similar to:

```c
typedef enum PblobKind {
  PBLOB_INT8,
  PBLOB_F16,
  PBLOB_F32
} PblobKind;

typedef enum PblobByteOrder {
  PBLOB_ORDER_NONE,
  PBLOB_ORDER_LE,
  PBLOB_ORDER_BE
} PblobByteOrder;

typedef struct PblobFormat {
  PblobKind eKind;
  PblobByteOrder eOrder;
  u8 nByte;
} PblobFormat;
```

Required mappings:

| Format | `eKind`      | `eOrder`           | `nByte` |
| ------ | ------------ | ------------------ | ------: |
| `int8` | `PBLOB_INT8` | `PBLOB_ORDER_NONE` |       1 |
| `<f2`  | `PBLOB_F16`  | `PBLOB_ORDER_LE`   |       2 |
| `>f2`  | `PBLOB_F16`  | `PBLOB_ORDER_BE`   |       2 |
| `<f4`  | `PBLOB_F32`  | `PBLOB_ORDER_LE`   |       4 |
| `>f4`  | `PBLOB_F32`  | `PBLOB_ORDER_BE`   |       4 |

The parser is original extension code.

Algorithm:

1. Require `sqlite3_value_type(argv[1]) == SQLITE_TEXT`.
2. Obtain the bytes using:

   ```c
   sqlite3_value_text(argv[1])
   sqlite3_value_bytes(argv[1])
   ```
3. Compare both byte count and bytes against the five accepted constants.
4. Populate `PblobFormat`.
5. On no exact match, report an unsupported-format error.

Do not use locale-aware comparison.

Do not accept embedded NUL characters merely because the visible prefix matches. Compare the explicit SQLite byte count.

---

### 6. Use of `json.c`

The implementation should reuse the following private JSON facilities from the uploaded `json.c`.

#### 6.1 Parsing and validation

Use:

```c
jsonParseFuncArg(ctx, argv[0], 0)
```

This:

* creates a `JsonParse`;
* parses TEXT input into internal JSONB;
* applies SQLite’s JSON and JSON5 syntax rules;
* reports malformed JSON and OOM through `ctx`;
* uses the JSON parse cache when applicable;
* returns `NULL` for SQL NULL.

The text parser translates complete input into `JsonParse.aBlob` and validates complete syntax before returning. `JsonParse` stores the resulting JSONB in `aBlob` and its size in `nBlob`.

Always release a successfully obtained parse using:

```c
jsonParseFree(pParse)
```

#### 6.2 JSONB node structure

Use the existing JSONB type constants:

```c
JSONB_NULL
JSONB_TRUE
JSONB_FALSE
JSONB_INT
JSONB_INT5
JSONB_FLOAT
JSONB_FLOAT5
JSONB_TEXT
JSONB_TEXTJ
JSONB_TEXT5
JSONB_TEXTRAW
JSONB_ARRAY
JSONB_OBJECT
```

The root node begins at offset zero.

The low four bits of the first node byte contain the JSONB type:

```c
pParse->aBlob[i] & 0x0f
```

#### 6.3 Payload decoding

Use:

```c
jsonbPayloadSize(pParse, iNode, &nPayload)
```

The return value is the node-header size.

For a valid node:

```text
payload starts at iNode + nHeader
next node starts at iNode + nHeader + nPayload
```

A return value of zero indicates malformed JSONB.

#### 6.4 Array counting

Use:

```c
jsonbArrayCount(pParse, 0)
```

only after verifying that the root node type is `JSONB_ARRAY`.

This provides the element count needed for exact BLOB allocation.

Because the source is fully parsed TEXT JSON, the internal JSONB is expected to be valid. Nevertheless, every subsequent `jsonbPayloadSize()` return must still be checked defensively.

#### 6.5 Integer parsing

For `JSONB_INT` and `JSONB_INT5`, use the same core parser used by `jsonReturnFromBlob()`:

```c
sqlite3DecOrHexToI64()
```

The extension should not call `strtol`, `strtoll`, `sscanf`, or another external parser.

A small private helper must adapt the relevant logic from `jsonReturnFromBlob()` because that function writes directly to `sqlite3_context` and does not return a C numeric value.

#### 6.6 Floating-point parsing

Use:

```c
sqlite3AtoF()
```

through a small private helper adapted from `jsonReturnFromBlob()`.

The helper copies the non-NUL-terminated JSONB payload to temporary NUL-terminated storage before invoking `sqlite3AtoF()`, matching the existing `json.c` approach. The source implementation uses `sqlite3DbStrNDup()`, `sqlite3AtoF()`, and `sqlite3DbFree()` for this operation.

Do not use:

* `strtod`;
* `atof`;
* `sscanf`;
* a second decimal parsing library.

#### 6.7 JSON output construction

Use:

```c
JsonString
jsonStringInit()
jsonAppendChar()
jsonPrintf()
jsonReturnString()
sqlite3_result_subtype()
```

`JsonString` already provides:

* inline initial storage;
* SQLite-managed dynamic growth;
* OOM propagation;
* output length handling;
* result ownership transfer.

The existing `jsonArrayFunc()` demonstrates the required construction and subtype sequence:

```c
jsonStringInit(&jx, ctx);
jsonAppendChar(&jx, '[');
/* append values */
jsonAppendChar(&jx, ']');
jsonReturnString(&jx, 0, 0);
sqlite3_result_subtype(ctx, JSON_SUBTYPE);
```

Do not create a separate JSON string builder.

---

### 7. Original helper code required

The following functionality is not directly exposed in a suitable form by `json.c` or FP16 and must be implemented privately.

#### 7.1 Exact format parser

Required as described in Section 5.

#### 7.2 JSONB integer-to-C helper

Create a helper conceptually equivalent to:

```c
static int pblobJsonbInteger(
  sqlite3_context *ctx,
  JsonParse *pParse,
  u32 iNode,
  sqlite3_int64 *pValue
);
```

Responsibilities:

* validate node payload;
* handle an optional leading minus sign;
* copy payload to NUL-terminated SQLite memory;
* invoke `sqlite3DecOrHexToI64()`;
* distinguish malformed syntax, representable signed integer, and out-of-range integer;
* return the result through `pValue`;
* report OOM through `ctx`.

For `int8`, values outside signed 64-bit range are necessarily outside `int8` range and must become a range error.

The helper does not need to reproduce `jsonReturnFromBlob()` behavior that converts an oversized positive hexadecimal integer to `double`, because `int8` requires a representable signed integer.

#### 7.3 JSONB number-to-double helper

Create a helper conceptually equivalent to:

```c
static int pblobJsonbNumber(
  sqlite3_context *ctx,
  JsonParse *pParse,
  u32 iNode,
  double *pValue
);
```

It accepts:

```text
JSONB_INT
JSONB_INT5
JSONB_FLOAT
JSONB_FLOAT5
```

For canonical decimal integer and floating payloads, use `sqlite3AtoF()`.

For `JSONB_INT5`, preserve SQLite JSON5 hexadecimal semantics. The preferred implementation is to adapt the `JSONB_INT5` path from `jsonReturnFromBlob()`:

1. Parse with `sqlite3DecOrHexToI64()`.
2. If representable as signed integer, convert to `double`.
3. Handle negative `SMALLEST_INT64`.
4. Handle a 16-digit positive hexadecimal value whose high bit is set as unsigned before conversion to `double`.
5. Treat malformed or larger unsupported payloads as malformed JSON.

Do not silently reinterpret malformed payloads.

#### 7.4 Endian readers and writers

Implement explicit byte helpers:

```c
static void pblobPutU16Le(u8 *p, uint16_t v);
static void pblobPutU16Be(u8 *p, uint16_t v);
static uint16_t pblobGetU16Le(const u8 *p);
static uint16_t pblobGetU16Be(const u8 *p);

static void pblobPutU32Le(u8 *p, uint32_t v);
static void pblobPutU32Be(u8 *p, uint32_t v);
static uint32_t pblobGetU32Le(const u8 *p);
static uint32_t pblobGetU32Be(const u8 *p);
```

Implement only with unsigned shifts, masks, and byte assignments.

Do not use:

* unaligned integer pointer casts;
* host-endian `memcpy` directly to the output;
* `htons`, `ntohs`, `htonl`, or `ntohl`;
* platform-specific byte-swap APIs;
* a third-party endian library.

#### 7.5 Signed-byte conversion

Packing:

```c
pOut[i] = (u8)(value & 0xff);
```

is permitted only after explicit validation that:

```text
-128 <= value <= 127
```

Unpacking must not depend on whether plain `char` is signed:

```c
int value = byte < 0x80 ? (int)byte : (int)byte - 0x100;
```

#### 7.6 Binary32 bitcasts

Use the FP16 module’s existing bitcast helpers:

```c
fp32_to_bits(float)
fp32_from_bits(uint32_t)
```

The uploaded bitcast header supplies compiler-specific implementations where available and a union-based fallback.

Do not write another float/word aliasing helper.

#### 7.7 Finite-value checks

Use SQLite’s existing internal NaN helper where useful:

```c
sqlite3IsNaN()
```

For complete binary32 finite classification, bit inspection is preferred:

```c
(uBits & UINT32_C(0x7f800000)) != UINT32_C(0x7f800000)
```

For binary16:

```c
(uBits & UINT16_C(0x7c00)) != UINT16_C(0x7c00)
```

This cleanly identifies both infinity and NaN without depending on `<math.h>` classification behavior.

---

### 8. Numeric semantics

#### 8.1 Target type controls conversion

The target `format` determines allowed values and conversion behavior.

The source JSON array does not need to preserve one lexical numeric subtype for floating formats.

Thus:

```json
[1, 2.0, 3e0]
```

is accepted for `f2` and `f4`.

For `int8`, every element must be an integer JSONB node:

```text
JSONB_INT or JSONB_INT5
```

A floating node such as `2.0` is rejected even if mathematically integral.

#### 8.2 No clamping or wrapping

For all formats:

* do not clamp out-of-range values;
* do not wrap modulo the target width;
* do not reinterpret overflow as another finite value.

#### 8.3 Floating conversion path

Packing to binary32:

```text
JSON numeric payload
-> SQLite double via sqlite3AtoF()/integer adaptation
-> C float conversion
-> fp32_to_bits()
-> explicit endian write
```

Packing to binary16:

```text
JSON numeric payload
-> SQLite double
-> C float conversion
-> fp16_ieee_from_fp32_value()
-> explicit endian write
```

This intentionally defines `f2` conversion through binary32.

The extension does not promise directly rounded decimal/binary64-to-binary16 conversion.

This path is appropriate for embeddings, which conventionally originate as binary32 vectors.

Unpacking binary16:

```text
explicit endian read
-> uint16_t binary16 bits
-> fp16_ieee_to_fp32_value()
-> float
-> exact promotion to double
-> SQLite JSON numeric formatting
```

Unpacking binary32:

```text
explicit endian read
-> uint32_t binary32 bits
-> fp32_from_bits()
-> float
-> exact promotion to double
-> SQLite JSON numeric formatting
```

#### 8.4 Rounding mode

The portable FP16 implementation states that its non-native conversion path does not assume a particular rounding mode. Native conversion paths may use current-direction hardware operations depending on compiler and architecture settings.

To ensure deterministic cross-build behavior, the packed-blob build should force:

```c
#define FP16_USE_NATIVE_CONVERSION 0
```

before including the FP16 implementation unless the project explicitly decides to permit hardware-dependent conversion behavior.

This is the recommended design.

Do not change the process-global floating-point rounding mode inside an SQL function.

#### 8.5 Overflow policy

A finite source JSON number that becomes infinity when narrowed to binary32 or binary16 must be rejected.

##### Binary32 packing

After:

```c
float f = (float)d;
uint32_t bits = fp32_to_bits(f);
```

if the exponent field is all ones, reject the value.

This rejects:

* overflow to positive infinity;
* overflow to negative infinity;
* any NaN, although valid text JSON should not produce NaN.

##### Binary16 packing

After:

```c
uint16_t bits = fp16_ieee_from_fp32_value(f);
```

if the binary16 exponent field is all ones, reject the value.

This rejects:

* binary16 overflow to infinity;
* NaN.

Normal underflow to a subnormal value or signed zero is accepted.

#### 8.6 Non-finite JSON5 input

SQLite accepts JSON5 infinity spellings and internally converts them to large floating literals such as `9e999`. SQLite maps JSON5 NaN spellings to JSON null in the parser.

Consequences:

* JSON5 infinity ultimately parses to a non-finite `double` or overflows when narrowed and must be rejected by the finite-value checks.
* JSON5 NaN becomes `JSONB_NULL` and must be rejected as a non-numeric element.
* No packed NaN or infinity can be produced by `pblob_pack()`.

#### 8.7 Non-finite packed input

A raw BLOB passed to `pblob_unpack()` may contain binary16 or binary32:

* positive infinity;
* negative infinity;
* quiet NaN;
* signaling NaN.

These values cannot be emitted as valid JSON numbers.

`pblob_unpack()` must reject the first non-finite element and return an SQL error.

Do not emit:

```json
NaN
Infinity
-Infinity
```

Do not convert them to:

* `null`;
* strings;
* zero;
* maximum finite values.

#### 8.8 Signed zero

Preserve signed zero in packed floating-point data.

Packing:

* JSON `-0.0` should produce a negative-zero binary16 or binary32 bit pattern.
* JSON integer `0` produces positive zero when converted to a floating format.

Unpacking:

* positive zero should be rendered as a floating JSON number;
* negative zero should retain its sign.

The JSON renderer must not intentionally normalize negative zero to positive zero.

---

### 9. Memory and size rules

#### 9.1 Exact allocation for `pblob_pack`

After parsing and root-array validation:

1. Count elements with:

   ```c
   jsonbArrayCount(pParse, 0)
   ```
2. Compute:

   ```text
   output_size = element_count * format.nByte
   ```
3. Detect integer multiplication overflow before allocation.
4. Verify the output size does not exceed:

   ```c
   db->aLimit[SQLITE_LIMIT_LENGTH]
   ```

   or use the corresponding stable internal limit access used elsewhere in the selected SQLite tree.
5. Allocate once with:

   ```c
   sqlite3_malloc64(output_size)
   ```
6. Return the allocation with:

   ```c
   sqlite3_result_blob64(ctx, pOut, output_size, sqlite3_free)
   ```

Use an allocation compatible with the destructor passed to `sqlite3_result_blob64()`.

Do not allocate one object per element.

For a zero-element array, return a zero-length BLOB without treating a zero-byte allocation returning `NULL` as OOM.

#### 9.2 `pblob_unpack` output allocation

Use `JsonString`.

Do not precompute an exact JSON text size.

`JsonString` handles incremental growth and reports OOM through `ctx`.

#### 9.3 Temporary numeric buffers

JSONB numeric payloads are not guaranteed to have a trailing NUL.

When a SQLite numeric parser requires NUL-terminated input, use:

```c
sqlite3DbStrNDup()
sqlite3DbFree()
```

as `jsonReturnFromBlob()` does.

No temporary buffer should survive one element conversion.

#### 9.4 Cleanup discipline

Every exit path must correctly release:

* `JsonParse` using `jsonParseFree()`;
* packed output memory using `sqlite3_free()` if ownership has not been transferred;
* temporary numeric strings using `sqlite3DbFree()`;
* `JsonString` indirectly through `jsonReturnString()` or explicitly through `jsonStringReset()` if returning before finalization.

Use one cleanup section per SQL callback where practical.

---

### 10. `pblob_pack()` common workflow

#### 10.1 Logical algorithm

##### Step 1: Handle NULL

If either argument is SQL NULL:

```c
sqlite3_result_null(ctx);
return;
```

Calls used:

```c
sqlite3_value_type()
sqlite3_result_null()
```

Code source: original extension callback logic.

##### Step 2: Validate argument storage classes

Require:

```text
argv[0] -> SQLITE_TEXT
argv[1] -> SQLITE_TEXT
```

If argument 1 is BLOB, reject it even when valid JSONB.

Calls used:

```c
sqlite3_value_type()
sqlite3_result_error()
```

Code source: original extension logic.

##### Step 3: Parse format

Invoke the original private format parser.

Calls used:

```c
sqlite3_value_text()
sqlite3_value_bytes()
memcmp()
```

Code source: original.

##### Step 4: Parse and validate JSON text

Call:

```c
pParse = jsonParseFuncArg(ctx, argv[0], 0);
```

If it returns `NULL`, return immediately. It has either:

* propagated NULL, although NULL was already handled;
* reported malformed JSON;
* reported OOM.

Because the callback has already required `SQLITE_TEXT`, the JSONB compatibility path is not used.

Calls used:

```c
jsonParseFuncArg()
```

Code source: `json.c`.

##### Step 5: Require a root array

Inspect:

```c
pParse->aBlob[0] & 0x0f
```

Require:

```c
JSONB_ARRAY
```

Otherwise report:

```text
pblob_pack: expected a JSON array
```

Calls used:

* direct `JsonParse` access;
* `sqlite3_result_error()`.

Code source: original validation using `json.c` constants.

##### Step 6: Count elements and allocate exact output

Call:

```c
nElem = jsonbArrayCount(pParse, 0);
```

Perform checked multiplication by `format.nByte`.

Allocate the exact BLOB buffer.

Calls used:

```c
jsonbArrayCount()
sqlite3_malloc64()
sqlite3_result_error_nomem()
```

Code source:

* count: `json.c`;
* checked multiplication and allocation: original.

##### Step 7: Locate array payload

Call:

```c
nRootHeader = jsonbPayloadSize(pParse, 0, &nRootPayload);
```

Set:

```text
iNode = nRootHeader
iEnd  = nRootHeader + nRootPayload
```

Require:

```text
nRootHeader != 0
iEnd == pParse->nBlob
```

A failure is an internal malformed-JSON condition.

Calls used:

```c
jsonbPayloadSize()
```

Code source: `json.c`.

##### Step 8: Traverse elements

For element index `iElem` from zero while `iNode < iEnd`:

1. Call:

   ```c
   nHeader = jsonbPayloadSize(pParse, iNode, &nPayload);
   ```
2. Require nonzero header and:

   ```text
   iNode + nHeader + nPayload <= iEnd
   ```
3. Inspect node type:

   ```c
   pParse->aBlob[iNode] & 0x0f
   ```
4. Dispatch to the selected target-format workflow.
5. Advance:

   ```text
   iNode += nHeader + nPayload
   ```

At completion require:

```text
iNode == iEnd
iElem == nElem
```

Calls used:

```c
jsonbPayloadSize()
```

Code source:

* node traversal primitive: `json.c`;
* loop and validation: original.

##### Step 9: Return BLOB

Call:

```c
sqlite3_result_blob64(ctx, pOut, nOut, sqlite3_free);
```

After ownership transfer, set the local pointer to `NULL`.

Calls used:

```c
sqlite3_result_blob64()
```

Code source: original.

##### Step 10: Cleanup

Call:

```c
jsonParseFree(pParse);
```

Free untransferred output memory.

Calls used:

```c
jsonParseFree()
sqlite3_free()
```

---

### 11. `pblob_pack()` workflow: `int8`

For each JSON array element:

##### Step 1: Validate JSONB node type

Accept only:

```c
JSONB_INT
JSONB_INT5
```

Reject:

```text
JSONB_FLOAT
JSONB_FLOAT5
JSONB_NULL
JSONB_TRUE
JSONB_FALSE
all string types
JSONB_ARRAY
JSONB_OBJECT
```

Error should identify the zero-based element index.

Calls used:

* direct node-type inspection;
* `sqlite3_result_error()` or `sqlite3_mprintf()` plus result error.

Code source: original.

##### Step 2: Parse integer

Invoke the original private helper adapted from `jsonReturnFromBlob()`.

Inside the helper:

1. Use `jsonbPayloadSize()` or the caller-supplied header/payload sizes.
2. Copy the numeric payload with:

   ```c
   sqlite3DbStrNDup()
   ```
3. Parse with:

   ```c
   sqlite3DecOrHexToI64()
   ```
4. Free with:

   ```c
   sqlite3DbFree()
   ```

Calls used:

```c
sqlite3DbStrNDup()
sqlite3DecOrHexToI64()
sqlite3DbFree()
```

Code source:

* core conversion: `json.c`/SQLite core;
* result-returning logic adapted into a value-returning private helper.

##### Step 3: Validate range

Require:

```text
-128 <= value <= 127
```

No clamping or wrapping.

Code source: original.

##### Step 4: Encode byte

Store the low eight bits only after successful range validation.

Code source: original.

---

### 12. `pblob_pack()` workflow: `<f4` and `>f4`

For each JSON array element:

##### Step 1: Validate JSONB node type

Accept:

```c
JSONB_INT
JSONB_INT5
JSONB_FLOAT
JSONB_FLOAT5
```

Reject all other node types.

Code source: original dispatch using `json.c` constants.

##### Step 2: Parse to double

Invoke the private `pblobJsonbNumber()` helper.

Calls used:

```c
sqlite3AtoF()
sqlite3DecOrHexToI64()
sqlite3DbStrNDup()
sqlite3DbFree()
```

Code source:

* numeric parsers: SQLite core;
* glue helper: adapted/original.

##### Step 3: Reject non-finite double

If the parsed value is non-finite, reject it.

Use:

```c
sqlite3IsNaN(d)
```

and an infinity check through magnitude/bit classification as appropriate.

Code source:

* NaN helper: SQLite core;
* complete finite check: original.

##### Step 4: Narrow to binary32

Perform:

```c
float f = (float)d;
```

Code source: C conversion.

##### Step 5: Obtain bits

Call:

```c
uint32_t bits = fp32_to_bits(f);
```

Call source: FP16 bitcast module.

##### Step 6: Reject binary32 non-finite result

Check the exponent field.

If all exponent bits are one, reject as target overflow or non-finite conversion.

Code source: original bit classification.

##### Step 7: Write requested byte order

For `<f4`, call the original:

```c
pblobPutU32Le()
```

For `>f4`, call:

```c
pblobPutU32Be()
```

Code source: original endian helpers.

---

### 13. `pblob_pack()` workflow: `<f2` and `>f2`

For each JSON array element:

##### Step 1: Validate JSONB node type

Accept the same numeric JSONB types as `f4`.

Code source: original dispatch.

##### Step 2: Parse to double

Use the same private `pblobJsonbNumber()` helper.

Call sources: SQLite core and adapted `json.c` logic.

##### Step 3: Reject non-finite double

As in `f4`.

##### Step 4: Narrow to binary32

Perform:

```c
float f = (float)d;
```

##### Step 5: Reject binary32 non-finite intermediate

Obtain binary32 bits using:

```c
fp32_to_bits(f)
```

Reject an all-ones binary32 exponent.

This distinguishes source-to-binary32 overflow before binary16 conversion.

Call source: FP16 bitcast module.

##### Step 6: Convert binary32 to IEEE binary16

Call:

```c
uint16_t bits = fp16_ieee_from_fp32_value(f);
```

Call source: FP16 module. The uploaded implementation returns the IEEE binary16 bit representation.

##### Step 7: Reject binary16 non-finite result

Check:

```c
(bits & UINT16_C(0x7c00)) == UINT16_C(0x7c00)
```

If true, reject as binary16 overflow or non-finite conversion.

Code source: original classification.

##### Step 8: Write requested byte order

For `<f2`, use:

```c
pblobPutU16Le()
```

For `>f2`, use:

```c
pblobPutU16Be()
```

Code source: original endian helpers.

---

### 14. `pblob_unpack()` common workflow

#### 14.1 Logical algorithm

##### Step 1: Handle NULL

If either argument is SQL NULL, return SQL NULL.

Calls used:

```c
sqlite3_value_type()
sqlite3_result_null()
```

##### Step 2: Validate argument storage classes

Require:

```text
argv[0] -> SQLITE_BLOB
argv[1] -> SQLITE_TEXT
```

Do not coerce TEXT to BLOB.

Calls used:

```c
sqlite3_value_type()
sqlite3_result_error()
```

##### Step 3: Parse format

Use the same private exact format parser.

##### Step 4: Read BLOB

Obtain:

```c
sqlite3_value_blob(argv[0])
sqlite3_value_bytes(argv[0])
```

A zero-byte BLOB is valid even if the returned data pointer is `NULL`.

##### Step 5: Validate length

Require:

```text
blob_length % format.nByte == 0
```

For `int8`, every nonnegative BLOB length is structurally valid.

Compute:

```text
element_count = blob_length / format.nByte
```

Code source: original.

##### Step 6: Initialize JSON writer

Call:

```c
JsonString out;
jsonStringInit(&out, ctx);
jsonAppendChar(&out, '[');
```

Call source: `json.c`.

##### Step 7: Decode and append every element

For each element:

1. If not the first element, append `','` using:

   ```c
   jsonAppendChar()
   ```

   Alternatively use `jsonAppendSeparator()`.
2. Dispatch to the selected unpack workflow.
3. Append one JSON number using `jsonPrintf()`.

Call source:

* JSON output operations: `json.c`;
* decode operations: FP16/original.

##### Step 8: Close and return array

Call:

```c
jsonAppendChar(&out, ']');
jsonReturnString(&out, 0, 0);
sqlite3_result_subtype(ctx, JSON_SUBTYPE);
```

Call source: `json.c`.

If an error is detected after `JsonString` initialization but before normal finalization:

1. reset the writer with:

   ```c
   jsonStringReset()
   ```
2. set the SQL error;
3. return.

---

### 15. `pblob_unpack()` workflow: `int8`

For each byte:

##### Step 1: Read unsigned byte

```c
u8 b = pBlob[i];
```

##### Step 2: Decode signed value explicitly

```text
b < 128 -> b
otherwise -> b - 256
```

Do not cast through plain `char`.

Code source: original.

##### Step 3: Append JSON integer

Use:

```c
jsonPrintf(16, &out, "%d", value);
```

or another bounded SQLite formatter invocation sufficient for `-128` through `127`.

Call source: `json.c` formatter.

The output must use integer syntax, with no decimal point.

---

### 16. `pblob_unpack()` workflow: `<f4` and `>f4`

For each four-byte element:

##### Step 1: Read word

Use:

```c
pblobGetU32Le()
```

or:

```c
pblobGetU32Be()
```

Code source: original.

##### Step 2: Reject non-finite bit patterns

Before converting to a C float, inspect the exponent field.

If all exponent bits are one, report an error identifying the element index and whether practical classify it as infinity or NaN from the fraction field.

Code source: original.

##### Step 3: Convert bits to binary32 value

Call:

```c
float f = fp32_from_bits(bits);
```

Call source: FP16 bitcast module.

##### Step 4: Promote exactly to double

```c
double d = (double)f;
```

Every binary32 finite value is exactly representable as binary64.

##### Step 5: Append JSON real

Use SQLite’s formatter through:

```c
jsonPrintf(100, &out, "%!0.17g", d);
```

This follows the real-value formatting pattern used by `jsonAppendSqlValue()`.

The formatter may emit more digits than the shortest binary32-specific representation. Correct round-trip representation is more important than minimal textual length in version 1.

To preserve floating type visually, verify the selected SQLite alternate-form formatter produces a decimal point for whole-valued reals as it does in existing JSON output. Do not add a second floating formatter unless actual behavior proves insufficient.

Calls used:

```c
jsonPrintf()
```

Call source: `json.c`.

---

### 17. `pblob_unpack()` workflow: `<f2` and `>f2`

For each two-byte element:

##### Step 1: Read word

Use:

```c
pblobGetU16Le()
```

or:

```c
pblobGetU16Be()
```

Code source: original.

##### Step 2: Reject non-finite bit patterns

Check the binary16 exponent field.

If all exponent bits are one, return an error.

Code source: original.

##### Step 3: Convert binary16 to binary32

Call:

```c
float f = fp16_ieee_to_fp32_value(bits);
```

Call source: FP16 module. The function handles IEEE binary16 normal numbers, subnormals, signed zero, infinities, and NaNs; this extension rejects the last two before conversion.

##### Step 4: Promote exactly to double

```c
double d = (double)f;
```

##### Step 5: Append JSON real

Use:

```c
jsonPrintf(100, &out, "%!0.17g", d);
```

Call source: `json.c`.

---

### 18. Empty-input workflows

#### 18.1 Empty JSON array to BLOB

Input:

```sql
pblob_pack('[]', format)
```

Algorithm:

1. `jsonParseFuncArg()` creates a valid root `JSONB_ARRAY`.
2. `jsonbArrayCount()` returns zero.
3. Checked output size is zero.
4. No element loop executes.
5. Return a zero-length BLOB.

Result:

```sql
x''
```

#### 18.2 Empty BLOB to JSON

Input:

```sql
pblob_unpack(x'', format)
```

Algorithm:

1. BLOB length zero is divisible by every element size.
2. Element count is zero.
3. Initialize `JsonString`.
4. Append `'['`.
5. Skip element loop.
6. Append `']'`.
7. Return JSON-subtyped text.

Result:

```json
[]
```

---

### 19. Error behavior

Errors must be deterministic and identify the SQL function.

Recommended messages:

#### Argument type

```text
pblob_pack: first argument must be JSON text
pblob_pack: format must be text
pblob_unpack: first argument must be a BLOB
pblob_unpack: format must be text
```

#### Format

```text
pblob_pack: unsupported format "<value>"
pblob_unpack: unsupported format "<value>"
```

For embedded NUL or unprintable bytes, a generic unsupported-format message is acceptable rather than interpolating unsafe text.

#### JSON root

```text
pblob_pack: expected a JSON array
```

#### Element type

```text
pblob_pack: element 4 must be an integer for format int8
pblob_pack: element 4 is not numeric
```

Indexes are zero-based.

#### Range and non-finite values

```text
pblob_pack: element 4 is outside the int8 range
pblob_pack: element 4 is outside the finite f2 range
pblob_pack: element 4 is outside the finite f4 range
pblob_unpack: element 4 is non-finite and cannot be represented in JSON
```

#### BLOB length

```text
pblob_unpack: BLOB length 5 is not divisible by element size 2 for format <f2
```

#### Malformed internal JSONB

Although text input is fully parsed before traversal, defensive failures should report:

```text
pblob_pack: malformed internal JSON representation
```

Do not continue after `jsonbPayloadSize()` returns zero or an element crosses its array payload boundary.

#### OOM

Use:

```c
sqlite3_result_error_nomem(ctx)
```

Do not replace OOM with a generic conversion error.

---

### 20. Function-local design

Recommended private callbacks:

```c
static void pblobPackFunc(
  sqlite3_context *ctx,
  int argc,
  sqlite3_value **argv
);

static void pblobUnpackFunc(
  sqlite3_context *ctx,
  int argc,
  sqlite3_value **argv
);
```

Recommended private helpers:

```c
static int pblobParseFormat(
  sqlite3_context *ctx,
  sqlite3_value *pArg,
  const char *zFunc,
  PblobFormat *pFormat
);

static int pblobJsonbInteger(
  sqlite3_context *ctx,
  JsonParse *pParse,
  u32 iNode,
  sqlite3_int64 *pValue
);

static int pblobJsonbNumber(
  sqlite3_context *ctx,
  JsonParse *pParse,
  u32 iNode,
  double *pValue
);

static void pblobPutU16Le(u8*, uint16_t);
static void pblobPutU16Be(u8*, uint16_t);
static uint16_t pblobGetU16Le(const u8*);
static uint16_t pblobGetU16Be(const u8*);

static void pblobPutU32Le(u8*, uint32_t);
static void pblobPutU32Be(u8*, uint32_t);
static uint32_t pblobGetU32Le(const u8*);
static uint32_t pblobGetU32Be(const u8*);
```

All helpers should be `static`.

The initializer may be non-static only if required by its location relative to the auto-extension dispatcher.

---

### 21. Registration design

Register exactly two two-argument scalar functions:

```text
pblob_pack
pblob_unpack
```

Do not register aliases.

Do not register:

* `pblob_count`;
* `pblob_valid`;
* `pblob_get`;
* format-specific convenience functions;
* C-callable conversion entry points.

Conceptual registration:

```c
sqlite3_create_function_v2(
  db,
  "pblob_pack",
  2,
  flags,
  0,
  pblobPackFunc,
  0,
  0,
  0
);

sqlite3_create_function_v2(
  db,
  "pblob_unpack",
  2,
  flags,
  0,
  pblobUnpackFunc,
  0,
  0,
  0
);
```

Return the first non-`SQLITE_OK` registration result.

If the second registration fails after the first succeeds, return the failure code. SQLite connection teardown will reclaim the first registration.

---

### 22. Portability requirements

The implementation targets platforms on which:

```text
CHAR_BIT == 8
sizeof(float) == 4
FLT_RADIX == 2
FLT_MANT_DIG == 24
FLT_MAX_EXP == 128
sizeof(uint16_t) == 2
sizeof(uint32_t) == 4
```

Add compile-time assertions or preprocessor checks.

The code must not depend on:

* host byte order;
* unaligned access support;
* plain `char` signedness;
* strict-aliasing violations;
* locale decimal separators;
* platform `long` width;
* native `_Float16`;
* native half conversion instructions.

Use the FP16 portable path by default.

---

### 23. Explicit non-goals

Version 1 must not implement:

* unsigned integer formats;
* signed integers other than `int8`;
* binary64;
* bfloat16;
* native-endian formats;
* multidimensional arrays;
* shape metadata;
* quantization scale or zero-point storage;
* compression;
* slicing;
* random element access;
* vector arithmetic;
* conversion directly between packed formats;
* automatic format inference;
* mixed packed types;
* JSON objects containing metadata;
* caller-supplied JSONB input;
* NaN or infinity substitution policies;
* public C APIs.

---

### 24. Coding priorities

The coding agent must optimize for these priorities, in order:

1. Correctness of packed bit patterns.
2. Complete and deterministic validation.
3. Reuse of existing SQLite and FP16 conversion machinery.
4. Minimal new conversion code.
5. Host-endian and alignment independence.
6. Proper SQLite memory ownership and OOM behavior.
7. Clear, stable SQL error messages.
8. Efficient single-allocation packing and linear traversal.
9. Readability and auditability.
10. Professional code documentation (docstrings/comments).
11. Micro-optimization only after the preceding requirements are satisfied.

The implementation must not duplicate substantial parts of the JSON parser, JSON writer, decimal parser, or FP16 converter.

---

The section is directionally correct, but it should state why a header is unnecessary and how third-party FP16 code is integrated. It should also clarify that `pblob.c` is an amalgamation source fragment, not an independently compilable public module.

### 25. Code Module

Implement the extension in a single source module:

```text
pblob.c
```

Do not create a corresponding public or private `pblob.h` header.

A separate header is unnecessary because:

* the extension exposes no public C API;
* all implementation types, constants, SQL callbacks, and conversion helpers are private to `pblob.c`;
* all such definitions should be declared `static` where possible;
* the only externally referenced symbol is the internal initialization function used by the project’s auto-extension dispatcher;
* `pblob.c` is compiled as part of the SQLite amalgamation and may directly use private `json.c` definitions that appear earlier in the same translation unit.

The module should contain:

1. The packed-format enums and descriptor structure.
2. Exact format-string parsing.
3. Endian-independent 16-bit and 32-bit read/write helpers.
4. JSONB numeric extraction helpers adapted from `json.c`.
5. `int8` packing and unpacking logic.
6. IEEE binary16 packing and unpacking through the vendored FP16 implementation.
7. IEEE binary32 packing and unpacking through the FP16 bitcast helpers and ordinary C floating-point conversion.
8. The `pblob_pack()` SQL callback.
9. The `pblob_unpack()` SQL callback.
10. The internal SQL-function registration initializer.

The vendored FP16 headers may remain separate source-tree dependencies during development, or their required contents may be expanded into `pblob.c` by the project’s source-bundling stage. In either case, they do not constitute a `pblob` public API and do not require a `pblob.h` file.

The module must be positioned after `json.c` in the generated amalgamation so that the required private JSON structures, constants, and `static` helper functions are visible in the same translation unit.

The auto-extension dispatcher may reference the initializer through a forward declaration local to the dispatcher or through amalgamation source ordering. Do not introduce a dedicated header solely for that declaration.

---
---


## 📗 SQLite Packed Numeric BLOB Extension Specification - Part 2: Testing Strategy and Implementation

> [!NOTE] Prompt
> 
> Proceed to Part 2 focused on testing strategy and implementation. Make sure to include a dedicated section providing instructions on how test builds are built and testing executed. Include a comprehensive enumeration of test modules and test cases.

### 1. Purpose

This part defines the complete testing strategy for the packed numeric BLOB extension specified in Part 1.

The extension exposes only:

```sql
pblob_pack(json_array, format) -> BLOB
pblob_unpack(blob, format) -> JSON text
```

The production implementation is contained in:

```text
pblob.c
```

The testing system must verify:

1. The public SQL contract.
2. Exact packed byte representations.
3. Correct JSON parsing and validation behavior.
4. Correct `int8` range and signed-byte behavior.
5. Correct IEEE 754 binary16 conversion.
6. Correct IEEE 754 binary32 conversion.
7. Correct little-endian and big-endian encoding.
8. Correct handling of subnormal values, signed zero, overflow, infinity, and NaN.
9. Proper SQLite result types and JSON subtype behavior.
10. Proper memory ownership, SQLite limits, allocation failures, and cleanup.
11. Correct operation when compiled into the complete SQLite amalgamation.
12. Absence of test-only code and symbols in normal production builds.

Tests must not rely exclusively on pack/unpack round trips. An incorrect encoder and incorrect decoder can agree with each other. Exact output bytes and independent reference values are mandatory.

---

### 2. Testing layers

Use four complementary testing layers.

#### 2.1 SQL black-box tests

These tests exercise the extension exclusively through the registered SQL functions.

They define the public behavior of:

```sql
pblob_pack()
pblob_unpack()
```

They verify:

* SQL argument handling;
* format parsing;
* JSON input validation;
* exact BLOB bytes;
* output JSON text;
* SQLite storage classes;
* JSON result subtype behavior;
* error messages;
* edge cases;
* integration with ordinary SQL expressions.

These tests are the authoritative public-contract tests.

#### 2.2 Test-only C helper functions

Certain low-level properties are impractical or inefficient to test entirely through SQL.

Test-only C code must directly exercise private implementation details such as:

* endian readers and writers;
* exhaustive binary16 decoding;
* exhaustive binary16 finite round trips;
* exact bit classification;
* selected binary32-to-binary16 rounding boundaries;
* signed-byte decoding;
* checked-size calculations.

This code is compiled only when:

```c
SQLITE_TEST
```

is defined.

It must not create a production C API.

#### 2.3 Differential reference-vector tests

Use independently generated expected results.

Reference vectors must be generated outside the extension implementation, using one or more independent implementations such as:

* NumPy for `int8`, `float16`, and `float32`;
* Python `struct` for IEEE binary32;
* a separate trusted IEEE binary16 implementation;
* fixed IEEE 754 values derived from the standard.

Generated vectors are committed as static test data.

The normal test run must not require Python, NumPy, network access, or any external package.

#### 2.4 SQLite fault-injection and limit tests

When built through SQLite’s test harness, verify:

* simulated allocation failures;
* SQLite length limits;
* cleanup after errors;
* no leaks;
* no use-after-free;
* no double-free;
* correct result after repeated calls and prepared-statement reuse.

---

### 3. Test code organization

Recommended modules:

```text
pblob.c
src/test_pblob.c
test/pblob.test
test/pblob_vectors.tcl
test/pblob_limits.test
test/pblob_fault.test
tool/gen_pblob_vectors.py
```

If the project keeps extension-specific tests near the extension source, equivalent paths are acceptable, but responsibilities must remain separated.

#### 3.1 `pblob.c`

Production extension implementation.

Under:

```c
#ifdef SQLITE_TEST
```

it may expose narrowly scoped test wrappers for otherwise private helpers, but it should not contain the full Tcl command registration implementation unless that is the established project convention.

No test code may alter production behavior.

#### 3.2 `src/test_pblob.c`

Test-only C module linked into `testfixture`.

Responsibilities:

* register Tcl test commands;
* call private or test-visible packed-blob helpers;
* run exhaustive low-level loops efficiently;
* report structured pass/fail information to Tcl;
* avoid duplicating the production conversion implementation.

This module must be excluded from normal `sqlite3.c`, `sqlite3.dll`, and `sqlite3.exe` builds unless those builds explicitly include test support.

#### 3.3 `test/pblob.test`

Primary SQL black-box test suite.

Responsibilities:

* API contract;
* exact bytes;
* valid conversions;
* invalid argument handling;
* malformed JSON;
* scalar-type rules;
* format handling;
* empty input;
* NULL propagation;
* non-finite packed values;
* output storage class and JSON validity.

#### 3.4 `test/pblob_vectors.tcl`

Static committed reference vectors.

Responsibilities:

* large set of exact input/output mappings;
* values generated independently of the extension;
* both endian variants;
* binary16 and binary32 edge cases;
* selected randomized finite values.

This file should contain data, not generator logic.

#### 3.5 `test/pblob_limits.test`

SQLite limits and large-input tests.

Responsibilities:

* output-length limit;
* large arrays;
* large BLOBs;
* checked multiplication;
* behavior near configured SQLite limits.

#### 3.6 `test/pblob_fault.test`

Allocation-failure and cleanup tests.

Responsibilities:

* OOM during JSON parsing;
* OOM during packed BLOB allocation;
* OOM during temporary numeric payload duplication;
* OOM during `JsonString` growth;
* repeated failure and recovery.

#### 3.7 `tool/gen_pblob_vectors.py`

Developer-only reference-vector generator.

Responsibilities:

* produce deterministic expected vectors;
* use an independent implementation;
* write stable Tcl data;
* include generator metadata and library versions in comments;
* never run as part of the standard test suite.

---

### 4. Test-only visibility design

The production helpers in `pblob.c` should remain `static`.

For test builds, expose only narrow wrappers.

One acceptable pattern is:

```c
#ifdef SQLITE_TEST
int sqlite3PblobTestPutGet16(...);
int sqlite3PblobTestPutGet32(...);
int sqlite3PblobTestF16Exhaustive(...);
int sqlite3PblobTestF16EncodeCase(...);
#endif
```

These wrappers are not public APIs. They exist only in test builds.

Another acceptable pattern, when source ordering permits, is to concatenate `src/test_pblob.c` after `pblob.c` in the test amalgamation so that test code can call earlier `static` functions from the same translation unit.

Preferred rule:

* Keep production helpers `static`.
* Avoid removing `static` merely to make testing easier.
* Avoid installing a `pblob.h`.
* Avoid exposing generic conversion entry points in production.

---

### 5. Test build configuration

#### 5.1 Required build variants

At minimum, run the suite against these variants.

##### Variant A: SQLite test build

Required defines:

```text
SQLITE_TEST
JSON enabled
packed-blob extension enabled
```

Recommended additional defines:

```text
SQLITE_DEBUG
SQLITE_ENABLE_API_ARMOR
```

This variant builds `testfixture` and runs all Tcl tests.

##### Variant B: release-style amalgamation build

Build the same amalgamation without:

```text
SQLITE_TEST
SQLITE_DEBUG
```

Run a concise SQL smoke suite against the resulting shell or library.

This catches accidental dependencies on test-only symbols or debug behavior.

##### Variant C: sanitizer or memory-check build

On a compiler/toolchain that supports it, build with:

```text
AddressSanitizer
UndefinedBehaviorSanitizer
```

or the platform’s equivalent runtime checks.

This variant is strongly recommended even when the primary supported production platform is Windows/MSVC.

##### Variant D: FP16 portable-path build

Force:

```c
FP16_USE_NATIVE_CONVERSION=0
```

This is the normative conversion build and must run the full suite.

If native conversion is ever enabled as an optional build mode, it must be tested separately and compared against the portable-path vectors.

#### 5.2 JSON requirement

The test build must not define:

```text
SQLITE_OMIT_JSON
```

The packed-blob functions should not be registered when JSON is omitted.

A separate compile-only configuration should verify that a JSON-omitted SQLite build still compiles cleanly and contains no unresolved packed-blob references.

---

### 6. Windows test build instructions

The primary Windows test executable is SQLite’s Tcl-enabled:

```text
testfixture.exe
```

The exact make target may differ according to the SQLite source snapshot and local makefile customization. The coding agent must inspect the project’s `Makefile.msc` and use its existing `testfixture` target rather than inventing a parallel build system.

A typical workflow is:

```bat
cd /d B:\path\to\sqlite-build
nmake /f B:\path\to\sqlite\Makefile.msc testfixture.exe
```

When the makefile expects execution from the source directory:

```bat
cd /d B:\path\to\sqlite
nmake /f Makefile.msc testfixture.exe
```

If the project builds from another directory using an overridden source root, preserve the project’s existing `TOP` or equivalent override:

```bat
nmake /f B:\path\to\sqlite\Makefile.msc TOP=B:\path\to\sqlite testfixture.exe
```

The exact command must follow the project’s current SQLite build convention.

Required build conditions:

1. `pblob.c` is present in the amalgamation source list after `json.c`.
2. `src/test_pblob.c` is present in the testfixture-only source list.
3. `SQLITE_TEST` is defined for `testfixture`.
4. The Tcl test harness can locate the source `test` directory.
5. The FP16 headers are available or already expanded by the project’s source bundler.
6. `FP16_USE_NATIVE_CONVERSION=0` is set for the normative test build.

#### 6.1 Building the SQLite shell for smoke tests

Build the project’s normal shell after the test build:

```bat
nmake /f Makefile.msc sqlite3.exe
```

or the equivalent custom target used by the project.

Verify that the shell contains the auto-extension without requiring `.load`.

#### 6.2 Clean rebuild requirement

At least one test cycle must begin from a clean build:

```bat
nmake /f Makefile.msc clean
nmake /f Makefile.msc testfixture.exe
```

or the project’s equivalent clean target.

This prevents stale amalgamation or object files from hiding missing source-list dependencies.

---

### 7. Executing tests

#### 7.1 Run the primary packed-blob suite

From a directory where the SQLite Tcl test harness can resolve its support files:

```bat
testfixture.exe test\pblob.test
```

If the harness expects the test script as an argument through `all.test` or another launcher, use the repository’s established form.

Equivalent common invocation:

```bat
testfixture.exe test\tester.tcl test\pblob.test
```

The agent must inspect existing project test invocations and follow them.

#### 7.2 Run limit and fault suites

```bat
testfixture.exe test\pblob_limits.test
testfixture.exe test\pblob_fault.test
```

#### 7.3 Run all packed-blob suites in one test script

A wrapper may source all modules:

```tcl
source [file join $testdir pblob.test]
source [file join $testdir pblob_limits.test]
source [file join $testdir pblob_fault.test]
```

The wrapper should be named:

```text
test/pblob_all.test
```

Then run:

```bat
testfixture.exe test\pblob_all.test
```

#### 7.4 Run full SQLite regression tests

After the focused suite passes, run the project’s normal SQLite regression target.

Examples, depending on the makefile:

```bat
nmake /f Makefile.msc test
```

or:

```bat
nmake /f Makefile.msc fulltest
```

or the project-specific equivalent.

The coding agent must not assume one target name without checking the selected SQLite source tree.

#### 7.5 Release-build smoke tests

Use the normal `sqlite3.exe`:

```bat
(
  echo SELECT hex(pblob_pack('[1,-2,127,-128]','int8'));
  echo SELECT pblob_unpack(x'01FE7F80','int8');
  echo SELECT hex(pblob_pack('[1.0,2.0]','^<f4'));
) | sqlite3.exe
```

In a batch script, escape `<` and `>` as required by `cmd.exe`, or place SQL in a file:

```sql
SELECT hex(pblob_pack('[1,-2,127,-128]','int8'));
SELECT pblob_unpack(x'01FE7F80','int8');
SELECT hex(pblob_pack('[1.0,2.0]','<f4'));
```

Then run:

```bat
sqlite3.exe :memory: < pblob_smoke.sql
```

Using a SQL file is preferred because `<` and `>` in format strings otherwise interact with CMD redirection syntax.

---

### 8. Test harness conventions

Use SQLite Tcl test helpers consistently.

Typical forms:

```tcl
do_execsql_test
do_catchsql_test
do_test
```

Where available, use helpers for:

* result storage classes;
* error-code inspection;
* allocation fault simulation;
* limit modification;
* prepared-statement reuse.

Each test name must be stable and hierarchical:

```text
pblob-pack-int8-1.1
pblob-pack-f16-2.4
pblob-unpack-f32-3.7
pblob-error-format-1.2
pblob-fault-pack-1.1
```

Do not encode transient implementation details into test names.

---

### 9. Public API presence tests

#### 9.1 Function registration

Verify both functions exist automatically:

```sql
SELECT pblob_pack('[]', 'int8');
SELECT pblob_unpack(x'', 'int8');
```

No `.load` or explicit initialization should be required.

#### 9.2 Arity

Verify exactly two arguments are required.

Test:

```sql
pblob_pack()
pblob_pack('[]')
pblob_pack('[]','int8',1)

pblob_unpack()
pblob_unpack(x'')
pblob_unpack(x'','int8',1)
```

Expected result: SQLite wrong-number-of-arguments error.

#### 9.3 No unintended aliases

Verify names such as these are absent unless separately provided by another extension:

```text
pack
unpack
pblob
pjson
packed_blob
packed_json
```

#### 9.4 JSON-disabled build

Compile SQLite with JSON omitted.

Verify:

* build succeeds;
* `pblob.c` contributes no unresolved references;
* `pblob_pack` and `pblob_unpack` are not registered.

This is a compile/configuration test, not part of the normal runtime suite.

---

### 10. NULL behavior tests

Test every nullable position:

```sql
SELECT pblob_pack(NULL, 'int8');
SELECT pblob_pack('[]', NULL);
SELECT pblob_pack(NULL, NULL);

SELECT pblob_unpack(NULL, 'int8');
SELECT pblob_unpack(x'', NULL);
SELECT pblob_unpack(NULL, NULL);
```

For each case verify:

```sql
typeof(result) = 'null'
```

NULL handling must occur before format parsing and argument-type errors.

For example:

```sql
pblob_pack(NULL, 123)
```

must return NULL if the contract states that any NULL argument propagates before checking the other argument.

Apply the same rule consistently to `pblob_unpack`.

---

### 11. Format parsing tests

#### 11.1 Accepted formats

Verify exact acceptance of:

```text
int8
<f2
>f2
<f4
>f4
```

#### 11.2 Rejected aliases

Test at least:

```text
INT8
Int8
i8
s8
<int8
>int8
f2
f4
float16
float32
fp16
fp32
<f16
>f16
<f32
>f32
= f4
=f4
@f4
native
```

#### 11.3 Whitespace

Reject:

```text
 int8
int8 
<f2 
 <f2
\t<f2
<f2\n
```

#### 11.4 Embedded NUL

Construct a format TEXT value containing an embedded NUL followed by valid or invalid suffix data.

Verify the parser compares explicit byte length and does not accept a valid prefix.

#### 11.5 Non-TEXT format argument

Test:

```sql
1
1.0
x'3C6632'
jsonb('"int8"')
```

Expected: format-type error, not coercion.

---

### 12. `pblob_pack()` first-argument type tests

#### 12.1 Accepted storage class

Accept only SQL TEXT containing JSON.

Examples:

```sql
'[]'
'[1,2,3]'
json('[1,2,3]')
```

`json()` returns JSON-subtyped TEXT and must be accepted.

#### 12.2 Rejected storage classes

Reject:

```sql
1
1.0
x'5B315D'
jsonb('[1]')
```

Even valid JSONB must be rejected because the public contract requires TEXT JSON.

#### 12.3 Empty TEXT

Test:

```sql
pblob_pack('', 'int8')
```

Expected: malformed JSON from `json.c`.

#### 12.4 Non-array JSON roots

Test valid JSON roots:

```json
null
true
false
0
1.0
"abc"
{}
```

Expected:

```text
pblob_pack: expected a JSON array
```

These are valid JSON but invalid function input shape.

---

### 13. JSON syntax and validation tests

Use SQLite’s own parser through `jsonParseFuncArg()`.

#### 13.1 Canonical JSON

Test valid arrays with:

* no whitespace;
* arbitrary legal whitespace;
* negative numbers;
* exponents;
* zero;
* negative zero;
* large finite decimal values.

#### 13.2 JSON5 accepted by SQLite

Test selected supported JSON5 features:

```text
[+1]
[.5]
[1.]
[0x7f]
[-0x80]
[1,]
[/*comment*/1]
```

Expected behavior should follow the selected `json.c`.

Do not independently redefine JSON5 syntax in `pblob` tests.

#### 13.3 Malformed JSON

Test at least:

```text
[
]
[1
1]
[1,,2]
[1 2]
[,1]
[1,,
[01]
[0x]
[.]
[1e]
[1e+]
["unterminated]
```

Expected: malformed JSON error produced through SQLite JSON parsing.

#### 13.4 Nested and non-numeric elements

Test arrays containing:

```json
[null]
[true]
[false]
["1"]
[[]]
[{}]
[1,null]
[1,"2"]
[1,[2]]
[1,{"x":2}]
```

Expected:

* `int8`: integer-element error.
* floating formats: numeric-element error.

Verify the first invalid element index is reported.

---

### 14. Empty-input tests

For every supported format:

```sql
SELECT typeof(pblob_pack('[]', format));
SELECT length(pblob_pack('[]', format));
SELECT hex(pblob_pack('[]', format));
```

Expected:

```text
blob
0
''
```

For every format:

```sql
SELECT typeof(pblob_unpack(x'', format));
SELECT pblob_unpack(x'', format);
SELECT json_valid(pblob_unpack(x'', format));
```

Expected:

```text
text
[]
1
```

Also verify JSON subtype behavior as described later.

---

### 15. `int8` packing tests

#### 15.1 Exact boundary bytes

Test:

```sql
SELECT hex(pblob_pack('[-128,-127,-1,0,1,126,127]', 'int8'));
```

Expected:

```text
8081FF00017E7F
```

#### 15.2 Full `int8` domain

Generate a JSON array containing all integers from `-128` through `127`.

Pack it and compare with a committed 256-byte expected hex string.

This test verifies:

* every signed value;
* every output byte;
* no signed-char dependency;
* correct sequence order.

#### 15.3 Out-of-range values

Reject:

```text
-129
128
-1000
1000
```

Verify both decimal and JSON5 hexadecimal forms where supported:

```text
-0x81
0x80
```

#### 15.4 Floating lexical values

Reject for `int8`:

```text
1.0
-0.0
1e0
.5
```

even when mathematically integral.

#### 15.5 Mixed array

Test:

```json
[1,2.0,3]
```

Expected failure at element index `1`.

#### 15.6 Very large integers

Test decimal and hexadecimal integers beyond signed 64-bit range.

Expected: `int8` range error, not wrapping or floating conversion.

---

### 16. `int8` unpacking tests

#### 16.1 Exact boundary decode

```sql
SELECT pblob_unpack(x'8081FF00017E7F', 'int8');
```

Expected:

```json
[-128,-127,-1,0,1,126,127]
```

#### 16.2 Full byte domain

Unpack a BLOB containing bytes:

```text
00 through FF
```

Expected JSON values:

```text
0 through 127, then -128 through -1
```

Compare against a committed expected JSON string or element-by-element result through `json_each()`.

#### 16.3 Any length valid

Test BLOB lengths:

```text
0
1
2
255
256
```

All are structurally valid for `int8`.

---

### 17. Binary32 packing exact-vector tests

For both `<f4` and `>f4`, verify exact bytes for:

| Value                       | Binary32 bits |
| --------------------------- | ------------- |
| `0.0`                       | `00000000`    |
| `-0.0`                      | `80000000`    |
| `1.0`                       | `3F800000`    |
| `-1.0`                      | `BF800000`    |
| `2.0`                       | `40000000`    |
| `0.5`                       | `3F000000`    |
| smallest positive subnormal | `00000001`    |
| largest subnormal           | `007FFFFF`    |
| smallest positive normal    | `00800000`    |
| maximum finite              | `7F7FFFFF`    |
| negative maximum finite     | `FF7FFFFF`    |

Example:

```sql
SELECT hex(pblob_pack('[1.0,2.0]', '<f4'));
```

Expected:

```text
0000803F00000040
```

Big-endian:

```text
3F80000040000000
```

#### 17.1 Integer-to-f4 input

Verify integer JSON nodes are accepted:

```sql
pblob_pack('[1,-2,3]', '<f4')
```

#### 17.2 Mixed numeric forms

Verify:

```json
[1,2.0,3e0]
```

is accepted.

#### 17.3 Rounding cases

Use committed reference vectors for values:

* exactly representable in binary32;
* halfway between adjacent binary32 values;
* immediately below and above halfway;
* values requiring exponent changes;
* values near subnormal boundaries.

Expected bytes must come from an independent reference generator.

#### 17.4 Overflow

Reject finite decimal values that narrow to binary32 infinity.

Include both signs.

#### 17.5 Underflow

Verify values that narrow to:

* binary32 subnormal;
* positive zero;
* negative zero.

Underflow to zero is valid.

---

### 18. Binary32 unpacking tests

#### 18.1 Exact finite patterns

Construct BLOBs directly for the known bit patterns in Section 17.

Verify output numerically through JSON extraction:

```sql
SELECT json_extract(pblob_unpack(blob, '<f4'), '$[0]');
```

Also verify exact output text for stable important cases:

```text
0.0
-0.0
1.0
-1.0
```

#### 18.2 Subnormal values

Test:

```text
00000001
007FFFFF
00800000
```

in both byte orders.

#### 18.3 Maximum finite

Test positive and negative maximum finite binary32.

#### 18.4 Infinity patterns

Reject:

```text
7F800000
FF800000
```

in both byte orders.

#### 18.5 NaN patterns

Reject multiple NaN encodings:

```text
7FC00000
7F800001
FFC00000
```

Do not test only one canonical NaN.

#### 18.6 Invalid BLOB lengths

For `f4`, reject all lengths not divisible by four.

At minimum:

```text
1
2
3
5
6
7
```

Verify the reported actual length and expected element size.

---

### 19. Binary16 packing exact-vector tests

For both `<f2` and `>f2`, verify exact bytes for:

| Value                       | Binary16 bits |
| --------------------------- | ------------- |
| `0.0`                       | `0000`        |
| `-0.0`                      | `8000`        |
| `1.0`                       | `3C00`        |
| `-1.0`                      | `BC00`        |
| `2.0`                       | `4000`        |
| `0.5`                       | `3800`        |
| smallest positive subnormal | `0001`        |
| largest positive subnormal  | `03FF`        |
| smallest positive normal    | `0400`        |
| maximum finite              | `7BFF`        |
| negative maximum finite     | `FBFF`        |

Example:

```sql
SELECT hex(pblob_pack('[1.0,2.0]', '<f2'));
```

Expected:

```text
003C0040
```

Big-endian:

```text
3C004000
```

#### 19.1 Integer and mixed inputs

Verify:

```json
[1,-2,3]
[1,2.0,3e0]
```

are accepted.

#### 19.2 Representative rounded values

Include:

```text
0.1
-0.1
1.0001
1.00048828125
1.0009765625
```

Use independent expected bits.

#### 19.3 Binary16 overflow

Reject values that convert to infinity.

Test:

* just above maximum finite where rounding still remains finite, if applicable;
* first values that round to infinity;
* clearly oversized values;
* both signs.

Reference vectors must establish exact boundaries.

#### 19.4 Binary16 underflow

Test values that become:

* smallest subnormal;
* another subnormal;
* positive zero;
* negative zero.

#### 19.5 Intermediate binary32 overflow

Test a decimal value too large for binary32.

Expected: rejection before or during binary16 conversion.

---

### 20. Binary16 unpacking tests

#### 20.1 Exhaustive 65,536-pattern classification

Use test-only C code to iterate through every `uint16_t` pattern.

Classify each pattern as:

* finite;
* positive infinity;
* negative infinity;
* NaN.

Verify classification against the IEEE bit fields:

```text
exponent != 31 -> finite
exponent == 31 and fraction == 0 -> infinity
exponent == 31 and fraction != 0 -> NaN
```

#### 20.2 Exhaustive finite decoding

For every finite binary16 pattern:

1. Decode with:

   ```c
   fp16_ieee_to_fp32_value()
   ```
2. Obtain binary32 bits with:

   ```c
   fp32_to_bits()
   ```
3. Compare with an independently established expected transformation or the bit-only FP16 function:

   ```c
   fp16_ieee_to_fp32_bits()
   ```
4. Confirm exact equality of binary32 bits.

This validates the chosen FP16 value-conversion path.

#### 20.3 Exhaustive finite round trip

For every finite binary16 pattern:

1. Decode to binary32.
2. Encode back with:

   ```c
   fp16_ieee_from_fp32_value()
   ```
3. Require identical binary16 bits.

Signed zeros must remain distinct.

NaN patterns are excluded because payload canonicalization may change NaN bits, and SQL unpack rejects NaN anyway.

#### 20.4 SQL-level representative decode

The SQL suite need not invoke all 65,536 patterns separately.

It must cover representative patterns from every category:

* both zeros;
* positive and negative subnormals;
* minimum normals;
* ordinary values;
* maximum finite;
* both infinities;
* several NaNs.

#### 20.5 Invalid BLOB lengths

For `f2`, reject every odd byte length.

At minimum:

```text
1
3
5
7
```

---

### 21. Endianness tests

#### 21.1 Known values

For each known binary16 and binary32 vector:

* pack little-endian;
* pack big-endian;
* verify each element’s byte order is reversed independently.

Do not reverse the entire multi-element BLOB as one unit.

Example:

```text
<f2 [1.0,2.0] -> 00 3C 00 40
>f2 [1.0,2.0] -> 3C 00 40 00
```

#### 21.2 Read/write helper tests

Through test-only C commands, verify:

```text
put LE -> get LE
put BE -> get BE
put LE bytes differ from BE bytes for asymmetric words
```

Use:

```text
0x0000
0x0001
0x00FF
0x0100
0x1234
0x8000
0xFFFF
```

and 32-bit equivalents.

#### 21.3 Unaligned addresses

Test helper calls using byte buffers beginning at non-word-aligned addresses.

This verifies that no implementation accidentally uses aligned integer loads or stores.

---

### 22. Signed-zero tests

#### 22.1 Packing

Verify:

```json
[-0.0]
```

produces:

```text
<f2 -> 0080
>f2 -> 8000
<f4 -> 00000080
>f4 -> 80000000
```

#### 22.2 Unpacking

Verify negative-zero patterns return JSON text preserving the sign.

Test both:

```sql
pblob_unpack(...)
json_extract(pblob_unpack(...), '$[0]')
```

Since SQL numeric comparison treats `-0.0` and `0.0` as equal, exact result text or bit reconstruction is required to verify the sign.

#### 22.3 Integer zero converted to float

Verify:

```json
[0]
```

packs as positive zero for `f2` and `f4`.

---

### 23. Output JSON tests

#### 23.1 Storage class

Verify:

```sql
typeof(pblob_unpack(...)) = 'text'
```

#### 23.2 JSON validity

Verify:

```sql
json_valid(pblob_unpack(...)) = 1
```

for every successful unpack result.

#### 23.3 Compact representation

Verify no spaces, tabs, CR, or LF are emitted.

#### 23.4 Element count

For representative BLOBs:

```sql
json_array_length(pblob_unpack(blob, format))
```

must equal:

```text
length(blob) / element_size
```

#### 23.5 Numeric element types

For `int8`, verify:

```sql
json_type(result, '$[i]') = 'integer'
```

For `f2` and `f4`, verify expected JSON/SQLite numeric behavior.

Where whole-valued floating output is expected to retain real syntax, test:

```sql
json_type(result, '$[i]') = 'real'
```

This specifically validates use of SQLite’s alternate floating formatter.

#### 23.6 JSON subtype

Verify the returned TEXT has `JSON_SUBTYPE`.

Use an existing test-harness subtype inspection command if available.

Also verify behavioral consequences in JSON construction. For example, when passed as a JSON argument, the unpacked array must be embedded as an array, not quoted as a string:

```sql
SELECT json_array(pblob_unpack(x'01FF', 'int8'));
```

Expected:

```json
[[1,-1]]
```

Not:

```json
["[1,-1]"]
```

---

### 24. Round-trip tests

Round trips are supplementary, not primary.

#### 24.1 `int8`

For every value in the full domain:

```text
JSON integer
-> pack
-> unpack
-> identical JSON integer
```

#### 24.2 Binary16

For committed source values:

```text
JSON number
-> binary16 BLOB
-> JSON text
-> repack
-> identical binary16 bits
```

The comparison must be on packed bytes, not textual JSON equality.

#### 24.3 Binary32

Apply the same packed-byte round-trip rule.

#### 24.4 Raw finite pattern round trips

For representative and exhaustive test-only cases:

```text
finite raw bits
-> unpack numeric value
-> pack
-> identical bits
```

For SQL-level tests, use representative patterns.

For exhaustive binary16, use direct C helpers.

---

### 25. Independent reference vectors

#### 25.1 Generator requirements

The vector generator must:

* be deterministic;
* use a fixed random seed;
* produce both little-endian and big-endian expected bytes;
* include explicit edge-value groups;
* include selected random finite values;
* include comments describing the generator and dependency versions.

#### 25.2 Recommended vector groups

##### `int8`

* complete `-128..127` domain.

##### Binary16

* every zero, subnormal boundary, normal boundary, and maximum finite value;
* values adjacent to rounding boundaries;
* selected random binary32 values;
* selected decimal literals representative of embeddings;
* positive and negative forms.

##### Binary32

* standard IEEE boundary patterns;
* selected decimal-to-binary32 rounding cases;
* selected random finite binary32 values rendered to round-trippable decimal text.

#### 25.3 Avoid self-reference

Do not generate expected FP16 bytes using the same vendored FP16 code used by `pblob.c`.

The independent oracle must not share the implementation under test.

---

### 26. Large-array tests

Test arrays with at least:

```text
1
2
3
128
768
1024
1536
4096
```

elements.

The dimensions `768`, `1024`, `1536`, and `4096` are representative embedding sizes.

For each:

* verify packed byte length;
* verify first, middle, and last bytes;
* verify unpacked element count;
* verify stable repeated execution.

Include arrays containing:

* all zeros;
* alternating signs;
* monotonic values;
* repeated decimal values;
* values near target precision limits.

---

### 27. SQLite length-limit tests

Temporarily reduce:

```text
SQLITE_LIMIT_LENGTH
```

through the test harness.

Test failures at these stages:

1. JSON input accepted but packed output exceeds the limit.
2. Packed input accepted but generated JSON text exceeds the limit.
3. Output exactly equal to the limit.
4. Output one byte above the limit.

Expected behavior:

* proper SQLite error;
* no partial result;
* no memory leak;
* subsequent calls still work.

---

### 28. Checked-size and overflow tests

The normal SQLite maximum BLOB size may prevent direct construction of a true `u64` multiplication overflow case.

Use test-only C wrappers to test the checked-size helper with artificial counts such as:

```text
0
1
UINT32_MAX
UINT64_MAX / 2
UINT64_MAX / 4
(UINT64_MAX / width) + 1
```

For widths:

```text
1
2
4
```

Verify:

* valid products are returned exactly;
* overflowing products are rejected;
* products exceeding SQLite length limits are rejected separately from arithmetic overflow.

---

### 29. Fault-injection tests

Use the SQLite test harness’s allocation-failure facilities.

#### 29.1 Pack parsing failures

Inject OOM while:

* allocating `JsonParse`;
* translating text JSON to JSONB;
* inserting or accessing the JSON parse cache.

#### 29.2 Temporary numeric copy failures

Inject OOM during:

```c
sqlite3DbStrNDup()
```

for integer and floating payloads.

#### 29.3 Packed-output allocation failure

Inject OOM during the exact packed BLOB allocation.

#### 29.4 Unpack JSON writer failures

Inject OOM:

* during initial `JsonString` growth;
* after several elements;
* near closing bracket;
* during final result ownership transfer where applicable.

#### 29.5 Recovery

After each simulated failure:

1. execute a simple successful packed-blob call;
2. verify correct output;
3. verify no persistent error or corrupted cache state.

---

### 30. Prepared-statement and cache tests

Because `jsonParseFuncArg()` can cache parsed TEXT JSON in statement auxiliary data, test prepared-statement reuse.

#### 30.1 Constant JSON input

Prepare once:

```sql
SELECT pblob_pack('[1,2,3]', 'int8');
```

Step repeatedly.

Verify identical output.

#### 30.2 Bound JSON parameter

Prepare:

```sql
SELECT pblob_pack(?1, ?2);
```

Bind different JSON arrays and formats across repeated executions.

Verify no stale parse or format state.

#### 30.3 Same text, different memory address

Bind equivalent JSON text values from separate allocations.

Verify cache lookup correctness.

#### 30.4 Error followed by valid bind

Execute malformed JSON, reset, then execute valid JSON.

Verify recovery.

---

### 31. SQL expression and schema integration tests

#### 31.1 CHECK constraint

Create:

```sql
CREATE TABLE t(
  vector BLOB NOT NULL,
  CHECK(length(vector) = 8)
);
```

Insert using `pblob_pack()`.

#### 31.2 Generated column

Where allowed by the selected SQLite build:

```sql
CREATE TABLE t(
  j TEXT,
  b BLOB GENERATED ALWAYS AS (pblob_pack(j, '<f2')) STORED
);
```

Verify deterministic-function eligibility.

#### 31.3 View

Create a view using `pblob_unpack()`.

Verify no `DIRECTONLY` restriction exists.

#### 31.4 Trigger

Use `pblob_pack()` in a trigger body.

#### 31.5 JSON composition

Verify subtype-sensitive composition:

```sql
json_array(pblob_unpack(...))
json_object('vector', pblob_unpack(...))
```

---

### 32. Error-message tests

Verify exact messages for stable extension-defined errors.

Test at least:

* first argument wrong storage class;
* format wrong storage class;
* unsupported format;
* non-array JSON root;
* invalid `int8` element type;
* invalid floating element type;
* `int8` range error;
* `f2` overflow;
* `f4` overflow;
* invalid BLOB length;
* non-finite unpack value.

For errors originating directly from `json.c`, avoid over-specifying byte-for-byte text beyond the selected SQLite version’s established behavior unless the project intentionally freezes those messages.

Always verify:

* SQL execution fails;
* no result row is returned;
* element indexes are zero-based;
* the first invalid element is reported.

---

### 33. Malformed internal representation tests

Because `pblob_pack()` accepts TEXT only, malformed caller-supplied JSONB cannot normally reach its traversal code.

Still test defensive internal behavior through test-only wrappers:

* invalid node header;
* truncated payload-size field;
* array payload ending inside an element;
* reserved JSONB type;
* invalid numeric payload.

Expected:

```text
malformed internal JSON representation
```

or the chosen internal-error equivalent.

These tests verify that defensive checks are not removed as “unreachable.”

---

### 34. Compiler-warning and static-analysis requirements

Build `pblob.c` with the project’s strict warning level.

The module must compile without new warnings for:

* signed/unsigned comparison;
* narrowing conversion;
* pointer aliasing;
* unaligned access;
* integer overflow;
* unused static functions;
* unreachable code;
* format-string type mismatch;
* implicit function declaration.

Where available, run:

* MSVC `/analyze`;
* Clang static analyzer;
* `clang-tidy` with project-appropriate checks.

Static-analysis output is supplementary and does not replace runtime tests.

---

### 35. Sanitizer tests

On a supported build environment, run the focused suite with:

```text
AddressSanitizer
UndefinedBehaviorSanitizer
```

Pay particular attention to:

* zero-length BLOB handling;
* unaligned byte reads;
* signed shifts;
* out-of-bounds payload traversal;
* lifetime of `JsonParse`;
* `JsonString` reset after errors;
* result destructor ownership;
* integer multiplication.

No sanitizer findings are acceptable.

---

### 36. Production-build verification

After all test builds pass, compile the normal release amalgamation.

Verify:

1. No dependency on `src/test_pblob.c`.
2. No unresolved test symbols.
3. No `SQLITE_TEST` registration functions.
4. No public `pblob` C API.
5. SQL functions are auto-registered.
6. FP16 portable conversion is compiled as intended.
7. Both SQL functions operate in `sqlite3.exe`.
8. The extension does not require dynamic loading.

Inspect exported DLL symbols where relevant. The extension should not introduce exported conversion symbols.

---

### 37. Minimum mandatory SQL cases

The following cases are mandatory before implementation acceptance.

```sql
SELECT hex(pblob_pack('[-128,-1,0,1,127]', 'int8'));
-- 80FF00017F

SELECT pblob_unpack(x'80FF00017F', 'int8');
-- [-128,-1,0,1,127]

SELECT hex(pblob_pack('[1.0,2.0]', '<f2'));
-- 003C0040

SELECT hex(pblob_pack('[1.0,2.0]', '>f2'));
-- 3C004000

SELECT hex(pblob_pack('[1.0,2.0]', '<f4'));
-- 0000803F00000040

SELECT hex(pblob_pack('[1.0,2.0]', '>f4'));
-- 3F80000040000000

SELECT pblob_unpack(x'003C0040', '<f2');
-- [1.0,2.0]

SELECT pblob_unpack(x'3C004000', '>f2');
-- [1.0,2.0]

SELECT pblob_unpack(x'0000803F00000040', '<f4');
-- [1.0,2.0]

SELECT pblob_unpack(x'3F80000040000000', '>f4');
-- [1.0,2.0]
```

Mandatory error cases:

```sql
SELECT pblob_pack(jsonb('[1]'), 'int8');
SELECT pblob_pack('{}', 'int8');
SELECT pblob_pack('[128]', 'int8');
SELECT pblob_pack('[1.0]', 'int8');
SELECT pblob_pack('[null]', '<f2');
SELECT pblob_unpack(x'00', '<f2');
SELECT pblob_unpack(x'000000', '<f4');
SELECT pblob_unpack(x'007C', '<f2');
SELECT pblob_unpack(x'0000807F', '<f4');
```

---

### 38. Test completion criteria

The implementation is ready for acceptance only when all of the following are true:

1. All focused Tcl SQL tests pass.
2. All exhaustive binary16 C tests pass.
3. All committed independent reference vectors pass.
4. Fault-injection tests pass without leaks or corruption.
5. SQLite length-limit tests pass.
6. Prepared-statement reuse tests pass.
7. The full SQLite regression suite passes.
8. The release-style amalgamation builds without test support.
9. Release shell smoke tests pass.
10. JSON-disabled configuration compiles cleanly without registering `pblob`.
11. Strict compiler warnings introduce no new warnings.
12. Sanitizer runs report no errors.
13. Exact endian byte tests pass.
14. Non-finite values are consistently rejected.
15. Signed zero is preserved.
16. No public C API or header has been introduced.
17. No standard test requires Python, NumPy, network access, or dynamic extension loading.

---

### 39. Required deliverables from the coding agent

The coding agent must provide:

```text
pblob.c
src/test_pblob.c
test/pblob.test
test/pblob_vectors.tcl
test/pblob_limits.test
test/pblob_fault.test
test/pblob_all.test
tool/gen_pblob_vectors.py
```

It must also provide concise build notes documenting:

1. Where `pblob.c` is inserted into the amalgamation source list.
2. Where `src/test_pblob.c` is inserted into the testfixture source list.
3. The exact Windows commands used to build `testfixture.exe`.
4. The exact commands used to run focused tests.
5. The exact command used to run the full SQLite regression suite.
6. The exact command used to build and smoke-test the release shell.
7. Whether `FP16_USE_NATIVE_CONVERSION` was explicitly forced to zero.
8. The compiler and SQLite source revision used for the recorded test run.
9. The independent reference implementation and version used to generate committed vectors.
10. A summary of all passing test groups and any intentionally unsupported build configurations.
