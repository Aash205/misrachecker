# Coding Conventions

## Formatting

- Style: Allman braces, 4-space indent, 100-col limit (`.clang-format`).
- Line endings: **CRLF** for `.c`/`.h`/`.cpp`/`.hpp` (matches firmware template). Everything
  else (scripts, docs, configs) stays LF.
- Comments: `///` trailing comments, column-aligned. Don't hand-pad — `clang-format` aligns
  them for you.
- Run `scripts/format.sh check|fix [target...]` before committing. Pre-commit does this
  automatically for staged files.

## Naming

**Not enforced by tooling** — no linter rule, and MISRA doesn't require a casing style.

In hand-written code, follow the existing ST/HAL convention rather than inventing one:

- Functions: capitalized module prefix + snake_case tail — `Motor_control`,
  `HAL_GPIO_WritePin`, `SystemClock_Config`.
- Params: PascalCase — `State`, `Speed`, `GPIOx`.
- Macros: `UPPER_SNAKE_CASE` — `MOTOR_SPEED`, `ENABLE_PIN_PORT`.
- Structs/members/locals: lowercase snake_case — `motor_info`, `speed`, `direction`.

## Don't touch generated / vendor code

These are never hand-edited and are excluded from linting (`misra/exclude-paths.txt`). Leave
them exactly as CubeMX/CubeIDE produced them:

- `Drivers/*HAL_Driver/*`, `*/CMSIS/*`, `*/Middlewares/*` — vendor libraries.
- `*/generated/*` — anything under a `generated/` folder.
- `syscalls.c`, `sysmem.c`, `system_stm32*.c` — CubeIDE runtime stubs.
- `stm32*_it.c` / `stm32*_it.h`, `*_hal_msp.c`, `*_timebase_tim.c` — interrupt/MSP skeletons.
- `stm32*_hal_conf.h`, `FreeRTOSConfig.h` — CubeMX config headers.
- `Core/Startup/*` — reset handler, vector table, linker scripts.

**Exception:** `main.c` (and `freertos.c` if present) — real init/task logic lives in their
`USER CODE` blocks, so they stay linted. Only touch code inside `USER CODE BEGIN/END` markers;
never edit CubeMX-owned sections outside them, or the next `.ioc` regeneration wipes your
changes.

## MISRA

- `.c`/`.h`: real MISRA C:2012 via Cppcheck (`misra.py`). Findings cite real rule numbers.
- `.cpp`/`.hpp`: best-effort MISRA C++ approximation via `.clang-tidy` — not certified, no
  real rule numbers.
- Details: `misra/README.md`.

## Before committing

```
scripts/format.sh check
scripts/lint.sh
```

Both also run via pre-commit (`scripts/setup.sh` to install).
