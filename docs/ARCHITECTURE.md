# Arquitetura — ControleRede 1.1

## Fluxo

```text
Get-NetAdapter -Physical
          |
          +-- Ethernet físico?
          |      |
          |      +-- InterfaceType = 6
          |      +-- HardwareInterface = True
          |      +-- não contém Loopback
          |      +-- NdisPhysicalMedium = 14 quando informado
          |
          +-- Link físico Connected?
                 |
                 +-- SIM --> desativa Wi-Fi
                 |           registra no estado.json
                 |
                 +-- NÃO --> consulta estado.json
                             |
                             +-- reativa Wi-Fi controlado
```

## Por que a versão 1.0 apresentou problema

A identificação anterior utilizava somente:

```powershell
InterfaceType -eq 6
```

Na máquina analisada, isso permitiu que:

```text
Topaz Loopback
```

fosse tratado como Ethernet conectado.

A consequência era que a condição Ethernet permanecia verdadeira mesmo quando o cabo físico era retirado.

## Versão 1.1

A identificação agora exige múltiplas condições.

A condição decisiva continua sendo:

```powershell
MediaConnectionState -eq "Connected"
```

mas somente depois que o adaptador passa pelos filtros de interface física.

## Estado

O estado é persistido em:

```text
C:\ProgramData\ControleRede\estado.json
```

Um adaptador Wi-Fi só sai do estado quando o Windows confirma que ele deixou de estar `Disabled`.

Se a reativação falhar, o nome permanece registrado para uma nova tentativa no próximo ciclo.
