#requires -version 5.1

$ErrorActionPreference = "Stop"

$Version = "1.1.0"

$BasePath = "C:\ProgramData\ControleRede"
$ScriptPath = Join-Path $BasePath "ControleRede.ps1"
$LogPath = Join-Path $BasePath "logs"
$StateFile = Join-Path $BasePath "estado.json"

$TaskName = "Controle Automático de Rede"

$ProjectRoot = Split-Path -Parent $PSScriptRoot

$SourceScript = Join-Path `
    $ProjectRoot `
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
        -ArgumentList (
            "-NoProfile -ExecutionPolicy Bypass " +
            "-File `"$PSCommandPath`""
        ) `
        -Verb RunAs

    exit
}

if (-not (Test-Path $SourceScript)) {

    throw (
        "ControleRede.ps1 não encontrado: " +
        $SourceScript
    )
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
    -Path $SourceScript `
    -Destination $ScriptPath `
    -Force

if (-not (Test-Path $StateFile)) {

    '{"DisabledWifiAdapters":[]}' |
        Set-Content `
            -Path $StateFile `
            -Encoding UTF8
}

# Remove instalação anterior da tarefa, se existir.
Unregister-ScheduledTask `
    -TaskName $TaskName `
    -Confirm:$false `
    -ErrorAction SilentlyContinue

$Action = New-ScheduledTaskAction `
    -Execute "powershell.exe" `
    -Argument (
        "-NoProfile -NonInteractive " +
        "-ExecutionPolicy Bypass " +
        "-WindowStyle Hidden " +
        "-File `"$ScriptPath`""
    )

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
    -RestartInterval (
        New-TimeSpan -Minutes 1
    )

Register-ScheduledTask `
    -TaskName $TaskName `
    -Action $Action `
    -Trigger $Trigger `
    -Principal $TaskPrincipal `
    -Settings $Settings `
    -Description (
        "ControleRede $Version - " +
        "controle automático Wi-Fi/Ethernet por link físico."
    ) `
    -Force | Out-Null

Start-ScheduledTask `
    -TaskName $TaskName

Write-Host ""
Write-Host "============================================"
Write-Host "ControleRede $Version instalado."
Write-Host "============================================"
Write-Host ""
Write-Host "Tarefa: $TaskName"
Write-Host "Destino: $BasePath"
Write-Host ""
