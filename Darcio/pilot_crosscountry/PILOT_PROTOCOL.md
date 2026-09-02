# Piloto cross-country — "o mundo bane margens em queda?" (protocolo congelado)

**Natureza:** piloto descritivo de 1 semana, decisório para a estratégia editorial do
Paper 1 (ver `paper/ledgers/JOURNAL_STRATEGY.md` §5). NÃO é análise causal. Congelado
ANTES de qualquer valor de indicador ser consultado na API do DHS; apenas o catálogo de
indicadores (metadados) foi inspecionado antes deste congelamento. Hash em
`PILOT_PROTOCOL_SHA256.txt`.

## Pergunta

Nos países que elevaram a idade mínima de casamento, a margem vinculada já estava em
queda (padrão Brasil) ou viva (padrão México 16–17) na década anterior à reforma?

## Roster (fixo; regra, não escolha)

(a) Os SEIS países da Tabela 1 de Batyra & Pesando (2021) — única lista publicada com
data exata (mês/ano) de implementação verificada por nós no texto completo (Europe PMC,
PMC8142081): Benin 08/2004; Butão 07/1996; Cazaquistão 12/1998; Mauritânia 07/2001;
Nepal 09/2002; Tajiquistão 07/2010 (todas para mínimo 18).
(b) Dois países com reforma verificada em referências do nosso ledger: Etiópia 2000
(Código de Família; McGavock 2021); Bangladesh 2017 (Child Marriage Restraint Act;
Amirapu et al. 2026).
(c) Dois países populosos com ban pós-2015 amplamente documentado, datas marcadas
`partially verified` até conferência no texto legal: Indonésia 2019 (Lei 16/2019,
idade da mulher 16→19); Moçambique 2019 (Lei 19/2019).
Alternate pré-especificado se algum país não tiver dados na API: Honduras 2017.
México e Brasil entram só como benchmarks de literatura (sem DHS recente).

## Dados e medição (regras fixas)

Fonte: API pública do DHS Program (`api.dhsprogram.com`), indicadores
`MA_MBAG_W_B18` e `MA_MBAG_W_B15` ("women first married by exact age 18/15" — a
definição DHS INCLUI uniões informais; isto mede a margem-fenômeno, não a formal) por
grupos etários quinquenais, todos os surveys disponíveis por país; e
`MA_MSTA_W_MAR`/`MA_MSTA_W_LTG` (status atual: casada vs coabitando) para mulheres
15–19 como proxy da participação FORMAL na margem.

**Construção de coortes:** célula (survey S, grupo etário [a,a+4]) → coorte que
completou 18 anos no ano c = ano(S) − (a+2 − 18). Grupos 20–24 … 45–49. Quando várias
pesquisas informam a mesma coorte (±2 anos), média ponderada pelos tamanhos amostrais
(ou simples, se N indisponível na API).

**Métricas por país (todas fixadas agora):**
- M1 = nível de married-by-18 na coorte da reforma (interpolação linear entre coortes
  vizinhas).
- M2 = variação relativa de married-by-18 entre a coorte da reforma e a coorte de 10
  anos antes (Δlog, em %).
- M1b/M2b = idem para married-by-15.
- M3 = MAR/(MAR+LTG) para 15–19 no survey mais próximo ANTERIOR à reforma (se não
  houver survey pré, o mais próximo posterior, marcado como tal): participação formal
  na margem adolescente.

**Classificação (fixa):** margem "em queda pré-reforma" se M2 ≤ −20%; "viva" se
M2 > −20%. Secundário: "formal-relevante" se M3 ≥ 50%; "informal-dominante" se
M3 < 50%. Veredicto do piloto: padrão Brasil é REGRA se ≥ 6 dos países computáveis
tiverem margem em queda; EXCEÇÃO se ≤ 3; zona cinzenta entre 4–5.

## Reporte obrigatório

CSV por país×coorte; CSV de métricas/classificação; uma figura (trajetórias
centradas no ano da reforma); results doc com veredicto, lacunas de dados (países sem
DHS na API são reportados como gap, não substituídos silenciosamente — o alternate só
entra se pré-anunciado aqui) e TODAS as limitações: margem-fenômeno ≠ margem formal;
coortes em resolução quinquenal; recall/deslocamento de idade em surveys; nenhuma
leitura causal.

## Interpretação vinculada

Este piloto decide apenas: (i) se a generalização "banindo margens em queda" merece
virar seção/paper (regra); ou (ii) se o Brasil segue caso-limite (exceção). Nenhum
resultado do piloto altera claims do Paper 1 sem novo protocolo.
