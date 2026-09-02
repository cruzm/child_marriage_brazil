# Piloto cross-country — resultados sob o protocolo congelado

**Executado:** 2026-09-02, sob `PILOT_PROTOCOL.md` (hash `cb3c503c…`, congelado antes de
qualquer valor ser consultado). Script: `pull_dhs.py` (regras de implementação fixadas
no cabeçalho antes da primeira consulta). Dados: API pública do DHS Program; respostas
brutas arquivadas em `outputs/raw/`. Tabelas: `PILOT_METRICS.csv`,
`PILOT_COHORT_SERIES.csv`. Figura: `PILOT_FIGURE_TRAJECTORIES.(png|pdf)`.

## Veredicto (regra congelada: regra ≥6 em queda; exceção ≤3)

**EXCEÇÃO — e de forma inequívoca: 0 de 7 países computáveis tinham a margem vinculada
em queda (M2 ≤ −20%) na década pré-reforma.** A hipótese "o mundo bane margens em
extinção" é REJEITADA neste roster. Os países que elevaram a idade mínima baniram
margens grandes e aproximadamente estáveis — o oposto do caso brasileiro.

| País | Reforma | M1 (by-18 na reforma, %) | M2 (Δ10 anos, %) | M1b (by-15) | M3 (% formal 15–19) | Classe |
|---|---|---:|---:|---:|---:|---|
| Benin | 08/2004 | 37,3 | **+1,6** | 15,3 | 73,4 (pré) | viva |
| Mauritânia | 07/2001 | 40,6 | **+0,2** | 15,1 | — | viva |
| Nepal | 09/2002 | 50,5 | **−2,1** | 13,2 | 100 (pós) | viva |
| Etiópia | 2000 | 52,8 | **−13,9** | 26,7 | 98,7 (pré) | viva |
| Tajiquistão | 07/2010 | 11,9 | **−15,6** | 0,2 | 100 (pós) | viva |
| Bangladesh | 2017 | 52,0 | **−19,9** | 17,3 | — | viva (na margem do corte) |
| Moçambique | 2019 | 48,4 | **−5,2** | 12,9 | 56,6 (pré) | viva |
| Indonésia | 2019 | — (coortes até 2013) | — | — | 96,8 (pré) | n/c |
| Honduras (alternate) | 2017 | — (coortes até 2007) | — | — | **7,5** (pré) | n/c |
| Butão | 07/1996 | — sem DHS | — | — | — | gap |
| Cazaquistão | 12/1998 | — sem séries na API | — | — | — | gap |

Nota de honestidade: Bangladesh (−19,9%) fica a 0,1 p.p. do corte congelado (−20%);
mesmo reclassificado, 1 ≤ 3 → o veredicto EXCEÇÃO não depende dele.

## O achado colateral que importa para o Paper 1

**A clivagem é de regime de formalidade, e é regional.** Onde os bans foram estudados e
"morderam" (Etiópia, Nepal, Bangladesh, Benin…), a margem adolescente em união é
majoritariamente FORMAL no sentido do survey (M3 = 73–100%) — a lei alcança o que
existe. Nos regimes latino-americanos de união consensual, a margem é informal-dominante
(Honduras M3 = 7,5%; Brasil, pelos nossos dados, análogo), e o ban vincula pouco.
Caveat vinculante: "married" no DHS inclui casamento religioso/costumeiro, não equivale
a registro civil — M3 é proxy de formalidade declarada, não de registro.

## Implicações (conforme decisão pré-escrita no protocolo e na estratégia)

1. **Caminho "The World Is Banning a Vanishing Margin": ENCERRADO.** Não há paper
   cross-country nessa tese; a semana de piloto economizou seis.
2. **O Paper 1 fica MAIS forte como está:** o Brasil não é ilustração de um fenômeno
   global — é o caso-limite de um REGIME (união informal dominante + margem formal
   vestigial) que a literatura de bans, concentrada em regimes formais de alta
   prevalência, não cobre. A validade externa correta é: os resultados falam para
   regimes tipo latino-americano, e o contraste com os regimes formais explica POR QUE
   Etiópia/México-16-17 acham efeitos e nós não. Qualquer incorporação disso ao texto
   do Paper 1 exige novo mini-protocolo (regra do piloto), mas a redação candidata é um
   parágrafo de validade externa citando o piloto como descritivo.
3. **Ladder editorial confirmado:** JPopEcon / World Development primeiro (a rota JDE
   via generalização morreu). Atualizar `JOURNAL_STRATEGY.md` §5.

## Limitações

Margem-fenômeno (união por idade, definição DHS) ≠ margem formal de registro civil;
resolução quinquenal de coortes com recall; Cazaquistão sem séries do indicador na API
(surveys 1995/1999 não expõem MA_MBAG na API — gap reportado, não substituído);
Indonésia/Honduras com coortes insuficientes para M2 na data da reforma; datas de
Indonésia/Moçambique/Honduras `partially verified`. Nenhuma leitura causal.
