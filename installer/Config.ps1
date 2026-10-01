#requires -version 5.1
<#
.SYNOPSIS
    Instala ou atualiza o ControleRede.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Version = '1.2.0'

$BasePath   = Join-Path $env:ProgramData 'ControleRede'
$ScriptPath = Join-Path $BasePath 'ControleRede.ps1'
$ConfigPath = Join-Path $BasePath 'config.json'
$LogPath    = Join-Path $BasePath 'logs'
$StateFile  = Join-Path $BasePath 'estado.json'

$TaskName = 'Controle Automático de Rede'

$ProjectRoot  = Split-Path -Parent $PSScriptRoot
$SourceScript = Join-Path $ProjectRoot 'src\ControleRede.ps1'
$SourceConfig = Join-Path $ProjectRoot 'src\config.json'

# SIDs fixos: funcionam em qualquer idioma do Windows
# ("Administradores" no Windows em português, por exemplo).
$SidSystem         = '*S-1-5-18'
$SidAdministrators = '*S-1-5-32-544'
$SidUsers          = '*S-1-5-32-545'

function Assert-Administrator {

    $Identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
    $Principal = New-Object Security.Principal.WindowsPrincipal($Identity)

    if (-not $Principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Execute o instalador como Administrador (use Instalar.bat).'
    }
}

function Invoke-Icacls {
    param([Parameter(Mandatory)][string[]]$Arguments)

    & icacls.exe @Arguments | Out-Null

    if ($LASTEXITCODE -ne 0) {
        throw "icacls falhou (código $LASTEXITCODE): icacls $($Arguments -join ' ')"
    }
}

# A tarefa roda como SYSTEM a partir desta pasta. Usuários comuns
# não podem ter permissão de escrita aqui, senão poderiam alterar o
# script e executar código como SYSTEM.
function Set-SecureFolder {
    param([Parameter(Mandatory)][string]$Path)

    New-Item -Path $Path -ItemType Directory -Force | Out-Null

    # Assume a propriedade de tudo (inclusive itens criados por terceiros).
    Invoke-Icacls @($Path, '/setowner', $SidAdministrators, '/T', '/C', '/Q')

    # Pasta raiz: sem herança do ProgramData; SYSTEM e Administradores
    # com controle total; Usuários somente leitura.
    Invoke-Icacls @(
        $Path, '/inheritance:r',
        '/grant:r', "${SidSystem}:(OI)(CI)F",
        '/grant:r', "${SidAdministrators}:(OI)(CI)F",
        '/grant:r', "${SidUsers}:(OI)(CI)RX",
        '/Q'
    )

    # Conteúdo existente: remove ACLs explícitas e passa a herdar da raiz.
    if (@(Get-ChildItem -LiteralPath $Path -Force).Count -gt 0) {
        Invoke-Icacls @((Join-Path $Path '*'), '/reset', '/T', '/C', '/Q')
    }
}

function Write-Utf8Bom {
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Destination
    )

    # Garante UTF-8 com BOM: o Windows PowerShell 5.1 lê scripts sem BOM
    # como ANSI e corrompe textos acentuados.
    $Text = [IO.File]::ReadAllText($Source, [Text.Encoding]::UTF8)
    [IO.File]::WriteAllText($Destination, $Text, (New-Object Text.UTF8Encoding($true)))
}

Assert-Administrator

foreach ($Required in @($SourceScript, $SourceConfig)) {
    if (-not (Test-Path -LiteralPath $Required)) {
        throw "Arquivo não encontrado: $Required"
    }
}

Write-Host ''
Write-Host "Instalando ControleRede $Version..."

# 1. Para a instância anterior, se existir.
$Existing = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue

if ($null -ne $Existing) {
    Write-Host 'Parando a versão anterior...'
    Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
}

# 2. Pasta protegida.
Set-SecureFolder -Path $BasePath
New-Item -Path $LogPath -ItemType Directory -Force | Out-Null

# 3. Arquivos. O estado.json existente é preservado (o script migra o
#    formato antigo). O config.json só é criado se ainda não existir,
#    para não sobrescrever personalizações do cliente.
Write-Utf8Bom -Source $SourceScript -Destination $ScriptPath

if (-not (Test-Path -LiteralPath $ConfigPath)) {
    Copy-Item -LiteralPath $SourceConfig -Destination $ConfigPath -Force
}

if (-not (Test-Path -LiteralPath $StateFile)) {
    '{"Version":2,"ControlledWifi":[]}' |
        Set-Content -LiteralPath $StateFile -Encoding UTF8
}

# 4. Tarefa agendada.
Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue

$Action = New-ScheduledTaskAction `
    -Execute 'powershell.exe' `
    -Argument (
        '-NoProfile -NonInteractive -ExecutionPolicy Bypass ' +
        "-WindowStyle Hidden -File `"$ScriptPath`""
    )

$Trigger = New-ScheduledTaskTrigger -AtStartup

$TaskPrincipal = New-ScheduledTaskPrincipal `
    -UserId 'S-1-5-18' `
    -LogonType ServiceAccount `
    -RunLevel Highest

# ExecutionTimeLimit = 0: sem limite. O padrão do Windows é 72 horas,
# o que encerraria o monitoramento após 3 dias ligado.
$Settings = New-ScheduledTaskSettingsSet `
    -ExecutionTimeLimit ([TimeSpan]::Zero) `
    -MultipleInstances IgnoreNew `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -RestartCount 999 `
    -RestartInterval (New-TimeSpan -Minutes 1)

Register-ScheduledTask `
    -TaskName $TaskName `
    -Action $Action `
    -Trigger $Trigger `
    -Principal $TaskPrincipal `
    -Settings $Settings `
    -Description "ControleRede $Version - alterna Wi-Fi conforme Ethernet físico com rede." `
    -Force | Out-Null

Start-ScheduledTask -TaskName $TaskName

Write-Host ''
Write-Host '============================================'
Write-Host "ControleRede $Version instalado."
Write-Host '============================================'
Write-Host ''
Write-Host "Tarefa:  $TaskName"
Write-Host "Destino: $BasePath"
Write-Host "Log:     $(Join-Path $LogPath 'controle-rede.log')"
Write-Host ''
