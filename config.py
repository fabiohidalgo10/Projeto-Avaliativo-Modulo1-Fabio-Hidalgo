"""Parâmetros da conexão e da origem dos dados."""

import os
from pathlib import Path

from dotenv import load_dotenv

from layout_csv import ARQUIVOS

PASTA_RAIZ = Path(__file__).resolve().parent
PASTA_DADOS = PASTA_RAIZ / "data"
load_dotenv(PASTA_RAIZ / ".env")

POSTGRES_CONFIG = {
    "host": os.getenv("PGHOST", "localhost"),
    "port": int(os.getenv("PGPORT", "5432")),
    "user": os.getenv("PGUSER", "postgres"),
    "password": os.getenv("PGPASSWORD", ""),
    "dbname": os.getenv("PGDATABASE", "transparencia"),
    "connect_timeout": 10,
}
# ID do ZIP viagens_2025_6meses.zip indicado no enunciado.
DRIVE_FILE_ID = os.getenv("DRIVE_FILE_ID", "").strip() or "1pQjKacyHdIsyteknQbwKGM5_4hL5V4RV"
TAMANHO_BLOCO = 50_000
CSV_SEPARADOR = ";"
CSV_ENCODING = "latin-1"
