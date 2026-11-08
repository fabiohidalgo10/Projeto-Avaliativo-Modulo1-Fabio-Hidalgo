# Viagens a Serviço do Governo Federal

Projeto Avaliativo do Módulo 1 de Análise de Dados com Python [T6]. O pipeline transforma o recorte de janeiro a junho de 2025 em indicadores de gastos e deslocamentos. A fonte é a base de Viagens a Serviço do Portal da Transparência, distribuída no ZIP da atividade.

| Fase | Execução | Resultado |
|---|---|---|
| 0 | `0_criar_banco.sql` | Banco `transparencia`, quatro tabelas Raw e quatro tabelas Silver |
| 1 | `1_extrair.py` | Carga em blocos de até 50 mil linhas, com `COPY` e `TRUNCATE` na mesma transação |
| 2 | `2_transformar.py` | Limpeza e tipagem com `sql/2_silver.sql`, chaves e colunas calculadas |
| 3 | `3_analise.ipynb` | Sete respostas, seis gráficos, view `vw_gold_indicadores` e tabela `gold_indicadores` |

O projeto usa Python, PostgreSQL, Psycopg, Jupyter, Pandas e Matplotlib. O pgAdmin é usado para executar e verificar o SQL no Windows.

## 1. Preparar o ambiente no Windows

Instale [Python 3.11 ou 3.12](https://www.python.org/downloads/windows/), [PostgreSQL com pgAdmin](https://www.postgresql.org/download/windows/) e [Git](https://git-scm.com/download/win). Guarde a senha escolhida para o usuário `postgres` durante a instalação. Confira a porta do servidor, geralmente `5432`.

Abra o PowerShell na pasta que contém este README e execute:

```powershell
py -3.12 -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
Copy-Item .env.example .env
notepad .env
```

Se instalou Python 3.11, use `py -3.11` na primeira linha. No `.env`, preencha `PGPASSWORD` com a senha do PostgreSQL e ajuste o usuário ou a porta se forem diferentes. O nome do banco é `transparencia`.

## 2. Criar o banco e as oito tabelas

No pgAdmin, conecte ao servidor local e abra o **Query Tool** do banco padrão `postgres`. Execute apenas este comando:

```sql
CREATE DATABASE transparencia;
```

Se o banco já existir, prossiga para ele. Atualize a lista **Databases**, selecione **transparencia** e abra seu **Query Tool**. Abra `0_criar_banco.sql`, selecione do `BEGIN;` ao `COMMIT;` e execute a seleção com **F5**. Atualize **Schemas → public → Tables**. Devem aparecer quatro tabelas `raw_*` e quatro `silver_*`.

O cabeçalho do arquivo contém comandos próprios do cliente `psql`. Para executar o arquivo inteiro em um terminal com `psql` no PATH, use:

```powershell
psql -h localhost -p 5432 -U postgres -d postgres -f 0_criar_banco.sql
```

## 3. Carregar a Raw

Para executar o **download automático exigido na atividade**, rode o comando
abaixo. O ID de [viagens_2025_6meses.zip](https://drive.google.com/file/d/1pQjKacyHdIsyteknQbwKGM5_4hL5V4RV/view)
já está configurado.  use o campo `DRIVE_FILE_ID` no `.env` para substituir o ID. O ZIP baixado fica na pasta `data`.

```powershell
.\.venv\Scripts\python.exe 1_extrair.py
```

Se quiser usar os CSVs já baixados, crie uma pasta `data` ao lado do README
e coloque nela os quatro arquivos:

- `2025_Viagem.csv`
- `2025_Pagamento.csv`
- `2025_Passagem.csv`
- `2025_Trecho.csv`

```powershell
.\.venv\Scripts\python.exe 1_extrair.py --csv-dir data
```

Se já tiver baixado o ZIP, também é possível passá-lo com `--zip caminho\arquivo.zip`. A carga preserva todos os campos, inclusive valores vazios como texto vazio, vírgulas decimais e datas no formato original. O mapeamento em `layout_csv.py` altera apenas o nome dos cabeçalhos para uso em SQL. Os CSVs usam `;` e `latin-1`.

## 4. Gerar a Silver

```powershell
.\.venv\Scripts\python.exe 2_transformar.py
```

O terminal mostra quantas linhas entraram em cada tabela e a diferença em relação à Raw. As viagens são carregadas antes das tabelas filhas. Registros órfãos e linhas sem campos obrigatórios ficam na Raw. O tratamento mantém a primeira ocorrência por `id_viagem` ou por `(id_viagem, sequencia_trecho)`. Pagamentos e passagens sem chave própria na fonte são de duplicados somente quando todos os campos originais coincidem. Se a fonte trouxer eventos genuinamente diferentes com todos os campos iguais, esse critério pode consolidá-los.

Campos em branco passam a `NULL` na Silver. As funções de tratamento convertem valores brasileiros em decimais e datas em `DATE`. Falhas de conversão ou de constraints abortam a transação. As duas fases de carga podem ser repetidas. Cada fase troca seus dados em uma única transação.

| Coluna calculada | Regra adotada |
|---|---|
| `valor_total` | Diárias + passagens + outros gastos − devoluções. Se houver pelo menos um componente informado, os demais vazios contam como zero. Se todos estiverem vazios, o total fica nulo. |
| `duracao_dias` | Data final menos data inicial, em dias corridos. Viagens no mesmo dia têm duração zero. Datas ausentes ou invertidas geram duração nula. |

## 5. Executar o notebook e conferir a Gold

```powershell
.\.venv\Scripts\python.exe -m notebook
```

No navegador, abra `3_analise.ipynb` e use **Kernel → Restart Kernel and Run All Cells**. Confira as tabelas, os seis gráficos e os comentários com os resultados. Salve o notebook.

No pgAdmin, abra o **Query Tool** de `transparencia` e execute:

```sql
SELECT indicador, count(*) AS categorias
FROM gold_indicadores
GROUP BY indicador
ORDER BY indicador;
```

Devem aparecer os quatro indicadores agregados. A view consulta a Silver atual, e a tabela é atualizada quando a célula de criação da Gold é executada. Se recarregar os dados, rode novamente a Silver e o notebook. O notebook documenta como trata os destinos múltiplos e quais registros entram em cada ranking.

## 6. Publicar e entregar

O pacote de entrega inclui `historico.bundle` e um guia de publicação. O bundle contém as branches e os commits por funcionalidade, prontos para serem recuperados com Git. Crie o repositório com o nome sugerido `Projeto-Avaliativo-Modulo1-Fabio-Hidalgo` e siga o guia para publicar e enviar o link pelo AVA.

O `.env.example` fica no repositório. O `.env`, os CSVs e os ZIPs ficam na pasta local, cobertos pelo `.gitignore`.

## Validação com o recorte da atividade

| Tabela | Linhas Raw | Linhas Silver | Duplicatas exatas removidas |
|---|---:|---:|---:|
| Viagem | 341.860 | 341.860 | 0 |
| Pagamento | 606.916 | 568.811 | 38.105 |
| Passagem | 167.260 | 167.210 | 50 |
| Trecho | 763.349 | 763.349 | 0 |
| **Total** | **1.879.385** | **1.841.230** | **38.155** |

O ZIP do Drive contém os mesmos quatro CSVs usados nesta validação. Foram
verificados o recarregamento da Raw, o rollback após uma entrada inválida
e a igualdade dos dados entre tabela e view da Gold após a atualização.
As tabelas filhas não apresentaram registros órfãos no recorte.

## Conclusões do recorte

- O Ministério da Justiça e Segurança Pública lidera o custo líquido por
  órgão superior, com R$ 486.933.121,65.
- Veículo Oficial é o meio de transporte mais frequente, com 386.424
  trechos. São Paulo lidera o ranking de UFs de destino, com 82.722 trechos.
- A categoria “Sigiloso” concentra o maior valor em pagamentos. Entre os
  órgãos identificados, o Fundo Nacional de Segurança Pública lidera com
  R$ 141.911.719,64. A coluna de órgão pagador e a de órgão superior
  descrevem papéis diferentes.

## Melhorias possíveis

Uma próxima versão pode registrar separadamente as contagens de órfãos, duplicados e campos inválidos. Uma identificação de destino fornecida pela fonte ajudaria a consolidar variações de grafia entre viagens.
