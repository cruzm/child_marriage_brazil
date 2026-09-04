# Avaliação causal da Lei nº 13.811/2019

Este diretório contém uma replicação auditável da mudança legal que eliminou as exceções ao casamento civil abaixo da idade núbil. Todo o trabalho produzido por este fluxo está isolado em `Darcio/`; os dados brutos preexistentes fora dele não são modificados.

## Resultado em uma frase

Na especificação congelada antes da estimação, a mudança relativa de registros civis aos 15 anos em 2019T2–T4 foi de **−1,1%** (IC95% −14,9% a +14,9%). A versão sem tendências encontra −37,8%, de modo que a inferência é fortemente dependente da trajetória prévia e não sustenta uma conclusão causal robusta de queda adicional. Na PNADC, o ponto para união corresidente conservadora é +0,399 p.p. (IC95% −0,003 a +0,801): sugestivo, mas inconclusivo, e não prova informalização.

No piloto diário do SINASC, o Gate G3 estima uma mudança de **+0,342 p.p.** no
salto aos 16 anos (IC95% −0,140 a +0,824; p=0,164) e `DELAY90` de +0,323 p.p.
(IC95% −0,318 a +0,964; p de Holm=0,328). A classificação congelada é
`INCONCLUSIVE`; junto ao G2 `QUALIFIED`, isso implica
`DO_NOT_ADVANCE_AS_CAUSAL_CORE`.

Leia primeiro:

- [Sumário executivo](outputs/analysis/EXECUTIVE_SUMMARY.md)
- [Relatório técnico](outputs/analysis/TECHNICAL_REPORT.md)
- [Auditoria dos dados](outputs/audit/DATA_AUDIT.md)
- [Estimandos e specification lock](outputs/analysis/ESTIMANDS_AND_SPECIFICATIONS.md)
- [Status final dos testes](outputs/analysis/FINAL_ACCEPTANCE.md)
- [Próximo redesenho de dados: microdados restritos do Registro Civil e DataJud](paper/ledgers/ADMINISTRATIVE_DATA_FEASIBILITY_2026-09-02.md)
- [Protocolo diário do SINASC aos 16 anos](paper/ledgers/SINASC_DAILY_PROTOCOL.md)
- [Resultado do Gate G0 do protocolo diário](outputs/analysis/SINASC_DAILY_GATE_G0.md)
- [Resultado do Gate G1 do protocolo diário](outputs/analysis/SINASC_DAILY_GATE_G1.md)
- [Resultado do Gate G2 do protocolo diário](outputs/analysis/SINASC_DAILY_GATE_G2.md)
- [Resultado do Gate G3 do protocolo diário](outputs/analysis/SINASC_DAILY_RESULTS.md)
- [R0 local do redesenho Registro Civil/SAR](outputs/analysis/REGISTRY_SAR_R0_RESULTS.md)
- [Consulta técnica ao IBGE pronta, mas não enviada](paper/ledgers/IBGE_SAR_TECHNICAL_INQUIRY_READY.md)
- [Crawler auditável das tabelas públicas do Registro Civil/IBGE](crawler_pdpj/README_REGISTRO_CIVIL.md)

## Replicação integral

A partir da raiz do repositório (`child_marr`):

```bash
./Darcio/run_all.sh
```

Alternativamente:

```bash
make -f Darcio/Makefile all
```

O comando executa os Gates A–E na ordem, revalida hashes e schemas, constrói todos os derivados, estima os modelos, exporta tabelas/figuras, gera relatórios e termina com a bateria final. Um retorno diferente de zero indica uma falha não resolvida.

Para executar apenas os testes sobre os artefatos existentes:

```bash
make -f Darcio/Makefile test
```

Para validar, sem estimar resultados, o lock do desenho diário do SINASC:

```bash
make -f Darcio/Makefile sinasc-daily-lock
```

Para executar exclusivamente o Gate G0 do desenho diário — reconciliação dos
arquivos, datas, status e massa amostral, sem regressão ou estimativa de efeito:

```bash
make -f Darcio/Makefile sinasc-daily-g0
```

Para revalidar somente os artefatos G0 já existentes, sem reler os microdados:

```bash
make -f Darcio/Makefile sinasc-daily-g0-check
```

Para executar exclusivamente o Gate G1 — densidade/heaping, continuidade das
covariáveis predeterminadas, composição não vinculante e missingness do estado
civil — após revalidar o lock e o G0, sem executar G2/G3 nem estimar o desfecho
de casamento:

```bash
make -f Darcio/Makefile sinasc-daily-g1
```

Para revalidar apenas os artefatos agregados já produzidos pelo G1, sem reler
os microdados:

```bash
make -f Darcio/Makefile sinasc-daily-g1-check
```

Para executar exclusivamente o Gate G2 — placebo temporal pré-lei, placebos
etários aos 15/17/19 anos, saltos anuais e diagnósticos leave-one-year-out —
após revalidar o lock, o G0 e o G1, sem estimar o modelo primário completo ou
qualquer estimando G3:

```bash
make -f Darcio/Makefile sinasc-daily-g2
```

Para revalidar somente os artefatos agregados existentes do G2, sem reler
microdados ou reestimar modelos:

```bash
make -f Darcio/Makefile sinasc-daily-g2-check
```

Para executar o Gate G3 completo — `TAU`, `DELAY90`, desfechos secundários,
as 13 especificações empilhadas congeladas e os cross-checks `rdrobust` — após
revalidar o lock e G0–G2:

```bash
make -f Darcio/Makefile sinasc-daily-g3
```

Para revalidar os 42 checks dos artefatos G3 existentes, sem reler microdados
ou reestimar modelos:

```bash
make -f Darcio/Makefile sinasc-daily-g3-check
```

Para executar o R0 local do redesenho com microdados exatos do Registro Civil —
auditoria dos insumos públicos, pacote de denominador, envelope de potência,
teste sintético de recuperação e checklist de envio, sem acessar dados restritos
nem transmitir pedido externo:

```bash
make -f Darcio/Makefile registry-sar-r0
```

Para revalidar apenas o lock e os artefatos locais existentes:

```bash
make -f Darcio/Makefile registry-sar-r0-check
```

O maior veredito permitido nesta etapa é
`LOCAL_READY_EXTERNAL_PENDING`. O status causal permanece `NOT_EVALUATED` até
que o IBGE confirme os campos e os gates com dados restritos sejam executados.

## Requisitos

- R e os pacotes enumerados em `src/00_check_dependencies.R`;
- para G3, `rdrobust` 3.0.0, com versão e SHA-256 da fonte registrados em
  `outputs/audit/SINASC_DAILY_G3_SOFTWARE.csv`;
- para o R0 Registro Civil/SAR, `fixest` 0.13.2 ou versão compatível registrada
  em `outputs/audit/REGISTRY_SAR_R0_SOFTWARE.csv`;
- `curl`, `unzip`, `file`, `sha256sum` e `pdfinfo`;
- acesso de rede apenas quando uma fonte oficial ainda não estiver no cache;
- espaço para 10,23 GB de ZIPs trimestrais da PNADC e seus derivados.

Se pacotes R estiverem ausentes e houver acesso à rede:

```bash
INSTALL_MISSING=1 ./Darcio/run_all.sh
```

O pipeline usa no máximo quatro workers, não expande os TXT trimestrais no disco e interrompe se os checks críticos falharem. No ambiente desta replicação havia 21,5 GiB de RAM, 272,5 GiB livres e 14 CPUs lógicas. A reprodução integral validada, com os insumos oficiais já em cache, levou aproximadamente 58 minutos; o tempo varia com CPU, disco e cache.

## Estrutura

```text
Darcio/
├── config/       # configuração central e specification lock
├── data/         # cache de fontes públicas (ignorado pelo Git)
├── docs/         # documentação de projeto
├── references/   # fontes oficiais, hashes e notas de conferência
├── src/          # módulos numerados do pipeline
├── tests/        # aceitação integrada
└── outputs/
    ├── audit/    # inventário, cobertura, validações, blockers e testes
    ├── data/     # bases analíticas derivadas e dicionários
    ├── figures/  # PNG e PDF
    ├── tables/   # CSV e LaTeX
    ├── analysis/ # relatórios, lock, emendas e manifesto
    └── logs/     # duração, memória e status por etapa
```

## Decisões metodológicas centrais

- O desenho é DiD por elegibilidade etária, não RD convencional: a idade existe em anos completos/categorias.
- A idade tratada principal é 15; 16–17 não são tratadas diretamente pela reforma.
- 2019T1 e março de 2019 não são pós integral; o pós começa em 2019T2 ou abril.
- O numerador do Registro Civil é por local e mês do registro; o denominador da PNADC é por residência. Região é a geografia primária compatível segundo a regra de precisão congelada.
- A reforma foi nacional. A inferência principal usa choques por período e é triangulada; células geográficas não são tratadas como reformas independentes.
- Registro Civil mede fluxo formal; PNADC mede estoque de união corresidente. Os outcomes nunca são subtraídos.
- A categoria abaixo de 15 recebe contagem e participação, não uma taxa enganosa com população de 0–14.
- A PNADC é repetição de cortes transversais; não se estima transição individual.

## Dados e proveniência

O Registro Civil vem da [tabela 4406 do SIDRA/IBGE](https://sidra.ibge.gov.br/tabela/4406), com reconstrução oficial de 2013–2024. Os denominadores e outcomes comportamentais usam microdados trimestrais oficiais da PNADC e o peso calibrado V1028, com Estrato/UPA. A legislação foi conferida no Planalto.

Todas as fontes efetivamente abertas estão em `references/SOURCES.csv`, com título, instituição, URL, data de acesso, cópia local quando possível e nota de verificação. Os arquivos de aquisição têm manifests SHA-256. O `RESULTS_MANIFEST.csv` liga cada tabela, figura e número-chave ao script, base e status causal.

## Specification lock

O lock foi criado em 2026-09-02T00:56:08−03:00, antes de qualquer estimativa pós-reforma:

- `config/specification_lock.yml`: `17f690311168b0953779e533f8a3a5b7ebf79e502237e0a4bbde3b8d07c465c2`
- `outputs/analysis/ESTIMANDS_AND_SPECIFICATIONS.md`: `537fe0474cc1cd69a99251ddbc08c222b14f9685e9edf198ebce88e623b07449`

As quatro emendas posteriores documentam somente colinearidade em event studies saturados e uma substituição computacional exata do `svyglm`; estão registradas antes das respectivas reestimações em `outputs/analysis/SPECIFICATION_AMENDMENTS.md`.

## Segurança e versionamento

Os dados públicos brutos grandes, derivados em nível de pessoa e a biblioteca local R são ignorados por `Darcio/.gitignore`. Outputs agregados, código, documentação e manifests são versionáveis. Nenhum commit ou push é realizado pelo pipeline.
