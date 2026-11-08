"""Conexão e execução de comandos PostgreSQL."""

import psycopg

from config import POSTGRES_CONFIG

# As etapas usam a mesma trava para evitar ler uma carga em andamento.
CHAVE_PIPELINE = 202501


def conectar():
    """Abre uma conexão. O chamador controla a transação."""
    try:
        return psycopg.connect(**POSTGRES_CONFIG)
    except psycopg.Error as erro:
        raise RuntimeError(
            "Falha ao conectar ao PostgreSQL. Confira o serviço, o .env e a "
            "criação do banco transparencia."
        ) from erro


def executar(conexao, sql, parametros=None):
    """Executa um comando SQL na transação do chamador."""
    return conexao.execute(sql, parametros)
