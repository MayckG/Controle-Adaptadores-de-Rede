# ControleRede

Automação para Windows que alterna automaticamente entre Ethernet e Wi-Fi conforme a presença de **link físico Ethernet**.

## Versão

**1.1.0**

### Correção principal desta versão

A versão 1.0 identificava qualquer interface com `InterfaceType = 6` como Ethernet candidata. Isso permitiu que interfaces de loopback/virtuais, como **Topaz Loopback**, fossem consideradas como link físico.

A versão 1.1 restringe a detecção para interfaces Ethernet físicas e valida:

- `Get-NetAdapter -Physical`;
- `InterfaceType = 6`;
- `HardwareInterface = True`;
- `NdisPhysicalMedium = 14` quando disponível;
- `MediaConnectionState = Connected`;
- exclusão explícita de interfaces com `Loopback` no nome/descrição.

## Comportamento

```text
Ethernet físico com cabo
        ↓
Wi-Fi ativo?
        ↓
SIM → desativa Wi-Fi
        ↓
registra Wi-Fi no estado.json
```

Quando o cabo é removido:

```text
Ethernet físico sem link
        ↓
estado.json possui Wi-Fi controlado?
        ↓
SIM → reativa Wi-Fi
        ↓
limpa estado.json
```

O projeto **não reativa Wi-Fi que já estava desativado antes da automação**.

## Recursos

- descoberta automática de adaptadores;
- sem nomes fixos como `Ethernet` ou `Wi-Fi`;
- diferencia adaptador habilitado de link físico;
- ignora loopback e interfaces virtuais na decisão Ethernet;
- preserva o estado dos adaptadores Wi-Fi controlados;
- execução silenciosa;
- inicialização automática com o Windows;
- execução como `SYSTEM`;
- logs;
- rotação de logs acima de 5 MB;
- reinstalação simples;
- desinstalação simples.

## Estrutura

```text
ControleRede/
├── src/
│   └── ControleRede.ps1
├── installer/
│   ├── Instalar.bat
│   └── Config.ps1
├── uninstaller/
│   ├── Desinstalar.bat
│   └── Desinstalar.ps1
├── docs/
│   ├── ARCHITECTURE.md
│   ├── SECURITY.md
│   └── TROUBLESHOOTING.md
├── logs/
│   └── .gitkeep
├── .gitignore
├── LICENSE
└── README.md
```

## Instalação

Execute:

```text
installer\Instalar.bat
```

O instalador solicitará privilégios administrativos.

A tarefa criada é:

```text
Controle Automático de Rede
```

e executa como:

```text
NT AUTHORITY\SYSTEM
```

## Desinstalação

Execute:

```text
uninstaller\Desinstalar.bat
```

## Arquivos instalados

```text
C:\ProgramData\ControleRede\
├── ControleRede.ps1
├── estado.json
└── logs\
    └── controle-rede.log
```

## Diagnóstico

```powershell
Get-ScheduledTask -TaskName "Controle Automático de Rede"
```

```powershell
Get-ScheduledTaskInfo -TaskName "Controle Automático de Rede"
```

```powershell
Get-NetAdapter -Physical |
    Select-Object Name, InterfaceDescription, InterfaceType,
                  HardwareInterface, NdisPhysicalMedium,
                  Status, MediaConnectionState
```

Log:

```text
C:\ProgramData\ControleRede\logs\controle-rede.log
```

Estado:

```text
C:\ProgramData\ControleRede\estado.json
```

## Teste recomendado

1. Instale o projeto.
2. Conecte o cabo Ethernet.
3. Confirme no log que o Ethernet físico foi detectado.
4. Confirme que o Wi-Fi foi desativado.
5. Confirme que `estado.json` contém o adaptador Wi-Fi.
6. Remova fisicamente o cabo.
7. Aguarde até 3 segundos.
8. Confirme no log:
   - Ethernet físico desconectado;
   - Wi-Fi reativado.
9. Confirme que `estado.json` foi limpo.

## Segurança

A instalação utiliza `-ExecutionPolicy Bypass` somente no processo necessário e não altera permanentemente a política de execução do Windows.

A tarefa operacional utiliza `SYSTEM` com nível elevado porque as operações de adaptador exigem privilégios administrativos.

## Licença

MIT.
