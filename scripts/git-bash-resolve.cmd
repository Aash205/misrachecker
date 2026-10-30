@echo off
setlocal enabledelayedexpansion

REM Resolves and execs Git for Windows' bash.exe by checking known install
REM locations directly (never via PATH -- if WSL is also installed, PATH
REM commonly resolves bare `bash` to WSL's launcher instead of Git Bash,
REM which then silently runs scripts inside WSL's filesystem, not the
REM Windows one .vscode/tasks.json expects).
REM
REM Custom install path not listed below? Add a line to the CANDIDATES
REM block, same format as the others.

set "PF=%ProgramFiles%"
set "PF86=%ProgramFiles(x86)%"
set "LAD=%LOCALAPPDATA%"
set "UP=%USERPROFILE%"

set "CANDIDATES[0]=%PF%\Git\bin\bash.exe"
set "CANDIDATES[1]=%PF86%\Git\bin\bash.exe"
set "CANDIDATES[2]=%LAD%\Programs\Git\bin\bash.exe"
set "CANDIDATES[3]=%UP%\scoop\apps\git\current\bin\bash.exe"

REM Ensure arm-none-eabi toolchain is on PATH for CMake, lint, and build tasks
where arm-none-eabi-gcc >nul 2>nul
if errorlevel 1 (
    for /d %%V in ("%LAD%\stm32cube\bundles\gnu-tools-for-stm32\*") do (
        if exist "%%V\bin\arm-none-eabi-gcc.exe" set "PATH=%%V\bin;!PATH!"
    )
    if defined CUBE_BUNDLE_PATH (
        for /d %%V in ("%CUBE_BUNDLE_PATH%\gnu-tools-for-stm32\*") do (
            if exist "%%V\bin\arm-none-eabi-gcc.exe" set "PATH=%%V\bin;!PATH!"
        )
    )
    for /d %%I in ("C:\ST\STM32CubeIDE_*") do (
        for /d %%P in ("%%I\STM32CubeIDE\plugins\com.st.stm32cube.ide.mcu.externaltools.gnu-tools-for-stm32.*") do (
            if exist "%%P\tools\bin\arm-none-eabi-gcc.exe" set "PATH=%%P\tools\bin;!PATH!"
        )
    )
    if exist "C:\ST\STM32CubeCLT\GNU-tools-for-STM32\bin\arm-none-eabi-gcc.exe" (
        set "PATH=C:\ST\STM32CubeCLT\GNU-tools-for-STM32\bin;!PATH!"
    )
    for /d %%V in ("%PF%\Arm GNU Toolchain arm-none-eabi\*") do (
        if exist "%%V\bin\arm-none-eabi-gcc.exe" set "PATH=%%V\bin;!PATH!"
    )
    for /d %%V in ("%PF86%\Arm GNU Toolchain arm-none-eabi\*") do (
        if exist "%%V\bin\arm-none-eabi-gcc.exe" set "PATH=%%V\bin;!PATH!"
    )
)

for /L %%i in (0,1,3) do (
    if exist "!CANDIDATES[%%i]!" (
        REM Standalone bash.exe does not always initialize Git's usr\bin
        REM PATH entries. Put Git's own utilities first so commands such as
        REM find and uname cannot resolve to unrelated Windows executables.
        for %%B in ("!CANDIDATES[%%i]!") do set "PATH=%%~dpB..\usr\bin;%%~dpB;!PATH!"
        "!CANDIDATES[%%i]!" --login %*
        set "BASH_EXIT=!ERRORLEVEL!"
        goto :return_bash_exit
    )
)

echo ERROR: bash.exe not found in any known Git for Windows install location. 1>&2
echo   Checked: %PF%\Git\bin, %PF86%\Git\bin, %LAD%\Programs\Git\bin, %UP%\scoop\apps\git\current\bin 1>&2
echo   Add your install path to scripts\git-bash-resolve.cmd's CANDIDATES list. 1>&2
exit /b 1

:return_bash_exit
exit /b !BASH_EXIT!
