"""
extrai_partes_granular.py

Extrai tabelas granulares dos parquets gerados pelo scrapper PDPJ,
processando cada (tribunal, ano) de forma independente.

Formatos suportados:
  Legado (TRT1-TRT5): schema com coluna 'detalhes' (struct aninhado).
    Arquivos podem estar em minusculas (partes_trt1_2015_N.parquet) ou
    maiusculas (partes_TRT1_2015_N.parquet).
  Novo (TRT6+): schema com 'processo_numero' e dados em colunas diretas.

Saida: {OUTPUT_DIR}/{tribunal}_{ano}/{tabela}.parquet
  Tabelas grandes sao divididas automaticamente em partes
  ({tabela}_parte0000.parquet, {tabela}_parte0001.parquet, ...) para evitar
  o limite do Arrow de ~2GB por array em um unico chunk.
  Cada tabela inclui as colunas de metadados:
    processo_id, processo_numero, processo_tribunal,
    processo_ano, processo_arquivo_origem
"""

import os
import re
import json
import math
import logging
import warnings
from datetime import datetime

import numpy as np
import pandas as pd
import pyarrow.parquet as pq

warnings.filterwarnings("ignore")

# ---------------------------------------------------------------------------
# CONFIGURACAO
# ---------------------------------------------------------------------------
INPUT_DIR  = "dados_pdpj"
OUTPUT_DIR = "extraidos"
LOG_DIR    = "logs"

# Selecao de quais (tribunal, ano) processar.
# None = processa TODOS os encontrados em INPUT_DIR.
# Para restringir, informe listas (nomes de tribunal sao case-insensitive):

trts = ["trt1","trt2","trt3","trt4","trt5","TRT6", "TRT7",
        "TRT8", "TRT9", "TRT10", "TRT11", "TRT12", "TRT13",
        "TRT14", "TRT15", "TRT16", "TRT17", "TRT18", "TRT19",
        "TRT20", "TRT21", "TRT22", "TRT23", "TRT24",
        ]

tjs = [
    "tjac", "tjal", "tjap", "tjam", "tjba", "tjce", "tjdft",
    "tjes", "tjgo", "tjma", "tjmt", "tjms", "tjmg", "tjpa",
    "tjpb", "tjpr", "tjpe", "tjpi", "tjrj", "tjrn", "tjrs",
    "tjro", "tjrr", "tjsc", "tjsp", "tjse", "tjto",
]

# Tribunais Regionais Federais (TRFs) - 6 regiões
trfs = [
    # "trf1",  # Região 1: DF, MG, BA, GO, TO, MT, RO, AC, AM, RR, AP, PA, MA, PI
    # "trf2",  # Região 2: RJ, ES
    # "trf3",  # Região 3: SP, MS
    "trf4",  # Região 4: RS, SC, PR
    "trf5",  # Região 5: PE, CE, AL, SE, RN, PB
    # "trf6",  # Região 6: MG (criado em 2022, desmembrado do TRF1)
]

TRIBUNAIS_ALVO = trfs
ANOS_ALVO      = None

# Tribunais cujos arquivos anteriores foram salvos em minusculas
_TRIBUNAIS_LEGADO = {"trt1", "trt2", "trt3", "trt4", "trt5"}

# Quantos processos sao explodidos por vez ao gerar cada tabela.
# Tabelas com muitas linhas por processo e texto longo (ex: movimentos)
# podem ultrapassar o limite do Arrow (~2GB por array em um unico chunk)
# se todo o df_root for explodido de uma vez. Processar em lotes menores
# tambem reduz o pico de memoria. Se ainda aparecer erro de tamanho para
# alguma tabela especifica, reduza este valor.
BATCH_SIZE_PROCESSOS = 3000

# Se True, reprocessa todos os grupos mesmo que ja existam com o mesmo
# conjunto de arquivos de entrada (util para testar mudancas na logica de
# extracao). Se False (padrao), grupos ja concluidos com o mesmo conjunto
# de arquivos de entrada sao pulados automaticamente (ver checkpoint abaixo).
FORCAR_REPROCESSAMENTO = False

# Colunas de metadado presentes em todas as tabelas extraidas
META_COLS = [
    "processo_id",
    "processo_numero",
    "processo_tribunal",
    "processo_ano",
    "processo_arquivo_origem",
]

# 16 tabelas extraidas.
# Cada entrada: (nome_da_tabela, caminho_no_objeto_raiz)
# Caminho: lista de chaves a navegar. Listas/ndarrays sao explodidos
# (LEFT JOIN: vazio vira linha NaN). Dicts sao descidos sem explodir.
TABLE_REGISTRY = [
    ("tramitacoes",              ["tramitacoes"]),
    ("partes",                   ["tramitacoes", "partes"]),
    ("partes_documentos",        ["tramitacoes", "partes", "documentosPrincipais"]),
    ("partes_outros_documentos", ["tramitacoes", "partes", "outrosDocumentos"]),
    ("partes_enderecos",         ["tramitacoes", "partes", "enderecos"]),
    ("partes_outros_nomes",      ["tramitacoes", "partes", "outrosNomes"]),
    ("partes_representantes",    ["tramitacoes", "partes", "representantes"]),
    ("assuntos",                 ["tramitacoes", "assunto"]),
    ("assuntos_outros",          ["tramitacoes", "assunto", "outrosAssuntos"]),
    ("classes",                  ["tramitacoes", "classe"]),
    ("classes_historico",        ["tramitacoes", "classe", "historico"]),
    ("distribuicoes",            ["tramitacoes", "distribuicoes"]),
    ("movimentos",               ["tramitacoes", "movimentos"]),
    ("movimentos_complementos",  ["tramitacoes", "movimentos", "tipo", "complementos"]),
    ("documentos",               ["tramitacoes", "documentos"]),
    ("processos_relacionados",   ["tramitacoes", "processosRelacionados"]),
]

_RE_ARQUIVO = re.compile(
    r"^partes_([a-zA-Z0-9]+)_(\d{4})_\d+\.parquet$", re.IGNORECASE
)

os.makedirs(OUTPUT_DIR, exist_ok=True)
os.makedirs(LOG_DIR,    exist_ok=True)
logging.basicConfig(
    filename=os.path.join(LOG_DIR, f"extrai_{datetime.now():%Y%m%d_%H%M%S}.log"),
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
)


# ---------------------------------------------------------------------------
# FUNCOES NUCLEO
# ---------------------------------------------------------------------------
def flatten_scalars(obj, prefix="", sep="_"):
    """Nivela recursivamente um dict com prefixos hierarquicos.
    - Dicts aninhados: prefixo = caminho de chaves separado por sep
    - Listas / ndarrays: coluna <chave>_n com a contagem (sem descer)
    - None: preservado
    - Primitivos: copiados diretamente
    """
    if not isinstance(obj, dict):
        return {}
    result = {}
    for key, val in obj.items():
        col = f"{prefix}{sep}{key}" if prefix else key
        if val is None:
            result[col] = None
        elif isinstance(val, dict):
            result.update(flatten_scalars(val, prefix=col, sep=sep))
        elif isinstance(val, (list, np.ndarray)):
            result[f"{col}_n"] = len(val)
        else:
            result[col] = val
    return result


def _safe_get(obj, key):
    """Navega em um dict por key. Retorna None se obj nao for dict."""
    if isinstance(obj, dict):
        return obj.get(key)
    return None


def _to_seq(val):
    """Converte lista ou ndarray para lista Python.
    Vazio ou None → [None] (preserva linha com NaN -- semantica LEFT JOIN)."""
    if val is None:
        return [None]
    if isinstance(val, np.ndarray):
        return val.tolist() if len(val) > 0 else [None]
    if isinstance(val, list):
        return val if len(val) > 0 else [None]
    return [None]


def explode_path(df_root, path, meta_cols):
    """Navega pelo caminho path a partir da coluna _root do df_root,
    explodindo listas/ndarrays (LEFT JOIN) e descendo em dicts sem explodir.

    Retorna DataFrame com meta_cols + colunas flattened do objeto folha.
    """
    df = df_root[meta_cols + ["_root"]].copy()
    df["_cur"] = df["_root"]
    df = df.drop(columns=["_root"])

    for step in path:
        df["_cur"] = df["_cur"].apply(lambda x: _safe_get(x, step))

        # Verifica o tipo do primeiro valor nao-nulo para decidir se explode
        sample = df["_cur"].dropna()
        if not sample.empty and isinstance(sample.iloc[0], (list, np.ndarray)):
            df["_cur"] = df["_cur"].apply(_to_seq)
            df = df.explode("_cur").reset_index(drop=True)

    # Nivela os dicts folha
    flat_rows = df["_cur"].apply(
        lambda x: flatten_scalars(x) if isinstance(x, dict) else {}
    ).tolist()
    flat_df = pd.DataFrame(flat_rows, index=range(len(df)))

    return pd.concat([
        df[meta_cols].reset_index(drop=True),
        flat_df,
    ], axis=1)


# ---------------------------------------------------------------------------
# NORMALIZACAO POR FORMATO
# ---------------------------------------------------------------------------
def _e_formato_legado(df):
    """Detecta formato legado pelo schema: presenca da coluna 'detalhes'."""
    return "detalhes" in df.columns


def _preparar_legado(df):
    """Monta df_root a partir do formato legado (TRT1-TRT5).
    Cada linha = um processo; coluna _root = dict detalhes."""
    return pd.DataFrame({
        "processo_id":             df["id"],
        "processo_numero":         df["numero_processo"],
        "processo_tribunal":       df["sigla_tribunal"].str.upper(),
        "processo_ano":            df["_ano"],
        "processo_arquivo_origem": df["_arquivo_origem"],
        "_root":                   df["detalhes"],
    })


def _preparar_novo(df):
    """Monta df_root a partir do formato novo (TRT6+).
    A estrutura exata depende do que pdpj.cpopg() retorna; o _root e
    montado a partir das colunas nao-meta existentes no DataFrame.
    Ajuste se necessario apos inspecionar um arquivo real de TRT6+."""
    # Coluna de ID do processo
    for candidato in ("processo_numero", "numeroProcesso", "id"):
        if candidato in df.columns:
            proc_id = df[candidato].astype(str)
            break
    else:
        proc_id = pd.Series([""] * len(df))

    # Se o scrapper salvou dados aninhados em 'detalhes', usa-a como raiz
    if "detalhes" in df.columns:
        root = df["detalhes"]
    else:
        # Caso contrario, transforma cada linha em dict (estrutura plana)
        # As colunas de metadado sao excluidas do root para evitar duplicidade
        cols_meta_excluir = {
            "processo_numero", "processo_tribunal", "processo_ano",
            "processo_arquivo_origem", "_arquivo_origem", "_ano",
        }
        root = df.apply(
            lambda row: {k: v for k, v in row.items() if k not in cols_meta_excluir},
            axis=1,
        )

    tribunal = (
        df["processo_tribunal"].str.upper()
        if "processo_tribunal" in df.columns
        else pd.Series([""] * len(df))
    )

    return pd.DataFrame({
        "processo_id":             proc_id,
        "processo_numero":         proc_id,
        "processo_tribunal":       tribunal,
        "processo_ano":            df["_ano"],
        "processo_arquivo_origem": df["_arquivo_origem"],
        "_root":                   root,
    })


# ---------------------------------------------------------------------------
# DESCOBERTA E AGRUPAMENTO DE ARQUIVOS
# ---------------------------------------------------------------------------
def _listar_grupos():
    """Agrupa arquivos parquet em INPUT_DIR por (tribunal_norm, ano),
    aplicando os filtros TRIBUNAIS_ALVO e ANOS_ALVO quando configurados.

    Para TRT1-TRT5: normaliza para minusculas e agrupa arquivos de ambas
    as convencoes de nome (partes_trt1_... e partes_TRT1_...) no mesmo grupo.
    Para TRT6+: usa o nome como esta no arquivo.
    """
    tribunais_filtro = (
        {t.lower() for t in TRIBUNAIS_ALVO} if TRIBUNAIS_ALVO else None
    )
    anos_filtro = set(ANOS_ALVO) if ANOS_ALVO else None

    grupos = {}
    for nome in os.listdir(INPUT_DIR):
        m = _RE_ARQUIVO.match(nome)
        if not m:
            continue
        trt_orig = m.group(1)
        ano      = m.group(2)
        trt_norm = trt_orig.lower()          # normalizacao para agrupamento

        if tribunais_filtro and trt_norm not in tribunais_filtro:
            continue
        if anos_filtro and ano not in anos_filtro:
            continue

        grupos.setdefault((trt_norm, ano), []).append((nome, trt_orig))

    return dict(sorted(grupos.items()))


# ---------------------------------------------------------------------------
# EXTRACAO E GRAVACAO DE UMA TABELA, EM LOTES
# ---------------------------------------------------------------------------
def _extrair_lote(df_root, path, inicio, fim):
    """Explode um unico lote (processos[inicio:fim]) e remove linhas
    totalmente vazias nos campos de dados. Retorna None se o lote nao
    gerou nenhuma linha com dados."""
    lote_root = df_root.iloc[inicio:fim]
    df_tab = explode_path(lote_root, path, META_COLS)
    cols_dados = [c for c in df_tab.columns if c not in META_COLS]
    if cols_dados:
        df_tab = df_tab.dropna(subset=cols_dados, how="all")
    return None if df_tab.empty else df_tab


def _calcular_schema_uniao(df_root, path, n_lotes, table_name):
    """Passada leve (sem gravar nada) que descobre a uniao de todas as
    colunas produzidas pelos lotes.

    Necessaria porque processos diferentes podem ter campos aninhados
    opcionais distintos (ex: um processo com 'orgaoJulgador_ibge' e outro
    sem esse campo) -- sem isso, arquivos de partes diferentes da mesma
    tabela teriam colunas diferentes entre si.

    Mantem so os NOMES das colunas em memoria, descartando os dados de
    cada lote assim que capturados.
    """
    colunas = list(META_COLS)
    vistas  = set(META_COLS)
    for i in range(n_lotes):
        inicio, fim = i * BATCH_SIZE_PROCESSOS, (i + 1) * BATCH_SIZE_PROCESSOS
        try:
            df_tab = _extrair_lote(df_root, path, inicio, fim)
        except Exception as e:
            logging.warning(
                "[%s] erro ao descobrir schema no lote %d: %s", table_name, i, e
            )
            continue
        if df_tab is None:
            continue
        for c in df_tab.columns:
            if c not in vistas:
                vistas.add(c)
                colunas.append(c)
        del df_tab
    return colunas


def _extrair_e_salvar_tabela(df_root, path, table_name, pasta):
    """Processa uma tabela em lotes de BATCH_SIZE_PROCESSOS processos,
    salvando cada lote nao-vazio como um arquivo de parte separado.

    Isso evita o limite do Arrow (~2GB por array em um unico chunk) e
    reduz o pico de memoria, pois nunca materializa a tabela inteira de
    uma vez quando o tribunal/ano tem muitos processos.

    Quando ha mais de um lote, roda uma passada previa (_calcular_schema_uniao)
    para garantir que todas as partes salvas tenham exatamente as mesmas
    colunas -- caso contrario, juntar as partes depois (concat/leitura em
    conjunto) ficaria inconsistente.

    Se o resultado couber em um unico lote, salva como {table_name}.parquet
    (sem sufixo de parte) para manter compatibilidade com uso anterior.
    """
    n_processos = len(df_root)
    n_lotes     = math.ceil(n_processos / BATCH_SIZE_PROCESSOS) if n_processos else 0
    if n_lotes == 0:
        return 0, 0, 0

    colunas_uniao = (
        _calcular_schema_uniao(df_root, path, n_lotes, table_name)
        if n_lotes > 1 else None
    )

    total_linhas  = 0
    partes_salvas = []
    erros_lote    = 0

    for i in range(n_lotes):
        inicio, fim = i * BATCH_SIZE_PROCESSOS, (i + 1) * BATCH_SIZE_PROCESSOS
        try:
            df_tab = _extrair_lote(df_root, path, inicio, fim)
            if df_tab is None:
                continue
            if colunas_uniao is not None:
                df_tab = df_tab.reindex(columns=colunas_uniao)
            total_linhas += len(df_tab)
            partes_salvas.append(df_tab)
        except Exception as e:
            erros_lote += 1
            logging.error(
                "[%s] lote %d (processos %d-%d): %s", table_name, i, inicio, fim, e
            )
            print(f"     ⚠️  lote {i} de {table_name} falhou: {e}")

    if not partes_salvas:
        return 0, 0, erros_lote

    # Um unico lote com dados → salva sem sufixo (compatibilidade)
    if len(partes_salvas) == 1 and n_lotes == 1:
        out = os.path.join(pasta, f"{table_name}.parquet")
        try:
            partes_salvas[0].to_parquet(out, index=False)
        except Exception as e:
            # Mesmo um unico lote pode estourar o limite em tribunais muito
            # grandes com BATCH_SIZE_PROCESSOS alto -- reduz e tenta de novo
            logging.error("Erro salvando %s mesmo em lote unico: %s", out, e)
            print(f"     ⚠️  Erro ao salvar {table_name} -- tente reduzir "
                  f"BATCH_SIZE_PROCESSOS (atual: {BATCH_SIZE_PROCESSOS}).")
            return total_linhas, 0, erros_lote + 1
        return total_linhas, 1, erros_lote

    # Multiplos lotes com dados → salva cada um como parte numerada
    # (todas com o mesmo schema, garantido por colunas_uniao acima)
    n_arquivos = 0
    for idx, df_parte in enumerate(partes_salvas):
        out = os.path.join(pasta, f"{table_name}_parte{idx:04d}.parquet")
        try:
            df_parte.to_parquet(out, index=False)
            n_arquivos += 1
        except Exception as e:
            erros_lote += 1
            logging.error("Erro salvando %s: %s", out, e)
            print(f"     ⚠️  Erro ao salvar parte {idx} de {table_name}: {e}")

    return total_linhas, n_arquivos, erros_lote


# ---------------------------------------------------------------------------
# CHECKPOINT -- verifica o que ja foi extraido em execucoes anteriores
# ---------------------------------------------------------------------------
_NOME_MANIFESTO = "_manifesto.json"


def _caminho_manifesto(pasta):
    return os.path.join(pasta, _NOME_MANIFESTO)


def _grupo_ja_extraido(pasta, arquivos):
    """Verifica se o grupo ja foi extraido com sucesso anteriormente,
    comparando o conjunto de arquivos de entrada usados na ultima extracao
    (registrado no manifesto) com o conjunto atual de arquivos do grupo.

    Nao usamos "o arquivo da tabela existe?" como criterio porque algumas
    tabelas podem legitimamente ficar vazias para um tribunal/ano (ex:
    processos_relacionados quando nenhum processo tem relacionados) -- nesse
    caso nenhum arquivo e gravado, e isso NAO significa que falta processar.
    """
    caminho = _caminho_manifesto(pasta)
    if not os.path.exists(caminho):
        return False
    try:
        with open(caminho, "r", encoding="utf-8") as f:
            manifesto = json.load(f)
    except Exception as e:
        logging.warning("Manifesto ilegivel em %s: %s -- reprocessando grupo.", caminho, e)
        return False

    arquivos_manifesto = set(manifesto.get("arquivos_entrada", []))
    arquivos_atuais    = {nome for nome, _ in arquivos}

    if arquivos_atuais != arquivos_manifesto:
        novos = arquivos_atuais - arquivos_manifesto
        if novos:
            print(f"  Novo(s) arquivo(s) de entrada desde a ultima extracao: "
                  f"{sorted(novos)} -- reprocessando grupo.")
        return False

    return True


def _salvar_manifesto(pasta, arquivos, resultado_tabelas):
    """Grava o manifesto de conclusao do grupo, registrando quais arquivos
    de entrada foram usados (para o checkpoint da proxima execucao) e um
    resumo por tabela, util para conferencia manual."""
    manifesto = {
        "arquivos_entrada": sorted(nome for nome, _ in arquivos),
        "extraido_em":      datetime.now().isoformat(),
        "tabelas":          resultado_tabelas,
    }
    try:
        with open(_caminho_manifesto(pasta), "w", encoding="utf-8") as f:
            json.dump(manifesto, f, ensure_ascii=False, indent=2)
    except Exception as e:
        logging.warning("Falha ao gravar manifesto em %s: %s", pasta, e)


# ---------------------------------------------------------------------------
# PROCESSAMENTO DE UM GRUPO (tribunal, ano)
# ---------------------------------------------------------------------------
def _processar_grupo(trt_norm, ano, arquivos):
    sep = "=" * 62
    print(f"\n{sep}")
    print(f"  [{trt_norm.upper()} {ano}]  {len(arquivos)} arquivo(s)")
    print(sep)

    pasta = os.path.join(OUTPUT_DIR, f"{trt_norm}_{ano}")

    if not FORCAR_REPROCESSAMENTO and _grupo_ja_extraido(pasta, arquivos):
        print(f"  ✓ Ja extraido anteriormente (mesmo conjunto de arquivos de "
              f"entrada) -- pulando. Ajuste FORCAR_REPROCESSAMENTO para reprocessar.")
        return

    # Le e concatena todos os arquivos do grupo
    dfs = []
    for nome, _ in sorted(arquivos):
        caminho = os.path.join(INPUT_DIR, nome)
        try:
            df_arq = pd.read_parquet(caminho)
            df_arq["_arquivo_origem"] = nome
            df_arq["_ano"]            = ano
            dfs.append(df_arq)
            print(f"  Lido:  {nome}  ({len(df_arq):,} processos)")
        except Exception as e:
            print(f"  ✗ Erro ao ler {nome}: {e}")
            logging.error("Erro ao ler %s: %s", nome, e)

    if not dfs:
        print("  Nenhum arquivo lido. Pulando grupo.")
        return

    df_all = pd.concat(dfs, ignore_index=True)

    # Prepara df_root de acordo com o formato detectado
    if _e_formato_legado(df_all):
        formato = "legado"
        df_root = _preparar_legado(df_all)
    else:
        formato = "novo"
        df_root = _preparar_novo(df_all)
        print(
            "  ⚠️  Formato novo (TRT6+) -- se as tabelas saírem vazias,\n"
            "     inspecione a coluna _root e ajuste _preparar_novo()."
        )

    print(f"  Formato: {formato} | {len(df_root):,} processos no total | "
          f"lotes de {BATCH_SIZE_PROCESSOS:,} processos")
    logging.info("[%s %s] formato=%s processos=%d", trt_norm, ano, formato, len(df_root))

    # Pasta de saida para este grupo (ja definida acima, no checkpoint)
    os.makedirs(pasta, exist_ok=True)

    # Extrai e salva cada tabela do registry, em lotes
    print()
    resultado_tabelas = {}
    houve_erro = False
    for table_name, path in TABLE_REGISTRY:
        total_linhas, n_arquivos, erros_lote = _extrair_e_salvar_tabela(
            df_root, path, table_name, pasta
        )
        logging.info(
            "[%s %s] %s → %d linhas em %d arquivo(s), %d erro(s) de lote",
            trt_norm, ano, table_name, total_linhas, n_arquivos, erros_lote,
        )
        resultado_tabelas[table_name] = {
            "linhas": total_linhas, "arquivos": n_arquivos, "erros_lote": erros_lote,
        }
        if erros_lote:
            houve_erro = True
        sufixo_erro = f"  ({erros_lote} lote(s) com erro)" if erros_lote else ""
        sufixo_arqs = f" em {n_arquivos} arquivo(s)" if n_arquivos > 1 else ""
        print(f"  ✓  {table_name:<38} {total_linhas:>9,} linhas{sufixo_arqs}{sufixo_erro}")

    _salvar_manifesto(pasta, arquivos, resultado_tabelas)
    if houve_erro:
        print(f"\n  ⚠️  Grupo concluido com erros em alguns lotes (ver log). "
              f"Manifesto gravado mesmo assim -- delete {_caminho_manifesto(pasta)} "
              "para forcar reprocessamento deste grupo especifico.")
    print(f"\n  Tabelas salvas em: {pasta}/")


# ---------------------------------------------------------------------------
# MAIN
# ---------------------------------------------------------------------------
def main():
    grupos = _listar_grupos()
    if not grupos:
        print(
            f"Nenhum arquivo parquet encontrado em {INPUT_DIR}/ "
            "para os filtros configurados (TRIBUNAIS_ALVO / ANOS_ALVO)."
        )
        return

    total_arq = sum(len(v) for v in grupos.values())
    filtro_info = []
    if TRIBUNAIS_ALVO:
        filtro_info.append(f"tribunais={TRIBUNAIS_ALVO}")
    if ANOS_ALVO:
        filtro_info.append(f"anos={ANOS_ALVO}")
    filtro_txt = f" (filtro: {', '.join(filtro_info)})" if filtro_info else ""

    print(
        f"Encontrados {len(grupos)} grupos ({total_arq} arquivo(s)) em {INPUT_DIR}/{filtro_txt}\n"
        f"Saida em: {OUTPUT_DIR}/"
    )

    for (trt_norm, ano), arquivos in grupos.items():
        _processar_grupo(trt_norm, ano, arquivos)

    print(f"\n{'='*62}")
    print(f"  Extracao concluida. Tabelas em {OUTPUT_DIR}/")


if __name__ == "__main__":
    main()
