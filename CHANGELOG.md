# Changelog

## 1.2.0

### Correções

- **Tarefa encerrada após 72 horas.** O limite padrão de execução das tarefas agendadas encerrava o monitoramento após 3 dias ligado (comum com a Inicialização Rápida do Windows), podendo deixar o Wi-Fi desativado. Agora a tarefa não tem limite de tempo.
- **Desinstalação deixava o Wi-Fi desativado.** O desinstalador agora reativa o Wi-Fi controlado antes de remover os arquivos.
- **Escalonamento de privilégio.** A pasta de instalação herdava permissões do ProgramData, permitindo que um usuário comum preparasse arquivos executados depois como SYSTEM. O instalador agora assume a propriedade da pasta e restringe a escrita a SYSTEM e Administradores (por SID, independentemente do idioma do Windows).
- **Acentuação corrompida.** Os scripts estavam em UTF-8 sem BOM, lidos como ANSI pelo Windows PowerShell 5.1 (nome da tarefa e mensagens de log com caracteres trocados). Agora são salvos com BOM.
- Wi-Fi não encontrado gerava um aviso no log a cada 3 segundos; agora avisa uma única vez.
- `estado.json` era regravado a cada ciclo com o cabo conectado; agora só é gravado quando muda.
- O Wi-Fi é registrado no estado **antes** de ser desativado, evitando perder o controle se o processo for encerrado no meio da operação.
- Logs arquivados agora têm retenção.

### Melhorias

- O Wi-Fi só é desativado se o Ethernet tiver IP válido e gateway padrão (não basta o link físico).
- Proteção contra oscilação: confirmações antes de desligar e tolerância antes de religar.
- Adaptadores identificados por GUID; migração automática do `estado.json` da versão 1.1.
- Reação imediata a eventos de rede, com verificação periódica como reserva.
- Instância única, `config.json`, exclusão de VPN e adaptadores virtuais conhecidos.
- Erros repetidos não inundam mais o log.
- Testes de simulação em `tests/`.

## 1.1.0

- Detecção restrita a Ethernet físico (exclui loopback, como Topaz Loopback).

## 1.0.0

- Versão inicial.
