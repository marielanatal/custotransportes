# Registro de Decisões

Toda decisão de arquitetura deste projeto, com a alternativa que foi descartada e o
motivo do descarte.

O *porquê* detalhado de cada escolha de modelagem vive em `modelo-canonico.md`. Este
documento guarda o que aquele não guarda: **a data, o que foi rejeitado, e por quê.**
Serve para não reabrir a mesma discussão daqui a seis meses sem lembrar que ela já
aconteceu.

Formato: identificador, data, decisão, alternativas consideradas, motivo. Decisão
revista não é apagada — ganha uma linha de status apontando para a que a substituiu.

---

## 2026-08-31 — Sessão de definição do modelo canônico

### D-001 — Schema em português, código Python em inglês

**Decisão.** Tabelas, colunas, views e arquivos `.sql` em português sem acento,
`snake_case`, singular. Funções, variáveis, módulos e classes em Python, em inglês.

**Alternativas.** (a) Tudo em inglês, como o CLAUDE.md dizia originalmente.
(b) Tudo em português.

**Motivo.** O catálogo de regras é a fonte da verdade do domínio e já fixou os nomes
das entidades em português. Os termos não traduzem limpo — "documento de frete" é um
objeto fiscal brasileiro, não um `freight_document`. Traduzir criaria ambiguidade
justamente sobre o vocabulário usado na venda. O CLAUDE.md foi corrigido nesta sessão
para refletir a regra em três linhas em vez de uma.

---

### D-002 — `tenant_id` como slug de texto, não UUID

**Decisão.** `tenant_id TEXT`, slug legível (`transp_alfa`), chave primária de `tenant`.

**Alternativas.** `UUID`, que é o padrão da indústria para identificador de tenant.

**Motivo.** Vamos passar muito tempo lendo resultado de consulta na mão durante o
desenvolvimento e o diagnóstico. `WHERE tenant_id = 'transp_alfa'` é legível; um UUID
exige um join só para descobrir de quem é a linha.

**Custo aceito.** O slug passa a ser imutável na prática — renomear tenant vira
migração de dado. Aceitável para um produto vendido a dezenas de clientes, não a
milhares.

---

### D-003 — Chave estrangeira composta com `tenant_id`

**Decisão.** Toda FK entre tabelas operacionais inclui o tenant:
`FOREIGN KEY (tenant_id, unidade_id) REFERENCES unidade (tenant_id, id)`.

**Alternativas.** FK simples por `id`, com o isolamento garantido apenas pelo `WHERE`
das consultas.

**Motivo.** Torna impossível, em nível de banco, o pior defeito de um produto
multiempresa: uma viagem da empresa A apontando para uma unidade da empresa B. Confiar
no `WHERE` é confiar em disciplina humana em cada consulta escrita, para sempre.

**Custo aceito.** DDL verboso e índices compostos maiores.

---

### D-004 — `NULL` significa "não informado", e nenhuma coluna consumida por regra tem `DEFAULT`

**Decisão.** Campo não informado pela origem entra como `NULL`. Nunca `0`, string
vazia, data sentinela ou default "razoável".

**Alternativas.** Preencher ausência com valor neutro, que simplificaria as consultas
das regras ao eliminar tratamento de nulo.

**Motivo.** É o princípio que sustenta o `NAO_APURAVEL`. Zero preenchido é
indistinguível de zero verdadeiro, e a diferença entre os dois é a diferença entre
"esta base não teve avaria" e "esta base não nos manda o dado de avaria". Número
errado com aparência de certo é o defeito que o catálogo proíbe explicitamente.

---

### D-005 — Dado derivado declara a própria procedência

**Decisão.** Quando o adaptador calcula um campo em vez de recebê-lo, o canônico
guarda o valor e uma coluna `*_procedencia` com `informado` ou `derivado`. Aplicado
hoje a `viagem.peso_taxado_kg` e a `rota_id`.

**Alternativas.** Gravar só o valor calculado, tratando derivação como detalhe da
ingestão.

**Motivo.** Sem isso não se distingue "a transportadora controla peso taxado" de "nós
inventamos peso taxado a partir de um fator médio". Só o primeiro sustenta um número
em reunião com o dono.

---

### D-006 — Parâmetro de calibração é versionado por vigência; recalibrar nunca é `UPDATE`

**Decisão.** Recalibrar fecha a vigência da linha anterior e insere uma nova.
`parametro_calibracao` guarda ainda `procedencia` (`calibrado` / `manual` / `padrao`)
e `amostras`.

**Alternativas.** Sobrescrever o valor vigente, mantendo uma linha por chave e escopo.

**Motivo.** Um achado apresentado em março precisa ser reproduzível em julho. "Não
consigo reproduzir o número que te mostrei" encerra a confiança no produto. O campo
`procedencia` existe para que achado gerado sob parâmetro ainda não calibrado saia com
ressalva em vez de sair como fato.

---

### D-007 — O fallback de escopo é resolvido em um objeto único do canônico

**Decisão.** A resolução `unidade + perfil` → `perfil` → `global` vive numa view ou
função em `src/canonico/`. Nenhuma regra reimplementa o fallback.

**Alternativas.** Cada regra resolve o próprio fallback na consulta.

**Motivo.** Fallback duplicado diverge, e a divergência só aparece em reunião com
cliente. Efeito colateral bom: o corte por volume mínimo de amostras vira
responsabilidade de quem grava o parâmetro — o calibrador não insere linha de escopo
específico sem amostras suficientes, e a consulta cai sozinha no nível seguinte.

---

### D-008 — Parâmetro que é lista vai para tabela filha, não `JSONB`

**Decisão.** `parametro_calibracao_item`, uma linha por item.

**Alternativas.** Coluna `JSONB` em `parametro_calibracao`.

**Motivo.** Essas listas — motivos de liberação aceitos, composição do custo de
transferência — são consultadas com `JOIN` o tempo todo. `JOIN` é mais simples de
escrever e de depurar do que operador de JSON, e não introduz um tipo novo na stack
sem necessidade.

---

### D-009 — Dedução de fatura é linha discriminada, não campo agregado

**Decisão.** Tabela `fatura_deducao`, com `documento_frete_id` e `ocorrencia_id`
nuláveis. Extensão ao catálogo, que só previa `fatura` com deduções somadas.

**Alternativas.** Manter apenas `fatura.valor_deducoes`.

**Motivo.** R-005(b) é apontada pelo catálogo como provavelmente o maior valor do
produto. Com dedução agregada ela seria inapurável **por construção do nosso modelo**,
não por falha do cliente. Os dois nulos são o achado, não a lacuna: sem documento é
desconto que não dá para conciliar; sem ocorrência é dedução sem sinistro aberto, que
é metade do sinal da regra.

---

### D-010 — Capacidade existe em `veiculo` e em `perfil_veiculo`, com precedência

**Decisão.** Capacidade do veículo quando informada, capacidade do perfil como
fallback.

**Alternativas.** Capacidade só no veículo, ou só no perfil.

**Motivo.** O pré-requisito de R-001 é justamente detectar cadastro de capacidade
furado. Com uma coluna só não existe contra o que comparar, e a verificação vira
impossível.

---

### D-011 — `evento_autorizacao` referencia o objeto de forma genérica, sem FK

**Decisão.** `objeto_tipo` + `objeto_id`, sem chave estrangeira.

**Alternativas.** Coluna `viagem_id` com FK — hoje R-002 só audita liberação de viagem.

**Motivo.** Trava sobre despesa e sobre fatura é extensão previsível deste produto, e
migrar depois custa mais do que a integridade referencial de que se abre mão agora.
Mitigação por validação no adaptador.

**Status.** É a decisão mais frágil desta sessão e a mais fácil de reverter. Se até a
implementação de R-002 nada além de viagem precisar de trava, vale voltar para
`viagem_id`.

---

### D-012 — Nenhum dado pessoal no modelo canônico

**Decisão.** Sem CPF, CNH, ou qualquer documento de pessoa física. `motorista.codigo`
e `evento_autorizacao.usuario_codigo` são identificadores opacos. Nome de motorista é
opcional; nome de usuário do sistema de origem não é modelado.

**Alternativas.** Modelar documento do motorista, que facilitaria deduplicação de
cadastro na ingestão.

**Motivo.** Nenhuma regra do catálogo precisa. R-004 exige reconciliar dois caminhos de
pagamento pelo mesmo motorista, e um código estável faz isso. O que não entra no modelo
não vaza. Deduplicação de cadastro duplicado passa a ser trabalho do adaptador.

---

### D-013 — Nove entidades acrescentadas ao catálogo

**Decisão.** Além das nove do catálogo, o canônico define: `cliente`, `motorista`,
`perfil_veiculo`, `apolice`, `rota`, `categoria_despesa`, `tipo_ocorrencia`,
`carga_ingestao` e `responsavel`.

**Alternativas.** Manter as nove originais e resolver as lacunas dentro das regras.

**Motivo.** Cada uma fecha uma dependência concreta: `cliente` e `motorista` são
citados pelo catálogo mas não estavam na lista; `apolice` porque R-005(a) calibra prazo
por apólice; `rota` porque R-001 calcula frete médio por kg da rota; `categoria_despesa`
com flags booleanas porque é o que transforma os pré-requisitos de R-006 e R-007 em
consulta em vez de opinião; `carga_ingestao` porque sem cobertura declarada metade das
verificações de pré-requisito vira chute; `responsavel` porque o campo **Dono** de cada
regra é dado que muda, não constante.

---

### D-014 — Documentação em `Docs/`, com o CLAUDE.md alinhado ao disco

**Decisão.** Manter `Docs/` com maiúscula e corrigir as referências do CLAUDE.md, que
apontavam para caminhos e nomes de arquivo inexistentes.

**Alternativas.** Renomear para `docs/` minúsculo, que é a convenção mais comum e a que
não quebra em sistema de arquivos sensível a maiúscula.

**Motivo.** Correção de texto é mais barata que renomeação, e o repositório não tinha
histórico a arrastar no momento da decisão.

**Status.** Em aberto. Se o projeto for rodar em Linux ou CI, vale reverter para
minúsculo — e agora com git, o rename fica rastreável.

---

### D-015 — Ordem de construção: DDL completo, gerador mínimo, R-004 de ponta a ponta

**Decisão.** Escrever o DDL das 21 tabelas de uma vez, mas o gerador sintético apenas
com o que R-004 precisa, com caso de duplicidade plantado, e implementar R-004 em
seguida.

**Alternativas.** (a) DDL fatiado por regra. (b) Gerador completo antes da primeira
regra.

**Motivo.** DDL parcial deixa chave estrangeira pendurada e a tradução do modelo é
mecânica — não há o que aprender fatiando. Gerador completo, ao contrário, é esforço
grande apoiado num modelo que **ainda não foi testado contra nenhuma regra**. R-004 é a
que o catálogo indica para abrir o piloto: menor dependência de dado e resultado
indiscutível. É ela que valida o modelo, e descobrir um erro de modelagem com uma regra
pronta é muito mais barato do que com sete.
