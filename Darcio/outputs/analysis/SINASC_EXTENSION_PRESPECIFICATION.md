# SINASC extension — pre-specification frozen before estimation

**Version:** 1.0.0 · **Frozen:** 2026-09-02T11:28:14−03:00 · **Machine-readable:**
`config/sinasc_extension_lock.yml` · **Hashes:** `SINASC_EXTENSION_LOCK_SHA256.txt`

Esta extensão adiciona estimandos baseados no SINASC à avaliação da Lei nº 13.811/2019.
Nada no lock original (Registro Civil e PNADC) é alterado. Nenhum contraste pós-reforma do
SINASC foi estimado antes deste congelamento.

## 1. Objeto e motivação

O Registro Civil mede o fluxo de casamentos formais (194 registros nas células tratadas de
2019T2–T4); a PNADC mede o estoque de união corresidente com MDE de 0,575 p.p. O SINASC
observa a situação conjugal declarada de toda mãe no nascimento — ~55–70 mil nascimentos
por ano de mães com menos de 16 anos — com idade exata (`DTNASCMAE`), mês do nascimento e
município de **residência**. É a janela de maior potência sobre a margem de formalização,
ao custo de duas restrições de interpretação (estoque entre parturientes; condicionamento
em nascimento) que ficam registradas na §6.

## 2. Estimandos congelados

- **S1 (primário).** Variação curta na probabilidade de a mãe declarar-se **casada** no
  parto, mães de 10–15 anos vs. 17–19, abril–dezembro de 2019, células região × grupo
  etário × mês, PPML com offset = log(nascimentos com situação conjugal válida), efeitos
  fixos região×grupo, região×período, grupo×mês-calendário e tendências lineares por
  grupo. Inferência primária: cluster por período (mês). *Sinal esperado registrado ex
  ante: negativo ou nulo.*
- **S2.** Idêntico, outcome **união estável** (código 5). *Esperado: positivo ou nulo
  (relabeling/substituição).*
- **S3.** Idêntico, outcome **qualquer união declarada** (2 ∪ 5). *Esperado: nulo.*
- **S1b.** Robustez de missing: ignorada/NA no denominador (missing = não casada).
- **S4 (fecundidade-composição).** Nascimentos de mães de **15 anos** por 100 mil
  residentes do sexo feminino de 15 anos, células região × idade × trimestre, espelhando
  exatamente o PPML primário do lock do Registro (idades 15 vs. 17–19). Robustez: idade
  14. Para ≤13 anos: apenas contagens e participações — nenhuma taxa é computada.
- **Robustez de idade exata.** S1 com grupos definidos por idade exata no parto
  (<16,0 vs. 17,0–19,99) via `DTNASC − DTNASCMAE`, excluindo `DTNASCMAE` inválida
  (participação reportada; 1,5% na auditoria).

Janelas idênticas às do lock original: pré 2013-01–2019-02; **março/2019 omitido**; pós
curto 2019-04–2019-12; 2020–2021 marcado como pandemia; 2022–2024 descritivo;
sensibilidade de janela pré iniciando em 2014 e 2015.

Grupo de controle primário 17–19; conjuntos 18–19 e 16–19 congelados como robustez. A
idade 16 nunca entra no controle primário: é a margem legalmente intocada mais próxima e
pode absorver formalização adiada.

## 3. Diagnósticos obrigatórios

Variante sem tendências (divulgação de dependência de tendência, como no Registro);
agregação trimestral; série Brasil mensal com HAC (Newey–West, 12 defasagens); event
study mensal com teste conjunto de 24 leads (bases de posto pleno conforme Emendas 1–2 do
lock original); placebos em abril de 2015–2018; DiD de missingness diferencial
(diagnóstico); MDE₈₀ = 2,8 × EP primário; TOST com margem de razão de taxas [0,85; 1,176]
para S1–S3.

## 4. Multiplicidade

Holm dentro da família {S1, S2, S3}; Holm separado em {S4-15, S4-14}.

## 5. Regras de construção dos dados

CSVs oficiais 2013–2024 (manifesto SHA-256 em `data/raw_external/sinasc/`), leitura em
streaming sem expansão persistente, nomes harmonizados, linha final truncada de 2015
preenchida e logada. Mês = mês do nascimento (`DTNASC`); região = primeiro dígito de
`CODMUNRES` (residência); idade = `IDADEMAE` em anos completos, 10–19 nas células de
análise (8–9 contados como erro provável e excluídos). Totais devem bater com a auditoria
(2015: 2.786.525; 2019: 2.849.146) sob pena de falha. Situação conjugal: 1 solteira,
2 casada, 3 viúva, 4 separada/divorciada, 5 união estável; 9/NA = ignorada, excluída de
numerador e denominador no primário.

## 6. Restrições de interpretação (vinculantes para o texto)

1. Situação no parto é **estoque entre parturientes**; o efeito da lei opera pelo
   fechamento do fluxo de entrada e deve ser gradual no curto prazo.
2. Todo estimando SINASC **condiciona em nascimento**: é outcome conjunto de fecundidade
   e formalização; nunca é tratado como amostra aleatória de adolescentes.
3. Declaração não verificada em cartório: casada→união estável pode ser relabeling; S2
   sozinho jamais estabelece substituição comportamental.
4. Nenhum coeficiente SINASC é subtraído de coeficiente do Registro ou da PNADC.

## 7. Divulgação de exposição prévia

Antes deste congelamento, a auditoria de dados tabulou quantidades descritivas brutas que
incluem meses pós-reforma: distribuições anuais de situação conjugal entre mães <16 em
2015 e 2019, distribuição 16–17 em 2019 e contagens mensais nacionais brutas de casadas e
uniões estáveis <16 em 2019. Nenhuma regressão, nenhum contraste com idades de controle,
nenhuma tabulação regional e nenhum estimando aqui especificado foi computado. As escolhas
de desenho espelham o lock do Registro, congelado antes da aquisição do SINASC.

## 8. Política de emendas

Idêntica à do lock principal: somente erro de dado documentado ou não-identificação
técnica, registrada em `SINASC_EXTENSION_AMENDMENTS.md` **antes** da reestimação, com
especificação afetada, regra anterior, substituição, evidência, timestamp e consequência
esperada. Mudanças motivadas por sinal, magnitude, p-valor ou narrativa são proibidas.
