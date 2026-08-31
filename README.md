# insuflo_misra_toolchain

[![MISRA lint](https://github.com/Aash205/misrachecker/actions/workflows/misra-lint.yml/badge.svg)](https://github.com/Aash205/misrachecker/actions/workflows/misra-lint.yml)

MISRA-flavored lint toolchain for STM32CubeIDE firmware projects. Tooling only, no firmware
source. Compilation stays exclusively in STM32CubeIDE; this adds linting, formatting, and
pre-commit checks in VSCode, the terminal, and CI.

## What you get

- Real MISRA C:2012 (Cppcheck `misra.py`, free) on hand-written `.c`/`.h`
- Best-effort MISRA-C++-flavored linting (clang-tidy, **not certified**) on hand-written `.cpp`/`.hpp`
- clang-format (Allman, 4-space) + pre-commit hooks that auto-format and lint staged files
- Vendor/generated code (`generated/`, HAL, CMSIS, Middlewares) fully excluded
- VSCode integration (clangd + Cppcheck extensions) and lint-only CI
- Windows via Git Bash (ships with Git for Windows)

## Setup (one shot — Linux, macOS, or Windows via Git Bash)

```bash
./scripts/setup.sh
```

## Installing into a firmware repo

```bash
./scripts/install.sh /path/to/your-firmware-repo
cd /path/to/your-firmware-repo && ./scripts/setup.sh
./scripts/gen_compile_commands.sh <cubeide-project-dir>   # once, and after CubeMX regen
```

## Try it here

```bash
./scripts/lint.sh demo
```

## Showing findings in STM32CubeIDE's Problems view (no plugin)

Project Properties → C/C++ Build → Settings → **Build Steps** tab → Post-build steps command:

```
"${ProjDirPath}/scripts/git-bash-resolve.cmd" "${ProjDirPath}/scripts/lint.sh" --cubeide "${ProjDirPath}"
```

(Linux/macOS: skip the resolver — just `"${ProjDirPath}/scripts/lint.sh" --cubeide "${ProjDirPath}"`.)

Details, licensing, and the MISRA C++ upgrade path: [`misra/README.md`](misra/README.md).
