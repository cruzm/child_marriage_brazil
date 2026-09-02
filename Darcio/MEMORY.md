# Memória do projeto — casamento precoce no Brasil

Atualizado em 2026-09-02. Esta memória registra o estado operacional e as decisões científicas mais recentes. Não substitui os ledgers, manifests ou o specification lock.

## Estado do paper

- A análise avalia a Lei nº 13.811/2019, que eliminou as exceções ao casamento civil abaixo dos 16 anos.
- O resultado primário congelado para registros civis aos 15 anos é −1,1% no período 2019T2–T4, com IC95% de −14,9% a +14,9%.
- A especificação sem tendências encontra −37,8%. Essa divergência mantém aberto o gate de identificação: o resultado depende fortemente da trajetória prévia.
- A PNADC mede estoque de união corresidente, não fluxo de casamentos. Seu ponto para a definição conservadora é +0,399 p.p., com IC95% de −0,003 a +0,801; é sugestivo e inconclusivo, sem provar informalização.
- A bateria integrada mais recente passou em 169/169 checks.

Documentos centrais:

- `README.md`;
- `config/specification_lock.yml`;
- `outputs/analysis/ESTIMANDS_AND_SPECIFICATIONS.md`;
- `paper/ledgers/IDENTIFICATION_GATE.md`;
- `paper/ledgers/ADMINISTRATIVE_DATA_FEASIBILITY_2026-09-02.md`.

## Retomada após a interrupção

O último componente identificado foi o crawler auditável das tabelas públicas de casamentos do Registro Civil/IBGE:

- código: `crawler_pdpj/crawler_registro_civil_ibge.py`;
- testes: `crawler_pdpj/test_crawler_registro_civil_ibge.py`;
- documentação: `crawler_pdpj/README_REGISTRO_CIVIL.md`.

Estado validado em 2026-09-02:

- testes unitários: 6/6;
- catálogo oficial: 12/12 anos descobertos, de 2013 a 2024;
- aquisição completa: 12/12 ZIPs, 31.276.921 bytes (29,83 MiB);
- todos os ZIPs passaram na verificação de estrutura e CRC;
- a segunda execução reutilizou 12/12 checkpoints sem novo download;
- nenhum arquivo `.part` permaneceu;
- os downloads são sequenciais e processados em blocos de 1 MiB;
- os arquivos permanecem em `crawler_pdpj/dados_registro_civil_publico/`, ignorado pelo Git;
- o manifesto portátil está em `outputs/audit/REGISTRY_PUBLIC_TABLES_ACQUISITION.csv`;
- a fonte foi registrada em `references/SOURCES.csv`.

Classificação obrigatória: esses ZIPs contêm tabelas públicas agregadas. Eles não são microdados evento a evento e não fornecem conjuntamente datas exatas de nascimento e celebração, residência dos cônjuges e chave do evento.

## Controle de recursos

Na retomada, o ambiente tinha aproximadamente:

- 21 GiB de RAM total e 20 GiB disponíveis;
- 8 GiB de swap, sem uso;
- 273 GiB livres no volume de trabalho;
- 14 GiB ocupados pelo diretório do projeto, dos quais cerca de 13 GiB eram dados brutos externos já existentes.

A bateria integrada consumiu pico de 79.164 KiB de RSS e não usou swap. Não é necessário reexecutar o pipeline integral para validar apenas o crawler. Para tarefas grandes, manter processamento anual/sequencial, liberar objetos entre anos, evitar extração simultânea de ZIPs e preservar checkpoints.

## Veredito sobre regressões descontínuas

### Registro Civil público — RD etária

Não apresentar como RD convencional. A idade é observada em anos completos na data do registro, enquanto a regra depende da idade na celebração. O suporte útil contém idades 15, 16, 17, 18 e 19, com `<15` agrupado; há somente um ponto não agrupado imediatamente abaixo do corte. Uma comparação 15 versus 16 é uma diferença discreta por idade e depende de forma funcional, não uma comparação local contínua.

### Registro Civil público — descontinuidade no tempo

Uma RDiT ao redor de março/abril de 2019 pode ser executada apenas como diagnóstico. A análise mensal existente encontra:

- painel regional com tendências: −2,4%, IC95% [−20,8%, +20,3%], p = 0,820;
- série nacional com Newey–West: −2,7%, p = 0,726.

Limitações: mês de registro em vez de celebração, março parcialmente tratado, defasagens de registro, queda secular anterior e apenas uma reforma nacional. Um protocolo dedicado deve usar tendências locais separadas, bandwidths de 6, 12, 18 e 24 meses, sazonalidade, HAC ou block bootstrap e datas placebo. Mesmo assim, não fecha o gate causal.

### SINASC — candidato executável com dados locais

É possível construir uma diferença-em-descontinuidades aos 16 anos usando a distância, em dias, entre a data do parto e o 16º aniversário da mãe. É necessário reconstruir bins diários ou semanais a partir dos arquivos brutos; o derivado atual retém apenas a idade exata arredondada para baixo.

Massa amostral preliminar nas idades inteiras 15–16:

- anos pré-selecionados 2013, 2014 e 2016–2018: 607.002 partos e 16.481 declarações de estado civil casado;
- 2022–2024: 190.844 partos e 2.601 declarações de casado.

Esse desenho mede estado conjugal declarado entre mães de nascidos vivos, condicionado ao parto. Não mede incidência de casamento, pode conter casamentos celebrados antes da reforma e não substitui o Registro Civil. Seu papel máximo é evidência complementar sobre a antiga exceção por gravidez.

Antes de estimar qualquer coeficiente, congelar um protocolo exploratório pós-resultado. Incluir bandwidths de 30, 60, 90 e 180 dias; polinômios locais lineares; densidade/heaping; equilíbrio de covariáveis; placebos aos 15, 17 e 19 anos; datas placebo; resultado `união estável`; tratamento explícito da incompletude do SINASC em 2015.

### SAR/IBGE — desenho preferido

O desenho com maior retorno é uma diferença-em-descontinuidades da taxa de celebração imediatamente acima e abaixo do 16º aniversário, antes versus depois de 13 de março de 2019. Ele exige microdados restritos com data exata de nascimento, data exata de celebração e denominador de exposição compatível.

O parâmetro é a mudança pós-reforma no salto da taxa de casamento aos 16 anos. Estimar taxas sobre pessoa-tempo em risco; nunca condicionar a amostra apenas às pessoas que efetivamente se casaram. Diagnósticos mínimos: heaping, manipulação/adiamento, bandwidths, placebos de idade e data, estabilidade pré-2019, sazonalidade, missingness e reconciliação com totais publicados.

O caminho de acesso pela SAR foi verificado em fontes oficiais, mas a retenção e comparabilidade anual de todos os campos em 2013–2024 ainda precisam ser confirmadas pelo IBGE. O rascunho está em `paper/ledgers/IBGE_SAR_PROJECT_DRAFT.md`; nenhuma solicitação foi enviada.

## Blockers e próximos passos

1. Congelar o protocolo do piloto diário do SINASC antes de abrir resultados.
2. Implementar esse piloto em processamento anual, mantendo baixo uso de RAM e sem duplicar os ZIPs brutos.
3. Manter qualquer RDiT do Registro Civil como apêndice diagnóstico.
4. Obter confirmação técnica e acesso à SAR para testar o desenho principal com idade na celebração.
5. Não usar a série pública da classe TPU 143 do DataJud para estimação: sigilo, datas corrompidas, cobertura pré-2019 insuficiente e mistura entre suprimento de idade e consentimento.

## Estado operacional

- Nenhum commit, push, upload ou pedido institucional foi realizado na retomada.
- O worktree contém alterações e arquivos não rastreados do projeto; preservá-los.
- Antes de novo processamento pesado, conferir `free -h`, `df -h .`, processos ativos, arquivos `.part` e checkpoints existentes.
