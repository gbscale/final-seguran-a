# Ameaças à operação de um provedor de Internet

**Grupo 10 · Segurança da Informação · contribuição do Integrante 3**

Um provedor precisa manter o acesso dos assinantes à Internet e proteger os equipamentos que administram esse acesso. Este relatório analisa dois vetores que atingem objetivos diferentes. O DDoS por reflexão e amplificação afeta a disponibilidade. A exploração de um equipamento de borda pode conceder acesso inicial e comprometer também a integridade e a confidencialidade. A discussão é teórica. A validação prática do grupo ficou nos contêineres autorizados do laboratório.

## 1. DDoS por reflexão e amplificação

Na reflexão, serviços de terceiros são induzidos a enviar respostas para a vítima. A falsificação do endereço de origem faz essas respostas seguirem para o alvo. Quando a resposta é maior que o pedido, existe também amplificação. O tráfego somado pode saturar a capacidade do destino, mesmo que os serviços do provedor estejam funcionando normalmente. [CERT.br/NIC.br — Recomendações para redução de DDoS](https://bcp.nic.br/ddos) · [NIC.br — Antispoofing](https://www.bcp.nic.br/antispoofing)

**Impacto no ISP.** A saturação de um enlace pode aumentar perda e latência, tornar serviços dos assinantes inalcançáveis e afetar o atendimento. Também há risco de equipamentos ou serviços do próprio provedor participarem como refletores, causando dano a terceiros. Esses são impactos esperados pela arquitetura, sem estimativa de frequência para o laboratório. [CERT.br/NIC.br — Impactos e medidas para provedores](https://bcp.nic.br/ddos)

**Prevenção em produção.** Valide endereços de origem na borda conforme as boas práticas BCP 38 e BCP 84, restrinja DNS recursivo a clientes autorizados e mantenha equipamentos de acesso atualizados e com serviços desnecessários desabilitados. Para proteger o enlace, estabeleça capacidade de mitigação a montante com o fornecedor de trânsito, monitore desvios de volume e perda e tenha um procedimento de contato e escalonamento. [NIC.br — Antispoofing](https://www.bcp.nic.br/antispoofing) · [CERT.br/NIC.br — Prevenção e mitigação](https://bcp.nic.br/ddos)

**Controle do laboratório.** O firewall de Victor valida a origem por interface, restringe as portas acessíveis e limita novos SYN de SSH e pedidos de ping no roteador. Os testes usaram tráfego pequeno para comprovar a decisão local. Uma saturação anterior ao roteador e a mitigação a montante ficaram fora da demonstração. [Regras e evidências do firewall](../firewall/README.md)

## 2. Exploração de equipamento de borda exposto

Serviços de administração, VPNs, firewalls e equipamentos de acesso ligam redes que têm níveis de confiança diferentes. Uma falha num serviço de borda alcançável pode permitir acesso inicial com os privilégios desse serviço. O resumo público do *CrowdStrike 2026 Global Threat Report* informa que 40% das vulnerabilidades exploradas por atores ligados à China no recorte analisado tinham como alvo equipamentos de borda expostos à Internet. O número descreve o conjunto observado pela CrowdStrike, sem medir a incidência entre provedores brasileiros. O CERT.br também lista sistemas de borda expostos como vetor de acesso inicial em incidentes de ransomware. [CrowdStrike — Resumo executivo do Global Threat Report 2026](https://www.crowdstrike.com/en-us/resources/reports/global-threat-report-executive-summary-2026/) · [CrowdStrike — Divulgação oficial do relatório](https://www.crowdstrike.com/en-us/press-releases/2026-crowdstrike-global-threat-report/) · [CERT.br — Acesso inicial em ransomware](https://www.cartilha.cert.br/docs/ransomware/entender/)

**Impacto no ISP.** A partir de um acesso de borda, um invasor pode tentar alterar regras e contas, interromper o acesso ou alcançar painéis e dados de assinantes. O impacto depende do privilégio obtido e do isolamento entre administração, operação e sistemas de negócio. Esses são cenários de risco para um ISP, inferidos do papel dos equipamentos. [CrowdStrike — Visão geral pública do relatório 2026](https://www.crowdstrike.com/en-us/global-threat-report/)

**Prevenção em produção.** Inventarie os equipamentos expostos e seus responsáveis. Restrinja a gerência a uma rede dedicada com autenticação forte, priorize patches que corrigem exposição crítica, elimine interfaces administrativas pela Internet e monitore alterações, logins e tráfego incomum. Mantenha backups verificados e uma rota de recuperação fora da rede potencialmente comprometida. [CrowdStrike — Visão geral pública e recomendações do relatório](https://www.crowdstrike.com/en-us/global-threat-report/) · [CERT.br — Como acontece o ransomware](https://www.cartilha.cert.br/docs/ransomware/entender/)

**Controle do laboratório.** Gabriel limitou o SSH a chave pública e configurou o serviço na porta 2222. O firewall restringiu o alcance da porta à LAN autorizada. O monitor de Igor detecta mudanças nas contas e na tabela IPv4 `filter` em relação a uma referência aprovada. A demonstração GPG verifica identidade e integridade em uma troca fictícia de configuração. Esses controles reduzem exposição e ajudam a detectar alterações. A validação não incluiu exploração de falhas, resposta automatizada ou comprometimento do host. [Hardening](../shozz-infra-lab/README.md) · [Monitor](../integridade/README.md) · [GPG](../criptografia/README.md)

## Escopo das fontes

Consulta realizada em 24/11/2026 no horário de São Paulo. Para a CrowdStrike, foram usados a página pública do relatório, o resumo executivo público e o comunicado oficial. O PDF integral não foi consultado. Os controles propostos para produção são recomendações para o cenário de um ISP. Os resultados práticos ficam nas evidências de cada módulo.
