# Gate A — Integridade do workspace

Criado em: 2026-09-01T22:34:20-03:00  
Raiz examinada: `/home/darciogm1/projetos/child_marr`  
Diretório autorizado para novos artefatos: `Darcio/`

## Estado inicial do repositório

- `git status --short` não mostrou mudanças antes da criação de `Darcio/`.
- Branch: `main`, acompanhando `origin/main`.
- Commit inicial preservado: `ec9a3febe20c9c0e916e1a482773fa88df5d09e3`.
- Remoto: `https://github.com/cruzm/child_marriage_brazil.git`.
- Após o Gate A, `git status --short` mostra somente `?? Darcio/`.
- Nenhum dado ou script preexistente foi modificado, renomeado ou apagado.
- Não existe `AGENTS.md` no workspace.

## Materiais lidos e conferidos

- `README.md`, integralmente.
- `code/10_inf_causal.Rmd`, integralmente, tratado como memorando e código legado — não como autoridade jurídica ou fonte de dados.
- `notes/data_structure.xlsx` e os oito workbooks em `notes/data dictionary/`: 9 workbooks, 53 planilhas e 50.191 linhas não vazias foram lidos sem erro por `Darcio/src/00_inspect_documentation.R`.
- `notes/data dictionary/glossario_registro_civil.pdf`, integralmente.
- Arquivo de layout `input_PNADC_trimestral.txt` contido em `Dicionario_e_input_20221031.zip`.
- `Estatísticas do Registro Civil 2022 — Notas técnicas`, IBGE, 32 páginas, inclusive conceitos, coleta e questionários.
- `PNAD Contínua — Chaves`, IBGE, integralmente.
- O conteúdo de `Documentacao_20230713.zip` foi inspecionado e identificado como documentação da POF 2017–2018, não da PNADC.
- Dicionários da PNS 2013/2019 e documentação histórica da PNADC foram lidos programaticamente e permanecem disponíveis no extrato integral comprimido.

Extratos auditáveis:

- `DOCUMENTATION_WORKBOOK_SUMMARY.csv`
- `DOCUMENTATION_ALL_ROWS.csv.gz`
- `DOCUMENTATION_RELEVANT_ROWS.csv`

## Alertas encontrados antes da análise

1. O memorando legado afirma incorretamente que a Lei nº 13.811/2019 criou proibição absoluta abaixo de 18 anos. As fontes primárias confirmam que a reforma suprimiu as exceções para quem ainda não atingiu a idade núbil; o art. 1.517 continuou permitindo casamento aos 16 e 17 anos, sujeito à autorização exigida pelo Código Civil.
2. O memorando chama de RD uma análise com idade construída na PNADC. Esse desenho não será reutilizado sem datas que permitam idade exata e sem denominador compatível. Idade anual ou categórica sustentará somente age-based DiD/diferença-em-descontinuidades discreta com ressalvas.
3. As notas técnicas do Registro Civil definem idade como anos completos na data do registro do casamento, mês de ocorrência como o mês da celebração e geografia como lugar do cartório de registro — não residência.
4. O arquivo oficial de chaves da PNADC diz que `UPA + V1008 + V1014` identifica domicílio longitudinalmente, enquanto a chave acrescida de `V2003` identifica pessoa apenas dentro do arquivo e não deve ser usada para análise longitudinal de pessoas.

## Recursos computacionais e limites

- Arquivos preexistentes (sem `.git` e sem `Darcio/`): 147 arquivos, 101.384.640 bytes (aprox. 96,7 MiB).
- RAM: 21 GiB total; 20 GiB disponíveis no fechamento do gate.
- Swap: 8 GiB, sem uso.
- Disco: 1.007 GiB total; 286 GiB disponíveis; 71% utilizado.
- CPUs lógicas: 14.
- Paralelismo máximo fixado: 4 processos (`min(4, floor(14/2))`).
- O fluxo deve reduzir paralelismo acima de 70% de RAM e interromper operações expansivas quando o espaço livre cair abaixo de 15%.
- Os ZIPs locais relevantes expandem de aproximadamente 70 KiB para 391 KiB; o ZIP de 5,0 MiB expande para cerca de 13,1 MiB e foi classificado como documentação da POF. Não há risco material de expansão no Gate A.

## Arquivos criados neste gate

- `Darcio/src/00_inspect_documentation.R`
- `Darcio/outputs/audit/DOCUMENTATION_WORKBOOK_SUMMARY.csv`
- `Darcio/outputs/audit/DOCUMENTATION_ALL_ROWS.csv.gz`
- `Darcio/outputs/audit/DOCUMENTATION_RELEVANT_ROWS.csv`
- `Darcio/references/ibge_registro_civil_2022_notas_tecnicas.pdf`
- `Darcio/references/ibge_registro_civil_2022_notas_tecnicas.txt`
- `Darcio/references/ibge_chaves_pnadc.pdf`
- `Darcio/references/ibge_chaves_pnadc.txt`
- `Darcio/references/SOURCES.csv`

## Testes e bloqueios

- Leitura dos 53 sheets: **aprovada**, zero sheets bloqueados.
- Conversão dos dois PDFs oficiais para texto: **aprovada**.
- Integridade Git: **aprovada**; somente `Darcio/` é novo.
- O servidor do Planalto respondeu ao navegador de pesquisa, mas não ao `curl` local dentro de 60 segundos. O texto oficial foi aberto e conferido; a falha de download será registrada, sem substituir a fonte por versão secundária.

