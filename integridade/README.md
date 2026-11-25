# Monitor de integridade SHA-256 do roteador

O [monitor](monitor.sh) calcula SHA‑256 de `/etc/passwd`, `/etc/shadow` e das regras ativas da tabela IPv4 `filter`, lidas com `iptables-save -t filter`. Os arquivos de contas são lidos somente no contêiner `ubuntu-router` como root. O script usa a capacidade `NET_ADMIN` que o roteador já possui para consultar as regras. O monitor não aplica nem restaura regras e não altera o Docker Compose, o firewall, o SSH ou as rotas.

## Preparação no Docker

Suba a infraestrutura conforme o [README do firewall](../firewall/README.md). Na raiz do repositório, execute no PowerShell. O roteador precisa estar com o firewall de Victor ativo. O script usa Bash, `awk`, `sha256sum`, `flock`, `stat` e `iptables-save`, disponíveis na imagem usada na validação.

```powershell
Set-Location shozz-infra-lab/infraestrutura
docker compose ps
docker compose exec -T ubuntu-router iptables -S
docker compose cp ../../integridade/monitor.sh ubuntu-router:/usr/local/sbin/isp-integridade.sh
docker compose exec -T ubuntu-router bash /usr/local/sbin/isp-integridade.sh init
docker compose exec -T ubuntu-router bash /usr/local/sbin/isp-integridade.sh check
```

Faça `init` apenas depois de revisar o estado conhecido do roteador. A coleta real exige `INPUT DROP`, `FORWARD DROP` e a cadeia `SHOZZ_SSH_RATE` de Victor para aceitar a referência. Essas checagens apoiam a revisão. Confira as regras completas antes de aceitar o estado. Se a referência já existe, `init` devolve erro e a preserva.

O estado padrão fica em `/var/lib/isp-integridade`. O diretório exige modo `0700` e os arquivos `referencia.sha256`, `auditoria.log` e `operacao.lock` exigem modo `0600`. No roteador, pertencem ao root. A referência guarda os hashes e rótulos dos alvos, o escopo e o identificador da transação no formato atual. O log registra data/hora UTC, alvo, estado e eventual motivo. Ele não expõe os hashes nem o conteúdo de `/etc/shadow`.

## Verificação, atualização e periodicidade

| Comando | Efeito |
| --- | --- |
| `init` | Cria uma referência inicial se ela ainda não existir. |
| `check` | Compara cada hash e registra `OK`, `ALERTA` ou `ERRO`. A referência permanece intacta. |
| `update --confirmar` | Substitui a referência após uma decisão administrativa explícita. Requer uma referência válida, coleta todos os alvos e registra a preparação antes da troca. |
| `watch SEGUNDOS [CICLOS]` | Verifica imediatamente, espera o intervalo entre ciclos e repete. Com `CICLOS`, encerra após a quantidade solicitada. |

Se houver uma divergência, confira a mudança aprovada mais recente e inspecione o arquivo ou as regras com os procedimentos operacionais do grupo. Depois de validar uma mudança legítima, atualize a referência e confirme com `check`. Use o [procedimento de resposta da PSI](../documentacao/POLITICA_SEGURANCA_INFORMACAO.md#resposta-a-incidentes) quando a alteração for inesperada.

```powershell
docker compose exec -T ubuntu-router bash /usr/local/sbin/isp-integridade.sh watch 2 3
docker compose exec -T ubuntu-router tail -n 15 /var/lib/isp-integridade/auditoria.log

# Após revisar e aprovar uma alteração legítima
docker compose exec -T ubuntu-router bash /usr/local/sbin/isp-integridade.sh update --confirmar
docker compose exec -T ubuntu-router bash /usr/local/sbin/isp-integridade.sh check
```

Para acompanhamento contínuo, rode `docker compose exec ubuntu-router bash /usr/local/sbin/isp-integridade.sh watch 30` em um terminal interativo e interrompa com **Ctrl+C**. Para uma sessão limitada pelo tempo, use `docker compose exec -T ubuntu-router timeout 60s bash /usr/local/sbin/isp-integridade.sh watch 5`. O monitor registra encerramento ao completar os ciclos ou receber `SIGINT` ou `SIGTERM`. O laço Bash funciona em Docker sem `cron` ou `systemd`. Ele precisa ser iniciado novamente após reiniciar o contêiner. Numa recriação da infraestrutura, a cópia do script e seu estado local deixam de existir. Preserve uma referência confiável em armazenamento protegido se precisar da continuidade entre recriações.

| Código de saída | Significado |
| --- | --- |
| `0` | Comparação íntegra ou referência efetivada. Se o comando avisar que a confirmação de auditoria está pendente, a referência nova já está ativa. |
| `1` | Pelo menos um alvo divergiu. |
| `2` | Uso incorreto, referência inválida, permissão insuficiente ou erro de coleta. |
| `130` / `143` | O monitor recebeu `SIGINT` / `SIGTERM`. Com `timeout`, o executor normalmente devolve `124` ao atingir o tempo limite. |

Cada ciclo continua após uma divergência, e o código final de um acompanhamento limitado é o mais severo encontrado. Operações de verificação e troca da referência são serializadas com `flock`.

### Auditoria e recuperação da referência

1. O monitor prepara os três hashes em um arquivo temporário privado no mesmo diretório da referência e sincroniza seus dados.
2. O monitor confere o dono, o modo e a possibilidade de escrever no log. Ele só prossegue depois de gravar e sincronizar `REFERENCIA_PREPARADA` com o identificador da transação. Uma falha nessa etapa preserva a referência anterior e retorna `2`.
3. A renomeação atômica efetiva a referência. O monitor sincroniza o diretório e registra `REFERENCIA_CRIADA` ou `REFERENCIA_ATUALIZADA`. Se a troca falhar e a referência continuar anterior, a operação retorna `2` e tenta registrar `REFERENCIA_ABORTADA`.
4. Se a confirmação falhar após a troca, a operação retorna `0` com aviso explícito de confirmação pendente. O registro de preparação permanece no log, e o identificador acompanha a referência ativa. Depois de restabelecer o log, execute `check`. Ele confirma a transação com `REFERENCIA_RECUPERADA` e prossegue com as comparações. Um registro apenas `PREPARADA` não comprova que a troca ocorreu.

O formato anterior (`v1`) continua legível. Somente uma atualização explícita troca uma referência anterior pelo formato com identificador (`v2`). Caso preserve o estado entre recriações, guarde também o log protegido para conservar o histórico das transações.

## Por que a representação das regras é estável

`iptables-save -t filter` consulta a tabela usada pelo firewall. O monitor remove comentários de cabeçalho/rodapé, zera os contadores nas declarações de cadeias e remove prefixos de contador por regra. Ele preserva políticas, ordem das regras, definições de cadeias e opções como `--comment`. Mudanças de horário e de tráfego não alteram o hash canônico. Trocar uma política de `DROP` para `ACCEPT` altera o hash. Use o mesmo backend e versão de `iptables-save` como referência depois de revisar uma atualização do equipamento. [Manual do iptables-save](https://man7.org/linux/man-pages/man8/iptables-save.8.html)

## Testes reproduzíveis

No Bash do Linux ou WSL, a partir da raiz.

```bash
bash integridade/teste.sh
```

Os testes usam arquivos temporários chamados `passwd`, `shadow` e `iptables-save.txt`, com campos fictícios. Não alteram os arquivos de contas do host ou as regras ativas. Para experimentar outras amostras, use `bash integridade/monitor.sh --amostras CAMINHO_DAS_AMOSTRAS --estado DIRETORIO_PRIVADO init`, seguido de `check` com as mesmas opções. As amostras precisam incluir os três nomes esperados. O monitor separa a referência de amostras da referência do roteador.

| Teste executado | Resultado observado |
| --- | --- |
| Comparação inicial e permissões | Os três alvos ficaram `OK`. O diretório ficou em `0700` e os arquivos em `0600`. |
| Mudança só de horários e contadores | O hash de regras permaneceu igual. |
| Mudanças de conteúdo em amostras | Houve `ALERTA` para cada um dos três alvos e código `1`. Os eventos foram registrados no log. |
| Ciclos e parada | Três ciclos repetiram as divergências nas amostras. `timeout` encerrou o monitor com o sinal registrado. |
| Atualização de referência | `init` repetido e `update` sem `--confirmar` foram recusados. A referência só mudou no comando confirmado e, em seguida, `check` passou. |
| Regressão de auditoria | A falha simulada ao preparar o log, as permissões incorretas e a falha na renomeação preservaram a referência. A falha após a troca retornou `0` com aviso, e o próximo `check` registrou a confirmação pendente uma única vez. |
| Compatibilidade | Uma referência `v1` passou em `check` e foi migrada para `v2` somente com `update --confirmar`. |
| Contas e regras reais | Os três alvos ficaram `OK` no roteador. A tentativa com usuário `ubuntu` foi recusada. |
| Tráfego durante três ciclos | O contador de ICMP permitido subiu em cinco. As nove comparações ficaram `OK`. O ping LAN → WAN recebeu 2 de 2 respostas na prova direta. |
| Coexistência com o firewall e SSH | `iptables -S` e os três IDs permaneceram iguais. O Nmap mostrou `2222/tcp open` na LAN e `filtered` na WAN. `sshd -t` passou e os três serviços ficaram `Up`. |
| Revalidação da versão corrigida no Docker | A atualização foi executada em uma referência temporária com os alvos reais, seguida de três ciclos com nove resultados `OK`. A cópia instalada passou em `check`. A referência em uso e as regras do firewall foram comparadas antes e depois e permaneceram iguais. |

[Testes com amostras e regressões](../evidencias/integridade/01-amostras.txt) · [Reprodução antes da correção](../evidencias/integridade/03-regressao-antes.txt) · [Validação original no roteador](../evidencias/integridade/02-roteador.txt) · [Revalidação no roteador](../evidencias/integridade/04-roteador-revalidacao.txt)

## Limitações

- O hash indica que o conteúdo mudou, sem identificar quem mudou, a causa ou a alteração específica. O monitor não corrige automaticamente o incidente.
- A comparação periódica pode perder mudanças feitas e revertidas entre ciclos. Referência e auditoria locais podem ser alteradas por quem comprometer o root do roteador. Em produção, mantenha cópias e alertas em um sistema protegido e separado.
- A cobertura de rede é a tabela IPv4 `filter` no roteador. Tabelas NAT, IPv6, regras do host e metadados como dono e permissões dos arquivos monitorados ficam fora do hash. O script valida as permissões do seu próprio estado.
- O procedimento local exige instalação pelo console Docker. A imagem e os arquivos Compose foram preservados. Após recriar o contêiner, reinstale o script e recupere uma referência aprovada quando houver uma disponível.
