"""Transforma os dados Raw em Silver e resume a quantidade de linhas."""

import logging
import sys

from psycopg import sql

from banco import CHAVE_PIPELINE, conectar, executar
from config import ARQUIVOS, PASTA_RAIZ

LOG = logging.getLogger(__name__)


def main():
    try:
        script = (PASTA_RAIZ / "sql" / "2_silver.sql").read_text(encoding="utf-8")
        contagens = []
        with conectar() as conexao:
            executar(conexao, "SELECT pg_advisory_xact_lock(%s)", (CHAVE_PIPELINE,))
            executar(conexao, script)
            for tabela, _ in ARQUIVOS.values():
                silver = tabela.replace("raw_", "silver_", 1)
                consulta = sql.SQL(
                    "SELECT (SELECT count(*) FROM {}), (SELECT count(*) FROM {})"
                ).format(sql.Identifier(tabela), sql.Identifier(silver))
                raw, limpa = executar(conexao, consulta).fetchone()
                contagens.append((silver, raw, limpa, raw - limpa))
        for nome, raw, limpa, diferenca in contagens:
            LOG.info("%s: Raw=%s | Silver=%s | fora da Silver=%s", nome, raw, limpa, diferenca)
        return 0
    except Exception as erro:
        LOG.error("Carga Silver interrompida. Nenhuma alteração parcial foi gravada. %s", erro)
        return 1


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
    sys.exit(main())
