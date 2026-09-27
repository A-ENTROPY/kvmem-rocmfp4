@echo off
REM ============================================================================
REM  KVMem + ROCmFP4 + DFlash2 launcher (ASCII wrapper)
REM  Logic and Chinese messages live in start-kvmem.ps1 (UTF-8 with BOM).
REM
REM  Usage:
REM     start-kvmem.bat -Model "G:\models\Qwen3.8-27B-Q4_0_ROCMFP4_STRIX.gguf" ^
REM                     -Draft "G:\models\Qwen3.8-27B-DFlash2-Q4_K_M.gguf"
REM     start-kvmem.bat -Model "..." -Context 262144 -Budget 36864 -Reserve 32768
REM     start-kvmem.bat -Spec none         (close speculative decoding)
REM     start-kvmem.bat -Model "...-mtp.gguf" -Spec mtp   (use MTP instead of DFlash2)
REM ============================================================================
setlocal EnableExtensions
set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%PS%" set "PS=powershell"
"%PS%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0start-kvmem.ps1" %*
set "RC=%ERRORLEVEL%"
if not "%RC%"=="0" (
    echo.
    echo [FAILED] exit code = %RC%
    pause
)
endlocal
exit /b %RC%
