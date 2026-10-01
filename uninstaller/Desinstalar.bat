@echo off
setlocal
title Controle Automatico de Rede - Desinstalacao

net session >nul 2>&1

if %errorlevel% neq 0 (
    echo.
    echo Solicitando privilegios de Administrador...
    echo.

    powershell.exe -NoProfile -Command "Start-Process '%~f0' -Verb RunAs"

    exit /b
)

powershell.exe ^
    -NoProfile ^
    -ExecutionPolicy Bypass ^
    -File "%~dp0Desinstalar.ps1"

if %errorlevel% neq 0 (
    echo.
    echo ============================================
    echo ERRO durante a desinstalacao.
    echo ============================================
    echo.
    pause
    exit /b 1
)

echo.
echo ============================================
echo DESINSTALACAO CONCLUIDA
echo ============================================
echo.

pause
endlocal
