# ThreadX example fixture — build & lint

ST's `Tx_Thread_Creation` example (x-cube-azrtos-l4), standard STM32 layout at repo root, with a
bundled MISRA lint toolchain (`scripts/`, `misra/`). `Core/` is linted; `Drivers/`/`Middlewares/`
are excluded vendor code (deviations documented in `misra/suppressions.txt` — don't "fix"
those).

## What it does

Creates 3 threads (MainThread, ThreadOne, ThreadTwo) demonstrating priority/preemption-threshold
changes on the fly. `LED_GREEN` toggles every 500ms (5s), then every 200ms (5s), repeats 3x, then
settles to toggling every 1s forever. `LED_RED` toggles every 1s and an error message prints over
serial on any error.

- Board: NUCLEO-L4R5ZI (STM32L4R5xx)
- Serial: LPUART1, 115200 8N1, no flow control

## Setup (one shot — Linux, macOS, or Windows via Git Bash)

```bash
./scripts/setup.sh
```

## Path A — STM32CubeIDE

1. File → Open Projects from File System → `STM32CubeIDE/`
2. Build
3. Project Properties → C/C++ Build → Settings → check "Generate compile_commands.json" →
   rebuild
4. `./scripts/gen_compile_commands.sh STM32CubeIDE`

To also see findings in STM32CubeIDE's own Problems view (no plugin): Project Properties →
C/C++ Build → Settings → **Build Steps** tab → Post-build steps command:

```
"${ProjDirPath}/scripts/git-bash-resolve.cmd" "${ProjDirPath}/scripts/lint.sh" --cubeide "${ProjDirPath}"
```

(Linux/macOS: skip the resolver — just `"${ProjDirPath}/scripts/lint.sh" --cubeide "${ProjDirPath}"`.)

## Path B — VS Code + STM32Cube extension (CMake)

1. Install recommended extensions (`.vscode/extensions.json`)
2. Import `Tx_Thread_Creation.ioc` via the STM32Cube extension, pick **CMake** as the toolchain
3. Run the CMake configure step
4. `./scripts/gen_compile_commands.sh .`

## Lint / format

- `./scripts/lint.sh Core`, `./scripts/format.sh check|fix Core`
- VS Code tasks: **MISRA: Lint**, **MISRA: Format fix**
- `./scripts/install-hooks.sh` once → runs on every `git commit`

## Troubleshooting

- `lint.sh` exits **2** (not 1) → no `compile_commands.json` yet, do the build step first.
- Need IAR/Keil? Regenerate from `Tx_Thread_Creation.ioc` in CubeMX — `EWARM`/`MDK-ARM` were
  removed (stale paths after the flatten).

Toolchain licensing / MISRA C++ upgrade path: [`misra/README.md`](misra/README.md).
