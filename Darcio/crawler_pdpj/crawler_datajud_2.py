"""
crawler_datajud.py

Coleta processos no DataJud (API pública do CNJ) em todos os tribunais
estaduais (TJs) e federais (TRFs), filtrando pelos códigos de assunto
configurados, e salva um arquivo CSV por combinação (tribunal, ano de
ajuizamento) -- no mesmo formato de entrada usado pelo scraper do PDPJ
(`metadados_{tribunal}_{ano}.csv`, dentro de `trts/`).

Características:
- Checkpoint por (tribunal, ano): se o arquivo de saída já existe, pula.
  Isso permite interromper e retomar o script sem perder trabalho.
- Log de erros separado (`trts/erros_datajud.csv`) para as combinações que
  falharem mesmo após retentativas -- permite reprocessar só o que faltou.
- Retentativas com backoff para falhas transitórias de rede/API.
- Execução sequencial (sem threads): a API pública do DataJud usa, por
  padrão, uma chave compartilhada por todos os usuários do juscraper, com
  limite de 120 requisições/minuto por chave (termo de uso do CNJ).
  Paralelizar aqui arriscaria estourar a cota para todo mundo. Se você
  tiver uma api_key própria com limite maior, dá pra paralelizar por
  tribunal -- me avise que ajusto.

Uso:
    python crawler_datajud.py
"""

import csv
import logging
import time
from datetime import datetime
from pathlib import Path

import juscraper as jus

# ---------------------------------------------------------------- config --

ASSUNTOS = ["6114", "11947", "11946", "6190", "6194"]

# Justiça Estadual (27 TJs)
TRIBUNAIS_ESTADUAIS = [
    "TJAC", "TJAL", "TJAP", "TJAM", "TJBA", "TJCE", "TJDFT", "TJES", "TJGO",
    "TJMA", "TJMG", "TJMS", "TJMT", "TJPA", "TJPB", "TJPR", "TJPE", "TJPI",
    "TJRJ", "TJRN", "TJRS", "TJRO", "TJRR", "TJSC", "TJSP", "TJSE", "TJTO",
]
# Justiça Federal (TRF1-6)
TRIBUNAIS_FEDERAIS = ["TRF1", "TRF2", "TRF3", "TRF4", "TRF5", "TRF6"]

TRIBUNAIS = TRIBUNAIS_FEDERAIS

# Intervalo de anos de ajuizamento a varrer. Ajuste conforme necessário --
# 2009 marca a consolidação da numeração única do CNJ (Resolução 65/2008).
ANO_INICIO = 2015
ANO_FIM = datetime.now().year

OUTPUT_DIR = Path("trts")
ERROS_PATH = OUTPUT_DIR / "erros_datajud.csv"

SLEEP_TIME_PAGINACAO = 1.5   # segundos entre páginas de uma mesma consulta
SLEEP_ENTRE_COMBOS = 1.0     # piso de intervalo entre combinações (tribunal, ano)
MAX_TENTATIVAS = 3           # tentativas por combinação em caso de erro
BACKOFF_BASE = 5             # segundos; cresce a cada retentativa (backoff linear)

# --------------------------------------------------------------- logging --

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
)
logger = logging.getLogger("crawler_datajud")
logging.getLogger("juscraper").setLevel(logging.WARNING)  # menos verboso


def registrar_erro(tribunal: str, ano: int, erro: str) -> None:
    novo = not ERROS_PATH.exists()
    with open(ERROS_PATH, "a", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        if novo:
            writer.writerow(["tribunal", "ano", "erro", "timestamp"])
        writer.writerow([tribunal, ano, erro, datetime.now().isoformat()])


def ja_processado(destino: Path) -> bool:
    """Considera concluído se o arquivo existe (mesmo vazio -- 0 resultados
    também é um resultado válido e não deve ser reconsultado)."""
    return destino.exists()


def main() -> None:
    OUTPUT_DIR.mkdir(exist_ok=True)
    datajud = jus.scraper("datajud", sleep_time=SLEEP_TIME_PAGINACAO, verbose=1)

    combinacoes = [
        (tribunal, ano)
        for tribunal in TRIBUNAIS
        for ano in range(ANO_INICIO, ANO_FIM + 1)
    ]
    total = len(combinacoes)
    n_pulados = 0
    n_ok = 0
    n_erro = 0
    total_processos = 0

    logger.info(
        "Iniciando varredura: %d tribunais x %d anos (%d-%d) = %d combinações",
        len(TRIBUNAIS), ANO_FIM - ANO_INICIO + 1, ANO_INICIO, ANO_FIM, total,
    )

    for i, (tribunal, ano) in enumerate(combinacoes, start=1):
        destino = OUTPUT_DIR / f"metadados_{tribunal.lower()}_{ano}.csv"

        if ja_processado(destino):
            n_pulados += 1
            logger.info("[%d/%d] %s/%s já processado, pulando.", i, total, tribunal, ano)
            continue

        logger.info("[%d/%d] Consultando %s / %s...", i, total, tribunal, ano)

        for tentativa in range(1, MAX_TENTATIVAS + 1):
            try:
                dados = datajud.listar_processos(
                    tribunal=tribunal,
                    ano_ajuizamento=ano,
                    assuntos=ASSUNTOS,
                    mostrar_movs=False,
                )
                dados.to_csv(destino, index=False)
                n_ok += 1
                total_processos += len(dados)
                logger.info("  -> %d processo(s) salvos em %s", len(dados), destino)
                break
            except Exception as exc:  # noqa: BLE001 -- captura ampla e proposital
                logger.warning(
                    "  Falha (tentativa %d/%d) em %s/%s: %s",
                    tentativa, MAX_TENTATIVAS, tribunal, ano, exc,
                )
                if tentativa == MAX_TENTATIVAS:
                    n_erro += 1
                    registrar_erro(tribunal, ano, str(exc))
                else:
                    time.sleep(BACKOFF_BASE * tentativa)

        time.sleep(SLEEP_ENTRE_COMBOS)

    logger.info(
        "Concluído. %d ok | %d pulados (já existiam) | %d com erro | "
        "%d processos no total. Arquivos em %s/",
        n_ok, n_pulados, n_erro, total_processos, OUTPUT_DIR,
    )
    if n_erro:
        logger.info("Combinações com erro registradas em %s -- rode o script "
                     "de novo para reprocessar só o que faltou.", ERROS_PATH)


if __name__ == "__main__":
    main()
