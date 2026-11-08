-- Funções da sessão. Os vazios viram NULL. Formatos inválidos interrompem a carga.
CREATE OR REPLACE FUNCTION pg_temp.limpar(texto TEXT)
RETURNS TEXT LANGUAGE SQL IMMUTABLE STRICT AS $$
    SELECT NULLIF(btrim(texto), '')
$$;

CREATE OR REPLACE FUNCTION pg_temp.decimal_br(texto TEXT)
RETURNS DECIMAL LANGUAGE SQL IMMUTABLE STRICT AS $$
    SELECT replace(replace(pg_temp.limpar(texto), '.', ''), ',', '.')::DECIMAL
$$;

CREATE OR REPLACE FUNCTION pg_temp.data_br(texto TEXT)
RETURNS DATE LANGUAGE SQL IMMUTABLE STRICT AS $$
    SELECT make_date(
        split_part(pg_temp.limpar(texto), '/', 3)::INT,
        split_part(pg_temp.limpar(texto), '/', 2)::INT,
        split_part(pg_temp.limpar(texto), '/', 1)::INT
    )
$$;

-- Verifica a presença dos dados antes de substituir a Silver.
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM raw_viagem)
        OR NOT EXISTS (SELECT 1 FROM raw_pagamento)
        OR NOT EXISTS (SELECT 1 FROM raw_passagem)
        OR NOT EXISTS (SELECT 1 FROM raw_trecho)
    THEN
        RAISE EXCEPTION 'Carregue os quatro CSVs na Raw antes de rodar a Silver.';
    END IF;
END;
$$;

TRUNCATE silver_viagem, silver_pagamento, silver_passagem, silver_trecho
    RESTART IDENTITY;

WITH viagens AS (
    SELECT DISTINCT ON (pg_temp.limpar(id_viagem))
        pg_temp.limpar(id_viagem) AS id_viagem,
        pg_temp.limpar(num_proposta) AS num_proposta,
        pg_temp.limpar(situacao) AS situacao,
        pg_temp.limpar(viagem_urgente) AS viagem_urgente,
        pg_temp.limpar(cod_orgao_superior) AS cod_orgao_superior,
        pg_temp.limpar(nome_orgao_superior) AS nome_orgao_superior,
        pg_temp.limpar(nome_viajante) AS nome_viajante,
        pg_temp.limpar(cargo) AS cargo,
        pg_temp.data_br(data_inicio) AS data_inicio,
        pg_temp.data_br(data_fim) AS data_fim,
        pg_temp.limpar(destinos) AS destinos,
        pg_temp.limpar(motivo) AS motivo,
        pg_temp.decimal_br(valor_diarias) AS valor_diarias,
        pg_temp.decimal_br(valor_passagens) AS valor_passagens,
        pg_temp.decimal_br(valor_devolucao) AS valor_devolucao,
        pg_temp.decimal_br(valor_outros_gastos) AS valor_outros_gastos
    FROM raw_viagem
    WHERE pg_temp.limpar(id_viagem) IS NOT NULL
      AND pg_temp.limpar(nome_orgao_superior) IS NOT NULL
    ORDER BY pg_temp.limpar(id_viagem), ctid
)
INSERT INTO silver_viagem (
    id_viagem, num_proposta, situacao, viagem_urgente, cod_orgao_superior,
    nome_orgao_superior, nome_viajante, cargo, data_inicio, data_fim,
    destinos, motivo, valor_diarias, valor_passagens, valor_devolucao,
    valor_outros_gastos, valor_total, duracao_dias
)
SELECT
    id_viagem, num_proposta, situacao, viagem_urgente, cod_orgao_superior,
    nome_orgao_superior, nome_viajante, cargo, data_inicio, data_fim,
    destinos, motivo, valor_diarias, valor_passagens, valor_devolucao,
    valor_outros_gastos,
    CASE WHEN num_nonnulls(
        valor_diarias, valor_passagens, valor_outros_gastos, valor_devolucao
    ) > 0 THEN
        COALESCE(valor_diarias, 0) + COALESCE(valor_passagens, 0)
        + COALESCE(valor_outros_gastos, 0) - COALESCE(valor_devolucao, 0)
    END,
    CASE WHEN data_fim >= data_inicio THEN data_fim - data_inicio END
FROM viagens;

-- O filtro por JOIN deixa na Raw os registros sem uma viagem correspondente.
-- Nos CSVs sem ID próprio, removemos apenas repetições de toda a linha Raw.
INSERT INTO silver_pagamento (
    id_viagem, num_proposta, nome_orgao_pagador, nome_ug_pagadora,
    tipo_pagamento, valor
)
SELECT
    v.id_viagem, pg_temp.limpar(r.num_proposta),
    pg_temp.limpar(r.nome_orgao_pagador), pg_temp.limpar(r.nome_ug_pagadora),
    pg_temp.limpar(r.tipo_pagamento), pg_temp.decimal_br(r.valor)
FROM (SELECT DISTINCT * FROM raw_pagamento) AS r
JOIN silver_viagem AS v ON v.id_viagem = pg_temp.limpar(r.id_viagem)
WHERE pg_temp.limpar(r.tipo_pagamento) IS NOT NULL;

INSERT INTO silver_passagem (
    id_viagem, meio_transporte, pais_origem_ida, uf_origem_ida,
    cidade_origem_ida, pais_destino_ida, uf_destino_ida, cidade_destino_ida,
    valor_passagem, taxa_servico, data_emissao
)
SELECT
    v.id_viagem, pg_temp.limpar(r.meio_transporte),
    pg_temp.limpar(r.pais_origem_ida), pg_temp.limpar(r.uf_origem_ida),
    pg_temp.limpar(r.cidade_origem_ida), pg_temp.limpar(r.pais_destino_ida),
    pg_temp.limpar(r.uf_destino_ida), pg_temp.limpar(r.cidade_destino_ida),
    pg_temp.decimal_br(r.valor_passagem), pg_temp.decimal_br(r.taxa_servico),
    pg_temp.data_br(r.data_emissao)
FROM (SELECT DISTINCT * FROM raw_passagem) AS r
JOIN silver_viagem AS v ON v.id_viagem = pg_temp.limpar(r.id_viagem);

WITH trechos AS (
    SELECT DISTINCT ON (v.id_viagem, pg_temp.limpar(r.sequencia_trecho)::INT)
        v.id_viagem, pg_temp.limpar(r.sequencia_trecho)::INT AS sequencia_trecho,
        pg_temp.data_br(r.origem_data) AS origem_data,
        pg_temp.limpar(r.origem_uf) AS origem_uf,
        pg_temp.limpar(r.origem_cidade) AS origem_cidade,
        pg_temp.data_br(r.destino_data) AS destino_data,
        pg_temp.limpar(r.destino_uf) AS destino_uf,
        pg_temp.limpar(r.destino_cidade) AS destino_cidade,
        pg_temp.limpar(r.meio_transporte) AS meio_transporte,
        pg_temp.decimal_br(r.numero_diarias) AS numero_diarias
    FROM raw_trecho AS r
    JOIN silver_viagem AS v ON v.id_viagem = pg_temp.limpar(r.id_viagem)
    WHERE pg_temp.limpar(r.sequencia_trecho) IS NOT NULL
    ORDER BY v.id_viagem, pg_temp.limpar(r.sequencia_trecho)::INT, r.ctid
)
INSERT INTO silver_trecho (
    id_viagem, sequencia_trecho, origem_data, origem_uf, origem_cidade,
    destino_data, destino_uf, destino_cidade, meio_transporte, numero_diarias
)
SELECT
    id_viagem, sequencia_trecho, origem_data, origem_uf, origem_cidade,
    destino_data, destino_uf, destino_cidade, meio_transporte, numero_diarias
FROM trechos;

ANALYZE silver_viagem;
ANALYZE silver_pagamento;
ANALYZE silver_passagem;
ANALYZE silver_trecho;
