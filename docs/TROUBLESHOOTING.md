# Troubleshooting

## 1. Verificar adaptadores

```powershell
Get-NetAdapter -Physical |
    Select-Object Name, InterfaceDescription, InterfaceType,
        HardwareInterface, NdisPhysicalMedium,
        Status, MediaConnectionState, InterfaceGuid
```

## 2. Verificar a conectividade do Ethernet

```powershell
Get-NetIPConfiguration -InterfaceAlias "Ethernet"
```

O Wi-Fi só é desativado se o Ethernet tiver IPv4 válido (não 169.254.x.x) ou IPv6 global e, por padrão, gateway padrão.

## 3. Verificar a tarefa

```powershell
Get-ScheduledTask -TaskName "Controle Automático de Rede"
Get-ScheduledTaskInfo -TaskName "Controle Automático de Rede"
```

## 4. Verificar o log

`C:\ProgramData\ControleRede\logs\controle-rede.log`

Sequência esperada:

```text
ESTADO | Ethernet físico CONECTADO e com rede.
AÇÃO | Desativando Wi-Fi: Wi-Fi (Intel(R) Wi-Fi 6)
OK | Wi-Fi desativado: Wi-Fi

ESTADO | Nenhum Ethernet físico conectado.
AÇÃO | Reativando Wi-Fi: Wi-Fi
OK | Wi-Fi reativado: Wi-Fi
```

## 5. O Wi-Fi não é desativado com o cabo conectado

Procure no log:

```text
ESTADO | Ethernet com link físico, mas sem rede utilizável (...)
```

O motivo aparece entre parênteses (`sem endereço IP válido` ou `sem gateway padrão`). Em redes cabeadas isoladas, sem gateway, defina `"RequireDefaultGateway": false` no `config.json`.

## 6. Um adaptador Ethernet válido é ignorado

Verifique se o nome ou a descrição contém algum trecho de `ExcludedAdapterPatterns` no `config.json`.

## 7. Reativação falha

```text
ERRO | Falha ao reativar Wi-Fi
```

O adaptador permanece no `estado.json` e uma nova tentativa ocorre no ciclo seguinte. O mesmo erro é registrado apenas uma vez.

## 8. Wi-Fi ficou desativado após remover a automação

Versões anteriores à 1.2 não reativavam o Wi-Fi na desinstalação. Reative em Configurações > Rede e Internet > Configurações de rede avançadas, ou:

```powershell
Get-NetAdapter -Physical | Where-Object InterfaceType -eq 71 | Enable-NetAdapter -Confirm:$false
```

## 9. Teste direto

Pare a tarefa antes (o mutex impede duas instâncias) e, como administrador:

```powershell
Stop-ScheduledTask -TaskName "Controle Automático de Rede"
powershell.exe -ExecutionPolicy Bypass -File .\src\ControleRede.ps1
```

Interrompa com `Ctrl + C`.
