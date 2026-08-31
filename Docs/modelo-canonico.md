# Modelo Canônico

**Versão 0.1 — rascunho de trabalho**

Este documento define o modelo de dados que as regras leem. É a contrapartida
técnica do `catalogo-regras-vazamento.md`: o catálogo diz *o que* detectar, este
diz *sobre qual estrutura*.

Duas fronteiras, e nenhuma delas é negociável:

- **Regra lê daqui e de mais nenhum lugar.** Nenhuma consulta de regra toca fonte
  externa, arquivo bruto ou tabela de sistema de origem. Se uma regra precisa de um
  campo que não existe aqui, o caminho é estender este documento — nunca ler por fora.
- **A adaptação acontece antes.** Traduzir qualquer fonte de entrada para estas
  tabelas é trabalho de `src/adaptadores/`. O canônico não sabe de onde o dado veio,
  só registra que veio.

---

## Sumário

1. [Princípios](#1-princípios)
2. [Convenções técnicas](#2-convenções-técnicas)
3. [Núcleo multiempresa](#3-núcleo-multiempresa)
4. [Calibração](#4-calibração)
5. [Dimensões](#5-dimensões)
6. [Fatos](#6-fatos)
7. [O que cada regra lê](#7-o-que-cada-regra-lê)
8. [Fora de escopo nesta versão](#8-fora-de-escopo-nesta-versão)

---

## 1. Princípios

### 1.1 `NULL` significa "não informado", e é sagrado

Este é o princípio que sustenta o produto inteiro.

Campo não informado pela origem entra como `NULL`. Nunca como `0`, nunca como
string vazia, nunca como data sentinela tipo `1900-01-01`, nunca como um default
"razoável".

O motivo é direto: a verificação de pré-requisito de cada regra é uma consulta
sobre presença de dado. Se o adaptador preenche buraco com zero, a regra roda, o
número sai, e o número está errado com aparência de certo — o pior defeito
possível neste produto. Zero preenchido é indistinguível de zero verdadeiro, e a
diferença entre os dois é a diferença entre "esta unidade não teve avaria" e "esta
unidade não nos manda o dado de avaria".

Corolário prático: nenhuma coluna de valor, peso ou data que uma regra consuma
pode ter `DEFAULT` no schema. `NOT NULL` só onde a ausência do dado torna a linha
inteira sem sentido — um lançamento de despesa sem valor não é um lançamento.

### 1.2 Dado derivado se declara como derivado

Quando o adaptador calcula um campo em vez de recebê-lo (peso taxado a partir de
cubagem, rota a partir de origem e destino), o canônico guarda o valor **e** a
procedência, numa coluna `*_procedencia` com dois estados: `informado` ou `derivado`.

Sem isso, uma regra não consegue distinguir "a transportadora controla peso taxado"
de "nós inventamos peso taxado a partir de um fator médio". A primeira sustenta um
número em reunião; a segunda não.

### 1.3 Parâmetro é dado, dono é dado

Nenhum limite, teto, janela ou percentual mora em código — todos vivem em
`parametro_calibracao`, por tenant, com vigência.

A mesma lógica vale para o campo **Dono** de cada regra do catálogo. "Supervisor da
base" não é uma constante: é uma pessoa diferente por unidade e por empresa, e
muda. Mora em `responsavel`.

### 1.4 Toda linha operacional carrega `tenant_id`

Sem exceção e sem "essa tabela é pequena, depois eu ajeito". Toda consulta filtra
por ele. A ausência de `tenant_id` numa cláusula `WHERE` de regra é defeito
crítico, não estilo.

### 1.5 Toda linha operacional carrega procedência

`origem_sistema` + `origem_id` + `carga_id`. Isso permite três coisas que você vai
precisar: reprocessar uma carga sem duplicar, rastrear um achado até a linha de
origem quando o cliente contestar, e medir cobertura de dado por período — que é
metade das verificações de pré-requisito.

`origem_sistema` é um rótulo livre definido pelo adaptador (`export_planilha`,
`extracao_banco`, `sintetico`). Não carrega nome de produto de terceiro.

---

## 2. Convenções técnicas

### 2.1 Nomenclatura

- Tabelas e colunas em **português, minúsculas, sem acento, `snake_case`**, singular
  (`documento_frete`, não `documentos_frete`). Casa com o catálogo, que é a fonte da
  verdade do domínio.
- Código Python em inglês. A fronteira entre os dois idiomas é a fronteira entre
  schema e aplicação.
- Nenhum nome de tabela, coluna, código ou constante de sistema de gestão de
  transporte comercial. Se uma lógica for descrita usando termo de sistema
  específico, a tradução para estes nomes acontece antes de qualquer implementação.

### 2.2 Bloco técnico

Toda tabela de **fato** e toda tabela de **dimensão** carrega estas colunas. Elas
não são repetidas nas definições abaixo:

| Coluna | Tipo | Nulo | Descrição |
|---|---|---|---|
| `id` | `BIGINT GENERATED ALWAYS AS IDENTITY` | não | Chave primária técnica |
| `tenant_id` | `TEXT` | não | `REFERENCES tenant(tenant_id)` |
| `origem_sistema` | `TEXT` | não | Rótulo do adaptador que produziu a linha |
| `origem_id` | `TEXT` | não | Identificador opaco na origem |
| `carga_id` | `BIGINT` | sim | `REFERENCES carga_ingestao (tenant_id, id)`, composta |
| `ingerido_em` | `TIMESTAMPTZ` | não | `DEFAULT now()` |

Restrição obrigatória em todas: `UNIQUE (tenant_id, origem_sistema, origem_id)`.
É ela que torna a reingestão idempotente.

Toda chave estrangeira entre tabelas operacionais é composta com o tenant:
`FOREIGN KEY (tenant_id, unidade_id) REFERENCES unidade (tenant_id, id)`. Verboso,
e impede em nível de banco o pior bug possível num produto multiempresa — uma
viagem da empresa A apontando para uma unidade da empresa B.

### 2.3 Tipos

| Natureza | Tipo | Observação |
|---|---|---|
| Dinheiro | `NUMERIC(14,2)` | Sempre BRL. Nunca `FLOAT`, nunca centavos em inteiro |
| Peso | `NUMERIC(12,3)` | Sempre kg |
| Volume | `NUMERIC(12,4)` | Sempre m³ |
| Percentual | `NUMERIC(7,4)` | Fração decimal: `0.70`, não `70` |
| Data de fato | `DATE` | Quando o dia é o que importa |
| Momento de sistema | `TIMESTAMPTZ` | Log, ingestão, autorização |
| Código de negócio | `TEXT` | Nunca inteiro, mesmo quando parece numérico |

Timestamps são gravados em UTC e lidos em `America/Sao_Paulo`. Unidade de medida é
fixa no canônico: conversão é trabalho do adaptador, e nenhuma tabela tem coluna
"unidade de medida".

### 2.4 Conjuntos fechados

Domínio fixado por nós (ex.: `vinculo` de veículo) vira `TEXT` com `CHECK`.
Domínio que varia por cliente (categoria de despesa, tipo de ocorrência) vira
tabela de dimensão por tenant. Sem `ENUM` do Postgres — alterar um custa migração
e não ganha nada aqui.

### 2.5 Cancelamento

Nada é apagado. Documento, cotação, viagem e despesa cancelados guardam
`cancelado_em` / `estornada_em`. As regras precisam enxergar o cancelamento — R-003
depende disso explicitamente: documento cancelado não conta como conversão.

---

## 3. Núcleo multiempresa

### `tenant`

A transportadora cliente. Única tabela sem `tenant_id` — ela é o tenant.

| Coluna | Tipo | Nulo | Descrição |
|---|---|---|---|
| `tenant_id` | `TEXT` | não | Chave primária. Slug legível: `transp_alfa` |
| `nome` | `TEXT` | não | Razão social ou nome de tratamento |
| `ativo` | `BOOLEAN` | não | `DEFAULT true` |
| `criado_em` | `TIMESTAMPTZ` | não | |

`tenant_id` é slug de texto e não UUID de propósito: você vai passar muito tempo
lendo resultado de consulta na mão, e `WHERE tenant_id = 'transp_alfa'` é legível
enquanto um UUID exige um join só para saber de quem é a linha. O custo é ter que
tratar slug como imutável — renomear tenant seria migração de dado.

### `carga_ingestao`

Um lote de ingestão. Sem esta tabela não existe verificação de cobertura, e sem
cobertura metade dos pré-requisitos vira chute.

| Coluna | Tipo | Nulo | Descrição |
|---|---|---|---|
| `id` | `BIGINT IDENTITY` | não | |
| `tenant_id` | `TEXT` | não | |
| `entidade` | `TEXT` | não | Tabela canônica alvo |
| `origem_sistema` | `TEXT` | não | |
| `periodo_inicio` | `DATE` | não | Início do período coberto pelo lote |
| `periodo_fim` | `DATE` | não | Fim do período coberto |
| `linhas_lidas` | `INTEGER` | sim | Lidas na origem |
| `linhas_aceitas` | `INTEGER` | sim | Gravadas no canônico |
| `linhas_rejeitadas` | `INTEGER` | sim | |
| `status` | `TEXT` | não | `CHECK IN ('em_andamento','concluida','falhou')` |
| `iniciado_em` | `TIMESTAMPTZ` | não | |
| `concluido_em` | `TIMESTAMPTZ` | sim | |

`periodo_inicio` / `periodo_fim` são declarados pelo adaptador, não inferidos do
dado. A diferença importa: um lote que declara cobrir janeiro e traz zero
ocorrências significa "janeiro sem avaria". Um lote que não declara período e traz
zero ocorrências não significa nada.

### `responsavel`

Quem trata o achado. Torna o campo **Dono** do catálogo um dado.

| Coluna | Tipo | Nulo | Descrição |
|---|---|---|---|
| *bloco técnico* | | | |
| `papel` | `TEXT` | não | `supervisor_base`, `gestor_unidade`, `financeiro`, `comercial`, `qualidade`, `planejamento`, `direcao` |
| `unidade_id` | `BIGINT` | sim | `NULL` = responsável corporativo, vale para todas |
| `nome` | `TEXT` | não | |
| `contato` | `TEXT` | sim | E-mail ou canal de tratativa |
| `vigencia_inicio` | `DATE` | não | |
| `vigencia_fim` | `DATE` | sim | `NULL` = vigente |

---

## 4. Calibração

### `parametro_calibracao`

Todo número calibrável do catálogo. Resolução em três níveis com fallback,
exatamente como o catálogo define: `unidade + perfil` → `perfil` → `global`.

| Coluna | Tipo | Nulo | Descrição |
|---|---|---|---|
| *bloco técnico* | | | |
| `chave` | `TEXT` | não | Namespaced por regra: `R001.ocupacao_minima` |
| `escopo` | `TEXT` | não | `CHECK IN ('unidade_perfil','perfil','global')` |
| `unidade_id` | `BIGINT` | sim | Obrigatório se escopo = `unidade_perfil` |
| `perfil_id` | `BIGINT` | sim | Obrigatório se escopo ≠ `global` |
| `valor_num` | `NUMERIC(18,6)` | sim | Para parâmetro numérico |
| `valor_texto` | `TEXT` | sim | Para parâmetro textual único |
| `procedencia` | `TEXT` | não | `CHECK IN ('calibrado','manual','padrao')` |
| `amostras` | `INTEGER` | sim | N observado na calibração |
| `calibrado_em` | `TIMESTAMPTZ` | sim | |
| `vigencia_inicio` | `DATE` | não | |
| `vigencia_fim` | `DATE` | sim | `NULL` = vigente |

Recalibrar **nunca é `UPDATE`**. Fecha-se a vigência anterior e insere-se linha
nova. Sem isso, um achado de março não pode ser reproduzido em julho, e "não
consigo reproduzir o número que te mostrei" é o fim da confiança.

`procedencia` distingue três situações que não podem ser confundidas: `calibrado`
(saiu da mediana observada, com `amostras` suficientes), `manual` (o cliente
definiu), `padrao` (nosso chute inicial, ainda não calibrado). Achado gerado sob
parâmetro `padrao` deve ser apresentado com essa ressalva.

Restrição: `CHECK (num_nonnulls(valor_num, valor_texto) = 1)` — exatamente um
preenchido.

### `parametro_calibracao_item`

Parâmetros que são lista, não escalar: motivos de liberação aceitos (R-002),
composição do custo de transferência (R-007), exceções legítimas de pagamento
(R-004).

| Coluna | Tipo | Nulo | Descrição |
|---|---|---|---|
| `id` | `BIGINT IDENTITY` | não | |
| `parametro_id` | `BIGINT` | não | `REFERENCES parametro_calibracao(id)` |
| `item` | `TEXT` | não | |

Lista em tabela em vez de `JSONB` de propósito: você consulta isso com `JOIN` todo
dia, e `JOIN` numa tabela é mais simples de escrever e de depurar do que operador
de JSON.

### Resolução do fallback

O padrão de consulta, escrito uma vez, para não ser reinventado torto em cada regra:

```sql
-- valor vigente de uma chave para (unidade, perfil), com fallback de escopo
SELECT DISTINCT ON (p.chave)
       p.chave, p.valor_num, p.procedencia, p.amostras
  FROM parametro_calibracao p
 WHERE p.tenant_id = :tenant_id
   AND p.chave     = :chave
   AND :data_ref BETWEEN p.vigencia_inicio
                     AND COALESCE(p.vigencia_fim, DATE '9999-12-31')
   AND (   (p.escopo = 'unidade_perfil' AND p.unidade_id = :unidade_id
                                        AND p.perfil_id  = :perfil_id)
        OR (p.escopo = 'perfil'         AND p.perfil_id  = :perfil_id)
        OR (p.escopo = 'global') )
 ORDER BY p.chave,
          CASE p.escopo WHEN 'unidade_perfil' THEN 1
                        WHEN 'perfil'         THEN 2
                        ELSE 3 END;
```

Este bloco vira uma view ou função em `src/canonico/` e **nenhuma regra reimplementa
o fallback na mão**. Fallback duplicado e divergente entre regras é o tipo de bug
que só aparece em reunião com cliente.

Nota: o catálogo diz que abaixo do volume mínimo de amostras (sugestão: 30) usa-se
o fallback. Isso é responsabilidade de quem **grava** o parâmetro, não de quem lê —
o calibrador simplesmente não insere linha de escopo `unidade_perfil` sem amostras
suficientes, e a consulta acima cai sozinha no nível seguinte.

---

## 5. Dimensões

### `unidade`

Base operacional. Unidade de calibração e de responsabilização.

| Coluna | Tipo | Nulo | Descrição |
|---|---|---|---|
| *bloco técnico* | | | |
| `codigo` | `TEXT` | não | Código de negócio. `UNIQUE (tenant_id, codigo)` |
| `nome` | `TEXT` | não | |
| `tipo` | `TEXT` | não | `CHECK IN ('matriz','filial','ponto_apoio')` |
| `cidade` | `TEXT` | sim | |
| `uf` | `TEXT` | sim | UF, `CHECK (~ '^[A-Z]{2}$')` |
| `ativo` | `BOOLEAN` | não | `DEFAULT true` |

### `perfil_veiculo`

Perfil de veículo. É a chave de calibração ao lado da unidade, e a referência de
capacidade contra a qual o cadastro do veículo é auditado.

| Coluna | Tipo | Nulo | Descrição |
|---|---|---|---|
| *bloco técnico* | | | |
| `codigo` | `TEXT` | não | `UNIQUE (tenant_id, codigo)` |
| `descricao` | `TEXT` | não | |
| `capacidade_peso_kg` | `NUMERIC(12,3)` | sim | Capacidade de referência do perfil |
| `capacidade_volume_m3` | `NUMERIC(12,4)` | sim | |

### `veiculo`

| Coluna | Tipo | Nulo | Descrição |
|---|---|---|---|
| *bloco técnico* | | | |
| `codigo` | `TEXT` | não | `UNIQUE (tenant_id, codigo)` |
| `perfil_id` | `BIGINT` | sim | `NULL` = perfil não classificado |
| `vinculo` | `TEXT` | não | `CHECK IN ('proprio','agregado','terceiro')` |
| `capacidade_peso_kg` | `NUMERIC(12,3)` | sim | Capacidade do veículo específico |
| `capacidade_volume_m3` | `NUMERIC(12,4)` | sim | |
| `ativo` | `BOOLEAN` | não | `DEFAULT true` |

Capacidade aparece nos dois lugares de propósito, e a precedência é: capacidade do
veículo quando informada, capacidade do perfil como fallback. Isso existe porque o
pré-requisito de R-001 é exatamente detectar cadastro de capacidade furado — se as
duas fossem a mesma coluna, não haveria contra o que comparar.

`perfil_id` nulo não é detalhe: viagem de veículo sem perfil é viagem que R-001 não
consegue calibrar, e isso alimenta a contagem do pré-requisito.

### `motorista`

| Coluna | Tipo | Nulo | Descrição |
|---|---|---|---|
| *bloco técnico* | | | |
| `codigo` | `TEXT` | não | Identificador opaco. `UNIQUE (tenant_id, codigo)` |
| `nome` | `TEXT` | sim | |
| `vinculo` | `TEXT` | não | `CHECK IN ('funcionario','agregado','terceiro')` |
| `ativo` | `BOOLEAN` | não | `DEFAULT true` |

O canônico **não modela CPF, CNH nem qualquer documento de pessoa física.** Não
precisamos para nenhuma regra do catálogo: R-004 exige reconciliar dois caminhos de
pagamento pelo mesmo motorista, e um código opaco estável faz isso. Se o dado real
nunca entra no modelo, ele não vaza. Deduplicar cadastro duplicado de motorista na
origem é trabalho do adaptador.

### `cliente`

Não está na tabela de entidades do catálogo, mas R-003 a lista e `documento_frete`
a referencia.

| Coluna | Tipo | Nulo | Descrição |
|---|---|---|---|
| *bloco técnico* | | | |
| `codigo` | `TEXT` | não | `UNIQUE (tenant_id, codigo)` |
| `nome` | `TEXT` | sim | |
| `segmento` | `TEXT` | sim | |
| `unidade_atendimento_id` | `BIGINT` | sim | Unidade comercial responsável |

### `rota`

Par origem→destino. Existe porque o cálculo de R-001 precisa de "frete médio por kg
da rota, no período".

| Coluna | Tipo | Nulo | Descrição |
|---|---|---|---|
| *bloco técnico* | | | |
| `codigo` | `TEXT` | não | `UNIQUE (tenant_id, codigo)` |
| `origem_unidade_id` | `BIGINT` | sim | |
| `destino_cidade` | `TEXT` | sim | |
| `destino_uf` | `TEXT` | sim | UF, `CHECK (~ '^[A-Z]{2}$')` |
| `tipo` | `TEXT` | não | `CHECK IN ('transferencia','distribuicao','coleta','dedicado')` |

Muitas origens não têm conceito de rota. Nesse caso o adaptador deriva a rota do par
(unidade de origem, cidade/UF de destino) e marca `rota_procedencia = 'derivado'` no
fato. `tipo` separa transferência de distribuição e é insumo direto do pré-requisito
de R-007.

### `categoria_despesa`

| Coluna | Tipo | Nulo | Descrição |
|---|---|---|---|
| *bloco técnico* | | | |
| `codigo` | `TEXT` | não | `UNIQUE (tenant_id, codigo)` |
| `descricao` | `TEXT` | não | |
| `grupo` | `TEXT` | não | `CHECK IN ('folha','transferencia','distribuicao','frete_terceiro','manutencao','combustivel','outros')` |
| `eh_hora_extra` | `BOOLEAN` | não | `DEFAULT false` |
| `eh_pagamento_motorista` | `BOOLEAN` | não | `DEFAULT false` |
| `permite_rateio` | `BOOLEAN` | não | `DEFAULT false` |

As flags booleanas são o que transforma os pré-requisitos de R-006 e R-007 em
consulta em vez de opinião. "A hora extra está separada das demais rubricas?" vira
`SELECT count(*) FROM categoria_despesa WHERE eh_hora_extra` — se der zero, a regra
é `NAO_APURAVEL` e você sabe disso antes de rodar qualquer cálculo.

### `tipo_ocorrencia`

| Coluna | Tipo | Nulo | Descrição |
|---|---|---|---|
| *bloco técnico* | | | |
| `codigo` | `TEXT` | não | `UNIQUE (tenant_id, codigo)` |
| `descricao` | `TEXT` | não | |
| `natureza` | `TEXT` | não | `CHECK IN ('avaria','extravio','roubo','atraso','outros')` |
| `indenizavel` | `BOOLEAN` | não | `DEFAULT true` |

### `apolice`

R-005(a) calibra prazo de aviso por apólice — logo, apólice é entidade, não parâmetro.

| Coluna | Tipo | Nulo | Descrição |
|---|---|---|---|
| *bloco técnico* | | | |
| `codigo` | `TEXT` | não | `UNIQUE (tenant_id, codigo)` |
| `seguradora` | `TEXT` | sim | |
| `vigencia_inicio` | `DATE` | não | |
| `vigencia_fim` | `DATE` | sim | |
| `prazo_aviso_dias` | `INTEGER` | sim | Prazo contratual para aviso do sinistro |
| `franquia_valor` | `NUMERIC(14,2)` | sim | |
| `limite_indenizacao` | `NUMERIC(14,2)` | sim | |

`prazo_aviso_dias` nulo é o gatilho de `NAO_APURAVEL` de R-005(a). Nunca assumir 30.

---

## 6. Fatos

### `viagem`

Carregamento que sai de uma unidade.

| Coluna | Tipo | Nulo | Descrição |
|---|---|---|---|
| *bloco técnico* | | | |
| `codigo` | `TEXT` | não | `UNIQUE (tenant_id, codigo)` |
| `unidade_id` | `BIGINT` | não | Unidade de saída |
| `veiculo_id` | `BIGINT` | sim | |
| `motorista_id` | `BIGINT` | sim | |
| `rota_id` | `BIGINT` | sim | |
| `rota_procedencia` | `TEXT` | sim | `CHECK IN ('informado','derivado')` |
| `data_saida` | `DATE` | não | |
| `data_chegada` | `DATE` | sim | |
| `peso_real_kg` | `NUMERIC(12,3)` | sim | |
| `peso_cubado_kg` | `NUMERIC(12,3)` | sim | |
| `peso_taxado_kg` | `NUMERIC(12,3)` | sim | O maior entre real e cubado |
| `peso_taxado_procedencia` | `TEXT` | sim | `CHECK IN ('informado','derivado')` |
| `volume_m3` | `NUMERIC(12,4)` | sim | |
| `status` | `TEXT` | não | `CHECK IN ('planejada','em_transito','concluida','cancelada')` |
| `cancelada_em` | `TIMESTAMPTZ` | sim | |

`peso_taxado_kg` é o campo que R-001 consome — o catálogo é explícito: nunca peso
real puro, senão carga leve e volumosa passa despercebida. Quando a origem não
informa peso taxado, o adaptador calcula com o fator de cubagem do tenant e marca
`peso_taxado_procedencia = 'derivado'`. Achado de R-001 apoiado em peso taxado
derivado precisa sair com essa ressalva no painel.

### `documento_frete`

Documento fiscal de transporte.

| Coluna | Tipo | Nulo | Descrição |
|---|---|---|---|
| *bloco técnico* | | | |
| `codigo` | `TEXT` | não | `UNIQUE (tenant_id, codigo)` |
| `viagem_id` | `BIGINT` | sim | |
| `cliente_id` | `BIGINT` | sim | |
| `unidade_emissora_id` | `BIGINT` | não | Base do faturamento em emissão |
| `rota_id` | `BIGINT` | sim | Derivada quando ausente na origem |
| `data_emissao` | `DATE` | não | |
| `valor_frete` | `NUMERIC(14,2)` | não | |
| `valor_mercadoria` | `NUMERIC(14,2)` | sim | |
| `peso_kg` | `NUMERIC(12,3)` | sim | |
| `origem_cidade` | `TEXT` | sim | |
| `origem_uf` | `TEXT` | sim | UF, `CHECK (~ '^[A-Z]{2}$')` |
| `destino_cidade` | `TEXT` | sim | |
| `destino_uf` | `TEXT` | sim | UF, `CHECK (~ '^[A-Z]{2}$')` |
| `status` | `TEXT` | não | `CHECK IN ('emitido','em_transporte','entregue','cancelado')` |
| `cancelado_em` | `TIMESTAMPTZ` | sim | |

`unidade_emissora_id` é `NOT NULL` porque R-007 divide custo de transferência pelo
faturamento em emissão da unidade — documento sem unidade emissora envenena o
denominador silenciosamente.

### `cotacao`

| Coluna | Tipo | Nulo | Descrição |
|---|---|---|---|
| *bloco técnico* | | | |
| `codigo` | `TEXT` | não | `UNIQUE (tenant_id, codigo)` |
| `cliente_id` | `BIGINT` | sim | |
| `unidade_id` | `BIGINT` | não | Unidade comercial que cotou |
| `data_cotacao` | `DATE` | não | |
| `valor_cotado` | `NUMERIC(14,2)` | não | |
| `status` | `TEXT` | não | `CHECK IN ('aberta','convertida','expirada','recusada','cancelada')` |
| `documento_frete_id` | `BIGINT` | sim | Documento gerado, se houve |
| `vinculo_procedencia` | `TEXT` | sim | `CHECK IN ('rastreavel','manual')` |
| `cancelada_em` | `TIMESTAMPTZ` | sim | |

`vinculo_procedencia` é o pré-requisito de R-003 virado coluna. `rastreavel`
significa que a origem carrega o vínculo cotação→documento; `manual` significa que
alguém digitou. O catálogo é claro: com vínculo manual a regra é indicativa, não
financeira, e o painel precisa saber a diferença.

O `status` é o informado pela origem. **A regra não confia nele** — R-003 recalcula
os três estados a partir da janela de conversão e do vínculo. Guardamos o status de
origem para poder mostrar a divergência, que costuma ser um achado por si só.

### `ocorrencia`

Evento de exceção na entrega.

| Coluna | Tipo | Nulo | Descrição |
|---|---|---|---|
| *bloco técnico* | | | |
| `codigo` | `TEXT` | não | `UNIQUE (tenant_id, codigo)` |
| `documento_frete_id` | `BIGINT` | sim | |
| `tipo_ocorrencia_id` | `BIGINT` | não | |
| `unidade_id` | `BIGINT` | sim | Unidade responsável pelo trecho |
| `veiculo_id` | `BIGINT` | sim | |
| `apolice_id` | `BIGINT` | sim | |
| `data_fato` | `DATE` | sim | Quando o sinistro aconteceu |
| `data_aviso_seguradora` | `DATE` | sim | Quando foi comunicado |
| `valor_mercadoria` | `NUMERIC(14,2)` | sim | |
| `valor_apurado` | `NUMERIC(14,2)` | sim | Prejuízo apurado após análise |
| `valor_indenizado` | `NUMERIC(14,2)` | sim | Efetivamente recebido |
| `status` | `TEXT` | não | `CHECK IN ('aberta','em_analise','indenizada','negada','encerrada')` |

`data_fato` e `data_aviso_seguradora` são colunas separadas e ambas nuláveis. Essa
separação é a regra R-005(a) inteira: sem as duas datas distintas não existe
intervalo, e sem intervalo não existe perda por decadência de prazo. Se a origem só
tem uma data, ela vai para `data_fato` e `data_aviso_seguradora` fica `NULL` — nunca
copiada de uma para a outra.

`valor_apurado` é o "devido" com que R-005(b) compara a dedução da fatura.

### `despesa`

| Coluna | Tipo | Nulo | Descrição |
|---|---|---|---|
| *bloco técnico* | | | |
| `codigo` | `TEXT` | não | `UNIQUE (tenant_id, codigo)` |
| `categoria_despesa_id` | `BIGINT` | não | |
| `unidade_id` | `BIGINT` | sim | |
| `viagem_id` | `BIGINT` | sim | |
| `motorista_id` | `BIGINT` | sim | Preenchido quando o favorecido é motorista |
| `fornecedor_codigo` | `TEXT` | sim | Favorecido não-motorista, opaco |
| `data_lancamento` | `DATE` | não | Quando entrou no sistema |
| `data_competencia` | `DATE` | não | A que mês pertence |
| `data_pagamento` | `DATE` | sim | Quando o dinheiro saiu |
| `valor` | `NUMERIC(14,2)` | não | |
| `canal_pagamento` | `TEXT` | sim | Normalizado pelo adaptador |
| `documento_pagamento` | `TEXT` | sim | Identificador do pagamento na origem |
| `natureza_pagamento` | `TEXT` | sim | `CHECK IN ('integral','adiantamento','saldo','complemento')` |
| `rateada` | `BOOLEAN` | não | `DEFAULT false` — valor distribuído entre unidades |
| `estornada_em` | `TIMESTAMPTZ` | sim | |

Quatro colunas aqui existem só para R-004, e cada uma tem função:

- `canal_pagamento` é o que permite detectar a mesma viagem paga por dois caminhos —
  o catálogo cita operação de crédito de frete versus pagamento direto. O adaptador
  normaliza para rótulos nossos; nenhum nome de produto de terceiro entra aqui.
- `natureza_pagamento` é o que evita o falso positivo mais óbvio da regra:
  adiantamento seguido de saldo são dois lançamentos legítimos para a mesma viagem.
  Sem esta coluna, R-004 acusa toda operação normal de adiantamento como duplicidade.
- `motorista_id` é a chave de reconciliação exigida pelo pré-requisito.
- `rateada` invalida a linha para R-006 e R-007, que dependem de custo atribuído à
  unidade correta.

`data_competencia` e `data_lancamento` são separadas porque duplicidade se detecta em
competência, mas a janela curta de valores idênticos se mede em lançamento.

### `fatura`

Cobrança ao cliente.

| Coluna | Tipo | Nulo | Descrição |
|---|---|---|---|
| *bloco técnico* | | | |
| `codigo` | `TEXT` | não | `UNIQUE (tenant_id, codigo)` |
| `cliente_id` | `BIGINT` | sim | |
| `unidade_id` | `BIGINT` | sim | |
| `data_emissao` | `DATE` | não | |
| `data_vencimento` | `DATE` | sim | |
| `valor_bruto` | `NUMERIC(14,2)` | não | |
| `valor_deducoes` | `NUMERIC(14,2)` | sim | Total informado pela origem |
| `valor_liquido` | `NUMERIC(14,2)` | sim | |
| `status` | `TEXT` | não | `CHECK IN ('emitida','paga','parcial','cancelada')` |
| `cancelada_em` | `TIMESTAMPTZ` | sim | |

### `fatura_item`

Vínculo N:N entre fatura e documentos cobrados.

| Coluna | Tipo | Nulo | Descrição |
|---|---|---|---|
| *bloco técnico* | | | |
| `fatura_id` | `BIGINT` | não | |
| `documento_frete_id` | `BIGINT` | não | |
| `valor` | `NUMERIC(14,2)` | não | |

### `fatura_deducao`

**A tabela mais importante deste documento.** O catálogo aponta R-005(b) como
provavelmente o maior valor do produto e como a lacuna mais comum do mercado. Toda
essa regra depende de dedução ser *linha discriminada*, não campo agregado.

| Coluna | Tipo | Nulo | Descrição |
|---|---|---|---|
| *bloco técnico* | | | |
| `fatura_id` | `BIGINT` | não | |
| `documento_frete_id` | `BIGINT` | sim | A qual documento a dedução se refere |
| `ocorrencia_id` | `BIGINT` | sim | Ocorrência que justifica a dedução |
| `tipo_deducao` | `TEXT` | não | `CHECK IN ('avaria','extravio','atraso','divergencia_tarifa','glosa','outros')` |
| `valor` | `NUMERIC(14,2)` | não | |
| `descricao` | `TEXT` | sim | Texto livre da origem |
| `data_deducao` | `DATE` | sim | |

Se `fatura.valor_deducoes` é maior que zero mas não existem linhas em
`fatura_deducao`, a frente (b) de R-005 é `NAO_APURAVEL` para aquele cliente — e
essa é uma resposta útil, não um fracasso. Ela nomeia exatamente o dado que falta.

Os dois nulos são intencionais e são o achado:

- `documento_frete_id` nulo = o cliente descontou sem dizer de qual frete. Não dá
  para conciliar, e o volume disso é a medida do problema.
- `ocorrencia_id` nulo = **dedução sem ocorrência correspondente aberta**, que é
  literalmente metade do sinal de R-005(b). Aqui o nulo não bloqueia a regra: ele *é*
  a regra.

### `evento_autorizacao`

Exceção autorizada no sistema de origem: quem liberou, quando, por quê, sobre o quê.

| Coluna | Tipo | Nulo | Descrição |
|---|---|---|---|
| *bloco técnico* | | | |
| `objeto_tipo` | `TEXT` | não | `CHECK IN ('viagem','documento_frete','despesa','fatura')` |
| `objeto_id` | `BIGINT` | não | Id na tabela indicada por `objeto_tipo` |
| `trava` | `TEXT` | não | Qual controle foi contornado. Ex.: `ocupacao_minima` |
| `usuario_codigo` | `TEXT` | não | Identificador opaco de quem liberou |
| `unidade_id` | `BIGINT` | sim | Unidade do objeto liberado |
| `ocorrido_em` | `TIMESTAMPTZ` | não | |
| `motivo_codigo` | `TEXT` | sim | Motivo estruturado, quando existe |
| `motivo_texto` | `TEXT` | sim | Motivo digitado |

`objeto_tipo` + `objeto_id` sem chave estrangeira é uma escolha consciente e tem
custo: o banco não garante que o `objeto_id` existe. A alternativa seria uma coluna
`viagem_id` — hoje R-002 só audita liberação de viagem. Optei pela forma genérica
porque trava sobre despesa e sobre fatura é extensão previsível deste produto, e
migrar depois custa mais do que a integridade referencial que estou abrindo mão
agora. A mitigação é validação no adaptador, não no schema. **Se você discordar,
este é o ponto mais fácil de reverter do documento inteiro.**

`usuario_codigo` é opaco por design. R-002 precisa detectar concentração anômala num
mesmo usuário, e para isso basta um identificador estável — nome não acrescenta nada
à regra e acrescenta dado pessoal ao modelo.

`motivo_codigo` e `motivo_texto` são separados porque o sinal de R-002 tem três
formas distintas: branco (ambos nulos), genérico repetido (mesmo `motivo_texto` em
frequência anômala) e concentração por usuário. Colapsar as duas colunas numa só
apaga a diferença entre "não preencheu" e "preencheu com lixo".

---

## 7. O que cada regra lê

A tradução do catálogo para este modelo, e — mais importante — a condição exata que
faz cada regra devolver `NAO_APURAVEL`.

| Regra | Lê | Devolve `NAO_APURAVEL` quando |
|---|---|---|
| **R-001** Ocupação | `viagem`, `veiculo`, `perfil_veiculo`, `unidade`, `rota`, `documento_frete` | mais de 5% das viagens da unidade com ocupação acima de 150%; ou capacidade ausente no veículo **e** no perfil; ou `peso_taxado_kg` nulo em parcela relevante da amostra |
| **R-002** Autorização | `evento_autorizacao`, `viagem`, `unidade`, `parametro_calibracao_item` | não há linhas de `evento_autorizacao` para a trava e o período — sem log, não é apurável |
| **R-003** Cotação | `cotacao`, `documento_frete`, `cliente`, `unidade` | `vinculo_procedencia = 'manual'` na maioria da amostra — resultado vira indicativo, não financeiro |
| **R-004** Duplicidade | `despesa`, `viagem`, `motorista`, `categoria_despesa` | `motorista_id` nulo nas despesas de pagamento a motorista; ou um único `canal_pagamento` distinto no período — os dois caminhos não chegaram ao mesmo repositório |
| **R-005(a)** Prazo | `ocorrencia`, `apolice`, `unidade` | `apolice.prazo_aviso_dias` nulo; ou `data_aviso_seguradora` nula em parcela relevante das ocorrências |
| **R-005(b)** Dedução | `fatura`, `fatura_deducao`, `ocorrencia`, `documento_frete` | `fatura.valor_deducoes > 0` sem linhas em `fatura_deducao` — a dedução não está discriminada |
| **R-006** Hora extra | `despesa`, `categoria_despesa`, `unidade` | nenhuma categoria com `eh_hora_extra = true`; ou despesas de folha com `rateada = true` acima do tolerado |
| **R-007** Transferência | `despesa`, `categoria_despesa`, `documento_frete`, `unidade`, `rota` | nenhuma categoria com `grupo = 'transferencia'` distinta de `'distribuicao'`; ou `unidade_emissora_id` ausente em parcela relevante dos documentos |

Duas observações que valem para todas as linhas dessa tabela:

**"Parcela relevante" é parâmetro, não constante.** Cada regra tem sua própria chave
de cobertura mínima em `parametro_calibracao` — `R005a.cobertura_minima_data_aviso`,
por exemplo. O padrão inicial fica em aberto e deve ser decidido com dataset
sintético na mão, não agora.

**A verificação roda antes da consulta, não depois.** O catálogo é explícito e o
modelo foi desenhado para isso: toda condição da coluna da direita é respondível com
uma consulta barata sobre cobertura e metadado, sem tocar no cálculo. Se o
pré-requisito só fosse verificável depois de apurar, a tentação de "já que calculei,
mostro o número" existiria — e ela é exatamente o defeito que o catálogo proíbe.

---

## 8. Fora de escopo nesta versão

O que este documento **não** cobre, e por quê:

- **Modelo de achado e tratativa.** Um desvio detectado vira o quê: fila, prazo,
  status, responsável. O catálogo lista isso como item em aberto, e ele é o que separa
  produto de relatório. É um modelo de *saída*, distinto do canônico de *entrada*, e
  merece documento próprio.
- **Custo de combustível, manutenção e pneu.** Nenhuma regra do catálogo v0.1 usa.
  Entra quando entrar a regra.
- **Contrato e tabela de frete do cliente.** R-005(b) compara a dedução com
  `ocorrencia.valor_apurado`, o que basta para o catálogo atual. Uma regra futura de
  divergência tarifária exigiria modelar tabela de preço — e essa é uma extensão
  grande, não um campo.
- **Histórico de alteração dos fatos.** O canônico guarda o estado atual mais a
  procedência da carga. Auditoria de "quem mudou o valor deste documento e quando" é
  problema do sistema de origem.

---

## Pendências deste documento

1. Definir o padrão inicial das chaves de cobertura mínima por regra — só com dataset
   sintético na mão.
2. Fechar a política de recalibração (item em aberto do catálogo): de quanto em quanto
   tempo, disparada por quem, e o que acontece com achados abertos sob parâmetro antigo.
3. Decidir o comportamento quando o pré-requisito falha: bloqueia a regra ou entrega
   em modo indicativo com aviso. O modelo suporta os dois; a decisão é de produto.
4. Registrar em `decisoes.md` as decisões tomadas aqui.
