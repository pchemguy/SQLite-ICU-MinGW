---
url: https://chatgpt.com/c/6a61e127-7f24-83eb-9bcf-31c5a900a6a4
---

## 📗 Overview

> [!NOTE] Prompt
> 
> Help me plan/define/design an SQLite packed blob extension starting with no c code. This extension will convert between JSON array of scalars (int or float, all the same type) and packed blob of int8, <f2, >f2, <f4, >f4

### Proposed extension contract

The extension should treat the BLOB as a **raw, headerless, contiguous array**. The element type and byte order are supplied separately through a format string.

This keeps storage overhead at exactly zero bytes beyond the packed values.

### 1. Supported format strings

| Format | Meaning                               | Bytes per element |
| ------ | ------------------------------------- | ----------------: |
| `int8` | Signed two’s-complement 8-bit integer |                 1 |
| `<f2`  | IEEE 754 binary16, little-endian      |                 2 |
| `>f2`  | IEEE 754 binary16, big-endian         |                 2 |
| `<f4`  | IEEE 754 binary32, little-endian      |                 4 |
| `>f4`  | IEEE 754 binary32, big-endian         |                 4 |

Recommended rules:

* Format strings are exact and case-sensitive.
* No aliases in version 1.
* `int8` has no endianness because it occupies one byte.
* `f2` specifically means IEEE 754 binary16, not `bfloat16`.
* `f4` specifically means IEEE 754 binary32.

Do not initially accept ambiguous forms such as `float16`, `half`, `i1`, `f`, or native-endian `=f4`.

---

### 2. Core SQL API

#### Packing

```sql
pblob_pack(json_array, format) -> BLOB
```

Examples:

```sql
SELECT pblob_pack('[1, 2, -3]', 'int8');

SELECT pblob_pack('[1.0, 2.5, -3.25]', '<f2');

SELECT pblob_pack(json('[1.0, 2.5]'), '>f4');
```

#### Unpacking

```sql
pblob_unpack(blob, format) -> JSON text
```

Examples:

```sql
SELECT pblob_unpack(x'01FE7F', 'int8');
-- [1,-2,127]

SELECT pblob_unpack(vector_blob, '<f2')
FROM embeddings;
```

The initial extension can consist of only these two functions.

I would nevertheless define several supporting functions before implementation so that the core contract does not later need incompatible changes.

---

### 3. Recommended supporting API

#### Element count

```sql
pblob_count(blob, format) -> INTEGER
```

```sql
SELECT pblob_count(vector_blob, '<f2');
```

Calculation:

```text
length(blob) / element_size
```

An invalid byte length must produce an error rather than silently truncating.

#### Format validation

```sql
pblob_is_valid(blob, format) -> INTEGER
```

Returns:

* `1` when the format is recognized and the BLOB length is valid.
* `0` when the BLOB length is incompatible with the format.
* SQL error for an unknown format.

This function checks structural validity only. It should not scan floating-point values for NaNs or infinities unless explicitly documented to do so.

#### Element extraction

Potential version 2 function:

```sql
pblob_get(blob, format, index) -> INTEGER | REAL
```

This is useful because unpacking an entire vector merely to inspect one element is wasteful.

Recommended indexing convention:

* Zero-based indexing.
* Negative indexes rejected initially rather than given Python-style semantics.
* Out-of-range index returns `NULL`, matching many SQLite lookup conventions.

Example:

```sql
SELECT pblob_get(vector_blob, '<f2', 0);
```

Do not include this in the first implementation unless there is a concrete need.

---

### 4. JSON input contract

`pblob_pack()` accepts one JSON array containing only JSON numbers.

Valid:

```json
[]
[1, 2, 3]
[1.0, 2.5, -3.25]
[1, 2.0, 3]
```

Invalid:

```json
null
123
{"x": 1}
[1, null, 3]
[1, true, 3]
["1", "2"]
[1, [2], 3]
```

Although the user-facing requirement says all values have the same scalar type, the cleanest rule is to make the requested packed format authoritative.

For example:

```sql
pblob_pack('[1, 2.0, 3]', '<f4')
```

should be accepted because all values are numeric and convertible to `f4`.

Conversely:

```sql
pblob_pack('[1, 2.0, 3]', 'int8')
```

should be rejected because `2.0` is lexically or semantically a floating-point JSON number, depending on the parser contract selected below.

There are two possible definitions for `int8`.

#### Recommended strict definition

For `int8`, every array element must be represented by SQLite as an integer and lie in:

```text
-128 through 127
```

Therefore:

```sql
pblob_pack('[1, 2, -3]', 'int8')     -- valid
pblob_pack('[1, 2.0, -3]', 'int8')   -- error
pblob_pack('[1, 128]', 'int8')       -- error
pblob_pack('[1, -129]', 'int8')      -- error
```

This avoids accidental conversion from floating-point values and avoids questions about rounding.

Do not clamp values. Do not wrap values modulo 256.

---

### 5. Floating-point conversion semantics

#### `f4`

Each JSON number is converted to IEEE 754 binary32 using normal round-to-nearest, ties-to-even behavior.

#### `f2`

Each JSON number is converted to IEEE 754 binary16 using round-to-nearest, ties-to-even.

The conversion should support:

* Normal values
* Subnormal values
* Positive zero
* Negative zero
* Rounding to zero on underflow

#### Overflow

Recommended version 1 policy:

> Reject finite JSON numbers whose magnitude cannot be represented as a finite value in the target format.

Therefore, do not silently convert an oversized finite value to positive or negative infinity.

Approximate finite limits:

| Format |       Maximum finite magnitude |
| ------ | -----------------------------: |
| `f2`   |                          65504 |
| `f4`   | approximately 3.4028235 × 10³⁸ |

Example:

```sql
pblob_pack('[70000]', '<f2')
```

should fail with a range error.

#### Precision loss

Normal rounding and precision loss are accepted.

For example:

```sql
pblob_pack('[0.1]', '<f2')
```

is valid even though `0.1` is not exactly representable in binary16.

---

### 6. NaN and infinity policy

This needs to be explicitly designed because JSON cannot represent IEEE NaN or infinity.

Packing from valid JSON does not normally encounter these values. However, arbitrary BLOBs may contain:

* Positive infinity
* Negative infinity
* Quiet NaNs
* Signaling NaNs

For `pblob_unpack()`, the strongest version 1 policy is:

> Reject any BLOB containing a non-finite floating-point value.

Example error:

```text
pblob_unpack: element 17 is not representable in JSON: NaN
```

Do not output invalid JSON such as:

```json
[NaN, Infinity]
```

Do not silently convert non-finite values to strings.

Do not silently convert them to `null`, because that loses information without an explicit request.

A later API could add an options argument:

```sql
pblob_unpack(blob, format, 'nonfinite=null')
```

But options should not complicate version 1.

---

### 7. Binary layout

The BLOB contains only consecutive packed values.

For:

```sql
pblob_pack('[1.0, 2.0]', '<f4')
```

the resulting bytes are:

```text
00 00 80 3F  00 00 00 40
```

For big-endian:

```sql
pblob_pack('[1.0, 2.0]', '>f4')
```

the resulting bytes are:

```text
3F 80 00 00  40 00 00 00
```

For:

```sql
pblob_pack('[-1, 0, 127, -128]', 'int8')
```

the bytes are:

```text
FF 00 7F 80
```

No metadata is embedded:

* No element count
* No type identifier
* No byte-order marker
* No version field
* No checksum
* No alignment padding

The caller or database schema is responsible for knowing the format.

---

### 8. Empty values and SQL NULL

Recommended behavior:

```sql
pblob_pack('[]', '<f2')
```

returns a zero-length BLOB:

```sql
x''
```

And:

```sql
pblob_unpack(x'', '<f2')
```

returns:

```json
[]
```

SQL NULL should propagate:

```sql
pblob_pack(NULL, '<f2')      -- NULL
pblob_pack('[1]', NULL)      -- NULL
pblob_unpack(NULL, '<f2')    -- NULL
pblob_unpack(x'0000', NULL)  -- NULL
```

This follows normal SQLite scalar-function behavior and makes the functions convenient in expressions.

Malformed non-NULL values should produce errors rather than NULL.

---

### 9. BLOB length validation

`pblob_unpack()` must require:

```text
length(blob) % element_size == 0
```

Examples:

```sql
pblob_unpack(x'00', '<f2')
```

Error:

```text
pblob_unpack: BLOB length 1 is not divisible by element size 2 for format <f2
```

For `int8`, every BLOB length is structurally valid.

---

### 10. Result JSON representation

`pblob_unpack()` should return compact canonical JSON text:

```json
[1,-2,3]
```

not:

```json
[ 1, -2, 3 ]
```

Integer values should have integer syntax:

```json
[-128,0,127]
```

Floating-point values should have JSON numeric syntax sufficient to recover the represented target value.

For example:

```json
[1.0,1.5,-0.0]
```

Important formatting properties:

* Locale-independent decimal point.
* No thousands separators.
* No unnecessary whitespace.
* Exponents use JSON-compatible notation.
* Negative zero should preferably be emitted as `-0.0`.
* The decimal representation should round-trip back to the same `f2` or `f4` bit pattern when repacked.

The last requirement is especially important. The formatter should emit the shortest decimal that round-trips to the original binary value, rather than a fixed number of decimal places.

---

### 11. Error categories

Errors should be deterministic and distinguishable by text.

Recommended categories:

#### Unknown format

```text
pblob_pack: unsupported format "f16"
```

#### Invalid JSON

```text
pblob_pack: malformed JSON
```

Where possible, include the parser offset:

```text
pblob_pack: malformed JSON at byte 12
```

#### Wrong top-level JSON type

```text
pblob_pack: expected a JSON array
```

#### Invalid element type

```text
pblob_pack: element 4 is null; expected a number
```

```text
pblob_pack: element 4 is a string; expected a number
```

#### Integer range error

```text
pblob_pack: element 4 value 128 is outside the int8 range
```

#### Integer type error

```text
pblob_pack: element 4 is not an integer
```

#### Floating-point overflow

```text
pblob_pack: element 4 is outside the finite range of f2
```

#### Invalid BLOB length

```text
pblob_unpack: BLOB length 5 is not divisible by element size 2 for format <f2
```

#### Non-finite unpacked value

```text
pblob_unpack: element 4 is not representable in JSON: infinity
```

The element index should be zero-based if `pblob_get()` will also use zero-based indexing.

---

### 12. Function naming

I recommend a short, collision-resistant prefix.

Preferred:

```text
pblob_pack
pblob_unpack
pblob_count
pblob_is_valid
pblob_get
```

Alternative prefix:

```text
packed_pack
packed_unpack
```

`pblob_*` is clearer and less likely to collide with existing extensions.

Avoid overly generic names such as:

```text
pack
unpack
encode
decode
```

SQLite applications often load several extensions, and global SQL function names share one namespace.

---

### 13. Database usage pattern

Because the BLOB is headerless, store or constrain its type at the schema level.

Example:

```sql
CREATE TABLE embeddings (
    region_id INTEGER PRIMARY KEY,
    vector_format TEXT NOT NULL
        CHECK (vector_format IN ('int8', '<f2', '>f2', '<f4', '>f4')),
    vector BLOB NOT NULL,
    CHECK (pblob_is_valid(vector, vector_format))
);
```

When every row uses the same representation, do not redundantly store the format:

```sql
CREATE TABLE embeddings_f16 (
    region_id INTEGER PRIMARY KEY,
    vector BLOB NOT NULL,
    CHECK (length(vector) % 2 = 0)
);
```

Usage:

```sql
INSERT INTO embeddings_f16(region_id, vector)
VALUES (101, pblob_pack('[0.25, -0.5, 1.0]', '<f2'));
```

```sql
SELECT pblob_unpack(vector, '<f2')
FROM embeddings_f16
WHERE region_id = 101;
```

For fixed-dimensional embeddings, constrain the exact byte length:

```sql
CREATE TABLE embeddings_768_f16 (
    region_id INTEGER PRIMARY KEY,
    vector BLOB NOT NULL CHECK (length(vector) = 768 * 2)
);
```

That is preferable to repeatedly decoding or counting the array.

---

### 14. Determinism and SQLite function flags

The functions should be designed as deterministic and side-effect-free.

Conceptually:

| Function         | Deterministic | Innocuous |
| ---------------- | ------------: | --------: |
| `pblob_pack`     |           Yes |       Yes |
| `pblob_unpack`   |           Yes |       Yes |
| `pblob_count`    |           Yes |       Yes |
| `pblob_is_valid` |           Yes |       Yes |
| `pblob_get`      |           Yes |       Yes |

That permits their use in:

* CHECK constraints
* Generated columns
* Expression indexes, where appropriate

The implementation should not depend on:

* Host locale
* Host floating-point print settings
* Native host endianness
* Process-global rounding-mode changes
* Environment variables

---

### 15. Resource limits

The extension should protect against pathological input.

Recommended checks:

* Reject output sizes exceeding SQLite’s current length limit.
* Check multiplication overflow before allocating:

```text
element_count * element_size
```

* Build output in one allocation when the count is known.
* Do not recurse through JSON.
* Reject nested arrays immediately.
* Avoid producing an intermediate array of SQLite values.
* For unpacking, pre-estimate JSON output conservatively and grow safely.

The implementation must work correctly for an empty array and very large arrays up to SQLite’s configured limits.

---

### 16. Version 1 scope

A disciplined first version should contain:

```sql
pblob_pack(json_array, format)
pblob_unpack(blob, format)
pblob_count(blob, format)
pblob_is_valid(blob, format)
```

Supported formats:

```text
int8
<f2
>f2
<f4
>f4
```

Explicitly excluded from version 1:

* Unsigned integers
* `int16`, `int32`, or `int64`
* `float64`
* `bfloat16`
* Native-endian formats
* Strides
* Multidimensional shapes
* Embedded headers
* Compression
* Base64
* NaN/infinity substitution modes
* Mutation or slicing
* Vector arithmetic
* JSON objects containing metadata
* Automatic type inference

This scope is small enough to implement and test rigorously.

---

### 17. Test specification before implementation

The test suite should be written from the contract, not from the eventual implementation.

#### Round-trip tests

For each format:

```sql
pblob_unpack(pblob_pack(json, format), format)
```

Test:

* Empty arrays
* One element
* Multiple elements
* Boundary values
* Negative values
* Signed zero
* Subnormals
* Values requiring rounding

#### Exact byte tests

Examples:

```text
[1.0] <f4 => 00 00 80 3F
[1.0] >f4 => 3F 80 00 00
[-1] int8 => FF
[-128,127] int8 => 80 7F
```

#### `int8` boundaries

Valid:

```text
-128
127
```

Invalid:

```text
-129
128
1.0
null
true
"1"
```

#### `f2` boundaries

Test:

* `65504`
* Values just below and above maximum finite
* Smallest normal
* Subnormal values
* Values that round to zero
* Positive and negative zero
* Halfway rounding cases

#### Malformed BLOBs

Test every invalid remainder:

* One-byte BLOB for `f2`
* One-, two-, and three-byte BLOBs for `f4`

#### Non-finite bit patterns

Feed manually constructed BLOBs containing:

* Positive infinity
* Negative infinity
* Several NaN payloads

Confirm that `pblob_unpack()` rejects them.

#### Endianness independence

Tests must use fixed expected byte strings so they catch accidental use of host-native byte order.

#### NULL propagation

Test every nullable argument position.

#### Large arrays

Verify:

* Allocation safety
* Correct byte length
* No quadratic behavior
* Correct operation near configured SQLite limits

---

### 18. Important design decision: raw versus self-describing BLOB

There are two possible extension models.

#### Raw BLOB, recommended

```sql
pblob_pack(json, '<f2')
pblob_unpack(blob, '<f2')
```

Advantages:

* Zero storage overhead
* Direct compatibility with Arrow-style primitive buffers
* Easy ingestion by Python, NumPy, C, Rust, and other systems
* Endianness is explicit
* No proprietary file structure

Disadvantage:

* The format must be known externally.

#### Self-describing BLOB

The BLOB contains a header with type and count.

Advantages:

* Safer when values are passed without schema context.

Disadvantages:

* Storage overhead
* Proprietary representation
* Harder interoperability
* Requires versioning and header validation
* Prevents the BLOB from being directly interpreted as a primitive array

For embedding and numeric-column storage, the raw representation is the better design.

---

### 19. Recommended definitive version 1 contract

The extension can be summarized as follows:

> `pblob_pack()` converts a JSON array of numeric scalars into a headerless contiguous BLOB using an explicitly specified primitive representation. `pblob_unpack()` performs the inverse conversion and returns valid compact JSON. Conversion is strict: invalid element types, integer overflow, floating-point overflow, malformed BLOB lengths, and non-finite floating-point values produce SQL errors. SQL NULL propagates. Empty arrays map to zero-length BLOBs. Endianness is always explicit for multi-byte formats.

The main unresolved implementation-level choice is how the extension parses JSON: by using SQLite’s JSON parser facilities, if suitably available to extensions, or by embedding a small dedicated parser. That choice should not change the SQL contract above.

---
---

## 📗 int8 Format

> [!NOTE] Prompt
> 
> When embedding are quantized to int8, are they normally signed?

Usually, yes. **Int8-quantized embeddings are normally stored as signed 8-bit integers**, with values in:

```text
-128 to 127
```

The common scheme is symmetric quantization:

```text
q[i] = round(x[i] / scale)
```

with dequantization:

```text
x[i] ≈ q[i] * scale
```

Often the effective range is deliberately limited to:

```text
-127 to 127
```

so that positive and negative magnitudes are symmetric and `-128` is unused.

There are also asymmetric schemes:

```text
x[i] ≈ (q[i] - zero_point) * scale
```

These may use either signed `int8` or unsigned `uint8`, but unsigned storage is more common for activations or image tensors than for centered embedding vectors.

For an SQLite packed-embedding extension, `int8` should therefore mean signed two’s-complement bytes. You will also need to decide where the quantization metadata lives:

- one scale per vector,
- one global scale for the entire embedding model,
- or one scale per dimension/block.

A raw `int8` BLOB alone is not sufficient to reconstruct approximate floating-point values unless the scale and, for asymmetric quantization, the zero point are known.

---
---

## 📗 float16 Format

> [!NOTE] Prompt
> 
> Same question about binary16 vs bf16

For **stored embedding vectors**, IEEE binary16 (`float16`, `f16`, `f2`) is generally the more conventional interchange/storage type than `bfloat16`.

The difference is:

| Type            | Exponent bits | Fraction bits | Main advantage           |
| --------------- | ------------: | ------------: | ------------------------ |
| binary16 / FP16 |             5 |            10 | Better precision         |
| bfloat16        |             8 |             7 | Much wider numeric range |

Both occupy 2 bytes. BF16 preserves roughly the exponent range of FP32, while FP16 provides substantially more significand precision. ([PyTorch Docs][1])

For embeddings, especially normalized embeddings whose components are normally small and bounded, **dynamic range is rarely the limiting factor**. Precision is more valuable because cosine similarity and dot products aggregate small coordinate-level errors. Therefore:

* **FP16 is normally preferable for persistent embeddings.**
* **BF16 is more commonly selected for model inference or training**, where intermediate activations may need FP32-like dynamic range and overflow resistance.
* A model may compute or emit tensors in BF16 because that is its inference dtype, but that does not make BF16 the best packed storage representation.

So your initial extension formats:

```text
<f2
>f2
```

should mean **IEEE 754 binary16**, matching NumPy `float16` and Python `struct` format `e`.

I would not make `f2` mean BF16. Add BF16 later under an explicit, unambiguous name:

```text
<bf2
>bf2
```

or preferably:

```text
<bf16
>bf16
```

There is no universally useful “native endian” BF16 form for a portable packed BLOB.

One caveat: if you are storing the model’s output with no conversion and the serving backend produces BF16, converting it to FP16 can overflow only when component magnitudes exceed FP16’s range. That is extraordinarily unlikely for ordinary embeddings, particularly L2-normalized vectors. Precision should generally improve rather than degrade because FP16 has 10 fraction bits versus BF16’s 7.

[1]: https://docs.pytorch.org/docs/stable/tensor_attributes.html "Tensor Attributes — PyTorch 2.13 documentation"

---
---

## 📗 Code Sourcing

> [!NOTE] Prompt
> 
> SQLite JSON module doesn't handle all data types, but it implements binary - text conversion, so I suppose most of the code for this extension can be adapted and glued snippets from SQLite JSON.c

Yes, **much of the machinery is conceptually reusable**, but directly adapting `src/json.c` is practical mainly when your extension is compiled **into the SQLite amalgamation**, not as a conventional independent loadable extension.

`json.c` already contains the difficult infrastructure you need:

* Parsing JSON text and JSON5 numeric syntax.
* Traversing arrays without materializing SQL rows.
* Distinguishing integer and floating-point elements.
* Numeric text-to-`sqlite3_int64` / `double` conversion.
* Dynamically constructing text output.
* Correct JSON numeric rendering.
* Allocation-limit and overflow handling.
* Detailed malformed-JSON detection.
* Accepting both JSON text and SQLite JSONB input.

SQLite’s current JSON implementation is built into SQLite by default and lives in `src/json.c`; JSONB is its internal parse-tree representation and can be supplied to ordinary JSON functions in place of text JSON. ([SQLite][1])

### The important limitation

Most useful `json.c` functions and structures are internal and `static`. They are not part of the public loadable-extension API.

A separately compiled extension cannot simply call things such as the internal JSON parser, node decoder, or text builder through `sqlite3ext.h`. You would have three architectural choices.

### 1. Compile the packed-array code into SQLite

This is the cleanest option for your custom SQLite build.

Your module can be compiled as part of the amalgamation, and selected internal JSON routines can be exposed or shared. Since you are already building a custom SQLite with extra extensions, this is likely the best design.

I would avoid copying large pieces of `json.c`. Instead, introduce a **small internal interface** used by both `json.c` and the packed-array module.

Conceptually:

```c
int sqlite3JsonArrayOpen(
    sqlite3_context *,
    sqlite3_value *,
    JsonParse *
);

int sqlite3JsonArrayNextNumber(
    JsonParse *,
    JsonArrayCursor *,
    int *numericType,
    sqlite3_int64 *integerValue,
    double *realValue
);
```

The precise interface should follow the current internal structures rather than inventing a parallel parser.

Advantages:

* Accepts text JSON and JSONB.
* Uses exactly SQLite’s JSON syntax and error rules.
* Avoids embedding another JSON parser.
* Avoids SQL-level `json_each()` overhead.
* Tracks upstream JSON behavior.

Disadvantage:

* Requires a maintained SQLite source patch.
* Internal JSON structures can change between SQLite releases.

### 2. Include copied portions of `json.c`

This can make a standalone extension possible, but it is less attractive than it initially appears.

You would need to extract and adapt:

* Parser structures.
* JSON/JSONB element decoding.
* Numeric conversion.
* String builder.
* Error handling.
* Supporting macros and utility functions.

Those pieces depend on SQLite internals that are unavailable to a normal extension. After extraction, many calls would need replacement with public API equivalents.

At that point, you effectively maintain a forked miniature JSON implementation. You also need to track upstream fixes and ensure compatibility with SQLite’s JSON5 and JSONB behavior.

SQLite explicitly describes JSONB as an internal SQLite representation even though its format is documented and intended to remain portable and backward-compatible. Applications are expected to use it through SQLite’s JSON functions rather than independently manipulating its bytes. ([SQLite][1])

### 3. Use public JSON SQL facilities

A loadable extension can invoke:

```sql
json_each(?)
```

through a prepared statement, or require callers to aggregate values through a virtual table.

That would work but is the wrong implementation for a compact conversion primitive:

* One virtual-table row per array element.
* Repeated SQL value construction.
* More allocations.
* Statement preparation and VM execution.
* Difficult error attribution.
* Poor fit for vectors with hundreds or thousands of dimensions.

It is useful as a reference implementation and test oracle, not as the final fast path.

### What should actually be reused

There are two separate directions.

#### JSON or JSONB to packed BLOB

Reuse the input-side parser and array traversal logic from `json.c`:

```text
sqlite3_value
    ↓
text JSON or JSONB recognition
    ↓
root element validation
    ↓
array child traversal
    ↓
numeric classification/conversion
    ↓
target packing
```

The new code only needs to provide the final numeric conversion:

```text
JSON integer → int8 validation → one byte
JSON number  → double → binary16 conversion → two bytes
JSON number  → double → binary32 conversion → four bytes
```

For `f4`, do not merely cast and copy a native `float`. Explicitly generate the IEEE binary32 bits and write the requested byte order. That removes dependence on host representation and host endianness.

For `f2`, you need a correct binary64-to-binary16 conversion routine. `json.c` will not provide that.

#### Packed BLOB to JSON text

Reuse the output-side string accumulator and numeric renderer:

```text
packed element bits
    ↓
int8 / binary16 / binary32 decode
    ↓
sqlite3_int64 or double
    ↓
SQLite JSON numeric renderer
    ↓
JSON text accumulator
```

This is especially useful for:

* Locale-independent formatting.
* Sufficient precision.
* Proper handling of `-0.0`.
* Allocation growth.
* SQLite length limits.
* Returning text with the JSON subtype.

However, you still need to define whether the output must be a **bitwise round-trip representation** for the source `f2` or `f4`. SQLite’s normal double formatter may emit enough digits to round-trip a binary64 value, which is sufficient but not always the shortest representation for the original narrower type.

That is correct but may produce unnecessarily long JSON:

```json
[0.0999755859375]
```

rather than a shorter decimal that still rounds back to the same FP16 value.

For a first version, correctness is more important than narrow-type shortest formatting.

### Better internal architecture

I would not make `pblob.c` directly understand the entire private `JsonParse` representation.

Instead, split out a narrow reusable internal layer:

```text
src/json.c
    owns parsing, JSONB decoding and JSON rendering

src/jsonapi.c or selected non-static json.c functions
    exposes internal array/numeric traversal and rendering helpers

ext/misc/pblob.c
    owns format parsing and primitive binary conversion
```

Possible internal abstractions:

```c
typedef struct JsonArrayReader JsonArrayReader;
typedef struct JsonTextWriter JsonTextWriter;
```

Reader operations:

```c
int sqlite3JsonArrayReaderInit(
    JsonArrayReader *,
    sqlite3_context *,
    sqlite3_value *
);

int sqlite3JsonArrayReaderNext(
    JsonArrayReader *,
    int *type,
    sqlite3_int64 *iValue,
    double *rValue
);

sqlite3_uint64 sqlite3JsonArrayReaderCount(
    const JsonArrayReader *
);
```

Writer operations:

```c
int sqlite3JsonWriterInit(JsonTextWriter *, sqlite3_context *);
int sqlite3JsonWriterAppendInt64(JsonTextWriter *, sqlite3_int64);
int sqlite3JsonWriterAppendDouble(JsonTextWriter *, double);
void sqlite3JsonWriterFinishArray(JsonTextWriter *);
```

These are internal APIs, not public SQLite interfaces.

This boundary isolates your extension from most changes in `json.c`.

### A potentially simpler initial implementation

Since your accepted input is only a flat homogeneous numeric array, the full JSON parse tree is more machinery than necessary.

The fastest initial implementation may be a **specialized streaming numeric-array parser**, adapted from the lexical and numeric routines in `json.c`, supporting:

```text
whitespace
[
number
,
number
]
```

and rejecting everything else.

That parser can:

1. Validate the opening `[`.
2. Parse one number.
3. Immediately pack it into the output buffer.
4. Continue until `]`.
5. Reject strings, objects, nested arrays, null and booleans.

Advantages:

* Very little code.
* No parse tree.
* No per-element allocations.
* Single pass.
* Exact output-size growth.
* Easy error indexing.

Disadvantages:

* Does not automatically accept SQLite JSONB.
* Must independently track SQLite JSON5 behavior if desired.
* Duplicates a small amount of numeric parsing logic.

Because arrays will commonly come from an embeddings API as JSON text, JSONB support may not initially matter. But accepting both text JSON and JSONB would make the extension behave consistently with modern SQLite JSON functions.

### My recommendation for your build

Given that you already control the SQLite amalgamation:

1. Build `pblob.c` into SQLite rather than treating it as a fully independent extension.
2. Reuse `json.c`’s parsing and rendering implementation through a very small internal interface.
3. Keep all binary packing, byte-order handling, FP16 conversion and format parsing in `pblob.c`.
4. Avoid copying the complete JSON parser.
5. Keep the packed format completely independent of SQLite JSONB.
6. Support both JSON text and JSONB as input if the internal interface makes that inexpensive.

So the code division becomes:

```text
json.c:
    JSON text/JSONB → typed numeric array iteration
    integer/double → JSON text generation

pblob.c:
    format string parsing
    target range checking
    int8 packing
    binary16 conversion
    binary32 conversion
    byte-order encoding/decoding
    BLOB length validation
    SQL function registration
```

That is substantially less work than writing an extension from scratch, but it is not merely gluing together existing text-to-BLOB conversion snippets: **the numeric binary representation logic is new**, while JSON syntax handling and JSON rendering are the reusable portions.

[1]: https://www.sqlite.org/json1.html "JSON Functions And Operators"

---
---

## 📗 SQLite AutoExtenstion

> [!NOTE] Prompt
> 
> The extension will be an auto extension compiled solely as part of amalgamation with enabled json

That changes the design materially. Since the extension is:

* compiled only as part of the amalgamation,
* registered as an auto-extension,
* built only when SQLite JSON support is enabled,

it can deliberately depend on SQLite internals and reuse code from `json.c`. There is no need to design it as a portable loadable extension or create a public JSON API.

Assuming “lson” means **JSON**, the extension should be conditionally compiled alongside `json.c`.

### Recommended architecture

Create one amalgamation source module, for example:

```text
ext/misc/packedblob.c
```

It should contain:

1. SQL function registration.
2. Format-string parsing.
3. JSON-array validation and numeric iteration.
4. `int8` range checking and packing.
5. binary16 encode/decode.
6. binary32 encode/decode.
7. endian-independent byte reads and writes.
8. JSON-array output generation.

Because amalgamation concatenates the source files into one translation unit, `packedblob.c` can potentially use `static` definitions from `json.c`, provided:

* `json.c` appears earlier in the amalgamation,
* the relevant declarations and types are visible at that point,
* names and implementations match the SQLite version being amalgamated.

That is a legitimate internal integration strategy for a source module tied to one SQLite source tree.

### Do not introduce an abstraction layer prematurely

My earlier suggestion of creating an internal JSON reader/writer API would be unnecessary unless you intend to maintain `packedblob.c` independently across many SQLite releases.

For an amalgamation-only extension, the simpler plan is:

```text
json.c internal parser/writer machinery
                ↓
packedblob.c conversion functions
```

You can adapt or invoke the exact internal routines available in the SQLite version being built.

The module should be considered part of your SQLite fork, not an external extension with a stable dependency boundary.

### Source ordering

The amalgamation order should conceptually be:

```text
...
src/json.c
...
ext/misc/packedblob.c
...
```

Then the packed-blob module may use JSON structures and functions defined earlier in the translation unit.

If the extension source is concatenated before `json.c`, you would need declarations or copied type definitions, which would be brittle and unnecessary.

### Conditional compilation

Use the same compile-time exclusion condition as SQLite JSON support.

Conceptually:

```c
#ifndef SQLITE_OMIT_JSON
/* packed-blob implementation */
#endif
```

The exact guard should follow the current SQLite source configuration.

Since the module has no useful non-JSON mode, do not register stub functions when JSON is omitted. Simply omit the entire extension.

### Auto-extension entry point

The module should expose one initializer, for example:

```text
sqlite3PackedBlobInit
```

and your existing extra-auto-extension dispatcher should call it.

Conceptually:

```text
sqlite3ExtraAutoExtInit()
    → sqlite3PackedBlobInit()
```

Because it is statically compiled into SQLite:

* no `sqlite3_extension_init`,
* no `sqlite3ext.h`,
* no `SQLITE_EXTENSION_INIT1`,
* no dynamic loading machinery,
* no exported DLL symbol is required.

The initializer should use internal or public registration functions available inside the core, most likely `sqlite3_create_function_v2()` or its internal equivalent.

### What to adapt from `json.c`

There are two useful portions.

#### JSON input handling

Adapt the path used by SQLite JSON functions to obtain a parsed representation from:

* JSON text,
* SQLite JSONB.

Then require that the root value is an array and iterate its immediate children.

For every child, classify it as:

```text
integer
real
anything else → error
```

Do not recursively process nested values.

This gives you SQLite-consistent handling of:

* malformed JSON,
* JSON5 accepted by SQLite,
* JSONB,
* numeric syntax,
* integer versus real classification,
* whitespace,
* parse errors.

#### JSON output handling

Use or adapt SQLite’s internal JSON string accumulator to emit:

```text
[
number,
number,
...
]
```

This provides:

* SQLite allocator use,
* length-limit enforcement,
* locale-independent output,
* correct result ownership,
* JSON subtype assignment,
* established error propagation.

### Likely code reuse pattern

You may not even need to modify `json.c`. Since both files are in the same amalgamation translation unit, a function marked `static` in `json.c` remains callable from code that appears later in that same translation unit.

For example, if `json.c` defines:

```c
static SomeType jsonSomeFunction(...);
```

then `packedblob.c`, concatenated afterward, can call it.

`static` gives internal linkage; it does not restrict visibility to the original source fragment after the files have been concatenated.

This is one of the important advantages of your amalgamation-only design.

However, structures or helper functions hidden inside narrower preprocessor blocks may still be unavailable. Source ordering and guards must match.

### Copy versus direct calls

Use this rule:

#### Directly call JSON internals when they provide

* parsed JSON/JSONB acquisition,
* array traversal,
* integer extraction,
* real extraction,
* JSON output buffering,
* JSON numeric rendering.

#### Copy and adapt only small self-contained snippets when

* the original helper is inseparable from a JSON-specific code path,
* calling it would require manufacturing unnatural parser state,
* a specialized flat-array loop would be substantially simpler,
* the copied code is stable and easy to audit.

Avoid copying the complete JSON parser. There is no reason to maintain two parsers inside the same amalgamation.

### Narrow first-version API

Given this architecture, I would initially implement only:

```sql
packed_blob(json_array, format) → BLOB
packed_json(blob, format)       → JSON
```

Possibly with a shorter prefix:

```sql
pblob(json_array, format)
pjson(blob, format)
```

But explicit paired names are clearer:

```sql
pblob_pack(json_array, format)
pblob_unpack(blob, format)
```

Supporting functions such as count and validation can be added after the core conversion paths are proven.

### Formats

Keep the initial grammar exact:

```text
int8
<f2
>f2
<f4
>f4
```

Internally, parse once into an enum-like descriptor:

```text
kind          int8 | binary16 | binary32
element_size  1 | 2 | 4
byte_order    irrelevant | little | big
```

Do not repeatedly compare the format string inside the element loop.

### JSON numeric rules

With SQLite’s JSON parser available, the clean contract is:

#### `int8`

Accept only JSON values classified by SQLite as integer, within:

```text
-128..127
```

Reject JSON real values even when mathematically integral:

```json
[1.0]
```

This preserves the homogeneous scalar-type rule and avoids implicit float-to-integer conversion.

#### `f2` and `f4`

Accept both JSON integer and real values.

Convert:

```text
integer → double → target float encoding
real    → double → target float encoding
```

Reject finite overflow to infinity.

Normal rounding is allowed.

### Output JSON

When unpacking:

* `int8` elements are emitted as JSON integers.
* `f2` and `f4` elements are decoded and emitted through SQLite’s JSON real-number writer.
* NaN and infinity should produce an error because neither is representable as a JSON number.
* The result should have SQLite’s JSON subtype.

### Important consequence of using SQLite JSON internals

The input should support both:

```sql
pblob_pack('[1,2,3]', 'int8')
```

and:

```sql
pblob_pack(jsonb('[1,2,3]'), 'int8')
```

without any separate extension logic.

That is worth preserving. Do not reduce the implementation to text-only parsing unless the relevant internal parse interface proves unusually awkward.

### Revised implementation plan

#### Phase 1: inspect the selected SQLite `json.c`

Identify the exact internal facilities for:

* converting `sqlite3_value` into the JSON parse representation,
* identifying the root type,
* traversing direct array children,
* reading integer and real nodes,
* initializing and growing JSON output,
* appending integer and real values,
* finalizing a JSON SQL result.

The design should be based on those actual definitions, not invented wrapper APIs.

#### Phase 2: implement binary primitives independently

Write and test:

* signed `int8` byte conversion,
* `double` to IEEE binary16,
* IEEE binary16 to `double`,
* `double` to binary32 with overflow detection,
* binary32 to `double`,
* explicit little-endian and big-endian reads/writes.

These should not rely on host byte order.

#### Phase 3: glue JSON traversal to packing

One pass over the JSON array:

```text
validate root
determine element count
check allocation size
allocate exact BLOB
iterate children
validate and encode each child
return BLOB
```

If the parsed representation exposes the child count cheaply, allocate the final BLOB once.

#### Phase 4: glue unpacking to JSON generation

```text
validate BLOB type and length
initialize JSON writer
append '['
decode each element
append JSON number
append ']'
return JSON-subtyped text
```

#### Phase 5: register as a core auto-extension

Register deterministic and innocuous scalar functions through your amalgamation auto-extension dispatcher.

The resulting extension is intentionally version-coupled to the SQLite source tree, which is appropriate here.

---
---

## 📗 SQL-only Surface

> [!NOTE] Prompt
> 
> The extension will not provide any public c API, only registered sql functions

Correct. Then the design should be strictly SQL-facing.

There is no need for:

* exported C symbols beyond the internal initializer,
* public headers,
* stable C ABI,
* `sqlite3ext.h`,
* loadable-extension entry points,
* reusable C helper API,
* external callers into the packing code.

The only externally visible contract is the registered SQL function set.

### Internal structure

The module can remain a single amalgamation source unit with private `static` helpers:

```text
format parsing
JSON array traversal
numeric validation
int8 packing
binary16 conversion
binary32 conversion
endianness helpers
JSON result construction
SQL callbacks
initializer
```

Everything except the initializer should be `static`.

Conceptually:

```text
static void pblobPackFunc(...);
static void pblobUnpackFunc(...);

static int pblobParseFormat(...);
static int pblobEncodeF16(...);
static double pblobDecodeF16(...);
...
```

The initializer only registers SQL functions:

```text
sqlite3PblobInit(db)
```

It does not expose conversion operations to other C modules.

### Recommended SQL surface

For version 1, I would keep it to two functions:

```sql
pblob_pack(json_array, format) → BLOB
pblob_unpack(blob, format)     → JSON
```

That is sufficient for the core purpose.

Examples:

```sql
SELECT pblob_pack('[1,2,-3]', 'int8');

SELECT pblob_unpack(value, '<f2')
FROM embeddings;
```

Additional SQL functions should only be added when they provide operations that cannot be done cheaply with ordinary SQLite expressions.

For example, count does not justify a separate function:

```sql
length(blob)               -- int8 count
length(blob) / 2           -- f2 count
length(blob) / 4           -- f4 count
```

Likewise, structural validation can usually be expressed with `length()` constraints.

### Registration flags

Both functions should be registered as:

```text
SQLITE_UTF8
SQLITE_DETERMINISTIC
SQLITE_INNOCUOUS
```

They should not be marked `SQLITE_DIRECTONLY`, because deterministic conversion functions are useful in:

* CHECK constraints,
* generated columns,
* expression indexes,
* views,
* triggers.

### Argument contract

#### `pblob_pack(json_array, format)`

Argument 1:

* JSON text or JSONB.
* SQL `NULL` returns `NULL`.
* Root must be an array.
* Elements must be numeric scalars.
* Nested arrays, objects, strings, booleans and JSON null are errors.

Argument 2:

* Exact text format name.
* SQL `NULL` returns `NULL`.

#### `pblob_unpack(blob, format)`

Argument 1:

* Must be a BLOB.
* SQL `NULL` returns `NULL`.
* Zero-length BLOB is valid and returns `[]`.

Argument 2:

* Exact text format name.
* SQL `NULL` returns `NULL`.

The returned text should have the JSON subtype set so it behaves as JSON when passed into SQLite JSON functions.

### Type strictness

Do not coerce arbitrary SQLite values.

For packing:

```sql
pblob_pack(123, 'int8')
```

should fail because the first argument is not JSON text or JSONB containing an array.

For unpacking:

```sql
pblob_unpack('abcd', 'int8')
```

should fail because the first argument is TEXT, not BLOB.

That prevents accidental reinterpretation caused by SQLite affinity.

### Internal use of `json.c`

Because the module is amalgamation-only, it may directly use private JSON internals available earlier in the translation unit. That does not make those internals part of your extension’s public API.

The dependency is entirely internal:

```text
SQL caller
   ↓
pblob SQL callback
   ↓
private json.c parser/writer helpers
   ↓
private binary conversion helpers
```

No new general-purpose JSON C interface needs to be introduced.

### Naming consideration

Because there is no C API, the SQL names deserve particular care. I would use the explicit pair:

```sql
pblob_pack(...)
pblob_unpack(...)
```

They clearly communicate direction and leave room for future functions such as:

```sql
pblob_get(...)
pblob_slice(...)
pblob_convert(...)
```

without committing to those now.

The extension can therefore be defined as:

> An amalgamation-only SQLite auto-extension, enabled only when JSON support is present, exposing deterministic SQL scalar functions that convert between flat numeric JSON arrays and raw packed numeric BLOBs. All implementation details and JSON integration remain private to the amalgamation.

---
---

## 📗 Libraries

> [!NOTE] Prompt
> 
> I do not need take json and jsonb. I need to take the one that it more convinient and let json.c handle conversion. The overall strategy is to minimize the amount of new code, especially perfoming core data conversion. I need a robust means to verify input json, and the other critical part is parsing and data conversion. Perhaps there are tiny open source, ideally available as integratable single pair of x.c/x.h modules, well established actively developed project(s) that can provide functionality not available from json.c or possibly other core modules? ( I only care about int8 and IEEE 754 binary f2/f4 with endianness, no other binary types)

Yes. Under your constraints, the minimal design is:

1. Require **JSONB** as the SQL input representation.
2. Use `json.c` internals for validation, array traversal, numeric classification, decimal parsing, and JSON output.
3. Add one small external dependency only for binary16 conversion.
4. Implement endianness locally with a few byte shifts.
5. Use ordinary C conversion for binary32.

### Use JSONB as the input contract

Define:

```sql
pblob_pack(jsonb_array, format) -> BLOB
```

The caller converts text JSON explicitly:

```sql
SELECT pblob_pack(jsonb('[1.0, 2.0, 3.0]'), '<f2');
```

This is preferable to accepting text JSON directly because SQLite’s JSON functions already use JSONB as their internal processing representation. Supplying JSONB bypasses the text-to-JSONB parsing stage. ([SQLite][1])

It also gives you a clean type distinction:

* `BLOB` containing valid JSONB: input array.
* `TEXT`: rejected.
* Ordinary BLOB: rejected as malformed JSONB.
* `NULL`: propagated.

The extension still must perform deep traversal and validation. SQLite documents that `jsonb()` itself only examines the outermost element when its input already appears to be JSONB, so merely receiving the output of `jsonb()` is not by itself proof that every nested element is structurally valid. ([SQLite][1])

However, your traversal through the existing `json.c` machinery naturally validates every array element that you consume.

### Why JSONB is especially suitable here

SQLite JSONB is already a contiguous sequence of typed elements. Each element carries a type and payload length, and an array payload consists directly of its child JSONB elements. Numeric payloads remain textual and are converted only when needed. ([SQLite][2])

Your packing loop can therefore be approximately:

```text
obtain validated root JSONB element
require ARRAY
walk direct child elements
    require INT/INT5 for int8
    require numeric element for f2/f4
    invoke SQLite numeric conversion
    encode result
```

You do not need:

* a second JSON parser,
* tokenization code,
* nested-array parsing,
* string escape handling,
* decimal-to-double conversion,
* JSON5 number handling,
* custom JSON syntax diagnostics.

### Best external component: Maratyszcza/FP16

The strongest fit is **Maratyszcza/FP16**.

It is:

* header-only,
* C99-compatible,
* MIT licensed,
* specifically limited to conversion to and from half-precision formats,
* tested for denormals, infinities, and NaNs,
* covered by unit tests and microbenchmarks,
* still actively maintained, including changes in 2025 and 2026. ([Chromium Git Repositories][3])

The primary header provides IEEE binary16 ↔ binary32 conversions. Conceptually, the useful operations are:

```c
uint16_t fp16_ieee_from_fp32_value(float value);
float fp16_ieee_to_fp32_value(uint16_t bits);
```

The result of the encoding function is the **binary16 bit pattern in a `uint16_t`**, not a native half object. That is exactly what your packed-BLOB extension needs.

You can vendor only the required headers, likely:

```text
fp16/fp16.h
fp16/bitcasts.h
```

Possibly also the small macro header required by the selected revision. It is not an `x.c/x.h` pair, but header-only is even easier for amalgamation integration.

### Important limitation of FP16

Maratyszcza/FP16 converts:

```text
binary32 ↔ binary16
```

It does not primarily provide:

```text
binary64 ↔ binary16
```

SQLite JSON numeric extraction normally yields a C `double`. Therefore the straightforward packing path is:

```text
JSON decimal
→ SQLite double
→ C float
→ FP16 binary16
```

This introduces an intermediate binary32 rounding.

For embedding data, this is generally the correct semantic path because embeddings conventionally originate as FP32 values before being stored as FP16. It also means that:

```sql
pblob_pack(..., '<f2')
```

should be defined as:

> Convert each JSON number to SQLite REAL, narrow it to IEEE binary32, and then convert binary32 to IEEE binary16 using round-to-nearest-even.

That contract is deterministic and maps cleanly to the available, established conversion library.

#### Double-rounding caveat

A decimal value converted directly to binary16 can, in rare halfway cases, produce a different result from:

```text
decimal → binary64 → binary32 → binary16
```

For actual JSON embeddings produced from FP32 values, this is not a meaningful problem: the JSON decimal is merely a textual representation of an original binary32 number. Reconstructing binary32 before converting to binary16 is appropriate.

If the function is intended as a general mathematically correctly rounded decimal-to-binary16 converter, the FP32 intermediate would be insufficient. You would then need a correct binary64-to-binary16 conversion.

### Berkeley SoftFloat: rigorous but excessive

Berkeley SoftFloat provides `f64_to_f16`, `f64_to_f32`, `f16_to_f64`, explicit rounding behavior, exception handling, and fully software-defined IEEE-754 semantics. The implementation includes direct `f64_to_f16` conversion. ([QEMU][4])

It is robust, but it is not a tiny pair of files. Pulling out `f64_to_f16.c` also pulls in:

* SoftFloat internal types,
* shift-with-jam helpers,
* rounding state,
* NaN specialization,
* platform configuration,
* exception flags,
* several headers and support routines.

For your extension, that would add substantially more code than the extension itself.

I would use SoftFloat only if you require all of the following:

* exact binary64-to-binary16 conversion,
* selectable IEEE rounding modes,
* platform-independent floating-point exception behavior,
* exact NaN payload propagation,
* operation on hosts that cannot be assumed to use IEEE binary32/binary64.

You do not appear to require those.

### Binary32 does not need another library

For `<f4` and `>f4`, use SQLite’s parsed `double`, narrow it to C `float`, and copy the resulting bits into a 32-bit unsigned integer.

Conceptually:

```c
double d = ...;           /* produced by json.c */
float f = (float)d;
uint32_t u;
memcpy(&u, &f, sizeof(u));
```

Then explicitly write the bytes:

```text
little-endian:
u
u >> 8
u >> 16
u >> 24

big-endian:
u >> 24
u >> 16
u >> 8
u
```

For unpacking, reconstruct the `uint32_t`, `memcpy` it into `float`, and promote the `float` to `double` for SQLite’s JSON number renderer.

This is very little new conversion code. The only assumptions are:

```text
sizeof(float) == 4
FLT_RADIX == 2
FLT_MANT_DIG == 24
FLT_MAX_EXP == 128
```

Those identify IEEE-754 binary32 characteristics sufficiently for this application. Reject the build at compile time when they are false.

SQLite itself already assumes common IEEE floating-point behavior in many supported builds, so adding an exotic non-IEEE portability layer would be inconsistent with your goal of minimizing code.

### Endianness does not warrant a dependency

Do not integrate an endian library.

The total required implementation is approximately four tiny helpers:

```text
read_u16_le
read_u16_be
write_u16_le
write_u16_be

read_u32_le
read_u32_be
write_u32_le
write_u32_be
```

These are simple unsigned byte shifts and OR operations. They are:

* independent of host endianness,
* independent of alignment,
* free from strict-aliasing problems,
* easy to test exhaustively,
* smaller than any external dependency.

Do not use direct casts such as:

```c
*(uint32_t *)p
```

because that introduces alignment and aliasing issues.

### `int8` needs no conversion library

For `int8`:

1. Require an SQLite JSONB integer element, not a floating-point element.
2. Convert it through the integer conversion already used by `json.c`.
3. Check:

```text
-128 <= value <= 127
```

4. Store:

```c
output[i] = (unsigned char)(signed char)value;
```

For unpacking, explicitly sign-extend the byte rather than relying on whether plain `char` is signed:

```c
int value = byte < 0x80 ? byte : byte - 0x100;
```

That is portable and unambiguous.

### Use `json.c` for numeric parsing

The most important code not to rewrite is decimal parsing.

JSONB numeric payloads are stored as text, with distinct element types for canonical integers, canonical floating-point numbers, and JSON5 variants. This design deliberately defers numeric conversion until a consumer requests a number. ([SQLite][2])

Therefore, use the same internal routines that existing JSON functions use to obtain:

```text
sqlite3_int64
double
```

Do not:

* call `strtod`,
* call `sscanf`,
* embed fast_float,
* embed yyjson,
* embed dtoa,
* manually recognize exponent syntax,
* manually handle JSON5 hexadecimal numbers.

SQLite already owns this layer.

### Use `json.c` for output too

For unpacking, use SQLite’s JSON output accumulator and number-rendering routines.

That gives you:

* canonical JSON text,
* locale-independent decimal rendering,
* SQLite allocation and length-limit handling,
* correct JSON subtype assignment,
* existing handling of integer and real formatting.

SQLite states that JSON text emitted by its JSON functions is canonical JSON even when input accepts JSON5 extensions. ([SQLite][1])

The result function must be registered with:

```text
SQLITE_RESULT_SUBTYPE
```

in addition to:

```text
SQLITE_UTF8
SQLITE_DETERMINISTIC
SQLITE_INNOCUOUS
```

because functions that call `sqlite3_result_subtype()` must declare that property in current SQLite. ([SQLite][5])

### Recommended dependency boundary

#### From SQLite core/json.c

Reuse directly:

```text
JSONB recognition
root element decoding
array child traversal
deep structural validation during traversal
numeric-type classification
integer text → sqlite3_int64
numeric text → double
JSON output accumulator
integer → JSON text
double → JSON text
error and allocation handling
result subtype
```

#### From Maratyszcza/FP16

Reuse:

```text
IEEE binary32 bits/value → IEEE binary16 bits
IEEE binary16 bits → IEEE binary32 bits/value
```

#### New extension code

Write only:

```text
format parser
SQL argument/type checks
array-homogeneity checks
int8 range checking
double → float narrowing and overflow checks
byte-order reads/writes
BLOB allocation
element loop
SQL function callbacks
registration initializer
```

### Recommended conversion semantics

The cleanest precise contract is:

| Format       | Accepted JSONB numeric elements | Conversion                                                 |
| ------------ | ------------------------------- | ---------------------------------------------------------- |
| `int8`       | Integer elements only           | JSON integer → `sqlite3_int64` → range check → signed byte |
| `<f2`, `>f2` | Integer or real elements        | JSON number → `double` → binary32 → binary16               |
| `<f4`, `>f4` | Integer or real elements        | JSON number → `double` → binary32                          |

For homogeneous input, enforce:

* `int8`: all elements must be JSON integer types.
* `f2`/`f4`: integers and reals may be mixed, because both are converted to the selected floating representation.

If you interpret “all the same type” literally at the JSON syntax level, then `[1,2.0]` would be rejected for `f4`; that adds validation code without improving the packed result. I would instead define homogeneity by the **target packed type**.

### Final recommendation

Use:

```text
SQLite json.c internals
+
Maratyszcza/FP16 header-only library
+
small local endian helpers
```

Do not add a separate general JSON library, decimal parser, float formatter, endian library, or binary serialization library.

The resulting critical path becomes:

```text
JSONB number
→ json.c numeric conversion
→ int8 / C binary32 / FP16 binary16 conversion
→ explicit byte-order write
```

and the inverse:

```text
explicit byte-order read
→ int8 / binary32 / FP16 binary16 decode
→ json.c numeric writer
```

That is likely the smallest robust implementation available without relying on compiler-specific `_Float16` support.

[1]: https://www.sqlite.org/json1.html "JSON Functions And Operators"
[2]: https://sqlite.org/jsonb.html "The SQLite JSONB Format"
[3]: https://chromium.googlesource.com/external/github.com/Maratyszcza/FP16/ "external/github.com/Maratyszcza/FP16 - Git at Google"
[4]: https://qemu.googlesource.com/berkeley-softfloat-3/%2B/refs/heads/master/source/ "source - berkeley-softfloat-3 - Git at Google"
[5]: https://www.sqlite.org/releaselog/3_45_1.html "SQLite Release 3.45.1 On 2024-01-30"
