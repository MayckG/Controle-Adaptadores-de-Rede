# Troubleshooting

## A tarefa não iniciou

Verifique:

```powershell
Get-ScheduledTask -TaskName "Controle Automático de Rede"
```

Depois:

```powershell
Get-ScheduledTaskInfo -TaskName "Controle Automático de Rede"
```

## Verificar adaptadores

```powershell
Get-NetAdapter -Physical |
    Select-Object Name, InterfaceType, Status, MediaConnectionState
```

## Verificar log

```text
C:\ProgramData\ControleRede\logs\controle-rede.log
```

## O Wi-Fi não foi reativado

Verifique o estado:

```text
C:\ProgramData\ControleRede\estado.json
```

Se o adaptador não estiver registrado, a automação deliberadamente não o reativará.

Isso evita alterar uma decisão manual anterior.

## Ethernet aparece como conectado sem cabo

Verifique:

```powershell
Get-NetAdapter -Physical |
    Select-Object Name, Status, MediaConnectionState
```

Se o driver reportar incorretamente o estado físico, a automação dependerá dessa informação fornecida pelo Windows/driver.

## Teste manual

Como administrador:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\src\ControleRede.ps1
```

Interrompa com:

```text
Ctrl + C
```
