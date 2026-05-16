## SUP-able functions

| Function                    | Arguments      | Description                                                                |
|-----------------------------|----------------|----------------------------------------------------------------------------|
| `cleanup_module_accounts/1` | `(ModuleName)` | Cleanup account(s) by name as generated in ModuleName                      |
| `modules/0`                 |                | List modules that will be run for seq tests                                |
| `run_module/1`              | `(Module)      | Run a module's quickcheck tests (correct and correct_parallel if exported) |
| `run_modules/0`             |                | Run all quickcheck tests in all modules                                    |
| `run_seq_module/1`          | `(Module)`     | Run a module's sequential tests in parallel and standalone                 |
| `run_seq_modules/0`         |                | Run all sequential tests in parallel and standalone                        |
