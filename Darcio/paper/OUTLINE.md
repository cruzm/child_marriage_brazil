# Paper 1 — Outline e espinha narrativa

**Título de trabalho:** Banning a Vanishing Margin: Brazil's Child Marriage Ban, Formal
Marriage, and Informal Unions
**Alvo:** JDE/JHR (stretch) · J. Population Economics / World Development / JPAM (realista)
**Idioma:** inglês acadêmico. **Status:** working draft v0.3, 2026-09-04.

## Espinha narrativa (uma linha por seção)

1. **Intro** — Leis de idade mínima regulam o casamento formal, mas o outcome social
   inclui uniões não registradas; o Brasil 2019 é um caso extremo em que nenhuma fonte
   pública valida sozinha um contrafactual causal.
2. **Background** — A Lei 13.811/2019 fechou as exceções do art. 1.520 para <16; 16–17
   continuaram casáveis com autorização; a margem <16 já era vestigial no registro.
3. **Data** — Três medidas que não se subtraem: fluxo formal (Registro Civil/SIDRA 4406),
   estoque de união corresidente (PNADC), situação conjugal no parto (SINASC).
4. **Strategy** — Hierarquia explícita: DiD por elegibilidade etária no Registro é a
   especificação originalmente travada, mas condicional à tendência; o SINASC diário é
   uma diferença-em-descontinuidades local e pós-resultado, com estabilidade temporal
   indispensável; PNADC e SINASC agrupado não são replicações do mesmo estimando.
5. **Results (registry)** — −1,1% [−14,9; +14,9] no modelo travado; sem tendências
   −37,8%. O rolling-origin pós-resultado reprova todos os cinco contrafactuais, logo o
   efeito permanece condicional; MDE 19,3% também é condicional ao modelo; sem recaptura
   confiável aos 16–17.
6. **Behavior (PNADC + SINASC)** — A PNADC não identifica redução da prevalência de
   união corresidente (+0,399 p.p., p=0,052; sugestivo, não prova de informalização).
   No SINASC diário, TAU = +0,342 p.p. [−0,140; +0,824], mas MDE80 = 0,688 p.p., G2 é
   qualificado e G3 inconclusivo; o agrupado segue como evidência de falha de tendência
   ([−23,9%; +29,3%], não intervalo causal).
7. **Robustness** — Placebos, janelas, sexo, DDD de exposição (não identifica), gates
   de densidade/composição e todos os 13 modelos congelados do SINASC diário.
8. **Discussion** — O que significa "proibir" quando o Estado só observa a margem formal:
   implicações para avaliação e monitoramento (ODS 5.3) de leis de idade mínima.

## Exhibit map (existente → paper)

| Exhibit paper | Fonte no repositório | Status |
|---|---|---|
| Fig. 1: Raw rates by age (registry) | FIGURE_01 | pronto |
| Fig. 2: Event study age 15 | FIGURE_03 | pronto |
| Fig. 3: Rolling-origin dos cinco contrafactuais | FIGURE_13_REGISTRY_TREND_SENSITIVITY | pronto (no paper) |
| Fig. 4: Age distribution / bunching | FIGURE_05 | pronto |
| Fig. 5: PNADC union prevalence + event study | FIGURE_07 + FIGURE_08 | pronto |
| Fig. 6: SINASC status shares (mothers 10–15 vs 17–19) | FIGURE_11_SINASC_STATUS_SHARES | pronto |
| Fig. 7: SINASC married-at-birth event study | FIGURE_12_SINASC_STATUS_EVENT_STUDY | pronto (appendix) |
| Fig. 8: SINASC diário ao redor dos 16 anos | FIGURE_14_SINASC_DAILY_RD | pronto (no paper) |
| Fig. A: saltos anuais aos 16 anos | FIGURE_SINASC_DAILY_G2_ANNUAL_JUMPS | pronto (appendix) |
| Fig. A: sensitividades congeladas do SINASC diário | FIGURE_SINASC_DAILY_G3_SENSITIVITY | pronto (appendix) |
| Tab. 1: Audit/coverage | TABLE_01 | pronto |
| Tab. 2: Registry primary + robustness | TABLE_03 + TABLE_04 | pronto |
| Tab. 3: Delay/recapture | TABLE_05 | pronto |
| Tab. 4: PNADC union | TABLE_07A/B | pronto |
| Tab. 5: Inference triangulation | TABLE_08 | pronto |
| Tab. 6: Power/MDE | TABLE_09 | pronto |
| Tab. 7: SINASC S1–S3 + diagnósticos + placebos + S4 | SINASC_STATUS_PRIMARY, SINASC_PLACEBO_DATES, SINASC_FERTILITY_S4 | pronto (TABLE_11/12) |
| Tab. 8: Calibração e efeitos dos cinco contrafactuais | TABLE_13_TREND_SENSITIVITY | pronto (appendix) |
| Tab. 9: SINASC diário, placebos e gates | TABLE_14_SINASC_DAILY_DESIGN | pronto (appendix; apenas outputs observados) |

## Placeholders ativos no manuscrito

- ~~REGISTRY TREND GATE~~ **RESOLVIDO 2026-09-02**: protocolo pós-resultado congelado
  antes das estimativas da extensão; 13/13 testes passam, mas 0/5 modelos atingem o tier
  qualificado. O envelope de pontos [−33,7%; +12,8%] não é bound causal; o intervalo do
  modelo sazonal [−54,7%; −0,3%] inclui queda de 49%. O texto foi reposicionado como
  dependência de contrafactual/falha de desenho.
- ~~SINASC DiD~~ **RESOLVIDO 2026-09-02**: estimado sob o extension lock v1.0.0; o
  desenho reprova os diagnósticos (leads p≈0; placebos 2017/2018 significativos);
  reportado como faixa de especificações [−23,9%; +29,3%], não como intervalo causal.
  Ver
  `outputs/analysis/SINASC_EXTENSION_RESULTS.md`.
- ~~SINASC fertility margin~~ **RESOLVIDO**: S4 idade 15 = +1,6% (IC95% [−1,3%;
  +4,6%], p=0,284); idade 14 = −3,0% (p Holm=0,137). Não tratar não rejeição como
  prova de efeito zero.
- ~~SINASC annual totals vs. SVSA~~ **RESOLVIDO 2026-09-02**: boletim SVSA (mar/2023)
  valida 2014 ao registro exato e revela exportação aberta de 2015 incompleta (−231.143,
  −7,7%); 2015 excluído por Emenda A1 (`SINASC_EXTENSION_AMENDMENTS.md`); reestimação
  não alterou o veredicto (bracket [−23,9%; +29,3%]).
- ~~NOVELTY SEARCH~~ **RODADAS 1–2 CONCLUÍDAS 2026-09-02**: 19 buscas registradas. O
  texto usa o claim mais estreito “first empirical evaluation centered on Brazil's 2019
  ban”; as checagens manuais pré-submissão permanecem no `NOVELTY_SEARCH_LOG.md`.
- ~~APPENDIX~~ **RESOLVIDO**: TABLE_11/12 SINASC geradas por `src/23_export_sinasc_tables.R`
  e appendix montado (SINASC + Registry/PNADC).
- ~~SINASC DAILY G0--G3~~ **RESOLVIDO 2026-09-04**: G0/G1 passam; G2 qualificado;
  G3 inconclusivo; decisão `DO_NOT_ADVANCE_AS_CAUSAL_CORE`. O paper usa a evidência
  local sem promovê-la e importa TABLE_14 diretamente de outputs reais.
- **REGRA DE PROVENIÊNCIA**: nenhum dado/coefficient de recuperação sintética do R0
  entra no manuscrito. O consistency check rejeita os nomes desses artefatos.
- Pendências administrativas do title page: e-mail, coautores, acknowledgments.
- Números pré-existentes do repositório citados no texto: conferidos contra
  outputs/tables/*.csv e TECHNICAL_REPORT.md em 2026-09-02; números SINASC conferidos
  contra outputs/tables/SINASC_*.csv em 2026-09-02.

## Consistency check (a rodar a cada revisão)

- Claim central = estimando (contraste curto, elegibilidade etária, registros aos 15)?
- Intro, tabelas e conclusão contam a mesma história (null impreciso + sem queda de união
  + sinal informal sugestivo)?
- Nenhum envelope de pontos é chamado de intervalo, identified set ou bound causal?
- O benchmark México é contextual e nunca “descartado” design-wide?
- Nenhum coeficiente de fluxo subtraído de coeficiente de estoque?
- Nenhuma referência `unverified` citada?
