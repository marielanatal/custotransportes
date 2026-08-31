-- Dimensões do modelo canônico.
-- Referência: Docs/modelo-canonico.md, seção 5.
--
-- Padrão repetido em toda tabela deste arquivo, escrito por extenso de propósito
-- (nada de template com LIKE — schema opaco custa mais do que schema repetitivo):
--
--   * bloco técnico: id, tenant_id, origem_sistema, origem_id, carga_id, ingerido_em
--   * UNIQUE (tenant_id, origem_sistema, origem_id) — torna a reingestão idempotente
--   * UNIQUE (tenant_id, id) — alvo das FK compostas de quem referencia esta tabela
--   * toda FK carrega tenant_id junto, para o banco impedir vínculo entre empresas


CREATE TABLE canonico.unidade (
    id              BIGINT      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tenant_id       TEXT        NOT NULL,
    origem_sistema  TEXT        NOT NULL,
    origem_id       TEXT        NOT NULL,
    carga_id        BIGINT,
    ingerido_em     TIMESTAMPTZ NOT NULL DEFAULT now(),

    codigo          TEXT        NOT NULL,
    nome            TEXT        NOT NULL,
    tipo            TEXT        NOT NULL,
    cidade          TEXT,
    uf              TEXT,
    ativo           BOOLEAN     NOT NULL DEFAULT true,

    CONSTRAINT unidade_tipo_valido
        CHECK (tipo IN ('matriz', 'filial', 'ponto_apoio')),
    CONSTRAINT unidade_uf_valida
        CHECK (uf ~ '^[A-Z]{2}$'),

    FOREIGN KEY (tenant_id) REFERENCES canonico.tenant (tenant_id),
    FOREIGN KEY (tenant_id, carga_id)
        REFERENCES canonico.carga_ingestao (tenant_id, id),

    CONSTRAINT unidade_origem_unica UNIQUE (tenant_id, origem_sistema, origem_id),
    CONSTRAINT unidade_codigo_unico UNIQUE (tenant_id, codigo),
    CONSTRAINT unidade_tenant_id_unico UNIQUE (tenant_id, id)
);


CREATE TABLE canonico.perfil_veiculo (
    id                    BIGINT        GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tenant_id             TEXT          NOT NULL,
    origem_sistema        TEXT          NOT NULL,
    origem_id             TEXT          NOT NULL,
    carga_id              BIGINT,
    ingerido_em           TIMESTAMPTZ   NOT NULL DEFAULT now(),

    codigo                TEXT          NOT NULL,
    descricao             TEXT          NOT NULL,
    capacidade_peso_kg    NUMERIC(12,3),
    capacidade_volume_m3  NUMERIC(12,4),

    CONSTRAINT perfil_capacidade_peso_positiva
        CHECK (capacidade_peso_kg IS NULL OR capacidade_peso_kg > 0),
    CONSTRAINT perfil_capacidade_volume_positiva
        CHECK (capacidade_volume_m3 IS NULL OR capacidade_volume_m3 > 0),

    FOREIGN KEY (tenant_id) REFERENCES canonico.tenant (tenant_id),
    FOREIGN KEY (tenant_id, carga_id)
        REFERENCES canonico.carga_ingestao (tenant_id, id),

    CONSTRAINT perfil_veiculo_origem_unica UNIQUE (tenant_id, origem_sistema, origem_id),
    CONSTRAINT perfil_veiculo_codigo_unico UNIQUE (tenant_id, codigo),
    CONSTRAINT perfil_veiculo_tenant_id_unico UNIQUE (tenant_id, id)
);


CREATE TABLE canonico.veiculo (
    id                    BIGINT        GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tenant_id             TEXT          NOT NULL,
    origem_sistema        TEXT          NOT NULL,
    origem_id             TEXT          NOT NULL,
    carga_id              BIGINT,
    ingerido_em           TIMESTAMPTZ   NOT NULL DEFAULT now(),

    codigo                TEXT          NOT NULL,
    perfil_id             BIGINT,
    vinculo               TEXT          NOT NULL,
    capacidade_peso_kg    NUMERIC(12,3),
    capacidade_volume_m3  NUMERIC(12,4),
    ativo                 BOOLEAN       NOT NULL DEFAULT true,

    CONSTRAINT veiculo_vinculo_valido
        CHECK (vinculo IN ('proprio', 'agregado', 'terceiro')),
    CONSTRAINT veiculo_capacidade_peso_positiva
        CHECK (capacidade_peso_kg IS NULL OR capacidade_peso_kg > 0),
    CONSTRAINT veiculo_capacidade_volume_positiva
        CHECK (capacidade_volume_m3 IS NULL OR capacidade_volume_m3 > 0),

    FOREIGN KEY (tenant_id) REFERENCES canonico.tenant (tenant_id),
    FOREIGN KEY (tenant_id, carga_id)
        REFERENCES canonico.carga_ingestao (tenant_id, id),
    FOREIGN KEY (tenant_id, perfil_id)
        REFERENCES canonico.perfil_veiculo (tenant_id, id),

    CONSTRAINT veiculo_origem_unica UNIQUE (tenant_id, origem_sistema, origem_id),
    CONSTRAINT veiculo_codigo_unico UNIQUE (tenant_id, codigo),
    CONSTRAINT veiculo_tenant_id_unico UNIQUE (tenant_id, id)
);

COMMENT ON COLUMN canonico.veiculo.capacidade_peso_kg IS
    'Capacidade do veículo específico. Precedência sobre a do perfil, que é o '
    'fallback. As duas existem para que o pré-requisito de R-001 tenha contra o '
    'que comparar ao detectar cadastro de capacidade furado.';

COMMENT ON COLUMN canonico.veiculo.perfil_id IS
    'Nulo é informação, não lacuna a preencher: viagem de veículo sem perfil é '
    'viagem que R-001 não consegue calibrar.';


CREATE TABLE canonico.motorista (
    id              BIGINT      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tenant_id       TEXT        NOT NULL,
    origem_sistema  TEXT        NOT NULL,
    origem_id       TEXT        NOT NULL,
    carga_id        BIGINT,
    ingerido_em     TIMESTAMPTZ NOT NULL DEFAULT now(),

    codigo          TEXT        NOT NULL,
    nome            TEXT,
    vinculo         TEXT        NOT NULL,
    ativo           BOOLEAN     NOT NULL DEFAULT true,

    CONSTRAINT motorista_vinculo_valido
        CHECK (vinculo IN ('funcionario', 'agregado', 'terceiro')),

    FOREIGN KEY (tenant_id) REFERENCES canonico.tenant (tenant_id),
    FOREIGN KEY (tenant_id, carga_id)
        REFERENCES canonico.carga_ingestao (tenant_id, id),

    CONSTRAINT motorista_origem_unica UNIQUE (tenant_id, origem_sistema, origem_id),
    CONSTRAINT motorista_codigo_unico UNIQUE (tenant_id, codigo),
    CONSTRAINT motorista_tenant_id_unico UNIQUE (tenant_id, id)
);

COMMENT ON TABLE canonico.motorista IS
    'Sem CPF, CNH ou qualquer documento de pessoa física. R-004 precisa apenas '
    'reconciliar dois caminhos de pagamento pelo mesmo motorista, e um código '
    'opaco estável faz isso. O que não entra no modelo não vaza.';


CREATE TABLE canonico.cliente (
    id                      BIGINT      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tenant_id               TEXT        NOT NULL,
    origem_sistema          TEXT        NOT NULL,
    origem_id               TEXT        NOT NULL,
    carga_id                BIGINT,
    ingerido_em             TIMESTAMPTZ NOT NULL DEFAULT now(),

    codigo                  TEXT        NOT NULL,
    nome                    TEXT,
    segmento                TEXT,
    unidade_atendimento_id  BIGINT,

    FOREIGN KEY (tenant_id) REFERENCES canonico.tenant (tenant_id),
    FOREIGN KEY (tenant_id, carga_id)
        REFERENCES canonico.carga_ingestao (tenant_id, id),
    FOREIGN KEY (tenant_id, unidade_atendimento_id)
        REFERENCES canonico.unidade (tenant_id, id),

    CONSTRAINT cliente_origem_unica UNIQUE (tenant_id, origem_sistema, origem_id),
    CONSTRAINT cliente_codigo_unico UNIQUE (tenant_id, codigo),
    CONSTRAINT cliente_tenant_id_unico UNIQUE (tenant_id, id)
);


CREATE TABLE canonico.rota (
    id                 BIGINT      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tenant_id          TEXT        NOT NULL,
    origem_sistema     TEXT        NOT NULL,
    origem_id          TEXT        NOT NULL,
    carga_id           BIGINT,
    ingerido_em        TIMESTAMPTZ NOT NULL DEFAULT now(),

    codigo             TEXT        NOT NULL,
    origem_unidade_id  BIGINT,
    destino_cidade     TEXT,
    destino_uf         TEXT,
    tipo               TEXT        NOT NULL,

    CONSTRAINT rota_tipo_valido
        CHECK (tipo IN ('transferencia', 'distribuicao', 'coleta', 'dedicado')),
    CONSTRAINT rota_uf_valida
        CHECK (destino_uf ~ '^[A-Z]{2}$'),

    FOREIGN KEY (tenant_id) REFERENCES canonico.tenant (tenant_id),
    FOREIGN KEY (tenant_id, carga_id)
        REFERENCES canonico.carga_ingestao (tenant_id, id),
    FOREIGN KEY (tenant_id, origem_unidade_id)
        REFERENCES canonico.unidade (tenant_id, id),

    CONSTRAINT rota_origem_unica UNIQUE (tenant_id, origem_sistema, origem_id),
    CONSTRAINT rota_codigo_unico UNIQUE (tenant_id, codigo),
    CONSTRAINT rota_tenant_id_unico UNIQUE (tenant_id, id)
);

COMMENT ON COLUMN canonico.rota.tipo IS
    'Separa transferência de distribuição. Insumo direto do pré-requisito de '
    'R-007: se as duas caírem na mesma rubrica, a regra não é apurável.';


CREATE TABLE canonico.categoria_despesa (
    id                      BIGINT      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tenant_id               TEXT        NOT NULL,
    origem_sistema          TEXT        NOT NULL,
    origem_id               TEXT        NOT NULL,
    carga_id                BIGINT,
    ingerido_em             TIMESTAMPTZ NOT NULL DEFAULT now(),

    codigo                  TEXT        NOT NULL,
    descricao               TEXT        NOT NULL,
    grupo                   TEXT        NOT NULL,
    eh_hora_extra           BOOLEAN     NOT NULL DEFAULT false,
    eh_pagamento_motorista  BOOLEAN     NOT NULL DEFAULT false,
    permite_rateio          BOOLEAN     NOT NULL DEFAULT false,

    CONSTRAINT categoria_grupo_valido
        CHECK (grupo IN ('folha', 'transferencia', 'distribuicao',
                         'frete_terceiro', 'manutencao', 'combustivel', 'outros')),

    FOREIGN KEY (tenant_id) REFERENCES canonico.tenant (tenant_id),
    FOREIGN KEY (tenant_id, carga_id)
        REFERENCES canonico.carga_ingestao (tenant_id, id),

    CONSTRAINT categoria_despesa_origem_unica UNIQUE (tenant_id, origem_sistema, origem_id),
    CONSTRAINT categoria_despesa_codigo_unico UNIQUE (tenant_id, codigo),
    CONSTRAINT categoria_despesa_tenant_id_unico UNIQUE (tenant_id, id)
);

COMMENT ON TABLE canonico.categoria_despesa IS
    'As flags booleanas são o que transforma os pré-requisitos de R-006 e R-007 '
    'em consulta em vez de opinião. Nenhuma linha com eh_hora_extra = true '
    'significa NAO_APURAVEL, verificável antes de qualquer cálculo.';


CREATE TABLE canonico.tipo_ocorrencia (
    id              BIGINT      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tenant_id       TEXT        NOT NULL,
    origem_sistema  TEXT        NOT NULL,
    origem_id       TEXT        NOT NULL,
    carga_id        BIGINT,
    ingerido_em     TIMESTAMPTZ NOT NULL DEFAULT now(),

    codigo          TEXT        NOT NULL,
    descricao       TEXT        NOT NULL,
    natureza        TEXT        NOT NULL,
    indenizavel     BOOLEAN     NOT NULL DEFAULT true,

    CONSTRAINT tipo_ocorrencia_natureza_valida
        CHECK (natureza IN ('avaria', 'extravio', 'roubo', 'atraso', 'outros')),

    FOREIGN KEY (tenant_id) REFERENCES canonico.tenant (tenant_id),
    FOREIGN KEY (tenant_id, carga_id)
        REFERENCES canonico.carga_ingestao (tenant_id, id),

    CONSTRAINT tipo_ocorrencia_origem_unica UNIQUE (tenant_id, origem_sistema, origem_id),
    CONSTRAINT tipo_ocorrencia_codigo_unico UNIQUE (tenant_id, codigo),
    CONSTRAINT tipo_ocorrencia_tenant_id_unico UNIQUE (tenant_id, id)
);


CREATE TABLE canonico.apolice (
    id                   BIGINT        GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tenant_id            TEXT          NOT NULL,
    origem_sistema       TEXT          NOT NULL,
    origem_id            TEXT          NOT NULL,
    carga_id             BIGINT,
    ingerido_em          TIMESTAMPTZ   NOT NULL DEFAULT now(),

    codigo               TEXT          NOT NULL,
    seguradora           TEXT,
    vigencia_inicio      DATE          NOT NULL,
    vigencia_fim         DATE,
    prazo_aviso_dias     INTEGER,
    franquia_valor       NUMERIC(14,2),
    limite_indenizacao   NUMERIC(14,2),

    CONSTRAINT apolice_vigencia_coerente
        CHECK (vigencia_fim IS NULL OR vigencia_fim >= vigencia_inicio),
    CONSTRAINT apolice_prazo_positivo
        CHECK (prazo_aviso_dias IS NULL OR prazo_aviso_dias > 0),

    FOREIGN KEY (tenant_id) REFERENCES canonico.tenant (tenant_id),
    FOREIGN KEY (tenant_id, carga_id)
        REFERENCES canonico.carga_ingestao (tenant_id, id),

    CONSTRAINT apolice_origem_unica UNIQUE (tenant_id, origem_sistema, origem_id),
    CONSTRAINT apolice_codigo_unico UNIQUE (tenant_id, codigo),
    CONSTRAINT apolice_tenant_id_unico UNIQUE (tenant_id, id)
);

COMMENT ON COLUMN canonico.apolice.prazo_aviso_dias IS
    'Nulo é o gatilho de NAO_APURAVEL de R-005(a). Nunca assumir 30.';
