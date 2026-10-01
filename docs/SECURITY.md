# Segurança

## Privilégios

A tarefa executa como:

```text
NT AUTHORITY\SYSTEM
```

com:

```text
RunLevel = Highest
```

Isso permite controlar adaptadores sem depender da sessão do usuário.

## ExecutionPolicy

Nenhuma política permanente do PowerShell é alterada.

O projeto usa:

```text
-ExecutionPolicy Bypass
```

somente nos processos envolvidos na instalação e execução.

## Estado

O arquivo:

```text
estado.json
```

registra somente os nomes dos adaptadores Wi-Fi que foram desativados pela automação.

## Logs

Não publique logs reais no GitHub.

O `.gitignore` exclui arquivos `.log`.

## Recomendações

Em ambiente corporativo:

- teste antes de distribuir;
- valide políticas de execução;
- considere assinatura de scripts;
- revise o uso de `SYSTEM`;
- distribua somente para máquinas autorizadas.
