
# Projeto Final - Segurança da Informação

## Grupo 10 - Telecomunicações e Provedores de Internet (ISP)

**Disciplina:** Segurança da Informação  
**Curso:** Sistemas de Informação  
**Instituição:** IF Goiano - Campus Ceres  
**Prazo:** 26/11/2026

## 1. Sobre o projeto

Este projeto tem como objetivo simular e proteger a infraestrutura de rede de um provedor de internet fictício.

A solução será desenvolvida utilizando Linux Ubuntu Server e ferramentas de segurança para proteger a comunicação entre redes, controlar acessos e identificar alterações não autorizadas em arquivos importantes.

O trabalho será dividido em três módulos.

## 2. Módulos do projeto

### Módulo 1 - Fundamentos e Segurança

- Identificar duas ameaças ao setor de telecomunicações.
- Propor medidas de prevenção.
- Elaborar uma Política de Segurança da Informação (PSI).

### Módulo 2 - Redes, Firewall e Hardening

- Configurar redes LAN e WAN.
- Implementar roteamento estático.
- Desenvolver regras de firewall com iptables.
- Aplicar políticas DROP nas cadeias INPUT e FORWARD.
- Implementar proteção contra varredura de portas e ataques DoS.
- Configurar o SSH com autenticação por chave.
- Aplicar medidas de hardening no Ubuntu Server.

### Módulo 3 - Criptografia e Integridade

- Gerar e utilizar chaves GPG.
- Demonstrar troca de arquivos criptografados.
- Desenvolver um script de verificação SHA-256.
- Registrar alterações não autorizadas em arquivos críticos.

## 3. Tecnologias previstas

- Ubuntu Server
- Linux
- Shell Script / Bash
- iptables
- OpenSSH
- GPG
- SHA-256
- Nmap
- Git e GitHub

## 4. Estrutura do projeto

- infraestrutura/ - Configuração de redes e roteamento.
- firewall/ - Regras de filtragem de pacotes.
- hardening/ - Proteção do sistema e SSH.
- criptografia/ - Chaves GPG e demonstrações.
- integridade/ - Scripts de verificação SHA-256.
- documentacao/ - Relatórios, diagramas e PSI.
- evidencias/ - Capturas de tela e logs dos testes.

## 5. Organização da equipe

O projeto será desenvolvido por três integrantes.

- Integrante 1: Infraestrutura, redes e SSH.
- Integrante 2: Firewall e testes de segurança.
- Integrante 3: Criptografia, integridade e documentação.

Todos os integrantes participarão da integração, dos testes e da apresentação final.

## 6. Testes planejados

- Testar o acesso às portas autorizadas.
- Verificar bloqueios do firewall utilizando Nmap.
- Validar as restrições de acesso SSH.
- Demonstrar a criptografia e descriptografia GPG.
- Verificar a detecção de alterações utilizando SHA-256.

## 7. Status do projeto

Em desenvolvimento.

As configurações, os scripts funcionais, as instruções de execução e os resultados dos testes serão documentados conforme a implementação.

## 8. Observações de segurança

O ambiente será utilizado exclusivamente para fins acadêmicos e testes autorizados.

Senhas, tokens e chaves privadas não devem ser publicados no repositório.
