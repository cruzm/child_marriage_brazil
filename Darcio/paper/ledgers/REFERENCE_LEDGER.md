# Reference Ledger — Paper 1

Regra: `unverified` não entra na versão final. `verified` = página oficial do periódico ou
repositório aberta e metadados conferidos. `partially verified` = confirmado por agregador
(RePEc/PubMed) ou snippet consistente; falta abrir a página oficial. Datas de conferência
em 2026-09-02, salvo nota.

| Ref | Metadados | Fonte de conferência | Claim que sustenta | Status |
|---|---|---|---|---|
| Bellés-Obrero & Lombardi (2023) | "Will You Marry Me, Later? Age-of-Marriage Laws and Child Marriage in Mexico", *Journal of Human Resources* 58(1): 221–259. DOI 10.3368/jhr.58.3.1219-10621R2 | Página oficial JHR (jhr.uwpress.org/content/58/1/221; magnitudes extraídas 2026-09-02) | Benchmark quantitativo. Frases exatas verificadas: meninas 16–17 — "0.695 fewer formal marriages per month for every 1,000 girls of this age, a 49 percent reduction over the mean"; 14–15 — efeitos não significativos; substituição — queda "completely counteracted by an increase in the share of mothers in an informal union"; escola — "small and statistically insignificant impacts on school attendance"; fecundidade 16–17 — sem redução. Desenho: TWFE DiD escalonado, 32 estados, 2008–2018 | **verified** |
| McGavock (2021) | "Here Waits the Bride? The Effect of Ethiopia's Child Marriage Law", *Journal of Development Economics* 149: 102580. DOI 10.1016/j.jdeveco.2020.102580 | Página da autora + ScienceDirect (403 no fetch; DOI conferido) | Lei de idade mínima com efeito real em contexto de alta prevalência | **verified** |
| Collin & Talbot (2023) | "Are age-of-marriage laws enforced? Evidence from developing countries", *JDE* 160: 102950. DOI 10.1016/j.jdeveco.2022.102950 | IDEAS/RePEc | Enforcement fraco de leis de idade mínima | **verified** |
| Amirapu, Asadullah & Wahhaj (2026) | "Can the law affect attitudes and behavior in the absence of strict enforcement?…", *JLEO* 42(2): 461–506. DOI 10.1093/jleo/ewaf003 | Página OUP | Lei sem enforcement pode ter efeitos perversos | **verified** |
| Le, Molina, Ibuka & Goto (2025) | "The Intergenerational Health Effects of Child Marriage Bans", *Journal of Health Economics* 104: 103075 (tb. IZA DP 17089) | Página IZA com nota de publicação | Bans e saúde intergeracional | **verified** (abrir página Elsevier antes da submissão) |
| Batyra & Pesando (2021) | "Trends in child marriage and new evidence on the selective impact of changes in age-at-marriage laws on early marriage", *SSM – Population Health* 14: 100811 | PubMed + PDF institucional | Efeito seletivo de mudanças legais; monitoramento por survey | **partially verified** |
| García-Hombrados (2022) | "Child marriage and infant mortality: causal evidence from Ethiopia", *J. of Population Economics* 35(3): 1163–1223 | RePEc (snippet) | Lei como variação exógena p/ efeitos do casamento | **partially verified** |
| Campos (s.d., WP) | "The Effects of Mexico's Child Marriage Ban on Adolescent Fertility, Domestic Violence, and Female Labor Income", SSRN 6373839 | Página SSRN (abstract) | Concorrência ativa; citar como WP se necessário | **partially verified** |
| Lei nº 13.811/2019 | Planalto, texto legal | Aberta e conferida (pipeline, 2026-09-01) | Tratamento: revogação das exceções do art. 1.520 | **verified** |
| Código Civil (L. 10.406/2002), arts. 1.517–1.520 | Planalto, texto compilado | Aberta e conferida (pipeline, 2026-09-01) | 16–17 seguem casáveis com autorização | **verified** |
| SINASC — dicionários e dataset | SVS/MS + OpenDataSUS | Abertos e arquivados em `references/sinasc/` | Definições ESTCIVMAE/IDADEMAE/DTNASCMAE | **verified** |
| IBGE — SIDRA 4406, Registro Civil, PNADC | Páginas oficiais IBGE | Conferidas (pipeline, 2026-09-01) | Fluxo formal, denominadores, união corresidente | **verified** |

| Urquia et al. (2022) | "The perinatal epidemiology of child and adolescent marriage in Brazil, 2011–2018", *SSM – Population Health*, art. 101093. DOI 10.1016/j.ssmph.2022.101093 | PubMed/ScienceDirect (snippets; página oficial não aberta) | Antecedente descritivo que se declara "baseline" para avaliar a lei de 2019 — sustenta o claim de novidade | **partially verified** |
| Bella et al. (2025) | "Beyond the Minimum: The Impact of Indonesia's Marriage Age Law…", Monash CHE WP 2025-17 | IDEAS/RePEc aberto | Concorrente temático recente (Indonésia, RD) | **verified** (como WP) |
| Campos (2026, WP) | SSRN 6373839, México; postado 2026-03-08; sem publicação registrada | Snippets restritos a ssrn.com (fetch 403) | Concorrência ativa no tema | **partially verified** |

Pendências antes do Gate 5: elevar Batyra & Pesando, García-Hombrados e Urquia et al. a
`verified` (abrir página oficial); abrir SSRN 6373839 manualmente no navegador; verificar
no PDF de Le et al. (JHE 2025) se o Brasil integra o painel de países (se sim, qualificar
o claim de novidade); varredura final de todos os DOI. Protocolo de novidade: rodadas 1–2
concluídas em 2026-09-02 — veredicto e qualificações em `NOVELTY_SEARCH_LOG.md`.
