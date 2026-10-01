#requires -version 5.1

$ErrorActionPreference = "Stop"

$BasePath = "C:\ProgramData\ControleRede"
$TaskName = "Controle Automático de Rede"

$Identity = [Security.Principal.WindowsIdentity]::GetCurrent()

$Principal = New-Object `
    Security.Principal.WindowsPrincipal($Identity)

$IsAdmin = $Principal.IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)

if (-not $IsAdmin) {

    Start-Process `
        powershell.exe `
        -ArgumentList (
            "-NoProfile -ExecutionPolicy Bypass " +
            "-File `"$PSCommandPath`""
        ) `
        -Verb RunAs

    exit
}

Stop-ScheduledTask `
    -TaskName $TaskName `
    -ErrorAction SilentlyContinue

Unregister-ScheduledTask `
    -TaskName $TaskName `
    -Confirm:$false `
    -ErrorAction SilentlyContinue

if (Test-Path $BasePath) {

    Remove-Item `
        -Path $BasePath `
        -Recurse `
        -Force
}

Write-Host ""
Write-Host "ControleRede desinstalado."
Write-Host ""
