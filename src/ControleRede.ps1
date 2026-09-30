#requires -version 5.1

Set-StrictMode -Version Latest
$ErrorActionPreference = "SilentlyContinue"

$BasePath = "C:\ProgramData\ControleRede"
$LogDirectory = Join-Path $BasePath "logs"
$LogFile = Join-Path $LogDirectory "controle-rede.log"
$StateFile = Join-Path $BasePath "estado.json"

$IntervalSeconds = 3
$MaxLogBytes = 5MB

New-Item -Path $LogDirectory -ItemType Directory -Force | Out-Null

function Write-Log {
    param([string]$Message)

    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $LogFile -Value "$Timestamp | $Message" -Encoding UTF8

    if ((Test-Path $LogFile) -and ((Get-Item $LogFile).Length -gt $MaxLogBytes)) {
        $Archive = Join-Path $LogDirectory (
            "controle-rede-{0}.log" -f (Get-Date -Format "yyyyMMdd-HHmmss")
        )

        Move-Item $LogFile $Archive -Force
    }
}

function Get-State {
    if (Test-Path $StateFile) {
        try {
            return Get-Content $StateFile -Raw -Encoding UTF8 |
                ConvertFrom-Json
        }
        catch {
            Write-Log "ERRO | Estado inválido. Criando estado limpo."
        }
    }

    return [PSCustomObject]@{
        DisabledWifiAdapters = @()
    }
}

function Save-State {
    param($State)

    $State |
        ConvertTo-Json -Depth 5 |
        Set-Content $StateFile -Encoding UTF8
}

function Test-PhysicalEthernetLink {
    param($Adapter)

    return ($Adapter.MediaConnectionState -eq "Connected")
}

Write-Log "INFO | Controle automático iniciado."

$LastEthernetState = $null

while ($true) {

    try {

        $Adapters = @(
            Get-NetAdapter -Physical -ErrorAction SilentlyContinue
        )

        $EthernetAdapters = @(
            $Adapters |
            Where-Object {
                $_.InterfaceType -eq 6
            }
        )

        $WifiAdapters = @(
            $Adapters |
            Where-Object {
                $_.InterfaceType -eq 71
            }
        )

        $EthernetConnected = $false

        foreach ($Adapter in $EthernetAdapters) {

            if (Test-PhysicalEthernetLink $Adapter) {
                $EthernetConnected = $true
                break
            }
        }

        $State = Get-State

        if ($null -eq $State.DisabledWifiAdapters) {
            $State.DisabledWifiAdapters = @()
        }

        if ($EthernetConnected) {

            if ($LastEthernetState -ne $true) {
                Write-Log "ESTADO | Ethernet com link físico CONECTADO."
            }

            foreach ($Wifi in $WifiAdapters) {

                if ($Wifi.Status -eq "Up") {

                    try {

                        Write-Log "AÇÃO | Desativando Wi-Fi: $($Wifi.Name)"

                        Disable-NetAdapter `
                            -Name $Wifi.Name `
                            -Confirm:$false `
                            -ErrorAction Stop

                        if (
                            $State.DisabledWifiAdapters -notcontains $Wifi.Name
                        ) {
                            $State.DisabledWifiAdapters += $Wifi.Name
                        }

                        Write-Log "OK | Wi-Fi desativado: $($Wifi.Name)"
                    }
                    catch {

                        Write-Log (
                            "ERRO | Falha ao desativar Wi-Fi '$($Wifi.Name)': " +
                            $_.Exception.Message
                        )
                    }
                }
            }
        }
        else {

            if ($LastEthernetState -ne $false) {
                Write-Log "ESTADO | Nenhum Ethernet com link físico conectado."
            }

            foreach ($WifiName in @($State.DisabledWifiAdapters)) {

                $Wifi = $WifiAdapters |
                    Where-Object {
                        $_.Name -eq $WifiName
                    }

                if (
                    $null -ne $Wifi -and
                    $Wifi.Status -eq "Disabled"
                ) {

                    try {

                        Write-Log "AÇÃO | Reativando Wi-Fi: $WifiName"

                        Enable-NetAdapter `
                            -Name $WifiName `
                            -Confirm:$false `
                            -ErrorAction Stop

                        Write-Log "OK | Wi-Fi reativado: $WifiName"
                    }
                    catch {

                        Write-Log (
                            "ERRO | Falha ao reativar Wi-Fi '$WifiName': " +
                            $_.Exception.Message
                        )

                        continue
                    }
                }
            }

            $State.DisabledWifiAdapters = @()
        }

        Save-State $State

        $LastEthernetState = $EthernetConnected
    }
    catch {

        Write-Log "ERRO | $($_.Exception.Message)"
    }

    Start-Sleep -Seconds $IntervalSeconds
}
