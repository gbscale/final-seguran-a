# Registro de testes de rede — Infraestrutura LAN/WAN

Laboratório: `shozz-infra-lab` · Branch: `feat/infraestrutura-ssh`

## 1. Identificação da auditoria

| Item | Valor |
|---|---|
| Data | 2026-11-23 |
| Horário da coleta | 16:01:37 a 16:02:32 (UTC-03:00); coleta complementar da revisão final às 16:13:36 (arquivo `16`) |
| Docker Engine (cliente/servidor) | 29.10.0 / 29.10.0 |
| Docker Compose | v5.8.0 |
| Kernel do host (compartilhado pelos contêineres) | 7.0.0-43-generic |
| Projeto Compose | `shozz-infra-lab` (iniciado com `-p shozz-infra-lab`) |
| Arquivo Compose | `shozz-infra-lab/infraestrutura/docker-compose.yml` |
| Contêineres iniciados em | 2026-11-23 15:45:54 (UTC-03:00) |

### Duas origens de resultados

- **Resultados anteriores:** obtidos pela equipe durante a implementação e informados na descrição da tarefa. Não foram salvos em arquivo, por isso não há saída bruta deles neste repositório. A seção 9 traz o resumo.
- **Resultados confirmados nesta auditoria:** coletados em 2026-11-23 entre 16:01 e 16:02. As saídas brutas e completas de cada comando estão na pasta [`saidas/`](saidas/). Cada arquivo começa pelo horário da coleta e pelo comando exato e termina pelo código de saída.

Nenhuma configuração foi alterada para obter estes resultados. Todos os comandos foram de leitura ou de teste não destrutivo (`ping`, `traceroute` com até 5 saltos, leitura de `/proc`).

---

## 2. Estado dos contêineres

Comando: `docker compose -p shozz-infra-lab ps` · Saída: [`saidas/01-conteineres.txt`](saidas/01-conteineres.txt)

| Contêiner | Imagem | Estado | Porta exibida |
|---|---|---|---|
| `shozz-ubuntu-router` | `shozz-infra-lab-ubuntu-router` (build local, Ubuntu 24.04.5 LTS) | Up | `2222/tcp` (apenas `EXPOSE`, sem publicação no host) |
| `shozz-cliente-lan` | `alpine:3.22` | Up | — |
| `shozz-cliente-wan` | `alpine:3.22` | Up | — |

**Resultado: APROVADO.** Os três contêineres estão em execução.

> Observação: `docker compose ps` executado sem `-p` dentro de `infraestrutura/` não lista nada. O projeto foi iniciado com o nome `shozz-infra-lab`, e o nome padrão seria `infraestrutura`. Veja a inconsistência I-1 na seção 10.
>
> **Atualização (revisão final, 2026-11-23 16:13):** foi adicionado `name: shozz-infra-lab` ao `docker-compose.yml`. A partir de então, `docker compose ps` sem `-p` lista os três contêineres, que **não** foram recriados ([`saidas/16-verificacoes-complementares.txt`](saidas/16-verificacoes-complementares.txt)).

## 3. Redes Docker

Comando: `docker network inspect shozz_lan shozz_wan` · Saída: [`saidas/02-redes-docker.txt`](saidas/02-redes-docker.txt)

| Rede | Driver | Sub-rede | Gateway (bridge do host) | Membros |
|---|---|---|---|---|
| `shozz_lan` | bridge | `10.10.10.0/24` | `10.10.10.254` | `shozz-cliente-lan` 10.10.10.10, `shozz-ubuntu-router` 10.10.10.1 |
| `shozz_wan` | bridge | `10.20.20.0/24` | `10.20.20.254` | `shozz-cliente-wan` 10.20.20.10, `shozz-ubuntu-router` 10.20.20.1 |

**Resultado: APROVADO.** As redes existem e estão de acordo com a topologia. O roteador é o único contêiner ligado às duas redes.

## 4. Interfaces e endereços

Saídas: [`saidas/03-interfaces-ubuntu-router.txt`](saidas/03-interfaces-ubuntu-router.txt), [`saidas/03-interfaces-cliente-lan.txt`](saidas/03-interfaces-cliente-lan.txt), [`saidas/03-interfaces-cliente-wan.txt`](saidas/03-interfaces-cliente-wan.txt)

| Contêiner | Interface | Endereço | MAC | Função |
|---|---|---|---|---|
| ubuntu-router | `eth0` | `10.20.20.1/24` | `82:16:c3:56:43:7b` | WAN |
| ubuntu-router | `eth1` | `10.10.10.1/24` | `6e:8c:3f:80:24:8d` | LAN |
| cliente-lan | `eth0` | `10.10.10.10/24` | `2a:73:67:39:eb:1e` | LAN |
| cliente-wan | `eth0` | `10.20.20.10/24` | `8e:bf:04:cb:c7:ef` | WAN |

**Resultado: APROVADO.** Todos os endereços batem com a tabela de endereçamento planejada.

> Nos clientes, o `ip` vem do BusyBox (Alpine) e não aceita a opção `-br`. Por isso a saída registrada é a de `ip addr`.

## 5. Tabelas de rotas

Saídas: [`saidas/04-rotas-*.txt`](saidas/)

**Roteador (`docker exec shozz-ubuntu-router ip route`):**

```text
default via 10.10.10.254 dev eth1
10.10.10.0/24 dev eth1 proto kernel scope link src 10.10.10.1
10.20.20.0/24 dev eth0 proto kernel scope link src 10.20.20.1
```

**Cliente LAN (`docker exec shozz-cliente-lan ip route`):**

```text
default via 10.10.10.254 dev eth0
10.10.10.0/24 dev eth0 scope link  src 10.10.10.10
10.20.20.0/24 via 10.10.10.1 dev eth0
```

**Cliente WAN (`docker exec shozz-cliente-wan ip route`):**

```text
default via 10.20.20.254 dev eth0
10.10.10.0/24 via 10.20.20.1 dev eth0
10.20.20.0/24 dev eth0 scope link  src 10.20.20.10
```

**Resultado: APROVADO.** As duas sub-redes aparecem no roteador como rotas diretamente conectadas (`proto kernel`). Cada cliente tem uma rota estática para a sub-rede oposta, com próximo salto no roteador Ubuntu.

## 6. Encaminhamento IPv4

Saída: [`saidas/05-ip-forward-router.txt`](saidas/05-ip-forward-router.txt)

```text
$ docker exec shozz-ubuntu-router cat /proc/sys/net/ipv4/ip_forward
1
$ docker exec shozz-ubuntu-router sysctl net.ipv4.ip_forward
net.ipv4.ip_forward = 1
```

**Resultado: APROVADO.** O encaminhamento está ativo no namespace de rede do roteador.

> **Complemento (revisão final, 16:13):** o host e os dois clientes também apresentam `ip_forward = 1` ([`saidas/16-verificacoes-complementares.txt`](saidas/16-verificacoes-complementares.txt)). O Compose define o valor apenas no roteador. Os clientes têm uma única interface e não atuam como roteadores. Veja I-9.

## 7. Testes de conectividade (ICMP)

| # | Teste | Comando | Enviados / Recebidos / Perda | TTL | RTT mín/méd/máx (ms) | Resultado | Evidência |
|---|---|---|---|---|---|---|---|
| T1 | LAN → roteador | `docker exec shozz-cliente-lan ping -c 4 10.10.10.1` | 4 / 4 / 0% | 64 | 0,147 / 0,240 / 0,387 | APROVADO | [`06`](saidas/06-ping-lan-para-roteador.txt) |
| T2 | WAN → roteador | `docker exec shozz-cliente-wan ping -c 4 10.20.20.1` | 4 / 4 / 0% | 64 | 0,147 / 0,222 / 0,355 | APROVADO | [`07`](saidas/07-ping-wan-para-roteador.txt) |
| T3 | LAN → WAN | `docker exec shozz-cliente-lan ping -c 4 10.20.20.10` | 4 / 4 / 0% | 63 | 0,236 / 0,504 / 1,117 | APROVADO | [`08`](saidas/08-ping-lan-para-wan.txt) |
| T4 | WAN → LAN | `docker exec shozz-cliente-wan ping -c 4 10.10.10.10` | 4 / 4 / 0% | 63 | 0,368 / 0,512 / 0,673 | APROVADO | [`09`](saidas/09-ping-wan-para-lan.txt) |

**Como ler o TTL:** os sistemas Linux enviam pacotes com TTL inicial 64. Nos testes T1 e T2 o destino é o próprio roteador, e a resposta chega com TTL 64, ou seja, sem nenhum salto intermediário. Nos testes T3 e T4 a resposta chega com **TTL 63**: ela foi decrementada uma vez, o que mostra que passou por exatamente um roteador.

## 8. Verificação do caminho (roteamento)

### 8.1 Decisão de rota nos clientes

Saída: [`saidas/10-route-get-clientes.txt`](saidas/10-route-get-clientes.txt)

```text
$ docker exec shozz-cliente-lan ip route get 10.20.20.10
10.20.20.10 via 10.10.10.1 dev eth0  src 10.10.10.10
$ docker exec shozz-cliente-wan ip route get 10.10.10.10
10.10.10.10 via 10.20.20.1 dev eth0  src 10.20.20.10
```

O kernel dos dois clientes escolhe o roteador Ubuntu como próximo salto, e não o gateway Docker (`.254`).

### 8.2 Traceroute

Saídas: [`saidas/11-traceroute-lan-para-wan.txt`](saidas/11-traceroute-lan-para-wan.txt), [`saidas/12-traceroute-wan-para-lan.txt`](saidas/12-traceroute-wan-para-lan.txt)

```text
$ docker exec shozz-cliente-lan traceroute -n -m 5 -w 2 10.20.20.10
 1  10.10.10.1  0.020 ms  0.030 ms  0.011 ms
 2  10.20.20.10  0.010 ms  0.021 ms  0.013 ms

$ docker exec shozz-cliente-wan traceroute -n -m 5 -w 2 10.10.10.10
 1  10.20.20.1  0.018 ms  0.012 ms  0.017 ms
 2  10.10.10.10  0.011 ms  0.015 ms  0.012 ms
```

Nos dois sentidos, o primeiro salto é a interface do roteador Ubuntu que fica do lado do cliente.

### 8.3 Tabela ARP (camada 2)

Saída: [`saidas/13-vizinhos-arp.txt`](saidas/13-vizinhos-arp.txt)

- O cliente LAN resolveu `10.10.10.1` para o MAC `6e:8c:3f:80:24:8d`, que é a `eth1` do roteador.
- O cliente WAN resolveu `10.20.20.1` para o MAC `82:16:c3:56:43:7b`, que é a `eth0` do roteador.
- O roteador conhece os dois clientes: `10.10.10.10` pela `eth1` e `10.20.20.10` pela `eth0`.

Os quadros enviados pelos clientes para a outra sub-rede têm como destino o MAC do roteador.

### 8.4 Contador de encaminhamento do kernel do roteador

Saída: [`saidas/14-contador-encaminhamento.txt`](saidas/14-contador-encaminhamento.txt)

O contador `Ip: ForwDatagrams` de `/proc/net/snmp`, dentro do roteador, foi lido antes e depois de `ping -c 10` do cliente LAN para o cliente WAN:

```text
ForwDatagrams antes : 44
10 packets transmitted, 10 packets received, 0% packet loss
ForwDatagrams depois: 64
Diferenca: 20
```

O resultado esperado era 10 *echo request* + 10 *echo reply* = 20 datagramas encaminhados, e o aumento foi **exatamente 20**. Essa é a prova direta de que o tráfego entre as sub-redes é encaminhado pelo kernel, dentro do namespace de rede do roteador Ubuntu.

**Resultado da verificação de roteamento: APROVADO.**

## 9. Comparação com os resultados anteriores

| Item | Resultado anterior (informado) | Resultado desta auditoria | Situação |
|---|---|---|---|
| Interfaces do roteador | eth0 = 10.20.20.1 (WAN), eth1 = 10.10.10.1 (LAN) | igual | Confirmado |
| Rotas do roteador | 2 diretamente conectadas + padrão via 10.10.10.254 | igual | Confirmado |
| `ip_forward` | 1 | 1 | Confirmado |
| Rotas do cliente LAN | local + 10.20.20.0/24 via 10.10.10.1 + padrão .254 | igual | Confirmado |
| Rotas do cliente WAN | local + 10.10.10.0/24 via 10.20.20.1 + padrão .254 | igual | Confirmado |
| Pings T1–T4 | 4/4, 0% de perda | 4/4, 0% de perda | Confirmado |
| Traceroute, TTL e contador de encaminhamento | não realizados | realizados nesta auditoria | Novo |

## 10. Inconsistências e observações encontradas

Nenhuma delas impede o funcionamento do roteamento. Todas foram registradas para correção ou para ficarem documentadas. **Nenhum arquivo de configuração foi alterado.**

| ID | Descrição | Impacto | Recomendação |
|---|---|---|---|
| I-1 | O projeto Compose está em execução com o nome `shozz-infra-lab`, mas o `docker-compose.yml` não define `name:`. Sem `-p shozz-infra-lab`, comandos como `docker compose ps` ou `down` executados em `infraestrutura/` usam o nome `infraestrutura` e não encontram os contêineres. Se alguém executar `docker compose up` sem `-p`, haverá conflito de `container_name`. | Operacional | **Corrigido na revisão final:** `name: shozz-infra-lab` foi adicionado ao Compose com autorização. `docker compose config` foi validado (exit 0) e `docker compose ps` sem `-p` encontra os contêineres ([`16`](saidas/16-verificacoes-complementares.txt)). |
| I-2 | O Dockerfile declara `EXPOSE 2222`, mas o `sshd` escuta na porta **22** (`ss -tlnp` e `sshd -T`). O `docker ps` mostra `2222/tcp`, o que leva a erro de interpretação. O `EXPOSE` é só metadado e nenhuma porta está publicada no host. | Documental / SSH | Será resolvido na etapa de SSH seguro, ao configurar `Port 2222` no `sshd_config`. Veja [`15-estado-ssh-atual.txt`](saidas/15-estado-ssh-atual.txt). **Atualização 2026-11-24: corrigido.** O `sshd` escuta só na 2222 e a porta 22 está fechada ([`32`](saidas/32-final-ssh-configuracao-efetiva.txt), [`36`](saidas/36-final-ssh-porta-22-fechada.txt)). Ver seção 12. |
| I-3 | O SSH do roteador ainda usa os padrões da distribuição: `port 22`, `permitrootlogin without-password`, `passwordauthentication yes`, e não há `AllowUsers`. | Segurança (etapa pendente) | Será tratado na etapa de hardening. **Ainda não está concluído.** **Atualização 2026-11-24: corrigido e testado** (`PermitRootLogin no`, `AllowUsers ubuntu`, somente `publickey`). Ver seção 12. |
| I-4 | Os nomes `eth0` (WAN) e `eth1` (LAN) do roteador dependem da ordem em que o Docker conecta as redes. Essa ordem não é garantida entre recriações dos contêineres. | Documental | Identificar as interfaces pelo endereço IP, e não pelo nome. Os testes devem consultar `ip addr` em cada execução. |
| I-5 | A rota padrão do roteador sai pela LAN (`via 10.10.10.254 dev eth1`), e não pela "WAN". No laboratório, a "WAN" é só uma segunda sub-rede interna, sem saída própria para a Internet. | Conceitual | Explicado no README. Não afeta o roteamento entre as sub-redes. |
| I-6 | A rota estática dos clientes é criada pelo `command` do contêiner (`ip route replace ...`). Ela não é persistente fora desse comando e é recriada a cada inicialização. Se o roteador ainda não estiver pronto, a rota é criada mesmo assim, porque só depende do endereço do próximo salto estar na sub-rede local. | Baixo | Comportamento esperado. Está documentado. |
| I-7 | Os clientes têm gateway padrão no host Docker (`.254`). Uma rota estática ausente faria o tráfego seguir para o host, e não para o roteador. | Documental | Os testes `ip route get` e `traceroute` confirmam que, hoje, o caminho usado é o roteador. |
| I-8 | *(Revisão final.)* As redes são bridges comuns, com `internal=false` ([`16`](saidas/16-verificacoes-complementares.txt)). Não há portas publicadas, o que impede conexões de **entrada** vindas de fora do host, mas o tráfego de **saída** não está bloqueado por configuração. Por padrão, o Docker aplica NAT no host. As regras de NAT não foram inspecionadas e nenhum teste de saída foi feito. | Segurança / documental | Isolamento de saída **não configurado nem comprovado**. A decisão (`internal: true` ou outro controle) fica para etapa futura. |
| I-9 | *(Revisão final.)* Os clientes e o host também apresentam `ip_forward = 1`, valor não definido pelo Compose para os clientes. | Documental | Os clientes têm uma única interface e não atuam como roteadores. O encaminhamento entre LAN e WAN foi comprovado no roteador (seção 8.4). |

## 11. Conclusão técnica

Em 2026-11-23, às 16:01–16:02 (UTC-03:00), a auditoria confirmou que:

1. Os três contêineres estão em execução, e as redes `shozz_lan` (10.10.10.0/24) e `shozz_wan` (10.20.20.0/24) existem com os gateways `.254` previstos.
2. O roteador Ubuntu 24.04.5 LTS tem uma interface em cada sub-rede (`eth1` = 10.10.10.1, `eth0` = 10.20.20.1) e está com `net.ipv4.ip_forward = 1`.
3. Os clientes têm rotas estáticas para a sub-rede oposta, com próximo salto no roteador.
4. Todos os quatro testes de conectividade passaram, com 0% de perda.
5. O tráfego entre as sub-redes atravessa o roteador Ubuntu. As provas, independentes entre si, são: `ip route get`, `traceroute` (1º salto = roteador), TTL 63 e o contador `ForwDatagrams` (+20 para 20 pacotes).

**A infraestrutura de roteamento LAN/WAN está funcional e de acordo com a topologia planejada.** O endurecimento do SSH e o hardening do sistema **não** fazem parte desta validação e continuam pendentes (I-2, I-3). O isolamento do tráfego de saída também não foi configurado nem comprovado (I-8).

> **Nota posterior (2026-11-24):** as pendências I-2 e I-3 citadas acima foram resolvidas na segunda auditoria (seção 12). A I-8 continua pendente por decisão do responsável.

---

## 12. Segunda auditoria — SSH seguro e hardening (2026-11-23 23:57 a 2026-11-24 00:09)

Esta seção registra uma rodada **nova**. As seções 1 a 11 acima foram mantidas como registro da primeira auditoria. As saídas brutas desta rodada são os arquivos `17` a `39`, gravados sem espaços em branco no fim das linhas.

### 12.1 Estado encontrado no início da rodada

| Item | Situação encontrada | Fonte |
|---|---|---|
| Contêineres e rede | Os três em execução desde 2026-11-23 15:45; rede igual à da 1ª auditoria | `docker compose ps`, `ip route` |
| SSH | `port 22`, `permitrootlogin without-password`, `passwordauthentication yes`, sem `AllowUsers`, `x11forwarding yes`, `maxauthtries 6` | [`hardening/backup/sshd-T.antes-hardening.txt`](../../hardening/backup/sshd-T.antes-hardening.txt) |
| Usuários | Só `root` e `ubuntu` (UID 1000, grupos `sudo` e `adm`), os dois com senha bloqueada | [`26`](saidas/26-hardening-analise-inicial.txt) |
| Chaves de host | Geradas no build e embutidas na imagem (comentário `root@buildkitsandbox`) | [`18`](saidas/18-ssh-etapa1-chave-ok.txt), [`26`](saidas/26-hardening-analise-inicial.txt) |
| Atualizações | 4 pendentes: `libc6`, `libc-bin`, `libsystemd0`, `libudev1` | [`26`](saidas/26-hardening-analise-inicial.txt) |
| Acesso ao SSH | O host alcança `10.10.10.1` e `10.20.20.1` diretamente pelas bridges, **sem publicar portas** | teste com `/dev/tcp` |

### 12.2 Procedimento (ordem real de execução)

1. **Backups** em [`hardening/backup/`](../../hardening/backup/): `Dockerfile`, `docker-compose.yml`, `sshd_config` original e `sshd -T` inicial. No contêiner antigo, também em `/root/backup-ssh`.
2. Geração de um par de chaves ED25519 **dedicado ao laboratório** no host (`~/.ssh/shozz_lab_ed25519`, impressão digital `SHA256:0dJzpy9uBimbUqnwJLu1SQ2j88lYB3HVJC7wYeF+MuQ`). Só a chave pública foi para o repositório.
3. **Etapa 1**, com a senha ainda habilitada: `10-shozz-hardening.conf` instalado com `PasswordAuthentication yes` e sem `AuthenticationMethods`; `sshd -t` OK; segunda instância do `sshd` na porta 2222, com a instância original mantida na 22 como acesso de reserva ([`17`](saidas/17-ssh-etapa1-validacao.txt)). Login por chave confirmado ([`18`](saidas/18-ssh-etapa1-chave-ok.txt)).
4. **Etapa 2**, só depois da chave validada: configuração final (`PasswordAuthentication no`, `AuthenticationMethods publickey`), `sshd -t` OK e `SIGHUP` só na instância de teste ([`19`](saidas/19-ssh-etapa2-validacao.txt)). Testes [`20`](saidas/20-ssh-teste-chave.txt) a [`25`](saidas/25-ssh-log-servidor.txt).
5. **Análise de hardening** ([`26`](saidas/26-hardening-analise-inicial.txt)).
6. **Decisões do responsável:** recriar só o roteador (autorizado); adiar `internal: true`; manter `ubuntu` no grupo `sudo` e o pacote `sudo`.
7. **Persistência:** novo `Dockerfile` (com `apt-get upgrade`, remoção das chaves de host da imagem, cópia dos arquivos de `hardening/` e permissões), `context: ..` no Compose e `.dockerignore`. `docker compose config --quiet` OK, `docker compose build ubuntu-router` OK; a imagem foi conferida sem chaves de host; `docker compose up -d --no-deps ubuntu-router`. Os clientes **não** foram recriados: mantêm o ID do contêiner e o horário de início 2026-11-23T18:45:5x Z ([`27`](saidas/27-final-estado-conteineres-redes.txt)).
8. **Testes finais** [`27`](saidas/27-final-estado-conteineres-redes.txt) a [`39`](saidas/39-final-hardening.txt).

### 12.3 Resultados da rede após a recriação do roteador

| Teste | Resultado | Comparação com a 1ª auditoria | Evidência |
|---|---|---|---|
| Redes e endereços | `shozz_lan` 10.10.10.0/24 gw .254, `shozz_wan` 10.20.20.0/24 gw .254; roteador .1/.1, clientes .10/.10; `internal=false`; sem portas publicadas | Igual | [`27`](saidas/27-final-estado-conteineres-redes.txt) |
| Interfaces do roteador | `eth0` 10.20.20.1 (WAN), `eth1` 10.10.10.1 (LAN) | Igual (veth `@if27`/`@if28`, antes `@if17`/`@if18`) | [`28`](saidas/28-final-interfaces-rotas-forward.txt) |
| Rotas (3 contêineres) | Idênticas às da seção 5 | Igual | [`28`](saidas/28-final-interfaces-rotas-forward.txt) |
| `ip_forward` do roteador | `1` | Igual | [`28`](saidas/28-final-interfaces-rotas-forward.txt) |
| T1 LAN → roteador | 4/4, 0%, TTL 64, RTT médio 0,709 ms | Aprovado nas duas | [`29`](saidas/29-final-ping.txt) |
| T2 WAN → roteador | 4/4, 0%, TTL 64, RTT médio 0,168 ms | Aprovado nas duas | [`29`](saidas/29-final-ping.txt) |
| T3 LAN → WAN | 4/4, 0%, TTL 63, RTT médio 0,477 ms | Aprovado nas duas | [`29`](saidas/29-final-ping.txt) |
| T4 WAN → LAN | 4/4, 0%, TTL 63, RTT médio 0,209 ms | Aprovado nas duas | [`29`](saidas/29-final-ping.txt) |
| `ip route get` e traceroute | 1º salto `10.10.10.1` (LAN→WAN) e `10.20.20.1` (WAN→LAN) | Igual | [`30`](saidas/30-final-traceroute-route-get.txt) |
| `ForwDatagrams` | 28 → 48 (+20) com `ping -c 10` WAN→LAN | Antes: 44 → 64 (+20), LAN→WAN. Agora o sentido oposto também está comprovado | [`31`](saidas/31-final-contador-encaminhamento.txt) |

### 12.4 Resultados do SSH

| # | Teste | Instância de teste (23:58) | Configuração definitiva (00:09) |
|---|---|---|---|
| — | `sshd -t` | OK ([`17`](saidas/17-ssh-etapa1-validacao.txt), [`19`](saidas/19-ssh-etapa2-validacao.txt)) | OK ([`32`](saidas/32-final-ssh-configuracao-efetiva.txt)) |
| — | `sshd -T`: `port 2222`, `permitrootlogin no`, `allowusers ubuntu`, `authenticationmethods publickey`, `passwordauthentication no`, `kbdinteractiveauthentication no` | Confirmado ([`19`](saidas/19-ssh-etapa2-validacao.txt)) | Confirmado ([`32`](saidas/32-final-ssh-configuracao-efetiva.txt)) |
| — | Escuta (`ss -tlnp`) | 22 (PID 1, antiga) e 2222 (teste) | **Só 0.0.0.0:2222** ([`32`](saidas/32-final-ssh-configuracao-efetiva.txt)) |
| T-SSH1 | `ubuntu` com chave, pela LAN e pela WAN | Aprovado ([`18`](saidas/18-ssh-etapa1-chave-ok.txt), [`20`](saidas/20-ssh-teste-chave.txt)) | Aprovado ([`33`](saidas/33-final-ssh-chave.txt)) |
| T-SSH2 | Só senha/keyboard-interactive | Negado: servidor anuncia só `publickey` ([`21`](saidas/21-ssh-teste-senha-bloqueada.txt)) | Negado ([`34`](saidas/34-final-ssh-senha-bloqueada.txt)) |
| T-SSH3 | `root` com a chave | Negado; log `not listed in AllowUsers` ([`22`](saidas/22-ssh-teste-root-bloqueado.txt), [`25`](saidas/25-ssh-log-servidor.txt)) | Negado ([`35`](saidas/35-final-ssh-root-bloqueado.txt), [`38`](saidas/38-final-ssh-log-servidor.txt)) |
| T-SSH4 | Porta 22 | Ainda aberta (instância antiga, esperado) ([`23`](saidas/23-ssh-teste-porta-22-antiga.txt)) | `Connection refused` ([`36`](saidas/36-final-ssh-porta-22-fechada.txt)) |
| T-SSH5 | 2222 a partir dos clientes | Aberta ([`24`](saidas/24-ssh-porta-2222-a-partir-dos-clientes.txt)) | Aberta, inclusive roteada LAN→10.20.20.1 ([`37`](saidas/37-final-ssh-alcance-clientes.txt)) |
| — | Impressão digital do servidor | `bPDh5v…` (`root@buildkitsandbox`) | `ZDxX9l…` (`root@ubuntu-router`), igual à conferida via `docker exec` ([`32`](saidas/32-final-ssh-configuracao-efetiva.txt), [`33`](saidas/33-final-ssh-chave.txt)) |

Observações sobre os logs:

- As linhas `invalid protocol identifier` e `kex_exchange_identification: Connection closed by remote host` vêm dos testes de porta (`/dev/tcp`, `nc -z`, leitura do banner), que abrem a conexão TCP sem negociar o SSH. Não são falhas.
- No T-SSH2, a linha `Connection closed by authenticating user ubuntu ... [preauth]` mostra que o cliente desistiu porque o servidor não ofereceu nenhum método compatível. Nenhuma senha foi enviada.

### 12.5 Hardening do contêiner

Resultado ([`39`](saidas/39-final-hardening.txt)):

- **0** atualizações pendentes; os 4 pacotes listados no arquivo `26` estão nas versões novas;
- um único processo (`sshd`, PID 1);
- permissões corretas em `sshd_config`, `10-shozz-hardening.conf` (`600`), chaves de host privadas (`600`), `~ubuntu/.ssh` (`700`), `authorized_keys` (`600`), `/etc/shadow` e `/etc/gshadow` (`640 root:shadow`) e `/etc/sudoers` (`440`);
- só `root` com UID 0; `root` e `ubuntu` com senha bloqueada;
- `sudo -n true` como `ubuntu` → `a password is required`;
- administração como root disponível via `docker exec` (`uid=0`).

Os binários SUID foram mantidos (ver I-11).

**Escopo:** nada disso foi aplicado ao host Linux Mint.

### 12.6 Novas observações

| ID | Descrição | Situação |
|---|---|---|
| I-10 | As chaves de host do SSH estavam embutidas na imagem: todo contêiner criado a partir dela teria a mesma identidade. | **Corrigido**: removidas no build e geradas pelo `entrypoint.sh`. |
| I-11 | `ubuntu` nos grupos `sudo`/`adm`; SUID em `ssh-keysign`, `chfn`, `chsh` e outros. | **Mantido por decisão do responsável.** `sudo` é inutilizável sem senha. Remoção registrada como recomendação. |
| I-12 | O SSH aceita conexões vindas da LAN e da WAN. | Comportamento atual, documentado. Restrição por origem fica como recomendação ou tarefa de firewall (outro integrante). |
| I-13 | O rebuild deixou a imagem anterior do roteador sem tag (`<none>`). | Não foi apagada, conforme as regras. Pode ser removida manualmente com `docker image prune`, se desejado. |
| I-8 | Isolamento de saída (`internal: true`). | **Adiado** por decisão do responsável. A análise de impacto está no `shozz-infra-lab/README.md`, seção 8. |

### 12.7 Conclusão da segunda auditoria

Em 2026-11-24, às 00:08–00:09, com o roteador recriado a partir da imagem endurecida:

1. A infraestrutura de rede continua idêntica e funcional. Os quatro testes de conectividade passaram com 0% de perda, e o encaminhamento pelo roteador foi comprovado nos dois sentidos.
2. O SSH escuta **somente na porta 2222**, aceita **somente chave pública**, **somente do usuário `ubuntu`**, e recusa `root` e senha. Isso foi comprovado com testes reais de autenticação e com o log do servidor.
3. A senha só foi desativada **depois** de comprovado o login por chave, e o servidor nunca ficou sem forma de administração (porta 22 de reserva durante os testes e `docker exec` sempre disponível).
4. O hardening foi aplicado **no contêiner**, e o host não foi alterado.
5. Continuam pendentes: o isolamento de saída (I-8) e as recomendações de menor privilégio (I-11).
