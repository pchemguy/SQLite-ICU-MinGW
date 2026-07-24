---
url: https://chatgpt.com/c/6a61e127-7f24-83eb-9bcf-31c5a900a6a4
---

# Coding-Agent Tasks

## 📗  Stage 1: `pblob.c` Skeleton and Build Integration

Implement only Stage 1 of the packed numeric BLOB extension.

Do not register SQL functions and do not implement any conversion logic in this stage.

### Objective

Create a production source module:

```text
pblob.c
```

and integrate it into the SQLite amalgamation build so that:

* it is compiled after `json.c`;
* it can reference private `json.c` types and functions later;
* it includes the vendored FP16 implementation correctly;
* it compiles in normal, test, and JSON-disabled configurations;
* it introduces no warnings;
* it exposes no public C API.

### Scope

This stage is limited to:

1. Creating the `pblob.c` source skeleton.
2. Adding module documentation.
3. Adding JSON compile guards.
4. Integrating/configuring the vendored FP16 headers.
5. Adding compile-time platform checks.
6. Defining private format-related types.
7. Adding private forward declarations for future callbacks and helpers.
8. Adding the internal initializer declaration or stub required by the build integration.
9. Inserting `pblob.c` into the amalgamation source list after `json.c`.
10. Verifying all required build configurations compile.

Do not implement any SQL-visible functionality.

---

### Source Module

Create:

```text
pblob.c
```

Do not create:

```text
pblob.h
```

A header is unnecessary because:

* the extension exposes no public C API;
* all production types and helpers are private;
* the module is compiled only as part of the amalgamation;
* private `json.c` definitions are visible through source ordering;
* only the project’s internal auto-extension dispatcher will eventually call the initializer.

All definitions should be `static` unless the internal initializer must be visible to a later amalgamation source fragment.

---

### Module Documentation

Add a professional module-level comment describing:

* the extension purpose;
* the SQL functions that will eventually be implemented:

  ```sql
  pblob_pack(json_array, format)
  pblob_unpack(blob, format)
  ```
* supported formats:

  ```text
  int8
  <f2
  >f2
  <f4
  >f4
  ```
* raw, headerless BLOB representation;
* amalgamation-only implementation;
* dependency on SQLite `json.c`;
* dependency on the vendored FP16 implementation;
* absence of a public C API;
* requirement that this source appear after `json.c`.

Do not claim that the SQL functions are already implemented.

---

### JSON Compile Guard

Wrap the implementation in:

```c
#ifndef SQLITE_OMIT_JSON

/* pblob implementation */

#endif /* SQLITE_OMIT_JSON */
```

When `SQLITE_OMIT_JSON` is defined:

* the module must compile cleanly;
* it must contribute no SQL registration;
* it must introduce no unresolved references;
* it must not require FP16 code unnecessarily unless source-bundling constraints make that unavoidable.

Prefer placing FP16 inclusion inside the JSON guard.

---

### FP16 Configuration

Use the vendored FP16 implementation already present in the project.

Before including its primary header, force the portable conversion path:

```c
#ifndef FP16_USE_NATIVE_CONVERSION
## define FP16_USE_NATIVE_CONVERSION 0
#endif
```

Then include the project’s top-level FP16 header using the actual project-relative include path.

Do not:

* enable native conversion;
* add compiler-specific half instructions;
* duplicate FP16 code;
* introduce another half-float library;
* modify the vendored FP16 implementation in this stage.

The following functions will be used in later stages and must be available after inclusion:

```c
fp16_ieee_from_fp32_value()
fp16_ieee_to_fp32_value()
fp32_to_bits()
fp32_from_bits()
```

Do not call them yet.

---

### Required Includes

Include only what is required for:

* fixed-width integer types;
* floating-point compile-time constants;
* `CHAR_BIT`;
* the vendored FP16 implementation.

Because this file is compiled inside the amalgamation after SQLite core sources, avoid duplicating SQLite internal includes unless the amalgamation structure requires them.

Use the source tree’s established style.

---

### Compile-Time Platform Checks

Add compile-time assertions for these assumptions:

```text
CHAR_BIT == 8
sizeof(uint16_t) == 2
sizeof(uint32_t) == 4
sizeof(float) == 4
FLT_RADIX == 2
FLT_MANT_DIG == 24
FLT_MAX_EXP == 128
```

Use the SQLite source tree’s established compile-time assertion mechanism where available.

Do not introduce a runtime platform check.

Failure on an unsupported platform should occur at compile time with a clear diagnostic.

---

### Private Format Types

Define these private types or an equivalent representation with the same semantics:

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

Requirements:

* the types remain private to `pblob.c`;
* no public typedefs are created;
* do not add unsupported formats;
* do not implement format parsing yet.

---

### Forward Declarations

Add private forward declarations for the future SQL callbacks:

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

Add forward declarations for future helper groups only where useful to establish the intended module structure:

* format parsing;
* 16-bit endian reads/writes;
* 32-bit endian reads/writes;
* JSONB integer extraction;
* JSONB numeric extraction.

Do not implement these functions in this stage.

Avoid declarations that trigger unused-function warnings. If necessary, defer helper declarations until the stage that implements them.

---

### Internal Initializer

Establish the internal initializer name expected by the project’s auto-extension dispatcher, for example:

```c
int sqlite3PblobInit(sqlite3 *db);
```

Use the actual project naming convention.

For this stage, either:

1. provide a minimal initializer returning `SQLITE_OK` without registering anything; or
2. provide only a forward declaration if the build and dispatcher integration allow registration to be deferred until Stage 2.

Preferred behavior:

```c
int sqlite3PblobInit(sqlite3 *db){
  UNUSED_PARAMETER(db);
  return SQLITE_OK;
}
```

Only use this form if the dispatcher is already wired to call the initializer in Stage 1.

Do not register:

```text
pblob_pack
pblob_unpack
```

in this stage.

Do not add placeholder SQL callbacks that are reachable from SQL.

---

### Amalgamation Integration

Insert `pblob.c` into the project’s amalgamation source list.

It must appear:

```text
after json.c
before the auto-extension dispatcher that references sqlite3PblobInit()
```

The exact location must preserve visibility of private `json.c` structures and `static` helpers in the same translation unit.

Do not:

* compile `pblob.c` as an independent loadable extension;
* add `sqlite3ext.h`;
* add `SQLITE_EXTENSION_INIT1`;
* add `sqlite3_extension_init`;
* add DLL export annotations;
* create a separate static library.

If the project uses a source-bundling Tcl script, update the actual source list used by that script.

---

### Build-System Integration

Modify only the build inputs necessary to include `pblob.c` in:

* the normal amalgamation;
* the test amalgamation where applicable.

Do not yet add:

```text
src/test_pblob.c
test/pblob.test
```

Those belong to later stages.

Preserve existing build conventions.

Do not create a new build system.

---

### Required Build Verification

Perform clean or dependency-safe builds for all three configurations.

#### Normal amalgamation build

Build the normal SQLite amalgamation or the project’s normal target.

Verify:

* `pblob.c` is included;
* no unresolved symbols exist;
* no new warnings appear.

#### Test build

Build the project’s normal SQLite test target or `testfixture` configuration.

At this stage, no packed-blob-specific test module is required.

Verify only that the test build compiles and links.

#### JSON-disabled build

Build with:

```text
SQLITE_OMIT_JSON
```

Verify:

* the build compiles and links;
* no `pblob` SQL functions are registered;
* no unresolved `json.c` or FP16 symbols remain;
* no unused-function warnings are introduced.

---

### Prohibited Work

Do not implement any of the following:

* SQL function registration;
* format parsing;
* NULL handling;
* SQL argument validation;
* JSON parsing;
* JSONB traversal;
* integer extraction;
* floating-point extraction;
* endian conversion logic;
* `int8` packing or unpacking;
* binary16 packing or unpacking;
* binary32 packing or unpacking;
* output BLOB allocation;
* JSON output construction;
* error-message design;
* test-only wrappers;
* Tcl tests;
* Python reference-vector generation;
* public headers;
* public C APIs.

Do not make speculative changes to `json.c`.

Do not refactor unrelated build scripts or SQLite sources.

---

### Expected Deliverables

Provide:

1. The new `pblob.c`.
2. The exact build/source-list changes that place it after `json.c`.
3. Any minimal auto-extension-dispatcher change required for a no-op initializer.
4. The exact build commands executed.
5. The result of:

   * normal build;
   * test build;
   * JSON-disabled build.
6. A concise list of modified files.
7. Confirmation that no SQL functions are registered yet.
8. Confirmation that no `pblob.h` or public C API was added.

---

### Acceptance Criteria

Stage 1 is complete only when:

* `pblob.c` exists;
* the module documentation is present;
* JSON compile guards are correct;
* FP16 portable mode is forced;
* platform assumptions are compile-time checked;
* private format types are defined;
* the source is included after `json.c`;
* normal build succeeds;
* test build succeeds;
* JSON-disabled build succeeds;
* no new compiler warnings are introduced;
* no SQL functions are registered;
* no conversion logic exists;
* no public header or public C API exists.

Stop after satisfying these criteria. Do not proceed to Stage 2.

---
---

## 📗 Stage 2: Register Placeholder SQL Functions

Implement only Stage 2 of the packed numeric BLOB extension.

This stage begins from the completed Stage 1 state, where:

* `pblob.c` already exists;
* it is compiled as part of the SQLite amalgamation;
* it appears after `json.c`;
* JSON compile guards are present;
* FP16 portable mode is configured;
* platform assumptions are compile-time checked;
* private format types are defined;
* no SQL functions are registered;
* no conversion logic exists.

Do not implement format parsing, JSON handling, packing, unpacking, or tests beyond the registration smoke checks required here.

### Objective

Register two SQL scalar functions:

```sql
pblob_pack(json_array, format)
pblob_unpack(blob, format)
```

Both functions must:

* have arity 2;
* be auto-registered on every database connection through the project’s existing auto-extension dispatcher;
* resolve successfully from SQL without `.load`;
* return a deterministic temporary “not implemented” error;
* expose no public C API;
* remain unavailable when `SQLITE_OMIT_JSON` is defined.

### Scope

This stage is limited to:

1. Implementing placeholder SQL callbacks.
2. Implementing or completing the internal initializer.
3. Registering the two SQL functions.
4. Wiring the initializer into the existing auto-extension dispatcher if Stage 1 did not already do so.
5. Verifying SQL visibility, arity, flags, and JSON-disabled behavior.
6. Adding only minimal smoke tests required to prove registration.

Do not implement any real conversion behavior.

---

### Placeholder SQL Callbacks

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

Each callback must:

* assert or otherwise expect `argc == 2`;
* avoid inspecting argument values;
* avoid coercing or parsing arguments;
* return a stable temporary error through `sqlite3_result_error()`.

Recommended temporary messages:

```text
pblob_pack: not implemented
pblob_unpack: not implemented
```

The callbacks must not:

* return NULL;
* return placeholder BLOB or JSON values;
* attempt partial argument validation;
* call `json.c`;
* call FP16 functions;
* allocate memory;
* register additional functions.

Use `UNUSED_PARAMETER()` or the project’s established equivalent for unused callback parameters.

---

### SQL Function Registration

Implement or complete the internal initializer, using the project’s established naming convention.

Expected form:

```c
int sqlite3PblobInit(sqlite3 *db);
```

Register exactly:

```text
pblob_pack
pblob_unpack
```

with:

```text
arity: 2
encoding: SQLITE_UTF8
```

Use these function flags:

```c
SQLITE_UTF8
| SQLITE_DETERMINISTIC
| SQLITE_INNOCUOUS
| SQLITE_RESULT_SUBTYPE
```

`SQLITE_RESULT_SUBTYPE` is included now because `pblob_unpack()` will later return JSON-subtyped text.

Do not use:

```c
SQLITE_DIRECTONLY
```

Do not register aliases.

Do not register variable-arity versions.

Do not register one-argument or three-argument overloads.

---

### Registration API

Use the project’s preferred core registration API.

A public API call such as:

```c
sqlite3_create_function_v2()
```

is acceptable if that is consistent with the surrounding internal extensions.

If the project uses an internal registration helper or a static function table, follow the existing convention instead of inventing a new registration mechanism.

The registration must associate:

```text
pblob_pack   -> pblobPackFunc
pblob_unpack -> pblobUnpackFunc
```

No aggregate-step or window-function callbacks are required.

No destructor callback is required.

No application data pointer is required.

---

### Initializer Error Handling

The initializer must:

1. Register `pblob_pack`.
2. Stop and return immediately if that registration fails.
3. Register `pblob_unpack`.
4. Return the second registration result.

Conceptually:

```c
int rc;

rc = sqlite3_create_function_v2(...pblob_pack...);
if( rc!=SQLITE_OK ){
  return rc;
}

rc = sqlite3_create_function_v2(...pblob_unpack...);
return rc;
```

Do not mask registration failures.

Do not always return `SQLITE_OK`.

Do not emit SQL errors from the initializer.

---

### Auto-Extension Dispatcher Integration

Ensure the project’s existing auto-extension dispatcher calls:

```c
sqlite3PblobInit(db)
```

for every newly initialized SQLite connection.

Requirements:

* no `.load` command;
* no dynamic extension loading;
* no exported DLL entry point;
* no `sqlite3_extension_init`;
* no `sqlite3ext.h`;
* no `SQLITE_EXTENSION_INIT1`;
* no external registration call required by the application.

If the dispatcher calls multiple initializers, preserve its existing error-propagation policy.

Do not reorder unrelated initializers unless source ordering requires the `pblob` initializer declaration to be visible.

---

### JSON Compile Guard

All callback definitions, initializer implementation, and registration code must remain inside:

```c
#ifndef SQLITE_OMIT_JSON
...
#endif
```

When `SQLITE_OMIT_JSON` is defined:

* no `pblob` SQL functions are registered;
* no callback symbols are referenced;
* no initializer call remains unresolved;
* the build compiles and links cleanly.

If the auto-extension dispatcher is outside the JSON guard, guard its call appropriately.

---

### SQL Flags Verification

Verify the registered functions are:

* deterministic;
* innocuous;
* not direct-only;
* scalar functions;
* fixed arity 2.

Where the selected SQLite test harness exposes function-property inspection, use it.

Otherwise verify behavior through integration tests that depend on these flags only in later stages.

Do not add schema-integration tests yet.

---

### Minimal Smoke Tests

Add only the minimal registration tests required for this stage.

Suggested test cases:

```sql
SELECT pblob_pack('[]', 'int8');
```

Expected error:

```text
pblob_pack: not implemented
```

```sql
SELECT pblob_unpack(x'', 'int8');
```

Expected error:

```text
pblob_unpack: not implemented
```

Verify both functions resolve without:

```sql
.load
```

Verify wrong arity is handled by SQLite:

```sql
SELECT pblob_pack();
SELECT pblob_pack('[]');
SELECT pblob_pack('[]', 'int8', 1);

SELECT pblob_unpack();
SELECT pblob_unpack(x'');
SELECT pblob_unpack(x'', 'int8', 1);
```

Expected result: SQLite wrong-number-of-arguments errors.

Do not test:

* NULL propagation;
* argument types;
* format validation;
* JSON parsing;
* BLOB contents;
* JSON subtype behavior;
* conversion semantics.

Those belong to later stages.

---

### Build Verification

Perform the same required build variants as Stage 1.

#### Normal build

Verify:

* `pblob.c` compiles;
* initializer links;
* no new warnings appear;
* both functions are available in the normal shell or library.

#### Test build

Build `testfixture` or the project’s equivalent test target.

Run the minimal registration smoke tests.

#### JSON-disabled build

Build with:

```text
SQLITE_OMIT_JSON
```

Verify:

* build and link succeed;
* `pblob_pack` is unavailable;
* `pblob_unpack` is unavailable;
* no unresolved initializer or callback references exist.

---

### Prohibited Work

Do not implement:

* NULL propagation;
* argument storage-class validation;
* format parsing;
* format enums beyond those already defined;
* JSON text parsing;
* JSONB acceptance or rejection;
* root-array validation;
* JSONB traversal;
* integer extraction;
* floating-point extraction;
* endian helpers;
* checked-size calculations;
* BLOB allocation;
* JSON output construction;
* `int8` conversion;
* binary16 conversion;
* binary32 conversion;
* non-finite handling;
* signed-zero handling;
* result subtype assignment inside the callbacks;
* test-only C wrappers;
* exhaustive tests;
* reference-vector generation;
* schema integration tests.

Do not refactor unrelated auto-extension registration code.

Do not modify `json.c`.

Do not add `pblob.h`.

---

### Expected Deliverables

Provide:

1. Updated `pblob.c`.
2. The auto-extension dispatcher change, if required.
3. Minimal registration smoke tests.
4. Exact build commands executed.
5. Exact test commands executed.
6. Results for:

   * normal build;
   * test build;
   * JSON-disabled build.
7. A concise list of modified files.
8. Confirmation that:

   * both SQL functions are registered;
   * both have arity 2;
   * both currently return only “not implemented” errors;
   * no argument validation or conversion logic was added;
   * no public header or public C API was added.

---

### Acceptance Criteria

Stage 2 is complete only when:

* `pblob_pack` resolves from SQL;
* `pblob_unpack` resolves from SQL;
* both require exactly two arguments;
* both return their stable temporary errors;
* both are auto-registered without `.load`;
* both use the required registration flags;
* registration failures propagate from the initializer;
* normal build succeeds;
* test build succeeds;
* JSON-disabled build succeeds;
* no new warnings appear;
* no conversion or argument-validation logic exists;
* no public C API or header exists.

Stop after satisfying these criteria. Do not proceed to Stage 3.

---
---

## 📗 Stage 3: Format Parsing and Common Argument Handling

Implement only Stage 3 of the packed numeric BLOB extension.

This stage begins from the completed Stage 2 state, where:

* `pblob.c` already exists;
* it is compiled into the SQLite amalgamation after `json.c`;
* FP16 portable mode is configured;
* private format-related types are defined;
* `pblob_pack` and `pblob_unpack` are auto-registered;
* both functions have arity 2;
* both currently return stable temporary “not implemented” errors;
* no format parsing or conversion logic exists.

Do not implement JSON parsing, JSONB traversal, endian helpers, numeric extraction, packing, or unpacking in this stage.

### Objective

Implement the complete common SQL argument-handling layer for:

```sql
pblob_pack(json_array, format)
pblob_unpack(blob, format)
```

This stage must add:

* SQL NULL propagation;
* strict storage-class validation;
* exact format-string parsing;
* stable errors for invalid argument types and unsupported formats;
* dispatch to the existing placeholder behavior only after all common validation succeeds.

The two functions must still perform no real conversion.

### Scope
 
This stage is limited to:

1. Implementing an exact private format parser.
2. Implementing SQL NULL propagation.
3. Validating argument storage classes.
4. Preserving strict TEXT-only input for `pblob_pack()`.
5. Preserving strict BLOB-only input for `pblob_unpack()`.
6. Replacing the unconditional placeholder errors with validation followed by the same temporary placeholder errors.
7. Adding focused tests for common argument handling.
8. Verifying normal, test, and JSON-disabled builds.

Do not implement any data conversion.

---

### Exact Format Parser

Implement a private helper equivalent to:

```c
static int pblobParseFormat(
  sqlite3_context *ctx,
  sqlite3_value *pArg,
  const char *zFunc,
  PblobFormat *pFormat
);
```

The helper must accept exactly these byte sequences:

```text
int8
<f2
>f2
<f4
>f4
```

Required mappings:

| Format | Kind         | Byte order         | Element size |
| ------ | ------------ | ------------------ | -----------: |
| `int8` | `PBLOB_INT8` | `PBLOB_ORDER_NONE` |            1 |
| `<f2`  | `PBLOB_F16`  | `PBLOB_ORDER_LE`   |            2 |
| `>f2`  | `PBLOB_F16`  | `PBLOB_ORDER_BE`   |            2 |
| `<f4`  | `PBLOB_F32`  | `PBLOB_ORDER_LE`   |            4 |
| `>f4`  | `PBLOB_F32`  | `PBLOB_ORDER_BE`   |            4 |

Use:

```c
sqlite3_value_type()
sqlite3_value_text()
sqlite3_value_bytes()
memcmp()
```

Do not use:

```c
strcmp()
sqlite3_stricmp()
sqlite3_strnicmp()
locale-aware comparison
prefix-only comparison
```

The parser must compare both:

* exact byte length;
* exact byte contents.

This is required so values containing embedded NUL bytes are not accepted based on a valid prefix.

Example invalid TEXT value:

```text
"<f2\0junk"
```

must not be accepted as `<f2`.

---

### Format Argument Storage Class

The format argument must have SQL storage class:

```text
SQLITE_TEXT
```

Do not coerce:

* INTEGER;
* FLOAT;
* BLOB;
* JSONB;
* numeric text generated through implicit affinity.

If the format argument is not TEXT, report:

```text
pblob_pack: format must be text
```

or:

```text
pblob_unpack: format must be text
```

according to the function being executed.

The helper may use the supplied `zFunc` value to construct the message.

Do not allocate an error string when a fixed message or bounded formatter can be used cleanly.

---

### Unsupported Format Errors

For unsupported TEXT values, return a stable function-specific error.

Recommended messages:

```text
pblob_pack: unsupported format
pblob_unpack: unsupported format
```

Including the actual format value is optional in this stage.

If the implementation includes the value, it must:

* use the explicit byte count;
* safely handle embedded NUL bytes;
* avoid treating arbitrary bytes as a conventional NUL-terminated string;
* avoid malformed or misleading error output.

A generic unsupported-format message is preferred.

---

### NULL Propagation

Both SQL functions must propagate SQL NULL.

Required rule:

> If either argument is SQL NULL, return SQL NULL immediately without validating the other argument.

Examples:

```sql
pblob_pack(NULL, 'int8') -> NULL
pblob_pack('[]', NULL) -> NULL
pblob_pack(NULL, NULL) -> NULL

pblob_unpack(NULL, 'int8') -> NULL
pblob_unpack(x'', NULL) -> NULL
pblob_unpack(NULL, NULL) -> NULL
```

NULL handling must occur before:

* first-argument storage-class validation;
* format storage-class validation;
* format parsing;
* placeholder dispatch.

This means:

```sql
SELECT pblob_pack(NULL, 123);
```

must return NULL, not a format-type error.

Similarly:

```sql
SELECT pblob_unpack(NULL, x'00');
```

must return NULL.

Use:

```c
sqlite3_value_type()
sqlite3_result_null()
```

Do not call `sqlite3_value_text()` or `sqlite3_value_blob()` before NULL propagation is complete.

---

### `pblob_pack()` First-Argument Validation

After NULL propagation, require:

```text
argv[0] storage class == SQLITE_TEXT
```

Accepted examples:

```sql
'[]'
'[1,2,3]'
json('[1,2,3]')
```

The result of `json()` is TEXT and is therefore accepted at this stage.

Reject:

```sql
1
1.0
x'5B315D'
jsonb('[1,2,3]')
```

Even valid SQLite JSONB must be rejected because the public contract for `pblob_pack()` requires TEXT JSON input.

Recommended error:

```text
pblob_pack: first argument must be JSON text
```

Do not attempt to parse the TEXT in this stage.

An empty TEXT value still passes storage-class validation and reaches the temporary placeholder error.

Malformed JSON also reaches the placeholder error because JSON parsing belongs to a later stage.

---

### `pblob_unpack()` First-Argument Validation

After NULL propagation, require:

```text
argv[0] storage class == SQLITE_BLOB
```

Accepted examples:

```sql
x''
x'00'
zeroblob(4)
```

Reject:

```sql
''
'0000'
1
1.0
json('[1]')
jsonb('[1]')
```

Although `jsonb('[1]')` is also a BLOB, it passes storage-class validation at this stage because `pblob_unpack()` accepts arbitrary raw BLOB input. Its content will not be interpreted yet.

Recommended error:

```text
pblob_unpack: first argument must be a BLOB
```

Do not retrieve or inspect BLOB bytes in this stage.

---

### Callback Control Flow

Update `pblobPackFunc()` to follow this exact order:

1. Confirm `argc == 2`.
2. Check whether either argument is SQL NULL.
3. If either is NULL, return SQL NULL.
4. Require `argv[0]` to be SQL TEXT.
5. Parse and validate `argv[1]` using `pblobParseFormat()`.
6. Return the temporary error:

   ```text
   pblob_pack: conversion not implemented
   ```

Update `pblobUnpackFunc()` to follow this exact order:

1. Confirm `argc == 2`.
2. Check whether either argument is SQL NULL.
3. If either is NULL, return SQL NULL.
4. Require `argv[0]` to be SQL BLOB.
5. Parse and validate `argv[1]` using `pblobParseFormat()`.
6. Return the temporary error:

   ```text
   pblob_unpack: conversion not implemented
   ```

The placeholder messages may remain:

```text
pblob_pack: not implemented
pblob_unpack: not implemented
```

provided they remain stable and clearly distinguish successful validation from earlier validation errors.

Do not inspect the populated `PblobFormat` beyond suppressing unused-variable warnings.

---

### Required Validation Order

The validation order is part of the contract.

For `pblob_pack()`:

```text
NULL propagation
-> first argument storage class
-> format storage class
-> exact format value
-> placeholder
```

For `pblob_unpack()`:

```text
NULL propagation
-> first argument storage class
-> format storage class
-> exact format value
-> placeholder
```

Examples:

```sql
SELECT pblob_pack(1, 2);
```

must report the first-argument error, not the format error.

```sql
SELECT pblob_pack('[]', 2);
```

must report the format-type error.

```sql
SELECT pblob_pack('[]', 'bad');
```

must report the unsupported-format error.

The same precedence applies to `pblob_unpack()`.

---

### Format Descriptor Initialization

On successful parsing, populate every field of `PblobFormat`.

Do not leave fields conditionally uninitialized.

For `int8`:

```text
eKind  = PBLOB_INT8
eOrder = PBLOB_ORDER_NONE
nByte  = 1
```

For floating formats, populate both kind and explicit byte order.

The parser should return:

```text
0 on success
nonzero on error
```

or follow another consistent internal convention.

When returning an error, it must already have set the SQL error on `ctx`.

Document the return convention in a concise function comment.

---

### Test Module

Extend the minimal Stage 2 smoke-test module or create the initial focused:

```text
test/pblob.test
```

Use the project’s established SQLite Tcl test-harness conventions.

Do not add:

```text
src/test_pblob.c
test/pblob_vectors.tcl
test/pblob_limits.test
test/pblob_fault.test
```

in this stage.

---

### Required NULL Tests

Test:

```sql
SELECT typeof(pblob_pack(NULL, 'int8'));
SELECT typeof(pblob_pack('[]', NULL));
SELECT typeof(pblob_pack(NULL, NULL));

SELECT typeof(pblob_unpack(NULL, 'int8'));
SELECT typeof(pblob_unpack(x'', NULL));
SELECT typeof(pblob_unpack(NULL, NULL));
```

Expected result for each:

```text
null
```

Also test validation-order cases:

```sql
SELECT typeof(pblob_pack(NULL, 123));
SELECT typeof(pblob_unpack(NULL, 123));
```

Expected:

```text
null
```

---

### Required Accepted-Format Tests

For `pblob_pack()`, use valid TEXT first arguments and verify each accepted format reaches the placeholder error:

```text
int8
<f2
>f2
<f4
>f4
```

For `pblob_unpack()`, use a valid BLOB first argument and verify the same.

These tests prove format recognition without requiring conversion behavior.

---

### Required Rejected-Format Tests

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
=f2
=f4
@f4
native
```

Also reject:

```text
 int8
int8 
 <f2
<f2 
>f4\t
<f4\n
```

Use actual tab and newline bytes where practical.

Expected: unsupported-format error.

---

### Embedded-NUL Format Test

Construct a SQL TEXT format containing an embedded NUL.

One possible Tcl binding approach is preferred because SQL string literals cannot conveniently represent arbitrary embedded NUL bytes.

Test at least:

```text
"<f2\0"
"<f2\0junk"
"int8\0"
```

Expected: unsupported-format error.

This test is mandatory.

---

### Required Format-Type Tests

For both functions, test non-TEXT format arguments:

```sql
1
1.0
x'696E7438'
jsonb('"int8"')
```

Expected: function-specific “format must be text” error.

---

### Required First-Argument Type Tests for `pblob_pack()`

Reject:

```sql
1
1.0
x'5B5D'
jsonb('[]')
```

Expected:

```text
pblob_pack: first argument must be JSON text
```

Accept as storage class and reach placeholder:

```sql
'[]'
''
'not JSON'
json('[]')
```

Do not reject malformed JSON yet.

---

### Required First-Argument Type Tests for `pblob_unpack()`

Reject:

```sql
''
'00'
1
1.0
json('[]')
```

Expected:

```text
pblob_unpack: first argument must be a BLOB
```

Accept as storage class and reach placeholder:

```sql
x''
x'00'
jsonb('[]')
zeroblob(4)
```

Do not validate BLOB length or contents yet.

---

### Required Error-Precedence Tests

Test at least:

```sql
SELECT pblob_pack(1, 2);
```

Expected first-argument error.

```sql
SELECT pblob_pack('[]', 2);
```

Expected format-type error.

```sql
SELECT pblob_pack('[]', 'bad');
```

Expected unsupported-format error.

```sql
SELECT pblob_unpack('00', 2);
```

Expected first-argument error.

```sql
SELECT pblob_unpack(x'00', 2);
```

Expected format-type error.

```sql
SELECT pblob_unpack(x'00', 'bad');
```

Expected unsupported-format error.

---

### Registration Regression Tests

Retain the Stage 2 tests proving:

* both functions resolve automatically;
* both have arity 2;
* wrong arity is rejected by SQLite;
* no `.load` is required.

---

### Build Verification

Perform all required build variants.

#### Normal build

Verify:

* build and link succeed;
* no new warnings appear;
* accepted valid arguments reach placeholder behavior;
* invalid common arguments produce the correct errors.

#### Test build

Build `testfixture` or the project’s equivalent.

Run the complete Stage 3 focused suite.

#### JSON-disabled build

Build with:

```text
SQLITE_OMIT_JSON
```

Verify:

* build and link succeed;
* neither SQL function is registered;
* no format-parser or callback references remain unresolved;
* no unused static-function warnings appear.

---

### Prohibited Work

Do not implement:

* JSON parsing;
* calls to `jsonParseFuncArg()`;
* JSONB traversal;
* root-array validation;
* malformed JSON detection;
* array counting;
* element iteration;
* endian read/write helpers;
* signed-byte conversion;
* integer extraction;
* floating-point extraction;
* checked output-size calculation;
* output BLOB allocation;
* BLOB-length validation;
* JSON output construction;
* JSON subtype assignment by the callbacks;
* `int8` conversion;
* binary16 conversion;
* binary32 conversion;
* non-finite handling;
* signed-zero handling;
* test-only C hooks;
* reference vectors;
* fault injection;
* limit tests.

Do not modify `json.c`.

Do not modify the vendored FP16 implementation.

Do not add `pblob.h`.

Do not register additional SQL functions.

---

### Expected Deliverables

Provide:

1. Updated `pblob.c`.
2. The focused Stage 3 test changes.
3. Exact build commands executed.
4. Exact test commands executed.
5. Results for:

   * normal build;
   * test build;
   * JSON-disabled build.
6. A concise list of modified files.
7. Confirmation that:

   * NULL propagation is implemented;
   * storage-class validation is implemented;
   * exact format parsing is implemented;
   * embedded-NUL formats are rejected;
   * validation order matches this specification;
   * valid calls still end in placeholder errors;
   * no JSON parsing or conversion logic was added;
   * no public header or C API was added.

---

### Acceptance Criteria

Stage 3 is complete only when:

* either SQL NULL argument returns SQL NULL;
* `pblob_pack()` accepts only TEXT as its non-format argument;
* `pblob_unpack()` accepts only BLOB as its non-format argument;
* the format argument accepts only TEXT;
* only the five exact format strings are accepted;
* case variants, aliases, whitespace variants, and embedded-NUL variants are rejected;
* validation errors occur in the specified order;
* accepted arguments reach the temporary placeholder error;
* all Stage 2 registration and arity tests remain passing;
* normal build succeeds;
* test build succeeds;
* JSON-disabled build succeeds;
* no new warnings appear;
* no JSON parsing or conversion logic exists;
* no public header or public C API exists.

Stop after satisfying these criteria. Do not proceed to Stage 4.

---
---

## 📗 Stage 4: Endian and Bit-Level Primitives

Implement only Stage 4 of the packed numeric BLOB extension.

This stage begins from the completed Stage 3 state, where:

* `pblob.c` exists and is compiled into the SQLite amalgamation after `json.c`;
* FP16 portable mode is configured;
* private format types are defined;
* `pblob_pack()` and `pblob_unpack()` are auto-registered with arity 2;
* SQL NULL propagation is implemented;
* strict first-argument storage-class validation is implemented;
* exact format parsing is implemented;
* valid calls still terminate with stable temporary “not implemented” errors;
* no JSON parsing, JSONB traversal, or conversion logic exists.

Do not implement JSON handling, numeric extraction, packing, unpacking, allocation, or output construction in this stage.

### Objective

Implement and verify the private low-level primitives required for later packed numeric conversion:

* explicit little-endian and big-endian 16-bit writes;
* explicit little-endian and big-endian 16-bit reads;
* explicit little-endian and big-endian 32-bit writes;
* explicit little-endian and big-endian 32-bit reads;
* IEEE binary16 finite, infinity, and NaN classification;
* IEEE binary32 finite, infinity, and NaN classification;
* explicit signed `int8` byte decoding;
* checked packed-size multiplication suitable for element sizes 1, 2, and 4.

These primitives must be:

* private;
* alignment-independent;
* host-endian-independent;
* free of strict-aliasing violations;
* free of signed-shift undefined behavior;
* independently testable in a test build;
* unused by the public SQL callbacks until later stages.

The SQL behavior established in Stages 2 and 3 must remain unchanged.

### Scope

This stage is limited to:

1. Implementing byte-order read and write helpers.
2. Implementing binary16 and binary32 bit-classification helpers.
3. Implementing signed-byte decoding.
4. Implementing checked output-size calculation.
5. Adding narrowly scoped test-only access to these helpers.
6. Adding focused low-level tests.
7. Verifying normal, test, and JSON-disabled builds.
8. Preserving all existing SQL registration and validation behavior.

Do not implement actual `pblob_pack()` or `pblob_unpack()` conversion workflows.

---

### 16-Bit Byte-Order Helpers

Implement these private helpers:

```c
static void pblobPutU16Le(u8 *pOut, uint16_t value);
static void pblobPutU16Be(u8 *pOut, uint16_t value);

static uint16_t pblobGetU16Le(const u8 *pIn);
static uint16_t pblobGetU16Be(const u8 *pIn);
```

Required behavior:

```text
pblobPutU16Le:
  pOut[0] = bits 0..7
  pOut[1] = bits 8..15

pblobPutU16Be:
  pOut[0] = bits 8..15
  pOut[1] = bits 0..7
```

Required reconstruction:

```text
pblobGetU16Le:
  byte 0 is least significant

pblobGetU16Be:
  byte 0 is most significant
```

Use only:

* `uint16_t`;
* `u8`;
* unsigned shifts;
* unsigned masks;
* byte indexing;
* bitwise OR.

Do not use:

```c
*(uint16_t *)pOut
*(const uint16_t *)pIn
memcpy() directly as endian conversion
htons()
ntohs()
_byteswap_ushort()
compiler byte-swap intrinsics
```

These helpers must work correctly when `pIn` or `pOut` is not naturally aligned.

---

### 32-Bit Byte-Order Helpers

Implement:

```c
static void pblobPutU32Le(u8 *pOut, uint32_t value);
static void pblobPutU32Be(u8 *pOut, uint32_t value);

static uint32_t pblobGetU32Le(const u8 *pIn);
static uint32_t pblobGetU32Be(const u8 *pIn);
```

Required behavior:

```text
pblobPutU32Le:
  pOut[0] = bits 0..7
  pOut[1] = bits 8..15
  pOut[2] = bits 16..23
  pOut[3] = bits 24..31

pblobPutU32Be:
  pOut[0] = bits 24..31
  pOut[1] = bits 16..23
  pOut[2] = bits 8..15
  pOut[3] = bits 0..7
```

Apply the same restrictions as for the 16-bit helpers.

All intermediate shift operands must be unsigned.

---

### Binary16 Classification

Implement private helpers equivalent to:

```c
static int pblobF16IsFinite(uint16_t bits);
static int pblobF16IsInf(uint16_t bits);
static int pblobF16IsNaN(uint16_t bits);
```

IEEE binary16 layout:

```text
sign:      bit 15
exponent:  bits 10..14
fraction:  bits 0..9
```

Required masks:

```c
#define PBLOB_F16_EXP_MASK  UINT16_C(0x7c00)
#define PBLOB_F16_FRAC_MASK UINT16_C(0x03ff)
```

Required semantics:

```text
finite:
  exponent field is not all ones

infinity:
  exponent field is all ones
  fraction field is zero

NaN:
  exponent field is all ones
  fraction field is nonzero
```

Positive and negative forms must classify identically apart from sign.

Do not call floating-point classification functions for raw binary16 values.

Do not convert the binary16 value to `float` merely to classify it.

---

### Binary32 Classification

Implement private helpers equivalent to:

```c
static int pblobF32IsFinite(uint32_t bits);
static int pblobF32IsInf(uint32_t bits);
static int pblobF32IsNaN(uint32_t bits);
```

IEEE binary32 layout:

```text
sign:      bit 31
exponent:  bits 23..30
fraction:  bits 0..22
```

Required masks:

```c
#define PBLOB_F32_EXP_MASK  UINT32_C(0x7f800000)
#define PBLOB_F32_FRAC_MASK UINT32_C(0x007fffff)
```

Required semantics match the binary16 rules.

Do not convert the bits to `float` merely to classify them.

---

### Signed `int8` Byte Decoding

Implement a private helper equivalent to:

```c
static int pblobDecodeInt8(u8 byte);
```

Required algorithm:

```text
if byte < 0x80:
    return byte
else:
    return byte - 0x100
```

Required output range:

```text
-128 through 127
```

Do not implement decoding as:

```c
(char)byte
(signed char)byte
(int8_t)byte
```

The required implementation must not depend on:

* plain `char` signedness;
* implementation-defined narrowing behavior;
* host integer representation beyond normal C integer semantics.

Packing of `int8` values is not implemented in this stage.

---

### Checked Packed-Size Calculation

Implement a private helper equivalent to:

```c
static int pblobCheckedSize(
  sqlite3_context *ctx,
  sqlite3_uint64 nElem,
  unsigned int nByte,
  sqlite3_uint64 *pSize
);
```

The exact signature may be adjusted to the project’s internal types, but the helper must:

1. Accept an element count.
2. Accept an element width.
3. Support widths:

   ```text
   1
   2
   4
   ```
4. Detect arithmetic multiplication overflow.
5. Detect output sizes exceeding SQLite’s current `SQLITE_LIMIT_LENGTH`.
6. Return the exact byte count on success.
7. Set a suitable SQL error on `ctx` on failure.
8. Distinguish OOM from size errors where applicable, though this helper itself should not allocate.

Recommended logical algorithm:

```text
validate nByte is 1, 2, or 4

if nElem > UINT64_MAX / nByte:
    report packed-size overflow
    fail

nSize = nElem * nByte

read the current database connection length limit

if nSize > SQLITE_LIMIT_LENGTH:
    report result too large
    fail

*pSize = nSize
succeed
```

Use the selected SQLite source tree’s established internal access to the database length limit.

Do not hard-code:

```text
1,000,000,000
2,147,483,647
```

Do not truncate through `int` before validation.

Do not allocate memory in this helper.

This helper is not yet called by `pblobPackFunc()`.

---

### Helper Visibility

All production helpers must remain:

```c
static
```

Do not create `pblob.h`.

Do not expose these helpers through the SQLite DLL.

Do not remove `static` merely to enable testing.

---

### Test-Only Access

Add narrowly scoped test-only wrappers under:

```c
#ifdef SQLITE_TEST
...
#endif
```

The preferred approach is to add a small test-only SQL or Tcl-facing command implementation in the existing Stage 3 test arrangement only if the project already has an established pattern.

If a dedicated `src/test_pblob.c` module is required to call the helpers cleanly, it may be introduced in this stage only for these low-level tests.

Do not yet add exhaustive binary16 conversion tests. Those belong to later stages.

Acceptable test-only operations include:

```text
pblob_test_u16
pblob_test_u32
pblob_test_classify_f16
pblob_test_classify_f32
pblob_test_decode_int8
pblob_test_checked_size
```

The exact command names must follow the SQLite test-suite naming convention.

Test-only commands must:

* be compiled only with `SQLITE_TEST`;
* not be registered in production builds;
* not form a supported application API;
* avoid duplicating production logic.

Where feasible, one test command may accept an operation selector rather than registering many tiny commands.

---

### 16-Bit Endian Test Cases

Test these values:

```text
0x0000
0x0001
0x00ff
0x0100
0x1234
0x3c00
0x8000
0x7c00
0xffff
```

For each value verify:

1. Little-endian output bytes.
2. Big-endian output bytes.
3. Little-endian write followed by little-endian read.
4. Big-endian write followed by big-endian read.
5. Big-endian output is the reverse of little-endian output.
6. Unaligned input and output positions work.

Examples:

```text
0x1234 LE -> 34 12
0x1234 BE -> 12 34

0x3c00 LE -> 00 3c
0x3c00 BE -> 3c 00
```

---

### 32-Bit Endian Test Cases

Test:

```text
0x00000000
0x00000001
0x000000ff
0x00000100
0x00010000
0x01000000
0x12345678
0x3f800000
0x80000000
0x7f800000
0xffffffff
```

Required examples:

```text
0x12345678 LE -> 78 56 34 12
0x12345678 BE -> 12 34 56 78

0x3f800000 LE -> 00 00 80 3f
0x3f800000 BE -> 3f 80 00 00
```

Test unaligned offsets such as:

```text
buffer + 1
buffer + 3
```

---

### Binary16 Classification Test Cases

Verify at least:

| Bits   | Expected                  |
| ------ | ------------------------- |
| `0000` | finite positive zero      |
| `8000` | finite negative zero      |
| `0001` | finite positive subnormal |
| `03ff` | finite largest subnormal  |
| `0400` | finite minimum normal     |
| `3c00` | finite `1.0`              |
| `7bff` | finite maximum positive   |
| `fbff` | finite maximum negative   |
| `7c00` | positive infinity         |
| `fc00` | negative infinity         |
| `7c01` | NaN                       |
| `7e00` | NaN                       |
| `fe00` | NaN                       |
| `ffff` | NaN                       |

For every case verify all three predicates, not only the expected positive predicate.

Example:

```text
7c00:
  finite = false
  infinity = true
  NaN = false
```

---

### Binary32 Classification Test Cases

Verify at least:

| Bits       | Expected                  |
| ---------- | ------------------------- |
| `00000000` | finite positive zero      |
| `80000000` | finite negative zero      |
| `00000001` | finite positive subnormal |
| `007fffff` | finite largest subnormal  |
| `00800000` | finite minimum normal     |
| `3f800000` | finite `1.0`              |
| `7f7fffff` | finite maximum positive   |
| `ff7fffff` | finite maximum negative   |
| `7f800000` | positive infinity         |
| `ff800000` | negative infinity         |
| `7f800001` | NaN                       |
| `7fc00000` | NaN                       |
| `ffc00000` | NaN                       |
| `ffffffff` | NaN                       |

---

### Signed `int8` Decode Tests

Test every byte from:

```text
0x00 through 0xff
```

Expected sequence:

```text
0 through 127
-128 through -1
```

At minimum verify explicit boundary values:

| Byte | Result |
| ---- | -----: |
| `00` |    `0` |
| `01` |    `1` |
| `7e` |  `126` |
| `7f` |  `127` |
| `80` | `-128` |
| `81` | `-127` |
| `fe` |   `-2` |
| `ff` |   `-1` |

The full 256-byte domain test is mandatory.

---

### Checked-Size Tests

Test valid products:

| Element count | Width | Expected bytes |
| ------------: | ----: | -------------: |
|             0 |     1 |              0 |
|             0 |     2 |              0 |
|             0 |     4 |              0 |
|             1 |     1 |              1 |
|             1 |     2 |              2 |
|             1 |     4 |              4 |
|           128 |     1 |            128 |
|           768 |     2 |           1536 |
|          1536 |     4 |           6144 |
|          4096 |     4 |          16384 |

Test invalid widths:

```text
0
3
5
8
```

These should fail defensively. They are internal programmer errors, but the helper must not silently calculate with them.

Test arithmetic overflow using artificial element counts through the test-only wrapper.

For each supported width:

```text
floor(UINT64_MAX / width)
floor(UINT64_MAX / width) + 1
```

The first value may still exceed SQLite’s length limit and therefore fail for that reason. The test wrapper should allow arithmetic-overflow behavior and SQLite-limit behavior to be distinguished or tested independently.

Test SQLite length-limit behavior by temporarily lowering `SQLITE_LIMIT_LENGTH`.

Examples:

```text
limit = 16
nElem = 4, width = 4 -> success
nElem = 5, width = 4 -> failure
```

Restore the original limit after each test.

---

### Existing SQL Behavior Regression Tests

Retain all Stage 2 and Stage 3 tests.

Verify that:

```sql
pblob_pack(NULL, 'int8')
pblob_unpack(NULL, 'int8')
```

still return NULL.

Verify valid arguments still reach:

```text
pblob_pack: not implemented
pblob_unpack: not implemented
```

or the established temporary equivalent.

No public SQL call may begin using the new primitives in this stage.

---

### Build Verification

Perform all required configurations.

#### Normal Build

Verify:

* all helpers compile;
* all production helpers remain private;
* no unused-static warnings appear;
* SQL behavior remains unchanged;
* no test-only commands are present.

If helpers would trigger unused-function warnings before later stages use them, choose one of these approaches:

1. Place their implementations under a local compiler-supported unused annotation consistent with SQLite style.
2. Compile the helper implementations only when either `SQLITE_TEST` or a later functional stage uses them.
3. Reference them only through test-build code while ensuring production compilers do not warn for private unused static functions.
4. Follow an established SQLite source convention.

Do not make the helpers non-static.

#### Test Build

Build `testfixture` or the project’s equivalent with:

```text
SQLITE_TEST
```

Run:

* endian tests;
* classification tests;
* complete signed-byte tests;
* checked-size tests;
* all existing Stage 2 and Stage 3 tests.

#### JSON-Disabled Build

Build with:

```text
SQLITE_OMIT_JSON
```

Verify:

* `pblob.c` contributes no active helpers unless intentionally outside the guard;
* no FP16 inclusion is required unnecessarily;
* no test-only pblob commands are registered;
* no unresolved symbols or warnings occur.

---

### Prohibited Work

Do not implement:

* `jsonParseFuncArg()` calls;
* JSON syntax validation;
* JSONB traversal;
* JSONB numeric extraction;
* root-array validation;
* array counting;
* element iteration;
* BLOB retrieval in `pblob_unpack()`;
* BLOB-length divisibility validation in the SQL callback;
* packed-output allocation;
* signed `int8` packing;
* any SQL-visible `int8` conversion;
* binary16 conversion calls;
* binary32 conversion calls;
* JSON output construction;
* JSON result subtype assignment;
* floating-point formatting;
* non-finite SQL errors;
* conversion error messages;
* reference-vector generation;
* OOM fault tests unrelated to these helpers;
* schema integration tests.

Do not modify:

* `json.c`;
* the vendored FP16 implementation;
* unrelated SQLite build logic.

Do not add:

```text
pblob.h
```

Do not register additional production SQL functions.

---

### Expected Deliverables

Provide:

1. Updated `pblob.c`.
2. Any test-only low-level test module added for this stage.
3. Focused low-level test cases.
4. Exact build commands executed.
5. Exact test commands executed.
6. Results for:

   * normal build;
   * test build;
   * JSON-disabled build.
7. A concise list of modified files.
8. Confirmation that:

   * endian helpers use only explicit byte operations;
   * unaligned addresses are tested;
   * binary16 classification is implemented;
   * binary32 classification is implemented;
   * full-domain signed-byte decoding is tested;
   * checked-size multiplication is implemented and tested;
   * all helpers remain private;
   * public SQL behavior remains unchanged;
   * no JSON or conversion workflow was added;
   * no public header or C API was added.

---

### Acceptance Criteria

Stage 4 is complete only when:

* all 16-bit endian helpers produce exact expected bytes;
* all 32-bit endian helpers produce exact expected bytes;
* read/write round trips pass;
* unaligned-buffer tests pass;
* binary16 finite, infinity, and NaN classification passes;
* binary32 finite, infinity, and NaN classification passes;
* every possible input byte decodes to the required signed `int8` value;
* checked multiplication detects arithmetic overflow;
* checked multiplication enforces the current SQLite length limit;
* invalid element widths fail defensively;
* all Stage 2 and Stage 3 tests remain passing;
* normal build succeeds;
* test build succeeds;
* JSON-disabled build succeeds;
* no new compiler warnings appear;
* production helpers remain `static`;
* public SQL behavior still ends in placeholder errors;
* no actual packing or unpacking logic exists;
* no public C API or header exists.

Stop after satisfying these criteria. Do not proceed to Stage 5.

---
---

## 📗 Stage 5: JSONB Numeric Extraction Helpers

Implement only Stage 5 of the packed numeric BLOB extension.

This stage begins from the completed Stage 4 state, where:

* `pblob.c` is compiled into the SQLite amalgamation after `json.c`;
* `pblob_pack()` and `pblob_unpack()` are auto-registered;
* NULL propagation, storage-class validation, and exact format parsing are complete;
* valid SQL calls still terminate with stable temporary “not implemented” errors;
* endian helpers are implemented;
* binary16 and binary32 bit-classification helpers are implemented;
* signed `int8` byte decoding is implemented;
* checked packed-size calculation is implemented;
* no JSON parsing, JSONB traversal, packing, or unpacking workflow exists.

Do not implement any public conversion workflow in this stage.

### Objective

Implement the private helpers that extract numeric values from individual SQLite JSONB numeric nodes.

The helpers must reuse SQLite’s existing internal numeric parsing behavior rather than introducing independent parsing code.

Implement:

```c
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
```

These helpers will be used by later packing stages.

They must not yet be called by:

```text
pblob_pack()
pblob_unpack()
```

The public SQL behavior established in Stages 2–4 must remain unchanged.

### Scope

This stage is limited to:

1. Validating and locating one JSONB numeric node.
2. Extracting signed integer values for future `int8` packing.
3. Extracting numeric values as `double` for future binary16 and binary32 packing.
4. Reusing:

   ```c
   jsonbPayloadSize()
   sqlite3DecOrHexToI64()
   sqlite3AtoF()
   sqlite3DbStrNDup()
   sqlite3DbFree()
   ```
5. Adapting relevant semantics from `jsonReturnFromBlob()`.
6. Handling malformed payloads and OOM correctly.
7. Adding test-only access to the helpers.
8. Adding focused extraction tests.
9. Preserving all existing public SQL behavior.

Do not implement array parsing or traversal.

---

### Existing SQLite Behavior to Reuse

The implementation must be based on the selected `json.c` behavior.

Relevant JSONB numeric node types are:

```c
JSONB_INT
JSONB_INT5
JSONB_FLOAT
JSONB_FLOAT5
```

Their payloads are textual numeric representations without a trailing NUL byte.

Use:

```c
jsonbPayloadSize(pParse, iNode, &nPayload)
```

to obtain:

```text
node header size
payload size
payload start offset
```

For a valid node:

```text
iPayload = iNode + nHeader
iNext    = iPayload + nPayload
```

A zero return from `jsonbPayloadSize()` indicates malformed JSONB.

The implementation must adapt the numeric conversion logic from `jsonReturnFromBlob()` rather than calling `jsonReturnFromBlob()` itself, because that function writes an SQL result directly and does not return a C numeric value.

Do not modify `json.c`.

---

### Helper Return Convention

Use a consistent convention:

```text
0     success
nonzero error, with the SQL error already set on ctx
```

On success:

* `*pValue` must be initialized.
* No error must remain pending.
* All temporary storage must be released.

On error:

* do not leave partially meaningful output in `*pValue`;
* report the correct error through `ctx`;
* release all temporary memory;
* return immediately.

Document this convention in concise helper comments.

---

### Common Node Validation

Both helpers must validate the node defensively.

Required logical steps:

1. Verify:

   ```text
   pParse != NULL
   pParse->aBlob != NULL
   iNode < pParse->nBlob
   ```
2. Call:

   ```c
   nHeader = jsonbPayloadSize(pParse, iNode, &nPayload);
   ```
3. Reject:

   ```text
   nHeader == 0
   nPayload == 0
   iNode + nHeader + nPayload > pParse->nBlob
   ```
4. Read the node type:

   ```c
   eType = pParse->aBlob[iNode] & 0x0f;
   ```
5. Validate that the type is accepted by the specific helper.
6. Determine:

   ```c
   const char *zPayload =
       (const char *)&pParse->aBlob[iNode + nHeader];
   ```

Use overflow-safe offset arithmetic.

Although later callers will normally supply valid internal JSONB produced from TEXT JSON, malformed-node handling is mandatory.

Recommended malformed-node error:

```text
pblob: malformed internal JSON representation
```

Test-only direct helper calls may use this error.

---

### Integer Extraction Helper

Implement:

```c
static int pblobJsonbInteger(
  sqlite3_context *ctx,
  JsonParse *pParse,
  u32 iNode,
  sqlite3_int64 *pValue
);
```

#### Accepted node types

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
all text types
JSONB_ARRAY
JSONB_OBJECT
```

Recommended wrong-type error for direct helper testing:

```text
pblob: JSONB node is not an integer
```

Later public packing code will normally perform type validation before calling the helper and will provide element-specific messages.

#### Required parsing behavior

Adapt the integer path from `jsonReturnFromBlob()`.

Required logical algorithm:

1. Validate and locate the payload.
2. Detect an optional leading `'-'`.
3. Reject a sign-only payload.
4. If negative:

   * exclude the leading sign from the string passed to `sqlite3DecOrHexToI64()`;
   * remember the negative sign separately.
5. Duplicate the unsigned payload using:

   ```c
   sqlite3DbStrNDup()
   ```
6. Parse using:

   ```c
   sqlite3DecOrHexToI64()
   ```
7. Free the duplicate using:

   ```c
   sqlite3DbFree()
   ```
8. Interpret the parser result according to the selected SQLite source behavior.
9. Apply the remembered sign.
10. Return the exact signed `sqlite3_int64`.

Do not use:

```c
strtol()
strtoll()
strtoul()
strtoull()
sscanf()
atoi()
atoll()
```

#### Required `sqlite3DecOrHexToI64()` result handling

The implementation must inspect and preserve the exact result-code semantics of the selected SQLite source.

At minimum, correctly handle the paths used by `jsonReturnFromBlob()`:

```text
rc == 0
    parsed successfully

rc == 3 with a leading negative sign
    exact SMALLEST_INT64 case

rc == 1
    malformed numeric input

other overflow result
    value is outside signed 64-bit range
```

For this helper, any value outside signed 64-bit range must fail.

Do not convert an oversized integer to `double` in `pblobJsonbInteger()`.

Recommended error for an integer outside signed 64-bit range:

```text
pblob: integer is outside the signed 64-bit range
```

This later allows `int8` packing to distinguish:

```text
valid int64 but outside int8
```

from:

```text
not representable as int64
```

#### Positive hexadecimal high-bit case

SQLite’s `jsonReturnFromBlob()` has special behavior for a positive hexadecimal literal with 16 significant digits whose high bit is set: `sqlite3DecOrHexToI64()` may return a negative bit pattern, but JSON semantics treat the literal as positive.

For `pblobJsonbInteger()`:

* do not reinterpret that bit pattern as a valid negative integer;
* do not return it as a signed integer;
* report signed 64-bit range overflow.

This helper is specifically for exact signed-integer extraction.

---

### General Numeric Extraction Helper

Implement:

```c
static int pblobJsonbNumber(
  sqlite3_context *ctx,
  JsonParse *pParse,
  u32 iNode,
  double *pValue
);
```

#### Accepted node types

Accept:

```c
JSONB_INT
JSONB_INT5
JSONB_FLOAT
JSONB_FLOAT5
```

Reject all other JSONB node types.

Recommended wrong-type error for direct helper testing:

```text
pblob: JSONB node is not numeric
```

#### Canonical decimal integer and floating nodes

For:

```c
JSONB_INT
JSONB_FLOAT
JSONB_FLOAT5
```

use SQLite’s floating parser.

Required algorithm:

1. Validate and locate the payload.
2. Duplicate the payload with:

   ```c
   sqlite3DbStrNDup()
   ```
3. Parse with:

   ```c
   sqlite3AtoF()
   ```
4. Free the temporary string.
5. Require the parser return value to indicate success.
6. Return the resulting `double`.

This intentionally permits integer values outside signed 64-bit range when SQLite can represent them as `double`.

Do not first force canonical decimal integer nodes through signed `int64`, because the floating formats are allowed to accept JSON numeric values beyond signed 64-bit range.

#### JSON5 hexadecimal integer nodes

For:

```c
JSONB_INT5
```

adapt the corresponding path from `jsonReturnFromBlob()`.

Required behavior:

1. Detect an optional leading minus sign.
2. Duplicate the unsigned literal.
3. Parse using:

   ```c
   sqlite3DecOrHexToI64()
   ```
4. Handle ordinary signed-range values.
5. Handle exact negative `SMALLEST_INT64`.
6. Handle a positive 16-digit hexadecimal value whose high bit is set:

   * reinterpret the returned 64-bit bit pattern as `sqlite3_uint64`;
   * convert that unsigned value to `double`;
   * do not treat it as negative.
7. Apply a leading negative sign where valid.
8. Reject malformed hexadecimal syntax.
9. Reject hexadecimal values too large for the supported SQLite path.

The implementation must avoid strict-aliasing violations when reinterpreting signed and unsigned 64-bit bit patterns.

Do not copy this pattern from `jsonReturnFromBlob()` if it uses aliasing that is unsuitable under the project’s warning or sanitizer settings. Use an alias-safe equivalent such as `memcpy()` where needed.

#### Floating result finiteness

Do not reject infinity or NaN in this helper solely because the result is non-finite.

Reason:

* this helper’s responsibility is extraction according to SQLite numeric semantics;
* target-format range and finite checks belong to later binary16 and binary32 packing workflows.

However:

* malformed input must still fail;
* JSON null must not be treated as NaN;
* nonnumeric node types must fail.

Later stages will perform explicit target-format finite checks.

---

### Temporary Storage and OOM

Numeric payloads are not NUL-terminated.

Use:

```c
sqlite3DbStrNDup(
  pParse->db,
  zPayload,
  (int)nPayload
)
```

or the exact signature used by the selected SQLite source.

On allocation failure:

```c
sqlite3_result_error_nomem(ctx);
```

Return failure immediately.

Always free successful allocations using:

```c
sqlite3DbFree(pParse->db, zCopy);
```

Do not mix allocator families.

Do not use:

```c
malloc()
free()
sqlite3_malloc()
sqlite3_free()
```

for these temporary database-owned strings.

Before converting `u32 nPayload` to `int`, verify that the value is within the supported integer range if the selected helper signature requires `int`.

---

### No Public SQL Integration Yet

Do not call either new helper from:

```c
pblobPackFunc()
pblobUnpackFunc()
```

Valid SQL calls must still end with the existing placeholder errors after Stage 3 validation.

This stage tests the helpers through test-only access only.

---

### Test-Only Access

Add narrowly scoped test-only access under:

```c
#ifdef SQLITE_TEST
```

Use the Stage 4 test infrastructure where possible.

Acceptable test operations:

```text
extract JSONB integer at root
extract JSONB number at root
extract array element by simple test-only index
```

A simple test-only Tcl command may:

1. accept JSON text;
2. parse it with:

   ```c
   jsonParseFuncArg()
   ```
3. optionally require a one-element array or select a specified array element;
4. invoke the extraction helper;
5. return the extracted SQLite numeric value.

The test wrapper may use `jsonLookupStep()` or direct array traversal, but do not add general production array-traversal helpers in this stage.

Keep all wrapper logic test-only.

Do not register production SQL functions for helper testing.

---

### Integer Extraction Test Cases

Test canonical decimal integers:

```text
0
1
-1
127
-128
9223372036854775807
-9223372036854775808
```

Verify exact SQL integer results.

Test JSON5 hexadecimal integers:

```text
0x0
0x1
0x7f
0x80
0x7fffffffffffffff
-0x1
-0x80
-0x8000000000000000
```

Verify exact signed results where representable.

Test signed-range overflow:

```text
9223372036854775808
-9223372036854775809
0x8000000000000000
0xffffffffffffffff
-0x8000000000000001
```

Expected: signed 64-bit range error.

The exact JSON5 literals accepted must follow the selected SQLite parser. Do not independently broaden syntax.

---

### Integer Helper Wrong-Type Tests

Invoke the helper against:

```json
1.0
1e0
null
true
false
"1"
[]
{}
```

Expected: integer-node type error.

This verifies that mathematically integral floating nodes are not accepted by the integer helper.

---

### General Numeric Extraction Test Cases

Test canonical numeric forms:

```text
0
-0
1
-1
1.0
-1.0
0.5
-0.5
1e0
1e10
1e-10
```

Test SQLite-supported JSON5 numeric forms:

```text
+1
.5
1.
0x7f
-0x80
```

Verify numeric equality with SQLite’s own JSON extraction behavior where appropriate.

Test large decimal integers that exceed signed 64-bit but are representable as `double`:

```text
9223372036854775808
18446744073709551615
```

The expected result should match the selected SQLite numeric conversion behavior, not an independently invented decimal policy.

Test hexadecimal unsigned-high-bit behavior:

```text
0x8000000000000000
0xffffffffffffffff
```

Verify that positive literals produce positive `double` values.

Test negative hexadecimal values at the signed boundary.

---

### General Numeric Helper Wrong-Type Tests

Invoke against:

```json
null
true
false
"1"
[]
{}
```

Expected: numeric-node type error.

---

### JSON5 Infinity and NaN Behavior

Test SQLite parser behavior explicitly.

The uploaded `json.c` maps accepted infinity spellings to large numeric payloads such as:

```text
9e999
-9e999
```

and maps accepted NaN spellings to JSON null.

Test at least:

```text
Infinity
-Infinity
NaN
QNaN
SNaN
```

Expected helper behavior:

* infinity forms reach `pblobJsonbNumber()` as numeric nodes and produce SQLite’s parsed numeric result;
* NaN forms reach the helper as `JSONB_NULL` and are rejected as nonnumeric.

Do not add custom NaN or infinity syntax handling in `pblob.c`.

---

### Negative Zero Tests

Test:

```text
-0
-0.0
-0e0
```

For `pblobJsonbNumber()` verify whether SQLite preserves negative zero through `sqlite3AtoF()` for each lexical form.

Record the actual selected-source behavior in the test expectations.

Do not normalize the result manually in this helper.

The later packing workflow will test bit-level negative-zero preservation.

---

### Malformed Internal JSONB Tests

Through test-only direct construction or mutation, test:

* node offset past the end;
* truncated node header;
* zero-length integer payload;
* zero-length floating payload;
* payload extending past `nBlob`;
* reserved node type;
* malformed decimal payload;
* malformed hexadecimal payload;
* sign-only payload.

Expected: deterministic helper failure, never out-of-bounds access.

Do not expose malformed JSONB handling through production SQL.

---

### OOM Tests

Where the SQLite test harness supports fault injection, test allocation failure during:

```c
sqlite3DbStrNDup()
```

for both helpers.

Verify:

* `sqlite3_result_error_nomem()` is used;
* no temporary allocation leaks;
* a subsequent helper invocation succeeds;
* no stale result is returned.

Keep these focused on helper-local temporary allocation.

Full extension fault testing belongs to a later stage.

---

### Existing SQL Regression Tests

Retain all Stage 2–4 tests.

Verify that:

```sql
SELECT pblob_pack('[]', 'int8');
SELECT pblob_unpack(x'', 'int8');
```

still produce their existing placeholder errors.

Verify NULL, type, format, endian-helper, classification, signed-byte, and checked-size tests remain passing.

No public SQL result may change in Stage 5.

---

### Build Verification

Perform all required build configurations.

#### Normal Build

Verify:

* both helpers compile;
* production helpers remain `static`;
* no unused-function warnings appear;
* public SQL behavior remains unchanged;
* no test-only helper interface is present.

If the new helpers are unused in production until Stage 6, follow the same established unused-static handling selected in Stage 4.

Do not remove `static`.

#### Test Build

Build `testfixture` or the project’s equivalent with:

```text
SQLITE_TEST
```

Run:

* integer extraction tests;
* general numeric extraction tests;
* JSON5 numeric tests;
* wrong-type tests;
* signed-boundary tests;
* malformed internal-node tests;
* focused OOM tests;
* all previous stage tests.

#### JSON-Disabled Build

Build with:

```text
SQLITE_OMIT_JSON
```

Verify:

* the helpers are excluded;
* no JSON or test-helper references remain;
* no unresolved symbols occur;
* no warnings are introduced.

---

### Prohibited Work

Do not implement:

* production calls to `jsonParseFuncArg()`;
* production JSON root validation;
* production array traversal;
* production element iteration;
* `jsonbArrayCount()` in public workflows;
* packed-output allocation;
* `int8` packing;
* `int8` unpacking;
* binary16 packing or unpacking;
* binary32 packing or unpacking;
* BLOB-length validation;
* JSON output construction;
* JSON subtype assignment;
* target-format range checks;
* target-format finite checks;
* element-indexed public errors;
* reference-vector generation;
* complete extension fault tests;
* schema integration tests.

Do not:

* modify `json.c`;
* modify FP16;
* add another numeric parser;
* add `pblob.h`;
* expose a public C API;
* register additional production SQL functions.

---

### Expected Deliverables

Provide:

1. Updated `pblob.c`.
2. Updated test-only helper access.
3. Focused Stage 5 tests.
4. Exact build commands executed.
5. Exact test commands executed.
6. Results for:

   * normal build;
   * test build;
   * JSON-disabled build.
7. A concise list of modified files.
8. Confirmation that:

   * integer extraction uses `sqlite3DecOrHexToI64()`;
   * general numeric extraction uses `sqlite3AtoF()` and adapted JSON5 integer handling;
   * temporary payloads use SQLite database allocators;
   * signed 64-bit boundaries are handled;
   * positive high-bit hexadecimal JSON integers are handled correctly for `double`;
   * malformed nodes and OOM are handled;
   * helpers remain private;
   * public SQL behavior remains unchanged;
   * no packing or unpacking workflow was added;
   * no public header or API was added.

---

### Acceptance Criteria

Stage 5 is complete only when:

* `pblobJsonbInteger()` correctly extracts every supported signed integer case;
* signed 64-bit overflow is rejected;
* floating JSONB nodes are rejected by the integer helper;
* `pblobJsonbNumber()` accepts all four JSONB numeric node types;
* canonical decimal values use SQLite’s floating parser;
* JSON5 hexadecimal values follow SQLite’s existing semantics;
* positive high-bit hexadecimal values convert to positive `double`;
* nonnumeric node types are rejected;
* malformed payloads fail safely;
* temporary-allocation OOM is reported correctly;
* all helper-local allocations are released;
* all Stage 2–4 tests remain passing;
* normal build succeeds;
* test build succeeds;
* JSON-disabled build succeeds;
* no new warnings appear;
* public SQL behavior still ends in placeholder errors;
* no production packing or unpacking logic exists;
* no public C API or header exists.

Stop after satisfying these criteria. Do not proceed to Stage 6.

---
---

## 📗 Stage 6: Implement `int8` Packing

Implement only Stage 6 of the packed numeric BLOB extension.

This stage begins from the completed Stage 5 state, where:

* `pblob.c` is compiled into the SQLite amalgamation after `json.c`;
* `pblob_pack()` and `pblob_unpack()` are auto-registered;
* NULL propagation, first-argument storage-class validation, and exact format parsing are implemented;
* endian helpers, binary classification helpers, signed-byte decoding, and checked packed-size calculation are implemented;
* `pblobJsonbInteger()` and `pblobJsonbNumber()` are implemented and tested;
* valid public SQL calls still terminate with temporary “not implemented” errors;
* no production JSON parsing, array traversal, packing, unpacking, BLOB allocation, or JSON output construction exists.

Implement only the complete `int8` packing workflow in:

```sql
pblob_pack(json_array, 'int8')
```

Do not implement:

```text
pblob_unpack(..., 'int8')
<f2
>f2
<f4
>f4
```

Those remain placeholders.

### Objective

Make this SQL workflow production-complete:

```sql
pblob_pack(json_array, 'int8') -> BLOB
```

The implementation must:

* accept only SQL TEXT JSON input;
* parse and validate JSON using `json.c`;
* require a top-level JSON array;
* require every array element to be a JSON integer node;
* accept both canonical JSON integers and SQLite-supported JSON5 hexadecimal integers;
* extract each integer with `pblobJsonbInteger()`;
* require every value to be in the inclusive range `-128..127`;
* encode each value as one two’s-complement byte;
* allocate the exact output size once;
* return a raw headerless BLOB;
* correctly handle an empty array;
* report the first invalid element using a zero-based index;
* preserve all existing behavior for other formats and for `pblob_unpack()`.

### Scope

This stage is limited to:

1. Adding production JSON parsing to `pblob_pack()`.
2. Requiring a root JSON array.
3. Counting and traversing array elements.
4. Allocating an exact output BLOB for `int8`.
5. Validating and packing integer elements.
6. Returning the BLOB with correct ownership.
7. Adding `int8` pack tests.
8. Adding focused OOM and malformed-internal checks directly related to this workflow.
9. Preserving all prior-stage tests.

Do not implement unpacking or floating-point formats.

---

### Public Behavior Introduced in This Stage

The following calls must now succeed:

```sql
SELECT pblob_pack('[]', 'int8');
SELECT pblob_pack('[0]', 'int8');
SELECT pblob_pack('[-128,-1,0,1,127]', 'int8');
```

Calls using:

```text
<f2
>f2
<f4
>f4
```

must still return their existing temporary not-implemented errors after common validation.

`pblob_unpack()` must remain unchanged and still return its temporary not-implemented error for valid arguments.

---

### `pblob_pack()` Control Flow

Update `pblobPackFunc()` to follow this order:

1. Confirm `argc == 2`.
2. Propagate SQL NULL if either argument is NULL.
3. Require the first argument to be SQL TEXT.
4. Parse the format argument with `pblobParseFormat()`.
5. If the selected format is not `PBLOB_INT8`, return the existing temporary format-specific placeholder error.
6. Parse the JSON TEXT with:

   ```c
   jsonParseFuncArg(ctx, argv[0], 0)
   ```
7. Require the root node to be `JSONB_ARRAY`.
8. Count the elements.
9. Compute the exact output size.
10. Allocate one output buffer.
11. Traverse and validate every array element.
12. Pack each value into one byte.
13. Return the BLOB.
14. Release all remaining owned resources.

The order is part of the contract.

Format parsing must still occur before JSON parsing.

Therefore:

```sql
SELECT pblob_pack('malformed', 'bad');
```

must report the unsupported-format error, not malformed JSON.

---

### JSON Parsing

Call:

```c
JsonParse *pParse = jsonParseFuncArg(ctx, argv[0], 0);
```

Required behavior:

* TEXT JSON and SQLite-supported JSON5 are accepted according to the selected `json.c`;
* malformed JSON errors are reported by `json.c`;
* OOM is reported by `json.c`;
* parse-cache behavior is preserved;
* no independent JSON parser is introduced.

If `jsonParseFuncArg()` returns `NULL`, return immediately.

Do not add a second malformed-JSON error unless required by a defensive internal failure after parsing.

Always release a successful parse using:

```c
jsonParseFree(pParse);
```

---

### Root Array Validation

The root JSONB node begins at offset zero.

Require:

```c
(pParse->aBlob[0] & 0x0f) == JSONB_ARRAY
```

If the parsed JSON root is not an array, report:

```text
pblob_pack: expected a JSON array
```

Valid but rejected roots include:

```json
null
true
false
0
1.0
"abc"
{}
```

Do not treat a scalar as a one-element array.

Do not accept an object containing an array.

---

### Array Element Count

After confirming the root is `JSONB_ARRAY`, obtain the element count using:

```c
jsonbArrayCount(pParse, 0)
```

Do not count delimiters or reparse the original JSON text.

The result type is `u32` in the selected `json.c`.

Convert it safely to the type required by `pblobCheckedSize()`.

For `int8`:

```text
output size = element count
```

because the element width is one byte.

---

### Exact Output-Size Calculation

Call the existing checked-size helper with:

```text
element count
element width = 1
```

It must enforce:

* arithmetic overflow protection;
* current `SQLITE_LIMIT_LENGTH`.

If size validation fails:

* release `JsonParse`;
* return without allocating;
* preserve the error already set by `pblobCheckedSize()`.

Do not duplicate the limit logic inside `pblobPackFunc()`.

---

### Root Payload Location

Obtain the root node’s header and payload sizes using:

```c
u32 nRootPayload = 0;
u32 nRootHeader = jsonbPayloadSize(pParse, 0, &nRootPayload);
```

Require:

```text
nRootHeader != 0
nRootHeader + nRootPayload == pParse->nBlob
```

Use overflow-safe arithmetic.

Set:

```text
iNode = nRootHeader
iEnd  = nRootHeader + nRootPayload
```

Although `jsonParseFuncArg()` should have produced valid internal JSONB, these checks remain mandatory.

On failure, report:

```text
pblob_pack: malformed internal JSON representation
```

---

### Output Allocation

Allocate exactly the checked output size once.

Use an allocator compatible with the destructor passed to the SQLite result API.

Preferred:

```c
u8 *pOut = sqlite3_malloc64(nOut);
```

and later:

```c
sqlite3_result_blob64(ctx, pOut, nOut, sqlite3_free);
```

For a zero-length output:

* return a zero-length BLOB;
* do not treat a `NULL` result from a zero-byte allocation as OOM;
* avoid allocating if unnecessary.

One acceptable pattern is:

```text
if nOut == 0:
    return zero-length BLOB directly
else:
    allocate nOut bytes
```

Use the selected SQLite source’s safe convention for returning a zero-length BLOB.

Do not allocate per element.

---

### Array Traversal

Traverse the array payload sequentially.

For each zero-based element index `iElem`:

1. Verify:

   ```text
   iNode < iEnd
   ```
2. Call:

   ```c
   nHeader = jsonbPayloadSize(pParse, iNode, &nPayload);
   ```
3. Require:

   ```text
   nHeader != 0
   iNode + nHeader + nPayload <= iEnd
   ```
4. Inspect:

   ```c
   eType = pParse->aBlob[iNode] & 0x0f;
   ```
5. Require:

   ```text
   eType == JSONB_INT or eType == JSONB_INT5
   ```
6. Call:

   ```c
   pblobJsonbInteger(ctx, pParse, iNode, &value)
   ```
7. Range-check `value`.
8. Encode one byte.
9. Advance:

   ```text
   iNode += nHeader + nPayload
   ```

After the loop require:

```text
iNode == iEnd
processed element count == jsonbArrayCount() result
```

If the count and traversal disagree, report malformed internal JSON.

Do not recurse.

Nested arrays and objects are rejected as invalid element types.

---

### Element Type Validation

For `int8`, accept only:

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
JSONB_TEXT
JSONB_TEXTJ
JSONB_TEXT5
JSONB_TEXTRAW
JSONB_ARRAY
JSONB_OBJECT
```

A floating lexical form must be rejected even when mathematically integral.

Examples that must fail:

```json
[1.0]
[1e0]
[-0.0]
[1,2.0,3]
```

Recommended error:

```text
pblob_pack: element N must be an integer for format int8
```

Where `N` is the zero-based element index.

The first invalid element must stop processing.

---

### Integer Extraction

For each accepted integer node, call:

```c
pblobJsonbInteger()
```

Do not:

* parse the payload again;
* call `sqlite3AtoF()`;
* use SQL coercion;
* convert through `double`;
* use `strtol()` or related functions.

If `pblobJsonbInteger()` reports signed 64-bit overflow, convert that into the public `int8` range error when practical:

```text
pblob_pack: element N is outside the int8 range
```

The public API does not need to expose the internal signed-64-bit distinction.

Do not allow helper-local generic errors to omit the element index when a public element error can be emitted instead.

---

### `int8` Range Validation

Require:

```text
-128 <= value <= 127
```

Reject all other values.

Examples:

```text
-129
128
-1000
1000
0x80
-0x81
```

Recommended error:

```text
pblob_pack: element N is outside the int8 range
```

Do not:

* clamp;
* saturate;
* wrap;
* mask before validation;
* convert modulo 256.

---

### Byte Encoding

After successful range validation, encode exactly one byte.

Acceptable logic:

```c
pOut[iElem] = (u8)(value & 0xff);
```

or an equivalent explicit conversion whose behavior is defined after the range check.

Required mappings:

```text
-128 -> 80
-127 -> 81
-1   -> FF
0    -> 00
1    -> 01
126  -> 7E
127  -> 7F
```

Do not depend on:

```c
(char)value
(signed char)value
(int8_t)value
```

---

### Empty Array

Input:

```sql
SELECT pblob_pack('[]', 'int8');
```

must return:

```text
storage class: blob
length: 0
hex: empty string
```

Required SQL checks:

```sql
SELECT typeof(pblob_pack('[]','int8'));
SELECT length(pblob_pack('[]','int8'));
SELECT hex(pblob_pack('[]','int8'));
```

Expected:

```text
blob
0
''
```

Do not return SQL NULL.

Do not return TEXT.

---

### Result Ownership

On successful nonempty packing:

```c
sqlite3_result_blob64(ctx, pOut, nOut, sqlite3_free);
```

After ownership transfer:

```c
pOut = 0;
```

or otherwise ensure cleanup does not free it again.

On every failure before ownership transfer:

```c
sqlite3_free(pOut);
```

if non-NULL.

Always release:

```c
jsonParseFree(pParse);
```

after successful parse ownership is acquired.

Use a single cleanup block where practical.

Do not mix SQLite database allocators used by `JsonParse` with the general allocator used for the returned BLOB.

---

### Error Precedence

Preserve this order:

```text
NULL propagation
-> first argument storage class
-> format storage class
-> exact format value
-> placeholder for non-int8 supported formats
-> JSON parsing
-> root array validation
-> size validation
-> element validation and packing
```

Examples:

```sql
SELECT pblob_pack(1, 'int8');
```

Expected: first-argument storage-class error.

```sql
SELECT pblob_pack('bad JSON', 'bad');
```

Expected: unsupported-format error.

```sql
SELECT pblob_pack('bad JSON', 'int8');
```

Expected: malformed JSON.

```sql
SELECT pblob_pack('{}', 'int8');
```

Expected: expected-array error.

```sql
SELECT pblob_pack('[1.0]', 'int8');
```

Expected: element-type error.

```sql
SELECT pblob_pack('[128]', 'int8');
```

Expected: range error.

---

### Non-`int8` Formats

For:

```text
<f2
>f2
<f4
>f4
```

retain the existing temporary error after common validation.

Do not parse JSON for those formats in this stage.

This means:

```sql
SELECT pblob_pack('bad JSON', '<f2');
```

should still return the temporary not-implemented error, not malformed JSON.

Only the `int8` branch becomes functional.

---

### `pblob_unpack()` Behavior

Do not change `pblobUnpackFunc()` beyond incidental refactoring required to compile.

For valid arguments it must still return:

```text
pblob_unpack: not implemented
```

or the previously established equivalent.

Do not retrieve BLOB bytes.

Do not validate BLOB length.

Do not initialize `JsonString`.

---

### Primary `int8` Packing Tests

Add exact-byte tests.

#### Boundaries

```sql
SELECT hex(
  pblob_pack('[-128,-127,-1,0,1,126,127]', 'int8')
);
```

Expected:

```text
8081FF00017E7F
```

#### Required minimal vector

```sql
SELECT hex(
  pblob_pack('[-128,-1,0,1,127]', 'int8')
);
```

Expected:

```text
80FF00017F
```

#### Ordinary values

```sql
SELECT hex(
  pblob_pack('[1,2,3,10,100]', 'int8')
);
```

Expected:

```text
0102030A64
```

#### Negative values

```sql
SELECT hex(
  pblob_pack('[-1,-2,-3,-10,-100]', 'int8')
);
```

Expected:

```text
FFFEFDF69C
```

---

### Full `int8` Domain Test

Create a JSON array containing every integer from:

```text
-128 through 127
```

Pack it and compare against a committed expected 256-byte hex value.

The expected byte order is:

```text
80 81 82 ... FE FF 00 01 02 ... 7E 7F
```

The expected vector must be independent of `pblob.c`.

This test is mandatory.

It verifies:

* complete range handling;
* two’s-complement byte encoding;
* output order;
* absence of signed-char dependence.

---

### JSON5 Integer Tests

Test SQLite-supported hexadecimal input:

```sql
SELECT hex(
  pblob_pack('[0x0,0x1,0x7f,-0x1,-0x80]', 'int8')
);
```

Expected:

```text
00017FFF80
```

Also test JSON5 syntax accepted by the selected parser where relevant:

```text
[+1]
[1,]
[/*comment*/1]
```

Only integer node forms are accepted.

Do not independently define JSON5 syntax.

---

### Out-of-Range Tests

Reject:

```json
[-129]
[128]
[-1000]
[1000]
[0x80]
[-0x81]
```

Verify the exact zero-based element index.

Also test arrays where the invalid value is not first:

```json
[0,1,128,2]
[-128,-129,0]
```

Expected indexes:

```text
2
1
```

---

### Wrong-Type Tests

Reject:

```json
[1.0]
[1e0]
[-0.0]
[null]
[true]
[false]
["1"]
[[]]
[{}]
```

Test mixed arrays:

```json
[1,2.0,3]
[1,null,3]
[1,"2",3]
[1,[2],3]
```

Verify the first invalid zero-based index.

---

### Root-Type Tests

Reject valid non-array JSON roots:

```text
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

Do not report element errors for non-array roots.

---

### Malformed JSON Tests

Test at least:

```text
empty TEXT
[
[1
[1,,2]
[1 2]
[,1]
[01]
[0x]
[.]
[1e]
[1e+]
```

Expected: malformed JSON from the selected SQLite parser.

Do not replace core parser error behavior with extension-specific syntax messages.

---

### Empty and Large Array Tests

Test element counts:

```text
0
1
2
128
256
768
1024
1536
4096
```

For each successful case verify:

```text
length(result) == element count
typeof(result) == blob
```

Use valid repeated or patterned `int8` values.

For representative large arrays also verify:

* first byte;
* middle byte;
* last byte;
* repeated execution yields identical output.

---

### SQLite Length-Limit Test

Temporarily lower:

```text
SQLITE_LIMIT_LENGTH
```

Then test an `int8` array whose packed output:

* exactly equals the limit;
* exceeds the limit by one byte.

Expected:

```text
at limit -> success
over limit -> result-too-large failure
```

Restore the original limit.

This test should exercise the existing `pblobCheckedSize()` path.

---

### Internal Traversal Failure Tests

Through test-only hooks, exercise defensive failures such as:

* root payload length inconsistent with `nBlob`;
* truncated child node;
* child payload crossing the array end;
* element count disagreement.

Expected:

```text
pblob_pack: malformed internal JSON representation
```

These conditions cannot normally arise from valid TEXT parsed by `json.c`, but the checks are required.

Do not add production acceptance of caller-supplied JSONB merely to test these cases.

---

### Focused OOM Tests

Use SQLite fault injection where available.

Exercise OOM during:

1. `jsonParseFuncArg()` allocation.
2. JSON text-to-JSONB conversion.
3. exact output BLOB allocation.
4. temporary integer payload duplication inside `pblobJsonbInteger()`.

Verify:

* an OOM error is returned;
* no partial BLOB is returned;
* `JsonParse` and output memory are released;
* a subsequent valid call succeeds.

Full fault-matrix coverage remains for a later stage.

---

### Prepared-Statement Reuse

Prepare:

```sql
SELECT pblob_pack(?1, 'int8');
```

Execute repeatedly with:

```text
[]
[1]
[-128,127]
[1,2,3]
malformed JSON
[0]
```

Verify:

* valid results remain correct;
* malformed JSON does not corrupt later executions;
* cached parse behavior does not return stale data.

Also test changing both parameters:

```sql
SELECT pblob_pack(?1, ?2);
```

including transitions between:

```text
int8
<f2
bad format
int8
```

---

### Existing Regression Tests

All Stage 2–5 tests must remain passing.

In particular:

* NULL propagation;
* exact format parsing;
* wrong storage classes;
* embedded-NUL format rejection;
* endian helpers;
* classification helpers;
* signed-byte decoding;
* checked-size tests;
* JSONB numeric extraction helper tests.

For valid floating-format pack calls, verify the placeholder remains.

For valid unpack calls, verify the placeholder remains.

---

### Test Module Changes

Extend:

```text
test/pblob.test
```

with public SQL tests for `int8` packing.

Use existing Stage 4 and Stage 5 test-only infrastructure for:

* internal malformed traversal;
* focused OOM paths where needed.

Do not yet add the complete reference-vector, full limit, or full fault modules unless the existing test layout already separated those concerns.

Do not create a public SQL debug function.

---

### Build Verification

Perform all required build configurations.

#### Normal Build

Verify:

* `int8` packing compiles and links;
* all helpers remain private;
* no new warnings appear;
* exact SQL vectors pass through the release shell or normal library;
* floating pack and all unpack paths remain placeholders.

#### Test Build

Build `testfixture` or the project’s equivalent with:

```text
SQLITE_TEST
```

Run:

* all Stage 6 `int8` pack tests;
* focused OOM tests;
* prepared-statement tests;
* all prior-stage tests.

#### JSON-Disabled Build

Build with:

```text
SQLITE_OMIT_JSON
```

Verify:

* build and link succeed;
* no `pblob` SQL functions are registered;
* no JSONB or `int8` pack symbols remain unresolved;
* no warnings are introduced.

---

### Prohibited Work

Do not implement:

* `pblob_unpack()` conversion;
* signed-byte unpacking through SQL;
* BLOB-length validation for unpacking;
* `JsonString` output;
* JSON result subtype behavior;
* binary16 packing;
* binary16 unpacking;
* binary32 packing;
* binary32 unpacking;
* floating target range checks;
* floating non-finite handling;
* FP16 conversion calls in production;
* binary32 bitcasts in production;
* automatic format inference;
* JSONB input acceptance for `pblob_pack()`;
* arrays containing floating values for `int8`;
* clamping or wrapping;
* public C APIs;
* public headers.

Do not modify:

* `json.c`;
* the vendored FP16 implementation;
* unrelated SQLite code.

Do not register any new production SQL functions.

---

### Expected Deliverables

Provide:

1. Updated `pblob.c`.
2. Updated `test/pblob.test`.
3. Any narrowly scoped test-only changes required for traversal and OOM testing.
4. Exact build commands executed.
5. Exact test commands executed.
6. Results for:

   * normal build;
   * test build;
   * JSON-disabled build.
7. A concise list of modified files.
8. Confirmation that:

   * only `pblob_pack(..., 'int8')` became functional;
   * JSON parsing uses `jsonParseFuncArg()`;
   * root arrays are required;
   * array traversal uses `jsonbPayloadSize()`;
   * element counting uses `jsonbArrayCount()`;
   * integer extraction uses `pblobJsonbInteger()`;
   * output allocation is exact and single-shot;
   * out-of-range values are rejected;
   * the empty array returns a zero-length BLOB;
   * other formats and all unpacking remain placeholders;
   * no public API or header was added.

---

### Acceptance Criteria

Stage 6 is complete only when:

* `pblob_pack('[]','int8')` returns a zero-length BLOB;
* every valid integer in `-128..127` packs to the exact required byte;
* the complete `int8` domain test passes;
* SQLite-supported hexadecimal integers pack correctly;
* floating lexical values are rejected;
* null, boolean, text, array, and object elements are rejected;
* non-array roots are rejected;
* malformed JSON is handled by `json.c`;
* out-of-range integers are rejected without clamping or wrapping;
* the first invalid zero-based element index is reported;
* output allocation is exact and performed once;
* SQLite length limits are enforced;
* OOM paths release all owned resources;
* prepared-statement reuse is correct;
* all Stage 2–5 tests remain passing;
* `<f2`, `>f2`, `<f4`, and `>f4` packing remain placeholders;
* all `pblob_unpack()` calls remain placeholders;
* normal build succeeds;
* test build succeeds;
* JSON-disabled build succeeds;
* no new warnings appear;
* no public C API or header exists.

Stop after satisfying these criteria. Do not proceed to Stage 7.

---
---

## 📗 Stage 7: `int8` Unpacking

Implement only Stage 7 of the packed numeric BLOB extension.

This stage begins from the completed Stage 6 state, where:

* `pblob.c` is compiled into the SQLite amalgamation after `json.c`;
* `pblob_pack()` and `pblob_unpack()` are auto-registered;
* NULL propagation, strict storage-class validation, and exact format parsing are implemented;
* endian helpers, binary classification helpers, signed-byte decoding, and checked packed-size calculation are implemented;
* JSONB integer and general numeric extraction helpers are implemented;
* `pblob_pack(json_array, 'int8')` is production-complete;
* `<f2`, `>f2`, `<f4`, and `>f4` packing remain placeholders;
* every `pblob_unpack()` format remains a placeholder;
* no production JSON output construction exists.

Implement only the complete `int8` unpacking workflow:

```sql
pblob_unpack(blob, 'int8') -> JSON text
```

Do not implement binary16 or binary32 behavior in either direction.

### Objective

Make this SQL workflow production-complete:

```sql
pblob_unpack(blob, 'int8')
```

The implementation must:

* accept only SQL BLOB input;
* treat every byte as one signed two’s-complement `int8` value;
* decode bytes without depending on `char` signedness;
* preserve element order;
* construct compact valid JSON text;
* return `[]` for a zero-length BLOB;
* assign SQLite’s JSON subtype to the result;
* use SQLite’s internal `JsonString` facilities;
* avoid per-element heap allocation;
* handle OOM and output-size limits correctly;
* leave all floating formats as placeholders.

### Scope

This stage is limited to:

1. Retrieving the input BLOB for `pblob_unpack()`.
2. Dispatching the `int8` format to a real unpacking implementation.
3. Decoding every byte using the existing signed-byte helper.
4. Constructing a JSON array with `JsonString`.
5. Returning JSON-subtyped TEXT.
6. Testing exact `int8` unpack behavior.
7. Testing empty, large, repeated, and malformed-call cases relevant to this workflow.
8. Preserving all Stage 2–6 behavior.

Do not modify `pblob_pack(..., 'int8')` except for necessary refactoring that preserves behavior exactly.

---

### Public Behavior Introduced in This Stage

The following calls must now succeed:

```sql
SELECT pblob_unpack(x'', 'int8');
SELECT pblob_unpack(x'00', 'int8');
SELECT pblob_unpack(x'80FF00017F', 'int8');
```

Expected JSON text:

```text
[]
[0]
[-128,-1,0,1,127]
```

Calls using:

```text
<f2
>f2
<f4
>f4
```

must still return their existing temporary not-implemented errors after common validation.

---

### `pblob_unpack()` Control Flow

Update `pblobUnpackFunc()` to follow this order:

1. Confirm `argc == 2`.
2. Propagate SQL NULL if either argument is NULL.
3. Require `argv[0]` to have SQL storage class `SQLITE_BLOB`.
4. Parse and validate the format argument.
5. If the selected format is not `PBLOB_INT8`, return the existing temporary not-implemented error.
6. Retrieve the BLOB pointer and length.
7. Initialize a `JsonString`.
8. Append the opening array bracket.
9. Decode and append every byte.
10. Append the closing array bracket.
11. Return the JSON string.
12. Assign `JSON_SUBTYPE`.
13. Release any remaining temporary state.

The established validation order must remain unchanged.

---

### BLOB Retrieval

After storage-class and format validation, retrieve:

```c
const u8 *pBlob = sqlite3_value_blob(argv[0]);
sqlite3_uint64 nBlob = sqlite3_value_bytes(argv[0]);
```

Use the exact APIs and integer types supported by the selected SQLite source.

If only the `int`-sized byte-count API is available in the local code path, ensure the value is consistent with SQLite’s configured length limit and convert safely.

Required behavior:

* zero-length BLOB is valid;
* a NULL pointer with zero length is valid;
* a NULL pointer with nonzero length must be treated as OOM or internal failure according to SQLite conventions;
* no input copy is required.

Do not call:

```c
sqlite3_value_text()
```

on the BLOB.

Do not reinterpret the input as JSONB.

Do not require any header or metadata.

---

### `int8` Element Count

For format `int8`:

```text
element count = BLOB byte length
```

No divisibility check is needed because the element width is one byte.

Do not call `pblobCheckedSize()` merely to calculate the input element count.

The checked-size helper will remain relevant for later wider formats and output-allocation planning.

---

### JSON Output Construction

Use SQLite’s private JSON output facilities already visible from `json.c`.

Initialize:

```c
JsonString out;
jsonStringInit(&out, ctx);
```

Use the exact selected-source signature.

Append:

```text
[
elements
]
```

using:

```c
jsonAppendChar()
jsonPrintf()
jsonReturnString()
```

Do not construct the JSON result using:

```c
sqlite3_str
sqlite3_mprintf()
snprintf()
sprintf()
manual heap concatenation
```

Do not introduce another JSON writer.

---

### Array Formatting

The output must be compact.

Examples:

```text
[]
[0]
[-1]
[-128,-1,0,1,127]
```

Do not emit:

```text
[ ]
[ 0 ]
[-128, -1, 0, 1, 127]
```

Append a comma before every element except the first.

One acceptable pattern is:

```c
jsonAppendChar(&out, '[');

for( i = 0; i < nBlob; ++i ){
  if( i != 0 ){
    jsonAppendChar(&out, ',');
  }
  jsonPrintf(20, &out, "%d", pblobDecodeInt8(pBlob[i]));
}

jsonAppendChar(&out, ']');
```

Use a sufficiently bounded `jsonPrintf()` size argument consistent with SQLite’s internal conventions.

Do not append an extra trailing comma.

---

### Signed Byte Decoding

For each input byte call the existing helper:

```c
pblobDecodeInt8()
```

Do not duplicate its logic inside the callback.

Do not use:

```c
(char)pBlob[i]
(signed char)pBlob[i]
(int8_t)pBlob[i]
```

Required mappings include:

```text
00 -> 0
01 -> 1
7F -> 127
80 -> -128
81 -> -127
FE -> -2
FF -> -1
```

The output must use JSON integer syntax.

Do not emit floating syntax such as:

```text
0.0
-1.0
```

---

### Empty BLOB

Input:

```sql
SELECT pblob_unpack(x'', 'int8');
```

must return:

```text
[]
```

Required checks:

```sql
SELECT typeof(pblob_unpack(x'', 'int8'));
SELECT pblob_unpack(x'', 'int8');
SELECT json_valid(pblob_unpack(x'', 'int8'));
SELECT json_array_length(pblob_unpack(x'', 'int8'));
```

Expected:

```text
text
[]
1
0
```

Do not return:

* SQL NULL;
* an empty TEXT string;
* a zero-length BLOB.

---

### Result Finalization

Finalize through:

```c
jsonReturnString(&out, 0, 0);
```

or the exact selected-source form.

After successfully returning the JSON text, assign:

```c
sqlite3_result_subtype(ctx, JSON_SUBTYPE);
```

Use the ordering required by the selected SQLite implementation.

The result registration already includes:

```c
SQLITE_RESULT_SUBTYPE
```

Do not remove that flag.

If `jsonReturnString()` has already reported OOM or another error, do not overwrite it with subtype handling.

Use the selected `JsonString` error state rather than inventing parallel error tracking.

---

### JSON Subtype

The returned result must have:

```text
JSON_SUBTYPE
```

This is required so the result composes correctly with SQLite JSON functions.

Test at least:

```sql
SELECT json_array(pblob_unpack(x'0001FF', 'int8'));
```

Expected semantic result:

```json
[[0,1,-1]]
```

It must not be treated as a quoted JSON string:

```json
["[0,1,-1]"]
```

Also test:

```sql
SELECT json_type(pblob_unpack(x'00', 'int8'));
SELECT json_array_length(pblob_unpack(x'0001FF', 'int8'));
```

Expected:

```text
array
3
```

---

### Output Length and SQLite Limits

JSON output is larger than the input BLOB.

The implementation must rely on `JsonString` and SQLite’s internal string-growth mechanisms to enforce allocation and length limits.

Do not precompute the exact textual output length in this stage unless the implementation already has a clear and reviewable helper.

Do not hard-code an output-size ceiling.

Verify behavior under a reduced:

```text
SQLITE_LIMIT_LENGTH
```

At minimum test:

* a result that fits;
* a result whose JSON text exceeds the configured limit.

Expected for the oversized result:

* SQLite “string or blob too big” behavior, or the selected source’s equivalent;
* no partial JSON result;
* no memory leak;
* subsequent calls still succeed.

---

### Error and Cleanup Handling

`JsonString` owns its dynamically grown buffer until result transfer or reset.

On an early failure after initialization, use:

```c
jsonStringReset(&out);
```

where required by the selected implementation.

Do not call `sqlite3_free()` directly on a `JsonString` internal buffer unless that is exactly what `jsonStringReset()` does and the local convention explicitly requires it.

Required cleanup properties:

* no memory leak on append failure;
* no double-free after `jsonReturnString()`;
* no partial result returned on OOM;
* no stale subtype assigned after an error.

A single cleanup path is preferred where it improves correctness.

---

### Error Precedence

Preserve this order:

```text
NULL propagation
-> first argument storage class
-> format storage class
-> exact format value
-> placeholder for non-int8 supported formats
-> BLOB retrieval
-> JSON output construction
```

Examples:

```sql
SELECT pblob_unpack(NULL, 'bad');
```

Expected: SQL NULL.

```sql
SELECT pblob_unpack('00', 'int8');
```

Expected: first-argument BLOB error.

```sql
SELECT pblob_unpack(x'00', 1);
```

Expected: format-must-be-text error.

```sql
SELECT pblob_unpack(x'00', 'bad');
```

Expected: unsupported-format error.

```sql
SELECT pblob_unpack(x'00', '<f2');
```

Expected: existing not-implemented error.

```sql
SELECT pblob_unpack(x'00', 'int8');
```

Expected:

```text
[0]
```

---

### Non-`int8` Formats

For:

```text
<f2
>f2
<f4
>f4
```

retain the existing temporary error.

Do not retrieve or inspect BLOB contents for those branches.

This means:

```sql
SELECT pblob_unpack(x'00', '<f2');
```

must return the placeholder even though the BLOB length is invalid for binary16.

Length divisibility checks belong to the stages that implement those formats.

---

### `pblob_pack()` Behavior

Do not change the public behavior of `pblob_pack()`.

The following must remain true:

```text
int8 packing is fully functional
floating packing formats remain placeholders
```

All exact `int8` pack vectors from Stage 6 must continue to pass.

---

### Primary `int8` Unpacking Tests

Add exact-text tests.

#### Empty BLOB

```sql
SELECT pblob_unpack(x'', 'int8');
```

Expected:

```text
[]
```

#### Boundaries

```sql
SELECT pblob_unpack(x'8081FF00017E7F', 'int8');
```

Expected:

```text
[-128,-127,-1,0,1,126,127]
```

#### Required Minimal Vector

```sql
SELECT pblob_unpack(x'80FF00017F', 'int8');
```

Expected:

```text
[-128,-1,0,1,127]
```

#### Ordinary Positive Values

```sql
SELECT pblob_unpack(x'0102030A64', 'int8');
```

Expected:

```text
[1,2,3,10,100]
```

#### Negative Values

```sql
SELECT pblob_unpack(x'FFFEFDF69C', 'int8');
```

Expected:

```text
[-1,-2,-3,-10,-100]
```

---

### Full Byte-Domain Test

Construct a BLOB containing all byte values:

```text
00 through FF
```

Unpack it and verify the exact 256-element sequence:

```text
0,1,2,...,127,-128,-127,...,-1
```

This test is mandatory.

It verifies:

* complete byte-domain decoding;
* element order;
* signed conversion;
* no dependency on `char` signedness;
* no skipped or duplicated values.

Also verify:

```sql
SELECT json_array_length(result);
```

Expected:

```text
256
```

---

### Pack/Unpack Round-Trip Tests

For representative valid integer arrays:

```text
[]
[0]
[-128]
[127]
[-128,-1,0,1,127]
full range -128..127
large patterned array
```

test:

```sql
SELECT pblob_unpack(
  pblob_pack(?1, 'int8'),
  'int8'
);
```

Compare semantically as JSON and, where the input is canonical compact integer JSON, compare exact text.

Also test byte identity:

```sql
SELECT hex(
  pblob_pack(
    pblob_unpack(?1, 'int8'),
    'int8'
  )
);
```

Expected: original BLOB hex.

For `int8`, every possible BLOB is valid, so this identity must hold for arbitrary BLOB inputs.

---

### Arbitrary BLOB Tests

Unlike wider floating formats, every BLOB length is valid for `int8`.

Test:

```text
length 0
length 1
length 2
length 3
length 127
length 128
length 255
length 256
length 1024
length 4096
```

For each:

```text
json_array_length(result) == input byte length
json_valid(result) == 1
typeof(result) == text
```

Use deterministic patterned bytes.

---

### JSON Subtype Tests

Test direct composition:

```sql
SELECT json_array(
  pblob_unpack(x'80FF00017F', 'int8')
);
```

Expected:

```text
[[-128,-1,0,1,127]]
```

Test object insertion:

```sql
SELECT json_object(
  'values',
  pblob_unpack(x'0001FF', 'int8')
);
```

Expected:

```text
{"values":[0,1,-1]}
```

Do not accept:

```text
{"values":"[0,1,-1]"}
```

Also test subtype survival through direct function composition where supported by SQLite.

Do not require subtype preservation through arbitrary storage in a table, because SQLite subtypes are transient expression metadata.

---

### Prepared-Statement Reuse

Prepare:

```sql
SELECT pblob_unpack(?1, 'int8');
```

Execute repeatedly with:

```text
x''
x'00'
x'80FF7F'
large BLOB
x'01'
```

Verify:

* no stale output;
* no buffer reuse corruption;
* correct result after a prior large allocation;
* correct result after a prior zero-length input.

Also prepare:

```sql
SELECT pblob_unpack(?1, ?2);
```

and alternate formats:

```text
int8
<f2
bad
int8
```

Verify placeholder and validation branches do not corrupt later successful `int8` executions.

---

### SQLite Length-Limit Tests

Temporarily lower:

```text
SQLITE_LIMIT_LENGTH
```

Use BLOBs whose JSON output is:

* clearly below the limit;
* exactly near the limit;
* clearly above the limit.

The expected boundary should be derived from actual compact JSON length, not guessed solely from input BLOB length.

Verify:

* fitting output succeeds;
* oversized output fails;
* no partial JSON text is returned;
* limit restoration occurs after the test;
* subsequent ordinary unpack succeeds.

---

### Focused OOM Tests

Use SQLite fault injection where supported.

Exercise OOM during:

1. initial `JsonString` growth;
2. later growth after multiple elements;
3. finalization or transfer where applicable.

Verify:

* an OOM error is returned;
* no malformed or partial JSON is returned;
* the `JsonString` buffer is released;
* subtype is not assigned to an error;
* a subsequent valid call succeeds.

Do not broaden this into the full fault matrix yet.

---

### Regression Tests

All Stage 2–6 tests must remain passing, including:

* SQL registration and arity;
* NULL propagation;
* storage-class validation;
* exact format parsing;
* embedded-NUL format rejection;
* endian helpers;
* binary classification helpers;
* full-domain signed-byte helper tests;
* checked-size tests;
* JSONB numeric extraction helper tests;
* complete `int8` packing tests;
* `int8` pack OOM and prepared-statement tests.

Verify floating pack and unpack formats still return placeholders.

---

### Test Module Changes

Extend:

```text
test/pblob.test
```

with public SQL tests for `int8` unpacking.

Use existing test-only infrastructure for focused OOM and limit tests.

Do not yet create the complete floating reference-vector suite.

Do not register any public SQL debug function.

---

### Build Verification

Perform all required build configurations.

#### Normal Build

Verify:

* `int8` unpacking compiles and links;
* exact unpack vectors pass;
* JSON subtype composition works;
* no new warnings appear;
* floating formats remain placeholders;
* no test-only commands appear.

#### Test Build

Build `testfixture` or the project’s equivalent with:

```text
SQLITE_TEST
```

Run:

* all Stage 7 unpack tests;
* round-trip tests;
* subtype tests;
* prepared-statement tests;
* focused limit tests;
* focused OOM tests;
* all prior-stage tests.

#### JSON-Disabled Build

Build with:

```text
SQLITE_OMIT_JSON
```

Verify:

* build and link succeed;
* no `pblob` SQL functions are registered;
* no `JsonString` or unpack references remain unresolved;
* no warnings are introduced.

---

### Prohibited Work

Do not implement:

* binary16 unpacking;
* binary32 unpacking;
* binary16 packing;
* binary32 packing;
* BLOB-length divisibility checks for widths 2 or 4;
* raw float bit decoding;
* FP16 conversion calls in production;
* binary32 bitcasts in production;
* floating-point formatting;
* non-finite BLOB rejection;
* signed-zero floating output;
* format inference;
* headers or metadata in the BLOB;
* JSONB return values;
* JSONB input acceptance for `pblob_pack()`;
* public C APIs;
* public headers.

Do not modify:

* `json.c`;
* vendored FP16;
* unrelated SQLite code.

Do not add new production SQL functions.

---

### Expected Deliverables

Provide:

1. Updated `pblob.c`.
2. Updated `test/pblob.test`.
3. Any narrowly scoped test-only changes required for OOM or limit testing.
4. Exact build commands executed.
5. Exact test commands executed.
6. Results for:

   * normal build;
   * test build;
   * JSON-disabled build.
7. A concise list of modified files.
8. Confirmation that:

   * only `pblob_unpack(..., 'int8')` became newly functional;
   * BLOB bytes are decoded with `pblobDecodeInt8()`;
   * output uses `JsonString`;
   * output is compact JSON TEXT;
   * output receives `JSON_SUBTYPE`;
   * zero-length BLOB returns `[]`;
   * every BLOB length is valid for `int8`;
   * pack/unpack byte round trips succeed;
   * floating formats remain placeholders;
   * no public API or header was added.

---

### Acceptance Criteria

Stage 7 is complete only when:

* `pblob_unpack(x'','int8')` returns `[]`;
* every byte `00..FF` decodes to the required signed integer;
* the full byte-domain test passes;
* output order matches input byte order;
* output JSON is compact and valid;
* output storage class is TEXT;
* output has `JSON_SUBTYPE`;
* direct composition with SQLite JSON functions treats the result as an array;
* arbitrary BLOB lengths are accepted;
* `pblob_pack(pblob_unpack(blob,'int8'),'int8')` reproduces every tested BLOB exactly;
* large outputs respect SQLite length limits;
* OOM paths release all output state;
* prepared-statement reuse is correct;
* all Stage 2–6 tests remain passing;
* `<f2`, `>f2`, `<f4`, and `>f4` remain placeholders;
* normal build succeeds;
* test build succeeds;
* JSON-disabled build succeeds;
* no new warnings appear;
* no public C API or header exists.

Stop after satisfying these criteria. Do not proceed to Stage 8.

---
---

## 📗 Stage 8: Binary32 Packing

Implement only Stage 8 of the packed numeric BLOB extension.

This stage begins from the completed Stage 7 state, where:

* `pblob.c` is compiled into the SQLite amalgamation after `json.c`;
* `pblob_pack()` and `pblob_unpack()` are auto-registered;
* NULL propagation, strict storage-class validation, and exact format parsing are implemented;
* endian helpers, binary16 and binary32 classification helpers, signed-byte decoding, and checked packed-size calculation are implemented;
* `pblobJsonbInteger()` and `pblobJsonbNumber()` are implemented and tested;
* `pblob_pack(json_array, 'int8')` is production-complete;
* `pblob_unpack(blob, 'int8')` is production-complete;
* `<f2`, `>f2`, `<f4`, and `>f4` remain placeholders;
* no production floating-point packing or unpacking exists.

Implement only binary32 packing for:

```sql
pblob_pack(json_array, '<f4')
pblob_pack(json_array, '>f4')
```

Do not implement binary32 unpacking or any binary16 behavior.

### Objective

Make these two SQL workflows production-complete:

```sql
pblob_pack(json_array, '<f4') -> little-endian IEEE binary32 BLOB
pblob_pack(json_array, '>f4') -> big-endian IEEE binary32 BLOB
```

The implementation must:

* accept SQL TEXT JSON arrays;
* accept JSON integer and floating numeric nodes;
* reuse `pblobJsonbNumber()` for extraction;
* convert through the required path:

  ```text
  JSON numeric value -> double -> float -> binary32 bits
  ```
* reject non-finite source values;
* reject finite source values that overflow binary32 to infinity;
* preserve positive and negative zero;
* permit normal underflow to subnormal or zero;
* emit exact IEEE binary32 bytes in the selected byte order;
* allocate the exact output size once;
* return a raw headerless BLOB;
* report the first invalid element using a zero-based index;
* preserve all existing `int8` behavior;
* leave binary32 unpacking and all binary16 paths as placeholders.

### Scope

This stage is limited to:

1. Extending `pblob_pack()` dispatch for `<f4` and `>f4`.
2. Reusing production JSON parsing and array traversal established in Stage 6.
3. Accepting all SQLite JSON numeric node types.
4. Extracting values with `pblobJsonbNumber()`.
5. Narrowing `double` to `float`.
6. Obtaining bits with `fp32_to_bits()`.
7. Rejecting non-finite source and target values.
8. Writing exact endian-specific bytes.
9. Adding binary32 packing tests.
10. Adding focused OOM, limit, and prepared-statement tests relevant to this workflow.
11. Preserving all previous-stage tests.

Do not implement any unpacking for floating formats.

---

### Public Behavior Introduced in This Stage

The following calls must now succeed:

```sql
SELECT hex(pblob_pack('[1.0,2.0]', '<f4'));
SELECT hex(pblob_pack('[1.0,2.0]', '>f4'));
```

Expected:

```text
0000803F00000040
3F80000040000000
```

The following remain placeholders:

```text
pblob_pack(..., '<f2')
pblob_pack(..., '>f2')
pblob_unpack(..., '<f2')
pblob_unpack(..., '>f2')
pblob_unpack(..., '<f4')
pblob_unpack(..., '>f4')
```

Existing `int8` packing and unpacking behavior must remain unchanged.

---

### `pblob_pack()` Dispatch

Update `pblobPackFunc()` so that, after common validation and format parsing:

```text
PBLOB_INT8 -> existing int8 packing path
PBLOB_F32  -> new binary32 packing path
PBLOB_F16  -> existing temporary not-implemented error
```

Do not dispatch based on raw format strings after `pblobParseFormat()` has succeeded.

Use:

```text
pFormat.eKind
pFormat.eOrder
pFormat.nByte
```

The binary32 branch must accept only:

```text
PBLOB_ORDER_LE
PBLOB_ORDER_BE
```

Treat `PBLOB_ORDER_NONE` for `PBLOB_F32` as an internal programmer error.

---

### Shared Pack Workflow

Where practical, reuse the existing production workflow for:

* JSON parsing;
* root array validation;
* element counting;
* checked output-size calculation;
* root payload location;
* sequential array traversal;
* exact single-shot allocation;
* cleanup;
* malformed internal JSON detection.

Do not duplicate the entire Stage 6 pack implementation merely to add binary32.

A reasonable structure is:

```c
static int pblobPackInt8(...);
static int pblobPackF32(...);
```

called from a shared callback after parsing and root validation.

Equivalent private organization is acceptable.

All helpers must remain `static`.

Do not create `pblob.h`.

---

### JSON Parsing and Root Validation

Use the established production path:

```c
jsonParseFuncArg(ctx, argv[0], 0)
```

Require the root node to be:

```c
JSONB_ARRAY
```

Use:

```c
jsonbArrayCount()
jsonbPayloadSize()
```

for element count and traversal.

Do not introduce a separate JSON parse path for floating formats.

Do not accept caller-supplied JSONB BLOB input.

---

### Output Size

For binary32:

```text
output bytes = element count * 4
```

Call the existing checked-size helper with:

```text
nByte = 4
```

The helper must enforce:

* multiplication overflow detection;
* the current SQLite length limit.

Do not duplicate size checking in the binary32 branch.

A zero-element array must return a zero-length BLOB.

---

### Accepted JSONB Element Types

For `<f4` and `>f4`, accept:

```c
JSONB_INT
JSONB_INT5
JSONB_FLOAT
JSONB_FLOAT5
```

Reject:

```text
JSONB_NULL
JSONB_TRUE
JSONB_FALSE
all JSON text node types
JSONB_ARRAY
JSONB_OBJECT
```

Examples that must be accepted:

```json
[0]
[1]
[-1]
[1.0]
[-1.0]
[0.5]
[1e10]
[0x7f]
[-0x80]
[1,2.5,0x10,-3]
```

Examples that must be rejected:

```json
[null]
[true]
[false]
["1"]
[[]]
[{}]
[1,null,2]
```

Recommended public error:

```text
pblob_pack: element N must be numeric for format <f4
```

or:

```text
pblob_pack: element N must be numeric for format >f4
```

The first invalid zero-based element index must be reported.

---

### Numeric Extraction

For every accepted numeric node, call:

```c
pblobJsonbNumber()
```

Do not:

* parse the payload again;
* route integer nodes through `pblobJsonbInteger()`;
* use SQL coercion;
* use `strtod()`;
* use `sscanf()`;
* duplicate SQLite JSON5 hexadecimal handling.

The helper returns a `double`.

The binary32 branch is responsible for target-format validation.

---

### Source Finiteness Check

Before narrowing to `float`, reject a non-finite `double`.

Use a robust finite check consistent with the selected source and project conventions.

Acceptable approaches include:

```c
sqlite3IsNaN(d)
```

combined with explicit infinity detection, or an equivalent internal helper.

Do not rely on:

```c
d == d
```

alone because that distinguishes NaN but not infinity.

Do not use locale-dependent or textual checks.

Recommended public error:

```text
pblob_pack: element N is not finite
```

This applies to values such as SQLite-supported JSON5 infinity forms if they arrive as non-finite numeric results.

NaN spellings that SQLite converts to JSON null must fail earlier as nonnumeric elements.

---

### Required Conversion Path

For each finite `double`:

```c
float f = (float)d;
uint32_t bits = fp32_to_bits(f);
```

This conversion path is normative.

Do not:

* directly convert decimal text to binary32;
* use `strtof()`;
* parse through a third-party library;
* manually construct binary32 bits;
* use union type-punning;
* pointer-cast between `float *` and `uint32_t *`.

The implementation must use the vendored bitcast helper:

```c
fp32_to_bits()
```

---

### Target Finiteness Check

After conversion to `float`, inspect:

```c
bits
```

using the existing:

```c
pblobF32IsFinite()
```

If the resulting binary32 value is not finite, reject it.

This catches finite `double` values that overflow to binary32 infinity.

Recommended public error:

```text
pblob_pack: element N is outside the finite float32 range
```

Do not return infinity bytes.

Do not clamp to:

```text
0x7f7fffff
0xff7fffff
```

Do not saturate.

---

### Underflow Behavior

Finite values that narrow to:

* a binary32 subnormal;
* positive zero;
* negative zero;

must be accepted.

Do not reject underflow merely because information is lost.

Examples:

```text
very small positive finite value -> positive subnormal or +0
very small negative finite value -> negative subnormal or -0
```

The resulting bytes must match the host’s IEEE binary32 conversion under the compile-time platform assumptions already enforced in Stage 1.

---

### Signed Zero

Signed zero must be preserved.

Required examples:

```text
+0.0 -> 0x00000000
-0.0 -> 0x80000000
```

Little-endian:

```text
+0.0 -> 00000000
-0.0 -> 00000080
```

Big-endian:

```text
+0.0 -> 00000000
-0.0 -> 80000000
```

Test negative-zero forms supported by SQLite, including where applicable:

```text
-0
-0.0
-0e0
```

Record actual source behavior for integer lexical `-0` if SQLite normalizes it before `pblobJsonbNumber()`.

Do not manually force a sign bit unless the extracted `double` retains negative zero.

---

### Endian Encoding

For each validated binary32 word:

```text
<f4 -> pblobPutU32Le()
>f4 -> pblobPutU32Be()
```

Do not:

* use host byte order;
* use `memcpy()` as an endian policy;
* pointer-cast the output;
* call platform byte-swap APIs.

Required examples:

```text
1.0 bits = 3F800000

<f4 -> 00 00 80 3F
>f4 -> 3F 80 00 00
```

---

### Array Traversal

Use the same defensive traversal requirements as Stage 6.

For each element:

1. Verify current offset is inside the array payload.
2. Decode header and payload size with `jsonbPayloadSize()`.
3. Verify the node fits entirely within the root payload.
4. Validate node type.
5. Extract the numeric value.
6. Check source finiteness.
7. Narrow to binary32.
8. check target finiteness.
9. write four bytes.
10. advance to the next node.

After processing all counted elements, require:

```text
iNode == iEnd
processed count == jsonbArrayCount() result
```

Any disagreement must report:

```text
pblob_pack: malformed internal JSON representation
```

Do not recurse into nested containers.

---

### Result Ownership

Use the same single-allocation ownership strategy as Stage 6.

For nonempty output:

```c
sqlite3_result_blob64(ctx, pOut, nOut, sqlite3_free);
```

On failure before transfer:

```c
sqlite3_free(pOut);
```

Always release:

```c
jsonParseFree(pParse);
```

Do not leak the buffer when one element fails after earlier elements were already written.

Do not return a partial BLOB.

---

### Error Precedence

Preserve this order:

```text
NULL propagation
-> first argument storage class
-> format storage class
-> exact format value
-> placeholder for f2
-> JSON parsing
-> root array validation
-> checked output size
-> element type validation
-> numeric extraction
-> source finiteness
-> binary32 range validation
-> packing
```

Examples:

```sql
SELECT pblob_pack('bad JSON', 'bad');
```

Expected: unsupported-format error.

```sql
SELECT pblob_pack('bad JSON', '<f4');
```

Expected: malformed JSON.

```sql
SELECT pblob_pack('{}', '<f4');
```

Expected: expected-array error.

```sql
SELECT pblob_pack('[null]', '<f4');
```

Expected: element-type error.

```sql
SELECT pblob_pack('[1e999]', '<f4');
```

Expected: non-finite or float32-range error according to the actual extracted `double`.

```sql
SELECT pblob_pack('[3.5e38]', '<f4');
```

Expected: finite float32 range error if narrowing produces infinity.

---

### Primary Exact Binary32 Vectors

Add exact-byte tests for both byte orders.

#### Zero and Signed Zero

```text
values:
  +0.0
  -0.0
```

Expected bits:

```text
00000000
80000000
```

Expected `<f4`:

```text
0000000000000080
```

Expected `>f4`:

```text
0000000080000000
```

#### Basic Values

Values:

```text
1.0
-1.0
2.0
0.5
```

Expected bits:

```text
3F800000
BF800000
40000000
3F000000
```

Expected `<f4`:

```text
0000803F000080BF000000400000003F
```

Expected `>f4`:

```text
3F800000BF800000400000003F000000
```

#### Integer Input

Test:

```sql
SELECT hex(pblob_pack('[1,-1,2,127,-128]', '<f4'));
```

Expected bits must be independently calculated and committed.

This verifies that integer JSON nodes are accepted and routed through the general numeric helper.

---

### Canonical IEEE Binary32 Vectors

Include at least:

| Value                       | Bits       |
| --------------------------- | ---------- |
| `+0`                        | `00000000` |
| `-0`                        | `80000000` |
| `1`                         | `3F800000` |
| `-1`                        | `BF800000` |
| `0.5`                       | `3F000000` |
| `2`                         | `40000000` |
| smallest positive subnormal | `00000001` |
| largest positive subnormal  | `007FFFFF` |
| smallest positive normal    | `00800000` |
| largest finite positive     | `7F7FFFFF` |
| largest finite negative     | `FF7FFFFF` |

Test both little-endian and big-endian byte output.

Where exact decimal JSON text for a boundary is cumbersome, use independently generated decimal strings committed by the reference-vector generator.

Do not derive expected bytes by calling `pblob_pack()` itself.

---

### Rounding Tests

Add representative values around binary32 rounding boundaries.

Include:

* exact binary32 values;
* values halfway between adjacent binary32 values;
* values just below and above halfway;
* values around `1.0`;
* values around powers of two;
* values around the normal/subnormal boundary;
* positive and negative variants.

Expected results must be generated independently.

The normative behavior is:

```text
SQLite decimal -> double -> C float conversion
```

Do not compare against direct decimal-to-binary32 rounding unless the test value is known not to expose double-rounding differences.

The reference generator must model the specified two-step path.

---

### Underflow Tests

Test finite values that become:

* a nonzero binary32 subnormal;
* positive zero;
* negative zero.

Verify exact bits.

At minimum include:

```text
smallest positive subnormal
half the smallest positive subnormal
negative half the smallest positive subnormal
```

Expected zero sign must match the source conversion behavior.

Do not reject these values.

---

### Overflow Tests

Reject finite values that narrow to infinity.

Test positive and negative values:

```text
just above maximum finite binary32
well above maximum finite binary32
```

Examples may include decimal strings around:

```text
3.4028235e38
```

Expected: float32 range error.

Do not encode:

```text
7F800000
FF800000
```

for packed output.

---

### JSON5 Numeric Tests

Test supported JSON5 numeric forms:

```text
[+1]
[.5]
[1.]
[0x7f]
[-0x80]
[1,]
[/*comment*/1.5]
```

Expected bytes must match equivalent canonical numeric values.

Do not independently broaden JSON5 syntax.

Test infinity and NaN spellings according to the selected `json.c` behavior:

```text
Infinity
-Infinity
NaN
QNaN
SNaN
```

Expected:

* infinity forms are rejected as non-finite or out of range;
* NaN forms that become JSON null are rejected as nonnumeric elements.

---

### Wrong-Type Tests

Reject:

```json
[null]
[true]
[false]
["1"]
[[]]
[{}]
```

Test mixed arrays:

```json
[1,2.5,null,3]
[1,"2",3]
[1,[2],3]
```

Verify the first invalid zero-based element index.

---

### Empty Array

For both formats:

```sql
SELECT typeof(pblob_pack('[]','<f4'));
SELECT length(pblob_pack('[]','<f4'));
SELECT hex(pblob_pack('[]','<f4'));

SELECT typeof(pblob_pack('[]','>f4'));
SELECT length(pblob_pack('[]','>f4'));
SELECT hex(pblob_pack('[]','>f4'));
```

Expected:

```text
blob
0
''
```

---

### Large Array Tests

Test element counts:

```text
0
1
2
128
256
768
1024
1536
4096
```

For each successful case verify:

```text
length(result) == element count * 4
typeof(result) == blob
```

Use deterministic numeric patterns that remain finite in binary32.

For representative large arrays verify:

* first word;
* middle word;
* last word;
* repeated calls produce identical BLOBs.

---

### SQLite Length-Limit Tests

Temporarily reduce:

```text
SQLITE_LIMIT_LENGTH
```

Test binary32 output:

```text
nElem * 4 == limit
nElem * 4 > limit
```

Expected:

```text
at limit -> success
over limit -> result-too-large error
```

Restore the previous limit.

This must exercise `pblobCheckedSize()`.

---

### Prepared-Statement Reuse

Prepare:

```sql
SELECT pblob_pack(?1, '<f4');
```

Execute repeatedly with:

```text
[]
[0]
[1.0,-1.0]
large valid array
[null]
[2.0]
```

Verify:

* no stale output;
* errors do not corrupt later successful executions;
* a prior large output does not affect a later small output.

Also prepare:

```sql
SELECT pblob_pack(?1, ?2);
```

and alternate:

```text
int8
<f4
>f4
<f2
bad
<f4
```

Verify dispatch remains correct.

---

### Focused OOM Tests

Use SQLite fault injection where supported.

Exercise OOM during:

1. JSON parsing.
2. temporary numeric payload duplication in `pblobJsonbNumber()`.
3. output BLOB allocation.
4. processing after some elements have already been packed.

Verify:

* no partial BLOB result;
* output allocation is freed;
* `JsonParse` is released;
* a subsequent valid call succeeds.

Do not broaden this into the final complete fault matrix.

---

### Independent Reference Vectors

Extend or introduce the independent vector generator for binary32 pack cases.

The generator must model:

```text
decimal numeric input
-> IEEE binary64
-> IEEE binary32
-> selected byte order
```

It must not:

* call SQLite;
* call `pblob_pack()`;
* reuse bytes emitted by the implementation under test.

Acceptable generator implementations may use:

* Python `struct`;
* carefully controlled NumPy conversion;
* a small independent C program.

Record:

```text
generator version
runtime version
endianness handling
rounding assumptions
```

Commit generated vectors as static test data.

Normal test execution must not require the generator.

---

### Regression Tests

All Stage 2–7 tests must remain passing, including:

* registration and arity;
* NULL propagation;
* strict argument types;
* exact format parsing;
* embedded-NUL format rejection;
* low-level endian and classification tests;
* signed-byte tests;
* checked-size tests;
* numeric extraction tests;
* complete `int8` pack and unpack tests;
* subtype tests;
* prepared-statement reuse;
* focused prior OOM and limit tests.

Verify:

```text
<f2 and >f2 packing remain placeholders
all floating unpacking remains placeholders
```

---

### Test Module Changes

Extend:

```text
test/pblob.test
```

with public binary32 packing tests.

Extend the independent vector data or generator as needed.

Use existing test-only infrastructure for focused OOM and limit testing.

Do not implement binary32 unpack reference tests yet.

Do not register any public debug SQL function.

---

### Build Verification

Perform all required configurations.

#### Normal Build

Verify:

* `<f4` and `>f4` packing compile and link;
* exact endian vectors pass;
* `int8` behavior remains unchanged;
* no new warnings appear;
* no test-only interface is present.

#### Test Build

Build `testfixture` or the project equivalent with:

```text
SQLITE_TEST
```

Run:

* exact binary32 vectors;
* rounding tests;
* underflow tests;
* overflow tests;
* signed-zero tests;
* JSON5 numeric tests;
* wrong-type tests;
* large-array tests;
* limit tests;
* prepared-statement tests;
* focused OOM tests;
* all previous-stage tests.

#### JSON-Disabled Build

Build with:

```text
SQLITE_OMIT_JSON
```

Verify:

* build and link succeed;
* no `pblob` SQL functions are registered;
* no JSONB, FP32, or binary32 pack references remain unresolved;
* no warnings are introduced.

---

### Prohibited Work

Do not implement:

* binary32 unpacking;
* binary16 packing;
* binary16 unpacking;
* BLOB length validation for floating unpacking;
* `JsonString` floating output;
* raw binary32 decoding;
* `fp32_from_bits()` in production;
* FP16 conversion calls in production;
* direct decimal-to-binary32 parsing;
* infinity or NaN output;
* saturation to maximum finite;
* format inference;
* BLOB headers or metadata;
* JSONB input acceptance for `pblob_pack()`;
* public C APIs;
* public headers.

Do not modify:

* `json.c`;
* vendored FP16;
* unrelated SQLite code.

Do not add new production SQL functions.

---

### Expected Deliverables

Provide:

1. Updated `pblob.c`.
2. Updated `test/pblob.test`.
3. Updated independent binary32 reference vectors or generator.
4. Any narrowly scoped test-only changes needed for OOM or limit testing.
5. Exact build commands executed.
6. Exact test commands executed.
7. Results for:

   * normal build;
   * test build;
   * JSON-disabled build.
8. A concise list of modified files.
9. Confirmation that:

   * only `<f4` and `>f4` packing became newly functional;
   * JSON numeric extraction uses `pblobJsonbNumber()`;
   * conversion follows `double -> float -> bits`;
   * `fp32_to_bits()` is used;
   * non-finite source and target values are rejected;
   * underflow is accepted;
   * signed zero is preserved;
   * endian output uses explicit byte helpers;
   * allocation is exact and single-shot;
   * binary32 unpacking and all binary16 paths remain placeholders;
   * no public API or header was added.

---

### Acceptance Criteria

Stage 8 is complete only when:

* `pblob_pack(...,'<f4')` emits exact little-endian IEEE binary32 bytes;
* `pblob_pack(...,'>f4')` emits exact big-endian IEEE binary32 bytes;
* integer and floating JSON numeric nodes are accepted;
* nonnumeric elements are rejected with the first zero-based index;
* extraction uses `pblobJsonbNumber()`;
* conversion follows the required `double -> float -> binary32 bits` path;
* signed zero is preserved;
* finite subnormal and zero underflow results are accepted;
* finite values that overflow binary32 are rejected;
* non-finite source values are rejected;
* no infinity or NaN bytes are emitted;
* exact independent vectors pass;
* output size is exactly `element count * 4`;
* SQLite length limits are enforced;
* OOM paths release all owned state;
* prepared-statement reuse is correct;
* all Stage 2–7 tests remain passing;
* binary32 unpacking remains a placeholder;
* binary16 packing and unpacking remain placeholders;
* normal build succeeds;
* test build succeeds;
* JSON-disabled build succeeds;
* no new warnings appear;
* no public C API or header exists.

Stop after satisfying these criteria. Do not proceed to Stage 9.

---
---

## 📗 Stage 9: Binary32 Unpacking

Implement only Stage 9 of the packed numeric BLOB extension.

This stage begins from the completed Stage 8 state, where:

* `pblob.c` is compiled into the SQLite amalgamation after `json.c`;
* `pblob_pack()` and `pblob_unpack()` are auto-registered;
* NULL propagation, strict storage-class validation, and exact format parsing are implemented;
* endian helpers, binary16 and binary32 classification helpers, signed-byte decoding, and checked packed-size calculation are implemented;
* `pblobJsonbInteger()` and `pblobJsonbNumber()` are implemented and tested;
* `pblob_pack(..., 'int8')` and `pblob_unpack(..., 'int8')` are production-complete;
* `pblob_pack(..., '<f4')` and `pblob_pack(..., '>f4')` are production-complete;
* binary32 unpacking remains a placeholder;
* all binary16 paths remain placeholders.

Implement only binary32 unpacking for:

```sql
pblob_unpack(blob, '<f4')
pblob_unpack(blob, '>f4')
```

Do not implement any binary16 behavior.

### Objective

Make these two SQL workflows production-complete:

```sql
pblob_unpack(blob, '<f4') -> JSON text
pblob_unpack(blob, '>f4') -> JSON text
```

The implementation must:

* accept only SQL BLOB input;
* require the BLOB length to be divisible by four;
* read every element using explicit endian helpers;
* reject IEEE binary32 infinity and NaN bit patterns;
* convert finite binary32 values through:

  ```text
  bits -> float -> double
  ```
* preserve positive and negative zero;
* preserve finite binary32 values exactly when promoted to `double`;
* emit compact valid JSON text;
* assign SQLite’s JSON subtype;
* use SQLite’s internal `JsonString` facilities;
* report the first invalid element using a zero-based index;
* leave all binary16 paths as placeholders;
* preserve all existing packing and `int8` behavior.

### Scope

This stage is limited to:

1. Extending `pblob_unpack()` dispatch for `<f4` and `>f4`.
2. Validating binary32 BLOB length.
3. Reading binary32 words with explicit endian helpers.
4. Rejecting non-finite bit patterns.
5. Converting with `fp32_from_bits()`.
6. Promoting the resulting `float` to `double`.
7. Formatting values as compact JSON numbers.
8. Preserving signed zero.
9. Returning JSON-subtyped TEXT.
10. Adding binary32 unpacking and round-trip tests.
11. Adding focused limit, OOM, and prepared-statement tests.
12. Preserving all previous-stage tests.

Do not implement binary16 packing or unpacking.

---

### Public Behavior Introduced in This Stage

The following calls must now succeed:

```sql
SELECT pblob_unpack(x'0000803F00000040', '<f4');
SELECT pblob_unpack(x'3F80000040000000', '>f4');
```

Expected:

```text
[1.0,2.0]
[1.0,2.0]
```

Exact output spelling must follow SQLite’s established JSON numeric formatter.

The following remain placeholders:

```text
pblob_pack(..., '<f2')
pblob_pack(..., '>f2')
pblob_unpack(..., '<f2')
pblob_unpack(..., '>f2')
```

Existing `int8` and binary32 packing behavior must remain unchanged.

---

### `pblob_unpack()` Dispatch

Update `pblobUnpackFunc()` so that, after common validation and format parsing:

```text
PBLOB_INT8 -> existing int8 unpacking path
PBLOB_F32  -> new binary32 unpacking path
PBLOB_F16  -> existing temporary not-implemented error
```

Do not dispatch by comparing raw format strings after `pblobParseFormat()` succeeds.

Use:

```text
pFormat.eKind
pFormat.eOrder
pFormat.nByte
```

For `PBLOB_F32`, require:

```text
pFormat.nByte == 4
pFormat.eOrder == PBLOB_ORDER_LE or PBLOB_ORDER_BE
```

Treat any other internal combination as a defensive internal error.

---

### Shared Unpack Workflow

Where practical, reuse the Stage 7 infrastructure for:

* BLOB retrieval;
* `JsonString` initialization;
* opening and closing JSON array brackets;
* compact comma handling;
* result finalization;
* subtype assignment;
* cleanup.

Do not duplicate the entire `pblobUnpackFunc()` implementation for binary32.

A reasonable structure is:

```c
static int pblobUnpackInt8(...);
static int pblobUnpackF32(...);
```

or equivalent private helpers called by the shared SQL callback.

All production helpers must remain `static`.

Do not create `pblob.h`.

---

### BLOB Retrieval

After common validation and format dispatch, retrieve:

```c
const u8 *pBlob = sqlite3_value_blob(argv[0]);
int nBlob = sqlite3_value_bytes(argv[0]);
```

or the exact internal types appropriate to the selected source.

Required behavior:

* zero-length BLOB is valid;
* a NULL pointer with zero length is valid;
* the input is read without copying;
* the BLOB is treated as raw binary32 data;
* no JSONB interpretation occurs.

Do not call:

```c
sqlite3_value_text()
```

on the BLOB.

---

### BLOB Length Validation

For binary32:

```text
element width = 4 bytes
```

Require:

```text
nBlob % 4 == 0
```

If not divisible by four, report a stable function-specific error.

Recommended messages:

```text
pblob_unpack: BLOB length is not divisible by 4 for format <f4
pblob_unpack: BLOB length is not divisible by 4 for format >f4
```

A shorter stable error is acceptable if it clearly identifies the invalid width.

Length validation must occur:

* after NULL, type, and format validation;
* before `JsonString` initialization where practical;
* before any element is read.

Do not partially decode a malformed-length BLOB.

---

### Element Count

For binary32:

```text
element count = nBlob / 4
```

Use a type that safely represents the result.

No multiplication is needed.

Do not call `pblobCheckedSize()` for this calculation.

---

### Endian Decoding

For each element:

```text
<f4 -> pblobGetU32Le()
>f4 -> pblobGetU32Be()
```

Do not:

* use host byte order;
* use pointer casts;
* use unaligned `uint32_t` loads;
* use `memcpy()` as the endian policy;
* use platform byte-swap APIs.

Required example:

```text
bytes 00 00 80 3F under <f4 -> bits 3F800000
bytes 3F 80 00 00 under >f4 -> bits 3F800000
```

Element offsets are:

```text
0
4
8
...
```

---

### Binary32 Classification

Before converting the raw bits, classify using:

```c
pblobF32IsFinite()
pblobF32IsInf()
pblobF32IsNaN()
```

Reject every non-finite bit pattern.

Required rejected classes:

```text
positive infinity
negative infinity
quiet NaN
signaling NaN
positive NaN payloads
negative NaN payloads
```

Recommended errors:

```text
pblob_unpack: element N is infinity
pblob_unpack: element N is NaN
```

or one stable combined message:

```text
pblob_unpack: element N is not a finite float32 value
```

The first invalid zero-based element index must be reported.

Do not call `fp32_from_bits()` before rejecting non-finite patterns unless the implementation can prove no floating-point exception or normalization issue can occur. Raw-bit classification first is preferred.

Do not convert non-finite values to JSON null.

Do not emit `Infinity`, `NaN`, or implementation-specific text.

---

### Required Conversion Path

For each finite raw bit pattern:

```c
float f = fp32_from_bits(bits);
double d = (double)f;
```

This path is normative.

Do not:

* reinterpret through pointer casts;
* use union type-punning;
* manually decode exponent and mantissa into `double`;
* use decimal conversion libraries;
* route through text;
* call `strtod()` or `strtof()`.

Use the vendored:

```c
fp32_from_bits()
```

helper.

Promotion from IEEE binary32 to binary64 is exact under the compile-time assumptions already established.

---

### JSON Numeric Formatting

Append each promoted `double` using SQLite’s JSON-aware formatter.

Use the exact project convention established by `json.c`, expected to be equivalent to:

```c
jsonPrintf(100, &out, "%!0.17g", d);
```

Use the selected source’s actual argument order and formatting convention.

Requirements:

* output must be valid JSON numeric syntax;
* output must be compact;
* every finite binary32 value must serialize without losing its value;
* reparsing the JSON number and packing it back to binary32 must reproduce the original bits;
* signed zero must remain distinguishable.

Do not use:

```c
printf()
sprintf()
snprintf()
sqlite3_mprintf()
strfromf()
```

Do not format through the process locale.

Do not emit hexadecimal floating-point syntax.

---

### Integer-Looking Floating Values

Binary32 values are floating-point elements even when mathematically integral.

The JSON formatter may produce output such as:

```text
1.0
2.0
-1.0
```

or another SQLite-established real-number spelling.

Do not force integer syntax manually.

This distinction is important because:

```sql
pblob_pack(pblob_unpack(blob, '<f4'), '<f4')
```

must route the resulting values through numeric extraction and reproduce the same binary32 values.

Use the actual `json.c` formatting behavior as the normative output.

---

### Signed Zero

Signed zero must be preserved.

Required input bit patterns:

```text
00000000 -> positive zero
80000000 -> negative zero
```

Expected semantic output:

```text
+0.0
-0.0
```

or the exact equivalent emitted by SQLite’s JSON formatter.

Required direct tests:

```sql
SELECT pblob_unpack(x'00000000', '>f4');
SELECT pblob_unpack(x'80000000', '>f4');
```

and:

```sql
SELECT pblob_unpack(x'00000000', '<f4');
SELECT pblob_unpack(x'00000080', '<f4');
```

Verify signed zero by repacking and checking exact bits:

```sql
SELECT hex(
  pblob_pack(
    pblob_unpack(x'80000000', '>f4'),
    '>f4'
  )
);
```

Expected:

```text
80000000
```

Do not rely only on displayed text.

---

### Finite Subnormal Values

All finite binary32 subnormal bit patterns are valid.

Examples:

```text
00000001
00000002
007FFFFF
80000001
807FFFFF
```

The implementation must:

* decode them;
* emit valid JSON numbers;
* preserve sign;
* reproduce the original binary32 bits when repacked.

Do not flush subnormal values to zero manually.

Do not reject them.

---

### Maximum Finite Values

Accept:

```text
7F7FFFFF
FF7FFFFF
```

These represent maximum positive and negative finite binary32 values.

The resulting JSON text may contain a long decimal or exponent form.

The only required semantic guarantee is:

```text
unpack -> pack reproduces the original bits
```

Do not compare against a hand-written shortened decimal unless independently verified.

---

### JSON Output Construction

Use the Stage 7 `JsonString` infrastructure:

```c
JsonString out;
jsonStringInit(&out, ctx);
jsonAppendChar(&out, '[');
...
jsonAppendChar(&out, ']');
jsonReturnString(...);
```

Append commas between elements without spaces.

Do not build output through manual heap concatenation.

For a zero-length BLOB, return:

```text
[]
```

with storage class TEXT and JSON subtype.

---

### Result Subtype

After successful finalization, assign:

```c
sqlite3_result_subtype(ctx, JSON_SUBTYPE);
```

The function registration must retain:

```c
SQLITE_RESULT_SUBTYPE
```

Test composition:

```sql
SELECT json_array(
  pblob_unpack(x'3F80000040000000', '>f4')
);
```

Expected semantic result:

```json
[[1.0,2.0]]
```

The result must not be quoted as a JSON string.

Also test:

```sql
SELECT json_type(pblob_unpack(x'3F800000', '>f4'));
SELECT json_array_length(pblob_unpack(x'3F80000040000000', '>f4'));
```

Expected:

```text
array
2
```

---

### Error Precedence

Preserve this order:

```text
NULL propagation
-> first argument storage class
-> format storage class
-> exact format value
-> placeholder for f2
-> binary32 BLOB length validation
-> per-element binary32 classification
-> conversion
-> JSON output construction
```

Examples:

```sql
SELECT pblob_unpack(NULL, 'bad');
```

Expected: SQL NULL.

```sql
SELECT pblob_unpack('00000000', '>f4');
```

Expected: first-argument BLOB error.

```sql
SELECT pblob_unpack(x'00000000', 1);
```

Expected: format-must-be-text error.

```sql
SELECT pblob_unpack(x'00000000', 'bad');
```

Expected: unsupported-format error.

```sql
SELECT pblob_unpack(x'00', '<f2');
```

Expected: binary16 placeholder, not a binary32 length error.

```sql
SELECT pblob_unpack(x'00', '<f4');
```

Expected: invalid-length error.

```sql
SELECT pblob_unpack(x'7F800000', '>f4');
```

Expected: non-finite element error at index 0.

---

### Primary Exact Binary32 Unpack Tests

Add tests for both byte orders.

#### Empty BLOB

```sql
SELECT pblob_unpack(x'', '<f4');
SELECT pblob_unpack(x'', '>f4');
```

Expected:

```text
[]
[]
```

#### Basic Values

Big-endian input:

```text
3F800000
BF800000
40000000
3F000000
```

Expected semantic values:

```text
1.0
-1.0
2.0
0.5
```

Little-endian input:

```text
0000803F
000080BF
00000040
0000003F
```

Expected the same values.

Where exact JSON spelling is stable in the selected source, assert exact text. Otherwise assert:

* `json_valid()`;
* array length;
* individual numerical equality;
* repacked byte identity.

---

### Canonical Finite Bit Vectors

Test at least:

| Bits       | Meaning                     |
| ---------- | --------------------------- |
| `00000000` | positive zero               |
| `80000000` | negative zero               |
| `00000001` | smallest positive subnormal |
| `80000001` | smallest negative subnormal |
| `007FFFFF` | largest positive subnormal  |
| `807FFFFF` | largest negative subnormal  |
| `00800000` | smallest positive normal    |
| `80800000` | smallest negative normal    |
| `3F000000` | `0.5`                       |
| `3F800000` | `1.0`                       |
| `BF800000` | `-1.0`                      |
| `40000000` | `2.0`                       |
| `7F7FFFFF` | largest positive finite     |
| `FF7FFFFF` | largest negative finite     |

Test both endian encodings.

For each finite vector verify:

```text
unpack succeeds
json_valid(result) == 1
array length is correct
repack reproduces the original bits
```

---

### Non-Finite Rejection Tests

Reject infinity:

```text
7F800000
FF800000
```

Reject representative NaNs:

```text
7F800001
7FC00000
7FFFFFFF
FF800001
FFC00000
FFFFFFFF
```

Test both endian forms.

Test invalid values at nonzero positions:

```text
[finite, infinity, finite]
[finite, NaN, finite]
```

Verify the first invalid zero-based element index.

No partial JSON result may be returned.

---

### Invalid Length Tests

Reject BLOB lengths:

```text
1
2
3
5
6
7
9
```

Test both `<f4` and `>f4`.

Accept:

```text
0
4
8
12
16
```

For rejected lengths:

* no element decoding occurs;
* no partial result is produced;
* the error identifies the required four-byte width.

---

### Pack/Unpack Bit-Identity Tests

For committed valid binary32 BLOB vectors, test:

```sql
SELECT hex(
  pblob_pack(
    pblob_unpack(?1, '<f4'),
    '<f4'
  )
);
```

Expected: original little-endian BLOB.

Also test big-endian.

Include:

* zeros;
* signed zeros;
* subnormals;
* normals;
* maximum finite values;
* mixed arrays;
* independently generated random finite words.

This bit-identity test is mandatory.

---

### Cross-Endian Tests

For a finite value array:

1. Unpack little-endian.
2. Pack the resulting JSON as big-endian.
3. Compare with the expected byte-swapped words.

Example:

```sql
SELECT hex(
  pblob_pack(
    pblob_unpack(x'0000803F00000040', '<f4'),
    '>f4'
  )
);
```

Expected:

```text
3F80000040000000
```

Also test the reverse direction.

---

### Independent Reference Vectors

Extend the committed binary32 reference vectors to include unpacking cases.

The source vectors must be generated independently of `pblob.c`.

At minimum include:

* canonical finite values;
* subnormals;
* maximum finite values;
* signed zero;
* multiple-element arrays;
* invalid infinity and NaN words;
* both endian forms.

Normal test execution must use committed static vectors and must not require Python or NumPy.

---

### Large BLOB Tests

Test element counts:

```text
0
1
2
128
256
768
1024
1536
4096
```

Input length is:

```text
element count * 4
```

Use deterministic finite bit patterns.

For each successful case verify:

```text
json_valid(result) == 1
json_array_length(result) == element count
typeof(result) == text
repacking reproduces the original BLOB
```

For representative cases inspect:

* first value;
* middle value;
* last value.

---

### SQLite Length-Limit Tests

JSON output can be much larger than the input BLOB.

Temporarily reduce:

```text
SQLITE_LIMIT_LENGTH
```

Test a result that:

* fits below the limit;
* reaches a practical boundary;
* exceeds the limit.

Expected oversized behavior:

* SQLite string-too-large error;
* no partial JSON result;
* no subtype assigned to an error;
* subsequent normal calls succeed.

Restore the original limit after every test.

Do not estimate the output limit solely from `nBlob * constant`; use actual resulting JSON length or controlled vectors.

---

### Prepared-Statement Reuse

Prepare:

```sql
SELECT pblob_unpack(?1, '<f4');
```

Execute repeatedly with:

```text
empty BLOB
one finite value
multiple finite values
invalid-length BLOB
infinity BLOB
NaN BLOB
large finite BLOB
one finite value
```

Verify:

* errors do not corrupt later successful results;
* no stale `JsonString` data remains;
* a large prior result does not affect a later small result;
* subtype is correct after recovery from an error.

Also prepare:

```sql
SELECT pblob_unpack(?1, ?2);
```

and alternate formats:

```text
int8
<f4
>f4
<f2
bad
>f4
```

Verify dispatch and recovery.

---

### Focused OOM Tests

Use SQLite fault injection where supported.

Exercise OOM during:

1. initial `JsonString` growth;
2. later growth after several binary32 elements;
3. formatting of a long decimal representation;
4. final result transfer where applicable.

Verify:

* no partial JSON text is returned;
* `JsonString` storage is released;
* subtype is not assigned after failure;
* a subsequent valid invocation succeeds.

Do not broaden this into the final full fault matrix.

---

### Existing Regression Tests

All Stage 2–8 tests must remain passing, including:

* registration and arity;
* NULL propagation;
* strict argument types;
* exact format parsing;
* embedded-NUL rejection;
* endian and classification tests;
* checked-size tests;
* numeric extraction tests;
* full `int8` pack/unpack coverage;
* binary32 packing exact vectors;
* packing overflow, underflow, and signed-zero tests;
* existing OOM, limit, and prepared-statement tests.

Verify all binary16 paths remain placeholders.

---

### Test Module Changes

Extend:

```text
test/pblob.test
```

with public binary32 unpacking tests.

Extend the committed reference-vector data as required.

Use existing test-only infrastructure for focused OOM and limit tests.

Do not add a public debug SQL function.

Do not implement exhaustive binary16 tests in this stage.

---

### Build Verification

Perform all required configurations.

#### Normal Build

Verify:

* `<f4` and `>f4` unpacking compile and link;
* exact and semantic tests pass;
* JSON subtype composition works;
* binary32 pack/unpack identity holds;
* all prior functionality remains unchanged;
* no new warnings appear;
* no test-only interface is present.

#### Test Build

Build `testfixture` or the project equivalent with:

```text
SQLITE_TEST
```

Run:

* exact binary32 unpack vectors;
* finite canonical bit-pattern tests;
* signed-zero tests;
* subnormal tests;
* non-finite rejection tests;
* invalid-length tests;
* pack/unpack identity tests;
* cross-endian tests;
* large-BLOB tests;
* subtype tests;
* limit tests;
* prepared-statement tests;
* focused OOM tests;
* all previous-stage tests.

#### JSON-Disabled Build

Build with:

```text
SQLITE_OMIT_JSON
```

Verify:

* build and link succeed;
* no `pblob` SQL functions are registered;
* no `JsonString`, FP32, or binary32 unpack references remain unresolved;
* no warnings are introduced.

---

### Prohibited Work

Do not implement:

* binary16 packing;
* binary16 unpacking;
* FP16 conversion calls in production;
* binary16 length validation;
* binary16 exact vectors;
* direct bit-level binary32-to-decimal implementation;
* custom decimal formatting;
* non-finite JSON output;
* replacement of infinity or NaN with null;
* format inference;
* BLOB headers or metadata;
* JSONB output;
* public C APIs;
* public headers.

Do not modify:

* `json.c`;
* the vendored FP16 implementation;
* unrelated SQLite code.

Do not add new production SQL functions.

---

### Expected Deliverables

Provide:

1. Updated `pblob.c`.
2. Updated `test/pblob.test`.
3. Updated independent binary32 unpack reference vectors.
4. Any narrowly scoped test-only changes needed for OOM or limit tests.
5. Exact build commands executed.
6. Exact test commands executed.
7. Results for:

   * normal build;
   * test build;
   * JSON-disabled build.
8. A concise list of modified files.
9. Confirmation that:

   * only `<f4` and `>f4` unpacking became newly functional;
   * BLOB length is required to be divisible by four;
   * endian reads use `pblobGetU32Le()` and `pblobGetU32Be()`;
   * non-finite bit patterns are rejected before conversion;
   * conversion uses `fp32_from_bits()` followed by exact promotion to `double`;
   * JSON output uses `JsonString`;
   * signed zero is preserved;
   * output receives `JSON_SUBTYPE`;
   * binary32 pack/unpack reproduces finite input bits;
   * all binary16 paths remain placeholders;
   * no public API or header was added.

---

### Acceptance Criteria

Stage 9 is complete only when:

* `pblob_unpack(...,'<f4')` correctly reads little-endian binary32 values;
* `pblob_unpack(...,'>f4')` correctly reads big-endian binary32 values;
* zero-length BLOBs return `[]`;
* BLOB lengths not divisible by four are rejected;
* every finite tested binary32 bit pattern is accepted;
* positive and negative zero are preserved;
* positive and negative subnormals are preserved;
* maximum finite values are accepted;
* every infinity and NaN test pattern is rejected;
* the first invalid zero-based element index is reported;
* conversion uses `fp32_from_bits()` and exact `float`-to-`double` promotion;
* output is compact valid JSON TEXT with `JSON_SUBTYPE`;
* `pack(unpack(blob))` reproduces every tested finite BLOB exactly;
* cross-endian conversion produces expected byte-swapped words;
* large outputs respect SQLite length limits;
* OOM paths release all output state;
* prepared-statement reuse is correct;
* all Stage 2–8 tests remain passing;
* binary16 packing and unpacking remain placeholders;
* normal build succeeds;
* test build succeeds;
* JSON-disabled build succeeds;
* no new warnings appear;
* no public C API or header exists.

Stop after satisfying these criteria. Do not proceed to Stage 10.


