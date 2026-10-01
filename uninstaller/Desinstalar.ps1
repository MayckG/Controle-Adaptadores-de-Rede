#requires -version 5.1
<#
.SYNOPSIS
    Remove o ControleRede, reativando antes os adaptadores Wi-Fi
    que a automação havia desativado.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$BasePath  = Join-Path $env:ProgramData 'ControleRede'
$StateFile = Join-Path $BasePath 'estado.json'
$TaskName  = 'Controle Automático de Rede'

function Get-PropertyValue {
    param($Object, [string]$Name)
    if ($null -eq $Object) { return $null }
    $Property = $Object.PSObject.Properties[$Name]
    if ($null -eq $Property) { return $null }
    return $Property.Value
}

$Identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
$Principal = New-Object Security.Principal.WindowsPrincipal($Identity)

if (-not $Principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Execute o desinstalador como Administrador (use Desinstalar.bat).'
}

Write-Host ''
Write-Host 'Desinstalando ControleRede...'

# 1. Encerra a tarefa e qualquer instância remanescente.
Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue

Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -like '*ControleRede\ControleRede.ps1*' } |
    ForEach-Object {
        Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
    }

Start-Sleep -Seconds 1

# 2. Reativa o Wi-Fi controlado pela automação (formatos 1.1 e 1.2).
$Pending = $false

if (Test-Path -LiteralPath $StateFile) {

    try {
        $State = Get-Content -LiteralPath $StateFile -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        $State = $null
        Write-Warning 'estado.json ilegível; verifique manualmente se o Wi-Fi está ativo.'
    }

    $Wifi    = @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { $_.InterfaceType -eq 71 })
    $Entries = @()

    foreach ($Item in @(Get-PropertyValue $State 'ControlledWifi')) {
        if ($null -ne $Item) {
            $Entries += [PSCustomObject]@{
                Guid = [string](Get-PropertyValue $Item 'InterfaceGuid')
                Name = [string](Get-PropertyValue $Item 'Name')
            }
        }
    }

    foreach ($Name in @(Get-PropertyValue $State 'DisabledWifiAdapters')) {
        if (-not [string]::IsNullOrWhiteSpace([string]$Name)) {
            $Entries += [PSCustomObject]@{ Guid = ''; Name = [string]$Name }
        }
    }

    foreach ($Entry in $Entries) {

        $Adapter = $null

        if ($Entry.Guid) {
            $Adapter = @($Wifi | Where-Object { [string]$_.InterfaceGuid -eq $Entry.Guid }) | Select-Object -First 1
        }
        if ($null -eq $Adapter -and $Entry.Name) {
            $Adapter = @($Wifi | Where-Object { $_.Name -eq $Entry.Name }) | Select-Object -First 1
        }

        if ($null -eq $Adapter) {
            Write-Warning "Wi-Fi '$($Entry.Name)' não encontrado; não foi possível reativá-lo."
            $Pending = $true
            continue
        }

        if ([string]$Adapter.Status -eq 'Disabled') {
            try {
                Enable-NetAdapter -InputObject $Adapter -Confirm:$false -ErrorAction Stop
                Write-Host "Wi-Fi reativado: $($Adapter.Name)"
            }
            catch {
                Write-Warning "Falha ao reativar '$($Adapter.Name)': $($_.Exception.Message)"
                $Pending = $true
            }
        }
    }
}

# 3. Remove os arquivos.
if (Test-Path -LiteralPath $BasePath) {
    Remove-Item -LiteralPath $BasePath -Recurse -Force
}

Write-Host ''
Write-Host 'ControleRede desinstalado.'

if ($Pending) {
    Write-Host ''
    Write-Host 'ATENÇÃO: algum Wi-Fi pode continuar desativado.'
    Write-Host 'Reative em: Configurações > Rede e Internet > Configurações de rede avançadas.'
}

Write-Host ''
