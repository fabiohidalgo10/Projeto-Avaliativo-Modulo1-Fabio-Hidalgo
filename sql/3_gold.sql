-- Cada agrupamento usa uma única tabela filha para evitar multiplicar registros.
CREATE OR REPLACE VIEW vw_gold_indicadores AS
WITH ufs (sigla, nome) AS (
    VALUES
        ('AC', 'Acre'), ('AL', 'Alagoas'), ('AP', 'Amapá'),
        ('AM', 'Amazonas'), ('BA', 'Bahia'), ('CE', 'Ceará'),
        ('DF', 'Distrito Federal'), ('ES', 'Espírito Santo'),
        ('GO', 'Goiás'), ('MA', 'Maranhão'), ('MT', 'Mato Grosso'),
        ('MS', 'Mato Grosso do Sul'), ('MG', 'Minas Gerais'),
        ('PA', 'Pará'), ('PB', 'Paraíba'), ('PR', 'Paraná'),
        ('PE', 'Pernambuco'), ('PI', 'Piauí'), ('RJ', 'Rio de Janeiro'),
        ('RN', 'Rio Grande do Norte'), ('RS', 'Rio Grande do Sul'),
        ('RO', 'Rondônia'), ('RR', 'Roraima'), ('SC', 'Santa Catarina'),
        ('SP', 'São Paulo'), ('SE', 'Sergipe'), ('TO', 'Tocantins')
)
SELECT
    'pagamento_por_tipo'::TEXT AS indicador,
    p.tipo_pagamento::TEXT AS categoria,
    count(p.valor) AS quantidade,
    sum(p.valor) AS total,
    avg(p.valor) AS media
FROM silver_pagamento AS p
JOIN silver_viagem AS v USING (id_viagem)
WHERE p.valor IS NOT NULL
GROUP BY p.tipo_pagamento

UNION ALL

SELECT
    'transporte_por_trecho', t.meio_transporte, count(*),
    NULL::NUMERIC, NULL::NUMERIC
FROM silver_trecho AS t
JOIN silver_viagem AS v USING (id_viagem)
WHERE t.meio_transporte IS NOT NULL AND t.meio_transporte <> 'Inválido'
GROUP BY t.meio_transporte

UNION ALL

SELECT
    'uf_destino_por_trecho', u.sigla, count(*),
    NULL::NUMERIC, NULL::NUMERIC
FROM silver_trecho AS t
JOIN silver_viagem AS v USING (id_viagem)
JOIN ufs AS u ON t.destino_uf IN (u.nome, u.sigla)
GROUP BY u.sigla

UNION ALL

SELECT
    'pagamento_por_orgao', p.nome_orgao_pagador, count(p.valor),
    sum(p.valor), avg(p.valor)
FROM silver_pagamento AS p
JOIN silver_viagem AS v USING (id_viagem)
WHERE p.nome_orgao_pagador IS NOT NULL AND p.valor IS NOT NULL
GROUP BY p.nome_orgao_pagador;

CREATE TABLE IF NOT EXISTS gold_indicadores (
    indicador TEXT NOT NULL,
    categoria TEXT NOT NULL,
    quantidade BIGINT NOT NULL,
    total NUMERIC,
    media NUMERIC,
    PRIMARY KEY (indicador, categoria)
);

TRUNCATE TABLE gold_indicadores;

INSERT INTO gold_indicadores (indicador, categoria, quantidade, total, media)
SELECT indicador, categoria, quantidade, total, media
FROM vw_gold_indicadores;
