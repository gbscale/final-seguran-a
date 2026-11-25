# GPG para troca de configuração entre administradores

Alice e Bruno são operadores fictícios do ISP. Alice precisa enviar uma configuração a Bruno com confidencialidade e com uma assinatura verificável. A demonstração usa [dados fictícios](exemplos/config-isp-demo.ini), domínios `.invalid` e chaveiros separados.

## Pré-requisitos e execução

Use Linux ou Ubuntu no WSL, com Bash 4.3 ou posterior, GnuPG compatível com Ed25519 e Curve25519, `gpgconf`, `awk` e os utilitários GNU. O teste registrado usou GnuPG 2.4.8. No Ubuntu, o pacote `gnupg` fornece os comandos se estiverem ausentes. Rode os comandos Bash na raiz do repositório.

```bash
gpg --version
mkdir -p criptografia/saida
rodada=$(mktemp -d criptografia/saida/rodada.XXXXXXXX)
set -o pipefail
bash criptografia/demo-gpg.sh "$rodada/exportacoes" 2>&1 | tee "$rodada/execucao.txt"
```

O argumento da demonstração precisa apontar para um diretório novo. `criptografia/saida/` é ignorado pelo Git. O script gera dois pares de chaves primárias Ed25519 para certificação e assinatura e acrescenta uma subchave `cv25519` de criptografia a cada identidade. As chaves expiram em 30 dias. Os chaveiros ficam em `/tmp` no Linux, com modo `0700`. A senha vazia e o modo não interativo só servem a essas chaves descartáveis. Na saída, o script encerra os agentes isolados e remove os chaveiros, inclusive as chaves privadas e os certificados de revogação gerados pelo GnuPG. Se o processo for encerrado abruptamente com um sinal que não possa ser tratado, o Linux pode manter os temporários até sua remoção.

## O que a demonstração verifica

1. Cada administrador lê o fingerprint no próprio chaveiro. Antes da importação, o script exige exatamente uma chave pública primária com o fingerprint esperado. Suas subchaves podem acompanhar a chave primária. Arquivos com outra chave primária, fingerprint divergente ou registros de chave secreta são recusados. Isso simula a conferência por um canal independente. Em produção, confirme o valor por exemplo em uma conversa autenticada com o titular.
2. Alice certifica a chave pública de Bruno, e Bruno certifica a de Alice. O script exporta as duas chaves com as certificações. Um terceiro chaveiro, que só recebe as chaves públicas, confirma que as assinaturas de certificação são válidas para os signatários esperados.
3. Alice assina a configuração com sua chave privada e cifra o conteúdo assinado para a chave pública de Bruno. A assinatura da mensagem viaja dentro do cifrado. A transferência é uma cópia local entre diretórios que representam os operadores. Uma assinatura separada do arquivo fictício é gerada para permitir a auditoria pública desta demonstração.
4. Bruno usa sua chave privada para recuperar o arquivo e a chave pública de Alice para verificar a assinatura. O script exige `VALIDSIG` com o fingerprint esperado. `cmp` compara os bytes e `sha256sum` mostra os dois hashes iguais.
5. Alice tenta abrir o arquivo cifrado para Bruno e recebe `NO_SECKEY`. Bruno tenta verificar a assinatura sobre uma cópia alterada e recebe `BADSIG`. Esses resultados são esperados e são verificados pelo script.
6. A regressão tenta importar um arquivo com a chave certa seguida de outra chave pública e um segundo arquivo com fingerprint incorreto. As duas tentativas são recusadas e o chaveiro de auditoria permanece vazio até as importações válidas.

| Conceito | O que faz neste exercício |
| --- | --- |
| Chave pública | Pode ser compartilhada. A pública de Bruno é usada para cifrar para ele, e a pública de Alice é usada para verificar a assinatura dela. |
| Chave privada | Fica com o titular. Bruno a usa para decifrar e Alice usa a dela para assinar. |
| Fingerprint | Identifica a chave. Um nome ou e-mail sozinho não prova que a chave pertence a alguém. |
| Certificação de chave | Associa a identidade publicada à chave pública com uma assinatura feita por quem conferiu essa associação. |
| Assinatura de arquivo | Permite verificar a autoria em relação a uma chave confiável e se o arquivo foi modificado. |
| Criptografia | Protege a leitura do conteúdo. O OpenPGP cifra o conteúdo com uma chave de sessão e protege essa chave para o destinatário. |

Na importação do primeiro arquivo no chaveiro público, o GnuPG pode informar que ainda falta a chave do signatário. O script verifica a certificação depois que as duas chaves foram importadas. A validade criptográfica e a confiança que um operador atribui à identidade são decisões distintas. [Manual GnuPG — gerenciamento e assinatura de chaves](https://gnupg.org/documentation/manuals/gnupg/OpenPGP-Key-Management.html)

## Evidências e verificação da assinatura publicada

O [registro da execução](../evidencias/criptografia/01-gpg.txt) contém comandos, fingerprints, certificações verificadas, sucesso da recuperação e os dois testes negativos. O diretório de [exportações](../evidencias/criptografia/exportacoes/) contém exatamente as duas chaves públicas, a assinatura separada e o arquivo cifrado. Com a chave privada descartada, o cifrado publicado serve de evidência. Execute uma rodada nova para demonstrar a descriptografia novamente.

Enquanto a assinatura publicada estiver verificável com a chave, é possível conferi-la contra o arquivo fictício usando só a chave pública. Execute em um Bash a partir da raiz.

```bash
auditoria=$(mktemp -d /tmp/isp-gpg-auditoria.XXXXXXXX)
gpg --no-options --homedir "$auditoria" --import evidencias/criptografia/exportacoes/alice-publica.asc
gpg --no-options --homedir "$auditoria" --verify \
  evidencias/criptografia/exportacoes/config-isp-demo.sig.asc \
  criptografia/exemplos/config-isp-demo.ini
```

Confira o fingerprint completo mostrado com o do registro. O diretório desse exemplo contém apenas a chave pública e metadados locais. A suíte cria chaves e fingerprints diferentes em cada nova rodada. Os arquivos de texto do módulo usam `LF` para que o checkout no Windows preserve os bytes assinados.
