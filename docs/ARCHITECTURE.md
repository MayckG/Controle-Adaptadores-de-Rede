# Arquitetura

## Componentes

### `src/ControleRede.ps1`

Motor da automação.

Responsabilidades:

- descoberta de adaptadores;
- identificação de Ethernet e Wi-Fi;
- detecção do link físico;
- controle dos adaptadores;
- persistência de estado;
- logging;
- loop de monitoramento.

### `installer/Config.ps1`

Configura o ambiente operacional.

Responsabilidades:

- validar privilégios;
- criar diretórios;
- copiar o motor para `ProgramData`;
- criar estado inicial;
- registrar a Tarefa Agendada;
- iniciar a tarefa.

### `uninstaller/Desinstalar.ps1`

Remove a instalação.

Responsabilidades:

- parar a tarefa;
- remover a tarefa;
- remover os arquivos instalados.

## Estado

A automação utiliza um modelo simples:

```text
Ethernet link = Connected
        |
        +--> Wi-Fi ativo -> desativa e registra
        |
Ethernet link = Disconnected
        |
        +--> Wi-Fi registrado como desativado
                 |
                 +--> reativa
```

## Frequência

A verificação ocorre a cada 3 segundos.

O intervalo pode ser alterado em:

```powershell
$IntervalSeconds = 3
```

## Adaptadores virtuais

O mecanismo utiliza:

```powershell
Get-NetAdapter -Physical
```

Portanto, adaptadores virtuais de VPN, Hyper-V, VMware e similares não entram na descoberta principal.
