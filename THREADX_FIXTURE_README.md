# ThreadX example fixture — setup & flow

This is STMicroelectronics' `Tx_Thread_Creation` example (x-cube-azrtos-l4, NUCLEO-L4R5ZI),
flattened to repo root in standard STM32 layout (`Core/{Inc,Src,Startup}`, `Drivers/`,
`Middlewares/`), used to verify the MISRA toolchain end-to-end against a real multi-file STM32
project. `Core/` is real, hand-written app code and is linted like any other project code;
`Drivers/`/`Middlewares/` are untouched vendor libraries and are excluded. See
`misra/suppressions.txt` for justified MISRA deviations (CMSIS/HAL register access, ThreadX's
own API signatures, weak-callback linkage) — those aren't bugs, don't "fix" them.

`Tx_Thread_Creation.ioc` was hand-built from the real `STM32CubeIDE/.cproject`'s MCU/clock/pin
config since ST didn't ship one with this example — open it in CubeMX/CubeIDE, eyeball the
pinout/clock tree, then regenerate.

Two supported ways to build. Both end up at the same lint/format step.

## Path A — STM32CubeIDE (classic managed build)

1. STM32CubeIDE → File → Open Projects from File System → point at `STM32CubeIDE/` (has
   `.project`/`.cproject` already, no need to regenerate from the `.ioc` unless you're changing
   pins/clock).
2. Build (Debug or Release).
3. Project Properties → C/C++ Build → Settings → check **Generate compile_commands.json** →
   rebuild.
4. From repo root: `./scripts/gen_compile_commands.sh STM32CubeIDE`

## Path B — VS Code + STM32Cube VS Code extension (CMake)

1. Open this repo folder in VS Code. Install the recommended extensions
   (`.vscode/extensions.json` — includes `stmicroelectronics.stm32-vscode-extension`).
2. Use the STM32Cube extension to import/generate from `Tx_Thread_Creation.ioc`, choosing
   **CMake** as the toolchain (the `.ioc`'s saved default is `STM32CubeIDE`, since that's this
   repo's primary documented path — pick CMake explicitly at generation time instead; CubeMX/the
   extension let you override it). This produces `CMakeLists.txt` + `CMakePresets.json`.
3. Run the CMake configure step (Debug or Release preset) — produces
   `build/<preset>/compile_commands.json`.
4. From repo root: `./scripts/gen_compile_commands.sh .`
   (`gen_compile_commands.sh` searches up to 4 levels deep for a native `compile_commands.json`
   and picks the most recently built one — works the same whether it came from CubeIDE's CDT
   export or a CMake build dir, so the same command works for either path.)

## Linting / formatting (either path, once `compile_commands.json` exists)

- Manual: `./scripts/lint.sh Core`, `./scripts/format.sh check Core` (or `fix`) from repo root.
- VS Code tasks (`.vscode/tasks.json`): **MISRA: Lint**, **MISRA: Format fix**, etc. — the Lint
  task and tools-check run automatically on folder open; format-on-save is wired via
  `triggerTaskOnSave`.
- `pre-commit`: run `./scripts/install-hooks.sh` once, then every `git commit` auto-formats and
  lints staged `Core/*.c|h` files (Drivers/Middlewares stay excluded; `require_serial: true` on
  the lint hook is required — see `.pre-commit-config.yaml` — so cppcheck sees all staged files
  together instead of pre-commit's default per-batch parallelization, which breaks its
  cross-file whole-program analysis).

## Notes

- `EWARM/`, `MDK-ARM/`, and `X-CUBE-AZRTOS-L4_ProjectsList.html` (ST's index across the whole
  AZRTOS pack, not just this one example) were removed — their relative paths broke when the
  fixture was flattened to repo root, and this toolchain only supports STM32CubeIDE/CMake
  anyway. Regenerate an IAR/Keil project from `Tx_Thread_Creation.ioc` in CubeMX if you need one.
- Without a real `compile_commands.json` (steps above), cppcheck can't resolve HAL/ThreadX
  macros and `lint.sh` correctly reports **exit 2** ("toolchain misconfigured"), distinct from
  exit 1 (real MISRA findings) — do the compile-commands step first if you see that.
