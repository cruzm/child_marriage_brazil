"""
Scrapper de partes (PDPJ)

Funcionalidades:
  - Checkpoint de SUCESSO: pula processos ja baixados em sessoes anteriores
  - Checkpoint de ERRO: pula processos que falharam, registrando tipo e mensagem
  - Multithread com limitador de taxa GLOBAL (RateLimiter compartilhado)
  - Circuit breaker e deteccao de token expirado
  - Gravacao incremental em buffer (evita pd.concat O(n^2) no loop)

Fluxo recomendado:
  1. Coloque os CSVs de entrada em trts/
  2. Rode o script; ele processa os processos pendentes
  3. Ao encerrar (tempo/token), renove o token e rode de novo --
     processos ja baixados E processos com erro sao pulados automaticamente
"""

import os
import re
import csv
import glob
import time
import logging
import warnings
import threading
from datetime import datetime
from getpass import getpass
from concurrent.futures import ThreadPoolExecutor, as_completed
import smtplib
import urllib.request
import urllib.parse
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart

import pandas as pd
import pyarrow.parquet as pq
import juscraper as jus
from tqdm import tqdm

warnings.filterwarnings("ignore")

# ---------------------------------------------------------------------------
# CONFIGURACAO -- ajuste aqui
# ---------------------------------------------------------------------------
INPUT_DIR  = "trts"
OUTPUT_DIR = "dados_pdpj"
LOG_DIR    = "logs"

# None = processa todos os tribunais encontrados em INPUT_DIR; ou ex: ["trt1"]

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
    # "trf4",  # Região 4: RS, SC, PR
    # "trf5",  # Região 5: PE, CE, AL, SE, RN, PB
    "trf6",  # Região 6: MG (criado em 2022, desmembrado do TRF1)
]

TRIBUNAIS_ALVO = trfs
ANO_MIN, ANO_MAX = "2015", "2026"

# Token PDPJ expira em 8h -- paramos um pouco antes para encerrar com folga
SESSION_BUDGET_SECONDS = 7 * 3600 + 30 * 60  # 7h30

# Threads e taxa de requisicoes
MAX_WORKERS              = 4    # comece baixo e aumente se a taxa de erro continuar baixa
TARGET_REQUEST_INTERVAL  = 0.3  # segundos entre requisicoes -- taxa GLOBAL (nao por thread)

MAX_CONSECUTIVE_ERRORS   = 1000
MAX_AUTH_ERRORS          = 5      # erros de acesso consecutivos para encerrar a sessao
ERROR_BACKOFF_SECONDS    = 5.0    # espera entre erros normais
PAUSE_ON_ERRORS_SECONDS  = 120    # pausa quando atinge MAX_CONSECUTIVE_ERRORS antes de retomar
SAVE_EVERY_N             = 250    # linhas no buffer antes de gravar em disco

# Notificacoes por e-mail
# Deixe EMAIL_REMETENTE vazio ("") para desativar notificacoes por e-mail.
# Para Gmail: crie uma senha de app em:
#   Conta Google > Seguranca > Verificacao em duas etapas > Senhas de app
# Recomendado: use variaveis de ambiente para nao expor credenciais no codigo:
#   export SCRAPPER_EMAIL_REMETENTE="seu@gmail.com"
#   export SCRAPPER_EMAIL_SENHA="sua_senha_de_app"
#   export SCRAPPER_EMAIL_DESTINATARIO="destinatario@email.com"
EMAIL_REMETENTE    = ""  # deixe vazio para desativar; preencha para reativar
EMAIL_SENHA        = ""  # os.environ.get("SCRAPPER_EMAIL_SENHA", "")
EMAIL_DESTINATARIO = ""  # os.environ.get("SCRAPPER_EMAIL_DESTINATARIO", EMAIL_REMETENTE)
EMAIL_SMTP_HOST    = "smtp.gmail.com"  # Gmail; para Outlook use "smtp.office365.com"
EMAIL_SMTP_PORT    = 587

# Notificacoes por WhatsApp (via CallMeBot -- gratuito, sem cartao de credito)
# Configuracao unica no celular:
#   1. Salve +34 644 44 22 33 na agenda como "CallMeBot"
#   2. Mande "I allow callmebot to send me messages" para esse numero pelo WhatsApp
#   3. Voce recebera sua apikey por mensagem
# Preencha as variaveis abaixo ou exporte via ambiente:
#   export SCRAPPER_WHATSAPP_PHONE="+5511999999999"
#   export SCRAPPER_WHATSAPP_APIKEY="sua_apikey"
WHATSAPP_PHONE  = os.environ.get("SCRAPPER_WHATSAPP_PHONE",  "")  # ex: +5511999999999
WHATSAPP_APIKEY = os.environ.get("SCRAPPER_WHATSAPP_APIKEY", "")

# Nomes de coluna candidatos para identificar o processo nos parquets antigos
# Ordem importa: colunas com IDs sem formatacao (apenas digitos) vem primeiro.
# Arquivos novos (este script): "processo_numero"
# Arquivos antigos (script original para TRT1-TRT5): "id" ou "processo"
# "numero_processo" e "numeroProcesso" ficam por ultimo pois contem o numero
# formatado (com pontos e hifens), que nao bate com o ID usado nas consultas.
ID_COLUMN_CANDIDATES = ["processo_numero", "id", "processo", "numeroProcesso", "numero_processo"]

os.makedirs(INPUT_DIR,  exist_ok=True)
os.makedirs(OUTPUT_DIR, exist_ok=True)
os.makedirs(LOG_DIR,    exist_ok=True)

logging.basicConfig(
    filename=os.path.join(LOG_DIR, f"scrapper_{datetime.now():%Y%m%d_%H%M%S}.log"),
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
)

# ---------------------------------------------------------------------------
# NOTIFICACAO POR E-MAIL
# ---------------------------------------------------------------------------
def _enviar_email(assunto: str, corpo: str):
    """Envia um e-mail de notificacao. Falhas sao logadas mas nao interrompem o script."""
    if not EMAIL_REMETENTE:
        return
    try:
        msg = MIMEMultipart()
        msg["From"]    = EMAIL_REMETENTE
        msg["To"]      = EMAIL_DESTINATARIO
        msg["Subject"] = f"[scrapper PDPJ] {assunto}"
        msg.attach(MIMEText(corpo, "plain", "utf-8"))
        with smtplib.SMTP(EMAIL_SMTP_HOST, EMAIL_SMTP_PORT) as smtp:
            smtp.ehlo()
            smtp.starttls()
            smtp.login(EMAIL_REMETENTE, EMAIL_SENHA)
            smtp.send_message(msg)
        logging.info("E-mail enviado: %s", assunto)
    except Exception as e:
        logging.warning("Falha ao enviar e-mail: %s", e)
        print(f"  ⚠️  Falha ao enviar e-mail de notificacao: {e}")


# ---------------------------------------------------------------------------
# NOTIFICACAO POR WHATSAPP (CallMeBot)
# ---------------------------------------------------------------------------
def _enviar_whatsapp(mensagem: str):
    """Envia notificacao via WhatsApp usando CallMeBot. Falhas sao logadas
    mas nao interrompem o script."""
    if not WHATSAPP_PHONE or not WHATSAPP_APIKEY:
        return
    try:
        texto = urllib.parse.quote(mensagem)
        url   = (
            f"https://api.callmebot.com/whatsapp.php"
            f"?phone={WHATSAPP_PHONE}&text={texto}&apikey={WHATSAPP_APIKEY}"
        )
        with urllib.request.urlopen(url, timeout=10) as resp:
            logging.info("WhatsApp enviado: status %s", resp.status)
    except Exception as e:
        logging.warning("Falha ao enviar WhatsApp: %s", e)
        print(f"  ⚠️  Falha ao enviar notificacao WhatsApp: {e}")


def _notificar(assunto: str, corpo: str):
    """Dispara todas as notificacoes ativas (e-mail e/ou WhatsApp)."""
    _enviar_email(assunto, corpo)
    _enviar_whatsapp(f"{assunto}\n\n{corpo}")


# ---------------------------------------------------------------------------
# AUTENTICACAO PDPJ
# ---------------------------------------------------------------------------
token = os.environ.get("JUSCRAPER_PDPJ_TOKEN")
if token is None:
    token = getpass("Digite o token de autenticacao do JUSCRAPER_PDPJ_TOKEN: ")

pdpj = jus.scraper("pdpj", sleep_time=0.0, verbose=0)
pdpj.auth(token=token)

session_start = time.time()

def tempo_de_sessao_esgotado() -> bool:
    return (time.time() - session_start) > SESSION_BUDGET_SECONDS


# ---------------------------------------------------------------------------
# LIMITADOR DE TAXA GLOBAL (compartilhado entre todas as threads)
# ---------------------------------------------------------------------------
class RateLimiter:
    """Garante que o intervalo minimo entre o INICIO de duas requisicoes
    seja respeitado somando TODAS as threads. Aumentar MAX_WORKERS nao
    aumenta a taxa -- so ajuda a manter varias chamadas em voo ao mesmo tempo,
    o que permite atingir de fato a taxa-alvo quando a latencia de rede e o
    gargalo (que e o caso tipico de uma API sincrona como esta)."""

    def __init__(self, interval: float):
        self.interval = interval
        self._lock    = threading.Lock()
        self._ultimo  = 0.0

    def aguardar(self):
        with self._lock:
            espera = self.interval - (time.time() - self._ultimo)
            if espera > 0:
                time.sleep(espera)
            self._ultimo = time.time()


rate_limiter = RateLimiter(TARGET_REQUEST_INTERVAL)


# ---------------------------------------------------------------------------
# CHECKPOINT DE ERROS
# ---------------------------------------------------------------------------
def _caminho_erros(trt, ano):
    return os.path.join(OUTPUT_DIR, f"erros_{trt}_{ano}.csv")


def _carregar_ids_com_erro(trt, ano) -> set:
    """Le o CSV de erros e devolve o conjunto de IDs a pular."""
    caminho = _caminho_erros(trt, ano)
    if not os.path.exists(caminho):
        return set()
    try:
        df  = pd.read_csv(caminho, dtype=str)
        ids = set(df["processo_id"].dropna().unique())
        print(f"  [{trt} {ano}] {len(ids)} processo(s) com erro registrado serao pulados.")
        logging.info("[%s %s] %d processos com erro carregados do checkpoint.", trt, ano, len(ids))
        return ids
    except Exception as e:
        logging.warning("Erro ao ler checkpoint de erros %s: %s", caminho, e)
        return set()


# Tipos de erro:
#   sem_acesso  -- API recusou acesso a este processo especifico (403/401 isolado);
#                  salvo no CSV e pulado nas proximas sessoes, mas NAO encerra a sessao
#   permanente  -- processo nao existe ou dados invalidos; improvavel de resolver
#   transitorio -- rede, timeout, etc.; pode ser retentado deletando a linha do CSV
#
# Apenas erros de auth CONSECUTIVOS (>= MAX_AUTH_ERRORS) encerram a sessao,
# evitando falsos positivos causados por processos individuais sem permissao.
_ERROS_PERMANENTES = ("404", "not found", "nao encontrado", "inexistente", "invalido")

# Padroes de autenticacao: usamos regex para evitar que "401" bata em numeros
# de processo e que "forbidden" bata em mensagens de restricao de recurso isoladas.
import re as _re
_RE_AUTH = _re.compile(
    r"(?<!\d)401(?!\d)"          # 401 isolado (nao parte de outro numero)
    r"|token\s*(expirado?|expired?|invalido?|invalid)"
    r"|jwt\s*(expired?|expirado?|invalid)"
    r"|credencial\s*invalida?"
    r"|authentication\s*failed"
    r"|nao\s*autenticado",
    _re.IGNORECASE,
)

def _classificar_erro(msg: str) -> str:
    if _RE_AUTH.search(msg):
        return "auth"
    msg_lower = msg.lower()
    # 403 sozinho pode ser restricao de recurso (nao auth global): tratado como sem_acesso
    if "403" in msg_lower or "forbidden" in msg_lower or "unauthorized" in msg_lower:
        return "sem_acesso"
    if any(t in msg_lower for t in _ERROS_PERMANENTES):
        return "permanente"
    return "transitorio"



# Lock global para escrita no CSV de erros (compartilhado entre instancias)
_lock_csv_erros = threading.Lock()

def _registrar_erro_csv(processo_id, tipo_erro, excecao, trt, ano):
    caminho = _caminho_erros(trt, ano)
    linha   = {
        "processo_id": processo_id,
        "tipo_erro":   tipo_erro,
        "mensagem":    str(excecao)[:400],
        "timestamp":   datetime.now().isoformat(),
    }
    with _lock_csv_erros:
        escrever_cabecalho = not os.path.exists(caminho)
        with open(caminho, "a", newline="", encoding="utf-8") as f:
            writer = csv.DictWriter(f, fieldnames=list(linha.keys()))
            if escrever_cabecalho:
                writer.writeheader()
            writer.writerow(linha)


# ---------------------------------------------------------------------------
# CHECKPOINT DE SUCESSO
# ---------------------------------------------------------------------------
def _indice_do_arquivo(caminho):
    m = re.search(r"_(\d+)\.parquet$", caminho)
    return int(m.group(1)) if m else -1


def _detectar_coluna_id(caminho):
    """Detecta automaticamente qual coluna identifica o processo no parquet,
    para compatibilidade com arquivos gerados pelo script original."""
    try:
        schema = pq.read_schema(caminho)
    except Exception:
        return None
    nomes = set(schema.names)
    for candidato in ID_COLUMN_CANDIDATES:
        if candidato in nomes:
            return candidato
    return None


# Tribunais cujos arquivos anteriores foram salvos em minusculas (trt1, trt2 ...)
# enquanto os metadados usam maiusculas (TRT1, TRT2 ...). Para estes, o glob
# precisa testar ambas as variantes. Os demais (TRT6 em diante) ja seguem o
# padrao atual e nao precisam de tratamento especial.
_TRIBUNAIS_LEGADO_MINUSCULAS = {"trt1", "trt2", "trt3", "trt4", "trt5"}


def _ids_ja_processados(trt, ano):
    """Retorna (conjunto de IDs ja baixados, proximo indice de arquivo parquet).

    Para trt1-trt5: busca arquivos com o nome do tribunal em maiusculas E
    minusculas, pois os arquivos anteriores foram salvos em minusculas (ex:
    partes_trt1_2015_4.parquet) enquanto os metadados usam maiusculas (TRT1).

    Para os demais tribunais: busca apenas com o nome como vem no metadado.

    A coluna de ID e detectada automaticamente:
      - Arquivos novos (gerados por este script): coluna "processo_numero"
      - Arquivos antigos (trt1-trt5, script original): coluna "id"
    """
    if trt.lower() in _TRIBUNAIS_LEGADO_MINUSCULAS:
        variantes = {trt, trt.lower(), trt.upper()}
    else:
        variantes = {trt}

    vistos   = set()
    arquivos = []
    for variante in variantes:
        pattern = os.path.join(OUTPUT_DIR, f"partes_{variante}_{ano}_*.parquet")
        for arq in glob.glob(pattern):
            arq_abs = os.path.abspath(arq)
            if arq_abs not in vistos:
                vistos.add(arq_abs)
                arquivos.append(arq)
    arquivos = sorted(arquivos, key=_indice_do_arquivo)

    ids = set()
    for arq in arquivos:
        coluna = _detectar_coluna_id(arq)
        if coluna is None:
            print(f"  Aviso: nenhuma coluna de ID reconhecida em {os.path.basename(arq)} "
                  "(arquivo excluido do checkpoint de sucesso, mas mantido nos dados).")
            logging.warning("Sem coluna de ID em %s -- excluido do checkpoint.", arq)
            continue
        try:
            col = pq.read_table(arq, columns=[coluna]).column(coluna)
            ids.update(col.to_pylist())
            logging.info("Checkpoint: %d IDs lidos de %s (coluna '%s')",
                         len(col), os.path.basename(arq), coluna)
        except Exception as e:
            logging.warning("Erro lendo checkpoint de sucesso %s: %s", arq, e)

    indices        = [i for i in (_indice_do_arquivo(a) for a in arquivos) if i >= 0]
    proximo_indice = max(indices, default=0) + 1
    return ids, proximo_indice


# ---------------------------------------------------------------------------
# ESTADO COMPARTILHADO DO PROCESSAMENTO (um por arquivo trt/ano)
# ---------------------------------------------------------------------------
class EstadoProcessamento:
    def __init__(self, trt, ano, nome_arquivo, indice_inicial):
        self.trt            = trt
        self.ano            = ano
        self.nome_arquivo   = nome_arquivo
        self.indice_arquivo = indice_inicial

        self.buffer                  = []
        self.erros_consecutivos      = 0
        self.erros_auth_consecutivos = 0  # contador separado para erros de acesso
        self.parar                   = threading.Event()
        self.motivo_parada           = None
        self._lock                   = threading.Lock()

        # Circuit breaker com recuperacao:
        # pode_continuar fica set() em modo normal e clear() durante a pausa.
        # Threads bloqueiam em .wait() ate a pausa terminar e o evento ser
        # liberado novamente -- sem encerrar a sessao.
        self.pode_continuar = threading.Event()
        self.pode_continuar.set()
        self._pausando = False  # evita que varias threads disparem a pausa ao mesmo tempo

    # -- sucesso -----------------------------------------------------------
    def registrar_sucesso(self, df_partes):
        with self._lock:
            self.buffer.append(df_partes)
            self.erros_consecutivos      = 0
            self.erros_auth_consecutivos = 0
            if len(self.buffer) >= SAVE_EVERY_N:
                self._salvar_buffer_sem_lock()

    # -- erro --------------------------------------------------------------
    def registrar_erro(self, processo_id, excecao):
        tipo = _classificar_erro(str(excecao))
        logging.warning("Erro (%s) em %s: %s", tipo, processo_id, excecao)

        if tipo == "auth":
            # Erro inequivoco de autenticacao (401 / token expirado):
            # conta separado e so encerra quando atinge MAX_AUTH_ERRORS consecutivos
            with self._lock:
                self.erros_auth_consecutivos += 1
                n_auth = self.erros_auth_consecutivos
            logging.warning(
                "Erro de auth consecutivo %d/%d em %s", n_auth, MAX_AUTH_ERRORS, processo_id
            )
            if n_auth >= MAX_AUTH_ERRORS:
                print(
                    f"\n🔒 {n_auth} erros de autenticacao consecutivos -- "
                    "token provavelmente expirado. Encerrando a sessao."
                )
                self._sinalizar_parada("auth")
            else:
                print(
                    f"\n⚠️  Erro de auth ({n_auth}/{MAX_AUTH_ERRORS}) em {processo_id} "
                    "-- pode ser restricao de recurso, continuando..."
                )
                time.sleep(ERROR_BACKOFF_SECONDS)
            return

        if tipo == "sem_acesso":
            # 403/forbidden isolado: restricao deste processo especifico, nao do token.
            # Salva para nao reprocessar, reseta o contador de auth e continua.
            _registrar_erro_csv(processo_id, "sem_acesso", excecao, self.trt, self.ano)
            with self._lock:
                self.erros_auth_consecutivos = 0  # reset: nao e problema de token
            time.sleep(ERROR_BACKOFF_SECONDS)
            return

        # Erro geral (permanente ou transitorio)
        _registrar_erro_csv(processo_id, tipo, excecao, self.trt, self.ano)
        with self._lock:
            self.erros_auth_consecutivos = 0  # reset ao ver erro nao-auth
            self.erros_consecutivos += 1
            consecutivos = self.erros_consecutivos
            deve_pausar  = consecutivos >= MAX_CONSECUTIVE_ERRORS and not self._pausando
            if deve_pausar:
                self._pausando = True

        if deve_pausar:
            self.pode_continuar.clear()  # bloqueia todas as outras threads
            print(
                f"\n⚠️  {MAX_CONSECUTIVE_ERRORS} erros consecutivos -- "
                f"pausando por {PAUSE_ON_ERRORS_SECONDS}s antes de retomar "
                f"(token ainda valido, sessao continua)..."
            )
            logging.warning(
                "Circuit breaker ativado -- pausando %ds antes de retomar.", PAUSE_ON_ERRORS_SECONDS
            )
            time.sleep(PAUSE_ON_ERRORS_SECONDS)
            with self._lock:
                self.erros_consecutivos = 0
                self._pausando          = False
            self.pode_continuar.set()   # libera todas as threads
            print("▶️  Retomando requisicoes.\n")
            return

        time.sleep(ERROR_BACKOFF_SECONDS)

    # -- controle de parada ------------------------------------------------
    def _sinalizar_parada(self, motivo):
        with self._lock:
            if not self.parar.is_set():
                self.motivo_parada = motivo
            self.parar.set()
        # Garante que threads bloqueadas na pausa sejam liberadas para encerrar
        self.pode_continuar.set()

    # -- gravacao ----------------------------------------------------------
    def _salvar_buffer_sem_lock(self):
        if not self.buffer:
            return
        df_out  = pd.concat(self.buffer, ignore_index=True)
        caminho = os.path.join(
            OUTPUT_DIR,
            f"partes_{self.trt}_{self.ano}_{self.indice_arquivo}.parquet"
        )
        df_out.to_parquet(caminho, index=False)
        logging.info("Salvo %s (%d linhas)", caminho, len(df_out))
        self.indice_arquivo += 1
        self.buffer          = []

    def flush_final(self):
        with self._lock:
            self._salvar_buffer_sem_lock()


# ---------------------------------------------------------------------------
# WORKER (executado por cada thread)
# ---------------------------------------------------------------------------
def _processar_um(processo_id: str, estado: EstadoProcessamento):
    if estado.parar.is_set():
        return
    if tempo_de_sessao_esgotado():
        estado._sinalizar_parada("tempo_esgotado")
        return

    # Bloqueia aqui durante a pausa do circuit breaker; retorna imediatamente se nao houver pausa
    estado.pode_continuar.wait()

    if estado.parar.is_set():  # pode ter sido encerrado durante a pausa
        return

    rate_limiter.aguardar()

    if estado.parar.is_set():  # outra thread pode ter parado enquanto aguardavamos
        return

    try:
        partes    = pdpj.cpopg(processo_id)
        df_partes = pd.DataFrame(partes)
        df_partes["processo_numero"]         = processo_id
        df_partes["processo_tribunal"]       = estado.trt
        df_partes["processo_ano"]            = estado.ano
        df_partes["processo_arquivo_origem"] = estado.nome_arquivo
        estado.registrar_sucesso(df_partes)
    except Exception as e:
        estado.registrar_erro(processo_id, e)


# ---------------------------------------------------------------------------
# DESCOBERTA DOS ARQUIVOS DE ENTRADA
# ---------------------------------------------------------------------------
def _listar_arquivos_entrada():
    arquivos = []
    for nome in os.listdir(INPUT_DIR):
        partes_nome = nome.split("_")
        if len(partes_nome) < 3:
            continue
        trt = partes_nome[1]
        ano = partes_nome[2].split(".")[0]
        if TRIBUNAIS_ALVO and trt not in TRIBUNAIS_ALVO:
            continue
        if not (ANO_MIN <= ano <= ANO_MAX):
            continue
        arquivos.append((nome, trt, ano))
    return sorted(arquivos, key=lambda x: (x[1], x[2]))


# ---------------------------------------------------------------------------
# PROCESSAMENTO DE UM ARQUIVO (trt, ano)
# ---------------------------------------------------------------------------
def _processa_arquivo(nome_arquivo: str, trt: str, ano: str) -> bool:
    """Retorna False se a sessao deve ser encerrada."""
    caminho_csv = os.path.join(INPUT_DIR, nome_arquivo)
    try:
        df = pd.read_csv(caminho_csv)
    except OSError as e:
        print(f"  ⚠️  [{trt} {ano}] Erro ao abrir '{caminho_csv}': {e} -- pulando arquivo.")
        logging.warning("OSError ao abrir %s: %s -- arquivo pulado.", caminho_csv, e)
        return True
    todos_ids = list(df["id"].str.split("_").str[-1].unique())

    ja_feitos,     proximo_indice = _ids_ja_processados(trt, ano)
    com_erro                      = _carregar_ids_com_erro(trt, ano)
    pendentes = [i for i in todos_ids if i not in ja_feitos and i not in com_erro]

    if not pendentes:
        print(f"[{trt} {ano}] Nenhum processo pendente "
              f"({len(ja_feitos)} ok | {len(com_erro)} com erro). Pulando.\n")
        return True

    print(
        f"\n[{trt} {ano}] {len(pendentes):,} pendentes | "
        f"{len(ja_feitos):,} ja baixados | "
        f"{len(com_erro):,} com erro (pulados) | "
        f"proximo arquivo: partes_{trt}_{ano}_{proximo_indice}.parquet | "
        f"{MAX_WORKERS} threads"
    )

    estado = EstadoProcessamento(trt, ano, nome_arquivo, proximo_indice)

    with tqdm(total=len(pendentes), desc=f"{trt}_{ano}") as barra:
        with ThreadPoolExecutor(max_workers=MAX_WORKERS) as executor:
            futures = {
                executor.submit(_processar_um, pid, estado): pid
                for pid in pendentes
            }
            for future in as_completed(futures):
                try:
                    future.result()
                except Exception as e:
                    logging.error("Excecao inesperada no worker: %s", e)
                barra.update(1)
                barra.set_postfix(erros_consec=estado.erros_consecutivos)
                if estado.parar.is_set():
                    for f in futures:
                        f.cancel()
                    break

    estado.flush_final()

    notificacoes = {
        "auth": (
            "🔒 [AUTH] Erro de autenticacao detectado -- renove o token e rode de novo.",
            f"O script parou ao processar {trt} / {ano} por erro de autenticacao "
            f"(provavel expiracao de token) em {datetime.now():%d/%m/%Y %H:%M:%S}.\n\n"
            "Renove o token PDPJ e rode o script novamente para continuar de onde parou.",
        ),
        "tempo_esgotado": (
            "⏰ [TEMPO] Orcamento de sessao esgotado -- renove o token e rode de novo.",
            f"O script encerrou a sessao ao processar {trt} / {ano} em "
            f"{datetime.now():%d/%m/%Y %H:%M:%S} porque o limite de {SESSION_BUDGET_SECONDS // 3600}h"
            f"{(SESSION_BUDGET_SECONDS % 3600) // 60}min foi atingido.\n\n"
            "Renove o token PDPJ e rode o script novamente para continuar de onde parou.",
        ),
    }
    if estado.motivo_parada in notificacoes:
        msg_console, corpo_email = notificacoes[estado.motivo_parada]
        print(f"\n{msg_console}")
        _notificar(msg_console, corpo_email)
        return False

    return True


# ---------------------------------------------------------------------------
# MAIN
# ---------------------------------------------------------------------------
def main():
    arquivos = _listar_arquivos_entrada()
    if not arquivos:
        print(f"Nenhum arquivo encontrado em {INPUT_DIR}/ para os filtros configurados.")
        return

    motivo_fim = "concluido"
    for nome_arquivo, trt, ano in arquivos:
        if tempo_de_sessao_esgotado():
            motivo_fim = "tempo_esgotado"
            print("Orcamento de tempo esgotado antes de iniciar novo arquivo. Encerrando.")
            break
        if not _processa_arquivo(nome_arquivo, trt, ano):
            motivo_fim = "parada_antecipada"
            break

    msg_fim = (
        "\nSessao encerrada. Renove o token e rode de novo para continuar --\n"
        "processos ja baixados e processos com erro registrado serao pulados automaticamente.\n"
        f"Erros estao registrados em {OUTPUT_DIR}/erros_{{trt}}_{{ano}}.csv\n"
        "(delete linhas 'transitorio' para retentar esses processos na proxima sessao)."
    )
    print(msg_fim)

    if motivo_fim == "concluido":
        _notificar(
            "✅ Processamento concluido",
            f"O script finalizou o processamento de todos os arquivos com sucesso "
            f"em {datetime.now():%d/%m/%Y %H:%M:%S}.\n\n{msg_fim}"
        )
    elif motivo_fim == "tempo_esgotado":
        _notificar(
            "⏰ Sessao encerrada por tempo",
            f"O script encerrou em {datetime.now():%d/%m/%Y %H:%M:%S} porque o "
            f"limite de sessao foi atingido antes de iniciar um novo arquivo.\n\n"
            "Renove o token PDPJ e rode o script novamente para continuar de onde parou."
        )


if __name__ == "__main__":
    main()
