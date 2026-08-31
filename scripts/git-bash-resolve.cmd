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

for /L %%i in (0,1,3) do (
    if exist "!CANDIDATES[%%i]!" (
        "!CANDIDATES[%%i]!" %*
        exit /b !ERRORLEVEL!
    )
)

echo ERROR: bash.exe not found in any known Git for Windows install location. 1>&2
echo   Checked: %PF%\Git\bin, %PF86%\Git\bin, %LAD%\Programs\Git\bin, %UP%\scoop\apps\git\current\bin 1>&2
echo   Add your install path to scripts\git-bash-resolve.cmd's CANDIDATES list. 1>&2
exit /b 1
