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
