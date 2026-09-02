# SINASC extension amendments

Extension lock: version 1.0.0, frozen 2026-09-02T11:28:14-03:00 (hashes em
`SINASC_EXTENSION_LOCK_SHA256.txt`). Política: somente erro de dado documentado ou
não-identificação técnica, registrado AQUI antes da reestimação.

## Amendment A1 — exportação aberta de 2015 materialmente incompleta

- **Timestamp:** 2026-09-02T12:26:00-03:00 (registrada antes de qualquer reestimação sob
  esta regra).
- **Estágio de detecção:** validação de totais anuais contra publicação oficial da SVSA
  (pendência declarada no `SINASC_DATA_AUDIT.md` §5.4), executada APÓS a primeira rodada
  de estimação e independentemente de qualquer resultado dela.
- **Evidência do erro de dado (quatro fontes independentes):**
  1. `DNBR2015.csv` termina em linha truncada no meio de um registro (detectado na
     auditoria); a variante JSON oficial (`DNBR2015_json.zip`, 3,12 GB) contém os mesmos
     2.786.525 registros — o déficit está na geração da exportação aberta, não no formato.
  2. Boletim Epidemiológico especial SVSA (março/2023, fonte `svsa_boletim_mulher_2023`):
     total 2014–2021 = 22.974.531, com 2014 = 2.979.259 — **igual, registro a registro,
     ao CSV aberto de 2014** — e 2021 preliminar = 2.672.046 (consolidado aberto:
     2.677.101; diferença +5.055 na direção esperada da consolidação).
  3. Identidade contábil: soma oficial 2015–2020 (17.323.226) − soma das exportações
     abertas 2015–2020 (17.092.083) = **231.143**. Atribuído integralmente a 2015, implica
     oficial 2015 = 3.017.668; os demais anos fecham exatamente.
  4. Corroborações: incidência publicada de microcefalia em 2015 (1.608 casos = 54,6 por
     100 mil nascidos vivos, Epidemiol. Serv. Saúde 2016) implica denominador ≈ 2.945.055
     ≫ 2.786.525 já na base preliminar; e a distribuição mensal do arquivo aberto de 2015
     tem out–dez deprimidos ~25% versus anos adjacentes (déficit concentrado no fim do
     arquivo/ano), incompatível com o calendário da queda de natalidade associada ao Zika
     (que atinge nascimentos a partir de meados de 2016).
- **Especificações afetadas:** todas as famílias S1–S3 (inclui variantes de robustez,
  event study, HAC, placebos) e S4; qualquer célula com `birth_year == 2015`.
- **Regra anterior:** anos de dados 2013–2024; placebo dates abril/2015–2018; janela pré
  2013-01–2019-02.
- **Substituição fixada antes da reestimação:**
  1. excluir o ano-calendário 2015 de todas as amostras de estimação SINASC;
  2. excluir a data placebo abril/2015 (não estimável sem 2015);
  3. manter 2013 e 2014 (2014 validado exato; 2013 sem âncora, mantido com flag
     `unanchored` no audit);
  4. a correção definitiva — aquisição da base consolidada DBC via DATASUS quando a rota
     estiver acessível, ou correção da exportação aberta pelo MS — substitui esta regra
     quando disponível, com nova execução integral;
  5. nenhuma outra mudança de modelo, janelas, grupos ou inferência.
- **Consequência esperada registrada antes da reestimação:** desconhecida em sinal.
  Remover um ano com déficit concentrado em out–dez altera as tendências ajustadas e a
  sazonalidade estimada; os diagnósticos (leads, placebos restantes) decidem, como antes,
  se alguma leitura causal é sustentada.
