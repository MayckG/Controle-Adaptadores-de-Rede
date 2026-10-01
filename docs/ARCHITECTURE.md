# Arquitetura — ControleRede 1.2

## Fluxo de decisão

```text
Get-NetAdapter -Physical
          |
          +-- Ethernet físico com link?
          |      InterfaceType = 6
          |      HardwareInterface = True
          |      fora de ExcludedAdapterPatterns (Loopback, VPN...)
          |      NdisPhysicalMedium = 14 quando informado
          |      MediaConnectionState = Connected
          |
          +-- Possui rede utilizável?
                 IP válido (exclui APIPA 169.254.x.x e link-local IPv6)
                 gateway padrão (configurável)

Resultado:
  Usable   -> após N confirmações: registra e desativa o Wi-Fi
  LinkOnly -> se havia Wi-Fi controlado: reativa após a tolerância
  NoLink   -> reativa o Wi-Fi controlado imediatamente
```

## Ciclo

O loop acorda em eventos de rede (`NetworkAddressChanged`, `MSNdis_StatusMediaConnect` e `MSNdis_StatusMediaDisconnect`) ou, na falta deles, a cada `IntervalSeconds`. Após um evento, aguarda 1,5 s para que o Windows atualize link, IP e rotas.

## Estado

`C:\ProgramData\ControleRede\estado.json` (formato 2):

```json
{
    "Version": 2,
    "ControlledWifi": [
        {
            "InterfaceGuid": "{...}",
            "Name": "Wi-Fi",
            "InterfaceDescription": "Intel(R) Wi-Fi 6 AX201"
        }
    ]
}
```

O Wi-Fi é registrado antes de ser desativado. Um adaptador sai do estado quando é reativado com sucesso ou quando já está ativo. Se a reativação falhar, ou o adaptador não estiver presente (ex.: USB removido), ele permanece registrado para nova tentativa.

O estado da versão 1.1 (`DisabledWifiAdapters`, lista de nomes) é migrado automaticamente.

## Instância única

Um mutex `Global\ControleRede` impede execuções simultâneas (por exemplo, a tarefa e um teste manual).
