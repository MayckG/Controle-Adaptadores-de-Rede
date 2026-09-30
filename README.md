# ControleRede

Automação para Windows que gerencia automaticamente os adaptadores de rede:

- quando existe **link físico Ethernet**, o Wi-Fi é desativado;
- quando o **link físico Ethernet desaparece**, o Wi-Fi que a automação desativou é reativado;
- os adaptadores são descobertos automaticamente;
- não depende dos nomes `Ethernet`, `Wi-Fi` etc.;
- executa em segundo plano como **Tarefa Agendada do Windows**;
- utiliza privilégios elevados via `SYSTEM`;
- mantém log e estado da automação;
- não altera permanentemente a política de execução do PowerShell.

> **Objetivo:** manter uma única rota de rede preferencial em computadores Windows que alternam entre Ethernet e Wi-Fi.

---

## ✨ Recursos

### Descoberta automática

O projeto não fixa nomes de interfaces.

A identificação utiliza propriedades do Windows:

| Tipo | `InterfaceType` |
|---|---:|
| Ethernet | `6` |
| Wi-Fi | `71` |

São considerados somente adaptadores físicos por meio de:

```powershell
Get-NetAdapter -Physical
```

### Detecção do cabo

O projeto não considera simplesmente:

```text
Status = Up
```

Ele verifica o estado físico do link:

```powershell
MediaConnectionState -eq "Connected"
```

Isso permite diferenciar:

```text
Ethernet habilitado
```

de:

```text
Ethernet com cabo/link físico conectado
```

### Preservação do estado do Wi-Fi

A automação registra quais adaptadores Wi-Fi foram desativados por ela.

Consequentemente, se o Wi-Fi já estava desativado antes da automação agir, ele não será reativado arbitrariamente quando o cabo for removido.

---

## 🏗️ Arquitetura

```text
ControleRede
│
├── src
│   └── ControleRede.ps1
│
├── installer
│   ├── Instalar.bat
│   └── Config.ps1
│
├── uninstaller
│   ├── Desinstalar.bat
│   └── Desinstalar.ps1
│
├── docs
│   ├── ARCHITECTURE.md
│   ├── SECURITY.md
│   └── TROUBLESHOOTING.md
│
├── logs
│   └── .gitkeep
│
├── .gitignore
├── LICENSE
└── README.md
```

---

## 🚀 Instalação

### Requisitos

- Windows 10 ou superior
- PowerShell 5.1+
- privilégios administrativos

### Instalação

Execute:

```text
installer\Instalar.bat
```

O instalador solicitará elevação via UAC quando necessário.

Depois da instalação, a automação será executada como:

```text
NT AUTHORITY\SYSTEM
```

através da Tarefa Agendada:

```text
Controle Automático de Rede
```

Não é necessário manter uma janela do PowerShell aberta.

---

## 🗑️ Desinstalação

Execute:

```text
uninstaller\Desinstalar.bat
```

A desinstalação:

1. interrompe a tarefa;
2. remove a Tarefa Agendada;
3. remove os arquivos instalados em:

```text
C:\ProgramData\ControleRede
```

---

## ⚙️ Funcionamento

```text
                 ┌──────────────────────────┐
                 │  Descobrir adaptadores   │
                 │       físicos             │
                 └────────────┬─────────────┘
                              │
                              ▼
                 ┌──────────────────────────┐
                 │ Existe Ethernet com      │
                 │ link físico conectado?   │
                 └────────────┬─────────────┘
                         ┌────┴────┐
                       SIM         NÃO
                        │            │
                        ▼            ▼
                ┌──────────────┐ ┌──────────────┐
                │ Desativar    │ │ Reativar     │
                │ Wi-Fi que    │ │ somente Wi-Fi│
                │ estiver ativo│ │ controlado   │
                └──────────────┘ └──────────────┘
                        │            │
                        └─────┬──────┘
                              ▼
                       aguarda 3 segundos
                              │
                              └──────► repete
```

A automação utiliza uma abordagem baseada em **estado desejado**, verificando continuamente a situação da rede.

---

## 📁 Arquivos instalados

Após a instalação:

```text
C:\ProgramData\ControleRede\
│
├── ControleRede.ps1
├── estado.json
└── logs\
    └── controle-rede.log
```

### `estado.json`

Registra os adaptadores Wi-Fi que foram desativados pela automação.

Exemplo:

```json
{
    "DisabledWifiAdapters": [
        "Intel(R) Wi-Fi 6E AX211"
    ]
}
```

### Log

```text
C:\ProgramData\ControleRede\logs\controle-rede.log
```

O log é rotacionado automaticamente quando ultrapassa 5 MB.

---

## 🔐 Segurança

O projeto foi desenvolvido para evitar alterações permanentes no sistema.

### ExecutionPolicy

O projeto não executa:

```powershell
Set-ExecutionPolicy -Scope LocalMachine
```

nem altera permanentemente a política de execução.

A execução utiliza:

```text
-ExecutionPolicy Bypass
```

somente no processo correspondente à automação/instalação.

### Privilégios

A tarefa operacional utiliza:

```text
SYSTEM
```

com:

```text
RunLevel = Highest
```

Isso é necessário porque `Disable-NetAdapter` e `Enable-NetAdapter` normalmente exigem privilégios elevados.

---

## 🧪 Teste manual

Antes de instalar como tarefa, o mecanismo pode ser testado como administrador:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\src\ControleRede.ps1
```

Para interromper:

```text
Ctrl + C
```

---

## 🔍 Diagnóstico

Verifique a tarefa:

```powershell
Get-ScheduledTask -TaskName "Controle Automático de Rede"
```

Verifique o estado:

```powershell
Get-ScheduledTaskInfo -TaskName "Controle Automático de Rede"
```

Verifique os adaptadores:

```powershell
Get-NetAdapter -Physical
```

Verifique o estado físico:

```powershell
Get-NetAdapter -Physical |
    Select-Object Name, InterfaceType, Status, MediaConnectionState
```

Verifique o log:

```text
C:\ProgramData\ControleRede\logs\controle-rede.log
```

Mais informações:

- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)
- [`docs/SECURITY.md`](docs/SECURITY.md)
- [`docs/TROUBLESHOOTING.md`](docs/TROUBLESHOOTING.md)

---

## 🛠️ Desenvolvimento

Clone o repositório:

```bash
git clone https://github.com/SEU-USUARIO/ControleRede.git
cd ControleRede
```

Durante o desenvolvimento, recomenda-se testar primeiro o script diretamente e somente depois registrar a Tarefa Agendada.

---

## 🤝 Contribuição

Contribuições são bem-vindas.

Fluxo recomendado:

```text
Fork
  ↓
Branch
  ↓
Alteração
  ↓
Teste
  ↓
Pull Request
```

Antes de enviar um Pull Request:

- teste em Windows;
- valide Ethernet conectado;
- valide Ethernet desconectado;
- valide Wi-Fi inicialmente desativado;
- verifique o log;
- verifique a Tarefa Agendada.

---

## 📄 Licença

Este projeto é distribuído sob a licença definida em [`LICENSE`](LICENSE).

---

## ⚠️ Observações

Este projeto altera o estado dos adaptadores de rede do Windows.

Use-o somente em computadores nos quais você possui autorização administrativa.

A implementação foi desenhada para ambientes em que Ethernet e Wi-Fi são adaptadores físicos. Adaptadores virtuais de VPN, Hyper-V, VMware e similares não são considerados pelo mecanismo principal.
