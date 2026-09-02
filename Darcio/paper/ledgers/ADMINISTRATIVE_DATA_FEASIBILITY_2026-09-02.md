# Administrative-data feasibility — exact Registry events and the judicial gate

**Date:** 2026-09-02
**Mode:** research architecture / data audit
**Decision:** pursue restricted IBGE Civil Registry microdata first; pursue
secrecy-inclusive judicial aggregates as a complementary mechanism source. Do not use
the public DataJud class-143 series for estimation.

## Question and identification payoff

The current paper cannot distinguish a March 2019 legal effect from a gradual pre-law
tightening of judicial authorization below age 16. It also observes age and timing at
registration rather than exact age and date at celebration, and assigns geography by
registration office rather than residence. The highest-return new information is therefore:

1. exact dates of marriage and birth plus the spouses' municipality of residence; and
2. monthly requests, grants, and refusals for judicial authorization below age 16.

The first source changes the design itself. The second measures a proposed enforcement
mechanism and can test whether the practical gate closed before the statutory gate.

## Main finding

The exact-date source is not hypothetical. The official IBGE marriage questionnaire
(`RC.2`) collects the day, month, and year of marriage; day, month, and year of birth for
both spouses; and municipality/UF of domicile or residence for both spouses. The same
fields appear in the official 2009 instruction manual and the 2022 questionnaire, which
bracket most of the paper's 2013--2024 window. An IBGE confidentiality manual explicitly
states that Civil Registry microdata are not released publicly because of reidentification
risk and that external researchers may use non-deidentified microdata in the controlled
Sala de Acesso a Dados Restritos (SAR). Thus the SAR route is **verified**, although the
retention, completeness, and coding of every requested field in the 2013--2024 analytical
files remain to be confirmed by the IBGE technical team.

The judicial source also exists, but the public version fails the feasibility gate. The CNJ
DataJud API contains TPU class 143, `Suprimento de Idade e/ou Consentimento`, but only for
public proceedings. Marriage proceedings ordinarily run under judicial secrecy, class 143
combines age and parental-consent cases, and the mandated historical load does not guarantee
closed cases before 2020. A live aggregate probe of all 27 state-court endpoints found severe
date corruption and sparse usable pre-law coverage. The full DataJud receives public and
secret proceedings, so a secrecy-inclusive aggregate extract through a research agreement
remains worth requesting.

## Verified source ledger

| Source | What was verified | Access/coverage limitation | Status |
|---|---|---|---|
| [IBGE Civil Registry page](https://www.ibge.gov.br/estatisticas/sociais/populacao/9110-estatisticas-do-registro-civil.html?lang=pt-BR) and 2022 `RC.2` questionnaire | Marriage and registration dates; both spouses' dates of birth; place of birth; domicile/residence; prior civil status; registry-office geography | Public tables suppress the event-level combination of exact dates and residence | **verified externally** |
| [IBGE Civil Registry instruction manual](https://www.ibge.gov.br/biblioteca/visualizacao/instrumentos_de_coleta/doc2675.pdf) | The 2009 manual defines the same exact-date and residence fields and their edit rules | A manual proves collection instructions, not completeness in every annual retained file | **verified externally** |
| [IBGE confidentiality manual](https://biblioteca.ibge.gov.br/visualizacao/livros/liv101636.pdf) | Civil Registry microdata are not publicly released; external researchers can use non-deidentified microdata in the SAR | Access requires an approved project and controlled disclosure | **verified externally** |
| [IBGE SAR page](https://www.ibge.gov.br/acesso-informacao/sala-de-acesso-a-dados-restritos.html) and [user guide](https://www.ibge.gov.br/images/pdf/acessoinformacao/guia_do_usuario_da_sala_de_acesso_a_dados_restritos_202211.pdf) | Institutional affiliation, project review, confidentiality agreement, supervised use, disclosure review, and a fee are required | Current processing time and exact cost are not stated in the materials examined | **verified externally** |
| [Current Gov.br SAR service](https://www.gov.br/pt-br/servicos/solicitacao-de-acesso-a-sala-de-dados-restritos) | The application service is active; the page was last modified on August 25, 2026 and accepts institution-affiliated researchers | Cost and processing time are currently listed as variable/not estimated | **verified externally** |
| [CNJ DataJud access page](https://datajud-wiki.cnj.jus.br/api-publica/acesso/) and [glossary](https://datajud-wiki.cnj.jus.br/api-publica/glossario/) | The public API exposes metadata for public proceedings: filing date, class, subjects, adjudicating body/municipality, and movements | No party age, legal basis, pregnancy indicator, or reliable final-outcome field is documented | **verified externally** |
| [CNJ Resolution 331/2020](https://atos.cnj.jus.br/atos/detalhar/3428), as amended by [Resolution 437/2021](https://atos.cnj.jus.br/atos/detalhar/4212) | Full DataJud receives public and secret cases; its minimum initial load is pending cases and cases closed since 2020; data beyond the public API may be requested by a research institution under a specific agreement | A complete pre-2019 history is not mandated | **verified externally** |
| [CPC, art. 189(II)](https://www2.camara.leg.br/legin/fed/lei/2015/lei-13105-16-marco-2015-780273-normaatualizada-pl.pdf) | Proceedings concerning marriage run under judicial secrecy | The public API cannot reveal how many relevant secret proceedings it omits | **verified externally** |
| [CNJ state-court class table](https://www.cnj.jus.br/wp-content/uploads/2011/02/tabela-de-classes-justia-estadual.pdf) | TPU 143 is `Suprimento de Idade e/ou Consentimento` | The title conflates two legally different requests | **verified externally** |
| [CNJ document-retention act](https://atos.cnj.jus.br/atos/detalhar/2512) | Marriage-habilitation records can include a sentence supplying marriageable age; the retention table recognizes age/consent proceedings | Local archival completeness and digitization are not established | **verified externally** |

## Public DataJud probe

The optional script `src/25_probe_datajud_class143.R` queried class 143 with `size=0`:
no case hits, process numbers, party data, or individual records were requested or retained.
The query ran against all 27 official state-court endpoints on 2026-09-02. Its SHA-256 is
`a9d24da6afe736c814e56c91302603ff611ebff3037c74164dd078922d369399`.

The snapshot returned:

- 3,574 public class-143 records and successful responses from all 27 courts;
- 3,363 records (94.1%) with a filing date after the snapshot, concentrated in impossible
  years 2564--2612;
- only 211 records with a plausible filing date, of which 179 fall in 2013--2024;
- 52 plausible filings in 2013--2018, 22 in 2019, and 105 in 2020--2024;
- any plausible 2019 record in only PE, RJ, and SP; any plausible 2013--2018 record in only
  AC, PE, RJ, and SP;
- 125 nonzero court-month cells out of 3,888 cells in 2013--2024 (96.8% zero);
- 1,125 records (31.5%) with at least one TPU merit-movement flag 219, 220, or 221. These
  flags are neither exhaustive nor necessarily mutually exclusive across a process history.

These are counts of indexed **public** records, not incidence estimates. Zeros can mean no
case, secrecy, incomplete historical migration, misclassification, or a corrupt filing date.
The public series is therefore a **no-go** for either an interrupted time series or a panel
linked to marriage registrations.

Reproducible aggregate artifacts:

- `outputs/audit/DATAJUD_CLASS_143_PUBLIC_PROBE.csv`;
- `outputs/audit/DATAJUD_CLASS_143_PUBLIC_BY_YEAR.csv`;
- `outputs/audit/DATAJUD_CLASS_143_PUBLIC_BY_MONTH.csv`;
- `outputs/logs/25_probe_datajud_class143.log`.

## Design unlocked by restricted Registry microdata

The preferred estimand becomes the change in the formal-marriage event rate immediately
below age 16 after the reform, relative to the event rate immediately above age 16 and to the
same age discontinuity before the reform. This is an **age-by-calendar difference in
discontinuities for event rates**, not an individual-outcome RD and not a design that conditions
only on observed marriages without an exposure denominator.

A feasible event-rate panel would index exact age in days (or narrow age bins) and calendar
date, with counts of celebrations as the numerator and a compatible birth-cohort population
exposure as the denominator. The pre-law discontinuity at 16 absorbs the already-existing
general marriageable-age rule; the post-minus-pre change isolates the elimination of the
below-16 exception under a continuity assumption for the age-hazard discontinuity at the
March 2019 reform date.

The restricted fields also permit three lower-risk improvements even if the local design is
not sufficiently powered:

1. classify eligibility by exact age on the date of celebration rather than completed age on
   the date of registration;
2. align treatment to the exact celebration date and measure the celebration-to-registration
   lag directly; and
3. construct residence-based local or regional rates rather than mixing registry-office and
   residence geography.

Necessary diagnostics are birthday/date heaping, missing exact dates, manipulation or delay
just above age 16, bandwidth sensitivity, calendar-date seasonality, placebo policy dates,
placebo age cutoffs, pre-law stability of the age discontinuity, and compatible risk-set
denominators. Exact dates improve the design; they do not make these assumptions automatic.

## What judicial aggregates would and would not identify

A secrecy-inclusive monthly series of requests and decisions would directly test whether the
approval gate was closing before March 2019. The key outcomes are request volume, approval
rate, refusal rate, time to decision, and the distribution of applicant age. A fall in approved
requests accompanied by a rising refusal rate before the law would support de facto tightening;
a fall in requests alone could reflect demand, legal advice, or composition.

These data would not, by themselves, create an untreated control for a national reform.
Court-level differences in pre-law approval or judge behavior could support a heterogeneity or
mechanism design only after assignment, case mix, and differential trends are audited. A judge-
leniency design requires quasi-random case assignment and cannot be presumed from the
existence of judge identifiers.

## Minimum data request: IBGE SAR

Request the 2013--2024 event-level `RC.2` files inside the SAR with only the variables needed
for analysis:

- date of marriage/celebration (day, month, year);
- date of registration (day, month, year or reference-year component);
- date of birth of each spouse (day, month, year);
- sex and prior civil status of each spouse;
- municipality/UF of domicile or residence of each spouse;
- municipality/UF and non-identifying code of the registration office;
- event composition and a within-SAR event key sufficient to avoid double counting;
- missing, edit, imputation, collection-mode, and annual-layout flags.

Do **not** request names, addresses, book/record numbers, or any direct identifier. Export only
disclosure-reviewed aggregates, coefficients, and diagnostics. Before approval, ask the
technical team to confirm that the listed fields are retained and consistently coded in each
year, including São Paulo's SEADE feed.

## Minimum data request: CNJ / courts

Ask first for a central, secrecy-inclusive **aggregate** tabulation from the full DataJud or
another CNJ source, covering class 143 and mapped local/predecessor classes for 2013--2024.
The smallest useful cell contains:

- tribunal, comarca, and IBGE municipality code;
- filing month and first-decision month;
- request basis: age, parental consent, both, or unknown;
- applicant age band: under 14, 14, 15, 16, 17, or unknown;
- pregnancy exception invoked: yes, no, or unknown, if structured/derivable;
- outcome: granted, partly granted, denied, dismissed without merits, pending, or unknown;
- public/secret status, retained only as an aggregate dimension;
- source system, mapped original class code, and a tribunal-month completeness flag.

No name, date of birth, address, party identifier, process number, or text of a secret case is
needed. If the basis and age are not structured in DataJud, request a data dictionary and a
small controlled pilot before any national extraction. If the CNJ cannot provide the series,
send the same aggregate template to the 27 TJs/Corregedorias.

## Draft technical inquiry to IBGE — not sent

> **Assunto: viabilidade de projeto na SAR — microdados de casamentos do Registro Civil,
> 2013--2024**
>
> Estamos preparando um projeto acadêmico sobre a Lei nº 13.811/2019. O formulário oficial
> RC.2 indica a coleta da data do casamento, data do registro, datas de nascimento e município
> de domicílio/residência dos cônjuges. Antes de submeter o projeto à SAR, solicitamos confirmar:
> (i) se esses campos estão retidos nos arquivos individuais de casamentos de 2013 a 2024;
> (ii) se a codificação e cobertura são comparáveis entre anos e incluem o fluxo recebido da
> Fundação SEADE para São Paulo; (iii) quais flags de crítica, imputação e forma de coleta estão
> disponíveis; e (iv) se o projeto pode exportar apenas tabulações e estimativas submetidas à
> revisão de confidencialidade. Não solicitaremos nomes, endereços, números de livro/registro ou
> qualquer identificador direto.

## Draft institutional request to CNJ — not sent

> **Assunto: consulta de viabilidade — tabulação agregada e sigilo-inclusiva da classe TPU 143**
>
> Para pesquisa acadêmica sobre a alteração do art. 1.520 do Código Civil pela Lei nº
> 13.811/2019, solicitamos avaliar a possibilidade de produzir tabulação mensal agregada,
> incluindo processos públicos e sigilosos, da classe TPU 143 (`Suprimento de Idade e/ou
> Consentimento`) e de classes locais, predecessoras ou sucessoras equivalentes, no período
> 2013--2024. A tabulação proposta contém apenas tribunal/comarca/município, mês de ajuizamento
> e decisão, fundamento (idade versus consentimento), faixa etária, resultado, indicador agregado
> de sigilo, sistema de origem e completude. Não solicitamos número de processo, identificação
> das partes, datas de nascimento, endereços ou texto dos autos. Caso os campos não sejam
> estruturados, solicitamos inicialmente apenas o dicionário, o mapa de classes locais e uma
> avaliação de viabilidade para projeto institucional nos termos do art. 11, parágrafo único, da
> Resolução CNJ nº 331/2020.

## Go/no-go rules

Advance the restricted Registry redesign only if:

1. exact celebration and birth dates are available with at least 99% valid values in the target
   ages, or missingness can be bounded without a policy-date discontinuity;
2. 2013--2024 coverage reconciles to published IBGE totals by year, age, sex, and registration
   geography;
3. residence municipality is present and valid for at least 95% of target events, with a
   prespecified fallback to region;
4. a compatible exact-age risk-set denominator can be constructed and validated; and
5. the number of events within candidate bandwidths supports a meaningful MDE.

Advance the judicial series as more than a descriptive mechanism only if:

1. it includes secret cases and certified historical completeness for 2013--2019;
2. age-supply cases can be separated from parental-consent cases;
3. applicant age, filing/decision dates, and outcome are available with at least 95% usable
   coverage; and
4. at least 24 of 27 courts, or courts covering at least 90% of under-16 Registry events, have
   comparable monthly data with explicit structural zeros.

Otherwise, retain the current paper's unresolved timing threat and do not backfill the gap with
the public API.

## Priority

1. **IBGE SAR technical inquiry and project:** highest identification return; verified path and
   verified questionnaire fields.
2. **CNJ institutional feasibility request:** complementary enforcement mechanism; full base
   includes secret cases, but relevant fields and pre-2019 completeness are unverified.
3. **TJ/Corregedoria requests:** fallback if the CNJ cannot generate the central aggregate.
4. **Public DataJud:** audit/provenance only; no-go for estimation.

No inquiry or data request was transmitted during this audit. Sending either draft requires the
researcher's institutional details and explicit authorization.
