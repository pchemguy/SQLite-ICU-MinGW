---
url: https://chatgpt.com/c/6a61e127-7f24-83eb-9bcf-31c5a900a6a4
---

## 📗 SQLite Packed Numeric BLOB Extension Implementation Plan

> [!NOTE] Prompt
> 
> Help me create a comprehensive staged implementation plan, probably starting from pblob.c skeleton.

### Objective

Implement the amalgamation-only SQLite auto-extension defined by the design specification.

Public SQL API:

```sql
pblob_pack(json_array, format) -> BLOB
pblob_unpack(blob, format) -> JSON text
```

Supported formats:

```text
int8
<f2
>f2
<f4
>f4
```

Implementation constraints:

* Production code is contained in one module: `pblob.c`.
* No `pblob.h` is created.
* No public C API is exposed.
* The extension is compiled only as part of the SQLite amalgamation.
* `pblob.c` appears after `json.c` in the amalgamation.
* JSON parsing, validation, JSONB traversal, numeric parsing, and JSON output construction reuse private `json.c` facilities.
* IEEE binary16 conversion uses the vendored FP16 implementation.
* Native FP16 conversion is disabled for deterministic behavior:
```c
#define FP16_USE_NATIVE_CONVERSION 0
```
* New code is limited primarily to format handling, traversal glue, endian operations, range checks, and SQL callbacks.

Each stage must leave the tree in a compilable state. Once SQL functions are registered, each subsequent stage must also leave the focused smoke tests passing.

---

### Stage overview

| Stage | Primary deliverable                                       |
| ----- | --------------------------------------------------------- |
| 0     | Confirm integration points and exact SQLite internals     |
| 1     | Create a compiling `pblob.c` skeleton                     |
| 2     | Register SQL functions with placeholder behavior          |
| 3     | Format parsing and common argument handling               |
| 4     | Endian and bit-level primitives                           |
| 5     | JSONB numeric extraction helpers                          |
| 6     | `int8` packing                                            |
| 7     | `int8` unpacking                                          |
| 8     | Binary32 packing                                          |
| 9     | Binary32 unpacking                                        |
| 10    | Integrate FP16 and implement binary16 packing             |
| 11    | Implement binary16 unpacking                              |
| 12    | Complete validation and edge-case behavior                |
| 13    | Add test-only low-level hooks                             |
| 14    | Complete SQL, vector, limit, and fault tests              |
| 15    | Run full integration, release, and portability validation |
| 16    | Final review and cleanup                                  |

Do not combine all stages into one large implementation patch.

---

### Stage 0 — Confirm source integration points

#### Goal

Resolve all source-tree and symbol dependencies before writing conversion logic.

#### Tasks

Inspect the exact SQLite source revision and confirm the presence and signatures of:

```c
JsonParse
JsonString

jsonParseFuncArg()
jsonParseFree()
jsonbPayloadSize()
jsonbArrayCount()

jsonStringInit()
jsonStringReset()
jsonAppendChar()
jsonPrintf()
jsonReturnString()

sqlite3DecOrHexToI64()
sqlite3AtoF()
sqlite3DbStrNDup()
sqlite3DbFree()

JSON_SUBTYPE
JSONB_INT
JSONB_INT5
JSONB_FLOAT
JSONB_FLOAT5
JSONB_ARRAY
```

Confirm that `pblob.c` can be inserted after `json.c` in the same amalgamation translation unit.

Confirm the project’s auto-extension dispatcher interface and determine:

* initializer name;
* expected initializer signature;
* registration error propagation;
* source-order or forward-declaration requirements.

Confirm how FP16 headers are made visible:

* directly included from the source tree; or
* expanded by the existing source bundler.

Confirm that the selected FP16 headers provide:

```c
fp16_ieee_from_fp32_value()
fp16_ieee_to_fp32_value()
fp32_to_bits()
fp32_from_bits()
```

#### Deliverable

A short implementation note recording:

```text
SQLite source revision
json.c symbols used
FP16 source revision
amalgamation insertion point
auto-extension initializer convention
testfixture integration point
```

#### Exit criteria

* No unresolved uncertainty about symbol names or source ordering.
* No invented abstraction layer is required.
* The build system location for `pblob.c` is known.

---

### Stage 1 — Create the `pblob.c` skeleton

#### Goal

Add the production module without implementing SQL behavior.

#### File structure

Create:

```text
pblob.c
```

Recommended initial organization:

```c
/*
** Module documentation
*/

#ifndef SQLITE_OMIT_JSON

/* FP16 configuration and inclusion */

/* Compile-time platform checks */

/* Private format enums and structures */

/* Forward declarations */

/* Format helpers */

/* Byte-order helpers */

/* JSONB numeric helpers */

/* Pack callback */

/* Unpack callback */

/* Registration initializer */

#endif /* SQLITE_OMIT_JSON */
```

#### Module documentation

The top-level comment should state:

* purpose;
* supported SQL functions;
* supported formats;
* raw headerless BLOB contract;
* amalgamation-only status;
* dependency on `json.c`;
* dependency on vendored FP16;
* absence of public C API.

#### FP16 configuration

Before including the FP16 implementation, force the portable conversion path:

```c
#ifndef FP16_USE_NATIVE_CONVERSION
### define FP16_USE_NATIVE_CONVERSION 0
#endif
```

Then include the project’s selected FP16 header.

Do not define native conversion conditionally by host capabilities.

#### Compile-time checks

Add compile-time checks for:

```text
CHAR_BIT == 8
sizeof(uint16_t) == 2
sizeof(uint32_t) == 4
sizeof(float) == 4
FLT_RADIX == 2
FLT_MANT_DIG == 24
FLT_MAX_EXP == 128
```

Use the project’s available static-assert convention.

#### Initial private declarations

Define:

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

Declare callbacks and helpers but do not implement conversion logic yet.

#### Exit criteria

* `pblob.c` compiles as part of the amalgamation.
* JSON-disabled builds also compile.
* No SQL functions are registered yet.
* No warnings are introduced.

---

### Stage 2 — Register placeholder SQL functions

#### Goal

Establish auto-extension integration and SQL visibility before implementing conversions.

#### Tasks

Implement:

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

At this stage, callbacks may return a deterministic temporary error:

```text
pblob_pack: not implemented
pblob_unpack: not implemented
```

Implement the internal initializer:

```c
int sqlite3PblobInit(sqlite3 *db);
```

Register:

```text
pblob_pack / arity 2
pblob_unpack / arity 2
```

Use flags:

```c
SQLITE_UTF8
| SQLITE_DETERMINISTIC
| SQLITE_INNOCUOUS
| SQLITE_RESULT_SUBTYPE
```

Wire the initializer into the project’s auto-extension dispatcher.

#### Initial smoke tests

Verify:

```sql
SELECT pblob_pack('[]', 'int8');
SELECT pblob_unpack(x'', 'int8');
```

Both functions must resolve without `.load`.

Verify wrong arity is handled by SQLite.

#### Exit criteria

* Both functions are auto-registered.
* No loadable-extension path is involved.
* Registration errors propagate correctly.
* Release and test builds compile.

---

### Stage 3 — Format parsing and common argument handling

#### Goal

Complete all common API validation independent of numeric conversion.

#### Implement exact format parser

Implement:

```c
static int pblobParseFormat(
  sqlite3_context *ctx,
  sqlite3_value *pArg,
  const char *zFunc,
  PblobFormat *pFormat
);
```

Exact accepted mappings:

```text
int8 -> PBLOB_INT8, NONE, 1
<f2  -> PBLOB_F16, LE,   2
>f2  -> PBLOB_F16, BE,   2
<f4  -> PBLOB_F32, LE,   4
>f4  -> PBLOB_F32, BE,   4
```

Use:

```c
sqlite3_value_type()
sqlite3_value_text()
sqlite3_value_bytes()
memcmp()
```

Do not use NUL-terminated comparison without checking byte length.

#### Implement NULL propagation

In both callbacks:

1. Check both argument types for SQL NULL.
2. If either is NULL:

   ```c
   sqlite3_result_null(ctx);
   return;
   ```

This must precede all other validation.

#### Implement storage-class validation

For `pblob_pack()` require:

```text
argument 0: SQLITE_TEXT
argument 1: SQLITE_TEXT
```

For `pblob_unpack()` require:

```text
argument 0: SQLITE_BLOB
argument 1: SQLITE_TEXT
```

Reject JSONB BLOB input to `pblob_pack()`.

Do not coerce storage classes.

#### Tests added at this stage

Add focused SQL tests for:

* function existence;
* arity;
* NULL propagation;
* accepted formats;
* rejected aliases;
* leading/trailing whitespace;
* wrong format storage class;
* wrong primary argument storage class;
* embedded NUL in format.

#### Exit criteria

* All API validation tests pass.
* No numeric conversion exists yet.
* Placeholder errors are reached only after arguments and format are valid.

---

### Stage 4 — Endian and bit-level primitives

#### Goal

Finish and test all host-independent byte operations before adding data workflows.

#### Implement helpers

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

Use only:

* byte indexing;
* unsigned shifts;
* unsigned masks;
* bitwise OR.

Do not use pointer casts to integer types.

#### Implement classification helpers

Optionally add small private predicates:

```c
static int pblobF16IsFinite(uint16_t bits);
static int pblobF32IsFinite(uint32_t bits);
```

Definitions:

```text
f16 finite: exponent field != 0x1F
f32 finite: exponent field != 0xFF
```

Optionally separate NaN and infinity classification for better errors.

#### Test strategy

Initially use compile-time assertions and test-only wrappers if already available.

At minimum test:

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

Test unaligned buffer offsets.

#### Exit criteria

* All read/write round trips pass.
* Known byte layouts are correct.
* No alignment or host-endian dependency exists.
* Sanitizer/static analysis reports no issue.

---

### Stage 5 — JSONB numeric extraction helpers

#### Goal

Create reusable private helpers for numeric extraction without yet writing packed output.

This stage is critical. It should be reviewed independently.

#### Integer helper

Implement:

```c
static int pblobJsonbInteger(
  sqlite3_context *ctx,
  JsonParse *pParse,
  u32 iNode,
  sqlite3_int64 *pValue
);
```

Expected result convention:

```text
0 -> success
nonzero -> error already reported
```

Algorithm:

1. Determine node type.
2. Require `JSONB_INT` or `JSONB_INT5`.
3. Obtain header and payload sizes with `jsonbPayloadSize()`.
4. Reject zero-length or malformed payload.
5. Handle optional leading minus sign as required by existing `json.c` logic.
6. Copy payload with:

   ```c
   sqlite3DbStrNDup()
   ```
7. Parse with:

   ```c
   sqlite3DecOrHexToI64()
   ```
8. Free temporary storage with:

   ```c
   sqlite3DbFree()
   ```
9. Return exact signed result.
10. Treat all values outside signed 64-bit range as range failures for `int8`.

Adapt the behavior from `jsonReturnFromBlob()` rather than inventing a new integer parser.

#### General numeric helper

Implement:

```c
static int pblobJsonbNumber(
  sqlite3_context *ctx,
  JsonParse *pParse,
  u32 iNode,
  double *pValue
);
```

Accepted types:

```text
JSONB_INT
JSONB_INT5
JSONB_FLOAT
JSONB_FLOAT5
```

Algorithm:

1. Determine type.
2. Obtain payload location and length.
3. For canonical decimal values:

   * duplicate payload;
   * call `sqlite3AtoF()`;
   * reject parser failure.
4. For JSON5 hexadecimal integers:

   * adapt the `jsonReturnFromBlob()` `JSONB_INT5` path;
   * use `sqlite3DecOrHexToI64()`;
   * correctly handle the positive 64-bit high-bit case;
   * convert result to `double`.
5. Return OOM distinctly.
6. Never use `strtod()` or `sscanf()`.

#### Local validation harness

Before full pack implementation, add temporary test-only wrappers or a minimal internal SQL debug path to verify extraction from:

```text
0
-1
127
-128
1.0
1e0
.5
0x7f
-0x80
large integer boundaries
```

Remove temporary production-visible debug behavior before the next stage.

#### Exit criteria

* Integer extraction matches SQLite semantics.
* Floating extraction matches SQLite semantics.
* JSON5 hexadecimal handling is correct.
* OOM cleanup paths are complete.
* No independent numeric parser has been added.

---

### Stage 6 — `int8` packing

#### Goal

Deliver the first complete production conversion workflow.

#### Common pack preparation

Replace the `pblob_pack()` placeholder with:

1. NULL handling.
2. type validation.
3. format parsing.
4. JSON parsing:

   ```c
   jsonParseFuncArg(ctx, argv[0], 0)
   ```
5. root `JSONB_ARRAY` validation.
6. element count:

   ```c
   jsonbArrayCount()
   ```
7. checked output-size calculation.
8. exact output allocation.
9. root payload traversal.

Initially dispatch only `PBLOB_INT8`. For floating formats, return a temporary “format not implemented” error.

#### `int8` element algorithm

For each element:

1. Decode node header with `jsonbPayloadSize()`.
2. Require type:

   ```text
   JSONB_INT or JSONB_INT5
   ```
3. Call `pblobJsonbInteger()`.
4. Require:

   ```text
   -128 <= value <= 127
   ```
5. Store one byte.
6. Advance to next node.

At the end require:

```text
node offset == array payload end
processed count == jsonbArrayCount result
```

#### Empty array

Return a zero-length BLOB with storage class `blob`.

Do not treat a zero-byte allocation result as OOM.

#### Tests added

* empty array;
* exact boundaries;
* full `-128..127` domain;
* JSON5 hexadecimal integers;
* out-of-range values;
* floating lexical values rejected;
* strings, booleans, null, arrays, objects rejected;
* first invalid element index;
* large arrays;
* exact result storage class.

#### Exit criteria

* `pblob_pack(..., 'int8')` is production-complete.
* Exact byte tests pass.
* Floating formats remain explicitly unimplemented.
* No memory leaks under repeated calls.

---

### Stage 7 — `int8` unpacking

#### Goal

Complete the first full pack/unpack format pair.

#### Common unpack preparation

Replace the `pblob_unpack()` placeholder with:

1. NULL handling.
2. storage-class validation.
3. format parsing.
4. BLOB retrieval.
5. length divisibility validation.
6. `JsonString` initialization.
7. opening bracket.
8. element loop.
9. closing bracket.
10. `jsonReturnString()`.
11. `sqlite3_result_subtype(ctx, JSON_SUBTYPE)`.

Initially dispatch only `PBLOB_INT8`.

#### `int8` decode algorithm

For each byte:

```text
if byte < 128:
    value = byte
else:
    value = byte - 256
```

Append using `jsonPrintf()` as integer syntax.

#### Tests added

* zero-length BLOB;
* boundary bytes;
* all byte values `00..FF`;
* arbitrary lengths;
* output JSON validity;
* compact output;
* JSON subtype composition;
* element count;
* integer JSON types.

#### Exit criteria

* Full `int8` round trips work.
* Exact pack and unpack tests pass independently.
* JSON subtype is correct.
* No floating format behavior has been added yet.

---

### Stage 8 — Binary32 packing

#### Goal

Add `<f4` and `>f4` packing.

#### Per-element algorithm

1. Accept:

   ```text
   JSONB_INT
   JSONB_INT5
   JSONB_FLOAT
   JSONB_FLOAT5
   ```
2. Extract `double` with `pblobJsonbNumber()`.
3. Reject non-finite source value.
4. Convert:

   ```c
   float f = (float)d;
   ```
5. Obtain bits:

   ```c
   uint32_t bits = fp32_to_bits(f);
   ```
6. Reject non-finite binary32 result.
7. Write:

   ```c
   pblobPutU32Le()
   ```

   or:

   ```c
   pblobPutU32Be()
   ```

#### Required semantic checks

* Integer JSON nodes are accepted.
* Mixed integer and real nodes are accepted.
* Overflow to infinity is rejected.
* Underflow to subnormal or zero is accepted.
* Negative zero is preserved.
* No use of host byte order.

#### Tests added

* known IEEE binary32 values;
* both endian forms;
* subnormal boundaries;
* minimum normal;
* maximum finite;
* positive and negative zero;
* representative rounding cases;
* overflow;
* underflow;
* mixed numeric arrays;
* non-numeric elements.

#### Exit criteria

* Exact `<f4` and `>f4` pack vectors pass.
* `int8` tests remain unchanged and passing.
* No binary32 unpacking exists yet.

---

### Stage 9 — Binary32 unpacking

#### Goal

Complete binary32 support.

#### Per-element algorithm

1. Read 32-bit word in requested byte order.
2. Inspect exponent bits.
3. Reject infinity and NaN before conversion.
4. Convert:

   ```c
   float f = fp32_from_bits(bits);
   ```
5. Promote:

   ```c
   double d = (double)f;
   ```
6. Append:

   ```c
   jsonPrintf(100, &out, "%!0.17g", d);
   ```

#### Length validation

Reject any BLOB length not divisible by four.

#### Tests added

* direct known bit-pattern decoding;
* both endian forms;
* positive and negative subnormals;
* maximum finite;
* infinity;
* multiple NaN forms;
* invalid lengths;
* signed-zero text preservation;
* pack/unpack/repack byte equality.

#### Exit criteria

* Binary32 pack and unpack are complete.
* All `int8` and `f4` tests pass.
* Output JSON is valid and JSON-subtyped.

---

### Stage 10 — Integrate FP16 and implement binary16 packing

#### Goal

Add `<f2` and `>f2` packing using the vendored FP16 converter.

#### Integration check

Confirm at compile time that:

```c
FP16_USE_NATIVE_CONVERSION == 0
```

for the normative build.

Do not add another binary16 converter.

#### Per-element algorithm

1. Accept numeric JSONB node types.
2. Extract `double`.
3. Reject non-finite source value.
4. Narrow:

   ```c
   float f = (float)d;
   ```
5. Obtain binary32 bits with:

   ```c
   fp32_to_bits(f)
   ```
6. Reject non-finite binary32 intermediate.
7. Convert:

   ```c
   uint16_t bits = fp16_ieee_from_fp32_value(f);
   ```
8. Reject binary16 exponent-all-ones result.
9. Write requested byte order.

#### Semantic documentation

Document clearly in code comments:

```text
decimal JSON -> SQLite double -> binary32 -> binary16
```

Do not claim direct correctly rounded binary64-to-binary16 conversion.

#### Tests added

* known binary16 values;
* both endian forms;
* subnormal boundaries;
* maximum finite;
* overflow boundaries;
* underflow;
* signed zero;
* representative rounding values;
* mixed numeric arrays;
* intermediate binary32 overflow.

#### Exit criteria

* Exact `<f2` and `>f2` pack vectors pass.
* FP16 portable path is confirmed.
* Existing formats remain passing.

---

### Stage 11 — Implement binary16 unpacking

#### Goal

Complete all public format workflows.

#### Per-element algorithm

1. Read 16-bit word in requested byte order.
2. Reject exponent-all-ones patterns.
3. Convert:

   ```c
   float f = fp16_ieee_to_fp32_value(bits);
   ```
4. Promote exactly to `double`.
5. Append with SQLite JSON real formatting.

#### Length validation

Reject odd BLOB lengths.

#### Tests added

* known finite patterns;
* both zeros;
* subnormals;
* minimum normals;
* maximum finite;
* infinity patterns;
* several NaNs;
* odd lengths;
* pack/unpack/repack bit equality.

#### Exit criteria

* All five formats are fully implemented.
* Both SQL functions have no placeholder branches.
* All focused exact-vector tests pass.

---

### Stage 12 — Complete validation and edge-case behavior

#### Goal

Audit the implementation against every design requirement before adding exhaustive testing infrastructure.

#### Validation audit

Confirm:

* SQL NULL propagates first.
* `pblob_pack()` accepts TEXT only.
* JSONB input is rejected.
* format matching is exact.
* root must be array.
* malformed JSON is handled by `json.c`.
* nested and non-numeric elements are rejected.
* integer floats are rejected for `int8`.
* `int8` does not clamp or wrap.
* finite floating overflow is rejected.
* floating underflow is accepted.
* packed infinity and NaN are rejected.
* signed zero is preserved.
* empty arrays/BLOBs work.
* element indexes are zero-based.
* malformed internal traversal is checked defensively.

#### Memory audit

For each callback, enumerate every owned object and exit path.

Verify:

* every `JsonParse` is freed;
* every temporary numeric string is freed;
* output BLOB ownership transfers exactly once;
* pre-transfer BLOB allocations are freed on errors;
* `JsonString` is reset after early failures;
* zero-length outputs do not create false OOM errors.

#### Limit audit

Implement or finalize:

* checked element-count multiplication;
* SQLite length-limit enforcement;
* conversion from `u32`/`u64` sizes without truncation;
* `sqlite3_result_blob64()` use.

#### Error-message audit

Normalize extension-defined messages and ensure function names are included.

#### Exit criteria

* Manual checklist against Part 1 is complete.
* Focused SQL suite passes.
* Strict-warning build is clean.

---

### Stage 13 — Add test-only low-level hooks

#### Goal

Support exhaustive and low-level testing without creating a production API.

#### Add `src/test_pblob.c`

Register Tcl commands for:

* endian helper validation;
* exhaustive binary16 classification;
* exhaustive binary16 decode comparison;
* exhaustive finite binary16 round trip;
* checked-size helper testing;
* malformed internal JSONB traversal where needed.

#### Visibility approach

Preferred:

* keep production helpers `static`;
* compile test code later in the same test amalgamation translation unit where feasible.

Otherwise add narrowly scoped declarations under:

```c
#ifdef SQLITE_TEST
```

Do not create `pblob.h`.

#### Exit criteria

* Test-only commands are available in `testfixture`.
* Release builds contain none of them.
* Production helper linkage remains private.

---

### Stage 14 — Complete the full test suite

#### Goal

Implement all test modules from Part 2.

#### Required files

```text
src/test_pblob.c
test/pblob.test
test/pblob_vectors.tcl
test/pblob_limits.test
test/pblob_fault.test
test/pblob_all.test
tool/gen_pblob_vectors.py
```

#### Test implementation order

##### Step 1

Complete deterministic SQL contract tests:

* registration;
* arity;
* argument types;
* NULL;
* format parsing;
* JSON syntax;
* exact bytes;
* output JSON;
* error cases.

##### Step 2

Generate and commit independent reference vectors.

##### Step 3

Add exhaustive binary16 C tests.

##### Step 4

Add SQLite length-limit tests.

##### Step 5

Add OOM and fault-injection tests.

##### Step 6

Add prepared-statement and cache tests.

##### Step 7

Add schema-integration tests.

#### Exit criteria

* All focused test modules pass independently.
* `pblob_all.test` passes.
* No normal test depends on Python or NumPy.

---

### Stage 15 — Full integration and build validation

#### Goal

Prove the implementation works in all intended build configurations.

#### Test build

Perform a clean build of:

```text
testfixture.exe
```

with:

```text
SQLITE_TEST
SQLITE_DEBUG
SQLITE_ENABLE_API_ARMOR
FP16_USE_NATIVE_CONVERSION=0
```

Run:

```text
pblob.test
pblob_limits.test
pblob_fault.test
pblob_all.test
```

#### Full SQLite suite

Run the selected source tree’s established full regression target.

Do not stop after the focused extension tests.

#### Release build

Build normal:

```text
sqlite3.exe
sqlite3.dll
```

without test defines.

Verify:

* auto-registration;
* smoke conversions;
* no unresolved symbols;
* no test-only exports;
* no need for `.load`.

#### JSON-disabled build

Compile with:

```text
SQLITE_OMIT_JSON
```

Verify clean compilation and absence of SQL function registration.

#### Sanitizer build

Run the focused suite under ASan/UBSan on a supported toolchain.

#### Exit criteria

* All configurations compile.
* All required runtime suites pass.
* No sanitizer findings.
* No new compiler warnings.

---

### Stage 16 — Final review and cleanup

#### Goal

Prepare the implementation for merge and future maintenance.

#### Code review checklist

Verify:

* one production module only;
* no `pblob.h`;
* no public C API;
* all private helpers are `static`;
* no duplicated JSON parser;
* no duplicated JSON writer;
* no duplicated decimal parser;
* no duplicated FP16 converter;
* no host-endian assumptions;
* no unaligned integer access;
* no plain-char signedness assumptions;
* no unsupported formats or aliases;
* no dead placeholder code;
* no test-only behavior in production builds.

#### Documentation review

Ensure comments explain:

* raw BLOB layout;
* target formats;
* binary16 conversion path through binary32;
* rejection of non-finite values;
* TEXT-only JSON input;
* reason for direct `json.c` dependency;
* source-order requirement.

#### Test report

Record:

```text
SQLite revision
compiler and version
build commands
test commands
FP16 portable-path status
focused test results
full SQLite test result
sanitizer result
reference-vector generator versions
```

#### Final acceptance criteria

The work is complete only when:

1. `pblob.c` implements both SQL functions.
2. All five formats are supported.
3. Exact byte vectors pass.
4. Exhaustive binary16 tests pass.
5. Fault and limit tests pass.
6. Full SQLite tests pass.
7. Release builds pass smoke tests.
8. JSON-disabled builds compile.
9. No public C API or header exists.
10. The implementation remains materially smaller than an independent parser/conversion implementation.

---

### Recommended patch sequence

The coding agent should submit changes in approximately this sequence:

```text
Patch 1
- pblob.c skeleton
- amalgamation integration
- no SQL registration

Patch 2
- SQL registration
- placeholder callbacks
- registration smoke tests

Patch 3
- format parser
- NULL and type validation tests

Patch 4
- endian and classification helpers
- low-level helper tests

Patch 5
- JSONB integer and numeric extraction helpers

Patch 6
- int8 packing
- int8 pack tests

Patch 7
- int8 unpacking
- int8 unpack and subtype tests

Patch 8
- f4 packing
- f4 exact-vector tests

Patch 9
- f4 unpacking
- f4 non-finite and length tests

Patch 10
- FP16 integration
- f2 packing tests

Patch 11
- f2 unpacking
- representative f2 tests

Patch 12
- validation, cleanup, limits, and error audit

Patch 13
- test_pblob.c
- exhaustive binary16 tests

Patch 14
- reference vectors
- fault, limit, cache, and integration tests

Patch 15
- final build-system notes
- full regression and release validation
```

Each patch must compile independently. From Patch 2 onward, previously implemented SQL behavior and tests must remain passing.

---

### First coding task

The first coding task should be limited to:

1. Create `pblob.c`.
2. Add the module documentation.
3. Add JSON compile guards.
4. Include/configure FP16.
5. Add compile-time platform checks.
6. Define private format types.
7. Add callback and initializer declarations.
8. Insert `pblob.c` after `json.c` in the amalgamation source list.
9. Confirm:
    * normal amalgamation build succeeds;
    * test amalgamation build succeeds;
    * JSON-disabled build succeeds.
10. Do not register SQL functions or implement conversion logic yet.

This establishes the correct compilation and source-order foundation before functional code is introduced.
