#requires -version 5.1

Set-StrictMode -Version Latest
$ErrorActionPreference = "SilentlyContinue"

$Version = "1.1.0"

$BasePath = "C:\ProgramData\ControleRede"
$LogDirectory = Join-Path $BasePath "logs"
$LogFile = Join-Path $LogDirectory "controle-rede.log"
$StateFile = Join-Path $BasePath "estado.json"

$IntervalSeconds = 3
$MaxLogBytes = 5MB

New-Item -Path $LogDirectory -ItemType Directory -Force | Out-Null

function Write-Log {
    param(
        [Parameter(Mandatory)]
        [string]$Message
    )

    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $LogFile -Value "$Timestamp | $Message" -Encoding UTF8

    if (
        (Test-Path $LogFile) -and
        ((Get-Item $LogFile).Length -gt $MaxLogBytes)
    ) {
        $Archive = Join-Path `
            $LogDirectory `
            ("controle-rede-{0}.log" -f (Get-Date -Format "yyyyMMdd-HHmmss"))

        Move-Item $LogFile $Archive -Force
    }
}

function Get-State {

    if (Test-Path $StateFile) {

        try {

            $State = Get-Content `
                $StateFile `
                -Raw `
                -Encoding UTF8 |
                ConvertFrom-Json

            if ($null -eq $State.DisabledWifiAdapters) {
                $State | Add-Member `
                    -MemberType NoteProperty `
                    -Name DisabledWifiAdapters `
                    -Value @()
            }

            return $State
        }
        catch {

            Write-Log `
                "AVISO | estado.json inválido. Criando novo estado."
        }
    }

    return [PSCustomObject]@{
        DisabledWifiAdapters = @()
    }
}

function Save-State {

    param(
        [Parameter(Mandatory)]
        $State
    )

    $TemporaryFile = "$StateFile.tmp"

    try {

        $State |
            ConvertTo-Json -Depth 5 |
            Set-Content `
                -Path $TemporaryFile `
                -Encoding UTF8

        Move-Item `
            -Path $TemporaryFile `
            -Destination $StateFile `
            -Force
    }
    catch {

        Write-Log `
            "ERRO | Não foi possível salvar estado.json: $($_.Exception.Message)"
    }
}

function Test-PhysicalEthernetLink {

    param(
        [Parameter(Mandatory)]
        $Adapter
    )

    # Ethernet
    if ($Adapter.InterfaceType -ne 6) {
        return $false
    }

    # Deve ser hardware físico
    if ($Adapter.HardwareInterface -ne $true) {
        return $false
    }

    # Proteção contra interfaces de loopback
    $IdentityText = @(
        $Adapter.Name
        $Adapter.InterfaceDescription
    ) -join " "

    if ($IdentityText -match "Loopback") {
        return $false
    }

    # Se o driver informar o meio físico, 14 = Ethernet 802.3.
    # Alguns drivers podem não expor essa propriedade; nesse caso,
    # a validação continua pelo link físico.
    if (
        $null -ne $Adapter.NdisPhysicalMedium -and
        $Adapter.NdisPhysicalMedium -ne 0 -and
        $Adapter.NdisPhysicalMedium -ne 14
    ) {
        return $false
    }

    # Esta é a verificação decisiva:
    # o Windows informa que existe link físico.
    return (
        $Adapter.MediaConnectionState -eq "Connected"
    )
}

function Get-ConnectedPhysicalEthernet {

    param(
        [Parameter(Mandatory)]
        [array]$Adapters
    )

    return @(
        $Adapters |
            Where-Object {
                Test-PhysicalEthernetLink $_
            }
    )
}

Write-Log "INFO | Controle automático iniciado. Versão $Version."

$LastEthernetState = $null

while ($true) {

    try {

        $Adapters = @(
            Get-NetAdapter `
                -Physical `
                -ErrorAction SilentlyContinue
        )

        $EthernetCandidates = @(
            $Adapters |
                Where-Object {
                    $_.InterfaceType -eq 6 -and
                    $_.HardwareInterface -eq $true
                }
        )

        $WifiAdapters = @(
            $Adapters |
                Where-Object {
                    $_.InterfaceType -eq 71
                }
        )

        $ConnectedEthernet = @(
            Get-ConnectedPhysicalEthernet `
                -Adapters $EthernetCandidates
        )

        $EthernetConnected = (
            $ConnectedEthernet.Count -gt 0
        )

        $State = Get-State

        # Normaliza para array para evitar problemas do PowerShell
        # quando existir apenas um adaptador registrado.
        $DisabledWifiNames = @(
            $State.DisabledWifiAdapters
        )

        if ($EthernetConnected) {

            if ($LastEthernetState -ne $true) {

                Write-Log `
                    "ESTADO | Ethernet físico CONECTADO."

                foreach ($Adapter in $ConnectedEthernet) {

                    Write-Log (
                        "ETHERNET | $($Adapter.Name) | " +
                        "$($Adapter.InterfaceDescription) | " +
                        "Medium=$($Adapter.NdisPhysicalMedium) | " +
                        "Link=$($Adapter.MediaConnectionState)"
                    )
                }
            }

            foreach ($Wifi in $WifiAdapters) {

                # Só desativa Wi-Fi que esteja operacional.
                if ($Wifi.Status -eq "Up") {

                    try {

                        Write-Log `
                            "AÇÃO | Desativando Wi-Fi: $($Wifi.Name)"

                        Disable-NetAdapter `
                            -Name $Wifi.Name `
                            -Confirm:$false `
                            -ErrorAction Stop

                        if (
                            $DisabledWifiNames -notcontains $Wifi.Name
                        ) {

                            $DisabledWifiNames += $Wifi.Name
                        }

                        Write-Log `
                            "OK | Wi-Fi desativado: $($Wifi.Name)"
                    }
                    catch {

                        Write-Log (
                            "ERRO | Falha ao desativar Wi-Fi " +
                            "'$($Wifi.Name)': " +
                            $_.Exception.Message
                        )
                    }
                }
            }

            $State.DisabledWifiAdapters = @(
                $DisabledWifiNames
            )

            Save-State $State
        }
        else {

            if ($LastEthernetState -ne $false) {

                Write-Log `
                    "ESTADO | Nenhum Ethernet físico conectado."
            }

            # Reavalia os adaptadores atuais porque o Wi-Fi pode
            # estar Disabled e ainda assim aparecer no inventário.
            foreach ($WifiName in $DisabledWifiNames) {

                $Wifi = @(
                    $WifiAdapters |
                        Where-Object {
                            $_.Name -eq $WifiName
                        }
                )

                if ($Wifi.Count -eq 0) {

                    Write-Log (
                        "AVISO | Wi-Fi registrado no estado.json " +
                        "não encontrado: $WifiName"
                    )

                    continue
                }

                $CurrentWifi = $Wifi[0]

                if ($CurrentWifi.Status -eq "Disabled") {

                    try {

                        Write-Log `
                            "AÇÃO | Reativando Wi-Fi: $WifiName"

                        Enable-NetAdapter `
                            -Name $WifiName `
                            -Confirm:$false `
                            -ErrorAction Stop

                        Write-Log `
                            "OK | Wi-Fi reativado: $WifiName"
                    }
                    catch {

                        Write-Log (
                            "ERRO | Falha ao reativar Wi-Fi " +
                            "'$WifiName': " +
                            $_.Exception.Message
                        )

                        # Mantém no estado para tentar novamente
                        # no próximo ciclo.
                        continue
                    }
                }
                else {

                    Write-Log (
                        "INFO | Wi-Fi '$WifiName' já está ativo."
                    )
                }
            }

            # Só limpa o estado depois de processar a lista.
            # Se uma tentativa falhar, o adaptador permanece
            # registrado para nova tentativa.
            $Remaining = @()

            foreach ($WifiName in $DisabledWifiNames) {

                $Wifi = @(
                    $WifiAdapters |
                        Where-Object {
                            $_.Name -eq $WifiName
                        }
                )

                if ($Wifi.Count -eq 0) {
                    $Remaining += $WifiName
                    continue
                }

                if ($Wifi[0].Status -eq "Disabled") {
                    $Remaining += $WifiName
                }
            }

            $State.DisabledWifiAdapters = @($Remaining)

            Save-State $State
        }

        $LastEthernetState = $EthernetConnected
    }
    catch {

        Write-Log `
            "ERRO | Falha no ciclo principal: $($_.Exception.Message)"
    }

    Start-Sleep `
        -Seconds $IntervalSeconds
}
