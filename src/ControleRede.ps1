#requires -version 5.1
<#
.SYNOPSIS
    ControleRede - alterna automaticamente entre Ethernet e Wi-Fi.

.DESCRIPTION
    Desativa o Wi-Fi somente quando existe um Ethernet físico com link
    E com rede utilizável (IP válido e gateway padrão). Reativa o Wi-Fi
    quando o cabo é removido ou quando a rede cabeada deixa de funcionar
    por mais tempo que o período de tolerância.

    Só reativa adaptadores Wi-Fi que a própria automação desativou.

.PARAMETER BasePath
    Pasta de dados (padrão: %ProgramData%\ControleRede).

.NOTES
    Para testes, o script pode ser carregado com dot-source
    (. .\ControleRede.ps1 -BasePath <pasta>) sem iniciar o loop.
#>

param(
    [string]$BasePath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Version = '1.2.0'

if ([string]::IsNullOrWhiteSpace($BasePath)) {
    $BasePath = Join-Path $env:ProgramData 'ControleRede'
}

$LogDirectory = Join-Path $BasePath 'logs'
$LogFile      = Join-Path $LogDirectory 'controle-rede.log'
$StateFile    = Join-Path $BasePath 'estado.json'
$ConfigFile   = Join-Path $BasePath 'config.json'

# Valores padrão. Podem ser sobrescritos por config.json.
$Config = [ordered]@{
    IntervalSeconds              = 3
    StableChecksBeforeDisable    = 2
    ConnectivityLossGraceSeconds = 15
    RequireDefaultGateway        = $true
    MaxLogBytes                  = 5242880
    LogRetentionCount            = 5
    ExcludedAdapterPatterns      = @(
        'Loopback', 'VPN', 'TAP-', 'Hyper-V', 'VMware', 'VirtualBox', 'Npcap'
    )
}

# Estado de execução (memória).
$Script:State          = $null
$Script:StateDirty     = $false
$Script:LastStatus     = $null
$Script:UsableStreak   = 0
$Script:LinkOnlySince  = $null
$Script:MissingWarned  = @{}
$Script:LastErrorByKey = @{}

#region Utilitários

function Write-Log {
    param(
        [Parameter(Mandatory)]
        [string]$Message
    )

    try {
        if (-not (Test-Path -LiteralPath $LogDirectory)) {
            New-Item -Path $LogDirectory -ItemType Directory -Force | Out-Null
        }

        $Timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        Add-Content -LiteralPath $LogFile -Value "$Timestamp | $Message" -Encoding UTF8

        if ((Get-Item -LiteralPath $LogFile).Length -gt $Config.MaxLogBytes) {

            $Archive = Join-Path $LogDirectory (
                'controle-rede-{0}.log' -f (Get-Date -Format 'yyyyMMdd-HHmmss')
            )

            Move-Item -LiteralPath $LogFile -Destination $Archive -Force

            # Retenção: mantém apenas os N arquivos mais recentes.
            Get-ChildItem -LiteralPath $LogDirectory -Filter 'controle-rede-*.log' |
                Sort-Object LastWriteTime -Descending |
                Select-Object -Skip $Config.LogRetentionCount |
                Remove-Item -Force -ErrorAction SilentlyContinue
        }
    }
    catch {
        # Uma falha de log nunca deve interromper o controle de rede.
    }
}

# Registra um erro recorrente apenas quando a mensagem muda,
# evitando inundar o log com a mesma falha a cada ciclo.
function Write-ErrorOnce {
    param(
        [Parameter(Mandatory)][string]$Key,
        [Parameter(Mandatory)][string]$Message
    )

    if ($Script:LastErrorByKey[$Key] -ne $Message) {
        Write-Log $Message
        $Script:LastErrorByKey[$Key] = $Message
    }
}

function Clear-ErrorOnce {
    param([Parameter(Mandatory)][string]$Key)
    $Script:LastErrorByKey.Remove($Key)
}

function Get-PropertyValue {
    param($Object, [string]$Name)

    if ($null -eq $Object) { return $null }

    $Property = $Object.PSObject.Properties[$Name]
    if ($null -eq $Property) { return $null }

    return $Property.Value
}

function Import-Config {

    if (Test-Path -LiteralPath $ConfigFile) {
        try {
            $Loaded = Get-Content -LiteralPath $ConfigFile -Raw -Encoding UTF8 |
                ConvertFrom-Json

            foreach ($Key in @($Config.Keys)) {
                $Value = Get-PropertyValue $Loaded $Key
                if ($null -ne $Value) {
                    $Config[$Key] = $Value
                }
            }
        }
        catch {
            Write-Log "AVISO | config.json inválido; usando valores padrão. $($_.Exception.Message)"
        }
    }

    # Sanidade dos valores.
    $Config['IntervalSeconds']              = [Math]::Max(1,  [int]$Config['IntervalSeconds'])
    $Config['StableChecksBeforeDisable']    = [Math]::Max(1,  [int]$Config['StableChecksBeforeDisable'])
    $Config['ConnectivityLossGraceSeconds'] = [Math]::Max(0,  [int]$Config['ConnectivityLossGraceSeconds'])
    $Config['RequireDefaultGateway']        = [bool]$Config['RequireDefaultGateway']
    $Config['MaxLogBytes']                  = [Math]::Max(65536, [long]$Config['MaxLogBytes'])
    $Config['LogRetentionCount']            = [Math]::Max(1,  [int]$Config['LogRetentionCount'])
    $Config['ExcludedAdapterPatterns']      = @(
        @($Config['ExcludedAdapterPatterns']) |
            ForEach-Object { [string]$_ } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )
}

#endregion

#region Estado

function New-EmptyState {
    return [PSCustomObject]@{
        Version        = 2
        ControlledWifi = @()
    }
}

function ConvertTo-WifiEntry {
    param([Parameter(Mandatory)]$Adapter)

    return [PSCustomObject]@{
        InterfaceGuid        = [string]$Adapter.InterfaceGuid
        Name                 = [string]$Adapter.Name
        InterfaceDescription = [string]$Adapter.InterfaceDescription
    }
}

function Read-State {
    param([array]$WifiAdapters = @())

    if (-not (Test-Path -LiteralPath $StateFile)) {
        return New-EmptyState
    }

    try {
        $Raw = Get-Content -LiteralPath $StateFile -Raw -Encoding UTF8

        if ([string]::IsNullOrWhiteSpace($Raw)) {
            return New-EmptyState
        }

        $Loaded  = $Raw | ConvertFrom-Json
        $Entries = @()

        # Formato 2 (v1.2): objetos identificados por InterfaceGuid.
        foreach ($Item in @(Get-PropertyValue $Loaded 'ControlledWifi')) {
            if ($null -eq $Item) { continue }

            $Entries += [PSCustomObject]@{
                InterfaceGuid        = [string](Get-PropertyValue $Item 'InterfaceGuid')
                Name                 = [string](Get-PropertyValue $Item 'Name')
                InterfaceDescription = [string](Get-PropertyValue $Item 'InterfaceDescription')
            }
        }

        # Formato 1 (v1.0/v1.1): lista de nomes. Migra para GUID.
        $Legacy = Get-PropertyValue $Loaded 'DisabledWifiAdapters'

        if ($null -ne $Legacy) {

            foreach ($Name in @($Legacy)) {
                if ([string]::IsNullOrWhiteSpace([string]$Name)) { continue }

                $Match = @($WifiAdapters | Where-Object { $_.Name -eq $Name })

                if ($Match.Count -gt 0) {
                    $Entries += ConvertTo-WifiEntry $Match[0]
                }
                else {
                    $Entries += [PSCustomObject]@{
                        InterfaceGuid        = ''
                        Name                 = [string]$Name
                        InterfaceDescription = ''
                    }
                }
            }

            Write-Log 'INFO | estado.json migrado do formato da versão 1.1.'
            $Script:StateDirty = $true
        }

        return [PSCustomObject]@{
            Version        = 2
            ControlledWifi = @($Entries)
        }
    }
    catch {
        Write-Log "AVISO | estado.json inválido; iniciando estado vazio. $($_.Exception.Message)"
        $Script:StateDirty = $true
        return New-EmptyState
    }
}

function Save-State {

    if (-not $Script:StateDirty) { return }

    $TemporaryFile = "$StateFile.tmp"

    try {
        $Json = [PSCustomObject]@{
            Version        = 2
            ControlledWifi = @($Script:State.ControlledWifi)
        } | ConvertTo-Json -Depth 5

        Set-Content -LiteralPath $TemporaryFile -Value $Json -Encoding UTF8
        Move-Item -LiteralPath $TemporaryFile -Destination $StateFile -Force

        $Script:StateDirty = $false
        Clear-ErrorOnce 'save-state'
    }
    catch {
        Write-ErrorOnce 'save-state' "ERRO | Não foi possível salvar estado.json: $($_.Exception.Message)"
    }
}

function Find-WifiAdapter {
    param(
        [Parameter(Mandatory)]$Entry,
        [array]$WifiAdapters = @()
    )

    if (-not [string]::IsNullOrWhiteSpace($Entry.InterfaceGuid)) {
        $Match = @($WifiAdapters | Where-Object { [string]$_.InterfaceGuid -eq $Entry.InterfaceGuid })
        if ($Match.Count -gt 0) { return $Match[0] }
    }

    if (-not [string]::IsNullOrWhiteSpace($Entry.Name)) {
        $Match = @($WifiAdapters | Where-Object { $_.Name -eq $Entry.Name })
        if ($Match.Count -gt 0) { return $Match[0] }
    }

    return $null
}

function Test-IsControlled {
    param([Parameter(Mandatory)]$Adapter)

    foreach ($Entry in @($Script:State.ControlledWifi)) {
        if ($Entry.InterfaceGuid -and $Entry.InterfaceGuid -eq [string]$Adapter.InterfaceGuid) {
            return $true
        }
    }

    return $false
}

#endregion

#region Detecção

function Test-ExcludedAdapter {
    param([Parameter(Mandatory)]$Adapter)

    $Text = "$($Adapter.Name) $($Adapter.InterfaceDescription)"

    foreach ($Pattern in $Config['ExcludedAdapterPatterns']) {
        if ($Text.IndexOf($Pattern, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
            return $true
        }
    }

    return $false
}

function Test-PhysicalEthernetLink {
    param([Parameter(Mandatory)]$Adapter)

    # Ethernet (IANA ifType 6)
    if ($Adapter.InterfaceType -ne 6) { return $false }

    # Hardware físico
    if ($Adapter.HardwareInterface -ne $true) { return $false }

    # Loopback, VPN e adaptadores virtuais conhecidos
    if (Test-ExcludedAdapter $Adapter) { return $false }

    # Se o driver informar o meio físico, 14 = Ethernet 802.3.
    $Medium = $Adapter.NdisPhysicalMedium
    if ($null -ne $Medium -and $Medium -ne 0 -and $Medium -ne 14) { return $false }

    # Link físico informado pelo Windows.
    $Media = [string]$Adapter.MediaConnectionState
    return ($Media -eq 'Connected' -or $Media -eq '1')
}

function Get-EthernetConnectivity {
    param([Parameter(Mandatory)]$Adapter)

    $Index = $Adapter.ifIndex

    $IPv4 = @(
        Get-NetIPAddress -InterfaceIndex $Index -AddressFamily IPv4 `
            -PolicyStore ActiveStore -ErrorAction SilentlyContinue |
            Where-Object {
                $_.IPAddress -notlike '169.254.*' -and
                [string]$_.AddressState -eq 'Preferred'
            }
    )

    $IPv6 = @(
        Get-NetIPAddress -InterfaceIndex $Index -AddressFamily IPv6 `
            -PolicyStore ActiveStore -ErrorAction SilentlyContinue |
            Where-Object {
                $_.IPAddress -notlike 'fe80:*' -and
                [string]$_.PrefixOrigin -ne 'WellKnown' -and
                [string]$_.AddressState -eq 'Preferred'
            }
    )

    if ($IPv4.Count -eq 0 -and $IPv6.Count -eq 0) {
        return [PSCustomObject]@{
            Usable = $false
            Reason = 'sem endereço IP válido (DHCP pendente ou APIPA)'
        }
    }

    if (-not $Config['RequireDefaultGateway']) {
        return [PSCustomObject]@{ Usable = $true; Reason = 'endereço IP válido' }
    }

    $Routes = @(
        Get-NetRoute -InterfaceIndex $Index -PolicyStore ActiveStore `
            -ErrorAction SilentlyContinue |
            Where-Object {
                (
                    $IPv4.Count -gt 0 -and
                    $_.DestinationPrefix -eq '0.0.0.0/0' -and
                    $_.NextHop -ne '0.0.0.0'
                ) -or (
                    $IPv6.Count -gt 0 -and
                    $_.DestinationPrefix -eq '::/0' -and
                    $_.NextHop -ne '::'
                )
            }
    )

    if ($Routes.Count -eq 0) {
        return [PSCustomObject]@{ Usable = $false; Reason = 'sem gateway padrão' }
    }

    return [PSCustomObject]@{ Usable = $true; Reason = 'IP e gateway padrão válidos' }
}

#endregion

#region Ações

function Disable-ControlledWifi {
    param([array]$WifiAdapters = @())

    foreach ($Wifi in $WifiAdapters) {

        $Status = [string]$Wifi.Status
        if ($Status -eq 'Disabled' -or $Status -eq 'Not Present') { continue }

        $Key = "disable|$($Wifi.InterfaceGuid)"

        # Registra ANTES de desativar: se o processo for encerrado entre
        # as duas operações, o adaptador ainda será reativado depois.
        if (-not (Test-IsControlled $Wifi)) {
            $Script:State.ControlledWifi = @($Script:State.ControlledWifi) + (ConvertTo-WifiEntry $Wifi)
            $Script:StateDirty = $true
            Save-State
        }

        try {
            Write-Log "AÇÃO | Desativando Wi-Fi: $($Wifi.Name) ($($Wifi.InterfaceDescription))"
            Disable-NetAdapter -InputObject $Wifi -Confirm:$false -ErrorAction Stop
            Write-Log "OK | Wi-Fi desativado: $($Wifi.Name)"
            Clear-ErrorOnce $Key
        }
        catch {
            Write-ErrorOnce $Key "ERRO | Falha ao desativar Wi-Fi '$($Wifi.Name)': $($_.Exception.Message)"
        }
    }
}

function Restore-ControlledWifi {
    param([array]$WifiAdapters = @())

    $Remaining = @()

    foreach ($Entry in @($Script:State.ControlledWifi)) {

        $Label = if ($Entry.Name) { $Entry.Name } else { $Entry.InterfaceGuid }
        $Key   = "$($Entry.InterfaceGuid)|$($Entry.Name)"
        $Wifi  = Find-WifiAdapter -Entry $Entry -WifiAdapters $WifiAdapters

        if ($null -eq $Wifi) {
            # Ex.: adaptador USB removido. Mantém registrado para reativar
            # quando reaparecer, mas avisa apenas uma vez.
            if (-not $Script:MissingWarned.ContainsKey($Key)) {
                Write-Log "AVISO | Wi-Fi registrado não encontrado: $Label. Será reativado quando reaparecer."
                $Script:MissingWarned[$Key] = $true
            }
            $Remaining += $Entry
            continue
        }

        $Script:MissingWarned.Remove($Key)

        if ([string]$Wifi.Status -eq 'Disabled') {
            try {
                Write-Log "AÇÃO | Reativando Wi-Fi: $($Wifi.Name)"
                Enable-NetAdapter -InputObject $Wifi -Confirm:$false -ErrorAction Stop
                Write-Log "OK | Wi-Fi reativado: $($Wifi.Name)"
                Clear-ErrorOnce "enable|$Key"
            }
            catch {
                Write-ErrorOnce "enable|$Key" "ERRO | Falha ao reativar Wi-Fi '$($Wifi.Name)': $($_.Exception.Message)"
                $Remaining += $Entry
                continue
            }
        }
        else {
            Write-Log "INFO | Wi-Fi '$($Wifi.Name)' já estava ativo; removido do controle."
        }

        $Script:StateDirty = $true
    }

    $Script:State.ControlledWifi = @($Remaining)
    Save-State
}

#endregion

#region Ciclo principal

function Invoke-ControlCycle {

    $Adapters = @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue)
    $Wifi     = @($Adapters | Where-Object { $_.InterfaceType -eq 71 })

    if ($null -eq $Script:State) {
        $Script:State = Read-State -WifiAdapters $Wifi
        Save-State
    }

    $Linked  = @($Adapters | Where-Object { Test-PhysicalEthernetLink $_ })
    $Usable  = @()
    $Reasons = @()

    foreach ($Ethernet in $Linked) {
        $Connectivity = Get-EthernetConnectivity $Ethernet
        if ($Connectivity.Usable) {
            $Usable += $Ethernet
        }
        else {
            $Reasons += "$($Ethernet.Name): $($Connectivity.Reason)"
        }
    }

    if     ($Usable.Count -gt 0) { $Status = 'Usable' }
    elseif ($Linked.Count -gt 0) { $Status = 'LinkOnly' }
    else                         { $Status = 'NoLink' }

    if ($Status -ne $Script:LastStatus) {
        switch ($Status) {
            'Usable' {
                Write-Log 'ESTADO | Ethernet físico CONECTADO e com rede.'
                foreach ($Adapter in $Usable) {
                    Write-Log (
                        "ETHERNET | $($Adapter.Name) | $($Adapter.InterfaceDescription) | " +
                        "Medium=$($Adapter.NdisPhysicalMedium) | Link=$($Adapter.MediaConnectionState)"
                    )
                }
            }
            'LinkOnly' {
                Write-Log "ESTADO | Ethernet com link físico, mas sem rede utilizável ($($Reasons -join '; '))."
            }
            'NoLink' {
                Write-Log 'ESTADO | Nenhum Ethernet físico conectado.'
            }
        }
    }

    $ControlledCount = @($Script:State.ControlledWifi).Count

    switch ($Status) {

        'Usable' {
            $Script:LinkOnlySince = $null
            $Script:UsableStreak++

            # Aguarda N verificações consecutivas para evitar oscilação
            # (ex.: cabo mal encaixado, DHCP renovando).
            if ($Script:UsableStreak -ge $Config['StableChecksBeforeDisable']) {
                Disable-ControlledWifi -WifiAdapters $Wifi
            }
        }

        'LinkOnly' {
            $Script:UsableStreak = 0

            if ($ControlledCount -gt 0) {

                if ($null -eq $Script:LinkOnlySince) {
                    $Script:LinkOnlySince = Get-Date
                    Write-Log (
                        "AGUARDANDO | Wi-Fi será reativado em " +
                        "$($Config['ConnectivityLossGraceSeconds']) s se a rede cabeada não voltar."
                    )
                }

                $Elapsed = ((Get-Date) - $Script:LinkOnlySince).TotalSeconds

                if ($Elapsed -ge $Config['ConnectivityLossGraceSeconds']) {
                    Restore-ControlledWifi -WifiAdapters $Wifi
                }
            }
        }

        'NoLink' {
            $Script:UsableStreak  = 0
            $Script:LinkOnlySince = $null

            if ($ControlledCount -gt 0) {
                Restore-ControlledWifi -WifiAdapters $Wifi
            }
        }
    }

    $Script:LastStatus = $Status
}

function Register-NetworkEvents {

    $Registered = 0

    try {
        Register-ObjectEvent `
            -InputObject ([System.Net.NetworkInformation.NetworkChange]) `
            -EventName NetworkAddressChanged `
            -SourceIdentifier 'ControleRede.AddressChanged' | Out-Null
        $Registered++
    }
    catch {
        Write-Log "AVISO | Evento NetworkAddressChanged indisponível: $($_.Exception.Message)"
    }

    foreach ($Class in 'MSNdis_StatusMediaConnect', 'MSNdis_StatusMediaDisconnect') {
        try {
            Register-CimIndicationEvent `
                -Namespace 'root/wmi' `
                -ClassName $Class `
                -SourceIdentifier "ControleRede.$Class" | Out-Null
            $Registered++
        }
        catch {
            Write-Log "AVISO | Evento $Class indisponível: $($_.Exception.Message)"
        }
    }

    return $Registered
}

function Wait-NextCycle {

    # Acorda imediatamente em eventos de rede; caso contrário,
    # funciona como polling no intervalo configurado.
    $Signal = Wait-Event -Timeout $Config['IntervalSeconds']

    if ($null -ne $Signal) {
        # Dá tempo para o Windows atualizar link, IP e rotas.
        Start-Sleep -Milliseconds 1500
        Get-Event -ErrorAction SilentlyContinue |
            Remove-Event -ErrorAction SilentlyContinue
    }
}

function Start-ControleRede {

    New-Item -Path $LogDirectory -ItemType Directory -Force | Out-Null

    Import-Config

    # Impede duas instâncias simultâneas (ex.: tarefa + teste manual).
    $Mutex    = New-Object System.Threading.Mutex($false, 'Global\ControleRede')
    $Acquired = $false

    try {
        $Acquired = $Mutex.WaitOne(0)
    }
    catch [System.Threading.AbandonedMutexException] {
        # A instância anterior foi encerrada sem liberar o mutex.
        $Acquired = $true
    }

    if (-not $Acquired) {
        Write-Log 'AVISO | Outra instância já está em execução. Encerrando.'
        return
    }

    try {
        Write-Log "INFO | Controle automático iniciado. Versão $Version. PID $PID."
        Write-Log (
            "INFO | Configuração: intervalo=$($Config['IntervalSeconds'])s; " +
            "confirmações=$($Config['StableChecksBeforeDisable']); " +
            "tolerância=$($Config['ConnectivityLossGraceSeconds'])s; " +
            "exigir gateway=$($Config['RequireDefaultGateway'])"
        )

        $Events = Register-NetworkEvents
        Write-Log "INFO | Eventos de rede registrados: $Events (polling como reserva)."

        while ($true) {
            try {
                Invoke-ControlCycle
                Clear-ErrorOnce 'cycle'
            }
            catch {
                Write-ErrorOnce 'cycle' "ERRO | Falha no ciclo principal: $($_.Exception.Message)"
            }

            Wait-NextCycle
        }
    }
    finally {
        Get-EventSubscriber -ErrorAction SilentlyContinue |
            Where-Object { $_.SourceIdentifier -like 'ControleRede.*' } |
            Unregister-Event -ErrorAction SilentlyContinue

        Write-Log 'INFO | Controle automático encerrado.'
        $Mutex.ReleaseMutex()
        $Mutex.Dispose()
    }
}

#endregion

# Não inicia o loop quando carregado com dot-source (testes).
if ($MyInvocation.InvocationName -ne '.') {
    Start-ControleRede
}
