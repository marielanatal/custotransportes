-- Calibração e responsabilização.
-- Referência: Docs/modelo-canonico.md, seções 3 e 4.


-- Todo parâmetro calibrável do catálogo. Nenhum limite, teto, janela ou
-- percentual mora em código.
CREATE TABLE canonico.parametro_calibracao (
    id               BIGINT         GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tenant_id        TEXT           NOT NULL,
    origem_sistema   TEXT           NOT NULL,
    origem_id        TEXT           NOT NULL,
    carga_id         BIGINT,
    ingerido_em      TIMESTAMPTZ    NOT NULL DEFAULT now(),

    chave            TEXT           NOT NULL,
    escopo           TEXT           NOT NULL,
    unidade_id       BIGINT,
    perfil_id        BIGINT,
    valor_num        NUMERIC(18,6),
    valor_texto      TEXT,
    procedencia      TEXT           NOT NULL,
    amostras         INTEGER,
    calibrado_em     TIMESTAMPTZ,
    vigencia_inicio  DATE           NOT NULL,
    vigencia_fim     DATE,

    CONSTRAINT parametro_escopo_valido
        CHECK (escopo IN ('unidade_perfil', 'perfil', 'global')),
    CONSTRAINT parametro_procedencia_valida
        CHECK (procedencia IN ('calibrado', 'manual', 'padrao')),

    -- Exatamente um dos dois valores. Parâmetro sem valor, ou com os dois,
    -- é linha que a resolução de fallback leria e devolveria lixo.
    CONSTRAINT parametro_valor_unico
        CHECK (num_nonnulls(valor_num, valor_texto) = 1),

    -- O escopo determina quais chaves precisam estar preenchidas. Sem isto,
    -- uma linha 'global' com unidade_id preenchido nunca seria alcançada pela
    -- consulta de resolução, e o silêncio seria indistinguível de acerto.
    CONSTRAINT parametro_escopo_coerente CHECK (
        (escopo = 'unidade_perfil' AND unidade_id IS NOT NULL AND perfil_id IS NOT NULL)
     OR (escopo = 'perfil'         AND unidade_id IS NULL     AND perfil_id IS NOT NULL)
     OR (escopo = 'global'         AND unidade_id IS NULL     AND perfil_id IS NULL)
    ),

    CONSTRAINT parametro_vigencia_coerente
        CHECK (vigencia_fim IS NULL OR vigencia_fim >= vigencia_inicio),
    CONSTRAINT parametro_amostras_nao_negativas
        CHECK (amostras IS NULL OR amostras >= 0),

    -- Parâmetro calibrado sem contagem de amostras não é auditável: não dá para
    -- saber se saiu de 400 viagens ou de 3.
    CONSTRAINT parametro_calibrado_tem_amostras
        CHECK (procedencia <> 'calibrado' OR amostras IS NOT NULL),

    FOREIGN KEY (tenant_id) REFERENCES canonico.tenant (tenant_id),
    FOREIGN KEY (tenant_id, carga_id)
        REFERENCES canonico.carga_ingestao (tenant_id, id),
    FOREIGN KEY (tenant_id, unidade_id)
        REFERENCES canonico.unidade (tenant_id, id),
    FOREIGN KEY (tenant_id, perfil_id)
        REFERENCES canonico.perfil_veiculo (tenant_id, id),

    CONSTRAINT parametro_origem_unica UNIQUE (tenant_id, origem_sistema, origem_id),
    CONSTRAINT parametro_tenant_id_unico UNIQUE (tenant_id, id)
);

-- No máximo um parâmetro em aberto por chave e escopo. Duas linhas vigentes ao
-- mesmo tempo fariam a resolução escolher uma arbitrariamente, e o achado
-- deixaria de ser reproduzível sem nenhum erro aparecer.
-- NULLS NOT DISTINCT trata os nulos de escopo 'global' e 'perfil' como iguais.
CREATE UNIQUE INDEX parametro_vigente_unico_idx
    ON canonico.parametro_calibracao (tenant_id, chave, escopo, unidade_id, perfil_id)
    NULLS NOT DISTINCT
    WHERE vigencia_fim IS NULL;

CREATE INDEX parametro_resolucao_idx
    ON canonico.parametro_calibracao (tenant_id, chave, vigencia_inicio);

COMMENT ON TABLE canonico.parametro_calibracao IS
    'Recalibrar nunca é UPDATE: fecha-se a vigência anterior e insere-se linha '
    'nova. Um achado apresentado em março precisa ser reproduzível em julho.';

COMMENT ON COLUMN canonico.parametro_calibracao.procedencia IS
    'calibrado = saiu da mediana observada com amostras suficientes; manual = o '
    'cliente definiu; padrao = chute inicial nosso. Achado gerado sob parâmetro '
    'padrao sai com ressalva, não como fato.';


-- Parâmetros que são lista, não escalar: motivos de liberação aceitos (R-002),
-- composição do custo de transferência (R-007), exceções legítimas de
-- pagamento (R-004).
CREATE TABLE canonico.parametro_calibracao_item (
    id            BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    parametro_id  BIGINT NOT NULL
                  REFERENCES canonico.parametro_calibracao (id) ON DELETE CASCADE,
    item          TEXT   NOT NULL,

    CONSTRAINT parametro_item_unico UNIQUE (parametro_id, item)
);


-- Quem trata o achado. O campo "Dono" de cada regra do catálogo é dado que
-- muda, não constante em código.
CREATE TABLE canonico.responsavel (
    id               BIGINT      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tenant_id        TEXT        NOT NULL,
    origem_sistema   TEXT        NOT NULL,
    origem_id        TEXT        NOT NULL,
    carga_id         BIGINT,
    ingerido_em      TIMESTAMPTZ NOT NULL DEFAULT now(),

    papel            TEXT        NOT NULL,
    unidade_id       BIGINT,
    nome             TEXT        NOT NULL,
    contato          TEXT,
    vigencia_inicio  DATE        NOT NULL,
    vigencia_fim     DATE,

    CONSTRAINT responsavel_papel_valido
        CHECK (papel IN ('supervisor_base', 'gestor_unidade', 'financeiro',
                         'comercial', 'qualidade', 'planejamento', 'direcao')),
    CONSTRAINT responsavel_vigencia_coerente
        CHECK (vigencia_fim IS NULL OR vigencia_fim >= vigencia_inicio),

    FOREIGN KEY (tenant_id) REFERENCES canonico.tenant (tenant_id),
    FOREIGN KEY (tenant_id, carga_id)
        REFERENCES canonico.carga_ingestao (tenant_id, id),
    FOREIGN KEY (tenant_id, unidade_id)
        REFERENCES canonico.unidade (tenant_id, id),

    CONSTRAINT responsavel_origem_unica UNIQUE (tenant_id, origem_sistema, origem_id),
    CONSTRAINT responsavel_tenant_id_unico UNIQUE (tenant_id, id)
);

COMMENT ON COLUMN canonico.responsavel.unidade_id IS
    'Nulo = responsável corporativo, vale para todas as unidades.';


-- Resolução do fallback de escopo: unidade + perfil -> perfil -> global.
--
-- Escrita uma vez, aqui. Nenhuma regra reimplementa isto: fallback duplicado
-- diverge, e a divergência só aparece em reunião com cliente.
--
-- O corte por volume mínimo de amostras é responsabilidade de quem GRAVA o
-- parâmetro — o calibrador não insere linha de escopo específico sem amostras
-- suficientes, e esta consulta cai sozinha no nível seguinte.
CREATE FUNCTION canonico.parametro_vigente(
    p_tenant_id  TEXT,
    p_chave      TEXT,
    p_data_ref   DATE,
    p_unidade_id BIGINT DEFAULT NULL,
    p_perfil_id  BIGINT DEFAULT NULL
)
RETURNS TABLE (
    valor_num    NUMERIC,
    valor_texto  TEXT,
    procedencia  TEXT,
    amostras     INTEGER,
    escopo       TEXT
)
LANGUAGE sql
STABLE
AS $$
    SELECT p.valor_num, p.valor_texto, p.procedencia, p.amostras, p.escopo
      FROM canonico.parametro_calibracao p
     WHERE p.tenant_id = p_tenant_id
       AND p.chave     = p_chave
       AND p_data_ref BETWEEN p.vigencia_inicio
                          AND COALESCE(p.vigencia_fim, DATE '9999-12-31')
       AND (   (p.escopo = 'unidade_perfil' AND p.unidade_id = p_unidade_id
                                            AND p.perfil_id  = p_perfil_id)
            OR (p.escopo = 'perfil'         AND p.perfil_id  = p_perfil_id)
            OR (p.escopo = 'global') )
     ORDER BY CASE p.escopo
                  WHEN 'unidade_perfil' THEN 1
                  WHEN 'perfil'         THEN 2
                  ELSE 3
              END
     LIMIT 1;
$$;

COMMENT ON FUNCTION canonico.parametro_vigente IS
    'Devolve zero linhas quando não há parâmetro em nenhum escopo. Quem chama '
    'trata isso como pré-requisito não atendido, nunca como valor zero.';
