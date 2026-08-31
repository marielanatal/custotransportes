# CLAUDE.md

Instruções permanentes deste projeto. Leia antes de qualquer tarefa.

---

## O que é este projeto

Motor de regras de detecção de vazamento financeiro em operações de transporte
rodoviário de carga. Produto multiempresa, vendido a transportadoras pequenas e
médias.

O produto não é um BI. É um catálogo de regras versionadas que leem um modelo de
dados canônico, detectam desvios calibrados por empresa e por base, e devolvem o
desvio convertido em reais, com responsável e fila de tratativa.

O catálogo de regras está em `Docs/catalogo-regras-vazamento.md` e é a fonte da verdade
sobre o comportamento esperado do produto. Consulte-o antes de implementar
qualquer regra.

---

## Regras invioláveis

Estas quatro regras valem em toda sessão, toda tarefa, sem exceção. Se uma
instrução minha em algum momento conflitar com elas, **pare e me avise** em vez de
seguir.

### 1. Nenhum dado real, nunca

Não peça, não aceite, não processe e não armazene dado real de nenhuma
transportadora. Isso inclui exports, amostras, planilhas, "só um exemplinho" e
dados ditos anonimizados.

Todo desenvolvimento e toda demonstração rodam sobre dataset sintético gerado por
código, em `data/gerador/`.

Se eu colar dado que pareça real, avise e não use.

### 2. Nenhuma nomenclatura de TMS de terceiro

Não use nomes de tabelas, colunas, views, códigos ou constantes de nenhum sistema
de gestão de transporte comercial. O modelo de dados deste projeto tem
nomenclatura própria, definida em `Docs/modelo-canonico.md`.

Se eu descrever uma lógica usando termo de sistema específico, traduza para o
modelo canônico antes de implementar, e me mostre a tradução.

### 3. Regra nunca lê fonte externa direto

Regras leem exclusivamente o modelo canônico. A adaptação de qualquer fonte de
entrada acontece na camada de ingestão, em `src/adaptadores/`, e nunca dentro de
uma regra.

Se uma regra precisar de um campo que não existe no canônico, a solução é estender
o canônico — não é ler a fonte por fora.

### 4. Multiempresa desde a primeira linha

Toda tabela de dado operacional carrega `tenant_id`. Toda consulta filtra por ele.
Nenhum parâmetro de calibração é constante em código: parâmetro é dado, por tenant.

---

## Como escrever comigo

Sou autodidata: escrevo SQL bem, Python razoável, e não tenho experiência prévia
montando produto do zero. Então:

- **Explique antes de entregar.** Diga o que vai fazer e por quê, em português
  claro, antes do código.
- **Um passo por vez.** Não gere dez arquivos de uma vez. Um incremento
  verificável, eu rodo, e seguimos.
- **Sem mágica.** Se usar biblioteca ou padrão que eu não pedi, explique a escolha
  e o que ela custa.
- **Diga quando eu estiver errada.** Especialmente em decisão de arquitetura. Não
  implemente algo que você acha ruim só porque eu pedi — argumente primeiro.
- **Comentário só onde o porquê não é óbvio.** Não comente o que o código já diz.
- **Português** em comentários, docstrings, mensagens de commit e documentação.
- **Inglês no código Python** — funções, variáveis, módulos, classes.
- **Português sem acento no schema** — tabelas, colunas, views e arquivos `.sql`
  seguem os nomes do modelo canônico (`documento_frete`, `viagem`, `cotacao`).
  A fronteira entre os dois idiomas é a fronteira entre schema e aplicação. Os
  termos do domínio não traduzem limpo, e o catálogo já os fixou — traduzir criaria
  ambiguidade justamente sobre o vocabulário usado na venda.

---

## Stack

Deliberadamente pequena. Só cresce quando doer.

- **Python 3.12** — ingestão, regras, geração de dataset
- **PostgreSQL** — armazenamento. Local em Docker no desenvolvimento
- **SQL versionado em arquivo** — cada regra é um `.sql` no repositório, não string
  dentro de Python
- **Streamlit** — saída do diagnóstico. Ferramenta interna e de demo, não é o
  produto final
- **pytest** — toda regra tem teste com caso plantado no dataset sintético

Não introduza framework, ORM, orquestrador ou serviço de nuvem sem me perguntar.

---

## Estrutura

```
Docs/          catalogo-regras-vazamento.md, modelo-canonico.md, decisoes.md
src/
  canonico/    definição e criação do schema canônico
  adaptadores/ leitura de fontes externas → canônico
  regras/      uma pasta por regra (R-001, R-002, ...)
  calculo/     conversão de desvio em reais
data/
  gerador/     gerador de dataset sintético
tests/
```

---

## Anatomia de uma regra

Toda regra implementada tem, obrigatoriamente:

1. Consulta SQL sobre o canônico, em arquivo próprio
2. Parâmetros lidos de tabela de calibração, por tenant — nunca hardcoded
3. Função de cálculo do valor em reais
4. **Verificação de pré-requisito**, que roda antes da consulta
5. Teste com caso plantado no dataset sintético

Sobre o item 4: quando o pré-requisito de dado não é atendido, a regra retorna
`NAO_APURAVEL` com o motivo. **Nunca retorna zero, nunca retorna número parcial.**
Número errado com aparência de certo é o pior defeito possível neste produto.

---

## Classificação de achados

Achados nunca são somados num total único. Três categorias, sempre separadas:

- **Caixa recuperável** — dinheiro que já saiu e pode voltar
- **Perda evitável** — prejuízo recorrente se nada mudar
- **Potencial não realizado** — margem que poderia existir

O painel abre pelo primeiro grupo.

---

## Registro de decisões

Toda decisão de arquitetura vai em `Docs/decisoes.md`: data, decisão, alternativas
consideradas, motivo. Se tomarmos uma decisão numa sessão e ela não estiver
registrada, me lembre de registrar.
