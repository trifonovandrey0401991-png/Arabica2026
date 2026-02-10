@echo off
chcp 65001 >nul 2>&1
echo ======================================================================
echo   ARABICA — Full Test Suite (3 levels)
echo   %date% %time%
echo ======================================================================
echo.

set PASS=0
set FAIL=0

:: ---- Level 1 + 2: API Smoke + Structure ----
echo [Level 1+2] API Smoke ^& Structure Tests
echo ------------------------------------------
node "%~dp0api-test.js"
if %ERRORLEVEL% EQU 0 (
    echo [PASS] API tests passed
    set /a PASS+=2
) else (
    echo [FAIL] API tests failed!
    set /a FAIL+=1
)
echo.

:: ---- Level 3: Flutter Analyze ----
echo [Level 3] Flutter Analyze
echo ------------------------------------------
cd /d "%~dp0.."
call flutter analyze --no-fatal-infos 2>&1
if %ERRORLEVEL% EQU 0 (
    echo [PASS] Flutter analyze passed
    set /a PASS+=1
) else (
    echo [FAIL] Flutter analyze failed!
    set /a FAIL+=1
)
echo.

:: ---- Summary ----
echo ======================================================================
if %FAIL% EQU 0 (
    echo   RESULT: ALL 3 LEVELS PASSED
) else (
    echo   RESULT: %FAIL% LEVEL(S) FAILED
)
echo ======================================================================

exit /b %FAIL%
