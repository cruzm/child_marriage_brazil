# SINASC extension — resultados sob o lock v1.0.0 + Amendment A1

**Estimado em:** 2026-09-02, após o congelamento de 11:28:14−03:00 e o registro da
Emenda A1 (exclusão do ano 2015 por exportação aberta incompleta — ver
`SINASC_EXTENSION_AMENDMENTS.md`; emenda registrada antes da reestimação). Scripts:
`src/21_build_sinasc.R`, `src/22_analyze_sinasc.R`, `src/23_export_sinasc_tables.R`.
Tabelas: `outputs/tables/SINASC_*.csv`, `TABLE_11`, `TABLE_12`. Figuras: `FIGURE_11`,
`FIGURE_12`.

## Veredicto em uma frase

**Os diagnósticos pré-especificados reprovam a interpretação causal dos contrastes de
situação conjugal (S1–S3): leads conjuntos p≈0; placebos de 2017 (+19,7%, p=0,004) e
2018 (+36,8%, p<0,001) do mesmo sinal e magnitude do estimando primário (+29,3%). O
conteúdo substantivo é descritivo: a parcela casada entre mães <16 caiu de 1,72% (2013)
para 0,88% (2016) e 0,69% (2019) — anos válidos — e estabilizou ANTES da lei, sem quebra
em março de 2019.**

## Números (razão de taxas em %; ano 2015 excluído em tudo — Emenda A1)

| Estimando | Efeito | IC95% | p (cluster período) | p Holm | Eventos tratados pós |
|---|---:|---:|---:|---:|---:|
| S1 casada (com tendências) | **+29,3%** | [+11,3; +50,1] | 0,0008 | 0,0015 | 270 |
| S1 sem tendências | **−23,9%** | [−33,6; −12,7] | <0,001 | — | 270 |
| S2 união estável | +3,7% | [+0,9; +6,7] | 0,010 | 0,010 | 7.848 |
| S3 qualquer união | +5,1% | [+2,2; +8,0] | 0,0004 | 0,0012 | 8.118 |
| S4 fecundidade idade 15 | +1,6% | [−1,3; +4,6] | 0,284 | 0,284 | 26.329 |
| S4 fecundidade idade 14 | −3,0% | [−6,1; +0,2] | 0,068 | 0,137 | 11.021 |
| Missingness diferencial (diagnóstico) | +3,4% | [−8,1; +16,3] | 0,577 | — | — |

Placebos: 2016 −5,9% (p=0,50); **2017 +19,7% (p=0,004); 2018 +36,8% (p<0,001)** — padrão
monótono no tempo, assinatura de tendência linear extrapolando decaimento convexo que
aplainou perto do piso. HAC Brasil mensal: +24,8% (p=0,024), mesmo artefato. Robustezes
com tendência (controles 18–19; 16–19; tratada só 15; idade exata; trimestral; missing
como não-casada; pré desde 2014): +22% a +33%. **Pré-janela iniciando em 2016 (regime já
plano): +1,5% (p=0,86)** — exatamente o previsto pela leitura de artefato: sem o trecho
íngreme 2013–2016 na amostra, a tendência linear deixa de fabricar efeito.

## Leitura vinculante

1. +29,3% é impossível mecanicamente como efeito causal (a lei só fecha o fluxo de
   entrada no estoque de casadas) e é reproduzido por placebos sem reforma — artefato de
   especificação, não tratamento.
2. Event study: pontos de 2017–2019 estáveis em ≈−30/−37% versus a base pré-2017, sem
   quebra na lei.
3. Bracket honesto do curto prazo por dependência de especificação: **[−23,9%; +29,3%]**,
   contém zero; causalmente não informativo.
4. S4 (fecundidade-composição) nulo; sem missingness diferencial.
5. Nenhuma reespecificação pós-resultado foi executada; a única mudança entre as duas
   rodadas foi a Emenda A1 (erro de dado documentado em 2015), que não alterou o veredicto.

## Validação de totais (pendência §5.4 do audit — RESOLVIDA)

Boletim Epidemiológico especial SVSA (março/2023, arquivado e hasheado): 2014 =
2.979.259 — **igual ao CSV aberto**; soma 2014–2021 = 22.974.531; identidade contábil
atribui o gap integral de 231.143 registros ao ano 2015 (oficial implícito: 3.017.668 vs
2.786.525 na exportação aberta, −7,7%), corroborado pela incidência publicada de
microcefalia de 2015 e pela depressão out–dez do arquivo. 2021 preliminar do boletim
(2.672.046) vs consolidado aberto (2.677.101): direção esperada. 2013 e 2022–2024:
sem âncora externa (flag `unanchored`).
