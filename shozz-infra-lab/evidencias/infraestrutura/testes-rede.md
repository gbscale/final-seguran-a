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
| I-2 | O Dockerfile declara `EXPOSE 2222`, mas o `sshd` escuta na porta **22** (`ss -tlnp` e `sshd -T`). O `docker ps` mostra `2222/tcp`, o que leva a erro de interpretação. O `EXPOSE` é só metadado e nenhuma porta está publicada no host. | Documental / SSH | Será resolvido na etapa de SSH seguro, ao configurar `Port 2222` no `sshd_config`. Veja [`15-estado-ssh-atual.txt`](saidas/15-estado-ssh-atual.txt). |
| I-3 | O SSH do roteador ainda usa os padrões da distribuição: `port 22`, `permitrootlogin without-password`, `passwordauthentication yes`, e não há `AllowUsers`. | Segurança (etapa pendente) | Será tratado na etapa de hardening. **Ainda não está concluído.** |
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
