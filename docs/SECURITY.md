# Segurança

## Privilégios

A tarefa operacional é registrada como:

```text
NT AUTHORITY\SYSTEM
```

com nível:

```text
Highest
```

Isso permite executar:

```powershell
Disable-NetAdapter
Enable-NetAdapter
```

sem depender de uma sessão interativa do usuário.

## ExecutionPolicy

O projeto não modifica permanentemente a política de execução do PowerShell.

A opção:

```text
-ExecutionPolicy Bypass
```

é aplicada somente ao processo iniciado pelo instalador ou pela tarefa.

## Estado controlado

O Wi-Fi somente é reativado quando estiver registrado no:

```text
estado.json
```

como um adaptador que a própria automação desativou.

## Log

O log pode conter nomes dos adaptadores de rede existentes na máquina.

Por isso:

- não publique logs reais do computador no GitHub;
- mantenha `logs/` fora do controle de versão;
- use `.gitignore`.

## Distribuição

Antes de distribuir internamente, recomenda-se:

- validar o código;
- testar em máquinas representativas;
- revisar políticas de segurança da organização;
- considerar assinatura de scripts PowerShell em ambientes corporativos.
