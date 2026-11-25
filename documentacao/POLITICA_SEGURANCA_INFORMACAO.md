# Política de Segurança da Informação para o ISP

**Grupo 10 · Proposta de política para o relatório técnico**

Esta política orienta colaboradores, administradores e prestadores que acessam redes, sistemas, códigos, logs ou dados de assinantes do provedor. No laboratório, o tratamento fica restrito a dados fictícios e aos ativos autorizados. Em produção, a gestão aprova os responsáveis, acompanha exceções e revisa a política após incidentes ou mudanças relevantes.

## Controle de acesso

- Use contas individuais e conceda apenas o privilégio necessário para a função. Autorize acessos privilegiados por solicitação registrada, com responsável, escopo e prazo. Revogue acessos após desligamento, mudança de função ou encerramento do serviço.
- Separe a rede de gerência do tráfego de assinantes. Restrinja a origem das sessões administrativas, mantenha acesso por chave e confira a identidade do equipamento antes de conectar. Exija autenticação forte, incluindo MFA quando suportado, para painéis e acessos remotos de produção.
- Proteja as chaves privadas e tokens com um cofre aprovado ou dispositivo criptográfico quando aplicável. Compartilhe apenas chaves públicas e use um canal independente para conferir fingerprints. Revogue ou rotacione material de acesso em caso de suspeita de comprometimento.

## Auditoria e rastreabilidade

- Registre autenticações, mudanças privilegiadas, alterações de firewall, alertas de integridade e ações de recuperação. Preserve data e hora sincronizadas, alvo, resultado, identidade do operador e número do chamado quando houver. Restrinja a leitura e a alteração dos registros e centralize cópias fora do equipamento monitorado em produção.
- Abra um chamado antes de alterar regras ou contas em produção. Registre aprovação, verificação prévia, plano de reversão e resultado. Atualize a referência de integridade somente após conferir que a alteração foi autorizada e que o estado final corresponde ao aprovado. O `update --confirmar` do laboratório é uma ação explícita, com registro de hora e alvos.
- Analise alertas e falhas de coleta. Defina retenção com os responsáveis pelo tratamento de dados, conforme finalidade, contrato e requisitos aplicáveis. Evite incluir senhas, tokens, chaves privadas ou conteúdo de `/etc/shadow` em logs, tickets e evidências.

## Uso aceitável dos recursos

- Utilize rede, credenciais, equipamentos e sistemas do ISP para atividades autorizadas. Qualquer teste deve ter escopo, permissão e janela definidos. No laboratório, os testes ficam nos contêineres e amostras dedicados.
- Preserve os controles de acesso e auditoria. Acione o responsável por segurança se uma atividade legítima exigir exceção. Registre a justificativa, o prazo e os controles compensatórios.
- Use dados de exemplo e identidades fictícias em treinamentos, repositórios e apresentações. Envie configuração sensível por canal aprovado, com proteção criptográfica quando necessário.

## Proteção dos dados dos assinantes

- Colete e consulte somente os dados necessários à finalidade aprovada. Restrinja acesso a cadastros, dados de faturamento, informações de atendimento, históricos e logs pelo papel do colaborador.
- Criptografe dados em trânsito e proteja dados armazenados e backups conforme a classificação, com acesso separado às chaves. Revise permissões de cópias e descarte dados com segurança após o prazo aplicável. Use dados fictícios para teste, salvo autorização específica com salvaguardas adequadas.
- No Brasil, o responsável pelo tratamento avalia medidas técnicas e administrativas e obrigações de comunicação de incidentes conforme a LGPD e a regulamentação aplicável. [LGPD, arts. 46 a 48](https://planalto.gov.br/ccivil_03/_ato2015-2018/2018/lei/l13709compilado.htm) · [ANPD — Comunicação de Incidente de Segurança](https://www.gov.br/anpd/pt-br/canais_atendimento/agente-de-tratamento/comunicado-de-incidente-de-seguranca-cis)

## Papéis e responsabilidades

| Papel | Responsabilidade |
| --- | --- |
| Gestão do ISP | Aprovar a política, designar responsáveis, priorizar correções e autorizar exceções com prazo. |
| Operação de rede e administradores | Proteger credenciais, aplicar mudanças autorizadas, revisar regras e patches, preservar evidências e executar recuperação. |
| Segurança e resposta a incidentes | Fazer triagem, coordenar contenção, manter a linha do tempo e revisar controles após o incidente. |
| Controlador e encarregado de dados | Avaliar impactos aos titulares, orientar o tratamento de dados e coordenar comunicação quando exigida. |
| Usuários e prestadores | Seguir o escopo do acesso, guardar material de autenticação e reportar suspeitas prontamente. |

## Resposta a incidentes

1. **Registrar e classificar.** Anote horário com fuso, alerta, ativo, impacto e responsável. Abra chamado e avise a operação ou segurança. Uma divergência de SHA‑256 exige comparação com a mudança autorizada mais recente.
2. **Preservar e conter.** Preserve logs, configurações e evidências com acesso restrito. Isole o ativo ou revogue o acesso suspeito conforme o impacto. Para indisponibilidade de enlace, acione o fornecedor de trânsito e a equipe de mitigação.
3. **Corrigir e recuperar.** Elimine a causa, revise credenciais afetadas e restaure a configuração aprovada. Confirme funcionamento e integridade antes de dar o incidente por encerrado. Registre a autorização antes de atualizar a referência.
4. **Comunicar e aprender.** O controlador avalia possíveis riscos ou danos relevantes aos titulares e as comunicações aplicáveis. A equipe revisa a causa, as defesas e o plano de resposta, com tarefas atribuídas e prazos registrados. [ANPD — Regulamento de Comunicação de Incidente de Segurança](https://www.gov.br/anpd/pt-br/assuntos/noticias/anpd-aprova-o-regulamento-de-comunicacao-de-incidente-de-seguranca)
