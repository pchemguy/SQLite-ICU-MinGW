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

---
---

## 📗 Stage 10: Binary16 Packing

Implement only Stage 10 of the packed numeric BLOB extension.

This stage begins from the completed Stage 9 state, where:

* `pblob.c` is compiled into the SQLite amalgamation after `json.c`;
* `pblob_pack()` and `pblob_unpack()` are auto-registered;
* NULL propagation, strict storage-class validation, and exact format parsing are implemented;
* endian helpers, binary16 and binary32 classification helpers, signed-byte decoding, and checked packed-size calculation are implemented;
* `pblobJsonbInteger()` and `pblobJsonbNumber()` are implemented and tested;
* `int8` packing and unpacking are production-complete;
* binary32 packing and unpacking are production-complete;
* `<f2` and `>f2` packing remain placeholders;
* `<f2` and `>f2` unpacking remain placeholders;
* the portable FP16 implementation is already included with native conversion disabled.

Implement only binary16 packing for:

```sql
pblob_pack(json_array, '<f2')
pblob_pack(json_array, '>f2')
```

Do not implement binary16 unpacking in this stage.

### Objective

Make these two SQL workflows production-complete:

```sql
pblob_pack(json_array, '<f2') -> little-endian IEEE binary16 BLOB
pblob_pack(json_array, '>f2') -> big-endian IEEE binary16 BLOB
```

The implementation must:

* accept SQL TEXT JSON arrays;
* accept JSON integer and floating numeric nodes;
* reuse `pblobJsonbNumber()` for extraction;
* convert through the required path:

  ```text
  JSON numeric value -> double -> float -> IEEE binary16
  ```
* use the vendored FP16 conversion routine;
* keep native FP16 conversion disabled;
* reject non-finite source values;
* reject finite values that overflow to binary32 before binary16 conversion;
* reject finite values that convert to binary16 infinity;
* preserve positive and negative zero;
* permit underflow to binary16 subnormal or zero;
* emit exact IEEE binary16 bytes in the requested byte order;
* allocate the exact output size once;
* return a raw headerless BLOB;
* report the first invalid element using a zero-based index;
* preserve all existing `int8` and binary32 behavior;
* leave binary16 unpacking as a placeholder.

### Scope

This stage is limited to:

1. Extending `pblob_pack()` dispatch for `<f2` and `>f2`.
2. Reusing the existing production JSON parsing and array traversal workflow.
3. Accepting all SQLite JSON numeric node types.
4. Extracting values with `pblobJsonbNumber()`.
5. Narrowing `double` to binary32 `float`.
6. Rejecting non-finite binary32 intermediates.
7. Converting with `fp16_ieee_from_fp32_value()`.
8. Rejecting non-finite binary16 results.
9. Writing explicit little-endian or big-endian bytes.
10. Adding binary16 packing tests.
11. Adding focused reference-vector, limit, OOM, and prepared-statement tests.
12. Preserving all previous-stage tests.

Do not implement any binary16 unpacking behavior.

---

### Public Behavior Introduced in This Stage

The following calls must now succeed:

```sql
SELECT hex(pblob_pack('[1.0,2.0]', '<f2'));
SELECT hex(pblob_pack('[1.0,2.0]', '>f2'));
```

Expected:

```text
003C0040
3C004000
```

The following remain placeholders:

```text
pblob_unpack(..., '<f2')
pblob_unpack(..., '>f2')
```

All `int8` and binary32 workflows must remain unchanged.

---

### `pblob_pack()` Dispatch

Update `pblobPackFunc()` so that, after common validation and format parsing:

```text
PBLOB_INT8 -> existing int8 packing path
PBLOB_F32  -> existing binary32 packing path
PBLOB_F16  -> new binary16 packing path
```

Do not dispatch using raw format strings after `pblobParseFormat()` has populated `PblobFormat`.

For `PBLOB_F16`, require:

```text
pFormat.nByte == 2
pFormat.eOrder == PBLOB_ORDER_LE or PBLOB_ORDER_BE
```

Treat any inconsistent internal format descriptor as a defensive internal error.

---

### Shared Pack Workflow

Reuse the established production infrastructure for:

* JSON parsing;
* root-array validation;
* element counting;
* checked packed-size calculation;
* root payload discovery;
* sequential array traversal;
* exact output allocation;
* cleanup;
* malformed internal JSON checks.

Do not duplicate the complete callback.

A suitable private structure may be:

```c
static int pblobPackInt8(...);
static int pblobPackF16(...);
static int pblobPackF32(...);
```

or an equivalent shared element loop with format-specific conversion helpers.

All production helpers must remain `static`.

Do not create `pblob.h`.

---

### FP16 Configuration

The normative build must continue to force:

```c
#define FP16_USE_NATIVE_CONVERSION 0
```

before including the vendored FP16 header.

Add a compile-time check where practical:

```c
#if FP16_USE_NATIVE_CONVERSION
# error "pblob requires portable FP16 conversion"
#endif
```

or an equivalent static assertion compatible with the vendored header.

Do not:

* enable compiler-native half conversion;
* use `_Float16`;
* use `__fp16`;
* use F16C intrinsics;
* use AVX-512 FP16;
* use ARM half-conversion intrinsics;
* add a second half-float converter.

The portable FP16 implementation is the normative source of binary16 rounding behavior.

---

### JSON Parsing and Root Validation

Use the existing production path:

```c
jsonParseFuncArg(ctx, argv[0], 0)
```

Require:

```c
JSONB_ARRAY
```

at the root.

Use:

```c
jsonbArrayCount()
jsonbPayloadSize()
```

for count and traversal.

Do not accept caller-supplied JSONB BLOB input.

Do not introduce a separate JSON parser or numeric parser for binary16.

---

### Output Size

For binary16:

```text
output bytes = element count * 2
```

Call the existing checked-size helper with:

```text
nByte = 2
```

The helper must enforce:

* multiplication overflow protection;
* the current `SQLITE_LIMIT_LENGTH`.

Do not duplicate size or limit logic in the binary16 branch.

A zero-element array must return a zero-length BLOB.

---

### Accepted JSONB Element Types

For `<f2` and `>f2`, accept:

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

Accepted examples:

```json
[0]
[1]
[-1]
[1.0]
[-1.0]
[0.5]
[1e3]
[0x7f]
[-0x80]
[1,2.5,0x10,-3]
```

Rejected examples:

```json
[null]
[true]
[false]
["1"]
[[]]
[{}]
```

Recommended public error:

```text
pblob_pack: element N must be numeric for format <f2
```

or:

```text
pblob_pack: element N must be numeric for format >f2
```

The first invalid zero-based element index must be reported.

---

### Numeric Extraction

For every accepted numeric node, call:

```c
pblobJsonbNumber()
```

Do not:

* parse the numeric payload again;
* route integer nodes through `pblobJsonbInteger()`;
* use `strtof()`;
* use `strtod()`;
* use SQL numeric coercion;
* duplicate JSON5 hexadecimal handling.

The helper returns `double`.

The binary16 packing path is responsible for target conversion and range validation.

---

### Required Conversion Path

The normative conversion path is:

```text
SQLite JSON numeric payload
-> pblobJsonbNumber()
-> double
-> float
-> fp16_ieee_from_fp32_value()
-> uint16_t binary16 bits
```

Implement conceptually:

```c
double d;
float f;
uint16_t bits;

f = (float)d;
bits = fp16_ieee_from_fp32_value(f);
```

This means binary16 conversion is explicitly:

```text
binary64 -> binary32 -> binary16
```

Do not claim or implement direct correctly rounded binary64-to-binary16 conversion.

Do not:

* parse decimal text directly to binary16;
* manually construct half-float exponent or fraction fields;
* use a different library;
* convert through binary32 text.

Document the required two-step narrowing in a concise source comment.

---

### Source Finiteness Check

Before narrowing to `float`, reject non-finite `double` values.

Use established SQLite or project finite checks.

Recommended public error:

```text
pblob_pack: element N is not finite
```

This applies to SQLite-supported JSON5 infinity values if `pblobJsonbNumber()` returns a non-finite result.

NaN spellings converted by `json.c` to JSON null must fail earlier as nonnumeric element types.

Do not permit non-finite source values to reach the FP16 converter.

---

### Binary32 Intermediate Check

After:

```c
float f = (float)d;
```

obtain binary32 bits:

```c
uint32_t f32bits = fp32_to_bits(f);
```

Check:

```c
pblobF32IsFinite(f32bits)
```

If the binary32 intermediate is non-finite, reject the value.

Recommended public error:

```text
pblob_pack: element N is outside the finite float32 range
```

This check is mandatory even though the target is binary16.

Reason:

* the normative conversion path passes through binary32;
* a finite `double` may overflow to binary32 infinity;
* non-finite input must not be passed to the binary16 converter.

Do not convert a binary32 infinity into binary16 infinity and report only the later failure.

---

### Binary16 Conversion

For a finite binary32 intermediate, call:

```c
uint16_t bits = fp16_ieee_from_fp32_value(f);
```

Do not call a native or alternate conversion path.

The result must be interpreted as raw IEEE binary16 bits.

Do not convert the returned bits back to `float` merely to validate ordinary finite values.

---

### Binary16 Target Finiteness Check

After conversion, require:

```c
pblobF16IsFinite(bits)
```

If false, reject the element.

This catches finite binary32 values that overflow the finite binary16 range.

Recommended public error:

```text
pblob_pack: element N is outside the finite float16 range
```

Do not emit:

```text
7C00
FC00
```

for positive or negative infinity.

Do not clamp or saturate to:

```text
7BFF
FBFF
```

---

### Underflow Behavior

Finite values that convert to:

* a binary16 subnormal;
* positive zero;
* negative zero;

must be accepted.

Do not reject underflow merely because precision or magnitude is lost.

Do not flush subnormals to zero manually.

The vendored portable FP16 converter defines the normative rounding and underflow behavior.

---

### Signed Zero

Signed zero must be preserved through:

```text
double -> float -> binary16
```

Required raw values:

```text
+0.0 -> 0000
-0.0 -> 8000
```

Little-endian:

```text
+0.0 -> 0000
-0.0 -> 0080
```

Big-endian:

```text
+0.0 -> 0000
-0.0 -> 8000
```

Test supported negative-zero lexical forms:

```text
-0
-0.0
-0e0
```

Do not manually set the sign bit unless the extracted numeric value and binary32 intermediate retain negative zero.

The exact behavior of lexical integer `-0` must follow the selected SQLite JSON parser.

---

### Endian Encoding

For each finite binary16 word:

```text
<f2 -> pblobPutU16Le()
>f2 -> pblobPutU16Be()
```

Do not:

* write in host byte order;
* use pointer casts;
* use unaligned integer stores;
* use `memcpy()` as the endian policy;
* use platform byte-swap functions.

Required example:

```text
1.0 bits = 3C00

<f2 -> 00 3C
>f2 -> 3C 00
```

---

### Array Traversal

Use the same defensive traversal rules as existing pack workflows.

For each element:

1. Verify the current node offset is inside the root payload.
2. Obtain header and payload size with `jsonbPayloadSize()`.
3. Verify the complete node fits inside the root payload.
4. Validate the JSONB node type.
5. Extract `double` with `pblobJsonbNumber()`.
6. Reject non-finite source.
7. Narrow to binary32.
8. reject non-finite binary32 intermediate.
9. convert to binary16.
10. reject non-finite binary16 result.
11. write two bytes in requested order.
12. advance to the next node.

After processing the counted elements, require:

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

Use the same exact single-allocation strategy as existing pack paths.

For nonempty output:

```c
sqlite3_result_blob64(ctx, pOut, nOut, sqlite3_free);
```

On failure before result ownership transfer:

```c
sqlite3_free(pOut);
```

Always release:

```c
jsonParseFree(pParse);
```

Do not return a partial BLOB when an element fails after previous elements were written.

---

### Error Precedence

Preserve this order:

```text
NULL propagation
-> first argument storage class
-> format storage class
-> exact format value
-> JSON parsing
-> root array validation
-> checked output size
-> element type validation
-> numeric extraction
-> source finiteness
-> binary32 intermediate finiteness
-> binary16 target finiteness
-> byte output
```

Examples:

```sql
SELECT pblob_pack('bad JSON', 'bad');
```

Expected: unsupported-format error.

```sql
SELECT pblob_pack('bad JSON', '<f2');
```

Expected: malformed JSON.

```sql
SELECT pblob_pack('{}', '<f2');
```

Expected: expected-array error.

```sql
SELECT pblob_pack('[null]', '<f2');
```

Expected: nonnumeric-element error.

```sql
SELECT pblob_pack('[1e999]', '<f2');
```

Expected: non-finite source or float32-range error according to actual extraction behavior.

```sql
SELECT pblob_pack('[70000]', '<f2');
```

Expected: finite float16 range error.

---

### Primary Exact Binary16 Vectors

Add exact-byte tests for both byte orders.

#### Zero and Signed Zero

Values:

```text
+0.0
-0.0
```

Expected bits:

```text
0000
8000
```

Expected `<f2`:

```text
00000080
```

Expected `>f2`:

```text
00008000
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
3C00
BC00
4000
3800
```

Expected `<f2`:

```text
003C00BC00400038
```

Expected `>f2`:

```text
3C00BC0040003800
```

#### Required Minimal Vector

```sql
SELECT hex(
  pblob_pack('[1.0,2.0]', '<f2')
);
```

Expected:

```text
003C0040
```

```sql
SELECT hex(
  pblob_pack('[1.0,2.0]', '>f2')
);
```

Expected:

```text
3C004000
```

---

### Canonical IEEE Binary16 Vectors

Include at least:

| Value                       | Bits   |
| --------------------------- | ------ |
| positive zero               | `0000` |
| negative zero               | `8000` |
| smallest positive subnormal | `0001` |
| largest positive subnormal  | `03FF` |
| smallest positive normal    | `0400` |
| `0.5`                       | `3800` |
| `1.0`                       | `3C00` |
| `-1.0`                      | `BC00` |
| `2.0`                       | `4000` |
| maximum positive finite     | `7BFF` |
| maximum negative finite     | `FBFF` |

Test both little-endian and big-endian representations.

Expected decimal inputs must be generated independently and must model the specified binary64-to-binary32-to-binary16 path.

---

### Rounding Tests

Add representative binary16 rounding tests.

Include values:

* exactly representable in binary16;
* halfway between adjacent binary16 values;
* immediately below halfway;
* immediately above halfway;
* around `1.0`;
* around powers of two;
* around the normal/subnormal boundary;
* positive and negative variants.

The expected result must model:

```text
decimal text
-> binary64
-> binary32
-> vendored binary16 conversion
```

Do not use direct decimal-to-binary16 results as the oracle when the two-step path could differ.

Include ties that verify round-to-nearest-even behavior implemented by the vendored FP16 converter.

---

### Double-Rounding Cases

Because the normative path includes binary32 narrowing before binary16 conversion, add targeted cases where direct binary64-to-binary16 conversion could differ from:

```text
binary64 -> binary32 -> binary16
```

The test oracle must follow the required two-step path.

Commit at least several such vectors if the independent generator can locate them.

The implementation must match the specified path, not an idealized direct conversion.

---

### Subnormal Tests

Test at least:

```text
smallest positive binary16 subnormal
second positive subnormal
largest positive subnormal
negative counterparts
```

Verify exact output bits.

Also test values that round:

* from normal to largest subnormal;
* from subnormal to minimum normal;
* to positive zero;
* to negative zero.

Do not reject finite subnormal outputs.

---

### Underflow-to-Zero Tests

Test finite values whose binary16 result is:

```text
0000
8000
```

Include values:

* below half the smallest positive subnormal;
* exactly at relevant rounding boundaries;
* negative equivalents.

Expected behavior must come from the portable FP16 reference path.

Signed zero must be verified through exact bytes.

---

### Maximum-Finite and Overflow Tests

Accept exact maximum finite binary16:

```text
7BFF
FBFF
```

Reject finite values that convert to:

```text
7C00
FC00
```

Test:

* maximum finite;
* largest value rounding to maximum finite;
* smallest value rounding to infinity;
* values clearly outside range;
* positive and negative forms.

Do not hard-code only a rough decimal threshold such as `65504`.

Use independently generated boundary vectors.

---

### Binary32 Intermediate Overflow Tests

Test finite decimal values that overflow during:

```text
double -> float
```

before binary16 conversion.

Expected: float32 intermediate range error.

These are distinct from ordinary binary16 overflow cases.

The test should prove the implementation checks the binary32 intermediate before calling the binary16 converter.

---

### JSON5 Numeric Tests

Test SQLite-supported forms:

```text
[+1]
[.5]
[1.]
[0x7f]
[-0x80]
[1,]
[/*comment*/1.5]
```

Expected bytes must match equivalent canonical values.

Test:

```text
Infinity
-Infinity
NaN
QNaN
SNaN
```

Expected:

* infinity forms are rejected as non-finite;
* NaN forms mapped to JSON null are rejected as nonnumeric elements.

Do not add custom JSON5 handling.

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

### Empty Array Tests

For both binary16 formats:

```sql
SELECT typeof(pblob_pack('[]','<f2'));
SELECT length(pblob_pack('[]','<f2'));
SELECT hex(pblob_pack('[]','<f2'));

SELECT typeof(pblob_pack('[]','>f2'));
SELECT length(pblob_pack('[]','>f2'));
SELECT hex(pblob_pack('[]','>f2'));
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
length(result) == element count * 2
typeof(result) == blob
```

Use deterministic numeric patterns that remain finite in binary16.

For representative large arrays verify:

* first word;
* middle word;
* last word;
* repeated calls produce identical output.

---

### SQLite Length-Limit Tests

Temporarily lower:

```text
SQLITE_LIMIT_LENGTH
```

Test:

```text
nElem * 2 == limit
nElem * 2 > limit
```

Expected:

```text
at limit -> success
over limit -> result-too-large error
```

Restore the original limit after each test.

This must exercise `pblobCheckedSize()` rather than duplicate its logic.

---

### Prepared-Statement Reuse

Prepare:

```sql
SELECT pblob_pack(?1, '<f2');
```

Execute repeatedly with:

```text
[]
[0]
[1.0,-1.0]
large valid array
[null]
[70000]
[2.0]
```

Verify:

* no stale output;
* errors do not corrupt later success;
* a prior large allocation does not affect later small output;
* range and type errors leave the statement reusable.

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
>f2
bad
<f2
```

Verify dispatch remains correct.

---

### Focused OOM Tests

Use SQLite fault injection where supported.

Exercise OOM during:

1. JSON parsing.
2. temporary numeric payload duplication in `pblobJsonbNumber()`.
3. exact output BLOB allocation.
4. processing after earlier elements have already been written.

Verify:

* no partial BLOB is returned;
* the output allocation is freed;
* `JsonParse` is released;
* a subsequent valid call succeeds.

Do not broaden this into the final complete fault matrix.

---

### Independent Binary16 Reference Vectors

Extend the independent reference-vector generator for binary16 packing.

The generator must model exactly:

```text
decimal input
-> IEEE binary64
-> IEEE binary32
-> portable IEEE binary16 conversion
-> selected byte order
```

It must not:

* call SQLite;
* call `pblob_pack()`;
* consume bytes emitted by the implementation under test;
* silently use direct binary64-to-binary16 conversion.

Preferred oracle choices:

1. Compile and run a small independent program using the same vendored FP16 public conversion API but not `pblob.c`.
2. Implement the portable FP16 algorithm independently in the generator.
3. Use a verified external numeric library only after proving it models the required binary32 intermediate.

Record:

```text
generator version
runtime/compiler version
FP16 source revision
portable-path status
rounding mode assumptions
endianness handling
```

Commit generated vectors as static test data.

Normal tests must not require the generator.

---

### Portable-Path Verification

Add a test-build assertion or diagnostic proving:

```text
FP16_USE_NATIVE_CONVERSION == 0
```

The normal test suite must fail if the build unexpectedly enables native conversion.

Do not infer portable mode solely from runtime results.

---

### Regression Tests

All Stage 2–9 tests must remain passing, including:

* registration and arity;
* NULL propagation;
* strict storage classes;
* exact format parsing;
* embedded-NUL rejection;
* endian and classification helpers;
* numeric extraction helpers;
* complete `int8` tests;
* complete binary32 packing tests;
* complete binary32 unpacking tests;
* binary32 round-trip, cross-endian, subtype, limit, OOM, and prepared-statement tests.

Verify binary16 unpacking remains a placeholder.

---

### Test Module Changes

Extend:

```text
test/pblob.test
```

with public binary16 packing tests.

Extend:

```text
tool/gen_pblob_vectors.py
```

or the selected independent vector generator.

Extend committed vector data as required.

Use existing test-only infrastructure for portable-path, OOM, and limit checks.

Do not implement binary16 unpacking tests beyond confirming the placeholder remains.

Do not register a public debug SQL function.

---

### Build Verification

Perform all required configurations.

#### Normal Build

Verify:

* `<f2` and `>f2` packing compile and link;
* exact vectors pass;
* portable FP16 mode is active;
* all existing behavior remains unchanged;
* no new warnings appear;
* no test-only interface is present.

#### Test Build

Build `testfixture` or the project equivalent with:

```text
SQLITE_TEST
FP16_USE_NATIVE_CONVERSION=0
```

Run:

* exact binary16 vectors;
* signed-zero tests;
* rounding tests;
* double-rounding tests;
* subnormal tests;
* underflow-to-zero tests;
* maximum-finite tests;
* overflow tests;
* binary32 intermediate overflow tests;
* JSON5 tests;
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
* no JSONB or FP16 packing references remain unresolved;
* no warnings are introduced;
* FP16 code is not unnecessarily active outside the JSON guard.

---

### Prohibited Work

Do not implement:

* binary16 unpacking;
* binary16 BLOB-length validation;
* `fp16_ieee_to_fp32_value()` in production;
* binary16 JSON output;
* binary16 non-finite unpack rejection;
* direct binary64-to-binary16 conversion;
* native half conversion;
* `_Float16`;
* `__fp16`;
* hardware FP16 intrinsics;
* another half-float library;
* saturation to maximum finite;
* infinity or NaN output;
* format inference;
* BLOB headers or metadata;
* JSONB input acceptance for `pblob_pack()`;
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
3. Updated independent binary16 packing vectors and generator.
4. Any narrowly scoped test-only changes required for portable-path, limit, or OOM testing.
5. Exact build commands executed.
6. Exact test commands executed.
7. Results for:

   * normal build;
   * test build;
   * JSON-disabled build.
8. A concise list of modified files.
9. Confirmation that:

   * only `<f2` and `>f2` packing became newly functional;
   * conversion follows `double -> float -> binary16`;
   * `fp16_ieee_from_fp32_value()` is used;
   * portable FP16 mode is forced;
   * non-finite source values are rejected;
   * non-finite binary32 intermediates are rejected;
   * non-finite binary16 results are rejected;
   * underflow is accepted;
   * signed zero is preserved;
   * endian output uses explicit byte helpers;
   * output allocation is exact and single-shot;
   * binary16 unpacking remains a placeholder;
   * no public API or header was added.

---

### Acceptance Criteria

Stage 10 is complete only when:

* `pblob_pack(...,'<f2')` emits exact little-endian IEEE binary16 bytes;
* `pblob_pack(...,'>f2')` emits exact big-endian IEEE binary16 bytes;
* integer and floating JSON numeric nodes are accepted;
* nonnumeric elements are rejected with the first zero-based index;
* extraction uses `pblobJsonbNumber()`;
* conversion follows the required `double -> float -> binary16` path;
* portable FP16 conversion is forced and verified;
* `fp16_ieee_from_fp32_value()` is used;
* signed zero is preserved;
* finite subnormal and zero-underflow results are accepted;
* finite values that overflow binary16 are rejected;
* finite values that overflow the binary32 intermediate are rejected;
* non-finite source values are rejected;
* no infinity or NaN binary16 bytes are emitted;
* exact independent vectors pass;
* rounding and double-rounding tests pass;
* output size is exactly `element count * 2`;
* SQLite length limits are enforced;
* OOM paths release all owned state;
* prepared-statement reuse is correct;
* all Stage 2–9 tests remain passing;
* binary16 unpacking remains a placeholder;
* normal build succeeds;
* test build succeeds;
* JSON-disabled build succeeds;
* no new warnings appear;
* no public C API or header exists.

Stop after satisfying these criteria. Do not proceed to Stage 11.

---
---

## 📗 Stage 11: Binary16 Unpacking

Implement only Stage 11 of the packed numeric BLOB extension.

This stage begins from the completed Stage 10 state, where:

* `pblob.c` is compiled into the SQLite amalgamation after `json.c`;
* `pblob_pack()` and `pblob_unpack()` are auto-registered;
* NULL propagation, strict storage-class validation, and exact format parsing are implemented;
* endian helpers, binary16 and binary32 classification helpers, signed-byte decoding, and checked packed-size calculation are implemented;
* `pblobJsonbInteger()` and `pblobJsonbNumber()` are implemented and tested;
* `int8` packing and unpacking are production-complete;
* binary32 packing and unpacking are production-complete;
* binary16 packing for `<f2` and `>f2` is production-complete;
* binary16 unpacking remains a placeholder;
* portable FP16 conversion is forced with `FP16_USE_NATIVE_CONVERSION=0`.

Implement only binary16 unpacking for:

```sql
pblob_unpack(blob, '<f2')
pblob_unpack(blob, '>f2')
```

Do not change the public semantics of any already implemented format.

### Objective

Make these two SQL workflows production-complete:

```sql
pblob_unpack(blob, '<f2') -> JSON text
pblob_unpack(blob, '>f2') -> JSON text
```

The implementation must:

* accept only SQL BLOB input;
* require the BLOB length to be divisible by two;
* read every element using explicit endian helpers;
* reject every IEEE binary16 infinity and NaN bit pattern;
* convert finite binary16 values using the vendored portable FP16 implementation;
* use the required conversion path:

  ```text
  binary16 bits -> binary32 float -> binary64 double
  ```
* preserve positive and negative zero;
* preserve every finite binary16 value exactly through promotion;
* emit compact valid JSON text;
* assign SQLite’s JSON subtype;
* report the first invalid element using a zero-based index;
* allow every finite binary16 subnormal and normal value;
* preserve all existing `int8`, binary32, and binary16 packing behavior.

After this stage, all five supported formats must be functional in both directions.

### Scope

This stage is limited to:

1. Extending `pblob_unpack()` dispatch for `<f2` and `>f2`.
2. Validating binary16 BLOB length.
3. Reading binary16 words with explicit endian helpers.
4. Rejecting non-finite raw binary16 values.
5. Converting with `fp16_ieee_to_fp32_value()`.
6. Promoting the resulting binary32 `float` to `double`.
7. Formatting finite values through SQLite’s JSON formatter.
8. Preserving signed zero.
9. Returning JSON-subtyped TEXT.
10. Adding binary16 unpacking, round-trip, exhaustive, limit, OOM, and prepared-statement tests.
11. Preserving all previous-stage tests.

Do not add new formats or public APIs.

---

### Public Behavior Introduced in This Stage

The following calls must now succeed:

```sql
SELECT pblob_unpack(x'003C0040', '<f2');
SELECT pblob_unpack(x'3C004000', '>f2');
```

Expected semantic result:

```text
[1.0,2.0]
[1.0,2.0]
```

Exact numeric spelling must follow SQLite’s established JSON formatter.

After this stage, no supported format may retain a placeholder branch.

---

### `pblob_unpack()` Dispatch

Update `pblobUnpackFunc()` so that, after common validation and format parsing:

```text
PBLOB_INT8 -> existing int8 unpacking path
PBLOB_F16  -> new binary16 unpacking path
PBLOB_F32  -> existing binary32 unpacking path
```

Do not compare raw format strings after `pblobParseFormat()` succeeds.

For `PBLOB_F16`, require:

```text
pFormat.nByte == 2
pFormat.eOrder == PBLOB_ORDER_LE or PBLOB_ORDER_BE
```

Treat any inconsistent internal format descriptor as a defensive internal error.

Remove the temporary binary16 unpack placeholder only after both endian paths are implemented.

---

### Shared Unpack Workflow

Reuse the established unpacking infrastructure for:

* BLOB retrieval;
* format dispatch;
* `JsonString` initialization;
* compact array punctuation;
* result finalization;
* subtype assignment;
* cleanup;
* OOM handling.

Do not duplicate the entire SQL callback.

A suitable private organization is:

```c
static int pblobUnpackInt8(...);
static int pblobUnpackF16(...);
static int pblobUnpackF32(...);
```

or an equivalent shared element loop.

All production helpers must remain `static`.

Do not create `pblob.h`.

---

### BLOB Retrieval

Use the existing validated BLOB path:

```c
const u8 *pBlob = sqlite3_value_blob(argv[0]);
int nBlob = sqlite3_value_bytes(argv[0]);
```

or the exact selected-source types.

Required behavior:

* zero-length BLOB is valid;
* NULL pointer with zero length is valid;
* the input is not copied;
* the BLOB is treated as raw binary16 words;
* no JSONB interpretation occurs.

Do not call `sqlite3_value_text()` on the BLOB.

---

### BLOB Length Validation

For binary16:

```text
element width = 2 bytes
```

Require:

```text
nBlob % 2 == 0
```

If the BLOB length is odd, return a stable function-specific error.

Recommended messages:

```text
pblob_unpack: BLOB length is not divisible by 2 for format <f2
pblob_unpack: BLOB length is not divisible by 2 for format >f2
```

Length validation must occur:

* after NULL propagation;
* after first-argument type validation;
* after format validation;
* before `JsonString` initialization where practical;
* before reading any element.

Do not decode a prefix of an odd-length BLOB.

---

### Element Count

For binary16:

```text
element count = nBlob / 2
```

Use a type that safely represents the result.

Do not call `pblobCheckedSize()` for input division.

No output-size precomputation is required; `JsonString` handles dynamic textual output growth.

---

### Endian Decoding

For each element:

```text
<f2 -> pblobGetU16Le()
>f2 -> pblobGetU16Be()
```

Required examples:

```text
bytes 00 3C under <f2 -> bits 3C00
bytes 3C 00 under >f2 -> bits 3C00
```

Do not use:

* host byte order;
* pointer casts;
* unaligned `uint16_t` loads;
* `memcpy()` as the endian policy;
* platform byte-swap APIs.

Element byte offsets are:

```text
0
2
4
6
...
```

---

### Raw Binary16 Classification

Before conversion, classify each raw word using:

```c
pblobF16IsFinite()
pblobF16IsInf()
pblobF16IsNaN()
```

Reject every non-finite pattern.

Required rejected classes:

```text
positive infinity
negative infinity
quiet NaN
signaling NaN
positive NaN payloads
negative NaN payloads
```

Recommended public errors:

```text
pblob_unpack: element N is infinity
pblob_unpack: element N is NaN
```

A combined stable error is also acceptable:

```text
pblob_unpack: element N is not a finite float16 value
```

The first invalid zero-based element index must be reported.

Do not:

* convert infinity or NaN to JSON null;
* emit `Infinity`;
* emit `NaN`;
* pass non-finite words to the FP16 converter before classification;
* silently canonicalize NaN payloads.

---

### Required Conversion Path

For each finite binary16 word:

```c
float f = fp16_ieee_to_fp32_value(bits);
double d = (double)f;
```

This path is normative:

```text
binary16 raw bits
-> vendored portable FP16 converter
-> binary32 float
-> exact binary64 promotion
```

Do not:

* manually decode sign, exponent, and significand into `double`;
* use `_Float16`;
* use `__fp16`;
* use hardware half-float instructions;
* use union type-punning;
* pointer-cast raw words;
* convert through decimal text;
* add another FP16 implementation.

The binary32-to-binary64 promotion must remain an ordinary exact C conversion.

---

### Portable FP16 Requirement

The build must continue to force:

```c
FP16_USE_NATIVE_CONVERSION == 0
```

The Stage 10 compile-time or test-time verification must remain active.

Do not weaken or remove it.

Binary16 unpacking must use:

```c
fp16_ieee_to_fp32_value()
```

from the vendored portable implementation.

Do not select a platform-dependent native path at runtime or compile time.

---

### Conversion Validation

All raw words accepted by `pblobF16IsFinite()` should convert to finite binary32 values.

The implementation may defensively verify:

```c
pblobF32IsFinite(fp32_to_bits(f))
```

after conversion.

If this check is included, a failure must be treated as an internal conversion error, because every finite IEEE binary16 value is exactly representable as finite IEEE binary32.

Do not use this defensive check to reject subnormals or signed zero.

---

### JSON Numeric Formatting

Promote the converted `float` to `double` and append using SQLite’s JSON-aware formatter.

Use the exact project convention, expected to be equivalent to:

```c
jsonPrintf(100, &out, "%!0.17g", d);
```

Requirements:

* output must be valid JSON;
* output must be compact;
* every finite binary16 value must serialize so that repacking through the specified binary32-to-binary16 path reproduces the original bits;
* signed zero must remain distinguishable;
* formatting must be locale-independent.

Do not use:

```c
printf()
sprintf()
snprintf()
sqlite3_mprintf()
strfromf()
```

Do not emit hexadecimal floating-point syntax.

---

### Floating-Point JSON Syntax

Decoded binary16 values remain floating-point values even when mathematically integral.

Use SQLite’s established floating JSON formatter.

Do not deliberately emit integer syntax for values such as:

```text
1.0
2.0
-1.0
```

Do not cast to `sqlite3_int64` merely because the value is integral.

The required invariant is:

```text
pblob_pack(pblob_unpack(blob, format), format)
```

reproduces every finite binary16 word exactly.

---

### Signed Zero

Signed zero must be preserved.

Raw patterns:

```text
0000 -> positive zero
8000 -> negative zero
```

Big-endian tests:

```sql
SELECT pblob_unpack(x'0000', '>f2');
SELECT pblob_unpack(x'8000', '>f2');
```

Little-endian tests:

```sql
SELECT pblob_unpack(x'0000', '<f2');
SELECT pblob_unpack(x'0080', '<f2');
```

Verify negative zero through exact repacking:

```sql
SELECT hex(
  pblob_pack(
    pblob_unpack(x'8000', '>f2'),
    '>f2'
  )
);
```

Expected:

```text
8000
```

Also test little-endian:

```text
0080
```

Do not rely only on displayed JSON text.

---

### Finite Subnormal Values

All finite binary16 subnormals are valid.

Required examples:

```text
0001
0002
03FF
8001
8002
83FF
```

The implementation must:

* accept them;
* preserve sign;
* emit valid JSON numbers;
* reproduce the exact original bits when repacked.

Do not flush binary16 subnormals to zero.

The portable converter must determine their exact binary32 values.

---

### Normal Values

Accept every binary16 normal value whose exponent field is not all ones.

Required examples include:

```text
0400
3C00
BC00
4000
7BFF
8400
FBFF
```

These include:

* minimum positive normal;
* `1.0`;
* `-1.0`;
* `2.0`;
* maximum positive finite;
* minimum negative normal;
* maximum negative finite.

---

### JSON Output Construction

Use existing `JsonString` infrastructure:

```c
JsonString out;

jsonStringInit(&out, ctx);
jsonAppendChar(&out, '[');
/* append values */
jsonAppendChar(&out, ']');
jsonReturnString(...);
```

Use commas without spaces.

A zero-length BLOB must return:

```text
[]
```

with:

```text
storage class: TEXT
subtype: JSON_SUBTYPE
```

Do not manually concatenate text.

---

### Result Finalization and Subtype

Finalize using the established `jsonReturnString()` path.

After successful finalization, assign:

```c
sqlite3_result_subtype(ctx, JSON_SUBTYPE);
```

Retain:

```c
SQLITE_RESULT_SUBTYPE
```

in the SQL function registration flags.

Do not assign the JSON subtype after an error.

Test composition:

```sql
SELECT json_array(
  pblob_unpack(x'3C004000', '>f2')
);
```

Expected semantic result:

```json
[[1.0,2.0]]
```

It must not become:

```json
["[1.0,2.0]"]
```

Also test:

```sql
SELECT json_type(pblob_unpack(x'3C00', '>f2'));
SELECT json_array_length(pblob_unpack(x'3C004000', '>f2'));
```

Expected:

```text
array
2
```

---

### Empty BLOB

For both formats:

```sql
SELECT pblob_unpack(x'', '<f2');
SELECT pblob_unpack(x'', '>f2');
```

Expected:

```text
[]
[]
```

Also verify:

```sql
SELECT typeof(pblob_unpack(x'', '<f2'));
SELECT json_valid(pblob_unpack(x'', '<f2'));
SELECT json_array_length(pblob_unpack(x'', '<f2'));
```

Expected:

```text
text
1
0
```

Do not return SQL NULL or BLOB.

---

### Error Precedence

Preserve this order:

```text
NULL propagation
-> first argument storage class
-> format storage class
-> exact format value
-> binary16 BLOB length validation
-> per-element raw classification
-> FP16 conversion
-> JSON output construction
```

Examples:

```sql
SELECT pblob_unpack(NULL, 'bad');
```

Expected: SQL NULL.

```sql
SELECT pblob_unpack('0000', '>f2');
```

Expected: first-argument BLOB error.

```sql
SELECT pblob_unpack(x'0000', 1);
```

Expected: format-must-be-text error.

```sql
SELECT pblob_unpack(x'0000', 'bad');
```

Expected: unsupported-format error.

```sql
SELECT pblob_unpack(x'00', '<f2');
```

Expected: invalid binary16 length error.

```sql
SELECT pblob_unpack(x'7C00', '>f2');
```

Expected: non-finite element error at index 0.

```sql
SELECT pblob_unpack(x'3C00', '>f2');
```

Expected semantic result:

```text
[1.0]
```

---

### Primary Exact Binary16 Unpack Tests

Add tests for both endian forms.

#### Basic Values

Raw words:

```text
3C00
BC00
4000
3800
```

Semantic values:

```text
1.0
-1.0
2.0
0.5
```

Big-endian BLOB:

```text
3C00BC0040003800
```

Little-endian BLOB:

```text
003C00BC00400038
```

Where exact JSON spelling is stable, assert exact text.

Otherwise verify:

* valid JSON;
* array length;
* semantic numeric values;
* exact repacked bytes.

#### Required Minimal Vector

```sql
SELECT pblob_unpack(x'003C0040', '<f2');
```

Expected semantic result:

```text
[1.0,2.0]
```

```sql
SELECT pblob_unpack(x'3C004000', '>f2');
```

Expected the same.

---

### Canonical Finite Bit Vectors

Test at least:

| Bits   | Meaning                     |
| ------ | --------------------------- |
| `0000` | positive zero               |
| `8000` | negative zero               |
| `0001` | smallest positive subnormal |
| `8001` | smallest negative subnormal |
| `03FF` | largest positive subnormal  |
| `83FF` | largest negative subnormal  |
| `0400` | smallest positive normal    |
| `8400` | smallest negative normal    |
| `3800` | `0.5`                       |
| `3C00` | `1.0`                       |
| `BC00` | `-1.0`                      |
| `4000` | `2.0`                       |
| `7BFF` | maximum positive finite     |
| `FBFF` | maximum negative finite     |

Test both endian encodings.

For every vector verify:

```text
unpack succeeds
json_valid(result) == 1
array length is correct
repacking reproduces the original bits
```

---

### Non-Finite Rejection Tests

Reject infinity:

```text
7C00
FC00
```

Reject representative NaNs:

```text
7C01
7D00
7E00
7FFF
FC01
FD00
FE00
FFFF
```

Test both endian forms.

Test invalid values at nonzero indexes:

```text
[finite, infinity, finite]
[finite, NaN, finite]
```

Verify the first invalid zero-based index.

No partial JSON result may be returned.

---

### Invalid Length Tests

Reject odd BLOB lengths:

```text
1
3
5
7
9
```

Test both `<f2` and `>f2`.

Accept even lengths:

```text
0
2
4
6
8
10
```

Length failure must occur before raw-value classification.

No prefix may be decoded from an odd-length BLOB.

---

### Pack/Unpack Bit-Identity Tests

For every committed finite binary16 vector, test:

```sql
SELECT hex(
  pblob_pack(
    pblob_unpack(?1, '<f2'),
    '<f2'
  )
);
```

Expected: original little-endian BLOB.

Repeat for `>f2`.

Include:

* zero;
* negative zero;
* positive and negative subnormals;
* minimum normals;
* ordinary normals;
* maximum finite values;
* mixed arrays;
* independently generated random finite words.

This identity is mandatory for every finite binary16 pattern tested.

---

### Cross-Endian Tests

Test little-endian unpack followed by big-endian packing:

```sql
SELECT hex(
  pblob_pack(
    pblob_unpack(x'003C0040', '<f2'),
    '>f2'
  )
);
```

Expected:

```text
3C004000
```

Test the reverse:

```sql
SELECT hex(
  pblob_pack(
    pblob_unpack(x'3C004000', '>f2'),
    '<f2'
  )
);
```

Expected:

```text
003C0040
```

Extend this to signed zero, subnormal, minimum normal, and maximum finite vectors.

---

### Exhaustive Finite Binary16 Test

The test build must exhaustively cover all 65,536 binary16 bit patterns.

For every raw word from:

```text
0000 through FFFF
```

perform classification.

Required totals:

```text
finite patterns: 63,488
infinity patterns: 2
NaN patterns: 2,046
```

For every finite word:

1. Decode with `fp16_ieee_to_fp32_value()`.
2. Promote to `double`.
3. Serialize through the production or equivalent formatter.
4. Parse and pack using the production binary16 packing path.
5. Verify the original binary16 bits are reproduced.

For every infinity or NaN word:

* verify `pblob_unpack()` rejects it;
* verify classification is correct.

The exhaustive loop should be implemented in test-only C where practical for performance.

Do not issue 65,536 separate SQL statements from Tcl unless measured performance is acceptable.

---

### Exhaustive Classification Counts

Explicitly verify:

```text
positive infinity: 1
negative infinity: 1
positive NaNs: 1,023
negative NaNs: 1,023
positive finite values including +0: 31,744
negative finite values including -0: 31,744
```

Ensure no bit pattern belongs to more than one category.

---

### Exhaustive Finite Conversion Oracle

For each finite binary16 word, independently verify that:

```text
fp16_ieee_to_fp32_value(bits)
```

produces the expected binary32 bits.

The expected mapping must not be generated by `pblob.c`.

Acceptable approaches:

1. A separate test-only reference implementation.
2. Committed independently generated mapping or digest.
3. Comparison with an established independent half-to-float implementation.
4. Exhaustive digest comparison generated by the reference-vector tool.

The production converter and independent oracle must not be the same code path presented under different wrappers.

At minimum, calculate and commit stable digests over:

```text
input binary16 word
decoded binary32 bits
```

for all finite inputs.

Document the digest algorithm and byte ordering.

---

### JSON Formatting Round-Trip

The most important public invariant is:

```text
finite binary16 bits
-> unpack JSON
-> pack binary16
-> identical bits
```

The exhaustive test must verify this for every finite raw word.

This validates:

* FP16 decoding;
* exact binary32-to-binary64 promotion;
* JSON number formatting;
* JSON reparsing;
* binary64-to-binary32 narrowing;
* binary32-to-binary16 conversion;
* signed-zero preservation.

Any failure must report the original raw word and intermediate values.

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

Input length:

```text
element count * 2
```

Use deterministic finite binary16 patterns.

For each successful case verify:

```text
json_valid(result) == 1
json_array_length(result) == element count
typeof(result) == text
repacking reproduces the original BLOB
```

For representative arrays verify:

* first value;
* middle value;
* last value.

---

### SQLite Length-Limit Tests

Binary16 JSON output can be substantially larger than the input BLOB.

Temporarily lower:

```text
SQLITE_LIMIT_LENGTH
```

Test outputs that:

* fit below the limit;
* are near the limit;
* exceed the limit.

Expected oversized behavior:

* SQLite string-too-large error;
* no partial JSON output;
* no subtype assigned after failure;
* subsequent valid calls succeed.

Restore the prior limit after each test.

Derive the boundary from actual compact output length rather than from a fixed multiplier of input length.

---

### Prepared-Statement Reuse

Prepare:

```sql
SELECT pblob_unpack(?1, '<f2');
```

Execute repeatedly with:

```text
empty BLOB
one finite value
multiple finite values
odd-length BLOB
infinity
NaN
large finite BLOB
one finite value
```

Verify:

* errors do not corrupt later successful results;
* no stale JSON text remains;
* a prior large allocation does not affect a later small result;
* subtype is correct after recovery from errors.

Also prepare:

```sql
SELECT pblob_unpack(?1, ?2);
```

Alternate:

```text
int8
<f2
>f2
<f4
>f4
bad
<f2
```

Verify format dispatch and recovery.

---

### Focused OOM Tests

Use SQLite fault injection where supported.

Exercise OOM during:

1. initial `JsonString` growth;
2. later growth after multiple elements;
3. formatting of a long subnormal or maximum-finite decimal;
4. final result transfer where applicable.

Verify:

* no partial JSON result is returned;
* `JsonString` storage is released;
* subtype is not assigned after failure;
* a subsequent valid call succeeds.

Do not broaden unrelated code in this stage.

---

### Independent Binary16 Unpack Vectors

Extend the independent vector suite to cover binary16 unpacking.

Commit vectors for:

* positive and negative zero;
* subnormals;
* normal boundaries;
* ordinary values;
* maximum finite values;
* infinities;
* NaNs;
* both endian forms;
* multiple-element arrays.

Normal tests must use committed static vectors and must not require Python, NumPy, or the generator.

The generator must record:

```text
runtime/compiler version
FP16 oracle implementation
portable-path status
endianness handling
digest algorithm
```

---

### Regression Tests

All Stage 2–10 tests must remain passing, including:

* registration and arity;
* NULL propagation;
* strict storage classes;
* exact format parsing;
* embedded-NUL format rejection;
* endian and bit-classification tests;
* checked-size tests;
* numeric extraction tests;
* complete `int8` pack and unpack tests;
* complete binary32 pack and unpack tests;
* complete binary16 packing tests;
* signed-zero, subnormal, rounding, overflow, limit, OOM, and prepared-statement tests.

After Stage 11, no supported format may return a not-implemented placeholder.

Add an explicit regression test that invokes all ten supported function/format directions:

```text
pack int8
unpack int8
pack <f2
unpack <f2
pack >f2
unpack >f2
pack <f4
unpack <f4
pack >f4
unpack >f4
```

All must succeed for valid input.

---

### Test Module Changes

Extend:

```text
test/pblob.test
```

with public binary16 unpacking tests.

Extend test-only C infrastructure for exhaustive binary16 testing where necessary.

Extend:

```text
tool/gen_pblob_vectors.py
```

or the selected independent vector generator.

Update committed vector data.

Do not register a public debug SQL function.

Any exhaustive helper must remain test-only.

---

### Build Verification

Perform all required configurations.

#### Normal Build

Verify:

* `<f2` and `>f2` unpacking compile and link;
* canonical and round-trip vectors pass;
* JSON subtype composition works;
* every supported format is functional;
* no placeholder code remains for supported formats;
* no new warnings appear;
* no test-only interface is present.

#### Test Build

Build `testfixture` or the project equivalent with:

```text
SQLITE_TEST
FP16_USE_NATIVE_CONVERSION=0
```

Run:

* exact binary16 unpack vectors;
* invalid-length tests;
* signed-zero tests;
* subnormal tests;
* maximum-finite tests;
* non-finite rejection tests;
* bit-identity tests;
* cross-endian tests;
* exhaustive 65,536-pattern classification;
* exhaustive finite round-trip tests;
* independent conversion-oracle checks;
* large-BLOB tests;
* subtype tests;
* limit tests;
* prepared-statement tests;
* focused OOM tests;
* every previous-stage test.

#### JSON-Disabled Build

Build with:

```text
SQLITE_OMIT_JSON
```

Verify:

* build and link succeed;
* no `pblob` SQL functions are registered;
* no `JsonString`, JSONB, or FP16 unpack references remain unresolved;
* FP16 code is not unnecessarily active outside the JSON guard;
* no warnings are introduced.

---

### Prohibited Work

Do not:

* add new packed formats;
* add BLOB headers;
* add metadata;
* add automatic endian detection;
* accept native-endian aliases;
* output infinity or NaN;
* map non-finite values to null;
* manually decode binary16 into binary64;
* use native half types;
* use hardware half-conversion instructions;
* add another FP16 implementation;
* accept JSONB input for `pblob_pack()`;
* return JSONB from `pblob_unpack()`;
* expose test-only helpers in release builds;
* add a public C API;
* add `pblob.h`.

Do not modify:

* `json.c`;
* the vendored FP16 implementation;
* unrelated SQLite code.

Do not register additional production SQL functions.

---

### Expected Deliverables

Provide:

1. Updated `pblob.c`.
2. Updated `test/pblob.test`.
3. Updated test-only binary16 exhaustive-test infrastructure.
4. Updated independent binary16 unpack vectors and generator.
5. Any narrowly scoped test-only limit or OOM changes.
6. Exact build commands executed.
7. Exact test commands executed.
8. Results for:

   * normal build;
   * test build;
   * JSON-disabled build.
9. A concise list of modified files.
10. Confirmation that:

    * `<f2` and `>f2` unpacking became functional;
    * odd BLOB lengths are rejected;
    * endian reads use `pblobGetU16Le()` and `pblobGetU16Be()`;
    * non-finite raw words are rejected before conversion;
    * `fp16_ieee_to_fp32_value()` is used;
    * portable FP16 mode remains forced;
    * decoded `float` values are promoted exactly to `double`;
    * output uses `JsonString`;
    * output receives `JSON_SUBTYPE`;
    * signed zero and subnormals are preserved;
    * exhaustive binary16 tests pass;
    * all supported format directions are now functional;
    * no public API or header was added.

---

### Acceptance Criteria

Stage 11 is complete only when:

* `pblob_unpack(...,'<f2')` correctly reads little-endian binary16 values;
* `pblob_unpack(...,'>f2')` correctly reads big-endian binary16 values;
* zero-length BLOBs return `[]`;
* odd BLOB lengths are rejected;
* every finite binary16 raw word is accepted;
* positive and negative zero are preserved;
* every positive and negative subnormal is preserved;
* minimum normals and maximum finite values are accepted;
* all two infinity patterns are rejected;
* all 2,046 NaN patterns are rejected;
* the first invalid zero-based element index is reported;
* conversion uses `fp16_ieee_to_fp32_value()` followed by exact promotion to `double`;
* portable FP16 conversion remains forced;
* output is compact valid JSON TEXT with `JSON_SUBTYPE`;
* every finite binary16 word survives unpack/pack with identical bits;
* cross-endian conversion produces exact byte-swapped words;
* exhaustive classification totals are correct;
* the independent binary16 conversion oracle passes;
* large outputs respect SQLite length limits;
* OOM paths release all output state;
* prepared-statement reuse is correct;
* all Stage 2–10 tests remain passing;
* no supported format retains placeholder behavior;
* normal build succeeds;
* test build succeeds;
* JSON-disabled build succeeds;
* no new warnings appear;
* no public C API or header exists.

Stop after satisfying these criteria. Do not proceed to Stage 12.

---
---

## 📗 Stage 12: Validation, Error, Limit, and Cleanup Audit

Implement only Stage 12 of the packed numeric BLOB extension.

This stage begins from the completed Stage 11 state, where all supported format directions are functional:

```text
pblob_pack(..., 'int8')
pblob_unpack(..., 'int8')

pblob_pack(..., '<f2')
pblob_unpack(..., '<f2')

pblob_pack(..., '>f2')
pblob_unpack(..., '>f2')

pblob_pack(..., '<f4')
pblob_unpack(..., '<f4')

pblob_pack(..., '>f4')
pblob_unpack(..., '>f4')
```

The implementation already includes:

* strict SQL argument handling;
* exact format parsing;
* SQLite JSON parsing and JSONB traversal;
* integer and numeric extraction helpers;
* explicit endian helpers;
* binary16 and binary32 finite-value handling;
* exact packed-output allocation;
* compact JSON output through `JsonString`;
* JSON result subtype assignment;
* focused functional, limit, OOM, and prepared-statement tests.

Stage 12 is an audit and hardening stage.

Do not add new formats, APIs, or ordinary conversion features.

### Objective

Perform a complete correctness and robustness audit of `pblob.c` against the design contract.

This stage must:

* verify and normalize validation order;
* verify every public error path;
* verify every allocation and ownership transition;
* verify integer and size conversions;
* verify malformed internal JSONB defenses;
* verify SQLite length-limit enforcement;
* verify empty-result handling;
* verify non-finite handling;
* verify signed-zero behavior;
* remove temporary placeholder code and obsolete scaffolding;
* normalize extension-defined errors;
* eliminate duplicated or unreachable logic;
* add targeted regression tests for every defect or ambiguity found;
* preserve all established public semantics.

The stage is complete only when the implementation has been audited as a whole rather than merely passing representative conversion tests.

### Scope

This stage is limited to:

1. Auditing public callback control flow.
2. Auditing helper contracts and return conventions.
3. Auditing memory ownership and cleanup.
4. Auditing integer arithmetic and length handling.
5. Auditing JSONB traversal boundaries.
6. Auditing empty arrays and empty BLOBs.
7. Auditing non-finite values and signed zero.
8. Normalizing extension-defined error messages.
9. Removing dead, temporary, or duplicated code.
10. Adding targeted tests for audit findings.
11. Running strict-warning, sanitizer, and regression builds.
12. Preserving all existing supported behavior.

Do not add test-only exhaustive infrastructure beyond what is needed to verify audit findings. The broader final test-suite organization belongs to later stages.

---

### Public Contract Audit

Verify the final public SQL contract is exactly:

```sql
pblob_pack(json_array, format) -> BLOB
pblob_unpack(blob, format) -> JSON text
```

Supported formats must remain exactly:

```text
int8
<f2
>f2
<f4
>f4
```

Confirm there are no accepted aliases, including:

```text
INT8
i8
s8
f2
f4
<f16
>f16
<f32
>f32
native
=f2
=f4
```

Confirm matching remains:

* case-sensitive;
* byte-length-sensitive;
* whitespace-sensitive;
* embedded-NUL-safe.

Do not broaden the accepted public syntax.

---

### Registration Audit

Verify both functions are registered exactly once with:

```text
name: pblob_pack
arity: 2

name: pblob_unpack
arity: 2
```

Required flags:

```c
SQLITE_UTF8
| SQLITE_DETERMINISTIC
| SQLITE_INNOCUOUS
| SQLITE_RESULT_SUBTYPE
```

Verify:

* no variable-arity overload exists;
* no aliases exist;
* `SQLITE_DIRECTONLY` is not present;
* no aggregate or window callbacks are registered;
* no duplicate registration occurs through multiple initialization paths;
* registration failure propagates correctly;
* the functions remain unavailable under `SQLITE_OMIT_JSON`.

Do not alter flags unless the audit proves the implementation does not match the design.

---

### Callback Validation Order

Audit both callbacks for exact validation order.

For `pblob_pack()`:

```text
SQL NULL propagation
-> first argument storage class
-> format storage class
-> exact format parsing
-> JSON parsing
-> root-array validation
-> element-count and output-size validation
-> element traversal
-> element type validation
-> numeric extraction
-> target-format validation
-> result construction
```

For `pblob_unpack()`:

```text
SQL NULL propagation
-> first argument storage class
-> format storage class
-> exact format parsing
-> BLOB length divisibility where applicable
-> element decoding
-> raw-value classification
-> conversion
-> JSON result construction
```

Confirm no callback:

* retrieves text or BLOB data before NULL propagation;
* parses JSON before format validation;
* initializes output state before a cheap validation that can fail;
* emits a later-stage error instead of the required earlier-stage error;
* performs element work before validating packed length.

Add explicit precedence tests where coverage is incomplete.

---

### SQL NULL Audit

Verify the contract:

> If either argument is SQL NULL, return SQL NULL immediately without validating the other argument.

Test all combinations for both functions:

```sql
pblob_pack(NULL, 'int8')
pblob_pack('[]', NULL)
pblob_pack(NULL, NULL)
pblob_pack(NULL, 123)
pblob_pack(123, NULL)

pblob_unpack(NULL, 'int8')
pblob_unpack(x'', NULL)
pblob_unpack(NULL, NULL)
pblob_unpack(NULL, 123)
pblob_unpack(123, NULL)
```

Every case containing at least one SQL NULL must return SQL NULL.

Do not allow a type, format, JSON, length, or conversion error to take precedence over NULL propagation.

---

### Storage-Class Audit

Confirm `pblob_pack()` accepts only:

```text
argv[0] == SQLITE_TEXT
argv[1] == SQLITE_TEXT
```

Confirm it rejects caller-supplied JSONB BLOB input even when valid.

Confirm `pblob_unpack()` accepts only:

```text
argv[0] == SQLITE_BLOB
argv[1] == SQLITE_TEXT
```

Do not coerce:

* INTEGER;
* FLOAT;
* TEXT to BLOB;
* BLOB to TEXT;
* JSONB to TEXT;
* numeric values to format names.

Audit that storage-class checks use `sqlite3_value_type()` before retrieving converted representations.

---

### Format Descriptor Audit

Verify every successful `pblobParseFormat()` call initializes all fields:

```text
int8:
  eKind  = PBLOB_INT8
  eOrder = PBLOB_ORDER_NONE
  nByte  = 1

<f2:
  eKind  = PBLOB_F16
  eOrder = PBLOB_ORDER_LE
  nByte  = 2

>f2:
  eKind  = PBLOB_F16
  eOrder = PBLOB_ORDER_BE
  nByte  = 2

<f4:
  eKind  = PBLOB_F32
  eOrder = PBLOB_ORDER_LE
  nByte  = 4

>f4:
  eKind  = PBLOB_F32
  eOrder = PBLOB_ORDER_BE
  nByte  = 4
```

Add defensive checks for impossible internal combinations only where they improve correctness.

Do not duplicate raw format-string comparisons in conversion branches.

---

### JSON Parsing Audit

Verify `pblob_pack()` uses:

```c
jsonParseFuncArg(ctx, argv[0], 0)
```

and no independent JSON parser.

Confirm:

* malformed JSON errors remain those produced by SQLite JSON internals;
* SQLite-supported JSON5 syntax follows `json.c`;
* caller JSONB remains rejected at the SQL storage-class layer;
* parse objects are released with `jsonParseFree()`;
* no parse pointer is used after release;
* no parse object leaks on root-type, size, element, range, or OOM errors.

Do not replace core JSON syntax errors with extension-defined syntax messages.

---

### Root JSONB Audit

Verify pack operations require the root node at offset zero to be:

```c
JSONB_ARRAY
```

Audit root-node boundary checks:

```text
pParse is non-NULL
pParse->aBlob is non-NULL
pParse->nBlob is nonzero for nonempty internal representation
jsonbPayloadSize() succeeds
root header and payload fit in nBlob
root node occupies the complete internal representation
```

Confirm valid non-array roots are rejected before element traversal.

Required rejected roots:

```json
null
true
false
0
1.0
"abc"
{}
```

---

### Array Count and Traversal Audit

Verify array element count uses:

```c
jsonbArrayCount()
```

Audit sequential traversal for all pack formats.

For each element require:

```text
current offset is before payload end
jsonbPayloadSize() returns a valid header
header + payload arithmetic does not overflow
node end does not exceed array payload end
node type is validated before extraction
element count and traversal count agree
final offset equals payload end
```

Use integer types appropriate to `JsonParse` fields.

Do not perform unchecked expressions such as:

```c
iNode + nHeader + nPayload
```

when overflow could invalidate the comparison.

Prefer subtraction-based bounds checks or widened arithmetic.

---

### Numeric Extraction Audit

Verify `pblobJsonbInteger()`:

* accepts only `JSONB_INT` and `JSONB_INT5`;
* returns exact signed `sqlite3_int64`;
* handles `SMALLEST_INT64`;
* rejects signed 64-bit overflow;
* rejects positive hexadecimal high-bit values as signed integers;
* uses `sqlite3DecOrHexToI64()`;
* frees every duplicated payload.

Verify `pblobJsonbNumber()`:

* accepts all four numeric node types;
* uses `sqlite3AtoF()` for applicable decimal forms;
* adapts SQLite JSON5 hexadecimal semantics;
* treats positive high-bit hexadecimal values as positive numeric values;
* returns `double`;
* does not perform target-format range checks;
* frees every duplicated payload.

Audit all casts from payload size to `int`.

Add a defensive failure if a payload length cannot be passed safely to an internal API requiring `int`.

---

### `int8` Packing Audit

Verify `int8` packing:

* accepts only integer JSONB nodes;
* rejects mathematically integral floating nodes such as `1.0` and `1e0`;
* requires `-128..127`;
* does not clamp;
* does not wrap;
* does not convert through `double`;
* encodes one exact byte per element;
* reports the first invalid zero-based element index;
* returns a zero-length BLOB for `[]`.

Required mapping:

```text
-128 -> 80
-1   -> FF
0    -> 00
1    -> 01
127  -> 7F
```

Verify no implementation-defined signed narrowing is used.

---

### `int8` Unpacking Audit

Verify every input byte is accepted.

Audit decoding:

```text
00..7F -> 0..127
80..FF -> -128..-1
```

Confirm:

* no `char` signedness dependency;
* no BLOB length restriction;
* zero-length BLOB returns `[]`;
* output values use JSON integer syntax;
* arbitrary BLOBs round-trip exactly through unpack then pack.

---

### Binary32 Packing Audit

Verify binary32 packing follows exactly:

```text
JSON numeric
-> double
-> float
-> fp32_to_bits()
-> explicit endian output
```

Audit:

* source `double` non-finite rejection;
* binary32 result non-finite rejection;
* acceptance of subnormal and zero underflow;
* signed-zero preservation;
* exact four-byte allocation per element;
* no direct decimal-to-binary32 parser;
* no host-endian stores;
* no unaligned integer stores.

Confirm no infinity or NaN bits are emitted.

---

### Binary32 Unpacking Audit

Verify binary32 unpacking follows exactly:

```text
raw bits
-> non-finite classification
-> fp32_from_bits()
-> exact float-to-double promotion
-> SQLite JSON formatting
```

Audit:

* BLOB length divisible by four;
* non-finite classification before conversion;
* all finite subnormals accepted;
* both signed zeros preserved;
* maximum finite values accepted;
* no infinity or NaN converted to JSON;
* first invalid element index reported;
* pack-after-unpack reproduces original finite bits.

---

### Binary16 Packing Audit

Verify binary16 packing follows exactly:

```text
JSON numeric
-> double
-> float
-> finite binary32 intermediate
-> fp16_ieee_from_fp32_value()
-> finite binary16 result
-> explicit endian output
```

Audit:

* `FP16_USE_NATIVE_CONVERSION == 0`;
* no native half type or intrinsic;
* no direct binary64-to-binary16 conversion;
* binary32 intermediate overflow rejection;
* binary16 overflow rejection;
* subnormal and zero underflow acceptance;
* signed-zero preservation;
* no infinity or NaN words emitted.

---

### Binary16 Unpacking Audit

Verify binary16 unpacking follows exactly:

```text
raw bits
-> binary16 non-finite classification
-> fp16_ieee_to_fp32_value()
-> exact float-to-double promotion
-> SQLite JSON formatting
```

Audit:

* odd BLOB lengths rejected before decoding;
* all finite words accepted;
* both infinity words rejected;
* all NaN words rejected;
* signed zero preserved;
* subnormals preserved;
* maximum finite values accepted;
* finite unpack/pack bit identity holds.

---

### Endian Helper Audit

Verify all endian helpers use explicit byte operations only.

Confirm there are no:

```c
uint16_t *
uint32_t *
```

casts over byte buffers.

Confirm:

* no host-endian assumptions;
* no unaligned integer loads or stores;
* all shifts operate on unsigned values;
* all masks are unsigned;
* endian behavior is identical on little-endian and big-endian hosts by construction.

Retain unaligned-buffer tests.

---

### Binary Classification Audit

Verify binary16 masks and predicates:

```text
exponent mask: 0x7C00
fraction mask: 0x03FF
```

Verify binary32 masks and predicates:

```text
exponent mask: 0x7F800000
fraction mask: 0x007FFFFF
```

For both formats confirm predicates are mutually consistent:

```text
finite XOR infinity XOR NaN
```

for every raw bit pattern.

Retain exhaustive binary16 classification totals.

---

### Packed-Size Audit

Audit `pblobCheckedSize()`.

It must:

* accept widths 1, 2, and 4 only;
* reject invalid widths defensively;
* detect multiplication overflow before multiplication;
* enforce the current connection’s `SQLITE_LIMIT_LENGTH`;
* avoid truncation through `int`;
* return exact `sqlite3_uint64` size;
* allocate nothing;
* set an SQL error on failure.

Verify output allocation APIs accept the validated size.

Audit all conversions between:

```text
u32
int
sqlite3_int64
sqlite3_uint64
size_t
```

Do not assume the compiler will warn about every narrowing conversion.

---

### BLOB Retrieval Audit

Verify unpack callbacks:

* retrieve BLOB bytes only after type and format validation;
* accept NULL pointer only when byte count is zero;
* never read beyond `sqlite3_value_bytes()` length;
* do not retain the pointer after the callback returns;
* do not copy the input unnecessarily;
* validate divisibility before reading wider elements.

Audit loop bounds so the final element read cannot overflow the byte offset.

---

### Empty-Input Audit

Verify all empty cases explicitly:

```sql
pblob_pack('[]', 'int8')
pblob_pack('[]', '<f2')
pblob_pack('[]', '>f2')
pblob_pack('[]', '<f4')
pblob_pack('[]', '>f4')
```

Each must return:

```text
storage class: BLOB
length: 0
hex: empty
```

Verify:

```sql
pblob_unpack(x'', 'int8')
pblob_unpack(x'', '<f2')
pblob_unpack(x'', '>f2')
pblob_unpack(x'', '<f4')
pblob_unpack(x'', '>f4')
```

Each must return:

```text
[]
```

with:

```text
storage class: TEXT
JSON subtype
```

Audit zero-size allocation paths so a NULL pointer returned for a zero-byte allocation is never treated as OOM.

---

### Result BLOB Ownership Audit

For every successful nonempty pack result, verify ownership transfer occurs exactly once through an API equivalent to:

```c
sqlite3_result_blob64(ctx, pOut, nOut, sqlite3_free);
```

Audit:

* `pOut` is freed on every pre-transfer error;
* `pOut` is not freed after ownership transfer;
* a partial buffer is never returned;
* no allocator family mismatch exists;
* zero-length BLOB handling does not create a dangling pointer.

Prefer a single cleanup block where it simplifies proof of ownership.

---

### `JsonString` Ownership Audit

For every unpack path, verify:

* `jsonStringInit()` is called once;
* append errors are propagated;
* `jsonReturnString()` transfers or finalizes ownership correctly;
* `jsonStringReset()` is used on early failure where required;
* the internal buffer is never freed manually through the wrong allocator;
* subtype is assigned only after successful result construction;
* no partial JSON result survives an OOM or length-limit failure.

Audit all return paths after `JsonString` initialization.

---

### JSON Subtype Audit

Verify every successful `pblob_unpack()` result receives:

```c
JSON_SUBTYPE
```

Confirm direct composition works for all formats:

```sql
json_array(pblob_unpack(...))
json_object('values', pblob_unpack(...))
json_type(pblob_unpack(...))
json_array_length(pblob_unpack(...))
```

The unpacked array must not become a quoted JSON string.

Do not require subtype persistence after storing the value in a table.

---

### Floating JSON Formatting Audit

Verify floating unpack output uses SQLite’s JSON-aware formatter consistently for both binary16 and binary32.

Audit:

* locale independence;
* valid JSON syntax;
* signed-zero preservation;
* sufficient precision for repacking;
* no custom special-case integer formatting;
* no hexadecimal float output;
* no direct `printf()` family usage outside SQLite’s JSON formatter.

The required invariant is bit identity after unpack and repack for every tested finite value.

---

### Non-Finite Error Audit

Normalize public behavior so:

* pack rejects non-finite extracted source values;
* binary32 pack rejects non-finite target words;
* binary16 pack rejects non-finite binary32 intermediates and binary16 results;
* binary32 unpack rejects infinity and NaN raw words;
* binary16 unpack rejects infinity and NaN raw words.

Do not:

* map non-finite values to JSON null;
* emit non-standard JSON;
* clamp infinity to maximum finite;
* silently ignore NaN payloads.

Ensure the first invalid zero-based element index is present in public errors.

---

### Error Message Normalization

Review every extension-defined error.

Messages must be:

* stable;
* concise;
* function-specific;
* grammatically consistent;
* zero-based where an element index is reported;
* independent of locale;
* safe for format values containing embedded NUL bytes.

Recommended message families:

```text
pblob_pack: first argument must be JSON text
pblob_unpack: first argument must be a BLOB

pblob_pack: format must be text
pblob_unpack: format must be text

pblob_pack: unsupported format
pblob_unpack: unsupported format

pblob_pack: expected a JSON array

pblob_pack: element N must be an integer for format int8
pblob_pack: element N must be numeric for format <f2
pblob_pack: element N must be numeric for format >f2
pblob_pack: element N must be numeric for format <f4
pblob_pack: element N must be numeric for format >f4

pblob_pack: element N is outside the int8 range
pblob_pack: element N is not finite
pblob_pack: element N is outside the finite float16 range
pblob_pack: element N is outside the finite float32 range

pblob_unpack: BLOB length is not divisible by 2 for format <f2
pblob_unpack: BLOB length is not divisible by 2 for format >f2
pblob_unpack: BLOB length is not divisible by 4 for format <f4
pblob_unpack: BLOB length is not divisible by 4 for format >f4

pblob_unpack: element N is not a finite float16 value
pblob_unpack: element N is not a finite float32 value

pblob_pack: malformed internal JSON representation
```

Equivalent wording is acceptable, but the implementation must use one consistent scheme.

Do not include arbitrary raw format bytes in an error unless length-safe escaping is implemented.

---

### Internal Error Audit

Differentiate public input errors from impossible internal-state errors.

Internal errors include:

* inconsistent `PblobFormat`;
* traversal count disagreement;
* malformed JSONB after successful internal parsing;
* finite binary16 converting to non-finite binary32;
* impossible helper width.

Use a stable internal-error path.

Do not use `assert()` as the only protection for malformed data or integer bounds that can affect release builds.

Assertions may supplement, but not replace, runtime checks where safety depends on them.

---

### OOM Audit

Enumerate every allocation site in `pblob.c`.

At minimum include:

* JSON parsing and conversion allocations;
* numeric payload duplication;
* packed-output allocation;
* `JsonString` growth;
* final result transfer where applicable.

For each allocation site verify:

```text
failure sets an OOM result
all previously owned resources are released
no partial result is returned
no subtype is assigned after failure
subsequent calls remain functional
```

Add missing fault-injection tests for any untested allocation site.

Do not collapse OOM into a generic conversion error.

---

### SQLite Length-Limit Audit

Verify the current connection’s:

```text
SQLITE_LIMIT_LENGTH
```

is enforced for:

* packed BLOB results;
* unpacked JSON text results.

For pack:

* size must be rejected before output allocation where possible.

For unpack:

* `JsonString` must surface the SQLite length-limit failure cleanly.

Test:

```text
below limit
at limit where deterministically representable
above limit
```

Restore the prior limit after every test, including test failures.

Do not use a hard-coded global maximum as a substitute.

---

### Prepared-Statement and Cache Audit

Retain and expand prepared-statement reuse tests.

For both functions, alternate among:

* empty values;
* small valid values;
* large valid values;
* malformed JSON;
* invalid format;
* wrong type;
* invalid BLOB length;
* non-finite raw values;
* valid calls after errors.

Verify:

* no stale parse state;
* no stale output buffer;
* no stale subtype;
* no stale element index;
* no result from a prior execution;
* statement reuse remains correct after OOM and limit errors where supported.

---

### Dead-Code Removal

Remove:

* all temporary “not implemented” messages;
* all unreachable placeholder branches;
* obsolete `UNUSED_PARAMETER()` calls;
* duplicate validation code superseded by shared helpers;
* temporary Stage 4 or Stage 5 debug paths no longer used;
* unused constants;
* unused helper declarations;
* comments describing future implementation that is now complete.

Do not remove test-only infrastructure still required by existing tests.

Do not perform unrelated stylistic refactoring.

---

### Helper Contract Review

Every private helper should have a concise and accurate contract.

Review:

* inputs;
* accepted value ranges;
* ownership;
* return convention;
* whether an SQL error is set on failure;
* whether outputs are initialized on success;
* whether outputs are undefined on failure.

Normalize helpers so they do not mix incompatible conventions such as:

```text
0 means failure in one helper
0 means success in another helper
```

unless the distinction is strongly justified and documented.

Prefer:

```text
0 = success
nonzero = error already reported
```

for SQL-context helpers.

Do not add verbose comments that merely restate code.

---

### Compiler-Warning Audit

Build with the strictest practical warning set supported by the project compiler.

Audit at least:

```text
implicit narrowing
signed/unsigned comparison
unused static functions
unreachable code
missing return
incorrect format specifier
pointer type mismatch
shift width
constant overflow
uninitialized variable
```

On MSVC, enable the project’s practical high warning level without introducing unrelated source-tree failures.

On Clang or GCC, use an equivalent strict build where available.

Do not suppress a warning globally to hide a `pblob.c` defect.

Any local suppression must be narrowly scoped and justified.

---

### Undefined-Behavior Audit

Review for:

* signed overflow;
* oversized shifts;
* shifting negative values;
* unaligned access;
* strict-aliasing violations;
* out-of-bounds pointer arithmetic;
* invalid pointer use after result transfer;
* use-after-free;
* double-free;
* narrowing before range validation;
* implementation-defined signed-byte conversion.

Run UBSan where supported.

Do not assume passing ordinary tests proves absence of undefined behavior.

---

### Address-Safety Audit

Run ASan or an equivalent memory-safety configuration where supported.

Exercise:

* empty values;
* maximum tested arrays;
* malformed JSON;
* malformed internal JSONB test hooks;
* invalid BLOB lengths;
* invalid non-finite words;
* OOM paths where compatible;
* repeated prepared-statement execution.

No leak, over-read, overwrite, use-after-free, or double-free is acceptable.

---

### Malformed Internal JSONB Tests

Retain test-only malformed-node coverage.

At minimum verify safe failure for:

* offset beyond `nBlob`;
* truncated root header;
* truncated child header;
* payload length crossing root end;
* zero-length numeric payload;
* element-count disagreement;
* malformed decimal numeric payload;
* malformed JSON5 hexadecimal payload;
* sign-only payload;
* reserved or unsupported node type.

These tests must never expose caller JSONB as a supported `pblob_pack()` input.

---

### Regression Matrix

Run representative successful cases for all directions:

```text
pack int8
unpack int8
pack <f2
unpack <f2
pack >f2
unpack >f2
pack <f4
unpack <f4
pack >f4
unpack >f4
```

For each format verify:

* empty case;
* one element;
* multiple elements;
* boundary values;
* cross-endian consistency where applicable;
* pack/unpack identity;
* type and format errors;
* length errors where applicable;
* limit behavior;
* prepared-statement reuse.

No supported direction may contain placeholder behavior.

---

### Required Audit Tests

Add or retain explicit tests for:

```text
NULL precedence
type-error precedence
format-error precedence
JSON-error precedence
root-type precedence
element-type precedence
range precedence
length-error precedence
first invalid element index
empty pack results
empty unpack results
JSON subtype
signed zero
subnormal preservation
maximum finite values
non-finite rejection
exact packed size
length-limit enforcement
OOM cleanup
prepared-statement recovery
```

Every defect found during audit must receive a regression test before it is fixed or in the same patch.

---

### Build Verification

Perform all required configurations.

#### Normal Build

Build the normal amalgamation and release targets.

Verify:

* all supported SQL functions work;
* no placeholder code remains;
* no test-only interface is present;
* no new warnings appear;
* exact smoke vectors pass.

#### Test Build

Build `testfixture` or the project equivalent with:

```text
SQLITE_TEST
SQLITE_DEBUG
FP16_USE_NATIVE_CONVERSION=0
```

Run:

* all focused `pblob` tests;
* exhaustive binary16 tests;
* malformed internal tests;
* limit tests;
* OOM tests;
* prepared-statement tests;
* all prior-stage tests.

#### Strict-Warning Build

Build with the project’s strict practical warning configuration.

Treat every new `pblob.c` warning as a failure.

#### Sanitizer Build

Run focused tests under:

```text
ASan
UBSan
```

or the closest supported equivalent.

Document unavailable sanitizer configurations rather than claiming they passed.

#### JSON-Disabled Build

Build with:

```text
SQLITE_OMIT_JSON
```

Verify:

* build and link succeed;
* no `pblob` functions are registered;
* no JSON, FP16, or test-only references remain unresolved;
* no warnings appear.

---

### Prohibited Work

Do not:

* add new formats;
* add new production SQL functions;
* add optional arguments;
* add format aliases;
* add headers or metadata to packed BLOBs;
* add automatic endian detection;
* accept JSONB input for `pblob_pack()`;
* return JSONB from `pblob_unpack()`;
* change the binary16 conversion path;
* enable native FP16 conversion;
* add another numeric parser;
* add another JSON writer;
* add another FP16 implementation;
* expose a public C API;
* add `pblob.h`;
* modify `json.c`;
* modify the vendored FP16 implementation;
* refactor unrelated SQLite code.

Do not proceed to test-suite reorganization or release documentation beyond what is required to complete this audit.

---

### Expected Deliverables

Provide:

1. Updated `pblob.c`.
2. Updated focused tests covering every audit finding.
3. Any narrowly scoped test-only helper corrections.
4. A written audit checklist showing each reviewed area and result.
5. Exact build commands executed.
6. Exact test commands executed.
7. Results for:

   * normal build;
   * test build;
   * strict-warning build;
   * sanitizer build;
   * JSON-disabled build.
8. A concise list of modified files.
9. A concise list of defects found and fixed.
10. Confirmation that:

    * all supported directions remain functional;
    * validation order is consistent;
    * every allocation has a proven cleanup path;
    * all size conversions are checked;
    * malformed internal JSONB fails safely;
    * empty results use the correct storage classes;
    * JSON subtype is assigned only on successful unpack;
    * non-finite values are consistently rejected;
    * signed zero is preserved;
    * no placeholder or dead implementation code remains;
    * no public API or header was added.

---

### Acceptance Criteria

Stage 12 is complete only when:

* every public validation path follows the specified precedence;
* NULL propagation always occurs before other validation;
* storage-class checks perform no coercion;
* only the five exact format strings are accepted;
* JSON parsing and traversal use SQLite internals safely;
* all traversal arithmetic is bounds-checked;
* all numeric payload length conversions are checked;
* every allocation and ownership transfer has a correct cleanup path;
* packed-size multiplication cannot overflow;
* current SQLite length limits are enforced;
* empty pack results are zero-length BLOBs;
* empty unpack results are JSON-subtyped `[]` TEXT;
* all `int8`, binary16, and binary32 semantics remain correct;
* all non-finite values are rejected consistently;
* signed zero survives all relevant round trips;
* all finite binary16 and tested binary32 values retain bit identity;
* every public element error identifies the first zero-based invalid index;
* OOM tests pass without leaks or stale results;
* malformed internal JSONB tests fail safely;
* prepared statements recover correctly after every tested error class;
* no temporary placeholder or dead code remains;
* strict-warning build is clean;
* sanitizer runs report no defects;
* all prior-stage tests remain passing;
* normal build succeeds;
* test build succeeds;
* JSON-disabled build succeeds;
* no public C API or header exists.

Stop after satisfying these criteria. Do not proceed to Stage 13.

---
---

## 📗 Stage 13: Consolidate Test-Only Low-Level Hooks

Implement only Stage 13 of the packed numeric BLOB extension.

This stage begins from the completed Stage 12 state, where:

* `pblob.c` is the only production source module for the extension;
* all supported packing and unpacking formats are functional;
* validation, cleanup, limits, and ownership have been audited;
* focused SQL tests exist;
* test-only access added in earlier stages may be incomplete, temporary, fragmented, or narrowly tailored;
* no public C API or public header exists.

Stage 13 must create a deliberate, consolidated test-only interface for low-level and exhaustive testing.

Do not change public SQL behavior.

### Objective

Add a coherent test-only command interface that exposes selected private `pblob.c` operations to SQLite’s Tcl test harness.

The interface must support:

* direct endian-helper testing;
* raw binary16 and binary32 classification;
* complete signed-byte decoding;
* checked-size testing;
* direct JSONB numeric extraction testing;
* malformed internal JSONB testing;
* exhaustive binary16 conversion and round-trip testing;
* verification that portable FP16 conversion is active.

The test interface must:

* exist only when `SQLITE_TEST` is defined;
* remain implemented in `pblob.c`;
* call the actual private production helpers;
* expose no production SQL functions;
* expose no application-facing C API;
* require no `pblob.h`;
* add no second production or test C module.

### Scope

This stage is limited to:

1. Reviewing all existing temporary test hooks.
2. Removing obsolete or duplicated hooks.
3. Defining one coherent Tcl-command interface.
4. Registering that interface in `testfixture`.
5. Implementing low-level command operations.
6. Implementing exhaustive binary16 test operations.
7. Adding Tcl tests for the consolidated interface.
8. Verifying that release builds contain none of the test-only interface.
9. Preserving all public SQL behavior and tests.

Do not redesign the production implementation.

---

### Single-Module Requirement

Keep all test-only `pblob` C code in:

```text
pblob.c
```

under:

```c
#ifdef SQLITE_TEST
...
#endif
```

Do not create:

```text
src/test_pblob.c
pblob_test.c
pblob_test.h
pblob.h
```

This requirement preserves the extension’s single-C-module structure and allows test-only code to call private `static` helpers directly.

The production helpers must remain `static`.

Do not remove `static` from a helper merely to enable testing.

---

### Test Command Design

Register one Tcl command:

```text
test_pblob
```

Preferred command form:

```text
test_pblob OPERATION ?ARGUMENT ...?
```

Use operation selectors rather than registering many independent commands.

Required operations:

```text
u16le
u16be
u32le
u32be
classify-f16
classify-f32
decode-int8
checked-size
jsonb-integer
jsonb-number
malformed-jsonb
fp16-mode
exhaustive-f16-classify
exhaustive-f16-convert
exhaustive-f16-roundtrip
```

Equivalent concise names are acceptable, but one stable command namespace is required.

Do not register these as SQL functions.

Do not expose them in normal `sqlite3.exe` or `sqlite3.dll` builds.

---

### Testfixture Registration

Follow the selected SQLite source tree’s established Tcl-command registration convention.

The Stage 13 implementation must ensure:

```text
test_pblob
```

is registered only in the `SQLITE_TEST` testfixture build.

Use the existing test initialization mechanism rather than inventing a second Tcl interpreter or registration framework.

Possible integration forms include:

* a test initialization function called from the existing testfixture setup;
* an entry in an existing test command table;
* a local registration hook included through the amalgamated test source.

Use the actual project convention.

The registration routine itself must also remain unavailable in production builds.

---

### Command Error Handling

Every operation must validate:

* argument count;
* integer syntax;
* numeric range;
* hexadecimal word width;
* malformed Tcl objects;
* invalid operation names.

Use Tcl result and error conventions established by the SQLite test suite.

Do not:

* call `abort()`;
* call `exit()`;
* rely only on assertions;
* print directly to standard output;
* return ambiguous empty results for invalid input.

On error, return `TCL_ERROR` with a concise diagnostic.

---

### Hexadecimal Input Convention

For bit-pattern operations, accept canonical hexadecimal text without prefixes:

```text
0000
3C00
FFFF

00000000
3F800000
FFFFFFFF
```

Requirements:

* binary16 input must contain exactly four hexadecimal digits;
* binary32 input must contain exactly eight hexadecimal digits;
* parsing must be case-insensitive;
* invalid characters must be rejected;
* leading or trailing whitespace must be rejected unless Tcl argument parsing already removes it structurally;
* values must not be parsed through floating-point conversions.

Do not silently accept short forms such as:

```text
1
3c
3f8000
```

unless an operation explicitly documents integer input instead of fixed-width bit-pattern input.

---

### `u16le` Operation

Command form:

```text
test_pblob u16le WORD
```

Input:

```text
WORD = exactly four hexadecimal digits
```

Return a Tcl list containing:

```text
little-endian hex bytes
round-tripped word
```

Example:

```text
test_pblob u16le 1234
```

Expected:

```text
3412 1234
```

The operation must call:

```c
pblobPutU16Le()
pblobGetU16Le()
```

It must use an intentionally unaligned internal buffer offset.

Do not duplicate endian logic in the test command.

---

### `u16be` Operation

Command form:

```text
test_pblob u16be WORD
```

Example:

```text
test_pblob u16be 1234
```

Expected:

```text
1234 1234
```

Call:

```c
pblobPutU16Be()
pblobGetU16Be()
```

Use an unaligned internal buffer offset.

---

### `u32le` Operation

Command form:

```text
test_pblob u32le WORD
```

Input:

```text
WORD = exactly eight hexadecimal digits
```

Example:

```text
test_pblob u32le 12345678
```

Expected:

```text
78563412 12345678
```

Call:

```c
pblobPutU32Le()
pblobGetU32Le()
```

Use an intentionally unaligned internal buffer.

---

### `u32be` Operation

Command form:

```text
test_pblob u32be WORD
```

Example:

```text
test_pblob u32be 12345678
```

Expected:

```text
12345678 12345678
```

Call:

```c
pblobPutU32Be()
pblobGetU32Be()
```

---

### Classification Operations

Provide:

```text
test_pblob classify-f16 WORD
test_pblob classify-f32 WORD
```

Return a Tcl list:

```text
finite infinity nan
```

using integer booleans:

```text
0
1
```

Examples:

```text
test_pblob classify-f16 3C00
```

Expected:

```text
1 0 0
```

```text
test_pblob classify-f16 7C00
```

Expected:

```text
0 1 0
```

```text
test_pblob classify-f16 7E00
```

Expected:

```text
0 0 1
```

The operations must call the production predicates:

```c
pblobF16IsFinite()
pblobF16IsInf()
pblobF16IsNaN()

pblobF32IsFinite()
pblobF32IsInf()
pblobF32IsNaN()
```

Do not reproduce masks in the test-only command.

---

### `decode-int8` Operation

Command form:

```text
test_pblob decode-int8 BYTE
```

Accept an integer in:

```text
0..255
```

Return:

```text
-128..127
```

The operation must call:

```c
pblobDecodeInt8()
```

Do not accept values outside the byte domain.

Do not cast through `signed char` in the test command.

---

### `checked-size` Operation

Command form:

```text
test_pblob checked-size COUNT WIDTH
```

Required widths:

```text
1
2
4
```

The operation must call the production checked-size helper.

It must run against the active SQLite connection so that the current:

```text
SQLITE_LIMIT_LENGTH
```

is enforced.

Return the calculated byte count on success.

On failure, return the same error category produced by the production helper.

The command must support large `sqlite3_uint64` count inputs where Tcl integer support permits them.

Do not truncate through `int`.

Do not perform an independent multiplication before calling the helper except where necessary to validate Tcl conversion.

---

### `jsonb-integer` Operation

Command form:

```text
test_pblob jsonb-integer JSON ?INDEX?
```

Behavior:

* parse `JSON` through SQLite’s internal JSON parser;
* when `INDEX` is omitted, require the root itself to be a numeric node;
* when `INDEX` is supplied, require the root to be an array and select that zero-based element;
* call:

  ```c
  pblobJsonbInteger()
  ```
* return the extracted signed integer.

The wrapper may use a small test-only node-selection helper.

Do not add a production array-navigation abstraction solely for this command.

Do not parse integer text independently in the wrapper.

---

### `jsonb-number` Operation

Command form:

```text
test_pblob jsonb-number JSON ?INDEX?
```

Follow the same selection rules as `jsonb-integer`.

Call:

```c
pblobJsonbNumber()
```

Return the extracted SQLite numeric value in a Tcl representation capable of preserving:

* ordinary finite values;
* signed zero where Tcl permits observation;
* infinity where the extraction helper returns it.

Do not impose binary16 or binary32 target-format rules in this command.

---

### `malformed-jsonb` Operation

Provide a controlled test-only operation for malformed internal JSONB.

Preferred form:

```text
test_pblob malformed-jsonb CASE HELPER
```

Where `CASE` selects a predefined malformed representation and `HELPER` selects:

```text
integer
number
traverse
```

Required predefined cases:

```text
offset-past-end
truncated-root-header
truncated-child-header
payload-past-end
zero-length-integer
zero-length-float
sign-only
malformed-decimal
malformed-hex
reserved-type
count-mismatch
```

Construct malformed buffers in test-only C.

Do not accept arbitrary raw pointers or addresses from Tcl.

Do not expose a general memory mutation primitive.

The command must call the actual production helper or traversal path being tested.

Expected result: controlled error, never crash or out-of-bounds access.

---

### `fp16-mode` Operation

Command form:

```text
test_pblob fp16-mode
```

Return:

```text
portable
```

when:

```c
FP16_USE_NATIVE_CONVERSION == 0
```

The command must fail or return a distinct unexpected value if native conversion is enabled.

This is a direct build-configuration check.

Do not infer the mode from conversion results.

---

### Exhaustive Binary16 Classification

Command form:

```text
test_pblob exhaustive-f16-classify
```

Loop over all:

```text
0x0000 through 0xFFFF
```

using the production classification helpers.

Return a Tcl list or dictionary containing at least:

```text
finite
infinity
nan
positive-finite
negative-finite
positive-infinity
negative-infinity
positive-nan
negative-nan
overlap
unclassified
```

Required totals:

```text
finite              63488
infinity                 2
nan                    2046

positive-finite       31744
negative-finite       31744

positive-infinity         1
negative-infinity         1

positive-nan           1023
negative-nan           1023

overlap                   0
unclassified              0
```

Each raw word must belong to exactly one of:

```text
finite
infinity
NaN
```

The loop must run entirely in test-only C.

Do not issue 65,536 Tcl callbacks.

---

### Exhaustive Binary16 Conversion

Command form:

```text
test_pblob exhaustive-f16-convert
```

For every finite binary16 word:

1. Convert using:

   ```c
   fp16_ieee_to_fp32_value()
   ```
2. Obtain resulting binary32 bits using:

   ```c
   fp32_to_bits()
   ```
3. Verify the result is finite.
4. Compare against an independent test-only half-to-float oracle.
5. Count mismatches.
6. Compute a stable digest over:

   ```text
   input binary16 bits
   expected binary32 bits
   actual binary32 bits
   ```

Return at least:

```text
tested
mismatches
digest
```

Required:

```text
tested = 63488
mismatches = 0
```

The independent oracle must not call:

```c
fp16_ieee_to_fp32_value()
```

internally.

A concise test-only integer implementation of IEEE binary16-to-binary32 mapping is acceptable.

Do not add that oracle to production code.

---

### Independent Binary16 Oracle

Implement the test-only oracle using integer bit operations.

For finite binary16 values, derive the expected binary32 bit pattern from:

```text
sign
binary16 exponent
binary16 fraction
```

Handle:

* positive and negative zero;
* subnormal normalization;
* ordinary normals.

The oracle must not:

* use native half types;
* call vendored FP16 conversion functions;
* call production unpacking;
* convert through decimal text.

Keep the oracle under:

```c
#ifdef SQLITE_TEST
```

Document that it exists only as an independent test reference.

---

### Exhaustive Binary16 Round Trip

Command form:

```text
test_pblob exhaustive-f16-roundtrip
```

For every finite binary16 raw word:

1. Decode with:

   ```c
   fp16_ieee_to_fp32_value()
   ```
2. Promote to `double`.
3. Format using the same SQLite JSON floating formatter used by production unpacking.
4. Parse the resulting JSON through the same SQLite JSON parser used by production packing.
5. Extract the numeric value.
6. Narrow to binary32.
7. Convert with:

   ```c
   fp16_ieee_from_fp32_value()
   ```
8. Compare resulting raw bits with the original word.

Required:

```text
tested = 63488
mismatches = 0
```

Return at least:

```text
tested
mismatches
first-input
first-output
first-json
```

Use empty values for first-failure fields when no mismatch occurs.

The test must exercise the actual production formatting and parsing path as directly as practical.

Do not reduce this to a direct:

```text
half -> float -> half
```

test, because that would not cover JSON formatting and reparsing.

---

### Exhaustive Round-Trip Efficiency

The exhaustive round-trip test must run primarily in C.

Avoid:

* preparing one SQL statement per raw word;
* invoking Tcl once per raw word;
* constructing 63,488 independent database connections.

A single prepared SQLite expression or direct use of the internal JSON helpers may be reused where correct.

The command may periodically check for SQLite OOM or interrupt conditions if consistent with testfixture conventions.

---

### Stable Digest

Use a simple documented stable digest suitable for regression detection.

Acceptable choices include:

```text
FNV-1a 64-bit
SHA-256 through an existing in-tree implementation
```

Prefer a compact dependency-free test-only digest such as FNV-1a 64-bit.

Define byte order explicitly.

For example, feed each integer as big-endian bytes:

```text
binary16 input: 2 bytes
binary32 output: 4 bytes
```

Return lowercase fixed-width hexadecimal text.

Do not use implementation-defined in-memory struct bytes.

---

### Test-Only OOM Behavior

The consolidated hooks must not interfere with SQLite fault injection.

For operations that allocate:

* propagate OOM cleanly;
* release temporary parse and string state;
* return `TCL_ERROR`;
* leave the interpreter usable.

Do not add broad new OOM matrices in this stage; ensure the hooks themselves are safe under the existing fault tests.

---

### Tcl Test Module

Create or extend a focused module:

```text
test/pblob_lowlevel.test
```

This module must test the consolidated `test_pblob` command.

Keep public SQL behavior tests in:

```text
test/pblob.test
```

Do not move ordinary SQL tests unnecessarily.

Required low-level test groups:

```text
command registration
argument validation
u16 endian helpers
u32 endian helpers
unaligned access
binary16 classification
binary32 classification
full int8 byte domain
checked-size behavior
JSONB integer extraction
JSONB numeric extraction
malformed JSONB
portable FP16 mode
exhaustive binary16 classification
exhaustive binary16 conversion
exhaustive binary16 JSON round trip
```

Use standard SQLite Tcl test naming conventions.

---

### Remove Temporary Test Hooks

Review all earlier-stage test-only interfaces.

Remove:

* duplicate commands;
* temporary SQL debug functions;
* one-off operation names superseded by `test_pblob`;
* wrappers that reimplement production logic;
* obsolete test registration code;
* unused test helper declarations.

Update tests to use the consolidated interface.

Do not leave parallel low-level interfaces unless required by unrelated existing project code.

---

### Production Isolation

Verify normal builds contain none of:

```text
test_pblob
test-only oracle code
exhaustive loops
test-only digest code
malformed JSONB constructors
Tcl registration code
```

The production object must contain only normal extension implementation.

Use compile guards narrowly enough that test-only string literals and operation names are also excluded.

---

### Public SQL Regression Tests

Run the full public SQL suite after consolidating hooks.

Verify unchanged behavior for:

```text
pblob_pack(..., 'int8')
pblob_unpack(..., 'int8')
pblob_pack(..., '<f2')
pblob_unpack(..., '<f2')
pblob_pack(..., '>f2')
pblob_unpack(..., '>f2')
pblob_pack(..., '<f4')
pblob_unpack(..., '<f4')
pblob_pack(..., '>f4')
pblob_unpack(..., '>f4')
```

Test-only consolidation must not affect:

* validation order;
* error messages;
* packed bytes;
* JSON formatting;
* JSON subtype;
* length limits;
* OOM behavior;
* prepared-statement reuse.

---

### Build Verification

Perform all required configurations.

#### Normal Build

Build the normal amalgamation and release targets.

Verify:

* no Tcl dependency is introduced;
* no test-only command symbol is present;
* no test-only operation strings are present where practical to inspect;
* public SQL behavior is unchanged;
* no new warnings appear.

#### Test Build

Build `testfixture` with:

```text
SQLITE_TEST
SQLITE_DEBUG
FP16_USE_NATIVE_CONVERSION=0
```

Run:

```text
test/pblob.test
test/pblob_lowlevel.test
```

Run all prior focused `pblob` tests.

#### JSON-Disabled Test Build

Build with:

```text
SQLITE_TEST
SQLITE_OMIT_JSON
```

Verify:

* no production `pblob` functions are registered;
* `test_pblob` is either absent or returns a clearly controlled unavailable result according to the chosen compile-guard structure;
* no JSON or FP16 symbols remain unresolved;
* no warnings appear.

Preferred behavior: do not register `test_pblob` when `SQLITE_OMIT_JSON` is active.

#### Strict-Warning Build

Compile both normal and test configurations with the practical strict-warning profile.

Treat warnings in test-only code as failures.

#### Sanitizer Build

Run `pblob_lowlevel.test` and public `pblob` tests under ASan and UBSan where supported.

The malformed JSONB operations must fail cleanly without sanitizer findings.

---

### Prohibited Work

Do not:

* add new production SQL functions;
* change the public SQL API;
* change accepted formats;
* change packed representations;
* change conversion paths;
* change public error semantics except to fix a proven Stage 12 regression;
* create `src/test_pblob.c`;
* create `pblob_test.c`;
* create `pblob.h`;
* remove `static` from production helpers;
* expose production helpers through DLL exports;
* register low-level helpers as SQL functions;
* accept arbitrary raw addresses from Tcl;
* expose general memory read or write operations;
* modify `json.c`;
* modify the vendored FP16 implementation;
* refactor unrelated SQLite test infrastructure.

Do not proceed to full test-suite organization, vector-generation cleanup, or release integration beyond what this stage requires.

---

### Expected Deliverables

Provide:

1. Updated `pblob.c` containing the consolidated `SQLITE_TEST` interface.
2. Updated testfixture registration for `test_pblob`.
3. New or updated:

   ```text
   test/pblob_lowlevel.test
   ```
4. Updated prior tests that used temporary hooks.
5. Exact build commands executed.
6. Exact test commands executed.
7. Results for:

   * normal build;
   * test build;
   * JSON-disabled test build;
   * strict-warning build;
   * sanitizer build.
8. A concise list of modified files.
9. A concise list of removed temporary test hooks.
10. Confirmation that:

    * all test-only C code remains in `pblob.c`;
    * no `src/test_pblob.c` or other test C module was added;
    * production helpers remain `static`;
    * `test_pblob` is available only in test builds;
    * exhaustive binary16 classification passes;
    * independent binary16 conversion comparison passes;
    * exhaustive binary16 JSON round-trip passes;
    * malformed internal JSONB tests fail safely;
    * public SQL behavior remains unchanged;
    * no public C API or header was added.

---

### Acceptance Criteria

Stage 13 is complete only when:

* one consolidated `test_pblob` Tcl command replaces temporary low-level hooks;
* the command exists only under `SQLITE_TEST`;
* all test-only C implementation remains inside `pblob.c`;
* no additional C source module is created;
* all production helpers remain `static`;
* endian operations call the production endian helpers;
* classification operations call the production predicates;
* signed-byte testing covers all 256 byte values;
* checked-size testing exercises the active SQLite length limit;
* JSONB extraction operations call the production extraction helpers;
* malformed internal JSONB operations fail without memory-safety defects;
* `fp16-mode` confirms portable conversion;
* exhaustive binary16 classification reports:

  ```text
  63488 finite
  2 infinity
  2046 NaN
  ```
* every binary16 pattern belongs to exactly one classification;
* all 63,488 finite binary16 values match the independent conversion oracle;
* all 63,488 finite binary16 values survive the JSON unpack/pack round trip with identical bits;
* no production build contains the test command or test-only oracle;
* all public SQL tests remain passing;
* normal build succeeds;
* test build succeeds;
* JSON-disabled build succeeds;
* strict-warning build is clean;
* sanitizer runs report no defects;
* no public C API or header exists.

Stop after satisfying these criteria. Do not proceed to Stage 14.

---
---

## 📗 Stage 14: Complete SQL, Vector, Limit, and Fault Tests

Implement only Stage 14 of the packed numeric BLOB extension.

This stage begins from the completed Stage 13 state, where:

* `pblob.c` is the only production and test-specific C module for the extension;
* all five formats are functional in both directions;
* validation, bounds, ownership, errors, limits, and cleanup have been audited;
* a consolidated `test_pblob` Tcl command exists only under `SQLITE_TEST`;
* exhaustive binary16 classification, conversion, and JSON round-trip operations exist;
* focused public SQL and low-level tests exist;
* independent vector generation may still be incomplete, fragmented, or mixed into earlier tests;
* focused length-limit and OOM tests exist but have not yet been organized into their final modules.

Stage 14 must complete and organize the comprehensive test suite.

Do not change public SQL semantics unless a newly added test exposes a genuine defect. Every defect fixed in this stage must receive a regression test.

### Objective

Create the final focused test structure for the extension.

The completed suite must cover:

* public SQL contract;
* exact packed bytes;
* independent reference vectors;
* all supported endian variants;
* integer boundaries;
* binary16 and binary32 boundary values;
* signed zero;
* subnormals;
* rounding;
* overflow and underflow;
* non-finite rejection;
* malformed JSON;
* malformed internal JSONB;
* invalid packed lengths;
* SQLite length limits;
* OOM and fault injection;
* prepared-statement reuse;
* result subtype;
* expression and schema integration;
* large inputs;
* exhaustive binary16 behavior;
* deterministic repeated execution;
* release-build smoke behavior.

The suite must be divided by concern so failures are easy to identify.

### Scope

This stage is limited to:

1. Finalizing the public SQL test module.
2. Finalizing the low-level test module.
3. Adding committed independent reference vectors.
4. Adding a dedicated length-limit test module.
5. Adding a dedicated fault-injection test module.
6. Adding an aggregate runner.
7. Completing the independent vector generator.
8. Adding prepared-statement and schema-integration coverage.
9. Removing duplicated or obsolete tests.
10. Running every focused test module independently and together.
11. Preserving the single-C-module requirement.

Do not redesign `pblob.c`.

---

### Final Test Layout

Use this final focused structure:

```text
test/pblob.test
test/pblob_lowlevel.test
test/pblob_vectors.test
test/pblob_limits.test
test/pblob_fault.test
test/pblob_all.test
tool/gen_pblob_vectors.py
```

A committed generated vector-data file may also be added, for example:

```text
test/pblob_vectors_data.tcl
```

or:

```text
test/pblob_vectors.data
```

Use the project’s established convention.

Do not add another C test module.

All test-only C support must remain in:

```text
pblob.c
```

under:

```c
#ifdef SQLITE_TEST
```

---

### Test Module Responsibilities

The modules must have clear, non-overlapping primary responsibilities.

#### `test/pblob.test`

Public SQL contract and ordinary functional behavior:

* registration;
* arity;
* NULL propagation;
* storage-class validation;
* exact format parsing;
* malformed JSON;
* root-array validation;
* element-type validation;
* ordinary exact pack and unpack examples;
* empty values;
* JSON subtype;
* prepared-statement reuse;
* schema and expression integration;
* representative large arrays;
* public error precedence.

#### `test/pblob_lowlevel.test`

Private helper and exhaustive test operations through:

```text
test_pblob
```

Including:

* endian primitives;
* unaligned access;
* bit classification;
* full signed-byte decoding;
* checked-size arithmetic;
* JSONB numeric extraction;
* malformed internal JSONB;
* portable FP16 mode;
* exhaustive binary16 classification;
* exhaustive binary16 conversion;
* exhaustive binary16 JSON round trip.

#### `test/pblob_vectors.test`

Committed independent numeric vectors:

* `int8`;
* binary16 packing;
* binary16 unpacking;
* binary32 packing;
* binary32 unpacking;
* both endian forms;
* boundary values;
* rounding values;
* random finite patterns;
* invalid non-finite words.

#### `test/pblob_limits.test`

SQLite limit behavior:

* packed BLOB output limits;
* unpacked JSON text limits;
* exact and near-boundary behavior;
* limit restoration;
* statement recovery after limit failures.

#### `test/pblob_fault.test`

SQLite fault injection and allocation failure:

* JSON parsing;
* numeric payload duplication;
* output BLOB allocation;
* `JsonString` growth;
* late failure after partial processing;
* recovery after OOM.

#### `test/pblob_all.test`

Focused aggregate runner that sources or executes all other `pblob` modules.

It must not duplicate their test bodies.

---

### Public SQL Contract Tests

Finalize tests proving the only public functions are:

```sql
pblob_pack(X, FORMAT)
pblob_unpack(X, FORMAT)
```

Verify:

* each has arity 2;
* no one-argument or variable-arity form exists;
* no `.load` is required;
* no aliases exist;
* functions are available on newly opened connections;
* functions are unavailable under `SQLITE_OMIT_JSON`.

Retain wrong-arity tests for:

```text
0 arguments
1 argument
3 arguments
```

for both functions.

---

### NULL Propagation Matrix

Test every relevant NULL combination.

For `pblob_pack()`:

```sql
pblob_pack(NULL, 'int8')
pblob_pack('[]', NULL)
pblob_pack(NULL, NULL)
pblob_pack(NULL, 1)
pblob_pack(1, NULL)
pblob_pack(NULL, x'00')
```

For `pblob_unpack()`:

```sql
pblob_unpack(NULL, 'int8')
pblob_unpack(x'', NULL)
pblob_unpack(NULL, NULL)
pblob_unpack(NULL, 1)
pblob_unpack(1, NULL)
pblob_unpack(NULL, x'00')
```

Every call containing either SQL NULL must return SQL NULL.

These tests must prove NULL propagation takes precedence over all other errors.

---

### Strict Type Tests

For `pblob_pack()` verify:

```text
argument 0 must be TEXT
argument 1 must be TEXT
```

Reject:

```text
INTEGER
REAL
BLOB
JSONB
```

as the first argument.

For `pblob_unpack()` verify:

```text
argument 0 must be BLOB
argument 1 must be TEXT
```

Reject:

```text
TEXT
INTEGER
REAL
```

as the first argument.

Confirm `jsonb('[]')` remains rejected by `pblob_pack()` because it is a BLOB.

Confirm arbitrary BLOB content, including JSONB bytes, remains acceptable as raw input to `pblob_unpack()` when its length and values are valid for the selected packed format.

---

### Format Parsing Tests

Accept only:

```text
int8
<f2
>f2
<f4
>f4
```

Reject:

```text
INT8
Int8
i8
s8
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
@f2
@f4
native
```

Reject whitespace variants:

```text
" int8"
"int8 "
"\tint8"
"int8\n"
" <f2"
"<f2 "
```

Reject embedded-NUL variants through bound Tcl values:

```text
"int8\0"
"<f2\0"
"<f2\0junk"
">f4\0suffix"
```

Test both functions.

---

### Error-Precedence Tests

Add an explicit matrix proving the public validation order.

For packing:

```text
wrong first type + wrong format type
valid first type + wrong format type
valid first type + unsupported format
malformed JSON + valid format
valid non-array JSON
array with wrong element type
array with out-of-range element
```

For unpacking:

```text
wrong first type + wrong format type
valid BLOB + wrong format type
valid BLOB + unsupported format
invalid length
valid length containing non-finite float word
```

Assert exact stable errors for extension-defined cases.

Do not over-specify SQLite core malformed-JSON wording if it varies by build configuration. Test the error category or stable relevant portion where necessary.

---

### `int8` Functional Tests

Retain exact packing vectors:

```text
[]                           -> empty BLOB
[-128,-1,0,1,127]           -> 80FF00017F
[-128,-127,-1,0,1,126,127]  -> 8081FF00017E7F
```

Retain exact unpacking vectors:

```text
empty BLOB       -> []
80FF00017F       -> [-128,-1,0,1,127]
```

Test the complete packing domain:

```text
-128 through 127
```

Test the complete unpacking byte domain:

```text
00 through FF
```

Verify:

```text
pack(unpack(blob,'int8'),'int8') == blob
```

for arbitrary deterministic BLOBs.

Reject:

* `-129`;
* `128`;
* floating lexical forms;
* null;
* booleans;
* text;
* nested containers.

---

### Binary16 Public Tests

Retain representative public tests for both endian forms.

At minimum include:

```text
positive zero
negative zero
smallest positive subnormal
largest positive subnormal
smallest positive normal
0.5
1.0
-1.0
2.0
maximum positive finite
maximum negative finite
```

Verify:

* exact packing bytes;
* semantic unpack values;
* repacked bit identity;
* endian conversion;
* odd-length rejection;
* infinity rejection;
* NaN rejection;
* first invalid element index.

The exhaustive binary16 domain remains in `pblob_lowlevel.test`.

Do not repeat all 65,536 patterns in Tcl vector tests.

---

### Binary32 Public Tests

Include representative tests for:

```text
positive zero
negative zero
smallest positive subnormal
largest positive subnormal
smallest positive normal
0.5
1.0
-1.0
2.0
maximum positive finite
maximum negative finite
```

Verify:

* exact packing bytes;
* semantic unpack values;
* repacked bit identity;
* endian conversion;
* invalid lengths 1, 2, and 3 modulo 4;
* infinity rejection;
* multiple NaN representations;
* first invalid element index.

Include deterministic random finite binary32 patterns from the committed independent vector set.

---

### Independent Vector Generator

Complete:

```text
tool/gen_pblob_vectors.py
```

The script must generate committed vector data independently of `pblob.c`.

It must not:

* invoke SQLite;
* invoke `pblob_pack()`;
* invoke `pblob_unpack()`;
* read previously generated implementation output as its oracle.

The script must generate:

```text
int8 exact vectors
binary16 pack vectors
binary16 unpack vectors
binary32 pack vectors
binary32 unpack vectors
invalid binary16 words
invalid binary32 words
rounding-boundary cases
deterministic random finite raw-word cases
```

---

### Generator Determinism

The generator must be deterministic.

Define:

```text
fixed random seed
fixed output ordering
fixed numeric formatting policy
fixed endian encoding
fixed line endings where practical
```

Running the script twice with the same runtime and dependencies must produce byte-identical output.

Include a generated-file header recording:

```text
generator filename
generator schema version
Python version
dependency versions
random seed
FP16 oracle method
generation timestamp omitted or normalized
```

Do not include a changing timestamp that makes reproducibility difficult.

---

### Binary32 Oracle

For binary32 vectors, use a clearly independent method such as Python’s:

```python
struct.pack()
struct.unpack()
```

Model the required packing path:

```text
input numeric value
-> Python binary64
-> IEEE binary32
-> raw bits
```

For unpack vectors, start from raw finite binary32 words and derive the corresponding Python float value.

Do not use native byte order implicitly.

Always specify:

```text
<
>
```

or explicitly manipulate raw integer words.

---

### Binary16 Oracle

For binary16 vectors, model the required path:

```text
numeric value
-> binary64
-> binary32
-> binary16
```

Do not silently use direct binary64-to-binary16 conversion if that could differ.

Preferred approaches:

1. Implement an independent integer binary32-to-binary16 conversion in Python.
2. Use a verified library path only after explicitly narrowing to binary32 first.
3. Cross-check generated canonical vectors against a second independent implementation during generator development.

The committed test data is the test oracle. The generator does not run during normal test execution.

---

### Rounding Vector Coverage

Generate targeted rounding vectors for binary16 and binary32.

Include:

```text
exact representable values
halfway values
just below halfway
just above halfway
ties resolving to even
normal/subnormal transition
subnormal/zero transition
maximum finite/infinity transition
positive and negative forms
```

For binary16, include known double-rounding-sensitive cases for:

```text
binary64 -> binary32 -> binary16
```

For binary32, model:

```text
binary64 -> binary32
```

Commit the resulting exact raw words.

---

### Deterministic Random Vectors

Generate a fixed deterministic sample of finite raw words.

Recommended minimum:

```text
binary16: 256 finite raw words
binary32: 512 finite raw words
```

Include both signs and all relevant exponent classes.

For binary16, exhaustive coverage already exists, so the random committed sample primarily validates public SQL and endian handling.

For binary32, sample:

```text
zeros
subnormals
small normals
ordinary normals
large normals
maximum-range values
both signs
```

Exclude non-finite patterns from the finite vector set.

Generate separate invalid sets for infinity and NaN.

---

### Vector Data Format

Use a simple committed format that Tcl can consume deterministically.

For example:

```tcl
set pblob_f16_vectors {
  {name zero value 0.0 bits 0000}
  ...
}
```

or a structured line-oriented text format.

The format must encode:

```text
case name
source numeric text where applicable
raw word
little-endian bytes
big-endian bytes
expected classification
expected validity
```

Do not require Python during the test run.

---

### Vector File Verification

Add a generator verification mode such as:

```text
--check
```

It must:

1. Regenerate output in memory or in a temporary file.
2. Compare it to the committed vector data.
3. Exit nonzero if they differ.
4. Leave the committed file unchanged.

Also support an explicit update mode such as:

```text
--write
```

Do not overwrite committed vector data during ordinary test runs.

---

### Length-Limit Test Module

Create:

```text
test/pblob_limits.test
```

Test packed BLOB output limits for:

```text
int8 width 1
f2 width 2
f4 width 4
```

For each width:

* set a reduced connection length limit;
* test output below the limit;
* test output at the limit where feasible;
* test output above the limit;
* verify correct error;
* restore the original limit.

Use `try/finally`-style Tcl cleanup conventions where available so limits are restored even when an assertion fails.

---

### Unpacked JSON Length Limits

For each unpack format:

```text
int8
<f2
>f2
<f4
>f4
```

construct input whose resulting compact JSON:

* fits;
* approaches the configured limit;
* exceeds the configured limit.

Verify:

* fitting result is valid JSON;
* oversized result fails cleanly;
* no partial result is returned;
* no JSON subtype is associated with an error result;
* subsequent ordinary calls succeed;
* the original limit is restored.

Do not assume a fixed text expansion ratio.

Use actual controlled values and measured expected output lengths.

---

### Fault Test Module

Create:

```text
test/pblob_fault.test
```

Use SQLite’s established fault-injection mechanism.

Cover allocation failures in:

```text
JSON text parsing
JSON text to internal JSONB conversion
numeric payload duplication
pack output allocation
JsonString initial allocation
JsonString growth
late JsonString growth
result finalization where applicable
```

Test each public format family:

```text
int8 pack
int8 unpack
f2 pack
f2 unpack
f4 pack
f4 unpack
```

Both endian variants need not duplicate every identical allocator path, but at least one path per endian-specific implementation must be covered where code differs.

---

### Fault-Test Requirements

For every injected failure verify:

```text
an error is returned
no partial BLOB is returned
no partial JSON is returned
no stale JSON subtype remains
all owned state is released
the prepared statement remains reusable
a subsequent valid execution succeeds
```

Do not assert only that “an error occurred.”

Where the harness supports leak detection, integrate it.

Do not treat non-OOM conversion errors as successful fault-injection coverage.

---

### Prepared-Statement Tests

Complete prepared-statement reuse tests for:

```sql
SELECT pblob_pack(?1, ?2);
SELECT pblob_unpack(?1, ?2);
```

Alternate among:

```text
valid empty input
valid small input
valid large input
wrong type
bad format
malformed JSON
non-array JSON
invalid element type
out-of-range element
invalid BLOB length
non-finite packed value
valid input after error
```

Verify:

* no stale result;
* no stale parse;
* no stale output allocation;
* no stale element index;
* no stale subtype;
* correct recovery after large output;
* correct recovery after OOM where supported.

---

### Expression Integration Tests

Test direct use in expressions:

```sql
length(pblob_pack(...))
hex(pblob_pack(...))
typeof(pblob_pack(...))

json_valid(pblob_unpack(...))
json_type(pblob_unpack(...))
json_array_length(pblob_unpack(...))
json_extract(pblob_unpack(...), '$[0]')
```

Test nesting:

```sql
pblob_pack(pblob_unpack(blob, format), format)
pblob_unpack(pblob_pack(json, format), format)
```

Test JSON composition:

```sql
json_array(pblob_unpack(...))
json_object('values', pblob_unpack(...))
```

Verify unpacked JSON is inserted as an array, not quoted text.

---

### Schema Integration Tests

Because both functions are registered as deterministic and innocuous, test use in schema expressions where SQLite permits such functions.

Include representative cases such as:

```text
generated columns
CHECK constraints
expression indexes
views
triggers
```

Only test constructs supported by the selected SQLite source and build configuration.

Examples:

```sql
CREATE TABLE t(
  source TEXT,
  packed BLOB GENERATED ALWAYS AS (
    pblob_pack(source, 'int8')
  ) STORED
);
```

and:

```sql
CREATE INDEX t_unpack_idx
ON t(json_array_length(pblob_unpack(packed, 'int8')));
```

Where schema usage is rejected by SQLite for reasons unrelated to `pblob`, document and test the actual supported subset rather than forcing an unsupported case.

---

### Deterministic-Function Tests

Verify repeated calls with identical inputs return identical results.

For each format, execute:

```text
same pack input many times
same unpack input many times
same input across separate prepared statements
same input across separate connections
```

Compare exact BLOB bytes or exact JSON text where formatting is stable.

At minimum verify semantic and bit identity for floating output.

---

### Innocuous-Function Tests

Where the test harness supports trusted-schema controls, verify the functions remain usable under the intended innocuous-function policy.

Test the selected SQLite behavior with:

```text
trusted_schema ON
trusted_schema OFF
```

for supported schema contexts.

Do not change registration flags merely to make an unsupported schema construct pass.

---

### Large-Input Tests

Test representative element counts:

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
16384
```

Use larger counts only when runtime remains practical.

For packing verify:

```text
exact output length
correct first element
correct middle element
correct last element
deterministic repeated output
```

For unpacking verify:

```text
valid JSON
correct array length
correct first value
correct middle value
correct last value
repacking identity
```

Avoid constructing huge expected JSON strings directly in Tcl when semantic checks are sufficient.

---

### Public Error Message Tests

Assert exact extension-defined messages for:

```text
wrong first argument type
wrong format type
unsupported format
expected array
wrong element type
int8 range error
float16 range error
float32 range error
invalid f2 length
invalid f4 length
non-finite f2 unpack element
non-finite f4 unpack element
malformed internal JSON representation through test hook
```

Ensure zero-based element indexes are correct.

Do not require exact full text for SQLite core OOM, malformed JSON, or length-limit messages where platform or build variations exist.

---

### Remove Duplicate Tests

Review all earlier-stage tests and remove duplication that no longer adds coverage.

Examples:

* low-level endian tests duplicated in `pblob.test`;
* exhaustive binary16 tests repeated in vector tests;
* identical NULL matrices repeated in several modules;
* old placeholder tests;
* tests using temporary command names removed in Stage 13.

Retain a small smoke subset in `pblob.test` even when detailed coverage exists elsewhere.

Do not remove tests solely to reduce runtime without preserving equivalent coverage.

---

### Aggregate Runner

Create:

```text
test/pblob_all.test
```

It must run:

```text
pblob.test
pblob_lowlevel.test
pblob_vectors.test
pblob_limits.test
pblob_fault.test
```

Use the test harness’s standard mechanism for sourcing or invoking test files.

The aggregate runner must:

* preserve test isolation;
* report which module failed;
* not silently skip unavailable modules;
* avoid recursively running itself;
* not duplicate test bodies.

Where fault tests require a separate harness mode, invoke them according to SQLite convention rather than merely sourcing them incorrectly.

---

### Independent Module Execution

Each test module must run independently.

Verify:

```text
pblob.test
pblob_lowlevel.test
pblob_vectors.test
pblob_limits.test
pblob_fault.test
```

do not rely on side effects from a previously run module.

Each module must:

* create its own required tables;
* restore modified limits;
* restore pragmas;
* clean up prepared statements;
* avoid relying on test order;
* use unique test names.

---

### Test Naming

Use consistent test names, for example:

```text
pblob-public-*
pblob-lowlevel-*
pblob-vectors-*
pblob-limits-*
pblob-fault-*
```

Names must be unique across modules.

Do not retain obsolete stage-number-based names if they obscure final test purpose.

---

### Test Runtime

Keep the normal focused suite practical.

The exhaustive binary16 tests may be the most expensive portion, but should remain implemented primarily in C.

Avoid:

* 65,536 separate Tcl test cases;
* large repeated SQL string construction;
* unnecessary database reopen loops;
* running the vector generator from ordinary tests.

Record approximate test runtime for each module.

Do not remove exhaustive coverage solely because it is slower than ordinary SQL tests.

---

### Test Data Integrity

Add checks that committed vector data is internally consistent.

Verify:

* little-endian bytes reverse each raw word correctly;
* big-endian bytes equal canonical raw-word order;
* finite vectors are classified finite;
* invalid vectors are actually infinity or NaN;
* vector names are unique;
* expected lengths match element counts.

These checks must not use the production conversion result as the sole oracle.

---

### Release Shell Smoke File

Add a concise SQL smoke script if the project uses such artifacts, for example:

```text
test/pblob_smoke.sql
```

It should test:

```text
pack/unpack int8
pack/unpack <f2
pack/unpack >f2
pack/unpack <f4
pack/unpack >f4
empty inputs
signed zero
one non-finite rejection
JSON subtype composition
```

This file must be runnable by the normal release `sqlite3.exe`.

Do not require `testfixture` commands in it.

If the project does not retain standalone smoke SQL files, document equivalent shell commands instead.

---

### Build Verification

Perform all required configurations.

#### Normal Build

Build normal:

```text
sqlite3.exe
sqlite3.dll
```

Run release-shell smoke tests.

Verify:

* every format direction works;
* no test-only Tcl command is present;
* no vector generator dependency exists;
* no new warnings appear.

#### Test Build

Build `testfixture` with:

```text
SQLITE_TEST
SQLITE_DEBUG
FP16_USE_NATIVE_CONVERSION=0
```

Run each focused module independently.

Then run:

```text
test/pblob_all.test
```

#### Strict-Warning Build

Compile normal and test configurations with the practical strict-warning profile.

Treat warnings in:

```text
pblob.c
test-only pblob code
vector generator
```

as failures where applicable.

#### Sanitizer Build

Run:

```text
pblob.test
pblob_lowlevel.test
pblob_vectors.test
pblob_limits.test
```

under ASan and UBSan where supported.

Run fault tests under sanitizers only where the harness and sanitizer configuration are compatible.

Document incompatibility rather than claiming success.

#### JSON-Disabled Build

Build with:

```text
SQLITE_OMIT_JSON
```

Verify:

* no public `pblob` functions;
* no `test_pblob` command;
* focused modules skip only through an explicit supported-feature guard or are not invoked;
* no unresolved symbols;
* no warnings.

---

### Prohibited Work

Do not:

* add new packed formats;
* add new production SQL functions;
* change accepted format strings;
* change public conversion semantics;
* add BLOB headers or metadata;
* add native-endian behavior;
* accept JSONB input for `pblob_pack()`;
* return JSONB from `pblob_unpack()`;
* create another C module;
* create `pblob.h`;
* remove `static` from production helpers;
* run Python during ordinary Tcl test execution;
* generate expected data from `pblob.c`;
* make tests depend on prior test-module execution;
* weaken exhaustive binary16 coverage;
* modify `json.c`;
* modify the vendored FP16 implementation;
* refactor unrelated SQLite tests.

---

### Expected Deliverables

Provide:

1. Finalized:

   ```text
   test/pblob.test
   test/pblob_lowlevel.test
   test/pblob_vectors.test
   test/pblob_limits.test
   test/pblob_fault.test
   test/pblob_all.test
   ```
2. Finalized:

   ```text
   tool/gen_pblob_vectors.py
   ```
3. Committed generated vector data.
4. Optional release smoke SQL file where consistent with the project.
5. Any necessary `pblob.c` fixes exposed by new tests.
6. Exact vector generation command.
7. Exact vector verification command.
8. Exact build commands.
9. Exact test commands.
10. Results for every focused module and aggregate runner.
11. Approximate runtime for each module.
12. A concise list of modified and added files.
13. A concise list of defects found by the expanded suite.
14. Confirmation that:

    * normal tests do not require Python;
    * all vector data is independent of `pblob.c`;
    * all test-only C code remains in `pblob.c`;
    * every test module runs independently;
    * limits and pragmas are restored;
    * fault tests verify cleanup and recovery;
    * exhaustive binary16 coverage remains active;
    * all public format directions remain functional;
    * no public API or header was added.

---

### Acceptance Criteria

Stage 14 is complete only when:

* the final focused test-module structure exists;
* each module has a clear primary responsibility;
* every module runs independently;
* `pblob_all.test` runs the complete focused suite;
* public SQL contract coverage is complete;
* strict type and format tests are complete;
* NULL and error-precedence matrices pass;
* exact `int8`, binary16, and binary32 vectors pass;
* both endian variants are covered;
* committed vectors are generated independently of `pblob.c`;
* vector generation is deterministic;
* vector verification mode detects stale committed data;
* normal test execution does not require Python;
* binary16 exhaustive classification still covers all 65,536 words;
* every finite binary16 word survives JSON unpack/pack bit-identically;
* deterministic finite binary32 raw-word samples survive round trips;
* non-finite binary16 and binary32 patterns are rejected;
* signed zero and subnormals are preserved;
* packed-output length limits are covered for widths 1, 2, and 4;
* unpacked JSON length limits are covered for all formats;
* fault injection covers every extension-owned allocation class;
* OOM never returns partial output or stale subtype;
* prepared statements recover after all tested error classes;
* schema and expression integration tests pass in supported contexts;
* release-shell smoke tests pass;
* all prior-stage tests remain passing;
* normal build succeeds;
* test build succeeds;
* strict-warning build is clean;
* sanitizer runs report no extension defects;
* JSON-disabled build succeeds;
* no second C module, public C API, or public header exists.

Stop after satisfying these criteria. Do not proceed to Stage 15.

---
---

## 📗 Stage 15: Full Integration, Release, and Portability Validation

Implement only Stage 15 of the packed numeric BLOB extension.

This stage begins from the completed Stage 14 state, where:

* `pblob.c` is the only production and test-specific C module;
* all five formats are functional in both directions;
* the implementation has completed validation and cleanup audit;
* the consolidated `test_pblob` command exists only under `SQLITE_TEST`;
* the final focused test modules exist;
* independent committed vectors exist;
* exhaustive binary16 tests pass;
* focused limit, fault, prepared-statement, schema-integration, and release-smoke tests exist;
* no public C API or public header exists.

Stage 15 is the final integration and build-validation stage.

Do not add new functionality.

### Objective

Prove that the completed extension integrates correctly with the full SQLite build and test environment.

This stage must validate:

* clean amalgamation generation;
* correct source ordering;
* normal release shell and DLL builds;
* testfixture integration;
* complete focused `pblob` tests;
* full SQLite regression tests;
* JSON-disabled builds;
* portable FP16 enforcement;
* strict-warning builds;
* sanitizer builds;
* repeated clean builds;
* release-binary smoke behavior;
* absence of test-only symbols from production artifacts;
* absence of accidental public exports;
* reproducibility of generated vector data;
* no regressions outside the extension.

No implementation change is acceptable unless required to fix an integration defect exposed during this stage.

### Scope

This stage is limited to:

1. Performing clean builds from the project’s normal source entry points.
2. Verifying amalgamation generation and source placement.
3. Building normal release artifacts.
4. Building the SQLite test harness.
5. Running all focused `pblob` tests.
6. Running the selected full SQLite regression suite.
7. Building with `SQLITE_OMIT_JSON`.
8. Building with strict warning configurations.
9. Running supported sanitizer builds.
10. Verifying production binary contents and exports.
11. Verifying deterministic vector generation.
12. Recording exact commands and results.
13. Fixing only defects exposed by these integration checks.

Do not reorganize the test suite or redesign `pblob.c`.

---

### Clean-Tree Requirement

Begin from a clean or reproducibly reset build state.

Remove or isolate:

```text
generated amalgamation files
object files
libraries
executables
test databases
temporary vector output
stale Tcl test artifacts
compiler intermediate files
```

Use the project’s established clean target where available.

Do not rely on incremental builds as the only validation.

At least one complete validation cycle must begin from a clean source and build tree.

Record whether the source tree contained unrelated pre-existing modifications.

Do not delete user-maintained source files or unrelated outputs.

---

### Amalgamation Generation

Run the project’s normal amalgamation-generation process.

Verify the generated amalgamation contains `pblob.c` content:

```text
after json.c
before any dispatcher or source fragment that calls sqlite3PblobInit()
```

Confirm that private `json.c` definitions used by `pblob.c` are visible in the same translation unit.

Verify no separate compilation of `pblob.c` is accidentally required for the normal amalgamation build.

Inspect the generated source for:

```text
module documentation
PblobFormat definitions
pblobPackFunc
pblobUnpackFunc
sqlite3PblobInit
```

Do not depend only on successful linking to infer source ordering.

---

### Amalgamation Source-Order Test

Add or retain a build-time verification that fails if `pblob.c` is moved before `json.c`.

An acceptable verification may:

* inspect the generated amalgamation;
* inspect the source-list order;
* depend on private types unavailable before `json.c`;
* use an explicit source-generation assertion.

Do not add a fragile line-number check.

Verify the source-generation process includes `pblob.c` exactly once.

---

### Normal Release Build

Build the project’s normal release artifacts, including at least:

```text
sqlite3.exe
sqlite3.dll
```

and any associated import or static library normally produced by the project.

Use the project’s intended production compiler flags.

Do not define:

```text
SQLITE_TEST
SQLITE_DEBUG
```

unless they are part of a separate debug validation build.

The release build must retain:

```text
FP16_USE_NATIVE_CONVERSION=0
```

for the extension.

Verify:

* compile succeeds;
* link succeeds;
* no unresolved symbols;
* no duplicate symbols;
* no new warnings;
* no dependence on testfixture or Tcl;
* no loadable-extension entry point is required.

---

### Release Shell Smoke Tests

Run the release shell against the Stage 14 smoke SQL or equivalent direct SQL commands.

Test all directions:

```text
pack int8
unpack int8
pack <f2
unpack <f2
pack >f2
unpack >f2
pack <f4
unpack <f4
pack >f4
unpack >f4
```

At minimum verify:

```sql
SELECT hex(pblob_pack('[-128,-1,0,1,127]', 'int8'));
SELECT pblob_unpack(x'80FF00017F', 'int8');

SELECT hex(pblob_pack('[1.0,2.0]', '<f2'));
SELECT pblob_unpack(x'003C0040', '<f2');

SELECT hex(pblob_pack('[1.0,2.0]', '>f2'));
SELECT pblob_unpack(x'3C004000', '>f2');

SELECT hex(pblob_pack('[1.0,2.0]', '<f4'));
SELECT pblob_unpack(x'0000803F00000040', '<f4');

SELECT hex(pblob_pack('[1.0,2.0]', '>f4'));
SELECT pblob_unpack(x'3F80000040000000', '>f4');
```

Expected packed values:

```text
int8: 80FF00017F
<f2:  003C0040
>f2:  3C004000
<f4:  0000803F00000040
>f4:  3F80000040000000
```

Also verify:

```text
empty pack returns zero-length BLOB
empty unpack returns []
negative zero survives repacking
non-finite raw input is rejected
unpacked result composes as JSON
```

No `.load` command may be used.

---

### DLL Integration

Verify the functions are available through a database connection opened against the produced `sqlite3.dll`.

Use either:

* the project’s normal shell linked against the DLL;
* a minimal existing test client;
* an established SQLite API test harness.

Verify:

* a new connection sees both functions automatically;
* multiple independent connections see both functions;
* closing and reopening a connection does not require manual registration;
* registration failures are not silently ignored.

Do not create a new supported application API solely for this test.

---

### Production Export Audit

Inspect the produced DLL export table.

Confirm no new public extension-specific symbol is exported, including:

```text
sqlite3PblobInit
pblobPackFunc
pblobUnpackFunc
pblobJsonbInteger
pblobJsonbNumber
test_pblob
```

Only the project’s intended SQLite public exports should remain.

If `sqlite3PblobInit` is visible at object level but not exported from the DLL, that is acceptable.

Do not add export annotations.

---

### Production Symbol Audit

Where supported, inspect object or binary symbols.

Verify:

* all helper symbols remain local or internal;
* no `test_pblob` operation strings or test-only oracle symbols appear in production artifacts;
* no Tcl symbols are linked into the release shell or DLL because of this extension;
* no loadable-extension entry point was introduced;
* no `pblob.h`-derived public symbols exist.

Account for compiler optimization and symbol stripping when interpreting results.

Do not claim absence based solely on inability to inspect a stripped binary; document the method used.

---

### Release Dependency Audit

Verify the production artifacts do not acquire an unintended runtime dependency on:

```text
Tcl
Python
NumPy
testfixture
a separate FP16 DLL
a separate pblob library
```

The vendored FP16 implementation must remain compiled into the amalgamation path as intended.

Use the platform’s dependency inspection tool where practical.

Record the actual new or unchanged runtime dependencies.

---

### Testfixture Build

Build the SQLite test harness using the project’s established test configuration.

Required definitions include:

```text
SQLITE_TEST
SQLITE_DEBUG
FP16_USE_NATIVE_CONVERSION=0
```

Use `SQLITE_ENABLE_API_ARMOR` only if it is already part of the selected project test configuration or is being validated as an additional build variant.

Do not introduce it as a mandatory requirement without source-tree justification.

Verify:

* `test_pblob` is registered;
* all required Tcl test commands are available;
* no duplicate registration occurs;
* exhaustive test operations run;
* all test-only code remains absent from release artifacts.

---

### Focused Test Modules

Run each focused module independently:

```text
test/pblob.test
test/pblob_lowlevel.test
test/pblob_vectors.test
test/pblob_limits.test
test/pblob_fault.test
```

Then run:

```text
test/pblob_all.test
```

For every module record:

```text
pass/fail
test count
runtime
skipped tests
known platform exclusions
```

A module that silently skips because of missing registration is a failure unless the skip is explicitly required by the build configuration.

---

### Independent Vector Verification

Run the vector generator in verification mode:

```text
tool/gen_pblob_vectors.py --check
```

or the final equivalent command.

Verify:

* committed vector data matches regenerated data;
* no file changes occur;
* the command exits successfully;
* the generator does not invoke SQLite;
* the generator uses the recorded deterministic seed and schema version.

Then run the verification a second time.

Both runs must produce identical results.

Do not update committed vectors during this validation unless a proven generator or vector defect is found.

---

### Full SQLite Regression Suite

Run the selected source tree’s established full or primary regression target.

Use the actual target appropriate to the project and platform.

Examples may include:

```text
test
fulltest
devtest
releasetest
```

Use only targets present in the selected source tree.

At minimum, run the broadest practical regression suite normally used for this project’s release validation.

Record:

```text
exact target
test count where reported
runtime
failures
skips
platform limitations
```

Any unrelated pre-existing failure must be clearly distinguished from a new failure caused by the extension.

Do not classify a new regression as unrelated without evidence.

---

### Regression Isolation

If the full suite fails:

1. Reproduce the failure.
2. Determine whether it occurs without the `pblob` integration.
3. Determine whether it depends on:

   * source order;
   * registration flags;
   * JSON internals;
   * memory limits;
   * subtype handling;
   * build defines;
   * test-only code.
4. Add a focused regression test where applicable.
5. Fix only the demonstrated defect.
6. Rerun:

   * the focused failing test;
   * all `pblob` tests;
   * the full regression target.

Do not make speculative broad changes.

---

### JSON-Disabled Release Build

Perform a clean release build with:

```text
SQLITE_OMIT_JSON
```

Verify:

* build succeeds;
* link succeeds;
* `pblob_pack` is unavailable;
* `pblob_unpack` is unavailable;
* `test_pblob` is absent;
* no unresolved JSON or FP16 symbols exist;
* no unused-static warnings occur;
* no extension registration call remains active.

The preferred behavior is that FP16 code required only by `pblob` is excluded or inactive under the JSON guard.

Document whether the vendored header is pre-expanded regardless of the guard, but ensure no active extension behavior remains.

---

### JSON-Disabled Test Build

Where the project supports it, build the test harness with:

```text
SQLITE_TEST
SQLITE_OMIT_JSON
```

Verify:

* `test_pblob` is not registered;
* focused `pblob` modules either:

  * are not invoked; or
  * skip through an explicit feature guard;
* no crash or unresolved symbol occurs;
* unrelated SQLite tests remain functional.

Do not make the test command partially available without JSON internals unless that is a deliberate and documented design.

---

### Portable FP16 Verification

Verify the normative build has:

```text
FP16_USE_NATIVE_CONVERSION == 0
```

Use multiple checks:

1. Preprocessor or compile-time assertion.
2. `test_pblob fp16-mode` in the test build.
3. Build command inspection.
4. Binary16 exact-vector tests.

The compile-time configuration is the authoritative proof.

Do not rely only on matching output vectors.

---

### Accidental Native-Mode Negative Test

Perform one deliberate build attempt with:

```text
FP16_USE_NATIVE_CONVERSION=1
```

only if the Stage 10 compile-time guard is intended to reject it.

Expected:

```text
compile-time failure with a clear diagnostic
```

This negative build is optional if project tooling cannot conveniently perform expected-failure tests, but the compile-time guard itself remains mandatory.

Do not weaken the guard merely to make this build succeed.

---

### Strict-Warning Release Build

Build the release configuration using the strictest practical warning profile supported by the selected compiler.

Audit at least:

```text
unused functions
unused variables
signed/unsigned comparisons
narrowing conversions
constant truncation
incorrect format strings
uninitialized values
unreachable code
pointer conversion
shift width
implicit fallthrough
```

Treat warnings originating from `pblob.c` as failures.

Do not globally disable a warning to hide an extension defect.

Document unavoidable warnings from unrelated upstream SQLite code separately.

---

### Strict-Warning Test Build

Build the `SQLITE_TEST` configuration under the same practical warning profile.

Include test-only code in the audit:

```text
Tcl command dispatch
malformed JSONB constructors
independent FP16 oracle
digest code
exhaustive loops
```

Warnings in test-only `pblob.c` code are failures.

Verify all operation selectors are handled and no command path lacks a return.

---

### Debug Build

Build with the project’s normal debug configuration.

Verify:

* assertions remain enabled where intended;
* defensive runtime checks still handle malformed data in release paths;
* no assertion fires during the full focused suite;
* exhaustive binary16 tests pass;
* prepared-statement reuse passes;
* malformed internal JSONB tests produce controlled errors.

Assertions must not be the sole protection against malformed internal state.

---

### AddressSanitizer Build

Where supported, build with AddressSanitizer.

Run at least:

```text
pblob.test
pblob_lowlevel.test
pblob_vectors.test
pblob_limits.test
```

Run `pblob_fault.test` only if the fault harness is compatible with ASan.

Exercise:

```text
large packing arrays
large unpacking BLOBs
malformed internal JSONB
invalid packed lengths
non-finite words
prepared-statement reuse
exhaustive binary16 conversion
```

No leak, over-read, overwrite, use-after-free, or double-free is acceptable.

Document unsupported Windows/MSVC sanitizer combinations rather than claiming they passed.

---

### UndefinedBehaviorSanitizer Build

Where supported, build with UndefinedBehaviorSanitizer.

Exercise:

```text
all endian helpers
all bit-classification helpers
signed-byte conversion
checked-size arithmetic
JSONB offset arithmetic
binary16 conversion tests
binary32 conversion tests
large loop bounds
```

No signed overflow, invalid shift, alignment violation, or out-of-bounds arithmetic is acceptable.

Run the focused suite and exhaustive binary16 tests.

---

### Additional Sanitizers

Where available and practical, consider:

```text
integer sanitizer
alignment sanitizer
leak sanitizer
```

These are supplementary and not required when unsupported.

Do not substitute supplementary sanitizers for ASan and UBSan where those are supported.

Record exactly which sanitizer configurations ran.

---

### Repeated Clean Build

Perform at least two clean normal builds from the same source state.

Verify:

* generated amalgamation output is byte-identical where the build is intended to be deterministic;
* vector files remain unchanged;
* release smoke results are identical;
* no generated file depends on stale build artifacts.

If amalgamation output includes intentionally variable content, compare semantically relevant sections and document the variation.

Do not accept a build that succeeds only after an incremental predecessor.

---

### Parallel Build Validation

If the build system supports parallel execution, perform one supported parallel build.

Verify:

* source generation dependencies are correct;
* `pblob.c` inclusion does not race with amalgamation generation;
* generated FP16-bundled content is ready before compilation;
* no intermittent missing-file failure occurs.

Do not require unsupported parallelism from `nmake`.

Use only the project’s supported mechanism.

---

### Multiple-Connection Test

Using the test harness or a small existing API test, open multiple database connections.

For each connection verify:

```text
pblob_pack exists
pblob_unpack exists
identical inputs produce identical results
closing one connection does not affect others
length limits remain connection-local
```

Test a reduced `SQLITE_LIMIT_LENGTH` on one connection and default limits on another.

Verify the extension does not use mutable global conversion state.

---

### Threading Validation

Where the selected SQLite build supports threaded use, run the project’s existing relevant thread tests with the extension enabled.

At minimum verify:

* no mutable static buffers in `pblob.c`;
* no global cached result state;
* no global `JsonString`;
* no global current-format state;
* vendored FP16 calls are stateless.

Do not create a new concurrency model or promise thread guarantees beyond SQLite’s configured mode.

---

### Database Schema Integration Validation

Rerun Stage 14 schema tests in the release-capable build configuration.

Verify supported use in:

```text
generated columns
CHECK constraints
expression indexes
views
triggers
```

Test under the selected trusted-schema settings.

Confirm registration flags permit the intended usage without weakening safety.

Do not force schema contexts that SQLite itself disallows.

---

### Determinism Validation

For each format, repeat identical calls many times:

```text
within one statement
across statement resets
across separately prepared statements
across connections
across clean builds
```

Compare:

* exact packed BLOB bytes;
* exact unpacked JSON text where stable;
* semantic and repacked bit identity otherwise.

No output may depend on uninitialized memory, host byte order, allocation address, or connection history.

---

### Locale Validation

Where practical, run release smoke tests under at least one non-default numeric locale.

Verify floating JSON output remains valid and uses:

```text
.
```

as the decimal separator.

The implementation must depend on SQLite’s locale-independent JSON formatting, not process-locale `printf()` behavior.

Do not alter global locale permanently within the test process.

---

### Host Endianness Review

A big-endian runtime may not be available.

Regardless, perform static and test review proving:

* all packed I/O uses explicit byte helpers;
* no `memcpy(float)` representation is emitted directly;
* no integer pointer cast reads packed data;
* no host-order branch exists;
* `<` and `>` formats are defined exclusively by helper calls.

If an actual big-endian test environment is available, run the focused suite there and record results.

Do not claim runtime big-endian validation when none occurred.

---

### Compiler Matrix

Where practical for the project, validate more than one compiler.

For a Windows-focused build, examples may include:

```text
MSVC
Clang-cl
MinGW GCC
```

Use only toolchains supported by the source tree and environment.

At minimum, the primary supported compiler must pass all required builds.

Secondary compiler failures caused by unsupported project configurations must be documented precisely.

Do not broaden scope into making the entire SQLite tree support a previously unsupported compiler.

---

### Architecture Matrix

Where available, validate the primary architecture and any additional supported architecture, such as:

```text
x64
x86
ARM64
```

At minimum verify compile-time assumptions remain valid:

```text
CHAR_BIT == 8
sizeof(uint16_t) == 2
sizeof(uint32_t) == 4
sizeof(float) == 4
FLT_RADIX == 2
FLT_MANT_DIG == 24
FLT_MAX_EXP == 128
```

Do not weaken these assumptions for an unsupported target.

---

### Release Optimization Validation

Build with normal release optimization and link-time optimization where the project normally uses it.

Verify:

* no helper is incorrectly removed when referenced;
* no strict-aliasing issue emerges;
* exhaustive vector tests still pass;
* negative zero remains preserved;
* malformed internal tests remain safe;
* test-only code remains excluded.

Optimization must not change packed bytes or JSON semantics.

---

### Binary Size Review

Record the approximate size effect of adding the extension to:

```text
sqlite3.c
sqlite3.exe
sqlite3.dll
```

Use comparable before/after artifacts if available.

This is informational, not a fixed acceptance threshold.

Distinguish:

* source-size increase;
* executable-size increase;
* debug-symbol increase.

Do not remove required validation or tests solely to reduce binary size.

---

### Performance Smoke Review

Run a non-benchmark timing sanity check for representative inputs:

```text
small array
4096-element array
16384-element array
binary16 exhaustive test command
```

The purpose is to detect catastrophic algorithmic mistakes such as:

```text
quadratic output construction
per-element SQL preparation
per-element heap allocation
reparsing the entire array for every element
```

Do not turn this stage into a formal optimization project.

Record approximate timings and environment.

Only fix obvious regressions or violations of the intended single-pass design.

---

### Source Review

Perform a final source review confirming:

```text
one production module
no pblob.h
no public C API
all helpers static except required internal initializer
no loadable-extension boilerplate
no independent JSON parser
no independent JSON writer
no independent decimal parser
no alternate FP16 converter
no native FP16 conversion
explicit endian handling
checked arithmetic
single-shot pack allocation
JsonString unpack output
```

Confirm comments match implemented behavior and no longer describe future stages.

---

### Test-Only Isolation Review

Verify all test-only sections are guarded by:

```c
#ifdef SQLITE_TEST
```

and, where necessary:

```c
#ifndef SQLITE_OMIT_JSON
```

Confirm release preprocessing excludes:

```text
Tcl includes
test_pblob registration
malformed JSONB builders
independent FP16 oracle
exhaustive loops
test digests
test operation strings
```

Do not rely only on linker dead-code elimination.

---

### Generated-File Review

Verify generated files are current:

```text
amalgamation source
committed vector data
any bundled FP16 source fragments
```

Run all available `--check` or equivalent verification modes.

No generated file may require an uncommitted local manual edit.

Document the generation commands.

---

### Build Command Accuracy

Use exact commands valid for the selected source tree and platform.

Do not provide guessed target names.

If a documented target is unavailable:

* inspect the actual build files;
* use the closest established target;
* record the substitution.

For Windows `nmake`, record all relevant variables such as:

```text
TOP
TCLDIR
OPTS
CFLAGS
LDFLAGS
```

where used.

Do not omit environment prerequisites required to reproduce the build.

---

### Failure Reporting

For every failed build or test, record:

```text
configuration
exact command
exit code
first relevant diagnostic
root cause
fix applied
regression test added
rerun result
```

Do not report only the final successful run if defects were found.

Do not conceal unsupported configurations.

---

### Final Integration Report

Create a concise integration report containing:

```text
SQLite source revision
pblob source revision or commit
vendored FP16 revision
primary compiler and version
secondary compilers tested
architectures tested
build configurations
amalgamation generation result
focused test results
full SQLite regression result
JSON-disabled result
strict-warning result
sanitizer results
release smoke result
vector verification result
production export audit
runtime dependency audit
known limitations
```

Do not include unsupported claims.

---

### Defect Handling

If Stage 15 exposes an implementation defect:

1. Add or identify a reproducing test.
2. Make the smallest correction.
3. Run the focused reproducer.
4. Run all `pblob` modules.
5. Run the affected build matrix entries.
6. Rerun the full SQLite regression suite when the change affects production code.

Do not proceed with a known unresolved defect that violates acceptance criteria.

---

### Prohibited Work

Do not:

* add new formats;
* add new public SQL functions;
* add optional parameters;
* add format aliases;
* change packed layout;
* add BLOB headers or metadata;
* change binary16 conversion semantics;
* enable native FP16 conversion;
* accept JSONB input for packing;
* return JSONB from unpacking;
* create another C module;
* create `pblob.h`;
* export the internal initializer;
* add loadable-extension entry points;
* reorganize unrelated SQLite build logic;
* modify `json.c`;
* modify the vendored FP16 implementation;
* rewrite the test suite structure established in Stage 14;
* optimize beyond fixing an obvious integration defect.

---

### Expected Deliverables

Provide:

1. Any minimal source or test fixes required by Stage 15 findings.
2. Exact clean commands.
3. Exact amalgamation-generation commands.
4. Exact normal release build commands.
5. Exact testfixture build commands.
6. Exact JSON-disabled build commands.
7. Exact strict-warning build commands.
8. Exact sanitizer build commands.
9. Exact focused test commands.
10. Exact full SQLite regression command.
11. Exact vector verification commands.
12. Release-shell smoke commands and output.
13. Production export and dependency audit commands.
14. Per-configuration results.
15. Focused test-module runtimes.
16. Full regression runtime.
17. A concise list of modified files.
18. A concise list of defects found and fixed.
19. The final integration report.
20. Confirmation that:

    * amalgamation source ordering is correct;
    * release shell and DLL builds succeed;
    * functions auto-register on new connections;
    * all focused tests pass;
    * the full SQLite regression suite passes or any unrelated pre-existing failures are proven and documented;
    * JSON-disabled builds succeed;
    * portable FP16 mode is enforced;
    * strict-warning builds are clean;
    * supported sanitizer builds report no defects;
    * vector data is current and reproducible;
    * release artifacts contain no test-only interface;
    * no accidental public exports or dependencies were added;
    * no public C API or header exists.

---

### Acceptance Criteria

Stage 15 is complete only when:

* a clean amalgamation build succeeds;
* `pblob.c` content appears exactly once after `json.c`;
* normal release shell and DLL builds succeed;
* all ten supported function/format directions work in release artifacts;
* no `.load` or application registration call is required;
* functions are available on every new connection;
* all focused test modules pass independently;
* `pblob_all.test` passes;
* committed vectors pass generator verification;
* repeated vector verification is deterministic;
* exhaustive binary16 tests pass;
* the selected full SQLite regression suite passes;
* any unrelated pre-existing failure is reproduced without the extension and documented;
* `SQLITE_OMIT_JSON` release build succeeds;
* `SQLITE_OMIT_JSON` test build succeeds where supported;
* neither public function exists in JSON-disabled builds;
* `test_pblob` exists only in `SQLITE_TEST` builds;
* portable FP16 conversion is enforced at compile time and verified in tests;
* release and test strict-warning builds introduce no `pblob.c` warnings;
* supported ASan and UBSan runs report no extension defects;
* release artifacts contain no Tcl or Python dependency;
* release artifacts contain no test-only command or oracle code;
* no extension-specific public DLL export is introduced;
* all packed bytes are deterministic across repeated clean builds;
* all floating output remains locale-independent;
* no source-order or parallel-build race exists;
* production source remains one C module;
* no `pblob.h`, public C API, loadable-extension entry point, or second C module exists.

Stop after satisfying these criteria. Do not proceed to Stage 16.

---
---

## 📗 Stage 16: Final Review and Cleanup

Implement only Stage 16 of the packed numeric BLOB extension.

This stage begins from the completed Stage 15 state, where:

* `pblob.c` is the only production and test-specific C module;
* all five formats are functional in both directions;
* amalgamation generation and source ordering are verified;
* release shell and DLL builds succeed;
* focused and full SQLite regression suites pass;
* JSON-disabled builds succeed;
* portable FP16 conversion is enforced;
* strict-warning and supported sanitizer builds pass;
* committed vectors are reproducible;
* release artifacts contain no test-only interfaces or accidental public exports;
* no public C API or public header exists.

Stage 16 is the final review and merge-preparation stage.

Do not add functionality.

### Objective

Prepare the completed implementation for final submission or merge.

This stage must:

* perform a final source review;
* confirm the implementation matches the approved design;
* remove obsolete comments and scaffolding;
* normalize naming and local style;
* confirm generated files are current;
* confirm tests and build instructions are reproducible;
* produce a concise implementation report;
* produce a concise reviewer checklist;
* produce the final patch or commit sequence;
* leave the tree clean and ready for review.

Only minimal corrections discovered during final review are permitted.

### Scope

This stage is limited to:

1. Final source and API review.
2. Final code-style and comment cleanup.
3. Final dead-code and symbol review.
4. Final test inventory review.
5. Final generated-file verification.
6. Final build-command verification.
7. Final documentation and integration-note preparation.
8. Final patch or commit organization.
9. Final clean-tree verification.
10. Minimal fixes for defects discovered during this review.

Do not redesign or optimize the implementation.

---

### Final Source Inventory

Confirm the intended extension source inventory.

Production and test-specific C code:

```text
pblob.c
```

Public SQL and Tcl tests:

```text
test/pblob.test
test/pblob_lowlevel.test
test/pblob_vectors.test
test/pblob_limits.test
test/pblob_fault.test
test/pblob_all.test
```

Independent vector generation:

```text
tool/gen_pblob_vectors.py
```

Committed generated vector data:

```text
the final selected vector-data file
```

Optional release smoke script:

```text
test/pblob_smoke.sql
```

Confirm there is no unintended file such as:

```text
pblob.h
pblob_test.c
src/test_pblob.c
test_pblob.c
pblob_internal.h
```

Remove obsolete temporary files created during staged development.

Do not delete unrelated project files.

---

### Final Public API Review

Confirm the only public SQL interface is:

```sql
pblob_pack(json_array, format)
pblob_unpack(blob, format)
```

Confirm both functions:

* have arity 2;
* auto-register on every connection;
* require no `.load`;
* have no aliases;
* expose no optional arguments;
* expose no public C wrapper.

Supported formats must remain exactly:

```text
int8
<f2
>f2
<f4
>f4
```

Confirm there is no accepted native-endian, shorthand, or case-insensitive alias.

---

### Packed Representation Review

Confirm the packed representation remains raw and headerless.

For each format:

```text
int8:
  1 byte per element

<f2:
  IEEE binary16, little-endian

>f2:
  IEEE binary16, big-endian

<f4:
  IEEE binary32, little-endian

>f4:
  IEEE binary32, big-endian
```

Confirm the implementation adds no:

* type marker;
* element count;
* version field;
* checksum;
* alignment padding;
* metadata;
* byte-order marker.

The format argument is the only interpretation metadata.

---

### Source-Ordering Review

Confirm `pblob.c` is placed:

```text
after json.c
```

in the amalgamation source order.

Verify this ordering is required and documented because `pblob.c` uses private `json.c` types and helpers in the same translation unit.

Confirm the source appears exactly once.

Confirm the auto-extension dispatcher can reference the internal initializer at the selected location.

Do not replace this design with a public header or exported internal symbols.

---

### Module Documentation Review

Review the top-level `pblob.c` comment.

It must accurately state:

* extension purpose;
* public SQL functions;
* supported formats;
* raw headerless representation;
* amalgamation-only design;
* dependency on private `json.c` internals;
* dependency on vendored FP16;
* portable FP16 requirement;
* absence of a public C API;
* required source ordering.

Remove wording that refers to:

```text
future implementation
placeholder behavior
later stages
planned formats
temporary test hooks
```

Do not document unsupported behavior.

---

### Compile Guard Review

Verify the implementation is correctly guarded by:

```c
#ifndef SQLITE_OMIT_JSON
...
#endif
```

Verify test-only code is additionally guarded by:

```c
#ifdef SQLITE_TEST
...
#endif
```

Confirm JSON-disabled builds do not retain:

* SQL registration;
* production callbacks;
* test commands;
* JSON references;
* active FP16 conversion code required only by the extension.

Use the narrowest practical guard structure consistent with source bundling.

---

### FP16 Configuration Review

Confirm the normative source forces:

```c
FP16_USE_NATIVE_CONVERSION == 0
```

before inclusion of the vendored FP16 implementation.

Verify there is a clear compile-time failure if native conversion is enabled unexpectedly.

Confirm production code uses only:

```c
fp16_ieee_from_fp32_value()
fp16_ieee_to_fp32_value()
fp32_to_bits()
fp32_from_bits()
```

as intended.

Confirm there is no use of:

```text
_Float16
__fp16
F16C
AVX-512 FP16
ARM half intrinsics
another half library
manual production FP16 conversion
```

---

### Platform Assumption Review

Confirm compile-time checks cover:

```text
CHAR_BIT == 8
sizeof(uint16_t) == 2
sizeof(uint32_t) == 4
sizeof(float) == 4
FLT_RADIX == 2
FLT_MANT_DIG == 24
FLT_MAX_EXP == 128
```

Verify diagnostics are understandable on unsupported platforms.

Do not weaken these assumptions without an approved design change.

---

### Private Symbol Review

Confirm all production helpers are:

```c
static
```

except the internal initializer where source integration requires non-static visibility.

Review all extension-specific symbols, including:

```text
pblobPackFunc
pblobUnpackFunc
pblobParseFormat
pblobPutU16Le
pblobPutU16Be
pblobGetU16Le
pblobGetU16Be
pblobPutU32Le
pblobPutU32Be
pblobGetU32Le
pblobGetU32Be
pblobF16IsFinite
pblobF16IsInf
pblobF16IsNaN
pblobF32IsFinite
pblobF32IsInf
pblobF32IsNaN
pblobDecodeInt8
pblobCheckedSize
pblobJsonbInteger
pblobJsonbNumber
```

Confirm none is exported from the DLL.

Do not introduce a header to declare private symbols.

---

### Type and Naming Review

Review private types:

```c
PblobKind
PblobByteOrder
PblobFormat
```

Confirm names are consistent and concise.

Verify enum values and structure fields clearly represent:

```text
numeric kind
byte order
element width
```

Remove obsolete enum values or fields only if genuinely unused.

Do not rename stable public SQL functions or format strings.

Avoid broad stylistic renaming that obscures the reviewed history.

---

### Helper Contract Review

Review each private helper for a concise contract.

For helpers that receive `sqlite3_context *`, confirm the convention is documented and consistent:

```text
0 = success
nonzero = error already reported
```

Review:

* required inputs;
* output initialization;
* accepted ranges;
* ownership;
* failure behavior;
* whether an SQL error is set.

Remove misleading comments.

Do not add comments that merely translate individual statements into English.

---

### Callback Structure Review

Review `pblobPackFunc()` and `pblobUnpackFunc()` for clarity.

Confirm the callbacks visibly follow:

```text
NULL handling
type validation
format parsing
shared preparation
format dispatch
cleanup
```

Prefer private format-specific helpers over deeply nested duplicated logic.

Do not refactor working code solely to reduce line count.

The callback should remain easy to audit for validation order and ownership.

---

### Validation-Order Review

Confirm final validation order remains exactly as tested.

For packing:

```text
NULL
first argument type
format type
format value
JSON parse
root array
output size
element type
numeric extraction
target validation
result
```

For unpacking:

```text
NULL
first argument type
format type
format value
packed length
raw classification
conversion
JSON result
```

Ensure no final cleanup refactoring changed error precedence.

---

### JSON Integration Review

Confirm packing uses:

```c
jsonParseFuncArg()
jsonParseFree()
jsonbPayloadSize()
jsonbArrayCount()
```

Confirm unpacking uses:

```c
JsonString
jsonStringInit()
jsonAppendChar()
jsonPrintf()
jsonReturnString()
jsonStringReset()
JSON_SUBTYPE
```

Confirm there is no independent:

* JSON parser;
* array parser;
* JSON serializer;
* decimal parser.

Do not replace private SQLite internals with public JSON SQL calls.

---

### Integer Conversion Review

Confirm `int8` packing:

* accepts only integer JSONB node types;
* uses `pblobJsonbInteger()`;
* rejects values outside `-128..127`;
* performs no wrapping or clamping.

Confirm `int8` unpacking:

* accepts every byte;
* uses `pblobDecodeInt8()`;
* has no `char` signedness dependency.

Confirm exact full-domain tests remain active.

---

### Binary32 Conversion Review

Confirm packing path:

```text
JSON number
-> double
-> float
-> fp32_to_bits()
-> endian output
```

Confirm unpacking path:

```text
endian input
-> raw bits
-> finite classification
-> fp32_from_bits()
-> double
-> JSON formatting
```

Confirm:

* non-finite values are rejected;
* underflow is accepted;
* signed zero is preserved;
* no direct decimal-to-binary32 parser exists.

---

### Binary16 Conversion Review

Confirm packing path:

```text
JSON number
-> double
-> float
-> finite binary32 check
-> fp16_ieee_from_fp32_value()
-> finite binary16 check
-> endian output
```

Confirm unpacking path:

```text
endian input
-> raw binary16 bits
-> finite classification
-> fp16_ieee_to_fp32_value()
-> double
-> JSON formatting
```

Confirm:

* portable FP16 is mandatory;
* direct binary64-to-binary16 conversion is not used;
* subnormals and signed zero are preserved;
* infinity and NaN are rejected.

---

### Endian Review

Confirm all packed reads and writes use explicit byte helpers.

There must be no:

```c
*(uint16_t *)
*(uint32_t *)
```

access over packed buffers.

Confirm no packed data is emitted or read using native-order `memcpy()`.

Verify endian helper tests include unaligned buffers.

---

### Size and Bounds Review

Review all size arithmetic.

Confirm:

* multiplication is checked before execution;
* only widths 1, 2, and 4 are accepted;
* current `SQLITE_LIMIT_LENGTH` is enforced;
* array offsets cannot overflow;
* node boundaries are checked before access;
* BLOB loops cannot overrun the final element;
* payload lengths are checked before narrowing to `int`;
* result APIs receive validated lengths.

Do not retain redundant unchecked parallel calculations.

---

### Ownership Review

For pack paths, confirm:

* one exact output allocation;
* no per-element output allocation;
* output is freed on every error;
* ownership transfers exactly once;
* zero-length output is handled without false OOM.

For unpack paths, confirm:

* `JsonString` is initialized once;
* early failures reset owned state;
* finalization transfers ownership correctly;
* subtype is assigned only after success;
* no partial result survives failure.

Prefer explicit cleanup labels where they make ownership easier to verify.

---

### Error Message Review

Review all extension-defined errors for consistency.

Confirm messages are:

* function-specific;
* stable;
* concise;
* safe with embedded-NUL format input;
* consistent in capitalization and punctuation;
* zero-based for element indexes.

Confirm no temporary or internal helper wording leaks through public errors where a format-specific public error is required.

Do not expose raw arbitrary format bytes in messages.

---

### Dead-Code Review

Remove any remaining:

* placeholder messages;
* unreachable branches;
* obsolete stage comments;
* unused helper prototypes;
* unused constants;
* unused test operations;
* duplicate error-formatting code;
* temporary assertions no longer useful;
* abandoned alternative implementations.

Do not remove defensive runtime checks merely because tests currently cannot trigger them.

---

### Test-Only Code Review

Review the `test_pblob` operation dispatcher.

Confirm:

* one Tcl command is registered;
* operation names are stable;
* every operation validates argument count;
* malformed input returns `TCL_ERROR`;
* no operation exposes raw pointers;
* no operation reimplements production logic unnecessarily;
* independent oracle code is clearly test-only;
* exhaustive loops execute in C;
* test-only code is excluded from release preprocessing.

Remove obsolete operation aliases.

---

### Test Inventory Review

Confirm the final test modules exist and have distinct responsibilities:

```text
pblob.test
pblob_lowlevel.test
pblob_vectors.test
pblob_limits.test
pblob_fault.test
pblob_all.test
```

Confirm:

* every module runs independently;
* `pblob_all.test` contains no duplicate test bodies;
* test names are unique;
* limits and pragmas are restored;
* temporary databases and statements are cleaned up;
* fault tests recover after injected failures;
* vector tests do not require Python.

Do not collapse the modules back into one large test file.

---

### Vector Generator Review

Review:

```text
tool/gen_pblob_vectors.py
```

Confirm:

* deterministic output;
* fixed random seed;
* no timestamp variation;
* explicit endian handling;
* independent numeric oracles;
* correct binary64-to-binary32-to-binary16 modeling;
* `--check` mode;
* explicit write/update mode;
* nonzero exit on stale data;
* clear main docstring;
* ASCII-safe source where required by project policy.

Run:

```text
--check
```

twice.

Both runs must leave the tree unchanged.

---

### Generated File Review

Confirm all generated artifacts are current:

```text
SQLite amalgamation
committed vector data
bundled FP16 fragments where applicable
```

Run every available generation check.

Verify no generated file contains a manual edit that would be lost on regeneration.

Do not commit temporary generated comparison files.

---

### Build Instruction Review

Review all recorded build commands from Stage 15.

Confirm they are:

* exact;
* valid for the selected source tree;
* valid for Windows CMD and `nmake` where applicable;
* free of PowerShell-only syntax;
* explicit about required variables;
* reproducible from a clean tree.

Document relevant variables such as:

```text
TOP
TCLDIR
OPTS
CFLAGS
LDFLAGS
```

only when actually used.

Do not publish guessed targets or placeholders.

---

### Final Smoke Commands

Prepare a concise final smoke sequence for the release shell.

It must test:

```text
int8 pack/unpack
f2 little-endian pack/unpack
f2 big-endian pack/unpack
f4 little-endian pack/unpack
f4 big-endian pack/unpack
empty results
negative zero
non-finite rejection
JSON subtype composition
```

Use a SQL file for Windows shell validation rather than fragile nested `echo` commands containing `<` and `>`.

Avoid CMD escaping ambiguity.

---

### Final Regression Commands

Record the exact commands for:

```text
focused public tests
low-level tests
vector tests
limit tests
fault tests
aggregate pblob tests
full SQLite regression
JSON-disabled build
strict-warning build
sanitizer build
vector verification
release smoke
```

Do not include commands that were not actually run.

---

### Final Test Results

Produce a concise final table or structured summary containing:

```text
configuration
command
result
test count where available
runtime
skips
notes
```

Include:

* normal release build;
* testfixture build;
* focused tests;
* aggregate test;
* full SQLite regression;
* JSON-disabled build;
* strict-warning build;
* ASan;
* UBSan;
* vector verification;
* release smoke;
* export audit;
* dependency audit.

Clearly mark unsupported or unavailable configurations.

Do not report them as passed.

---

### Final Defect Record

List every defect found during Stages 12–16.

For each defect record:

```text
symptom
root cause
fix
regression test
affected files
validation result
```

If no defect was found in Stage 16, state that explicitly.

Do not omit defects merely because they were fixed before the final run.

---

### Final Design-Conformance Checklist

Produce a checklist confirming:

```text
one C module
no public header
no public C API
amalgamation-only
after json.c
uses private JSON internals
TEXT-only pack input
BLOB-only unpack input
five exact formats
raw headerless layout
portable FP16
explicit endian helpers
finite-only float formats
signed-zero preservation
subnormal support
JSON-subtyped unpack output
deterministic and innocuous registration
JSON-disabled exclusion
test-only hooks excluded from release
```

Every item must be supported by source or test evidence.

---

### Commit or Patch Organization

Prepare a clean final patch sequence.

Preferred logical grouping:

```text
Patch 1
Production implementation and amalgamation integration

Patch 2
Test-only low-level interface

Patch 3
Public and low-level Tcl tests

Patch 4
Independent vectors and generator

Patch 5
Limit, fault, aggregate, and smoke tests

Patch 6
Final integration notes and generated-file updates
```

If the repository prefers one squashed commit, provide a corresponding single commit message.

Do not preserve the original 16 development stages as 16 required final commits unless the project explicitly wants them.

The final history should be reviewable rather than mechanically mirroring development.

---

### Commit Message

Prepare a professional commit message.

The subject should be concise, for example:

```text
Add packed numeric BLOB SQL functions
```

The body should summarize:

* `pblob_pack()` and `pblob_unpack()`;
* supported formats;
* raw packed representation;
* JSON integration;
* portable FP16 dependency;
* test coverage.

Do not include unsupported performance claims.

Do not mention temporary staged placeholders.

---

### Reviewer Notes

Prepare concise reviewer notes identifying the highest-risk areas:

```text
private json.c dependency and source order
JSONB numeric payload extraction
signed 64-bit and JSON5 hexadecimal handling
binary64-to-binary32-to-binary16 path
non-finite rejection
JSON floating formatting and round-trip identity
size and ownership handling
test-only malformed JSONB infrastructure
```

For each area, point reviewers to the relevant source helper and test module.

Do not repeat the entire implementation plan.

---

### Final Tree Cleanliness

After all generation, builds, and tests:

* remove temporary databases;
* remove temporary vector outputs;
* remove sanitizer logs not intended for commit;
* remove compiler scratch files;
* remove generated comparison files;
* retain only intended generated artifacts.

Run the repository’s status command.

Classify every remaining modified or untracked file as:

```text
intended
generated and current
unrelated pre-existing
unexpected
```

No unexpected file may remain.

Do not discard unrelated user changes.

---

### Final Reproducibility Check

From the final source state:

1. Clean the build.
2. Regenerate required artifacts.
3. Run vector verification.
4. Build release artifacts.
5. Build testfixture.
6. Run focused aggregate tests.
7. Run release smoke tests.
8. Confirm repository status contains no unexpected generated differences.

This is the final validation cycle.

Do not rely solely on earlier Stage 15 results.

---

### Minimal Fix Policy

If final review exposes a defect:

1. Add or identify a reproducing test.
2. Make the smallest correction.
3. Run the focused reproducer.
4. Run `pblob_all.test`.
5. Run the affected build variants.
6. Run the full SQLite regression suite if production code changed.
7. Repeat final clean-tree verification.

Do not perform opportunistic refactoring after the final test cycle.

---

### Prohibited Work

Do not:

* add new formats;
* add new production SQL functions;
* add optional arguments;
* add format aliases;
* change packed layout;
* add metadata or headers;
* change floating conversion paths;
* enable native FP16;
* accept JSONB for packing;
* return JSONB from unpacking;
* create another C module;
* create `pblob.h`;
* export internal symbols;
* add a loadable-extension entry point;
* redesign the test structure;
* modify `json.c`;
* modify vendored FP16;
* refactor unrelated SQLite code;
* introduce a new build system;
* add unverified performance claims.

---

### Expected Deliverables

Provide:

1. Any minimal final source or test corrections.
2. Final cleaned `pblob.c`.
3. Final test inventory.
4. Final generated-file verification result.
5. Final vector verification result.
6. Final exact build commands.
7. Final exact test commands.
8. Final release smoke SQL and results.
9. Final full regression result.
10. Final JSON-disabled result.
11. Final strict-warning and sanitizer results.
12. Final export and dependency audit results.
13. Final defect record.
14. Final design-conformance checklist.
15. Final reviewer notes.
16. Final commit or patch organization.
17. Final commit message.
18. Final modified-file list.
19. Final clean-tree status classification.
20. Confirmation that:

    * no unsupported feature was added;
    * no placeholder or obsolete code remains;
    * all generated files are current;
    * all required tests pass;
    * all commands are reproducible;
    * release artifacts contain no test-only code;
    * no public C API or header exists;
    * the tree is ready for merge.

---

### Acceptance Criteria

Stage 16 is complete only when:

* final source comments describe implemented behavior accurately;
* no temporary stage wording remains;
* no placeholder or dead code remains;
* all production helpers have appropriate private visibility;
* public SQL API remains exactly two functions with five exact formats;
* packed representation remains raw and headerless;
* portable FP16 remains enforced;
* all validation, bounds, ownership, and error paths remain covered;
* final test modules are complete and independent;
* committed vector data passes deterministic verification;
* generated amalgamation and other generated files are current;
* exact release and test commands are documented;
* a final clean build succeeds;
* `pblob_all.test` passes from the final clean state;
* the full selected SQLite regression suite passes;
* release smoke tests pass;
* JSON-disabled builds pass;
* strict-warning builds remain clean;
* supported sanitizer builds remain clean;
* release artifacts contain no test-only symbols or dependencies;
* no accidental public export exists;
* reviewer notes identify the principal risk areas;
* the final patch or commit sequence is reviewable;
* the repository contains no unexpected modified or untracked files;
* no second C module, public C API, public header, or loadable-extension entry point exists.

Stop after satisfying these criteria. The implementation is ready for merge.
