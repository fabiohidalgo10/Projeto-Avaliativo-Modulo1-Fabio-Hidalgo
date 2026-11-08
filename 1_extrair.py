"""Baixa a fonte e carrega as quatro tabelas Raw em uma transação."""

import argparse
import csv
import io
import logging
import sys
from contextlib import ExitStack
from itertools import islice
from pathlib import Path, PurePosixPath
from tempfile import TemporaryDirectory
from zipfile import ZipFile

import gdown
from psycopg import sql

from banco import CHAVE_PIPELINE, conectar, executar
from config import (
    ARQUIVOS,
    CSV_ENCODING,
    CSV_SEPARADOR,
    DRIVE_FILE_ID,
    PASTA_DADOS,
    TAMANHO_BLOCO,
)

LOG = logging.getLogger(__name__)


def baixar_zip():
    """Baixa o ZIP pelo ID do arquivo e valida o formato antes de guardar."""
    PASTA_DADOS.mkdir(exist_ok=True)
    destino = PASTA_DADOS / "viagens_2025.zip"
    with TemporaryDirectory(dir=PASTA_DADOS) as pasta:
        temporario = Path(pasta) / destino.name
        obtido = gdown.download(
            id=DRIVE_FILE_ID, output=str(temporario), quiet=False, resume=False
        )
        if not obtido:
            raise RuntimeError("O download do ZIP falhou. Confira o acesso no Drive.")
        with ZipFile(temporario):
            pass
        temporario.replace(destino)
    return destino


def abrir_arquivos(pilha, pasta, caminho_zip):
    """Abre os CSVs diretamente da pasta ou de dentro do ZIP."""
    if pasta is not None:
        return {
            nome: pilha.enter_context(
                (pasta / nome).open(encoding=CSV_ENCODING, newline="")
            )
            for nome in ARQUIVOS
        }

    zip_dados = pilha.enter_context(ZipFile(caminho_zip))
    membros = {}
    for membro in zip_dados.infolist():
        nome = PurePosixPath(membro.filename).name
        if membro.is_dir() or nome not in ARQUIVOS:
            continue
        if nome in membros:
            raise ValueError(f"Há mais de um {nome} dentro do ZIP.")
        membros[nome] = membro
    faltam = set(ARQUIVOS) - membros.keys()
    if faltam:
        raise ValueError(f"CSV(s) ausente(s) no ZIP: {', '.join(sorted(faltam))}")
    return {
        nome: pilha.enter_context(
            io.TextIOWrapper(zip_dados.open(membro), CSV_ENCODING, newline="")
        )
        for nome, membro in membros.items()
    }


def carregar_tabela(conexao, arquivo, nome_csv):
    tabela, mapeamento = ARQUIVOS[nome_csv]
    linhas = csv.reader(arquivo, delimiter=CSV_SEPARADOR, strict=True)
    if next(linhas, None) != list(mapeamento):
        raise ValueError(f"Cabeçalho diferente do esperado em {nome_csv}.")

    comando = sql.SQL("COPY {} ({}) FROM STDIN").format(
        sql.Identifier(tabela),
        sql.SQL(", ").join(map(sql.Identifier, mapeamento.values())),
    )
    total = 0
    with conexao.cursor() as cursor, cursor.copy(comando) as carga:
        while bloco := list(islice(linhas, TAMANHO_BLOCO)):
            for linha in bloco:
                if len(linha) != len(mapeamento):
                    raise ValueError(
                        f"Quantidade de campos incorreta em {nome_csv}, "
                        f"registro {total + 1}."
                    )
                carga.write_row(linha)
                total += 1
    if total == 0:
        raise ValueError(f"O CSV {nome_csv} não contém registros.")
    return total


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    fonte = parser.add_mutually_exclusive_group()
    fonte.add_argument("--csv-dir", type=Path, help="Pasta com os quatro CSVs.")
    fonte.add_argument("--zip", type=Path, help="ZIP já baixado.")
    args = parser.parse_args()

    try:
        caminho_zip = args.zip
        if args.csv_dir is None and caminho_zip is None:
            caminho_zip = baixar_zip()

        with ExitStack() as pilha:
            arquivos = abrir_arquivos(pilha, args.csv_dir, caminho_zip)
            with conectar() as conexao:
                executar(conexao, "SELECT pg_advisory_xact_lock(%s)", (CHAVE_PIPELINE,))
                tabelas = sql.SQL(", ").join(
                    sql.Identifier(tabela) for tabela, _ in ARQUIVOS.values()
                )
                executar(conexao, sql.SQL("TRUNCATE TABLE {}").format(tabelas))
                for nome, arquivo in arquivos.items():
                    total = carregar_tabela(conexao, arquivo, nome)
                    LOG.info("%s: %s registros processados", nome, total)
        LOG.info("Carga Raw confirmada.")
        return 0
    except Exception as erro:
        LOG.error("Carga Raw interrompida. Nenhuma alteração parcial foi gravada. %s", erro)
        return 1


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
    sys.exit(main())
