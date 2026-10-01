#requires -version 5.1
<#
.SYNOPSIS
    Simulação da lógica de decisão do ControleRede, sem tocar em
    adaptadores reais. Substitui os cmdlets de rede por funções falsas.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\tests\Simulacao.Tests.ps1
#>

$ErrorActionPreference = 'Stop'

$TestRoot = Join-Path ([IO.Path]::GetTempPath()) ("controlerede-teste-" + [guid]::NewGuid())
New-Item -Path $TestRoot -ItemType Directory -Force | Out-Null

. (Join-Path $PSScriptRoot '..\src\ControleRede.ps1') -BasePath $TestRoot

$Config['StableChecksBeforeDisable']    = 2
$Config['ConnectivityLossGraceSeconds'] = 0

# ---------- Ambiente simulado ----------
$Sim = @{
    EthLink    = $false
    EthIP      = $null
    EthGateway = $false
    WifiStatus = 'Up'
    WifiExists = $true
    Disables   = 0
    Enables    = 0
}

function New-FakeAdapter($Name, $Desc, $Type, $Guid, $Index, $Status, $Media) {
    [PSCustomObject]@{
        Name = $Name; InterfaceDescription = $Desc; InterfaceType = $Type
        InterfaceGuid = $Guid; ifIndex = $Index; HardwareInterface = $true
        NdisPhysicalMedium = $(if ($Type -eq 6) { 14 } else { 9 })
        Status = $Status; MediaConnectionState = $Media
    }
}

function Get-NetAdapter {
    param([switch]$Physical)
    $List = @(
        New-FakeAdapter 'Ethernet' 'Intel(R) Ethernet' 6 '{E}' 10 `
            $(if ($Sim.EthLink) { 'Up' } else { 'Disconnected' }) `
            $(if ($Sim.EthLink) { 'Connected' } else { 'Disconnected' })
        New-FakeAdapter 'Topaz Loopback' 'Topaz Loopback' 6 '{L}' 30 'Up' 'Connected'
    )
    if ($Sim.WifiExists) {
        $List += New-FakeAdapter 'Wi-Fi' 'Intel(R) Wi-Fi 6' 71 '{W}' 20 $Sim.WifiStatus 'Connected'
    }
    $List
}

function Get-NetIPAddress {
    param($InterfaceIndex, $AddressFamily, $PolicyStore)
    if ($InterfaceIndex -eq 10 -and $AddressFamily -eq 'IPv4' -and $Sim.EthIP) {
        [PSCustomObject]@{ IPAddress = $Sim.EthIP; AddressState = 'Preferred'; PrefixOrigin = 'Dhcp' }
    }
}

function Get-NetRoute {
    param($InterfaceIndex, $PolicyStore)
    if ($InterfaceIndex -eq 10 -and $Sim.EthGateway) {
        [PSCustomObject]@{ DestinationPrefix = '0.0.0.0/0'; NextHop = '192.168.0.1' }
    }
}

function Disable-NetAdapter { param($InputObject, [switch]$Confirm) $Sim.WifiStatus = 'Disabled'; $Sim.Disables++ }
function Enable-NetAdapter  { param($InputObject, [switch]$Confirm) $Sim.WifiStatus = 'Up';       $Sim.Enables++ }

# ---------- Asserções ----------
$Failures = 0
function Assert($Condition, $Message) {
    if ($Condition) { Write-Host "  OK    $Message" -ForegroundColor Green }
    else            { Write-Host "  FALHA $Message" -ForegroundColor Red; $script:Failures++ }
}
function Step { Invoke-ControlCycle }
function SavedEntries {
    @((Get-Content $StateFile -Raw | ConvertFrom-Json).ControlledWifi)
}

Write-Host "`n1. Sem cabo: nada muda; loopback ignorado"
Step
Assert ($Sim.WifiStatus -eq 'Up') 'Wi-Fi continua ativo'
Assert ($Script:LastStatus -eq 'NoLink') 'Topaz Loopback não conta como Ethernet'

Write-Host "`n2. Cabo com link, DHCP ainda pendente"
$Sim.EthLink = $true
Step; Step; Step
Assert ($Sim.WifiStatus -eq 'Up') 'Wi-Fi mantido sem IP no cabo'
Assert ($Script:LastStatus -eq 'LinkOnly') 'estado = link sem rede'

Write-Host "`n3. APIPA (169.254.x.x) não conta como rede"
$Sim.EthIP = '169.254.10.20'
Step; Step
Assert ($Sim.WifiStatus -eq 'Up') 'Wi-Fi mantido com APIPA'

Write-Host "`n4. IP válido sem gateway"
$Sim.EthIP = '192.168.0.50'
Step; Step
Assert ($Sim.WifiStatus -eq 'Up') 'Wi-Fi mantido sem gateway'

Write-Host "`n5. IP + gateway: desativa somente após 2 confirmações"
$Sim.EthGateway = $true
Step
Assert ($Sim.WifiStatus -eq 'Up') '1a verificação: ainda não desativa'
Step
Assert ($Sim.WifiStatus -eq 'Disabled') '2a verificação: Wi-Fi desativado'
Assert (@(SavedEntries)[0].InterfaceGuid -eq '{W}') 'estado.json registra o GUID'

Write-Host "`n6. Ciclos estáveis não regravam estado.json"
$Before = (Get-Item $StateFile).LastWriteTimeUtc
Start-Sleep -Milliseconds 1100
Step; Step; Step
Assert ((Get-Item $StateFile).LastWriteTimeUtc -eq $Before) 'arquivo não foi regravado'

Write-Host "`n7. Rede cabeada cai, link continua: reativa após tolerância"
$Sim.EthGateway = $false
Step
Assert ($Sim.WifiStatus -eq 'Up') 'Wi-Fi reativado'
Assert (@(SavedEntries).Count -eq 0) 'estado.json limpo na mesma passada'

Write-Host "`n8. Rede volta e cabo é removido"
$Sim.EthGateway = $true
Step; Step
Assert ($Sim.WifiStatus -eq 'Disabled') 'Wi-Fi desativado novamente'
$Sim.EthLink = $false
Step
Assert ($Sim.WifiStatus -eq 'Up') 'cabo removido: Wi-Fi reativado imediatamente'

Write-Host "`n9. Wi-Fi desativado pelo usuário não é reativado"
$Sim.WifiStatus = 'Disabled'
$Enables = $Sim.Enables
$Sim.EthLink = $true; Step; Step
$Sim.EthLink = $false; Step
Assert ($Sim.WifiStatus -eq 'Disabled' -and $Sim.Enables -eq $Enables) 'Wi-Fi do usuário respeitado'

Write-Host "`n10. Migração do estado.json da v1.1"
$Sim.WifiStatus = 'Disabled'
'{"DisabledWifiAdapters":["Wi-Fi"]}' | Set-Content $StateFile
$Script:State = $null; $Script:LastStatus = $null
Step
Assert ($Sim.WifiStatus -eq 'Up') 'Wi-Fi da v1.1 reativado após migração'

Write-Host "`n11. Adaptador USB removido: aviso único no log"
$Sim.WifiStatus = 'Up'; $Sim.EthLink = $true
Step; Step
$Sim.WifiExists = $false; $Sim.EthLink = $false
1..5 | ForEach-Object { Step }
$Warnings = @(Get-Content $LogFile | Where-Object { $_ -like '*não encontrado*' }).Count
Assert ($Warnings -eq 1) "aviso registrado uma única vez (encontrados: $Warnings)"
$Sim.WifiExists = $true
Step
Assert ($Sim.WifiStatus -eq 'Up') 'adaptador reaparece e é reativado'

Remove-Item $TestRoot -Recurse -Force

Write-Host ''
if ($Failures -eq 0) { Write-Host 'Todos os cenários passaram.' -ForegroundColor Green; exit 0 }
else { Write-Host "$Failures falha(s)." -ForegroundColor Red; exit 1 }
