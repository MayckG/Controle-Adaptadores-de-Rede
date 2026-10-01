# Troubleshooting

## 1. Verificar adaptadores

```powershell
Get-NetAdapter -Physical |
    Select-Object Name,
        InterfaceDescription,
        InterfaceType,
        HardwareInterface,
        NdisPhysicalMedium,
        Status,
        MediaConnectionState
```

## 2. Verificar a tarefa

```powershell
Get-ScheduledTask `
    -TaskName "Controle Automático de Rede"
```

```powershell
Get-ScheduledTaskInfo `
    -TaskName "Controle Automático de Rede"
```

## 3. Verificar estado

```text
C:\ProgramData\ControleRede\estado.json
```

Esperado enquanto o cabo estiver conectado:

```json
{
    "DisabledWifiAdapters": [
        "Wi-Fi"
    ]
}
```

Depois da reativação bem-sucedida:

```json
{
    "DisabledWifiAdapters": []
}
```

## 4. Verificar log

```text
C:\ProgramData\ControleRede\logs\controle-rede.log
```

Sequência esperada:

```text
ESTADO | Ethernet físico CONECTADO.
AÇÃO | Desativando Wi-Fi: Wi-Fi
OK | Wi-Fi desativado: Wi-Fi

ESTADO | Nenhum Ethernet físico conectado.
AÇÃO | Reativando Wi-Fi: Wi-Fi
OK | Wi-Fi reativado: Wi-Fi
```

## 5. Topaz Loopback

Se aparecer:

```text
Topaz Loopback
```

ele não deve ser considerado Ethernet físico pela versão 1.1.

## 6. Reativação falha

Se o log mostrar:

```text
ERRO | Falha ao reativar Wi-Fi
```

o nome permanece em `estado.json`, permitindo nova tentativa no ciclo seguinte.

## 7. Teste direto

Como administrador:

```powershell
powershell.exe `
    -ExecutionPolicy Bypass `
    -File .\src\ControleRede.ps1
```

Interrompa com:

```text
Ctrl + C
```
