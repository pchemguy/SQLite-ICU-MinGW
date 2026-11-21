# Procedural revision of `sqlite_build.sh`

Refactor the native Linux driver so a maintainer can read the complete workflow in `main()` and jump directly to the procedure responsible for any step. The model is the Windows driver's `:MAIN`, which calls named subroutines for source acquisition, extension preparation, compilation, and artifact collection. [Bash driver](sqlite_build.sh) · [Windows coordinator](../MSVC/sqlite_msbuild.bat#L39-L106)

## Entry point and source layout

Put `main()` immediately after the shebang, script summary, shell settings, and shared declarations. Arrange the other functions below it in workflow order, with each phase's helpers together. End the file with a fenced dispatcher containing the single invocation `main "$@"`. By then Bash has read every definition. All build actions belong inside functions.

```bash
# ============================================================================ MAIN BEGIN
# Run the requested action and publish the SQLite package after verification.
main() {
    parse_arguments "$@"
    if [[ $action == help ]]; then
        usage
        return 0
    fi

    select_preset "$preset"
    resolve_paths
    if [[ $action == clean ]]; then
        clean_output_root
        return
    fi

    open_build_root
    resolve_build_settings
    load_build_helpers
    ensure_dependencies
    create_workspace
    prepare_sqlite_source

    set_build_options
    collect_extensions
    report_build_settings
    write_build_inputs
    configure_sqlite_if_needed
    prepare_target_sources
    compile_sqlite

    stage_package
    verify_package
    publish_package
    report_success
}
# ============================================================================ MAIN END
```

Give **every Bash function** a matching pair of `NAME BEGIN` and `NAME END` comment fences, using the uppercase spelling of its function name. Place a brief `#` docstring **immediately above the declaration**, inside the opening fence. State the function's job and, when significant, its arguments, output, special return status, or effect on shared state. Apply the convention to `main`, short helpers such as `die`, the existing sourced Bash helpers, and hook functions such as `prepare_pblob`. The same pattern makes a multistep phase readable on its own.

```bash
# ============================================================================ PREPARE_TARGET_SOURCES BEGIN
# Generate the target source tree and restage selected extensions when needed.
prepare_target_sources() {
    prepare_target_tree
    if extensions_need_staging; then
        invalidate_extension_stamp
        copy_extension_sources
        run_extension_prepare_hooks
        select_tcl_interpreter
        generate_extension_dispatcher
        verify_dispatcher_entries
        bundle_extension_headers
        mark_extensions_ready
    fi
}
# ============================================================================ PREPARE_TARGET_SOURCES END
```

## Procedure boundaries

Each procedure owns one result a caller can rely on. Keep commands that establish that result together. For example, installing a versioned shared library includes creating its two symlinks. Verifying and publishing that library are separate steps.

| Coordinator step | Subroutines and responsibilities |
|---|---|
| `parse_arguments`, `select_preset`, `resolve_build_settings` | Parsing records the action and preset. Help returns before touching the filesystem. Keep `bare`, `bare-icu`, `bare-icu-ext`, and `full` in one `case`, with `full` as the default. Apply environment overrides, then call `validate_features` and `set_toolchain_defaults` for builds. |
| `resolve_paths`, `open_build_root`, `clean_output_root` | Resolve the driver directory and the caller's `OUT_DIR`. Share `lock_output_root` and the ownership-marker check between build and clean. Build may claim a fresh root. Clean succeeds for a missing root, rejects an unmanaged root, and removes managed outputs while retaining the cache. |
| `load_build_helpers`, `ensure_dependencies`, `create_workspace` | Source the existing dependency and source helpers. Retain the ICU and zlib probes, missing-package installation, and final probe. Create the temporary work directory and register `cleanup_workspace` for exit and signal handling. |
| `prepare_sqlite_source` | `fetch_sqlite_archive` uses the existing cache and `download`. `refresh_sqlite_source` compares the archive digest, validates the extracted tree with `unpack_zip`, and installs it only when needed. |
| `set_build_options`, `collect_extensions` | Use `set_sqlite_defaults`, `add_icu_flags`, and `add_zlib_flags` to assemble options. Call `register_stock_extensions`, `load_project_hooks`, then `finalize_extension_list`. Preserve stock source order, sorted hook discovery, and the generated dispatcher as the last `EXTRA_SRC` entry. |
| `write_build_inputs`, `configure_sqlite_if_needed` | `write_toolchain_inputs`, `write_dependency_inputs`, and `write_input_digests` produce the manifest in its existing order. Compare it before configuring. On a change, configure the build tree, call `verify_configured_zlib` when required, then save the manifest. |
| `prepare_target_sources` | `prepare_target_tree` runs `make .target_source` and recovers a missing generated header. The staging predicate checks that extensions are selected and compares the stamp, target-source timestamp, and expected files. Invalidate the stamp before editing. Write it only after the Tcl or bundled Jim run completes and the headers are bundled. |
| `compile_sqlite`, `stage_package` | Use the existing `make_sqlite` helper for the CLI, shared library, and static archive. Call `stage_cli`, `stage_libraries`, `stage_headers`, and `write_pkgconfig` to populate the temporary prefix. |
| `verify_package`, `publish_package` | Check the staged CLI version and run the registered extension SQL checks. Then `ensure_package_links`, `switch_package_generation`, and `prune_old_generations` establish the public links, switch the package atomically, and retire older generations in that order. |

## State and failure handling

- Keep shared paths, build options, ordered source arrays, and callback lists in one documented declaration block. Use `local` for loop variables and intermediate paths. Pass arguments to leaf functions when they operate on a single archive, path, or package.
- Preserve the sourced hook interface, including `add_source`, `project_source`, `header_archives`, `prepare_steps`, and `smoke_tests`. PBLOB's FP16 archive path must still be available when its deferred preparation function runs. Keep stock `regexp.c` ahead of RegexpMatches.
- Hold the output lock through publication or clean. Give the exit trap access to `work` after `main` returns. Preserve the original failure or signal status during cleanup and the previously published package on a staging failure. Call state-changing phases as ordinary commands under `set -euo pipefail`. Use conditionals for predicates with intentional true and false returns.

## Implementation sequence and acceptance

1. Record the merged driver's behavior for help, clean, preset selection, cache reuse, and package publication. Use the same cached SQLite and extension sources for before-and-after comparisons.
2. Extract the leaf procedures in workflow order, reusing `tool/dependencies.sh`, `tool/sources.sh`, and the existing hooks. Wire the proposed `main()` and bottom dispatcher. Review every function for a single purpose, a directly preceding docstring, and matching fences.
3. Run `bash -n` on each Bash file and ShellCheck on the driver, helpers, and hooks. Use focused pytest checks for help with an absent output root, clean on missing and unmanaged roots, and cleanup after a failed build. Check that two builds sharing one output root serialize.
4. Run `python3 -m pytest -v tests` from `Current/GCC` on Debian and Fedora. Exercise all four presets, each custom extension disabled individually, and the project-only selection. Verify the 15 stock modules and ICUex, PBLOB, and RegexpMatches through the relocated CLI and both library clients. Check stock exclusions on plain shared and static library connections because the shell registers several modules itself. The suite also exercises offline reuse and a failed package copy. The edited driver changes its own manifest digest, so allow the first rebuild to reconfigure and check reuse on the following run.
