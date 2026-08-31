-- Núcleo multiempresa: o tenant e o registro de cargas de ingestão.
-- Referência: Docs/modelo-canonico.md, seção 3.

CREATE SCHEMA IF NOT EXISTS canonico;


-- A transportadora cliente. Única tabela sem tenant_id: ela é o tenant.
CREATE TABLE canonico.tenant (
    tenant_id   TEXT        PRIMARY KEY,
    nome        TEXT        NOT NULL,
    ativo       BOOLEAN     NOT NULL DEFAULT true,
    criado_em   TIMESTAMPTZ NOT NULL DEFAULT now(),

    -- O slug é imutável na prática e vira prefixo de tudo: restringir o formato
    -- agora evita descobrir na marra que 'Transp Alfa' quebra script de shell.
    CONSTRAINT tenant_slug_valido
        CHECK (tenant_id ~ '^[a-z][a-z0-9_]{2,49}$')
);


-- Um lote de ingestão. Sem esta tabela não existe verificação de cobertura,
-- e sem cobertura metade dos pré-requisitos das regras vira chute.
CREATE TABLE canonico.carga_ingestao (
    id                 BIGINT      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tenant_id          TEXT        NOT NULL REFERENCES canonico.tenant (tenant_id),
    entidade           TEXT        NOT NULL,
    origem_sistema     TEXT        NOT NULL,
    periodo_inicio     DATE        NOT NULL,
    periodo_fim        DATE        NOT NULL,
    linhas_lidas       INTEGER,
    linhas_aceitas     INTEGER,
    linhas_rejeitadas  INTEGER,
    status             TEXT        NOT NULL,
    iniciado_em        TIMESTAMPTZ NOT NULL DEFAULT now(),
    concluido_em       TIMESTAMPTZ,

    CONSTRAINT carga_status_valido
        CHECK (status IN ('em_andamento', 'concluida', 'falhou')),
    CONSTRAINT carga_periodo_coerente
        CHECK (periodo_fim >= periodo_inicio),

    -- Alvo das chaves estrangeiras compostas das demais tabelas.
    CONSTRAINT carga_ingestao_tenant_id_unico UNIQUE (tenant_id, id)
);

CREATE INDEX carga_ingestao_tenant_entidade_idx
    ON canonico.carga_ingestao (tenant_id, entidade, periodo_inicio);

COMMENT ON COLUMN canonico.carga_ingestao.periodo_inicio IS
    'Declarado pelo adaptador, nunca inferido do dado. Lote que declara cobrir '
    'janeiro e traz zero ocorrências significa "janeiro sem avaria". Lote sem '
    'período declarado e zero ocorrências não significa nada.';
