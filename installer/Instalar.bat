@echo off
setlocal
title Controle Automatico de Rede - Instalacao

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
    -File "%~dp0Config.ps1"

if %errorlevel% neq 0 (
    echo.
    echo ============================================
    echo ERRO durante a configuracao.
    echo ============================================
    echo.
    pause
    exit /b 1
)

echo.
echo ============================================
echo INSTALACAO CONCLUIDA COM SUCESSO
echo ============================================
echo.

pause
endlocal
