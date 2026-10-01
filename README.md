# ControleRede

Automação para Windows que alterna automaticamente entre Ethernet e Wi-Fi: o Wi-Fi é desativado quando há um **Ethernet físico conectado e com rede funcionando**, e reativado quando o cabo é removido ou a rede cabeada deixa de funcionar.

## Versão

**1.2.0** — veja o [CHANGELOG](CHANGELOG.md).

## Comportamento

```text
Ethernet físico com link
        ↓
Possui IP válido e gateway padrão?  (não conta APIPA 169.254.x.x)
        ↓
NÃO → mantém o Wi-Fi ligado
SIM → confirmado em 2 verificações seguidas?
        ↓
SIM → registra o Wi-Fi no estado.json e o desativa
```

Quando o cabo é removido, o Wi-Fi é reativado **imediatamente**.

Quando o cabo continua conectado, mas a rede cabeada para de funcionar, o Wi-Fi é reativado após o período de tolerância (padrão: 15 segundos).

O projeto **nunca reativa um Wi-Fi que já estava desativado antes da automação**.

## Recursos

- descoberta automática de adaptadores, sem nomes fixos;
- adaptadores identificados por GUID (renomear um adaptador não quebra o controle);
- validação de conectividade (IP + gateway) antes de desligar o Wi-Fi;
- proteção contra oscilação (confirmações e período de tolerância);
- ignora loopback, VPN e adaptadores virtuais conhecidos;
- reação imediata a eventos de rede, com verificação periódica como reserva;
- instância única (mutex);
- configurável por `config.json`;
- execução silenciosa como `SYSTEM`, iniciada com o Windows e sem limite de tempo;
- pasta de instalação protegida contra alteração por usuários comuns;
- logs com rotação e retenção;
- desinstalação que reativa o Wi-Fi controlado.

## Estrutura

```text
ControleRede/
├── src/
│   ├── ControleRede.ps1
│   └── config.json
├── installer/
│   ├── Instalar.bat
│   └── Config.ps1
├── uninstaller/
│   ├── Desinstalar.bat
│   └── Desinstalar.ps1
├── tests/
│   └── Simulacao.Tests.ps1
├── docs/
│   ├── ARCHITECTURE.md
│   ├── SECURITY.md
│   └── TROUBLESHOOTING.md
├── logs/
│   └── .gitkeep
├── CHANGELOG.md
├── .gitattributes
├── .gitignore
├── LICENSE
└── README.md
```

## Instalação

Execute `installer\Instalar.bat`. O instalador solicitará privilégios administrativos.

Reinstalar sobre uma versão anterior é seguro: o `estado.json` é preservado (e migrado do formato 1.1) e o `config.json` existente não é sobrescrito.

A tarefa criada é **Controle Automático de Rede** e executa como `NT AUTHORITY\SYSTEM`.

## Desinstalação

Execute `uninstaller\Desinstalar.bat`. Antes de remover os arquivos, o desinstalador reativa todo Wi-Fi que a automação havia desativado.

## Configuração

Arquivo `C:\ProgramData\ControleRede\config.json`. Após alterar, reinicie a tarefa (ou o computador).

| Chave | Padrão | Descrição |
|---|---|---|
| `IntervalSeconds` | 3 | Intervalo da verificação periódica (reserva aos eventos). |
| `StableChecksBeforeDisable` | 2 | Verificações seguidas com rede cabeada antes de desligar o Wi-Fi. |
| `ConnectivityLossGraceSeconds` | 15 | Tolerância antes de religar o Wi-Fi quando o cabo tem link mas a rede caiu. |
| `RequireDefaultGateway` | true | Exige gateway padrão no Ethernet. Use `false` em redes isoladas sem gateway. |
| `MaxLogBytes` | 5242880 | Tamanho máximo do log antes da rotação. |
| `LogRetentionCount` | 5 | Quantidade de logs arquivados mantidos. |
| `ExcludedAdapterPatterns` | Loopback, VPN… | Trechos de nome/descrição que nunca contam como Ethernet. |

## Arquivos instalados

```text
C:\ProgramData\ControleRede\
├── ControleRede.ps1
├── config.json
├── estado.json
└── logs\
    └── controle-rede.log
```

## Diagnóstico

```powershell
Get-ScheduledTask -TaskName "Controle Automático de Rede"
Get-ScheduledTaskInfo -TaskName "Controle Automático de Rede"
```

```powershell
Get-NetAdapter -Physical |
    Select-Object Name, InterfaceDescription, InterfaceType,
                  HardwareInterface, NdisPhysicalMedium,
                  Status, MediaConnectionState
```

Mais detalhes em [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md).

## Testes

A lógica de decisão pode ser testada sem tocar em adaptadores reais:

```powershell
powershell -ExecutionPolicy Bypass -File .\tests\Simulacao.Tests.ps1
```

### Teste manual recomendado

1. Instale o projeto e conecte o cabo Ethernet.
2. Confirme no log `ESTADO | Ethernet físico CONECTADO e com rede.` e o Wi-Fi desativado.
3. Remova o cabo e confirme no log que o Wi-Fi foi reativado em poucos segundos.
4. Conecte o cabo a uma porta sem rede (ou desative o DHCP): o Wi-Fi deve permanecer ligado.
5. Desinstale com o cabo conectado e confirme que o Wi-Fi volta a funcionar.

## Segurança

Veja [docs/SECURITY.md](docs/SECURITY.md).

## Licença

MIT.
