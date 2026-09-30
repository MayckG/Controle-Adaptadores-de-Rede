#requires -version 5.1

$ErrorActionPreference = "Stop"

$BasePath = "C:\ProgramData\ControleRede"
$ScriptPath = Join-Path $BasePath "ControleRede.ps1"
$LogPath = Join-Path $BasePath "logs"
$StateFile = Join-Path $BasePath "estado.json"

$TaskName = "Controle Automático de Rede"

$SourceScript = Join-Path `
    (Split-Path -Parent $PSScriptRoot) `
    "src\ControleRede.ps1"

$Identity = [Security.Principal.WindowsIdentity]::GetCurrent()

$Principal = New-Object `
    Security.Principal.WindowsPrincipal($Identity)

$IsAdmin = $Principal.IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)

if (-not $IsAdmin) {

    Start-Process `
        powershell.exe `
        -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" `
        -Verb RunAs

    exit
}

if (-not (Test-Path $SourceScript)) {
    throw "ControleRede.ps1 não encontrado: $SourceScript"
}

New-Item `
    -Path $BasePath `
    -ItemType Directory `
    -Force | Out-Null

New-Item `
    -Path $LogPath `
    -ItemType Directory `
    -Force | Out-Null

Copy-Item `
    $SourceScript `
    $ScriptPath `
    -Force

if (-not (Test-Path $StateFile)) {

    '{"DisabledWifiAdapters":[]}' |
        Set-Content `
        -Path $StateFile `
        -Encoding UTF8
}

Unregister-ScheduledTask `
    -TaskName $TaskName `
    -Confirm:$false `
    -ErrorAction SilentlyContinue

$Action = New-ScheduledTaskAction `
    -Execute "powershell.exe" `
    -Argument "-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$ScriptPath`""

$Trigger = New-ScheduledTaskTrigger `
    -AtStartup

$TaskPrincipal = New-ScheduledTaskPrincipal `
    -UserId "SYSTEM" `
    -LogonType ServiceAccount `
    -RunLevel Highest

$Settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -RestartCount 3 `
    -RestartInterval (New-TimeSpan -Minutes 1)

Register-ScheduledTask `
    -TaskName $TaskName `
    -Action $Action `
    -Trigger $Trigger `
    -Principal $TaskPrincipal `
    -Settings $Settings `
    -Description "Controla automaticamente Wi-Fi conforme o link físico Ethernet." `
    -Force | Out-Null

Start-ScheduledTask `
    -TaskName $TaskName

Write-Host ""
Write-Host "Controle Automático de Rede instalado."
Write-Host "Tarefa: $TaskName"
Write-Host "Destino: $BasePath"
Write-Host ""
