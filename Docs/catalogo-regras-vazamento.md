# Catálogo de Regras de Vazamento

**Versão 0.1 — rascunho de trabalho**

Documento fundacional do produto. Define, sem código e sem referência a nenhum TMS
específico, quais são as regras que detectam dinheiro saindo da operação de uma
transportadora, como cada uma é calibrada e como cada uma vira reais.

Regra alguma neste catálogo lê tabela de TMS. Todas leem o modelo canônico.

---

## Modelo canônico (v0.1)

As entidades mínimas que as regras deste catálogo precisam. Nomenclatura própria,
independente de origem.

| Entidade | Para que serve |
|---|---|
| `unidade` | Base operacional. Unidade de calibração e de responsabilização. |
| `veiculo` | Perfil, capacidade em peso e em volume, vínculo (próprio / agregado / terceiro). |
| `viagem` | Carregamento que sai de uma unidade. Peso real, peso taxado, volume, rota, veículo, data. |
| `documento_frete` | Documento fiscal de transporte. Valor, peso, cliente, origem, destino, status, viagem. |
| `cotacao` | Proposta comercial. Cliente, valor, data, status, vínculo com documento gerado. |
| `ocorrencia` | Evento de exceção na entrega. Tipo, valor da mercadoria, documento, data do fato, data do aviso. |
| `despesa` | Lançamento de custo. Categoria, unidade, fornecedor/motorista, valor, data, competência. |
| `fatura` | Cobrança ao cliente. Valor bruto, deduções, valor líquido, documentos vinculados. |
| `evento_autorizacao` | Registro de exceção autorizada no sistema: quem liberou, quando, por quê, sobre qual objeto. |

**Convenção de calibração.** Todo parâmetro é dado, nunca constante em código.
Escopo de calibração em três níveis, com fallback: `unidade + perfil` → `perfil` →
`global`. Referência estatística é mediana, não média. Margem de segurança padrão
de 70–80% abaixo da mediana observada no período de calibração.

**Período de calibração.** Mínimo de um mês fechado de operação, com volume mínimo
de amostras por combinação (sugestão inicial: 30). Abaixo disso, usa o fallback.

---

## Anatomia de uma regra

Todo item do catálogo tem sete campos. O sétimo é o que separa produto de painel.

1. **Pergunta** — a pergunta de negócio em uma frase, na língua do dono
2. **Entidades** — o que a regra lê no modelo canônico
3. **Sinal** — a condição que caracteriza o desvio
4. **Parâmetros** — o que é calibrável, e o padrão inicial
5. **Cálculo em R$** — como o desvio vira dinheiro
6. **Dono** — quem trata, não quem olha
7. **Pré-requisito** — a condição de dado sem a qual a regra **não roda**

Regra sem pré-requisito atendido não sai como zero e não sai como número baixo.
Sai como **"não apurável"**, com o motivo. Número errado com aparência de certo
destrói a confiança no produto inteiro, e não tem volta.

---

## R-001 — Ocupação abaixo do mínimo

- **Pergunta:** quanto de frete a empresa deixou de faturar rodando veículo vazio?
- **Entidades:** `viagem`, `veiculo`, `unidade`
- **Sinal:** peso taxado ÷ capacidade do veículo < limite calibrado para a
  combinação unidade + perfil
- **Parâmetros:** limite mínimo por unidade e perfil (padrão: 70% da mediana
  observada no período de calibração); teto de descarte de 150% de ocupação
- **Cálculo em R$:** (capacidade × limite − peso taxado) × frete médio por kg
  da rota, no período
- **Dono:** supervisor da base
- **Pré-requisito:** vínculo viagem ↔ perfil de veículo confiável. Se a taxa de
  ocupação acima de 150% na amostra superar 5%, o cadastro de capacidade está
  furado e a regra não é apurável para aquela unidade.

**Nota de calibração:** usar peso taxado (o maior entre real e cubado), nunca peso
real puro. Carga leve e volumosa ocupa o veículo inteiro e passaria despercebida.

---

## R-002 — Exceção autorizada sem justificativa válida

- **Pergunta:** a trava está sendo respeitada, ou virou formalidade que todo mundo
  clica pra passar?
- **Entidades:** `evento_autorizacao`, `viagem`, `unidade`
- **Sinal:** liberação de viagem abaixo do mínimo com motivo em branco, motivo
  genérico repetido, ou concentração anômala em um mesmo usuário
- **Parâmetros:** lista de motivos aceitos; teto de liberações por usuário/mês;
  teto de % de viagens liberadas por unidade (padrão: 10%)
- **Cálculo em R$:** mesmo cálculo de R-001, aplicado só às viagens liberadas —
  é o valor que a trava deveria ter barrado e não barrou
- **Dono:** gestor da unidade; reincidência sobe para a direção
- **Pré-requisito:** o sistema de origem registra usuário, timestamp e motivo em
  log recuperável. Sem log, não é apurável.

**Por que essa regra importa mais do que parece:** é a única do catálogo que mede
se o controle está funcionando, e não se a operação está. Toda trava vira ruído
depois de três meses se ninguém audita a liberação. Isso vale como argumento de
venda: você não entrega só o controle, entrega a vigilância sobre o controle.

---

## R-003 — Cotação sem conversão

- **Pergunta:** quanto de negócio proposto morreu sem virar frete, e onde?
- **Entidades:** `cotacao`, `documento_frete`, `cliente`, `unidade`
- **Sinal:** cotação sem documento de frete vinculado após a janela de conversão.
  Três estados: convertida, dentro do prazo, expirada sem conversão
- **Parâmetros:** janela de conversão em dias (padrão: 5); regra de vínculo
  cotação ↔ documento; tratamento de documento cancelado
- **Cálculo em R$:** somatório do valor cotado das expiradas. Reportar como
  **receita potencial perdida**, nunca como prejuízo — são coisas diferentes e
  confundir as duas queima credibilidade na primeira reunião
- **Dono:** comercial da unidade
- **Pré-requisito:** existe vínculo rastreável entre cotação e documento gerado.
  Se a conversão é informada na mão, a regra vira indicativa, não financeira.

**Regra de contagem:** documento cancelado não conta como conversão.

---

## R-004 — Pagamento em duplicidade a motorista

- **Pergunta:** a empresa pagou duas vezes pela mesma viagem?
- **Entidades:** `despesa`, `viagem`, `veiculo`
- **Sinal:** mais de um lançamento de pagamento para a mesma combinação de
  motorista + viagem + competência, por caminhos diferentes (pagamento via
  operação de crédito de frete e pagamento direto), ou valores idênticos ao mesmo
  favorecido dentro de uma janela curta
- **Parâmetros:** janela de detecção em dias (padrão: 7); tolerância de valor
  (padrão: exato); lista de exceções legítimas (adiantamento + saldo, complemento)
- **Cálculo em R$:** valor do lançamento duplicado — **este é o único da lista que
  é caixa recuperável, não economia projetada**
- **Dono:** financeiro
- **Pré-requisito:** os dois caminhos de pagamento chegam ao mesmo repositório de
  despesa e são reconciliáveis por identificador de motorista.

**Por que essa é a regra de abertura numa venda:** o número é indiscutível, é
dinheiro que já saiu, e a validação leva minutos com o financeiro. Se o
diagnóstico achar duplicidade real, a conversa acaba ali. Comece o piloto por ela.

---

## R-005 — Sinistro fora de prazo e desconto não conciliado

- **Pergunta:** quanto de avaria e extravio virou prejuízo próprio por perda de
  prazo, e quanto o cliente descontou além do devido?
- **Entidades:** `ocorrencia`, `documento_frete`, `fatura`, `unidade`, `veiculo`
- **Sinal:** duas frentes independentes.
  **(a)** ocorrência com intervalo entre data do fato e data do aviso à seguradora
  maior que o prazo contratual da apólice.
  **(b)** dedução em fatura sem ocorrência correspondente aberta, ou com valor de
  dedução maior que o valor apurado da ocorrência
- **Parâmetros:** prazo de aviso por apólice (padrão: conforme contrato, tipicamente
  curto); franquia; tolerância de divergência de valor (padrão: R$ 0)
- **Cálculo em R$:** (a) valor indenizável perdido por decadência de prazo;
  (b) diferença entre descontado e devido
- **Dono:** (a) qualidade/sinistros; (b) financeiro/faturamento
- **Pré-requisito:** data do fato **e** data do aviso registradas separadamente, e
  deduções de fatura discriminadas por documento. Sem discriminação da dedução, a
  frente (b) não é apurável — e essa é a lacuna mais comum do mercado.

**Nota:** a frente (b) costuma ser a maior do catálogo em valor e a mais invisível,
porque o desconto chega diluído na fatura e ninguém amarra à ocorrência de origem.

---

## R-006 — Hora extra acima da meta

- **Pergunta:** onde a jornada extra virou custo estrutural em vez de exceção?
- **Entidades:** `despesa`, `unidade`
- **Sinal:** custo de hora extra da unidade acima do teto calibrado, medido como
  percentual da folha da unidade e em variação contra a própria base histórica
- **Parâmetros:** teto por unidade (padrão: mediana do quadrimestre anterior menos
  a meta de redução); sazonalidade por mês
- **Cálculo em R$:** valor acima do teto, no mês
- **Dono:** gestor da unidade
- **Pré-requisito:** despesa de hora extra separada das demais rubricas de folha e
  atribuída à unidade correta. Rateio genérico invalida a regra.

**Cuidado de leitura:** hora extra alta pode ser sintoma, não doença — falta de
efetivo, rota mal dimensionada, atraso de terceiro. A regra aponta onde olhar; ela
não diagnostica a causa, e o produto não deve fingir que diagnostica.

---

## R-007 — Custo de transferência acima da meta

- **Pergunta:** o custo de mover carga entre bases está corroendo a margem do frete?
- **Entidades:** `viagem`, `despesa`, `documento_frete`, `unidade`
- **Sinal:** custo de transferência acumulado ÷ faturamento em emissão da unidade
  acima do teto calibrado
- **Parâmetros:** teto por unidade (padrão: mediana do quadrimestre anterior menos
  a meta); composição do que entra como custo de transferência
- **Cálculo em R$:** (percentual apurado − teto) × faturamento em emissão do período
- **Dono:** gestor da unidade e planejamento
- **Pré-requisito:** despesa de transferência separável de despesa de distribuição.
  Se as duas estão na mesma rubrica, não é apurável.

---

## Classificação — e por que ela decide a venda

Não misture os três tipos no mesmo total. Somar tudo num número só é a tentação
óbvia e é o que faz o dono desconfiar da apresentação inteira.

| Tipo | Regras | O que é | Como apresentar |
|---|---|---|---|
| **Caixa recuperável** | R-004, R-005(b) | Dinheiro que já saiu e pode voltar | Valor cheio, com lista de casos |
| **Perda evitável** | R-001, R-002, R-005(a) | Prejuízo que se repete se nada mudar | Valor mensal recorrente |
| **Potencial não realizado** | R-003, R-006, R-007 | Margem que poderia existir | Sempre nomeado como potencial |

O painel abre com o total do primeiro grupo. É o mais baixo dos três e é o único
que ninguém contesta.

---

## Ordem de construção

1. **R-004** — menor dependência de dado, resultado indiscutível, valida o método
2. **R-001** — você já domina a calibração, e é a de maior efeito visual
3. **R-005(b)** — provavelmente o maior valor do catálogo
4. **R-003**
5. **R-002, R-006, R-007**

---

## Em aberto

- Definir a estrutura de tratativa: um desvio detectado vira o quê? Fila, prazo,
  status, responsável. Sem isso o produto é relatório, e relatório não vira hábito
- Decidir o que acontece quando o cliente não tem o dado do pré-requisito: bloqueia
  a regra, ou entrega em modo indicativo com aviso?
- Definir a política de recalibração: a cada quanto tempo os parâmetros são
  revistos, e por quem
- Mapear quais regras dependem de dado que muitas transportadoras simplesmente não
  registram — isso define o teto de mercado de cada uma
