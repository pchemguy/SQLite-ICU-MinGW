---
url: https://chatgpt.com/c/6a6599df-da20-83eb-af51-90d35bffbe07
project: SQLite Extension
---

## 📗 Project Structure

> [!NOTE] Prompt
> 
> I need to define a robust project structure aligned with best leading practicies for small C project. If relevant, take into account library/extension/embedded project nature. I will need to organized sources, tests, and docs. Plus I will have a dedicated non-tracked dir, perhaps, "build", which will be structured as
> 
> ```
> build/
>     sqlite/
>     build/
>     sqlite.zip
> ```
> `build/sqlite` will contain unpacked SQLite checkpoint. `build/build` will be used for actually building SQLite together with the developed extension.

### Recommended Project Structure

```text
pblob/
├── .gitignore
├── LICENSE
├── README.md
├── CHANGELOG.md
│
├── src/
│   └── pblob.c
│
├── test/
│   ├── pblob.test
│   ├── pblob_vectors.tcl
│   ├── pblob_limits.test
│   ├── pblob_fault.test
│   ├── pblob_all.test
│   │
│   ├── c/
│   │   └── test_pblob.c
│   │
│   └── data/
│       ├── f16_vectors.tcl
│       ├── f32_vectors.tcl
│       └── int8_vectors.tcl
│
├── tools/
│   ├── build.cmd
│   ├── test.cmd
│   ├── clean.cmd
│   ├── prepare_sqlite.cmd
│   ├── bundle_sources.tcl
│   └── gen_pblob_vectors.py
│
├── vendor/
│   └── fp16/
│       ├── LICENSE
│       └── include/
│           └── fp16/
│               ├── fp16.h
│               ├── bitcasts.h
│               └── macros.h
│
├── docs/
│   ├── design.md
│   ├── testing.md
│   ├── implementation-plan.md
│   ├── build.md
│   ├── sql-api.md
│   └── decisions/
│       ├── 0001-json-text-input.md
│       ├── 0002-headerless-blob-format.md
│       └── 0003-fp16-conversion.md
│
└── build/
    ├── sqlite.zip
    ├── sqlite/
    ├── out/
    ├── generated/
    ├── logs/
    └── tmp/
```

The entire `build/` directory should be excluded from version control.

---

### Directory Responsibilities

#### `src/`

Contains production source code owned by the project.

```text
src/
└── pblob.c
```

Because the extension:

* has no public C API;
* has no independently consumed private API;
* is compiled only into the SQLite amalgamation;
* consists of one production module;

a matching `pblob.h` is unnecessary.

Do not place vendored FP16 code in `src/`. Keeping project code and third-party code separate makes ownership, licensing, updates, and reviews clearer.

---

#### `test/`

Contains all committed test code and static test data.

```text
test/
├── pblob.test
├── pblob_vectors.tcl
├── pblob_limits.test
├── pblob_fault.test
├── pblob_all.test
├── c/
│   └── test_pblob.c
└── data/
    ├── f16_vectors.tcl
    ├── f32_vectors.tcl
    └── int8_vectors.tcl
```

##### `test/pblob.test`

Primary SQL-level behavioral tests:

* SQL function registration;
* argument handling;
* format parsing;
* exact packed bytes;
* JSON validation;
* pack and unpack behavior;
* SQL result types;
* error messages;
* JSON subtype behavior.

##### `test/pblob_vectors.tcl`

Loads and executes committed reference vectors.

This file should contain test orchestration, while large generated datasets live under `test/data/`.

##### `test/pblob_limits.test`

Contains:

* SQLite length-limit tests;
* large-array tests;
* checked-size tests;
* boundary allocation tests.

##### `test/pblob_fault.test`

Contains:

* allocation fault injection;
* cleanup and recovery tests;
* parse-cache failure tests;
* `JsonString` allocation failures.

##### `test/pblob_all.test`

Focused suite entry point that runs every packed-blob test module.

##### `test/c/test_pblob.c`

Contains testfixture-only C support:

* exhaustive binary16 tests;
* endian-helper tests;
* checked-size helper tests;
* private implementation validation.

Keeping test-only C code below `test/c/` makes its non-production status explicit.

When SQLite build integration requires the file to appear as `src/test_pblob.c` in the unpacked SQLite tree, the build preparation script should copy it there. Its canonical project location should remain:

```text
test/c/test_pblob.c
```

##### `test/data/`

Contains committed generated reference vectors.

Separate files by representation so that changes remain reviewable:

```text
int8_vectors.tcl
f16_vectors.tcl
f32_vectors.tcl
```

Generated test data should never be mixed into production source.

---

#### `tools/`

Contains developer and build-automation tools.

```text
tools/
├── build.cmd
├── test.cmd
├── clean.cmd
├── prepare_sqlite.cmd
├── bundle_sources.tcl
└── gen_pblob_vectors.py
```

Use plural `tools`, which is conventional for a collection of independent development utilities.

##### `prepare_sqlite.cmd`

Responsibilities:

1. Verify `build/sqlite.zip`.
2. Recreate or update `build/sqlite/`.
3. Unpack the SQLite source checkpoint.
4. Copy or bundle `src/pblob.c`.
5. Copy test modules into the locations expected by SQLite.
6. apply only generated build integration, if necessary;
7. leave the project’s tracked sources untouched.

The script should be idempotent.

##### `build.cmd`

Responsibilities:

1. Ensure the SQLite source tree is prepared.
2. Create `build/out/`.
3. Invoke `nmake` with the required source and build-directory overrides.
4. Build the selected artifacts:
    * `sqlite3.c`;
    * `sqlite3.exe`;
    * `sqlite3.dll`;
    * `testfixture.exe`, where requested.
5. Write build output to `build/logs/`.

##### `test.cmd`

Responsibilities:

1. Build `testfixture.exe` if needed.
2. Execute `test/pblob_all.test`.
3. Optionally run the complete SQLite regression suite.
4. Return a nonzero process status on failure.

##### `clean.cmd`

Should remove generated outputs without deleting the cached SQLite archive unless explicitly requested.

Recommended distinction:

```text
clean.cmd             remove build/out, generated, logs, tmp
clean.cmd --all       also remove build/sqlite
clean.cmd --purge     also remove build/sqlite.zip
```

##### `bundle_sources.tcl`

Performs source preparation needed before amalgamation generation, including local include expansion where required.

##### `gen_pblob_vectors.py`

Developer-only generator for committed test vectors.

It should not be required for ordinary builds or test execution.

---

#### `vendor/`

Contains third-party code committed into the repository.

```text
vendor/
└── fp16/
    ├── LICENSE
    └── include/
        └── fp16/
            ├── fp16.h
            ├── bitcasts.h
            └── macros.h
```

This preserves the upstream include form:

```c
#include <fp16/fp16.h>
```

The small top-level forwarding header shown in the supplied material is unnecessary unless some existing source expects `<fp16.h>` rather than `<fp16/fp16.h>`. The upstream implementation itself is header-only and includes the bitcast and macro headers internally.
Include the upstream license and record:

* upstream repository;
* exact revision or release;
* local modifications, if any;
* update procedure.

A useful optional file is:

```text
vendor/fp16/README.md
```

containing that provenance.

Do not place SQLite itself under `vendor/`, because the SQLite checkpoint is an external build input rather than maintained project source.

---

#### `docs/`

Contains maintained project documentation.

```text
docs/
├── design.md
├── testing.md
├── implementation-plan.md
├── build.md
├── sql-api.md
└── decisions/
```

##### `design.md`

The consolidated Part 1 implementation specification.

##### `testing.md`

The consolidated Part 2 testing specification.

##### `implementation-plan.md`

The staged implementation plan.

##### `build.md`

Documents:

* MSVC Build Tools prerequisites;
* Tcl requirement;
* SQLite checkpoint preparation;
* exact build commands;
* build variants;
* testfixture construction;
* test execution;
* generated artifacts.

##### `sql-api.md`

User-facing SQL contract:

```sql
pblob_pack(json_array, format)
pblob_unpack(blob, format)
```

Include:

* supported formats;
* binary layout;
* input constraints;
* NULL behavior;
* overflow behavior;
* non-finite-value policy;
* examples.

##### `docs/decisions/`

Small architecture decision records are useful because this project makes several non-obvious choices.

Recommended initial decisions:

```text
0001-json-text-input.md
0002-headerless-blob-format.md
0003-fp16-conversion.md
```

Each decision record should contain:

```text
Status
Context
Decision
Consequences
```

This is preferable to letting important design reasoning exist only in chat history.

---

### Build Workspace

#### Recommended layout

```text
build/
├── sqlite.zip
├── sqlite/
├── out/
├── generated/
├── logs/
└── tmp/
```

#### `build/sqlite.zip`

The downloaded or manually supplied SQLite source checkpoint archive.

Because this is untracked, document its expected origin and optional checksum in `docs/build.md`.

For reproducibility, also keep a tracked metadata file outside `build/`, for example:

```text
sqlite-checkpoint.txt
```

Suggested contents:

```text
SQLite version: 3.x.y
Source archive: sqlite-src-xxxxxxx.zip
Source identifier: ...
SHA-256: ...
Retrieved: YYYY-MM-DD
```

That records the required source input without committing the archive.

A more structured alternative is:

```text
config/sqlite-checkpoint.txt
```

but a top-level file is reasonable for a project this small.

#### `build/sqlite/`

Unpacked SQLite source checkpoint.

This directory should be treated as disposable.

Do not manually develop inside it. Any project-owned changes must originate from:

```text
src/
test/
tools/
vendor/
```

and be copied or generated into `build/sqlite/`.

This rule prevents the unpacked SQLite tree from becoming an untracked source of truth.

#### `build/out/`

Actual out-of-tree SQLite build directory.

Recommended contents:

```text
build/out/
├── release/
├── test/
└── debug/
```

For example:

```text
build/out/release/
    sqlite3.c
    sqlite3.h
    sqlite3.dll
    sqlite3.lib
    sqlite3.exe

build/out/test/
    testfixture.exe
    testfixture.pdb

build/out/debug/
    sqlite3.exe
    sqlite3.pdb
```

This is clearer than:

```text
build/build/
```

because paths such as:

```text
build/build/build.log
```

quickly become confusing.

When only one build configuration is used initially, `build/out/` may contain outputs directly. Retaining configuration subdirectories from the beginning is usually worthwhile.

#### `build/generated/`

Contains generated intermediate sources, such as:

* bundled `pblob.c`;
* copied test modules;
* generated amalgamation input lists;
* patched or staged SQLite build files;
* generated `extra_autoext.c`.

This separates generated integration artifacts from compiled binaries.

#### `build/logs/`

Contains captured output:

```text
prepare.log
build-release.log
build-test.log
pblob-test.log
sqlite-fulltest.log
```

#### `build/tmp/`

Contains short-lived script intermediates.

The build scripts may delete this directory freely.

---

### Root-Level Files

#### `README.md`

Keep the root README concise.

Recommended sections:

1. Project purpose.
2. Supported formats.
3. SQL API.
4. Build summary.
5. Test summary.
6. Documentation links.
7. Licensing.

Do not duplicate the complete design specification in the README.

#### `LICENSE`

Project license.

Because SQLite source is not committed and the FP16 dependency has its own license, document third-party licensing separately.

#### `CHANGELOG.md`

Useful once functional releases begin.

Use a simple structure:

```text
Unreleased
Added
Changed
Fixed
```

#### `.gitignore`

Recommended baseline:

```gitignore
### Entire disposable build workspace
/build/

### Editor and IDE state
.vs/
.vscode/
*.user
*.suo

### MSVC outputs that might appear outside build/
*.obj
*.pdb
*.ilk
*.exp
*.lib
*.dll
*.exe

### Python generator cache
__pycache__/
*.py[cod]

### Temporary files
*.tmp
*.bak
*~
```

Since all compiled artifacts should remain under `build/`, the broad MSVC patterns are defensive rather than the primary exclusion mechanism.

---

### Recommended Tracked Tree

The resulting tracked repository remains compact:

```text
pblob/
├── .gitignore
├── LICENSE
├── README.md
├── CHANGELOG.md
├── sqlite-checkpoint.txt
├── src/
│   └── pblob.c
├── test/
│   ├── pblob.test
│   ├── pblob_vectors.tcl
│   ├── pblob_limits.test
│   ├── pblob_fault.test
│   ├── pblob_all.test
│   ├── c/
│   │   └── test_pblob.c
│   └── data/
│       ├── int8_vectors.tcl
│       ├── f16_vectors.tcl
│       └── f32_vectors.tcl
├── tools/
│   ├── build.cmd
│   ├── test.cmd
│   ├── clean.cmd
│   ├── prepare_sqlite.cmd
│   ├── bundle_sources.tcl
│   └── gen_pblob_vectors.py
├── vendor/
│   └── fp16/
│       ├── LICENSE
│       ├── README.md
│       └── include/
│           └── fp16/
│               ├── fp16.h
│               ├── bitcasts.h
│               └── macros.h
└── docs/
    ├── design.md
    ├── testing.md
    ├── implementation-plan.md
    ├── build.md
    ├── sql-api.md
    └── decisions/
        ├── 0001-json-text-input.md
        ├── 0002-headerless-blob-format.md
        └── 0003-fp16-conversion.md
```

The disposable local workspace is:

```text
build/
├── sqlite.zip
├── sqlite/
├── generated/
├── out/
│   ├── release/
│   ├── test/
│   └── debug/
├── logs/
└── tmp/
```

---

### Structural Principles

#### Keep one source of truth

Project-owned files live only in tracked project directories.

Never edit:

```text
build/sqlite/
build/generated/
build/out/
```

manually and then rely on those changes.

#### Separate source preparation from compilation

Use two distinct phases:

```text
prepare
    unpack SQLite
    stage project sources
    bundle local includes
    generate integration files

build
    generate amalgamation
    compile SQLite
```

This separation makes failures reproducible and easier to diagnose.

#### Keep generated files out of `src/`

The canonical `src/pblob.c` should remain human-maintained.

Any expanded or amalgamation-ready variant belongs in:

```text
build/generated/
```

or in the staged SQLite tree.

#### Keep tests beside the project, not only inside SQLite

The committed tests belong under the project’s `test/` directory.

The preparation process may copy them to the SQLite test tree, but the SQLite working copy must not become their canonical location.

#### Avoid unnecessary generic directories

Do not add these unless the project later needs them:

```text
include/
lib/
examples/
benchmarks/
cmake/
pkgconfig/
```

There is currently:

* no installable header;
* no standalone library;
* no package installation;
* no independent example program;
* no need for CMake.

A small project benefits from explicit structure, not maximal directory count.

#### Add benchmarks only when required

Performance tests are distinct from correctness tests.

When needed, add:

```text
benchmark/
├── benchmark_pack.sql
├── benchmark_unpack.sql
└── data/
```

Do not place benchmarks under `test/` if they have timing-dependent pass criteria.

---

### Final Recommendation

Use `build/` as the single ignored workspace, but replace:

```text
build/build/
```

with:

```text
build/out/
```

The core design is:

```text
tracked project sources
    src/
    test/
    tools/
    vendor/
    docs/

disposable external workspace
    build/sqlite.zip
    build/sqlite/
    build/generated/
    build/out/
```

This fits the project’s actual nature: a small, embedded, amalgamation-only SQLite extension with one production source module, substantial integration tests, and one vendored numeric-conversion dependency.
