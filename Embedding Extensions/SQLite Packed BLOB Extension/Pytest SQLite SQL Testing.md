---
url: https://chatgpt.com/c/6a677c95-da1c-83eb-8ee7-90281b215417
---

## 📗 SQLite Information Schema - Python Program Specification

> [!NOTE] Prompt
> 
> Help me create a specification for a single module Python program `sqlite_dbmeta`. This program will open a blank in-memory SQLite database and will run a number of metadata queries to provide comprehensive SQLite engine information used by Python.
> 
> I am thinking of
> 
> ```sql
> SELECT sqlite_version();
> SELECT name FROM pragma_module_list() ORDER BY name;
> SELECT name, builtin, type, enc, narg FROM pragma_function_list() ORDER BY name, narg;
> ```
> 
> What else can I query?

The program should report **three distinct layers**:

1. The Python runtime and `sqlite3` wrapper.
2. The linked SQLite library and its compiled capabilities.
3. The initial state of the newly opened `:memory:` connection and database.

Your three queries are a strong starting point. The most important additions are `sqlite_source_id()`, compile options, collations, available pragmas, connection limits, and `SQLITE_DBCONFIG` states.

### 1. Purpose

`sqlite_dbmeta` is a single-module Python command-line program that reports comprehensive metadata about the SQLite engine used by the executing Python interpreter.

The program shall:

1. Import Python’s standard-library `sqlite3` module.
2. Open a new blank in-memory SQLite database using `sqlite3.connect(":memory:")`.
3. Inspect:

   * the Python runtime;
   * the Python `sqlite3` wrapper;
   * the linked SQLite runtime library;
   * SQLite compile-time configuration;
   * registered SQL functions, virtual-table modules, collations, and pragmas;
   * connection runtime limits;
   * connection configuration options;
   * relevant initial pragma values.
4. Produce deterministic, human-readable output.
5. Optionally produce machine-readable JSON output.
6. Avoid modifying any persistent database or loading third-party extensions.

The program shall be implemented entirely in one file:

```text
sqlite_dbmeta.py
```

No third-party Python packages shall be required.

---

### 2. Scope

The report describes the SQLite environment available through the current Python process.

It does not attempt to describe:

* an arbitrary user database;
* SQLite installations used by other Python interpreters;
* the system `sqlite3` command-line executable;
* SQLite DLLs or shared libraries not loaded by the current process;
* extensions that could theoretically be loaded but are not currently registered;
* compile-time information unavailable through SQLite or Python APIs.

---

### 3. Invocation

The primary invocation shall be:

```text
python sqlite_dbmeta.py
```

Recommended command-line interface:

```text
python sqlite_dbmeta.py [OPTIONS]
```

Supported options should include:

```text
--format text
--format json
--output FILE
--compact
--help
```

#### `--format`

Select the output representation:

* `text`: structured human-readable report;
* `json`: machine-readable JSON document.

The default shall be `text`.

#### `--output FILE`

Write the report to `FILE` instead of standard output.

The output file shall be written using UTF-8 encoding without a byte-order mark.

#### `--compact`

For JSON output, suppress indentation and unnecessary whitespace.

For text output, this option may suppress explanatory notes while retaining all collected values.

---

### 4. General Collection Rules

The program shall create exactly one primary connection:

```python
connection = sqlite3.connect(":memory:")
```

The program shall not:

* create application tables;
* attach persistent databases;
* load extensions;
* change connection limits;
* change database configuration options;
* change pragma values merely to test whether they are writable.

Metadata collection shall be observational wherever possible.

Every metadata operation shall be isolated so that failure of one optional query does not prevent generation of the remaining report.

Each optional operation shall produce one of:

* a collected value;
* `unsupported`;
* `unavailable`;
* an error record containing the exception type and message.

Expected version-dependent absence shall not be treated as a fatal program error.

---

### 5. Report Structure

The report shall contain the following top-level sections:

1. Program
2. Operating Environment
3. Python Runtime
4. Python `sqlite3` Module
5. SQLite Runtime
6. SQLite Compile Options
7. Connection State
8. Database State
9. Runtime Limits
10. Database Connection Configuration
11. Registered Collations
12. Registered Virtual-Table Modules
13. Registered SQL Functions
14. Available Pragmas
15. Feature Summary
16. Collection Diagnostics

---

### 6. Program Metadata

The program shall report:

* program name;
* program version;
* report schema version;
* execution timestamp;
* output format.

Recommended fields:

```text
program.name
program.version
program.report_schema_version
program.generated_at
```

The timestamp should use ISO 8601 form and include the local UTC offset.

Example:

```text
2026-07-27T18:42:31+03:00
```

The report schema version shall be independent of the program version so that output consumers can detect structural changes.

---

### 7. Operating Environment

The program shall report:

* operating-system platform;
* platform release;
* platform version;
* machine architecture;
* processor description, when available;
* Python executable path;
* process architecture;
* native byte order.

Recommended sources include:

```python
platform.system()
platform.release()
platform.version()
platform.machine()
platform.processor()
sys.executable
struct.calcsize("P") * 8
sys.byteorder
```

Recommended fields:

```text
environment.platform
environment.platform_release
environment.platform_version
environment.machine
environment.processor
environment.process_bits
environment.byteorder
environment.python_executable
```

Environment values that are empty or unavailable shall be represented as `null` in JSON rather than omitted.

---

### 8. Python Runtime Metadata

The program shall report:

```python
sys.version
sys.version_info
sys.implementation.name
sys.implementation.version
platform.python_compiler()
platform.python_build()
```

Recommended fields:

```text
python.version
python.version_info
python.implementation
python.implementation_version
python.compiler
python.build
```

The complete `sys.version` string shall be preserved because it commonly identifies the compiler and build configuration used for Python.

---

### 9. Python `sqlite3` Module Metadata

The following module-level values shall be reported when present:

```python
sqlite3.__file__
sqlite3.apilevel
sqlite3.paramstyle
sqlite3.threadsafety
sqlite3.sqlite_version
sqlite3.sqlite_version_info
```

Recommended fields:

```text
python_sqlite3.module_path
python_sqlite3.apilevel
python_sqlite3.paramstyle
python_sqlite3.threadsafety
python_sqlite3.sqlite_version
python_sqlite3.sqlite_version_info
```

The deprecated `sqlite3.version` and `sqlite3.version_info` attributes shall not be required. When present, they may be reported in a clearly marked deprecated section, but their absence must not be considered an error.

#### Wrapper capability inventory

The program should report whether selected module and connection APIs are present.

Relevant connection methods include:

```text
backup
blobopen
create_aggregate
create_collation
create_function
create_window_function
deserialize
enable_load_extension
getconfig
getlimit
interrupt
iterdump
load_extension
serialize
setconfig
setlimit
set_authorizer
set_progress_handler
set_trace_callback
```

For each capability, report only whether the attribute exists and is callable. Do not invoke mutating or security-sensitive methods merely to test them.

Example JSON representation:

```json
{
  "backup": true,
  "blobopen": true,
  "create_window_function": true,
  "deserialize": true,
  "getconfig": true,
  "getlimit": true,
  "serialize": true
}
```

---

### 10. SQLite Runtime Identification

The program shall execute:

```sql
SELECT
    sqlite_version() AS version,
    sqlite_source_id() AS source_id;
```

`sqlite_version()` identifies the linked runtime SQLite version. `sqlite_source_id()` additionally identifies the exact SQLite source check-in and is therefore substantially more precise than the version number alone.

Recommended fields:

```text
sqlite.version
sqlite.source_id
```

The program shall compare:

```python
sqlite3.sqlite_version
```

with:

```sql
SELECT sqlite_version();
```

If the values differ, the report shall include a diagnostic warning. They normally describe the same runtime library.

---

### 11. SQLite Compile Options

The program shall execute:

```sql
SELECT compile_options
FROM pragma_compile_options()
ORDER BY compile_options;
```

An alternative compatible form is:

```sql
PRAGMA compile_options;
```

The table-valued form is preferred because it permits explicit ordering.

Compile options shall be preserved exactly as returned by SQLite. SQLite omits the leading `SQLITE_` prefix in this result.

The report shall contain:

1. The complete ordered list.
2. A parsed mapping for options of the form `NAME=VALUE`.
3. A derived feature summary.

Example parsed representation:

```json
{
  "ENABLE_FTS5": true,
  "ENABLE_JSON1": true,
  "MAX_ATTACHED": 10,
  "MAX_VARIABLE_NUMBER": 250000,
  "THREADSAFE": 1
}
```

Parsing rules:

* `NAME` becomes a boolean `true`.
* `NAME=INTEGER` becomes an integer where conversion is unambiguous.
* Other `NAME=VALUE` options retain the value as a string.
* The original unparsed option shall always remain available.

The parser shall not assume that absence of a compile option necessarily proves absence of a feature. Some SQLite features are enabled by default and may not have a positive `ENABLE_*` option.

---

### 12. Initial Connection State

The program shall report connection properties available through Python:

```python
connection.in_transaction
connection.isolation_level
connection.total_changes
```

When supported by the executing Python version, it shall also report:

```python
connection.autocommit
```

Recommended fields:

```text
connection.in_transaction
connection.isolation_level
connection.autocommit
connection.total_changes
```

The program shall distinguish Python transaction-control state from SQLite engine autocommit terminology.

The value of `connection.total_changes` should remain zero because metadata collection must not alter user tables.

---

### 13. Database Inventory

The program shall execute:

```sql
SELECT seq, name, file
FROM pragma_database_list()
ORDER BY seq;
```

This normally reports the blank in-memory `main` database and may report `temp` after SQLite has initialized the temporary schema.

The report shall not require `temp` to exist.

The `file` value for an in-memory database will normally be empty. It shall be reported exactly as returned rather than replaced with `:memory:`.

Recommended fields per database:

```text
seq
name
file
```

---

### 14. Initial Database and Connection Pragmas

The program shall collect a curated set of read-only pragma values.

#### Database representation

```sql
PRAGMA encoding;
PRAGMA page_size;
PRAGMA auto_vacuum;
PRAGMA application_id;
PRAGMA user_version;
PRAGMA schema_version;
```

#### Journaling and synchronization

```sql
PRAGMA journal_mode;
PRAGMA synchronous;
PRAGMA locking_mode;
PRAGMA journal_size_limit;
PRAGMA wal_autocheckpoint;
```

Some values are of limited practical significance for an in-memory database but remain useful for distinguishing runtime defaults.

#### Temporary storage and cache

```sql
PRAGMA temp_store;
PRAGMA cache_size;
PRAGMA cache_spill;
PRAGMA mmap_size;
PRAGMA soft_heap_limit;
PRAGMA hard_heap_limit;
```

#### SQL and schema behavior

```sql
PRAGMA foreign_keys;
PRAGMA defer_foreign_keys;
PRAGMA recursive_triggers;
PRAGMA trusted_schema;
PRAGMA writable_schema;
PRAGMA legacy_alter_table;
PRAGMA reverse_unordered_selects;
PRAGMA automatic_index;
PRAGMA ignore_check_constraints;
PRAGMA query_only;
PRAGMA read_uncommitted;
```

#### Integrity and diagnostic behavior

```sql
PRAGMA cell_size_check;
PRAGMA checkpoint_fullfsync;
PRAGMA fullfsync;
```

#### Deprecated or compatibility-sensitive pragmas

The following may be collected when available, but shall be placed in a compatibility subsection:

```sql
PRAGMA case_sensitive_like;
PRAGMA count_changes;
PRAGMA empty_result_callbacks;
PRAGMA legacy_file_format;
PRAGMA short_column_names;
PRAGMA full_column_names;
```

A pragma that returns no row shall be represented as unavailable. It shall not be assigned an invented `false` value.

#### Collection method

Scalar pragmas should be collected separately because:

* result column names are inconsistent;
* some return text while others return integers;
* some may return zero rows;
* availability varies between SQLite builds.

Each record should include:

```text
name
value
value_type
status
```

Example:

```json
{
  "name": "foreign_keys",
  "value": 0,
  "value_type": "integer",
  "status": "available"
}
```

---

### 15. Runtime Limits

When `Connection.getlimit()` is available, the program shall enumerate every module constant whose name begins with:

```text
SQLITE_LIMIT_
```

For each discovered constant:

1. Obtain its integer category value.

2. Call:

   ```python
   connection.getlimit(category)
   ```

3. Record the symbolic name, category number, and current limit.

Expected constants commonly include:

```text
SQLITE_LIMIT_LENGTH
SQLITE_LIMIT_SQL_LENGTH
SQLITE_LIMIT_COLUMN
SQLITE_LIMIT_EXPR_DEPTH
SQLITE_LIMIT_COMPOUND_SELECT
SQLITE_LIMIT_VDBE_OP
SQLITE_LIMIT_FUNCTION_ARG
SQLITE_LIMIT_ATTACHED
SQLITE_LIMIT_LIKE_PATTERN_LENGTH
SQLITE_LIMIT_VARIABLE_NUMBER
SQLITE_LIMIT_TRIGGER_DEPTH
SQLITE_LIMIT_WORKER_THREADS
```

The program shall discover these constants dynamically rather than hard-code the available set.

Recommended representation:

```json
{
  "name": "SQLITE_LIMIT_VARIABLE_NUMBER",
  "category": 9,
  "value": 250000
}
```

Unsupported categories shall be reported individually without aborting collection.

The program shall not call `setlimit()`.

---

### 16. Database Connection Configuration

When both of the following are available:

```python
connection.getconfig
```

and module constants beginning with:

```text
SQLITE_DBCONFIG_
```

the program shall enumerate the available connection configuration options.

For each discovered constant:

1. Obtain its numeric operation code.

2. Call:

   ```python
   connection.getconfig(operation)
   ```

3. Record:

   * symbolic name;
   * operation number;
   * current boolean value;
   * status.

Potential options include:

```text
SQLITE_DBCONFIG_DEFENSIVE
SQLITE_DBCONFIG_DQS_DDL
SQLITE_DBCONFIG_DQS_DML
SQLITE_DBCONFIG_ENABLE_FKEY
SQLITE_DBCONFIG_ENABLE_FTS3_TOKENIZER
SQLITE_DBCONFIG_ENABLE_LOAD_EXTENSION
SQLITE_DBCONFIG_ENABLE_QPSG
SQLITE_DBCONFIG_ENABLE_TRIGGER
SQLITE_DBCONFIG_ENABLE_VIEW
SQLITE_DBCONFIG_LEGACY_ALTER_TABLE
SQLITE_DBCONFIG_LEGACY_FILE_FORMAT
SQLITE_DBCONFIG_NO_CKPT_ON_CLOSE
SQLITE_DBCONFIG_RESET_DATABASE
SQLITE_DBCONFIG_TRIGGER_EQP
SQLITE_DBCONFIG_TRUSTED_SCHEMA
SQLITE_DBCONFIG_WRITABLE_SCHEMA
```

Availability depends on both the Python version and the SQLite version against which Python was built.

The program shall discover constants dynamically.

The program shall not call `setconfig()`.

`SQLITE_DBCONFIG_RESET_DATABASE` is operationally sensitive. It may be queried through `getconfig()` when supported, but shall never be enabled.

---

### 17. Registered Collations

The program shall execute:

```sql
SELECT seq, name
FROM pragma_collation_list()
ORDER BY name;
```

The output identifies collating sequences currently registered on the connection.

Common built-in collations include:

```text
BINARY
NOCASE
RTRIM
```

The program shall not assume that only those three exist.

Recommended fields:

```text
seq
name
```

The primary deterministic ordering shall be by `name`. The original `seq` value shall still be retained.

---

### 18. Registered Virtual-Table Modules

The program shall execute:

```sql
SELECT name
FROM pragma_module_list()
ORDER BY name;
```

This reports virtual-table modules registered on the current connection.

Depending on the build, results may include modules such as:

```text
fts3
fts4
fts5
json_each
json_tree
rtree
rtree_i32
dbstat
pragma
```

The presence of a module is stronger evidence of runtime availability than merely finding a related compile option.

The program shall not instantiate modules merely to test them.

---

### 19. Registered SQL Functions

The program shall execute:

```sql
SELECT
    name,
    builtin,
    type,
    enc,
    narg,
    flags
FROM pragma_function_list()
ORDER BY
    name,
    narg,
    type,
    enc,
    builtin,
    flags;
```

The `flags` column should be included. It contains the bit mask of SQLite function-property flags and provides information not present in the proposed five-column query.

Fields:

```text
name
builtin
type
enc
narg
flags
```

#### Interpretation

`builtin`:

* nonzero: registered as a built-in function;
* zero: application-defined or extension-provided registration.

`type` commonly distinguishes:

* scalar functions;
* aggregate functions;
* window functions.

`enc` identifies the preferred text encoding associated with the registration.

`narg` identifies arity:

* nonnegative values indicate a fixed number of arguments;
* `-1` indicates variadic arity.

`flags` shall always be retained numerically.

The program may additionally decode recognized public flags into symbolic names, including:

```text
SQLITE_DETERMINISTIC
SQLITE_DIRECTONLY
SQLITE_INNOCUOUS
SQLITE_SUBTYPE
SQLITE_RESULT_SUBTYPE
```

Flag decoding shall be additive: the original integer bit mask must remain in the report.

The program shall not assume that function names are unique. SQLite can register multiple implementations under the same name with different arities, encodings, types, or flags.

---

### 20. Available Pragmas

When supported, the program shall execute:

```sql
SELECT name
FROM pragma_pragma_list()
ORDER BY name;
```

This reports pragma names recognized by the current SQLite build.

The result shall be treated as a capability inventory, not as proof that every pragma is meaningful for every database or connection.

The program shall distinguish:

* available pragma names;
* the curated pragmas whose current values were successfully queried;
* pragmas that are available but deliberately not executed because they mutate state, perform expensive work, or require arguments.

The program shall not indiscriminately execute every pragma returned by `pragma_pragma_list()`.

Examples of pragmas that should not be invoked as generic scalar metadata queries include:

```text
integrity_check
quick_check
foreign_key_check
optimize
shrink_memory
wal_checkpoint
incremental_vacuum
table_info
table_xinfo
index_info
index_xinfo
index_list
foreign_key_list
function_list
module_list
pragma_list
compile_options
database_list
collation_list
```

Some are already handled through dedicated collectors; others require schema object names or can alter state.

---

### 21. Schema Inventory

Because the database is intentionally blank, the program may execute:

```sql
SELECT
    type,
    name,
    tbl_name,
    rootpage,
    sql
FROM sqlite_schema
ORDER BY type, name;
```

The expected result is empty.

This confirms that metadata collection did not create persistent schema objects.

The report shall not classify an empty result as an error.

The temporary schema may optionally be checked separately:

```sql
SELECT
    type,
    name,
    tbl_name,
    rootpage,
    sql
FROM temp.sqlite_schema
ORDER BY type, name;
```

Internal transient objects shall be reported when present but not treated as program-created application objects.

---

### 22. Feature Summary

The program shall derive a concise feature summary from multiple evidence sources.

Potential feature names include:

```text
column_metadata
dbstat
deserialize
fts3
fts4
fts5
geopoly
icu
json
loadable_extensions
math_functions
normalize
preupdate_hook
rtree
session
snapshot
soundex
statement_scanstatus
threadsafe
unlock_notify
update_delete_limit
```

Each derived feature shall include:

```text
status
evidence
notes
```

Recommended statuses:

```text
available
unavailable
indeterminate
```

Example:

```json
{
  "name": "fts5",
  "status": "available",
  "evidence": [
    "compile option ENABLE_FTS5",
    "registered module fts5"
  ]
}
```

#### Evidence rules

A feature may be classified as `available` based on direct runtime evidence, such as:

* a registered module;
* a registered SQL function;
* successful execution of a harmless feature-specific query;
* a corresponding Python API;
* an unambiguous compile option.

Absence of an `ENABLE_*` compile option shall not by itself classify a default-enabled SQLite feature as unavailable.

#### JSON feature detection

JSON support should be tested using a harmless prepared expression rather than relying exclusively on `ENABLE_JSON1`, because modern SQLite versions include JSON functionality by default and may not report an `ENABLE_JSON1` compile option.

Recommended probe:

```sql
SELECT json_valid('null');
```

Expected result:

```text
1
```

JSONB support may be tested separately when desired:

```sql
SELECT typeof(jsonb('null'));
```

Expected result when supported:

```text
blob
```

Failure with “no such function” shall be classified as unsupported, not as a fatal error.

#### Math-function detection

A harmless probe may be used:

```sql
SELECT pi();
```

Alternatively, inspect `pragma_function_list()` for the expected function registrations.

#### FTS and R-tree detection

Prefer module registration evidence:

```text
fts3
fts4
fts5
rtree
rtree_i32
```

No virtual table needs to be created.

---

### 23. Threading Information

The report shall include both:

```python
sqlite3.threadsafety
```

and the `THREADSAFE` compile option, when present.

These values use different numbering systems and must not be presented as interchangeable.

The report should derive a descriptive threading mode:

```text
single-thread
multi-thread
serialized
unknown
```

The derivation shall use documented mappings.

The report shall make clear that compile-time threading mode does not by itself describe every connection-level or application-level concurrency decision.

---

### 24. Deterministic Ordering

All collection outputs containing multiple rows shall use explicit ordering.

Required orderings include:

```sql
-- Compile options
ORDER BY compile_options

-- Databases
ORDER BY seq

-- Collations
ORDER BY name

-- Modules
ORDER BY name

-- Functions
ORDER BY name, narg, type, enc, builtin, flags

-- Pragmas
ORDER BY name

-- Schema
ORDER BY type, name
```

Python-discovered constants shall be ordered first by symbolic name.

Dictionary keys in JSON should be emitted with deterministic ordering where practical.

---

### 25. JSON Output Schema

The JSON document should use an object similar to:

```json
{
  "program": {},
  "environment": {},
  "python": {},
  "python_sqlite3": {
    "capabilities": {}
  },
  "sqlite": {
    "version": "",
    "source_id": "",
    "compile_options": {
      "raw": [],
      "parsed": {}
    },
    "features": []
  },
  "connection": {
    "state": {},
    "limits": [],
    "dbconfig": []
  },
  "database": {
    "list": [],
    "pragmas": [],
    "schema": []
  },
  "registrations": {
    "collations": [],
    "modules": [],
    "functions": [],
    "pragmas": []
  },
  "diagnostics": {
    "warnings": [],
    "unsupported": [],
    "errors": []
  }
}
```

The report schema shall favor stable arrays of records over dictionaries when duplicate names are possible.

In particular, registered SQL functions must be represented as an array because the same function name may have multiple registrations.

---

### 26. Text Output

Text output shall use numbered section headings corresponding to the logical report structure.

Example:

```text
SQLite Database Metadata
========================

1. Program
----------

Name:                  sqlite_dbmeta
Version:               1.0.0
Generated:             2026-07-27T18:42:31+03:00

2. Python Runtime
-----------------

Version:               3.14.6
Implementation:        CPython
Compiler:              MSC v.1944 64 bit (AMD64)

3. SQLite Runtime
-----------------

SQLite version:        3.x.x
SQLite source ID:      ...
DB-API threadsafety:   3
Compile THREADSAFE:    1
Threading mode:        serialized
```

Tabular sections shall use stable columns and shall not depend on terminal-specific formatting packages.

Long values, especially `sqlite_source_id`, shall not be truncated.

---

### 27. Error Handling

Fatal errors shall include:

* failure to import `sqlite3`;
* failure to create the in-memory connection;
* inability to write the requested output file;
* invalid command-line arguments;
* failure to serialize the final report.

Optional metadata-query failures shall not be fatal.

The process exit statuses should be:

```text
0  Report generated successfully.
1  Fatal runtime or collection failure.
2  Invalid command-line usage.
3  Output-file failure.
```

A report containing unsupported optional features may still exit with status `0`.

If nonfatal unexpected collection errors occurred, the text report shall include a visible diagnostics section.

---

### 28. Resource Management

The connection shall be closed reliably using a context manager or `try/finally`.

The program shall not leave:

* files;
* temporary directories;
* attached databases;
* loaded extensions;
* registered application callbacks;
* modified global SQLite state.

Standard output and standard error shall not be explicitly closed.

---

### 29. Security Requirements

The program shall:

* execute only static SQL statements defined in the source;
* perform no SQL interpolation;
* load no extension;
* accept no SQL text from command-line arguments;
* avoid printing environment variables;
* avoid searching arbitrary filesystem locations for SQLite libraries;
* avoid using `ctypes` to call undocumented or unexposed SQLite APIs.

The report may include `sqlite3.__file__` and `sys.executable`, even though these expose local paths, because they are directly relevant to identifying the inspected runtime.

An optional future `--redact-paths` switch may replace local paths with file names.

---

### 30. Internal Design

The single module should remain internally structured.

Recommended components:

```text
main()
parse_arguments()
collect_report()
collect_program_metadata()
collect_environment_metadata()
collect_python_metadata()
collect_python_sqlite_metadata()
collect_sqlite_identity()
collect_compile_options()
collect_connection_state()
collect_database_list()
collect_pragma_values()
collect_limits()
collect_dbconfig()
collect_collations()
collect_modules()
collect_functions()
collect_pragma_list()
collect_schema()
derive_features()
derive_threading_mode()
render_text()
render_json()
write_output()
```

A small generic SQL helper may be used:

```python
query_rows(connection, sql)
query_scalar(connection, sql)
```

Collectors shall return ordinary Python data structures rather than print directly.

Rendering shall be separated from collection.

---

### 31. Compatibility

The program should support maintained CPython versions that provide the standard-library `sqlite3` module.

Version-dependent Python APIs shall be discovered using `hasattr()` and symbolic constant enumeration.

The program shall not infer API support solely from `sys.version_info`.

SQLite table-valued pragma functions may be unavailable on sufficiently old SQLite versions. For important metadata, the collector should support a fallback from:

```sql
SELECT ... FROM pragma_name()
```

to:

```sql
PRAGMA name;
```

Where no practical fallback exists, the section shall be marked unsupported.

---

### 32. Minimum Required Query Set

The minimum complete implementation shall execute or attempt the following queries:

```sql
SELECT sqlite_version(), sqlite_source_id();

SELECT compile_options
FROM pragma_compile_options()
ORDER BY compile_options;

SELECT seq, name, file
FROM pragma_database_list()
ORDER BY seq;

SELECT seq, name
FROM pragma_collation_list()
ORDER BY name;

SELECT name
FROM pragma_module_list()
ORDER BY name;

SELECT name, builtin, type, enc, narg, flags
FROM pragma_function_list()
ORDER BY name, narg, type, enc, builtin, flags;

SELECT name
FROM pragma_pragma_list()
ORDER BY name;

SELECT type, name, tbl_name, rootpage, sql
FROM sqlite_schema
ORDER BY type, name;
```

It shall also query the curated scalar pragmas, runtime limits, and database connection configuration values described above.

---

### 33. Test Requirements

Tests should verify at least the following:

#### Basic execution

* The program runs without arguments.
* It opens an in-memory database.
* It exits successfully.
* Text output is nonempty.
* JSON output parses successfully.

#### Runtime identification

* SQL `sqlite_version()` equals `sqlite3.sqlite_version`.
* `sqlite_source_id()` is nonempty.
* At least one compile option is normally returned, while permitting unusual builds with none.

#### Registration inventories

* Function rows retain duplicate names.
* Function rows include the `flags` field.
* Modules are sorted.
* Collations are sorted.
* Pragmas are sorted when supported.

#### Limits and DB configuration

* Every discovered `SQLITE_LIMIT_*` constant is attempted.
* No limit is modified.
* Every discovered `SQLITE_DBCONFIG_*` constant is attempted when `getconfig()` exists.
* No configuration option is modified.

#### Blank-database behavior

* The persistent schema remains empty.
* `connection.total_changes` remains zero.
* No filesystem database is created.

#### Compatibility

* Missing `getlimit()` is handled.
* Missing `getconfig()` is handled.
* Missing `pragma_pragma_list()` is handled.
* Unsupported scalar pragmas do not abort the report.
* Missing JSON or math functions do not abort the report.

#### Output

* JSON output uses stable field types.
* Duplicate function registrations are not overwritten.
* UTF-8 output is valid.
* Output-file errors produce the documented exit status.
* Deterministic sections are emitted in sorted order.

---

### 34. Non-Goals

The initial implementation shall not:

* inspect an arbitrary database path;
* benchmark SQLite;
* run integrity checks;
* create test tables or virtual tables;
* load external extensions;
* discover the physical SQLite library through process-memory inspection;
* compare the Python SQLite library with the system SQLite executable;
* invoke private CPython implementation details;
* expose a reusable library API beyond the functions needed internally by the module.

Those capabilities may be considered separately after the metadata format is stable.

The highest-value additions to your original list are therefore:

```sql
SELECT sqlite_version(), sqlite_source_id();

SELECT compile_options
FROM pragma_compile_options()
ORDER BY compile_options;

SELECT seq, name
FROM pragma_collation_list()
ORDER BY name;

SELECT name
FROM pragma_pragma_list()
ORDER BY name;

SELECT seq, name, file
FROM pragma_database_list()
ORDER BY seq;
```

For `pragma_function_list()`, include `flags`; omitting it discards determinism, direct-only, innocuous, subtype, and related registration metadata. SQLite documents `sqlite_source_id()` as identifying the exact source check-in, while `PRAGMA compile_options` reports the options used for the running SQLite build. ([SQLite][1])

SQL alone cannot provide the full picture. Python exposes the runtime library version, DB-API thread-safety mapping, per-connection runtime limits through `getlimit()`, and—on newer Python versions—connection configuration through `getconfig()`. These should be first-class report sections rather than forced into SQL queries. ([Python documentation][2])

[1]: https://www.sqlite.org/lang_corefunc.html "Built-In Scalar SQL Functions"
[2]: https://docs.python.org/3/library/sqlite3.html "sqlite3 — DB-API 2.0 interface for SQLite databases — Python 3.14.6 documentation"

---
---

## 📗 Refine Queries

> [!NOTE] Prompt
> 
> I will go with
> 
> ```sql
> SELECT sqlite_version(), sqlite_source_id();
> SELECT compile_options FROM pragma_compile_options() ORDER BY compile_options;
> SELECT seq, name, file FROM pragma_database_list() ORDER BY seq;
> SELECT seq, name FROM pragma_collation_list() ORDER BY name;
> SELECT name FROM pragma_module_list() ORDER BY name;
> SELECT name, builtin, type, enc, narg FROM pragma_function_list() ORDER BY name, builtin, narg;
> SELECT name FROM pragma_pragma_list() ORDER BY name;
> ```
> 
> Nothing else. I do not want any info provided by Python, system info etc. Literally, results of these queries ONLY. Now, what would be a convenient format for output inspection ?

For manual inspection, use a **sectioned plain-text report with aligned tables**. It is easier to scan than raw JSON and preserves the row/column structure of each query.

Recommended structure:

```text
SQLite Runtime
==============

sqlite_version()  sqlite_source_id()
----------------  ----------------------------------------------------------------
3.50.4            2025-07-30 19:33:53 ...

Compile Options
===============

compile_options
----------------------------------------
ATOMIC_INTRINSICS=1
COMPILER=msvc-1944
DEFAULT_AUTOVACUUM
ENABLE_FTS5
ENABLE_RTREE
THREADSAFE=1

Databases
=========

seq  name  file
---  ----  ----------------
0    main

Collations
==========

seq  name
---  ------
0    RTRIM
1    NOCASE
2    BINARY

Modules
=======

name
----------------
fts5
json_each
json_tree
pragma
rtree

Functions
=========

name          builtin  type  enc   narg
------------  -------  ----  ----  ----
abs           1        s     utf8  1
avg           1        w     utf8  1
coalesce      1        s     utf8  -1
json_extract  1        s     utf8  -1

Pragmas
=======

name
------------------------
analysis_limit
application_id
auto_vacuum
automatic_index
```

### Formatting rules

Use the query result column names as table headers. Separate sections by a blank line and a prominent heading. Calculate column widths from the returned values, but cap very long columns only if necessary.

I would not truncate `sqlite_source_id()` or `file`; these are identification fields and should remain complete.

Represent SQL values consistently:

```text
NULL
0
1
-1
```

Do not translate values into descriptions. For example, preserve `type = s` and `enc = utf8` exactly as returned.

### Best output modes

A practical program could support two formats:

```text
sqlite_dbmeta
sqlite_dbmeta --format json
```

The default should be the aligned text report above.

JSON is useful for comparison, automated testing, and archival:

```json
{
  "sqlite": [
    {
      "sqlite_version()": "3.50.4",
      "sqlite_source_id()": "2025-07-30 19:33:53 ..."
    }
  ],
  "compile_options": [
    {
      "compile_options": "ATOMIC_INTRINSICS=1"
    },
    {
      "compile_options": "ENABLE_FTS5"
    }
  ],
  "databases": [
    {
      "seq": 0,
      "name": "main",
      "file": ""
    }
  ],
  "collations": [],
  "modules": [],
  "functions": [],
  "pragmas": []
}
```

For the JSON property names, I would use stable section names rather than SQL expressions:

```text
runtime
compile_options
databases
collations
modules
functions
pragmas
```

The runtime record could similarly use cleaner keys:

```json
{
  "runtime": {
    "version": "3.50.4",
    "source_id": "2025-07-30 19:33:53 ..."
  }
}
```

This does not add information; it only makes the query results easier to consume.

### Recommendation

Use:

* **aligned sectioned text** as the default;
* **JSON** as an optional machine-readable format;
* no explanatory prose, derived values, counts, or Python/system metadata.

For especially large function output, an additional `--format tsv` mode could be useful, but it is not necessary for the initial program.

---
---

## 📗 Scope Refinement

> [!NOTE] Prompt
> 
> I will go with aligned sectioned text. Add counts for uniquely named functions and modules.

Add a summary line immediately below the **Modules** and **Functions** headings.

### Output Format

The program shall emit a sectioned plain-text report containing aligned tables.

Each section shall:

1. Start with a descriptive heading.
2. Underline the heading with `=`.
3. Optionally include a summary line.
4. Include one blank line before the table.
5. Render the query result as an aligned table.
6. Preserve all values exactly as returned by SQLite.

Example:

```text
SQLite Runtime
==============

sqlite_version()  sqlite_source_id()
----------------  ----------------------------------------------------------------
3.50.4            2025-07-30 19:33:53 ...

Compile Options
===============

compile_options
----------------------------------------
ATOMIC_INTRINSICS=1
COMPILER=msvc-1944
ENABLE_FTS5
ENABLE_RTREE
THREADSAFE=1

Databases
=========

seq  name  file
---  ----  ----------------
0    main

Collations
==========

seq  name
---  ------
0    RTRIM
1    NOCASE
2    BINARY

Modules
=======

Modules: 8

name
----------------
dbstat
fts5
json_each
json_tree
pragma
rtree
rtree_i32
zipfile

Functions
=========

Functions: 129 unique names, 178 registrations

name          builtin  type  enc   narg
------------  -------  ----  ----  ----
abs           1        s     utf8  1
avg           1        w     utf8  1
coalesce      1        s     utf8  -1
json_extract  1        s     utf8  -1
like          1        s     utf8  2
like          1        s     utf8  3

Pragmas
=======

name
------------------------
analysis_limit
application_id
auto_vacuum
automatic_index
```

### Module Count

The module count shall be the number of rows returned by:

```sql
SELECT name
FROM pragma_module_list()
ORDER BY name;
```

Because each row represents one module name, this is also the number of uniquely named modules.

Equivalent calculation:

```python
module_count = len(module_rows)
```

The summary line shall use:

```text
Modules: <count>
```

### Function Counts

The function report shall include two counts:

* **unique names**: the number of distinct values in the `name` column;
* **registrations**: the total number of rows returned by the query.

Equivalent calculation:

```python
function_registration_count = len(function_rows)
function_name_count = len({row["name"] for row in function_rows})
```

The summary line shall use:

```text
Functions: <unique-count> unique names, <row-count> registrations
```

Multiple rows with the same function name shall remain visible because SQLite may register different implementations by:

* arity;
* function type;
* encoding;
* built-in status.

The count shall therefore not collapse or otherwise modify the function table.

### Value Formatting

SQL values shall be represented as follows:

```text
NULL
0
1
-1
```

Empty strings shall remain empty table cells.

Values shall not be translated, decoded, summarized, or annotated.

### Column Alignment

Column widths shall be calculated from:

* the column heading;
* every rendered value in that column.

Text values shall be left-aligned.

Integer values shall be right-aligned.

No column shall be truncated. In particular, the following values shall always be shown in full:

* `sqlite_source_id()`;
* database file names;
* compile options;
* function names;
* pragma names.

For modules, a separate “unique names” count would be redundant because `pragma_module_list()` already returns one row per module name.

---
---

## 📗 Summary Table

> [!NOTE] Prompt
> 
> No summary lines. Summary table going first reporting sqlite version, source_id and counts.

Use a compact **Summary** table first, followed by the seven raw query-result sections without per-section summaries.

The program shall emit a sectioned plain-text report containing aligned tables.

The first section shall be a derived summary table. All subsequent sections shall contain only the unmodified results of the specified SQL queries.

### Summary

The summary table shall report:

* SQLite version;
* SQLite source ID;
* number of compile options;
* number of databases;
* number of collations;
* number of uniquely named modules;
* number of uniquely named functions;
* total number of function registrations;
* number of pragmas.

Example:

```text
Summary
=======

item                     value
-----------------------  ------------------------------------------------------------
SQLite version           3.50.4
SQLite source ID         2025-07-30 19:33:53 ...
Compile options          48
Databases                1
Collations               3
Modules                   8
Function names           129
Function registrations   178
Pragmas                   71
```

The summary values shall be derived exclusively from the results of the seven specified queries.

#### Count Definitions

`Compile options` is the total number of rows returned by:

```sql
SELECT compile_options
FROM pragma_compile_options()
ORDER BY compile_options;
```

`Databases` is the total number of rows returned by:

```sql
SELECT seq, name, file
FROM pragma_database_list()
ORDER BY seq;
```

`Collations` is the total number of rows returned by:

```sql
SELECT seq, name
FROM pragma_collation_list()
ORDER BY name;
```

`Modules` is the number of distinct values in the module query's `name` column.

Because `pragma_module_list()` normally returns one row per module name, this will ordinarily equal the row count.

`Function names` is the number of distinct values in the function query's `name` column.

`Function registrations` is the total number of rows returned by the function query.

`Pragmas` is the total number of rows returned by:

```sql
SELECT name
FROM pragma_pragma_list()
ORDER BY name;
```

The summary shall not contain any information obtained from Python APIs, operating-system APIs, environment variables, filesystem inspection, or additional SQL queries.

### SQLite Runtime

```text
SQLite Runtime
==============

sqlite_version()  sqlite_source_id()
----------------  ----------------------------------------------------------------
3.50.4            2025-07-30 19:33:53 ...
```

Query:

```sql
SELECT sqlite_version(), sqlite_source_id();
```

### Compile Options

```text
Compile Options
===============

compile_options
----------------------------------------
ATOMIC_INTRINSICS=1
COMPILER=msvc-1944
ENABLE_FTS5
ENABLE_RTREE
THREADSAFE=1
```

Query:

```sql
SELECT compile_options
FROM pragma_compile_options()
ORDER BY compile_options;
```

### Databases

```text
Databases
=========

seq  name  file
---  ----  ----------------
  0  main
```

Query:

```sql
SELECT seq, name, file
FROM pragma_database_list()
ORDER BY seq;
```

### Collations

```text
Collations
==========

seq  name
---  ------
  0  RTRIM
  1  NOCASE
  2  BINARY
```

Query:

```sql
SELECT seq, name
FROM pragma_collation_list()
ORDER BY name;
```

### Modules

```text
Modules
=======

name
----------------
dbstat
fts5
json_each
json_tree
pragma
rtree
rtree_i32
zipfile
```

Query:

```sql
SELECT name
FROM pragma_module_list()
ORDER BY name;
```

### Functions

```text
Functions
=========

name          builtin  type  enc   narg
------------  -------  ----  ----  ----
abs                 1  s     utf8     1
avg                 1  w     utf8     1
coalesce            1  s     utf8    -1
json_extract        1  s     utf8    -1
like                1  s     utf8     2
like                1  s     utf8     3
```

Query:

```sql
SELECT name, builtin, type, enc, narg
FROM pragma_function_list()
ORDER BY name, builtin, narg;
```

### Pragmas

```text
Pragmas
=======

name
------------------------
analysis_limit
application_id
auto_vacuum
automatic_index
```

Query:

```sql
SELECT name
FROM pragma_pragma_list()
ORDER BY name;
```

### Formatting Rules

Each section shall:

1. Begin with a heading.
2. Underline the heading with `=`.
3. Include one blank line before its table.
4. Render column headings exactly as returned by SQLite.
5. Render all rows returned by the corresponding query.
6. Preserve the query-defined row order.
7. Contain no explanatory prose or count line.

The summary table is the only derived section.

Text values shall be left-aligned.

Integer values shall be right-aligned.

Column widths shall be calculated from the column heading and every rendered value in that column.

No value shall be truncated.

SQL `NULL` shall be rendered as:

```text
NULL
```

Empty strings shall remain empty cells.

This gives the report an immediately useful inventory at the top while keeping every detailed section as a clean rendering of its query result.

---
---

## 📗 `sqlite_dbmeta` Implementation Specification

> [!NOTE] Prompt
> 
> Generate a full spec suitable for implementation by AI.

Below is a complete implementation specification constrained to the exact SQLite metadata queries and output structure established above.

### 1. Purpose

Implement a single-module Python command-line program named `sqlite_dbmeta.py`.

The program shall:

1. Open a new blank in-memory SQLite database.
2. Execute a fixed set of SQLite metadata queries.
3. Derive a compact summary exclusively from those query results.
4. Print a deterministic, sectioned, aligned plain-text report.
5. Report only SQLite engine metadata exposed by the specified SQL queries.

The program shall not report Python runtime information, Python `sqlite3` module information, operating-system information, filesystem information, environment variables, or connection-specific database inventory.

---

### 2. Deliverable

Create exactly one source file:

```text
sqlite_dbmeta.py
```

No additional modules, packages, configuration files, templates, or generated files are required.

The program shall use only the Python standard library.

---

### 3. Runtime Requirements

The implementation shall use Python’s standard-library `sqlite3` module.

The program shall create one SQLite connection:

```python
sqlite3.connect(":memory:")
```

The database shall remain blank.

The program shall not:

* create tables;
* create indexes;
* create views;
* create triggers;
* create virtual tables;
* attach databases;
* load extensions;
* register Python-defined SQL functions;
* register Python-defined collations;
* change pragma values;
* change connection configuration;
* execute arbitrary user-provided SQL.

---

### 4. Scope of Reported Information

The report shall contain only information obtained from these six SQL queries:

```sql
SELECT sqlite_version(), sqlite_source_id();

SELECT name
FROM pragma_module_list()
ORDER BY name;

SELECT seq, name
FROM pragma_collation_list()
ORDER BY name;

SELECT name, builtin, type, enc, narg
FROM pragma_function_list()
ORDER BY name, builtin, narg;

SELECT name
FROM pragma_pragma_list()
ORDER BY name;

SELECT compile_options
FROM pragma_compile_options()
ORDER BY compile_options;
```

No additional SQL metadata query shall be executed.

In particular, the program shall not query:

```sql
pragma_database_list()
sqlite_schema
temp.sqlite_schema
```

or any scalar pragma value.

---

### 5. Report Structure

The program shall print the following sections in exactly this order:

1. Summary
2. Modules
3. Collations
4. Functions
5. Pragmas
6. Compile Options

The SQLite version and source ID shall appear only in the Summary section.

There shall be no separate SQLite Runtime section.

---

### 6. Summary Section

The Summary section shall be derived exclusively from the six query result sets.

It shall contain the following rows in exactly this order:

1. SQLite version
2. SQLite source ID
3. Module names
4. Collations
5. Function names
6. Function registrations
7. Pragmas
8. Compile options

Example:

```text
Summary
=======

item                    value
----------------------  ------------------------------------------------------------
SQLite version          3.50.4
SQLite source ID        2025-07-30 19:33:53 ...
Module names            8
Collations              3
Function names          129
Function registrations  178
Pragmas                 71
Compile options         48
```

#### SQLite version

Use the first column returned by:

```sql
SELECT sqlite_version(), sqlite_source_id();
```

#### SQLite source ID

Use the second column returned by the same query.

The source ID shall be printed in full and shall not be truncated.

#### Module names

Count the number of distinct non-null `name` values returned by:

```sql
SELECT name
FROM pragma_module_list()
ORDER BY name;
```

Although SQLite normally returns one row per module name, the implementation shall explicitly calculate the distinct-name count.

Equivalent logic:

```python
len({row["name"] for row in module_rows if row["name"] is not None})
```

#### Collations

Count the total number of rows returned by:

```sql
SELECT seq, name
FROM pragma_collation_list()
ORDER BY name;
```

Do not derive a distinct-name count for collations.

#### Function names

Count the number of distinct non-null `name` values returned by:

```sql
SELECT name, builtin, type, enc, narg
FROM pragma_function_list()
ORDER BY name, builtin, narg;
```

Equivalent logic:

```python
len({row["name"] for row in function_rows if row["name"] is not None})
```

#### Function registrations

Count the total number of rows returned by the function query.

Multiple rows having the same function name are separate registrations and shall all contribute to this count.

#### Pragmas

Count the total number of rows returned by:

```sql
SELECT name
FROM pragma_pragma_list()
ORDER BY name;
```

#### Compile options

Count the total number of rows returned by:

```sql
SELECT compile_options
FROM pragma_compile_options()
ORDER BY compile_options;
```

---

### 7. Modules Section

Execute:

```sql
SELECT name
FROM pragma_module_list()
ORDER BY name;
```

Render the complete result as an aligned table.

Example:

```text
Modules
=======

name
--------
dbstat
fts5
json_each
json_tree
pragma
rtree
rtree_i32
```

The section shall contain:

* the heading;
* the heading underline;
* one blank line;
* the table header;
* the separator row;
* every query result row.

It shall not contain:

* a module count;
* explanatory prose;
* annotations;
* derived capability descriptions.

---

### 8. Collations Section

Execute:

```sql
SELECT seq, name
FROM pragma_collation_list()
ORDER BY name;
```

Render the complete result as an aligned table.

Example:

```text
Collations
==========

seq  name
---  ------
  2  BINARY
  1  NOCASE
  0  RTRIM
```

The query-defined ordering by `name` shall be preserved.

The `seq` column shall not be re-sorted numerically.

---

### 9. Functions Section

Execute:

```sql
SELECT name, builtin, type, enc, narg
FROM pragma_function_list()
ORDER BY name, builtin, narg;
```

Render the complete result as an aligned table.

Example:

```text
Functions
=========

name          builtin  type  enc   narg
------------  -------  ----  ----  ----
abs                 1  s     utf8     1
avg                 1  w     utf8     1
coalesce            1  s     utf8    -1
json_extract        1  s     utf8    -1
like                1  s     utf8     2
like                1  s     utf8     3
```

All rows shall be preserved.

The implementation shall not:

* collapse duplicate function names;
* merge overloads;
* group functions;
* decode `type`;
* decode `enc`;
* interpret `builtin`;
* interpret `narg`;
* sort using any columns beyond those specified in the SQL query.

The function query intentionally omits the `flags` column. The implementation shall not add it.

---

### 10. Pragmas Section

Execute:

```sql
SELECT name
FROM pragma_pragma_list()
ORDER BY name;
```

Render the complete result as an aligned table.

Example:

```text
Pragmas
=======

name
------------------------
analysis_limit
application_id
auto_vacuum
automatic_index
```

The implementation shall not execute any pragma listed in the result.

The section is an inventory of pragma names only.

---

### 11. Compile Options Section

Execute:

```sql
SELECT compile_options
FROM pragma_compile_options()
ORDER BY compile_options;
```

Render the complete result as an aligned table.

Example:

```text
Compile Options
===============

compile_options
----------------------------------------
ATOMIC_INTRINSICS=1
COMPILER=msvc-1944
ENABLE_FTS5
ENABLE_RTREE
THREADSAFE=1
```

Compile-option values shall be printed exactly as returned by SQLite.

The implementation shall not:

* add an `SQLITE_` prefix;
* parse `NAME=VALUE`;
* group compile options;
* interpret feature availability;
* normalize case;
* remove duplicates;
* add descriptions.

---

### 12. SQL Definitions

Store the SQL statements as fixed module-level constants.

Recommended structure:

```python
SQL_RUNTIME = """
SELECT sqlite_version(), sqlite_source_id();
"""

SQL_MODULES = """
SELECT name
FROM pragma_module_list()
ORDER BY name;
"""

SQL_COLLATIONS = """
SELECT seq, name
FROM pragma_collation_list()
ORDER BY name;
"""

SQL_FUNCTIONS = """
SELECT name, builtin, type, enc, narg
FROM pragma_function_list()
ORDER BY name, builtin, narg;
"""

SQL_PRAGMAS = """
SELECT name
FROM pragma_pragma_list()
ORDER BY name;
"""

SQL_COMPILE_OPTIONS = """
SELECT compile_options
FROM pragma_compile_options()
ORDER BY compile_options;
"""
```

The statements shall remain static.

The implementation shall not use string interpolation, parameter substitution, or dynamically constructed SQL.

---

### 13. Query Execution

Each query shall be executed exactly once.

Recommended execution order:

1. SQLite runtime query
2. Modules query
3. Collations query
4. Functions query
5. Pragmas query
6. Compile-options query

This order matches the report’s logical data dependencies.

The runtime result shall be retrieved as one row.

Every inventory query shall be fully materialized before rendering.

Recommended representation:

```python
runtime_row = cursor.execute(SQL_RUNTIME).fetchone()
module_rows = cursor.execute(SQL_MODULES).fetchall()
collation_rows = cursor.execute(SQL_COLLATIONS).fetchall()
function_rows = cursor.execute(SQL_FUNCTIONS).fetchall()
pragma_rows = cursor.execute(SQL_PRAGMAS).fetchall()
compile_option_rows = cursor.execute(SQL_COMPILE_OPTIONS).fetchall()
```

The implementation may use one cursor or separate cursors.

A single cursor is sufficient because each result is fully fetched before the next query is executed.

---

### 14. Row Representation

Set the connection row factory to:

```python
sqlite3.Row
```

This allows collectors and renderers to access values by column name while preserving SQLite’s returned column names.

Example:

```python
connection.row_factory = sqlite3.Row
```

The generic table renderer shall obtain column names from:

```python
row.keys()
```

or from the cursor description captured immediately after query execution.

Because an empty result contains no row from which to obtain keys, the preferred query helper shall capture column names from `cursor.description`.

Recommended result structure:

```python
@dataclass(frozen=True)
class QueryResult:
    columns: tuple[str, ...]
    rows: tuple[tuple[object, ...], ...]
```

Use of `dataclasses` is optional.

An equivalent tuple- or dictionary-based internal representation is acceptable.

The result representation shall preserve:

* column order;
* row order;
* original SQLite values.

---

### 15. Column Names

For detailed sections, render column headings exactly as returned by SQLite.

Expected headings are:

#### Modules

```text
name
```

#### Collations

```text
seq
name
```

#### Functions

```text
name
builtin
type
enc
narg
```

#### Pragmas

```text
name
```

#### Compile Options

```text
compile_options
```

For the runtime query, the returned expression names may be:

```text
sqlite_version()
sqlite_source_id()
```

These raw headings are not rendered because the runtime result is incorporated into the Summary section.

---

### 16. Text Rendering

The report shall be plain text.

It shall not use:

* Markdown tables;
* box-drawing characters;
* ANSI colors;
* terminal-control sequences;
* Unicode alignment glyphs;
* external formatting packages.

Only ordinary ASCII characters shall be used for table structure:

```text
=
-
space
```

SQLite-returned text values may contain Unicode and shall be preserved.

---

### 17. Section Headings

Each section heading shall be followed by an underline consisting of `=` repeated to the exact character length of the heading.

Examples:

```text
Summary
=======

Modules
=======

Collations
==========

Functions
=========

Pragmas
=======

Compile Options
===============
```

There shall be exactly one blank line between the underline and the table.

There shall be exactly one blank line between the end of one section and the next section heading.

The report shall end with one newline.

---

### 18. Table Layout

Every table shall contain:

1. one header row;
2. one separator row;
3. zero or more data rows.

Columns shall be separated by exactly two spaces.

Example:

```text
name          builtin  type  enc   narg
------------  -------  ----  ----  ----
abs                 1  s     utf8     1
```

No leading indentation shall be added to the table as a whole.

---

### 19. Column Width Calculation

For each column, calculate the display width as the maximum of:

* the rendered header width;
* the rendered width of every value in that column.

Equivalent rule:

```python
width = max(
    len(rendered_header),
    *(len(rendered_value) for rendered_value in column_values),
)
```

For an empty result set, the width shall equal the header width.

No arbitrary minimum width is required.

No maximum width shall be imposed.

No value shall be truncated, abbreviated, wrapped, or replaced with an ellipsis.

---

### 20. Value Rendering

Render SQLite values according to the following rules.

#### Null

Python `None`, representing SQL `NULL`, shall be rendered as:

```text
NULL
```

#### Integer

Integers shall be rendered using ordinary base-10 notation:

```text
0
1
-1
250
```

#### Floating-point

Although none of the specified columns normally return floating-point values, a generic renderer may use:

```python
str(value)
```

#### Text

Text shall be rendered exactly as returned.

The implementation shall not:

* quote strings;
* escape spaces;
* change case;
* trim leading or trailing whitespace;
* normalize Unicode.

#### Blob

The specified queries are not expected to return BLOB values.

A generic renderer may represent an unexpected byte value using hexadecimal, but this is not required.

---

### 21. Alignment

Text-valued columns shall be left-aligned.

Integer-valued columns shall be right-aligned.

The alignment decision should be made per column rather than per individual cell.

A column shall be right-aligned when every non-null value in that column is an integer.

Otherwise, it shall be left-aligned.

Under this rule:

* `seq` is right-aligned;
* `builtin` is right-aligned;
* `narg` is right-aligned;
* names and text fields are left-aligned.

`NULL` values in an integer column shall follow the column’s right alignment.

The separator row shall consist of `-` repeated to the full width of each column.

---

### 22. Summary Table Formatting

The Summary table shall use exactly two columns:

```text
item
value
```

Example:

```text
item                    value
----------------------  ------------------------------------------------------------
SQLite version          3.50.4
SQLite source ID        2025-07-30 19:33:53 ...
Module names            8
Collations              3
Function names          129
Function registrations  178
Pragmas                 71
Compile options         48
```

The `item` column shall be left-aligned.

The `value` column shall also be left-aligned, including numeric counts.

This exception keeps the summary visually uniform and prevents mixed alignment in a descriptive key-value table.

The summary shall use the following labels exactly:

```text
SQLite version
SQLite source ID
Module names
Collations
Function names
Function registrations
Pragmas
Compile options
```

Do not rename them to alternatives such as:

```text
Modules
Functions
Unique functions
Pragma names
Compilation options
```

---

### 23. Derived Counts

Counts shall be calculated after all query results have been materialized.

Recommended logic:

```python
module_name_count = len(
    {
        row[module_name_index]
        for row in module_rows
        if row[module_name_index] is not None
    }
)

collation_count = len(collation_rows)

function_name_count = len(
    {
        row[function_name_index]
        for row in function_rows
        if row[function_name_index] is not None
    }
)

function_registration_count = len(function_rows)

pragma_count = len(pragma_rows)

compile_option_count = len(compile_option_rows)
```

Name lookup is preferable to hard-coded indexes when using `sqlite3.Row`.

Counts shall be ordinary Python integers.

The implementation shall not obtain counts by executing additional SQL such as:

```sql
SELECT count(*)
SELECT count(DISTINCT name)
```

No additional queries are permitted.

---

### 24. Command-Line Interface

The initial implementation shall require no command-line arguments.

Invocation:

```text
python sqlite_dbmeta.py
```

The report shall be written to standard output.

The program may support the standard help option through `argparse`, but no functional options are required.

The simplest compliant interface is:

```text
python sqlite_dbmeta.py
```

Any unexpected positional argument or unsupported option should produce a usage error and a nonzero exit status if `argparse` is used.

The implementation shall not add:

* JSON output;
* CSV output;
* TSV output;
* output-file selection;
* filtering;
* sorting options;
* extension loading;
* database-path input;
* verbosity levels;
* compact mode;
* color mode.

These are outside the current scope.

---

### 25. Standard Output and Standard Error

The complete report shall be written to standard output.

Standard error shall be used only for fatal error messages.

A successful run shall not print status messages such as:

```text
Opening database...
Executing metadata queries...
Done.
```

The output shall contain only the report.

---

### 26. Error Handling

The program shall fail cleanly when:

* the `sqlite3` module cannot be imported;
* the in-memory connection cannot be opened;
* any required metadata query fails;
* standard output cannot be written.

Because all six queries are required, failure of any query shall be fatal.

The program shall not silently omit an unavailable section.

A fatal error message shall:

* be concise;
* identify the failed operation;
* include the underlying exception message;
* be written to standard error.

Example:

```text
sqlite_dbmeta: failed to query pragma_function_list(): no such table: pragma_function_list
```

The program shall not print a Python traceback during normal command-line execution.

Unexpected exceptions may be caught at the top level and converted into a concise fatal error.

---

### 27. Exit Status

Use the following exit statuses:

```text
0  Report generated successfully.
1  Runtime, SQLite, query, rendering, or output failure.
2  Invalid command-line usage.
```

If no command-line parser is implemented, exit status `2` need not be used.

---

### 28. Resource Management

The SQLite connection shall always be closed.

Use either:

```python
with sqlite3.connect(":memory:") as connection:
    ...
```

or:

```python
connection = sqlite3.connect(":memory:")
try:
    ...
finally:
    connection.close()
```

Be aware that a `sqlite3.Connection` context manager controls transaction commit or rollback but does not necessarily serve as the clearest expression of connection closure across Python versions.

A `try/finally` block with explicit `close()` is preferred.

No transaction is needed.

The program shall not call `commit()` or `rollback()` unless required by generic cleanup logic.

---

### 29. Recommended Internal Structure

The single module should be organized into small functions.

Recommended structure:

```python
def execute_query(
    connection: sqlite3.Connection,
    sql: str,
) -> QueryResult:
    ...

def render_value(value: object) -> str:
    ...

def determine_numeric_columns(result: QueryResult) -> tuple[bool, ...]:
    ...

def render_table(
    columns: Sequence[str],
    rows: Sequence[Sequence[object]],
    *,
    force_left_align: bool = False,
) -> list[str]:
    ...

def render_section(
    title: str,
    result: QueryResult,
) -> list[str]:
    ...

def build_summary(
    runtime: QueryResult,
    modules: QueryResult,
    collations: QueryResult,
    functions: QueryResult,
    pragmas: QueryResult,
    compile_options: QueryResult,
) -> QueryResult:
    ...

def collect_metadata(
    connection: sqlite3.Connection,
) -> MetadataReport:
    ...

def render_report(report: MetadataReport) -> str:
    ...

def main() -> int:
    ...
```

Use of `QueryResult` and `MetadataReport` data classes is recommended but not mandatory.

The design shall separate:

* query execution;
* summary derivation;
* value formatting;
* table formatting;
* report assembly;
* command-line error handling.

Query functions shall not print.

Rendering functions shall not execute SQL.

---

### 30. Suggested Data Structures

A robust implementation may define:

```python
from dataclasses import dataclass

@dataclass(frozen=True)
class QueryResult:
    columns: tuple[str, ...]
    rows: tuple[tuple[object, ...], ...]


@dataclass(frozen=True)
class MetadataReport:
    runtime: QueryResult
    modules: QueryResult
    collations: QueryResult
    functions: QueryResult
    pragmas: QueryResult
    compile_options: QueryResult
```

The summary need not be stored in `MetadataReport`; it may be derived during rendering.

Alternatively, it may be represented as another `QueryResult`.

All stored rows should be immutable tuples after collection.

---

### 31. Query Helper Requirements

The generic query helper shall:

1. execute the supplied fixed SQL;
2. capture `cursor.description`;
3. fetch all rows;
4. return column names and row values;
5. close the cursor if a dedicated cursor was created.

Recommended behavior:

```python
cursor = connection.execute(sql)
try:
    columns = tuple(description[0] for description in cursor.description or ())
    rows = tuple(tuple(row) for row in cursor.fetchall())
finally:
    cursor.close()
```

The helper shall verify that a result set exists.

If `cursor.description` is `None`, raise an internal error because every specified query must return rows or at least a result schema.

---

### 32. Runtime Query Validation

The runtime query shall return exactly one row and exactly two columns.

The implementation shall validate this expectation.

Failure conditions include:

* zero rows;
* more than one row;
* fewer or more than two columns.

The two values should normally be strings.

The implementation may validate that neither value is `NULL`.

A malformed runtime result shall be treated as fatal.

---

### 33. Inventory Query Validation

The inventory queries may legally return zero rows.

The renderer shall still print:

* the section heading;
* the table header;
* the separator row.

Example empty section:

```text
Modules
=======

name
----
```

Do not print placeholders such as:

```text
No rows.
None.
Unavailable.
```

Do not omit empty sections.

---

### 34. Determinism

Given the same SQLite engine and registrations, repeated program runs shall produce identical output.

The only permitted variability is metadata returned by SQLite itself.

The program shall not include:

* timestamps;
* process IDs;
* memory addresses;
* Python versions;
* execution durations;
* host names;
* current working directories;
* random identifiers.

All multi-row queries already define explicit ordering and shall be rendered without additional sorting.

The Summary rows shall use the fixed order specified in this document.

---

### 35. Encoding

The source file shall be UTF-8.

The report shall be written using Python text output.

SQLite text values shall be preserved as Unicode strings.

The implementation shall not manually encode standard output unless necessary for error handling.

If standard output cannot represent a returned character due to the active console encoding, the program shall fail cleanly rather than silently replace the character.

No ASCII-only restriction applies to SQLite-returned metadata values.

---

### 36. Style Requirements

The implementation shall be production-quality Python.

It shall include:

* a module docstring;
* type annotations;
* descriptive function names;
* concise docstrings for nontrivial functions;
* no unused imports;
* no dead code;
* no debug output;
* no global mutable state;
* no third-party dependencies.

The code shall follow conventional PEP 8 formatting.

The main entry point shall be:

```python
if __name__ == "__main__":
    raise SystemExit(main())
```

---

### 37. Module Docstring

The module docstring should state:

* the program’s purpose;
* that it inspects the SQLite engine linked to Python;
* that it opens a blank in-memory database;
* that it reports only the results of the fixed metadata queries;
* the basic invocation.

Suggested content:

```python
"""
Report SQLite engine metadata available through Python's sqlite3 module.

The program opens a blank in-memory SQLite database, executes a fixed set of
SQLite metadata queries, and prints an aligned sectioned text report.

Usage:
    python sqlite_dbmeta.py
"""
```

Do not include extensive implementation notes in the module docstring.

---

### 38. Prohibited Additions

The implementation shall not add any of the following unless the specification is revised:

* Python version;
* Python implementation;
* `sqlite3` module version;
* `sqlite3.threadsafety`;
* `sqlite3.sqlite_version`;
* executable path;
* operating-system name;
* machine architecture;
* process bitness;
* byte order;
* environment variables;
* SQLite connection limits;
* SQLite database configuration;
* scalar pragma values;
* attached database inventory;
* schema objects;
* feature probes;
* extension loading;
* JSON capability tests;
* FTS capability tests;
* R-tree capability tests;
* timestamps;
* derived feature interpretations;
* compile-option parsing;
* explanations of function types;
* explanations of collations;
* duplicate elimination from detailed tables;
* JSON, CSV, TSV, HTML, or Markdown output.

---

### 39. Complete Output Shape

A representative report shall have this form:

```text
Summary
=======

item                    value
----------------------  ------------------------------------------------------------
SQLite version          3.50.4
SQLite source ID        2025-07-30 19:33:53 ...
Module names            8
Collations              3
Function names          129
Function registrations  178
Pragmas                 71
Compile options         48

Modules
=======

name
--------
dbstat
fts5
json_each
json_tree
pragma
rtree
rtree_i32
zipfile

Collations
==========

seq  name
---  ------
  2  BINARY
  1  NOCASE
  0  RTRIM

Functions
=========

name          builtin  type  enc   narg
------------  -------  ----  ----  ----
abs                 1  s     utf8     1
avg                 1  w     utf8     1
coalesce            1  s     utf8    -1
json_extract        1  s     utf8    -1
like                1  s     utf8     2
like                1  s     utf8     3

Pragmas
=======

name
------------------------
analysis_limit
application_id
auto_vacuum
automatic_index

Compile Options
===============

compile_options
----------------------------------------
ATOMIC_INTRINSICS=1
COMPILER=msvc-1944
ENABLE_FTS5
ENABLE_RTREE
THREADSAFE=1
```

The actual widths shall be calculated dynamically.

The example widths are illustrative only.

---

### 40. Acceptance Criteria

The implementation is complete when all of the following are true:

* `sqlite_dbmeta.py` is the only required file.
* The program uses only the standard library.
* It opens one blank `:memory:` SQLite database.
* It executes exactly the six specified metadata queries.
* It executes each query exactly once.
* It executes no additional SQL.
* It prints Summary first.
* It prints Modules second.
* It prints Collations third.
* It prints Functions fourth.
* It prints Pragmas fifth.
* It prints Compile Options sixth.
* SQLite version and source ID appear only in Summary.
* Summary counts are derived from already-fetched rows.
* Module names are counted distinctly.
* Function names are counted distinctly.
* Function registrations are counted by total rows.
* Collations, pragmas, and compile options are counted by total rows.
* Detailed tables preserve every returned row.
* Detailed tables preserve query-defined ordering.
* Integer columns are right-aligned.
* Text columns are left-aligned.
* Summary values are left-aligned.
* Columns are separated by exactly two spaces.
* No value is truncated or wrapped.
* `NULL` is rendered as `NULL`.
* Empty strings remain empty cells.
* Empty result sets still render headers and separators.
* The report contains no Python, system, connection-limit, schema, or database-list information.
* Successful execution returns exit status `0`.
* Fatal errors return exit status `1`.
* The connection is always closed.
* Successful standard output contains only the report.

---
---

## 📗 Implementation Plan

> [!NOTE] Prompt
> 
> Now generate a detailed implementation plan, including module architechture decomposition.

### 1. Objective

Implement `sqlite_dbmeta.py` as a single-module Python command-line program that:

1. Opens one blank in-memory SQLite database.
2. Executes exactly six fixed SQLite metadata queries.
3. Executes each query exactly once.
4. Derives a summary from the already-materialized query results.
5. Prints one deterministic aligned plain-text report.
6. Emits no Python runtime, operating-system, filesystem, database-schema, or connection-state metadata.
7. Uses only the Python standard library.

The implementation shall remain a single physical module while being internally decomposed into clearly separated architectural layers.

---

### 2. Deliverable

Create:

```text
sqlite_dbmeta.py
```

The module shall contain:

* immutable data models;
* fixed SQL definitions;
* query execution logic;
* result validation;
* summary derivation;
* value and table formatting;
* report assembly;
* top-level execution and error handling.

No additional source files shall be created.

---

### 3. Implementation Strategy

Implement the program in seven stages:

1. Establish the module skeleton and constants.
2. Define immutable internal data structures.
3. Implement SQL execution and result collection.
4. Implement validation and summary derivation.
5. Implement generic aligned-table rendering.
6. Implement report assembly and command-line execution.
7. Verify determinism, exact query scope, and error behavior.

Each stage should leave the module syntactically valid and progressively closer to an executable program.

---

#### Stage 1 — Establish the module skeleton

##### Goal

Create the initial single-file program structure without implementing query or rendering behavior.

##### Tasks

Create `sqlite_dbmeta.py` with:

* a concise module docstring;
* standard-library imports;
* module-level SQL constants;
* exception definitions;
* function stubs;
* the `main()` entry point;
* the standard `__main__` guard.

Recommended initial structure:

```python
"""
Report SQLite engine metadata from a blank in-memory database.

The program executes a fixed set of SQLite metadata queries and prints a
deterministic aligned plain-text report.

Usage:
    python sqlite_dbmeta.py
"""

from __future__ import annotations

import sqlite3
import sys
from dataclasses import dataclass
from typing import Sequence
```

The exact imports may be adjusted as implementation proceeds. Remove any unused imports before completion.

Define the six SQL statements as immutable module-level constants:

```python
SQL_RUNTIME = """
SELECT sqlite_version(), sqlite_source_id();
"""

SQL_MODULES = """
SELECT name
FROM pragma_module_list()
ORDER BY name;
"""

SQL_COLLATIONS = """
SELECT seq, name
FROM pragma_collation_list()
ORDER BY name;
"""

SQL_FUNCTIONS = """
SELECT name, builtin, type, enc, narg
FROM pragma_function_list()
ORDER BY name, builtin, narg;
"""

SQL_PRAGMAS = """
SELECT name
FROM pragma_pragma_list()
ORDER BY name;
"""

SQL_COMPILE_OPTIONS = """
SELECT compile_options
FROM pragma_compile_options()
ORDER BY compile_options;
"""
```

Do not construct these statements dynamically.

Do not add aliases to the selected columns unless the specification is revised.

##### Architectural outcome

At the end of this stage, the module should visibly separate:

* configuration and SQL definitions;
* data models;
* collection;
* derivation;
* rendering;
* orchestration.

---

#### Stage 2 — Define the internal data model

##### Goal

Create immutable representations for individual query results and the complete collected report.

##### Query result model

Define:

```python
@dataclass(frozen=True)
class QueryResult:
    columns: tuple[str, ...]
    rows: tuple[tuple[object, ...], ...]
```

###### Responsibilities

`QueryResult` shall preserve:

* SQLite-returned column order;
* SQLite-returned row order;
* original Python value types produced by `sqlite3`;
* empty result schemas.

It shall not:

* sort rows;
* transform values;
* derive counts;
* render output.

###### Invariants

A valid `QueryResult` must satisfy:

```text
len(row) == len(columns)
```

for every row.

Columns shall always be stored as strings.

Rows shall always be tuples.

##### Complete metadata model

Define:

```python
@dataclass(frozen=True)
class MetadataReport:
    runtime: QueryResult
    modules: QueryResult
    collations: QueryResult
    functions: QueryResult
    pragmas: QueryResult
    compile_options: QueryResult
```

###### Responsibilities

`MetadataReport` shall contain only the six required query result sets.

It shall not contain:

* Python metadata;
* system metadata;
* timestamps;
* pre-rendered text;
* derived feature descriptions;
* connection information;
* database inventory.

##### Summary model

The summary can be represented as another `QueryResult`.

Preferred approach:

```python
def build_summary(report: MetadataReport) -> QueryResult:
    ...
```

The returned summary shall use:

```python
columns = ("item", "value")
```

and eight rows.

This avoids introducing a second table abstraction.

##### Custom exception

Define one internal exception for predictable program failures:

```python
class DbMetaError(RuntimeError):
    """Raised when SQLite metadata collection or validation fails."""
```

Use this exception to wrap errors with operation-specific context.

Do not create an elaborate exception hierarchy.

---

#### Stage 3 — Query execution

##### Goal

Implement one generic SQL execution function that captures column metadata and all result rows without losing empty-result schemas.

##### Function

Implement:

```python
def execute_query(
    connection: sqlite3.Connection,
    sql: str,
    description: str,
) -> QueryResult:
    ...
```

`description` is an internal human-readable operation label used only for errors, such as:

```text
SQLite runtime metadata
module list
collation list
function list
pragma list
compile-option list
```

##### Required behavior

The function shall:

1. Create or obtain a cursor.
2. Execute the supplied static SQL.
3. Capture `cursor.description`.
4. Fetch all rows.
5. Convert columns to a tuple of names.
6. Convert every row to a plain tuple.
7. Validate row widths.
8. Close the cursor.
9. Return a `QueryResult`.

Recommended implementation pattern:

```python
cursor = connection.cursor()
try:
    cursor.execute(sql)

    if cursor.description is None:
        raise DbMetaError(
            f"{description} query did not produce a result set"
        )

    columns = tuple(
        column_description[0]
        for column_description in cursor.description
    )
    rows = tuple(tuple(row) for row in cursor.fetchall())
finally:
    cursor.close()
```

Wrap `sqlite3.Error` with contextual information:

```python
except sqlite3.Error as exc:
    raise DbMetaError(
        f"failed to query {description}: {exc}"
    ) from exc
```

##### Validation

After fetching, verify:

```python
expected_width = len(columns)
```

and every row length equals that width.

If not, raise:

```text
invalid <description> result: expected N columns, received M
```

This condition is unlikely but establishes a strong internal invariant.

##### Restrictions

The query helper shall not:

* print anything;
* commit;
* roll back;
* retry;
* modify SQL;
* add parameters;
* add ordering;
* normalize column names;
* convert values to strings;
* suppress query failures.

---

#### Stage 4 — Metadata collection

##### Goal

Open no connections here; collect all required metadata from a provided connection in the exact required order.

##### Function

Implement:

```python
def collect_metadata(
    connection: sqlite3.Connection,
) -> MetadataReport:
    ...
```

##### Query order

Execute queries in exactly this order:

1. `SQL_RUNTIME`
2. `SQL_MODULES`
3. `SQL_COLLATIONS`
4. `SQL_FUNCTIONS`
5. `SQL_PRAGMAS`
6. `SQL_COMPILE_OPTIONS`

Example:

```python
runtime = execute_query(
    connection,
    SQL_RUNTIME,
    "SQLite runtime metadata",
)

modules = execute_query(
    connection,
    SQL_MODULES,
    "module list",
)
```

Continue similarly for all six result sets.

##### Exactly-once requirement

Every SQL constant shall be passed to `execute_query()` exactly once during one normal program execution.

Do not:

* re-run queries during rendering;
* issue count queries;
* issue distinct-count queries;
* probe feature availability;
* query alternate fallback forms;
* execute validation SQL.

All counts must be derived from stored rows.

##### Runtime result validation

Immediately validate the runtime query.

Required shape:

```text
2 columns
1 row
```

Implement:

```python
def validate_runtime_result(result: QueryResult) -> None:
    ...
```

Validation rules:

* exactly two columns;
* exactly one row;
* both values non-null;
* both values text strings.

Do not validate exact column-name spelling because expression-column names are SQLite-defined.

Potential error messages:

```text
invalid SQLite runtime result: expected 2 columns, received 1
invalid SQLite runtime result: expected 1 row, received 0
invalid SQLite runtime result: SQLite version is NULL
invalid SQLite runtime result: source ID is not text
```

##### Inventory result shape validation

Validate expected column counts:

| Result          | Expected columns |
| --------------- | ---------------: |
| Modules         |                1 |
| Collations      |                2 |
| Functions       |                5 |
| Pragmas         |                1 |
| Compile options |                1 |

Implement a small helper:

```python
def require_column_count(
    result: QueryResult,
    expected: int,
    description: str,
) -> None:
    ...
```

Do not require nonempty result sets.

##### Return value

Return one immutable `MetadataReport`.

---

#### Stage 5 — Summary derivation

##### Goal

Build the Summary result exclusively from already-collected rows.

##### Function

Implement:

```python
def build_summary(report: MetadataReport) -> QueryResult:
    ...
```

##### Summary rows

Produce rows in exactly this order:

```text
SQLite version
SQLite source ID
Module names
Collations
Function names
Function registrations
Pragmas
Compile options
```

##### Value extraction

Obtain:

```python
sqlite_version = report.runtime.rows[0][0]
sqlite_source_id = report.runtime.rows[0][1]
```

##### Distinct name counting

Implement a reusable helper:

```python
def count_distinct_non_null(
    result: QueryResult,
    column_name: str,
) -> int:
    ...
```

The helper shall:

1. Locate the requested column by exact name.
2. Collect non-null values into a set.
3. Return the set length.

Recommended logic:

```python
try:
    column_index = result.columns.index(column_name)
except ValueError as exc:
    raise DbMetaError(
        f"required column {column_name!r} is missing"
    ) from exc

return len(
    {
        row[column_index]
        for row in result.rows
        if row[column_index] is not None
    }
)
```

Use it for:

```python
module_name_count = count_distinct_non_null(
    report.modules,
    "name",
)

function_name_count = count_distinct_non_null(
    report.functions,
    "name",
)
```

##### Row counts

Calculate:

```python
collation_count = len(report.collations.rows)
function_registration_count = len(report.functions.rows)
pragma_count = len(report.pragmas.rows)
compile_option_count = len(report.compile_options.rows)
```

##### Summary value types

Store:

* SQLite version and source ID as strings;
* counts as integers.

Do not pre-render all values as strings in the model.

The table renderer will render them.

##### Summary result

Return:

```python
QueryResult(
    columns=("item", "value"),
    rows=(
        ("SQLite version", sqlite_version),
        ("SQLite source ID", sqlite_source_id),
        ("Module names", module_name_count),
        ("Collations", collation_count),
        ("Function names", function_name_count),
        ("Function registrations", function_registration_count),
        ("Pragmas", pragma_count),
        ("Compile options", compile_option_count),
    ),
)
```

---

#### Stage 6 — Scalar value rendering

##### Goal

Create one deterministic conversion from SQLite-returned Python values to report text.

##### Function

Implement:

```python
def render_value(value: object) -> str:
    ...
```

##### Required mappings

###### `None`

```python
None -> "NULL"
```

###### Boolean

SQLite does not normally return Python `bool` values for these queries, but because `bool` is a subclass of `int`, handle it explicitly before integers.

Recommended mapping:

```python
True -> "1"
False -> "0"
```

###### Integer

Use:

```python
str(value)
```

###### Float

Use:

```python
str(value)
```

No specified query is expected to return floating-point values.

###### String

Return exactly as provided.

Do not:

* strip whitespace;
* quote the value;
* escape ordinary characters;
* normalize case;
* normalize Unicode.

###### Bytes

The fixed queries should not return BLOBs. Treat unexpected bytes as a fatal internal rendering error rather than inventing an unspecified representation.

Recommended behavior:

```python
if isinstance(value, bytes):
    raise DbMetaError(
        "unexpected BLOB value in SQLite metadata result"
    )
```

###### Unexpected value type

Raise `DbMetaError` with the Python type name.

This prevents silent nondeterministic representations such as object memory addresses.

---

#### Stage 7 — Alignment classification

##### Goal

Determine whether each detailed-table column should be left- or right-aligned.

##### Function

Implement:

```python
def numeric_columns(
    result: QueryResult,
) -> tuple[bool, ...]:
    ...
```

##### Rule

A column is numeric when:

1. It contains at least one non-null value.
2. Every non-null value is an integer.
3. Boolean values, if encountered, are accepted as integer-like.

Otherwise, it is textual.

Recommended algorithm:

```python
flags: list[bool] = []

for column_index in range(len(result.columns)):
    values = [
        row[column_index]
        for row in result.rows
        if row[column_index] is not None
    ]

    is_numeric = bool(values) and all(
        isinstance(value, int)
        for value in values
    )
    flags.append(is_numeric)

return tuple(flags)
```

##### Expected classification

###### Modules

```text
name       left
```

###### Collations

```text
seq        right
name       left
```

###### Functions

```text
name       left
builtin    right
type       left
enc        left
narg       right
```

###### Pragmas

```text
name       left
```

###### Compile Options

```text
compile_options    left
```

##### Summary exception

The summary shall force both columns to left alignment.

Do not rely on generic numeric inference for Summary.

---

#### Stage 8 — Aligned table rendering

##### Goal

Render any `QueryResult` as an aligned ASCII table.

##### Function

Implement:

```python
def render_table(
    result: QueryResult,
    *,
    force_left_align: bool = False,
) -> list[str]:
    ...
```

Return a list of complete output lines without trailing newline characters.

##### Rendering process

###### Step 1: Render headers

Convert each column name using direct string use:

```python
rendered_columns = result.columns
```

Column names are already strings.

###### Step 2: Render rows

Build:

```python
rendered_rows = tuple(
    tuple(render_value(value) for value in row)
    for row in result.rows
)
```

###### Step 3: Determine widths

For each column:

```python
width = max(
    len(column_name),
    *(len(row[column_index]) for row in rendered_rows),
)
```

Handle empty row sets explicitly:

```python
width = len(column_name)
```

Do not use a fixed minimum width.

###### Step 4: Determine alignment

When `force_left_align` is true:

```python
align_right = (False, ...) 
```

Otherwise, use `numeric_columns(result)`.

###### Step 5: Render header row

Headers shall always be left-aligned, including headers for numeric columns.

This yields:

```text
seq  name
```

rather than right-aligning the word `seq`.

###### Step 6: Render separator row

For each column:

```python
"-" * width
```

Join with exactly two spaces.

###### Step 7: Render data rows

For each cell:

* use `rjust(width)` for right-aligned columns;
* use `ljust(width)` for left-aligned columns.

Join cells using:

```python
"  "
```

###### Trailing spaces

Avoid trailing spaces at the end of each output line.

This matters because left-padding each final cell to its full width can create trailing whitespace.

Preferred approach:

* format all columns except the last using full width;
* for the final column:

  * right-align if numeric;
  * otherwise emit the unpadded text.

Alternatively, render the complete line and call:

```python
line.rstrip()
```

Using `rstrip()` on the assembled line is acceptable because values themselves are not expected to require significant trailing spaces. However, the specification states that returned text should be preserved exactly, including whitespace.

Therefore, the safer implementation is to avoid padding the last textual column rather than trimming complete lines.

Recommended cell assembly:

```python
for column_index, value in enumerate(row):
    is_last = column_index == column_count - 1

    if align_right[column_index]:
        cell = value.rjust(widths[column_index])
    elif is_last:
        cell = value
    else:
        cell = value.ljust(widths[column_index])
```

This preserves trailing spaces that are part of the last value.

For a non-final text column, exact preservation of trailing spaces conflicts with alignment padding. SQLite metadata names and compile options are not expected to contain trailing spaces. No additional escaping scheme is required.

##### Empty tables

An empty result shall render only:

1. header row;
2. separator row.

Example:

```text
name
----
```

Do not add an empty-state message.

---

#### Stage 9 — Section rendering

##### Goal

Render one titled section with exact heading and blank-line rules.

##### Function

Implement:

```python
def render_section(
    title: str,
    result: QueryResult,
    *,
    force_left_align: bool = False,
) -> list[str]:
    ...
```

##### Output structure

Return:

```python
[
    title,
    "=" * len(title),
    "",
    *render_table(
        result,
        force_left_align=force_left_align,
    ),
]
```

Do not append an extra blank line within this function unless the report assembler explicitly expects it.

Keeping inter-section spacing in one place reduces accidental double blank lines.

---

#### Stage 10 — Complete report assembly

##### Goal

Assemble all six sections in the exact required order.

##### Function

Implement:

```python
def render_report(report: MetadataReport) -> str:
    ...
```

##### Section order

Render:

1. Summary
2. Modules
3. Collations
4. Functions
5. Pragmas
6. Compile Options

Example logical structure:

```python
sections = (
    render_section(
        "Summary",
        build_summary(report),
        force_left_align=True,
    ),
    render_section("Modules", report.modules),
    render_section("Collations", report.collations),
    render_section("Functions", report.functions),
    render_section("Pragmas", report.pragmas),
    render_section(
        "Compile Options",
        report.compile_options,
    ),
)
```

##### Joining sections

Join lines inside each section with `"\n"`.

Join sections using exactly two newline characters:

```python
"\n\n"
```

Append exactly one final newline:

```python
return "\n\n".join(section_texts) + "\n"
```

This produces:

* no blank line before the first heading;
* one empty line between sections;
* one newline after the final row.

##### Restrictions

The report renderer shall not:

* execute SQL;
* access the connection;
* add timestamps;
* add introductory prose;
* add diagnostic notes;
* add count lines inside detailed sections;
* omit empty sections.

---

#### Stage 11 — Application orchestration

##### Goal

Create one function that owns the SQLite connection lifecycle and coordinates collection and rendering.

##### Function

Implement:

```python
def generate_report() -> str:
    ...
```

Recommended structure:

```python
def generate_report() -> str:
    try:
        connection = sqlite3.connect(":memory:")
    except sqlite3.Error as exc:
        raise DbMetaError(
            f"failed to open in-memory SQLite database: {exc}"
        ) from exc

    try:
        metadata = collect_metadata(connection)
        return render_report(metadata)
    finally:
        connection.close()
```

##### Connection configuration

Do not set:

* `row_factory`;
* `text_factory`;
* isolation mode;
* URI mode;
* timeout;
* extension loading;
* user-defined functions;
* user-defined collations.

The default tuple row format is sufficient because `QueryResult` stores explicit column names from `cursor.description`.

Avoid `sqlite3.Row`; it is unnecessary once cursor metadata is captured generically.

##### Blank database requirement

The connection shall remain blank.

No transaction or schema operation shall be performed.

---

#### Stage 12 — Command-line entry point

##### Goal

Write the report to standard output and convert errors into concise diagnostics.

##### Function

Implement:

```python
def main() -> int:
    ...
```

Recommended logic:

```python
def main() -> int:
    try:
        report_text = generate_report()
        sys.stdout.write(report_text)
    except DbMetaError as exc:
        sys.stderr.write(f"sqlite_dbmeta: {exc}\n")
        return 1
    except OSError as exc:
        sys.stderr.write(
            f"sqlite_dbmeta: failed to write output: {exc}\n"
        )
        return 1

    return 0
```

##### Broken pipe handling

When output is piped to a command that closes early, Python may raise `BrokenPipeError`.

Treat this as an output failure or exit quietly with a nonzero status.

A simple compliant implementation may let `OSError` handling cover it.

Do not print a traceback.

##### Entry point

Use:

```python
if __name__ == "__main__":
    raise SystemExit(main())
```

##### Arguments

No functional command-line arguments are required.

The initial implementation does not need `argparse`.

If arguments are intentionally rejected, add:

```python
if len(sys.argv) != 1:
    sys.stderr.write(
        "usage: sqlite_dbmeta.py\n"
    )
    return 2
```

This is optional.

The simplest implementation may ignore the issue because Python passes only the script name during normal invocation. However, explicit rejection is preferable for a tightly specified program.

Recommended behavior:

```text
python sqlite_dbmeta.py
```

succeeds, while:

```text
python sqlite_dbmeta.py anything
```

prints:

```text
usage: sqlite_dbmeta.py
```

and returns `2`.

Do not add help, format, file, filter, or database arguments.

---

#### Stage 13 — Enforce exact SQL scope

##### Goal

Ensure the implementation cannot drift into collecting additional metadata.

##### Tasks

Review the final source and confirm:

* exactly six SQL constants exist;
* only those constants are executed;
* no SQL appears inline elsewhere;
* no `COUNT(*)` queries exist;
* no `DISTINCT` count queries exist;
* no schema queries exist;
* no `pragma_database_list()` query exists;
* no scalar pragma query exists;
* no feature-probe query exists.

A useful source-level review is to search for:

```text
SELECT
PRAGMA
execute(
connection.execute
cursor.execute
```

Every SQL execution must lead back to the six approved constants through `execute_query()`.

##### Architectural guard

Keep `cursor.execute()` in one function only.

This centralization makes exact-query auditing straightforward.

---

#### Stage 14 — Deterministic output

##### Goal

Confirm repeated runs against the same SQLite engine produce byte-identical output.

##### Checks

Run:

```text
python sqlite_dbmeta.py > output1.txt
python sqlite_dbmeta.py > output2.txt
```

Then compare:

```text
fc /b output1.txt output2.txt
```

on Windows CMD.

Expected result:

```text
FC: no differences encountered
```

Potential nondeterminism must not be introduced by:

* set iteration;
* dictionary iteration;
* timestamps;
* runtime identifiers;
* unsorted Python-side rows.

Distinct counts may use sets because only the resulting integer is emitted. Set order is irrelevant.

Detailed rows must be rendered in query order.

---

#### Stage 15 — Table formatting

##### Goal

Verify every table follows the alignment and spacing rules.

##### Checks

###### Summary

Confirm:

* two columns named `item` and `value`;
* both left-aligned;
* exactly eight rows;
* fixed row order;
* no right-aligned counts.

###### Modules

Confirm:

* one `name` column;
* no summary count line;
* all rows retained.

###### Collations

Confirm:

* `seq` right-aligned;
* `name` left-aligned;
* row order is alphabetical by `name`, not numeric by `seq`.

###### Functions

Confirm:

* all five columns are present;
* `builtin` and `narg` are right-aligned;
* `name`, `type`, and `enc` are left-aligned;
* duplicate function names remain;
* no `flags` column is added.

###### Pragmas

Confirm:

* one `name` column;
* no pragma is executed based on the list.

###### Compile Options

Confirm:

* one `compile_options` column;
* values are not parsed or modified.

###### Separators

Confirm:

* headings use `=`;
* table separators use `-`;
* columns use exactly two spaces;
* no box-drawing characters are present.

---

#### Stage 16 — Failure handling

##### Goal

Ensure required-query failures are fatal and produce concise errors.

##### Required behavior

Any failure of the six queries shall:

1. stop report generation;
2. produce no partial report;
3. write one concise line to standard error;
4. return exit status `1`;
5. not print a traceback.

##### Suggested tests

Temporarily replace one query with invalid SQL during development:

```sql
SELECT * FROM pragma_nonexistent();
```

Expected form:

```text
sqlite_dbmeta: failed to query module list: no such table: pragma_nonexistent
```

Restore the correct SQL immediately afterward.

Also test malformed runtime validation by temporarily changing the runtime query to return one column.

Expected failure should identify the invalid result shape.

These mutations are development-only and shall not remain in the final source.

---

#### Stage 17 — Final code-quality pass

##### Goal

Prepare the module for direct use and AI-agent review.

##### Review checklist

Confirm:

* source is one module;
* imports are minimal;
* all public-facing errors start with `sqlite_dbmeta:`;
* all functions have type annotations;
* nontrivial functions have concise docstrings;
* no debug output remains;
* no commented-out experiments remain;
* no third-party package is imported;
* no global mutable collection is used;
* SQL constants are clearly named;
* line lengths are reasonable;
* the main execution path is easy to follow.

##### Recommended function order

Organize the module in this sequence:

1. Module docstring
2. Imports
3. SQL constants
4. Exception types
5. Data classes
6. Query execution helpers
7. Validation helpers
8. Collection functions
9. Summary derivation
10. Value-rendering helpers
11. Table-rendering helpers
12. Report assembly
13. Connection orchestration
14. `main()`
15. `__main__` guard

This order allows a reader to move from definitions to low-level mechanics to high-level execution.

---

### 4. Module Architecture

Although physically contained in one file, the implementation shall use the following logical architecture.

#### 4.1 SQL definition layer

##### Components

```text
SQL_RUNTIME
SQL_MODULES
SQL_COLLATIONS
SQL_FUNCTIONS
SQL_PRAGMAS
SQL_COMPILE_OPTIONS
```

##### Responsibilities

* define the complete SQL scope;
* preserve exact query text;
* make auditing easy.

##### Prohibited responsibilities

* execution;
* formatting;
* result interpretation.

---

#### 4.2 Data model layer

##### Components

```text
QueryResult
MetadataReport
```

##### Responsibilities

* preserve query schemas and rows;
* provide immutable boundaries between collection and rendering;
* prevent renderer access to live cursors.

##### Prohibited responsibilities

* SQL execution;
* output formatting;
* database lifecycle management.

---

#### 4.3 Query execution layer

##### Components

```text
execute_query()
```

##### Responsibilities

* execute one fixed query;
* capture column names;
* materialize all rows;
* normalize internal container types;
* wrap SQLite errors with context.

##### Prohibited responsibilities

* query selection;
* output formatting;
* summary derivation.

---

#### 4.4 Validation layer

##### Components

```text
require_column_count()
validate_runtime_result()
```

##### Responsibilities

* enforce expected query shapes;
* reject malformed or unexpected runtime results;
* preserve strong internal assumptions.

##### Prohibited responsibilities

* repairing malformed results;
* silently omitting sections;
* issuing fallback queries.

---

#### 4.5 Collection layer

##### Components

```text
collect_metadata()
```

##### Responsibilities

* execute the six queries once;
* preserve required execution order;
* validate results;
* return `MetadataReport`.

##### Prohibited responsibilities

* rendering;
* printing;
* opening or closing the connection;
* deriving display widths.

---

#### 4.6 Derivation layer

##### Components

```text
count_distinct_non_null()
build_summary()
```

##### Responsibilities

* calculate approved counts;
* extract version and source ID;
* produce the Summary table model.

##### Prohibited responsibilities

* additional SQL;
* feature inference;
* compile-option interpretation;
* modification of detailed result sets.

---

#### 4.7 Rendering layer

##### Components

```text
render_value()
numeric_columns()
render_table()
render_section()
render_report()
```

##### Responsibilities

* convert values to text;
* determine column alignment;
* calculate widths;
* render aligned tables;
* assemble sectioned output.

##### Prohibited responsibilities

* SQL execution;
* connection access;
* metadata collection;
* error recovery.

---

#### 4.8 Application layer

##### Components

```text
generate_report()
main()
```

##### Responsibilities

* open and close the connection;
* invoke collection;
* invoke rendering;
* write standard output;
* convert failures to exit statuses.

##### Prohibited responsibilities

* duplicating query or rendering logic;
* adding unrelated runtime information.

---

### 5. Recommended Function Inventory

The final module should contain approximately the following functions:

```python
def execute_query(
    connection: sqlite3.Connection,
    sql: str,
    description: str,
) -> QueryResult:
    ...

def require_column_count(
    result: QueryResult,
    expected: int,
    description: str,
) -> None:
    ...

def validate_runtime_result(
    result: QueryResult,
) -> None:
    ...

def collect_metadata(
    connection: sqlite3.Connection,
) -> MetadataReport:
    ...

def count_distinct_non_null(
    result: QueryResult,
    column_name: str,
) -> int:
    ...

def build_summary(
    report: MetadataReport,
) -> QueryResult:
    ...

def render_value(
    value: object,
) -> str:
    ...

def numeric_columns(
    result: QueryResult,
) -> tuple[bool, ...]:
    ...

def render_table(
    result: QueryResult,
    *,
    force_left_align: bool = False,
) -> list[str]:
    ...

def render_section(
    title: str,
    result: QueryResult,
    *,
    force_left_align: bool = False,
) -> list[str]:
    ...

def render_report(
    report: MetadataReport,
) -> str:
    ...

def generate_report() -> str:
    ...

def main() -> int:
    ...
```

This decomposition is detailed enough to isolate responsibilities without overengineering a small single-module utility.

---

### 6. Data Flow

The program’s complete data flow shall be:

```text
main()
  |
  +-- validate command-line usage
  |
  +-- generate_report()
        |
        +-- sqlite3.connect(":memory:")
        |
        +-- collect_metadata(connection)
        |     |
        |     +-- execute_query(SQL_RUNTIME)
        |     +-- execute_query(SQL_MODULES)
        |     +-- execute_query(SQL_COLLATIONS)
        |     +-- execute_query(SQL_FUNCTIONS)
        |     +-- execute_query(SQL_PRAGMAS)
        |     +-- execute_query(SQL_COMPILE_OPTIONS)
        |     |
        |     +-- validation
        |     |
        |     +-- MetadataReport
        |
        +-- render_report(report)
        |     |
        |     +-- build_summary(report)
        |     |
        |     +-- render_section("Summary")
        |     +-- render_section("Modules")
        |     +-- render_section("Collations")
        |     +-- render_section("Functions")
        |     +-- render_section("Pragmas")
        |     +-- render_section("Compile Options")
        |     |
        |     +-- final text
        |
        +-- close connection
  |
  +-- sys.stdout.write(report)
  |
  +-- return exit status
```

No backward dependency shall exist from lower layers to higher layers.

In particular:

* rendering shall not call collection;
* derivation shall not call SQLite;
* query execution shall not know section titles;
* data classes shall not print themselves.

---

### 7. Implementation Decisions

#### Use immutable tuples

Convert all collected rows to tuples immediately.

Benefits:

* stable internal representation;
* no accidental mutation;
* easy testing;
* clear separation from live SQLite cursor objects.

#### Do not use `sqlite3.Row`

Column names are already available from `cursor.description`.

Using ordinary tuples keeps result handling predictable and avoids coupling the renderer to SQLite-specific row objects.

#### Use one generic table renderer

All six tables share the same formatting model.

The Summary table only needs one explicit difference:

```text
force all columns left-aligned
```

Avoid writing section-specific formatting functions.

#### Keep counts out of SQL

This is a strict requirement.

All counts are calculated from already-fetched rows, ensuring:

* each query runs exactly once;
* no additional SQL is introduced;
* detailed and summary values cannot diverge.

#### Fail on missing metadata facilities

The program targets an SQLite version that provides the requested table-valued pragmas.

If one is unavailable, the report is incomplete, so the program shall fail rather than silently substitute another query or omit a section.

#### Do not interpret metadata

The output is an inventory, not an analysis report.

Do not explain:

* function type codes;
* encoding names;
* compile options;
* module capabilities;
* pragma behavior.

---

### 8. Development Verification Matrix

| Requirement                 | Verification method                              |
| --------------------------- | ------------------------------------------------ |
| One module only             | Confirm only `sqlite_dbmeta.py` is created       |
| Standard library only       | Inspect imports                                  |
| Blank in-memory database    | Confirm exact `sqlite3.connect(":memory:")` call |
| Six queries only            | Search source for SQL and `execute()`            |
| Each query once             | Inspect `collect_metadata()`                     |
| Summary first               | Inspect `render_report()`                        |
| Section order exact         | Compare rendered headings                        |
| Version only in Summary     | Search output                                    |
| Distinct module count       | Compare set count with rows                      |
| Distinct function count     | Compare set count with rows                      |
| Function registration count | Compare with function row count                  |
| No per-section counts       | Inspect output                                   |
| Query order preserved       | Compare output with direct SQL                   |
| Integer alignment           | Inspect `seq`, `builtin`, `narg`                 |
| No truncation               | Test long source ID and compile options          |
| Empty table handling        | Unit-test synthetic empty `QueryResult`          |
| No traceback                | Force a query failure                            |
| Connection closed           | Inspect `try/finally`                            |
| Final newline               | Check output bytes                               |
| Deterministic output        | Compare two generated files                      |

---

### 9. Suggested Unit-Level Checks

Even if no separate test module is created initially, the implementation should be designed so the following functions can be tested independently.

#### `render_value()`

Verify:

```text
None       -> NULL
0          -> 0
-1         -> -1
"utf8"     -> utf8
```

Verify unexpected `bytes` raises `DbMetaError`.

#### `numeric_columns()`

Use synthetic rows to verify:

```text
integer-only column     -> right-aligned
text column             -> left-aligned
mixed integer/text      -> left-aligned
all-null column         -> left-aligned
```

#### `render_table()`

Verify:

* exactly two spaces between columns;
* correct widths;
* headers left-aligned;
* numeric data right-aligned;
* empty results include header and separator;
* no value truncation.

#### `build_summary()`

Verify:

* fixed row order;
* distinct-name counting;
* duplicate function registrations retained in total count;
* null names excluded from distinct counts.

#### `render_report()`

Verify:

* exact section order;
* one blank line between sections;
* one final newline;
* no introductory or trailing prose.

---

### 10. Completion Criteria

Implementation is complete when:

1. `python sqlite_dbmeta.py` prints a valid report.
2. The report begins with `Summary`.
3. The report ends with the final compile-option row followed by one newline.
4. The six SQL queries are the only SQL executed.
5. The Summary contains exactly eight rows.
6. Modules, Collations, Functions, Pragmas, and Compile Options contain only their aligned query results.
7. No database-list information appears.
8. No Python or operating-system information appears.
9. No values are interpreted or annotated.
10. Repeated runs against the same SQLite engine produce byte-identical output.
11. Query failures return exit status `1` without a traceback.
12. Invalid command-line usage returns exit status `2` if argument rejection is implemented.
13. The SQLite connection is always closed.
14. The code remains a single maintainable Python module with clearly separated logical layers.

---
---

## 📗 Pytest SQLite Testing

> [!NOTE] Prompt
> 
> I am changing approach. The first implementation of the testing system will focus solely on testing via SQL. This scope mean that this testing can be fully implemented via pytest. I will directly replace the copy of sqlite3.dll used by Python with the target built copy.

