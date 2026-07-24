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

## 📗 

