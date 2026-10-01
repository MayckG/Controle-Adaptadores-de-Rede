# Segurança

## Privilégios

A tarefa executa como `NT AUTHORITY\SYSTEM` com `RunLevel = Highest`, necessário para ativar e desativar adaptadores sem depender da sessão do usuário.

## Permissões da pasta de instalação

Como o script é executado como SYSTEM, quem puder alterá-lo poderia executar código com privilégio máximo. Por isso o instalador:

- assume a propriedade de `C:\ProgramData\ControleRede` e de todo o conteúdo (inclusive arquivos criados antes da instalação);
- remove a herança de permissões do ProgramData;
- concede controle total apenas a SYSTEM e Administradores e somente leitura a Usuários.

As permissões são aplicadas por SID, funcionando em Windows de qualquer idioma.

Para conferir:

```powershell
icacls "C:\ProgramData\ControleRede"
```

## ExecutionPolicy

Nenhuma política permanente do PowerShell é alterada. `-ExecutionPolicy Bypass` é usado somente nos processos de instalação e execução.

## Estado

O `estado.json` registra apenas GUID, nome e descrição dos adaptadores Wi-Fi desativados pela automação.

## Logs

Não publique logs reais no GitHub; o `.gitignore` exclui arquivos `.log`.

## Recomendações para distribuição a clientes

- teste em um equipamento piloto antes de distribuir;
- considere assinar os scripts com certificado de assinatura de código;
- distribua somente para máquinas autorizadas;
- informe ao cliente como desinstalar e onde ficam os logs.
