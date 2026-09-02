# Auditoria de fonte — SINASC (Sistema de Informações sobre Nascidos Vivos)

**Data da auditoria:** 2026-09-02  
**Auditor:** pipeline assistido (mr-child-marriage-brazil, MODE: DATA AUDITOR)  
**Propósito:** avaliar o SINASC como outcome comportamental de alta potência para o Paper 1
(avaliação causal da Lei nº 13.811/2019): situação conjugal de mães adolescentes no
nascimento, por idade exata, mês e residência.

## 1. Data Source Ledger

| Campo | Valor |
|---|---|
| Nome oficial | Sistema de Informações sobre Nascidos Vivos (SINASC) |
| Instituição produtora | Ministério da Saúde — Secretaria de Vigilância em Saúde e Ambiente (SVSA) |
| Documento-base | Declaração de Nascido Vivo (DN), preenchida no estabelecimento de saúde ou cartório |
| Distribuição usada | CSVs anuais nacionais do OpenDataSUS (dataset "Sistema de Informação sobre Nascidos Vivos – Sinasc", Ministério da Saúde, licença CC-BY), hospedados em `https://s3.sa-east-1.amazonaws.com/ckan.saude.gov.br/SINASC/csv/` |
| Cobertura disponível | 1996–2026 (2024 = final; 2025 = preliminar; 2026 = 1ª prévia) |
| Cobertura usada no projeto | 2013–2024 (janela idêntica à do Registro Civil/SIDRA 4406) |
| Unidade de observação | nascido vivo (uma linha por DN) |
| Universo | todos os nascidos vivos registrados no território nacional |
| Geografia | município de residência da mãe (`CODMUNRES`) e de ocorrência (`CODMUNNASC`) |
| Variáveis-chave | `IDADEMAE`, `ESTCIVMAE`, `DTNASC`, `DTNASCMAE`, `CODMUNRES`, `SEXO`, `ESCMAE2010`/`ESCMAEAGR1`, `RACACORMAE`, `QTDFILVIVO`, `CONSPRENAT`, `MESPRENAT`, `PESO`, `SEMAGESTAC` |
| Restrições de acesso | público, sem cadastro; CSVs abertos são anonimizados (sem `NUMERODN`/nomes) |
| Data de acesso | 2026-09-02 |
| Cache local | `data/raw_external/sinasc/*.zip` com `SHA256_MANIFEST.txt` |
| Dicionários arquivados | `references/sinasc/Dicionario_SINASC_DN.pdf` (SVS/MS, tabela DN; SHA-256 `e20200c8…`) e `references/sinasc/SINASC_Estrutura_atual.pdf` (OpenDataSUS "Dicionário de Dados"; SHA-256 `0ffc4599…`) |
| Status | **verified** para layout e variáveis; **pending** para conferência dos totais anuais contra publicação oficial (ver §5) |

## 2. Variáveis verificadas no dicionário oficial (SVS/MS)

Fonte: `Dicionario_de_Dados_SINASC_tabela_DN.pdf`, baixado de
`https://svs.aids.gov.br/download/Dicionario_de_Dados_SINASC_tabela_DN.pdf` em 2026-09-02
(domínio oficial da SVS/Ministério da Saúde). Confirmado também no dicionário vigente do
OpenDataSUS (`https://diaad.s3.sa-east-1.amazonaws.com/sinasc/SINASC+-+Estrutura.pdf`).

- **`ESTCIVMAE`** — "Situação conjugal da mãe: 1– Solteira; 2– Casada; 3– Viúva;
  4– Separada judicialmente/divorciada; **5– União estável**; 9– Ignorada."
  A distinção casamento civil × união estável existe no instrumento — exatamente a margem
  formal × informal de que o Paper 1 precisa.
- **`IDADEMAE`** — idade da mãe (anos completos, 2 dígitos).
- **`DTNASCMAE`** — data de nascimento da mãe (ddmmaaaa) → idade exata em dias no parto.
- **`DTNASC`** — data de nascimento da criança (ddmmaaaa) → frequência diária/mensal.
- **`CODMUNRES`** — município de **residência** da mãe (resolve a incompatibilidade
  cartório × residência do Registro Civil).
- Covariáveis: escolaridade (`ESCMAE2010`, `ESCMAEAGR1`), raça/cor da mãe (`RACACORMAE`),
  paridade (`QTDFILVIVO`, `QTDGESTANT`), pré-natal (`CONSPRENAT`, `MESPRENAT`), idade do pai
  (`IDADEPAI`), peso ao nascer (`PESO`), gestação (`SEMAGESTAC`).

## 3. Rota de aquisição e o que foi testado

1. **FTP DATASUS (`ftp.datasus.gov.br`, DBC)** — **inacessível** deste ambiente em
   2026-09-02: sem TLS (porta 443 ausente) e timeout na porta 80/FTP mesmo fora do sandbox;
   o backend `datasus.saude.gov.br/wp-content/ftp.php` devolveu HTTP 500 (indício de
   indisponibilidade do próprio serviço no dia). Não é a rota usada.
2. **OpenDataSUS/CKAN antigo (`opendatasus.saude.gov.br`)** — redireciona integralmente para
   o novo portal; API CKAN antiga fora do ar; `ckan-dadosabertos.saude.gov.br` recusa
   conexões diretas.
3. **Rota adotada (funcional): portal `dadosabertos.saude.gov.br`** → dataset Sinasc →
   CSVs anuais em S3 (HTTPS). Metadados do dataset obtidos pela rota de dados do próprio
   portal. `metadata_modified` do dataset: 2026-08-31. Arquivos regenerados em 2026-05-07.

Testes executados (DuckDB 1.5.1, threads=12, memory_limit=14GB, sem expansão persistente):

- `SINASC_2019_csv.zip` (110,1 MB; SHA-256 `4d528a8b…`) → `SINASC_2019.csv`, 64 colunas,
  separador `;`, cabeçalho MAIÚSCULO, **2.849.146 linhas**, zero linhas malformadas.
- `DNBR2015_csv.zip` (104,3 MB; SHA-256 `ea73be3b…`) → `DNBR2015.csv`, cabeçalho minúsculo
  (inclui `numerodn`), **2.786.525 linhas** com `null_padding` — a **última linha do arquivo
  é truncada** (6 de 64 colunas); zero rejeições adicionais.

## 4. Resultados da auditoria de conteúdo (2015 e 2019)

Mães com `IDADEMAE` entre 10 e 15 anos (tratadas pela Lei 13.811/2019):

| Ano | N mães 10–15 | Solteira | **Casada** | **União estável** | Ignorada+NA | `DTNASCMAE` missing |
|---|---:|---:|---:|---:|---:|---:|
| 2015 | 69.709 | 73,2% | **1,09% (758)** | **23,98% (16.714)** | 1,65% | 1,5% |
| 2019 | 54.866 | 78,8% | **0,68% (374)** | **19,22% (10.546)** | 1,27% | (<18: 1,5%) |

Mães de 16–17 anos em 2019: 3,90% casadas, 23,3% em união estável (n=139.922).

Série mensal 2019 (mães <16): 4.000–5.000 nascimentos/mês; casadas entre 19 e 47/mês, sem
colapso visível em abril–dezembro (média jan–mar 34,7; abr–dez 30,0) — consistente com a
leitura de que `ESTCIVMAE=2` mede **estoque** de casadas entre parturientes, que decai
lentamente, e não fluxo de casamentos.

Implicações de potência para o Paper 1: o SINASC observa ~55–70 mil nascimentos/ano de mães
<16 (contra 194 registros de casamento aos 15 nas células tratadas de 2019T2–T4 no SIDRA) e
~10–17 mil mães <16 em união estável por ano — ordens de magnitude mais eventos para margem
informal e covariáveis individuais que o Registro Civil não tem.

## 5. Limitações e pendências (obrigatórias no paper)

1. **`ESTCIVMAE` é autodeclarada/informada no preenchimento da DN**, mede situação conjugal
   no momento do parto (estoque entre parturientes), não fluxo de casamentos; não há
   verificação cartorial. Mudanças de declaração (casada → união estável) podem refletir
   relabeling e não comportamento.
2. **Condicionamento em nascimento**: qualquer análise usa a população de mães adolescentes,
   que é selecionada; efeitos da lei sobre fecundidade deslocam a composição. Tratar como
   outcome conjunto (fecundidade × formalização), nunca como amostra aleatória de adolescentes.
3. **Quebra de geração de arquivos 2015→2016** (`DNBR*` minúsculo com `numerodn` ×
   `SINASC_*` maiúsculo sem `numerodn`): harmonização de schema obrigatória no ingest;
   última linha truncada em `DNBR2015.csv` (tratar com `null_padding` e log).
4. **Totais anuais conferidos contra publicação oficial em 2026-09-02 — RESOLVED, com
   achado material.** Fonte: Boletim Epidemiológico especial SVSA (março/2023; fonte
   `svsa_boletim_mulher_2023`, arquivada com hash). Resultado: 2014 = 2.979.259 bate
   exatamente com o CSV aberto; a identidade contábil da soma 2014–2021 (22.974.531)
   revela déficit de 231.143 registros atribuível integralmente a **2015** (oficial
   implícito 3.017.668 vs 2.786.525 na exportação aberta, −7,7%; mesmos 2.786.525 na
   variante JSON oficial), corroborado pela incidência publicada de microcefalia de 2015
   (denominador ≈2,95M) e pela depressão de out–dez no arquivo. **O ano 2015 da
   exportação aberta é inválido para análise** — excluído por emenda registrada
   (`SINASC_EXTENSION_AMENDMENTS.md`, A1). 2021: preliminar do boletim (2.672.046) <
   consolidado aberto (2.677.101), direção esperada. 2013 e 2022–2024: sem âncora
   externa (`unanchored`); correção definitiva exige a base DBC consolidada do DATASUS
   quando a rota estiver acessível.
5. 2025–2026 são preliminares; não usar além de descrição explícita.
6. Ética: dados públicos anonimizados de menores; reportar apenas células agregadas; não
   tentar reidentificação; atenção a células pequenas em cruzamentos finos (idade exata ×
   município × mês).

## 6. Veredicto de prontidão

**CONDITIONALLY READY.** Layout, variáveis e acesso verificados; conteúdo de 2015 e 2019
auditado e consistente com o desenho; aquisição 2013–2024 automatizável por HTTPS com
manifesto SHA-256. Bloqueiam o Gate 3 apenas: (i) conferência dos totais anuais contra
publicação oficial; (ii) harmonização de schema entre gerações de arquivo; (iii) definição
congelada dos estimandos SINASC (emenda ao specification lock **antes** de qualquer contraste
pós-reforma além dos already-reported acima, que são descritivos e de auditoria).

## 7. Fontes oficiais abertas nesta auditoria

- Ministério da Saúde. Dataset "Sistema de Informação sobre Nascidos Vivos – Sinasc",
  Portal de Dados Abertos do SUS: `https://dadosabertos.saude.gov.br/dataset/sistema-de-informacao-sobre-nascidos-vivos-sinasc`. Acesso 2026-09-02.
- SVS/MS. Dicionário de Dados do SINASC — tabela DN:
  `https://svs.aids.gov.br/download/Dicionario_de_Dados_SINASC_tabela_DN.pdf`. Acesso 2026-09-02.
- Ministério da Saúde. SINASC — Estrutura (dicionário vigente, OpenDataSUS):
  `https://diaad.s3.sa-east-1.amazonaws.com/sinasc/SINASC+-+Estrutura.pdf`. Acesso 2026-09-02.
- Ministério da Saúde. Página institucional do SINASC:
  `https://www.gov.br/saude/pt-br/composicao/svsa/sistemas-de-informacao/sinasc`. Acesso 2026-09-02.
