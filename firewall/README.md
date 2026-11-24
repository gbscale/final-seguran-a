# Firewall do Grupo 10 — Telecomunicações e ISP

O firewall filtra o tráfego IPv4 no roteador do laboratório Shozz. Ele restringe a administração por SSH à LAN, permite um fluxo de diagnóstico de LAN para WAN e bloqueia novas conexões que a política não autoriza. O laboratório usa o firewall para demonstrar a separação entre segmentos de rede de um provedor.

## Topologia e política

| Equipamento | Endereço | Papel |
| --- | --- | --- |
| Cliente LAN | `10.10.10.10` | Origem do SSH administrativo e dos pings de diagnóstico |
| Roteador, interface LAN | `10.10.10.1` | Destino do SSH em `2222/tcp` e do ping local |
| Gateway da bridge LAN | `10.10.10.254` | Segunda origem autorizada para o SSH, usada na administração do host Linux |
| Roteador, interface WAN | `10.20.20.1` | Próximo salto do cliente WAN para chegar à LAN |
| Cliente WAN | `10.20.20.10` | Destino do ping encaminhado pela LAN |

O Docker Compose mantém as bridges, os endereços fixos e as rotas estáticas do Gabriel. O cliente LAN encaminha `10.20.20.0/24` para `10.10.10.1` e o cliente WAN encaminha `10.10.10.0/24` para `10.20.20.1`. O `net.ipv4.ip_forward=1` habilita o encaminhamento no roteador. O script descobre as duas interfaces pelos endereços IPv4 atribuídos, pois `eth0` e `eth1` podem trocar de papel. A capacidade `NET_ADMIN` já declarada no roteador permite aplicar as regras no seu namespace de rede.

| Regra ou cadeia | Função |
| --- | --- |
| `INPUT DROP` | Política padrão de descarte para pacotes com destino ao roteador. |
| `FORWARD DROP` | Política padrão de descarte para pacotes que atravessam o roteador. |
| `OUTPUT ACCEPT` | Permite respostas e tráfego originado no próprio roteador. |
| `INPUT` com `-i lo` | Permite a comunicação local entre processos do roteador. |
| `INVALID` | Descarta pacotes que o conntrack não consegue classificar em `INPUT` e `FORWARD`. |
| Validação de origem por interface | Encaminha para descarte os pacotes que chegam pela LAN ou WAN com origem fora da sub-rede esperada naquela interface. |
| Salto de `INPUT` para `SHOZZ_SSH` | Faz todo pacote destinado a `2222/tcp` passar pela autorização SSH, inclusive conexões que já estavam abertas antes da aplicação. |
| `SHOZZ_SSH` | Exige interface LAN e destino `10.10.10.1`. Preserva sessões estabelecidas de `10.10.10.10` e `10.10.10.254` e envia somente novos SYN dessas origens para `SHOZZ_SSH_RATE`. Descarta as demais tentativas. |
| `SHOZZ_SSH_RATE` | Limita novos SYN por IP autorizado a `12/min`, com quatro créditos iniciais. O excesso é registrado com limite e descartado. |
| ICMP em `INPUT` | Permite `echo-request` do cliente LAN para `10.10.10.1`, com limite de `3/s` por origem e rajada de cinco. Descarta os outros pedidos de ping ao roteador. |
| ICMP em `FORWARD` | Permite `echo-request` de `10.10.10.10` para `10.20.20.10` na direção LAN → WAN, com limite separado de `3/s` e rajada de cinco. Descarta os demais pedidos de ping encaminhados. |
| `ESTABLISHED,RELATED` | Permite tráfego de retorno e mensagens relacionadas nos caminhos restantes. A checagem de SSH e de `echo-request` vem antes dessa regra, para manter as restrições também em sessões ou fluxos com estado. |
| `SHOZZ_INPUT_DENY` e `SHOZZ_FORWARD_DENY` | Cada cadeia registra até quatro ocorrências iniciais e repõe créditos à taxa de quatro por minuto. O `DROP` seguinte descarta todos os pacotes que chegam à cadeia, tenham sido registrados ou não. |

O OpenSSH valida a chave do usuário `ubuntu`, usa a porta `2222` e segue executando em primeiro plano pelo script do Gabriel. O firewall controla de quais endereços se consegue chegar a essa porta. Os dois controles se complementam.

## Instalação e inspeção

Execute no PowerShell a partir da raiz do repositório.

```powershell
Set-Location shozz-infra-lab/infraestrutura
docker compose config --quiet
docker compose build ubuntu-router
docker compose up -d --no-deps ubuntu-router
docker compose ps
docker compose logs --tail 20 ubuntu-router
docker compose exec -T ubuntu-router shozz-firewall status
docker compose exec -T ubuntu-router iptables -S
```

Em uma instalação inicial, suba também os clientes com `docker compose up -d`. Em uma instalação existente, o comando com `--no-deps` atualiza apenas o roteador e pode recriá-lo se a imagem mudou. A recriação interrompe as sessões desse contêiner e gera novas chaves de host SSH. Confira a nova impressão digital com `docker compose exec -T ubuntu-router ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub` antes de atualizar uma entrada de `known_hosts`.

O Dockerfile instala `iptables` na imagem do roteador e normaliza para `LF` as cópias dos scripts executados no Linux. O Compose usa `firewall/` como contexto adicional de build, o que requer Compose 2.17 ou posterior. O `.dockerignore` desse contexto só inclui `firewall.sh`. O firewall é aplicado na inicialização e, em seguida, o processo chama o [entrypoint original](../shozz-infra-lab/hardening/entrypoint.sh). [Documentação do Compose sobre contextos adicionais](https://docs.docker.com/reference/compose-file/build/#additional_contexts)

## Recuperação e reaplicação

Use o terminal do Docker para aplicar e recuperar as regras, inclusive se uma sessão SSH cair. Antes de trocar a tabela `filter`, o script gera um snapshot com `iptables-save`, confere se ele é restaurável e guarda o primeiro snapshot em `/run/shozz-firewall/filter-before.rules`. A troca usa `iptables-restore`. A validação acontece antes do `COMMIT` que instala as regras. Em caso de falha na instalação, o script tenta restaurar o snapshot imediatamente anterior à tentativa. O `flock` serializa as chamadas do próprio script.

```powershell
docker compose exec -T ubuntu-router shozz-firewall restore
docker compose exec -T ubuntu-router iptables -S
docker compose exec -T ubuntu-router shozz-firewall apply
docker compose exec -T ubuntu-router shozz-firewall status
```

`restore` recupera a tabela `filter` inteira que existia antes da primeira aplicação daquele contêiner. Faça esse teste em uma janela do laboratório, pois restaurar a política inicial pode tornar o SSH alcançável pela WAN simulada. `apply` reaplica o conjunto de regras e mantém o primeiro backup. O backup pertence ao contêiner e uma recriação faz um novo snapshot antes de instalar o firewall no novo namespace. Exporte o backup com `docker cp` antes de recriar o roteador se precisar consultar o estado anterior depois.

Se o firewall não conseguir iniciar, o Compose registra o erro no log e o processo do roteador para. Para diagnóstico, `SHOZZ_FIREWALL=off` é uma opção de recuperação temporária no Compose. No PowerShell, com a variável inicialmente ausente, use `$env:SHOZZ_FIREWALL = 'off'` e `docker compose up -d --no-deps ubuntu-router`. Ao concluir o diagnóstico, remova a variável com `Remove-Item Env:SHOZZ_FIREWALL` e execute novamente `docker compose up -d --no-deps ubuntu-router`. Ao mudar o ambiente, o Compose pode recriar o roteador. O estado padrão é `on`.

## Resultados dos testes

Medições de 24/11/2026 no Docker Desktop com Docker Engine 29.2.1, Compose v5.0.2, iptables 1.8.10 (`nf_tables`) e Nmap 7.97. As sondagens usaram apenas os clientes e os endereços do laboratório. Os arquivos de evidência mostram os comandos, as saídas e os códigos de retorno. Consulte também [os comandos de demonstração](GUIA_ESTUDO_FIREWALL.md#7-roteiro-oral-de-cinco-minutos).

| Verificação | Antes | Com o firewall ativo | Evidência |
| --- | --- | --- | --- |
| LAN → roteador LAN, `2222/tcp` | `open` | `open`. Login por chave retornou `ubuntu`. O arquivo `authorized_keys` foi restaurado com o mesmo hash após o teste. | [Antes](evidencias/01-antes.txt), [depois](evidencias/03-depois.txt), [login](evidencias/04-ssh-lan.txt) |
| WAN → roteador WAN, `2222/tcp` | `open` | `filtered`. A tentativa pela WAN ao IP administrativo `10.10.10.1` também ficou `filtered`. | [Antes](evidencias/01-antes.txt), [depois](evidencias/03-depois.txt) |
| LAN e WAN → roteador, `22/tcp` e `80/tcp` | `closed` | `filtered`. | [Antes](evidencias/01-antes.txt), [depois](evidencias/03-depois.txt) |
| WAN → cliente LAN, `8080/tcp` | `closed`, sem serviço na porta | `filtered`, com descartes também observados em `FORWARD`. | [Antes](evidencias/01-antes.txt), [depois](evidencias/03-depois.txt) |
| Ping de um cliente para o outro | Respondia nos dois sentidos | O ping iniciado na LAN recebeu 2/2 respostas. O ping iniciado na WAN recebeu 0/2. | [Antes](evidencias/01-antes.txt), [depois](evidencias/03-depois.txt) |
| Limite de novas conexões SSH | Sem o limite do script | Quatro das seis conexões TCP de teste passaram, duas foram filtradas, e a porta voltou a aceitar uma nova conexão após a espera de seis segundos. | [Limite SSH](evidencias/05-limite.txt) |
| Limite de pings IPv4 | Sem o limite do script | Dos sete pedidos por caminho, cinco receberam resposta e dois foram descartados. Os deltas bateram tanto em `INPUT` quanto em `FORWARD`. | [Limite ICMP](evidencias/08-icmp-revalidacao.txt) |
| Configuração efetiva do SSH | Arquivos originais do Gabriel | `2222/tcp`, `AllowUsers ubuntu`, autenticação por `publickey`, senha e acesso de root desabilitados. | [Hardening](evidencias/08-icmp-revalidacao.txt) |
| Recriação do roteador | Roteador anterior sem iptables | O novo contêiner aplicou `DROP` no boot e iniciou o SSH. Os IDs dos clientes e os hashes dos arquivos de configuração do SSH foram preservados. | [Integração](evidencias/02-integracao.txt) |
| Restauração, reaplicação e reinício | Snapshot com `INPUT ACCEPT` e `FORWARD ACCEPT` | A WAN voltou a alcançar a porta durante a restauração. Duas aplicações voltaram às mesmas regras `DROP`, com o backup intacto. Após o reinício, os três serviços ficaram `Up`, e a WAN voltou a ver a porta filtrada. | [Recuperação](evidencias/06-recuperacao.txt) |

O contador da política padrão pode ficar em zero mesmo quando há bloqueios. Os pacotes da demonstração chegaram às cadeias explícitas de descarte e incrementaram os contadores `DROP` dessas cadeias.

Na primeira coleta ICMP houve cinco respostas em sete pings, mas a validação dos contadores parou porque `iptables -L` não mostra o nome interno do `hashlimit`. A revalidação identificou a regra pelo padrão ICMP e conferiu os contadores nos dois caminhos. [Primeira coleta](evidencias/07-icmp-hardening.txt) · [Revalidação](evidencias/08-icmp-revalidacao.txt)

## Limitações

- O filtro cobre IPv4 no namespace do roteador. Ele só vê tráfego entregue ao roteador ou encaminhado por ele. Os clientes podem trocar tráfego na mesma bridge ou usar seus gateways Docker para outros destinos fora desse caminho. O projeto não usa as WAN e LAN simuladas para testar redes reais.
- O limite SSH conta pacotes SYN classificados como `NEW`, inclusive possíveis retransmissões. Ele não tem acesso ao conteúdo criptografado do SSH e não distingue tentativa de senha, chave rejeitada ou login válido. Um administrador também pode consumir todos os créditos temporariamente.
- O bloqueio de portas reduz a informação exposta a sondagens e o limite desestimula tentativas repetidas contra a porta permitida. Um IP permitido continua sujeito à autenticação por chave. A validação de sub-rede não comprova a identidade de máquinas da mesma LAN.
- Os limites reduzem a carga sobre serviços do laboratório. Um ataque volumétrico distribuído pode ocupar o enlace ou esgotar recursos antes de o filtro atuar. Uma rede real precisaria de mitigação a montante, além de monitoramento e capacidade compatível com o tráfego.
- Os descartes são verificáveis nos contadores do iptables. A entrega das mensagens do alvo `LOG` ao log de kernel depende do ambiente Docker e da configuração do host. O prefixo e o limite constam no filtro, mas `docker compose logs` acompanha o processo do contêiner.
- O firewall gerencia a tabela IPv4 `filter` deste roteador. Evite manter regras manuais concorrentes nela. Tráfego de retorno rastreado pode sobreviver à troca de regras enquanto durar a entrada no conntrack, com as exceções explícitas de SSH e pedidos de ICMP tratadas antes da regra geral de estado.

Referências de consulta sobre extensões de estado, limites e contadores. [Manual de extensões do iptables](https://ipset.netfilter.org/iptables-extensions.man.html) · [Estados de porta do Nmap](https://nmap.org/book/man-port-scanning-basics.html)
