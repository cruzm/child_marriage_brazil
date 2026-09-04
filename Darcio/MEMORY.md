# Memória do projeto — casamento precoce no Brasil

Atualizado em 2026-09-04. Esta memória registra o estado operacional e as decisões científicas mais recentes. Não substitui os ledgers, manifests ou o specification lock.

## Estado do paper

- A análise avalia a Lei nº 13.811/2019, que eliminou as exceções ao casamento civil abaixo dos 16 anos.
- O resultado primário congelado para registros civis aos 15 anos é −1,1% no período 2019T2–T4, com IC95% de −14,9% a +14,9%.
- A especificação sem tendências encontra −37,8%. Essa divergência mantém aberto o gate de identificação: o resultado depende fortemente da trajetória prévia.
- A PNADC mede estoque de união corresidente, não fluxo de casamentos. Seu ponto para a definição conservadora é +0,399 p.p., com IC95% de −0,003 a +0,801; é sugestivo e inconclusivo, sem provar informalização.
- A bateria integrada geral mais recente passou em 169/169 checks; as validações
  isoladas dos Gates G0, G1, G2 e G3 diários passaram adicionalmente em 20/20,
  32/32, 35/35 e 42/42 checks. O R0 local Registro Civil/SAR passou em 30/30
  checks, com status `LOCAL_READY_EXTERNAL_PENDING`; identificação causal segue
  `NOT_EVALUATED` nesse trilho.

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

O protocolo exploratório pós-resultado foi congelado em 2026-09-04, antes de qualquer contraste por distância diária: `paper/ledgers/SINASC_DAILY_PROTOCOL.md` e `config/sinasc_daily_lock.yml`. O cutoff primário é 16 anos, bandwidth 90 dias, nascimentos únicos, pré 2016–2018 e pós maduro 2022–2024. Bandwidths 30/60/180, densidade/heaping, continuidade, placebos aos 15/17/19, placebo temporal e regras de parada são obrigatórios. Como situação conjugal é estoque, o lock também fixa `DELAY90` para detectar resposta gradual; esse estimando não pode substituir o salto primário nem salvar um gate reprovado.

O Gate G0 foi implementado e executado em 2026-09-04 com veredito `PASS`: 6/6
totais anuais reconciliam exatamente com âncoras independentes; a menor validade
de datas é 98,859%; a menor concordância de idade é 99,976%; a menor validade de
estado civil em era×lado é 98,636%; e as menores células em h=90 contêm 21.420
nascimentos e 125 eventos de estado civil casado. Esses dois últimos são
contagens de viabilidade, não taxas nem contrastes. Relatório:
`outputs/analysis/SINASC_DAILY_GATE_G0.md`.

O Gate G1 também foi implementado e executado em 2026-09-04, exclusivamente no
escopo pré-outcome, com veredito `PASS`. Os testes robustos de densidade não
rejeitam continuidade no pré (p=0,8481; razão direita/esquerda=0,9944) nem no
pós maduro (p=0,3946; razão=0,9629). Nenhuma das dez covariáveis predeterminadas
falha após Holm; a maior magnitude padronizada é 0,0359, abaixo de 0,10. A
mudança da descontinuidade de missingness do estado civil é +0,2616 p.p.
(p=0,3165), abaixo da regra conjunta de falha. Nenhum dos 14 diagnósticos de
composição tem p de Holm abaixo de 0,05.

Transparência: as contagens exatas em janelas de 30 dias mostram aproximadamente
6,2% mais nascimentos à direita tanto no pré quanto no pós e rejeitam igualdade
binomial em ambas as eras. Elas são diagnósticas; não substituem o teste robusto
de densidade nem alteram a regra congelada, que exige conjuntamente p<0,05 e
razão absoluta acima do limiar de 5%. Na etapa G1, nenhum desfecho de casamento,
placebo G2 ou estimando G3 foi construído. Relatório:
`outputs/analysis/SINASC_DAILY_GATE_G1.md`.

O Gate G2 foi implementado e executado em 2026-09-04 com veredito
`QUALIFIED`, não `PASS` nem `FAIL`. O placebo temporal pré-lei aos 16 anos é
−0,2799 p.p. (IC90% [−0,7248; +0,1650], IC95% [−0,8102; +0,2503],
p=0,3006). Ele não satisfaz equivalência dentro de ±0,25 p.p., mas o IC95%
inclui zero e, portanto, não aciona a regra de falha. Os placebos etários são
−0,0273 p.p. aos 15, +0,0537 aos 17 e −0,0639 aos 19; todos têm p de Holm igual
a 1. Nenhum rejeita, mas nenhum IC90% cabe integralmente na margem de
equivalência. Pela emenda prospectiva A003, a família etária também é
`QUALIFIED`: ausência de significância não foi tratada como evidência de
equivalência.

Todos os 11 saltos anuais e as nove combinações leave-one-year-out foram
identificados. A instabilidade permanece visível: o salto anual de 2022 é
+0,9515 p.p. (IC95% [+0,2534; +1,6495], p bruto=0,0077), enquanto 2023 e 2024
não rejeitam; uma das nove exclusões anuais produz p bruto=0,0497. Esses testes
de estabilidade não receberam regra de multiplicidade e não alteram o gate
vinculante, mas impedem uma leitura excessivamente confortável do resultado.
O G2 processou 806.437 registros cutoff-específicos em h=90, excluiu 1.312
aniversários inexistentes, todos explicados por nascimento materno em 29 de
fevereiro, e reconciliou 12/12 células primárias do G0. O modelo primário
completo aos 16 anos e todos os estimandos G3 permaneceram não executados nessa
etapa.
Relatório: `outputs/analysis/SINASC_DAILY_GATE_G2.md`.

O Gate G3 foi implementado e executado em 2026-09-04 sob a emenda prospectiva
A004. O estimando primário é +0,3420 p.p. (EP 0,2457; IC90%
[−0,0624; +0,7463], IC95% [−0,1399; +0,8238], p=0,1642). O MDE80 é
0,6880 p.p.; o ponto corresponde a 37,6% da participação pré-lei ponderada
abaixo do cutoff, de 0,9095%. `DELAY90` é +0,3231 p.p. (EP 0,3269; IC90%
[−0,2148; +0,8610], IC95% [−0,3179; +0,9641], p de Holm=0,3284). O teste
conjunto de `TAU=phi=0` tem p=0,3793. Nenhum dos dois IC90% cabe na margem de
±0,25 p.p., e nenhum sinal rejeita zero: a classificação mecânica é
`INCONCLUSIVE`, não um efeito positivo apoiado nem um nulo informativo.

As 13 especificações empilhadas congeladas foram identificadas; os pontos vão
de +0,1479 a +0,3556 p.p., mas não substituem o primário. O cross-check
`rdrobust` 3.0.0 em h=90 encontra saltos bias-corrected de +0,1844 p.p. no pré
e +0,5095 p.p. no pós, uma diferença pontual de +0,3251 p.p. para a qual o
protocolo proíbe construir inferência a partir dos dois ajustes separados. Os
secundários são −0,6276 p.p. para união estável e −0,2856 p.p. para qualquer
união, ambos com p de Holm=1. G3 passou 42/42 verificações técnicas, mas G2
continua `QUALIFIED`; a decisão vinculante é
`DO_NOT_ADVANCE_AS_CAUSAL_CORE`. Relatório:
`outputs/analysis/SINASC_DAILY_RESULTS.md`.

### SAR/IBGE — desenho preferido

O desenho com maior retorno é uma diferença-em-descontinuidades da taxa de celebração imediatamente acima e abaixo do 16º aniversário, antes versus depois de 13 de março de 2019. Ele exige microdados restritos com data exata de nascimento, data exata de celebração e denominador de exposição compatível.

O parâmetro é a mudança pós-reforma no salto da taxa de casamento aos 16 anos. Estimar taxas sobre pessoa-tempo em risco; nunca condicionar a amostra apenas às pessoas que efetivamente se casaram. Diagnósticos mínimos: heaping, manipulação/adiamento, bandwidths, placebos de idade e data, estabilidade pré-2019, sazonalidade, missingness e reconciliação com totais publicados.

O caminho de acesso pela SAR foi verificado em fontes oficiais, mas a retenção e comparabilidade anual de todos os campos em 2013–2024 ainda precisam ser confirmadas pelo IBGE. O rascunho está em `paper/ledgers/IBGE_SAR_PROJECT_DRAFT.md`; nenhuma solicitação foi enviada.

O R0 local do redesenho foi congelado e executado em 2026-09-04. Os três
insumos públicos passaram a auditoria. O pacote PNADC contém 288 células
nacionais trimestrais para idades 15/16 e sexos combinado/feminino/masculino;
os 18 critérios de cobertura, tamanho, CV e comparação anual passaram. Na
população combinada, o CV máximo é 2,354% e a maior diferença entre a média
trimestral e a estimativa anual é 3,444%.

O envelope de potência usa somente contagens por idade e ano de registro. O
cenário-base em h=90 produz MDE80 de 19,09% para uma queda; o cenário de estresse
em h=180, com metade da alocação proporcional e inflação de variância igual a
dois, produz 25,88%. Ambos passam os limiares congelados, mas continuam
provisórios até a contagem por idade e data exatas da celebração. O dry run com
51.623 células sintéticas recuperou o IRR verdadeiro de 0,60 com erro de 0,0197
log ponto; esse resultado testa o software e é proibido como evidência do paper.

A consulta técnica está em
`paper/ledgers/IBGE_SAR_TECHNICAL_INQUIRY_READY.md`, marcada
`READY_NOT_SENT`. O envio, a identificação institucional e a resposta do IBGE
são os blockers externos. Relatório local:
`outputs/analysis/REGISTRY_SAR_R0_RESULTS.md`.

## Blockers e próximos passos

1. Preservar a decisão congelada após G3: não recentrar o paper no piloto diário
   do SINASC e não selecionar uma sensibilidade para reverter o resultado.
2. Se o piloto diário entrar no manuscrito, apresentá-lo como evidência local
   inconclusiva e manter visíveis G2 `QUALIFIED`, os saltos anuais e a precisão.
3. Manter qualquer RDiT do Registro Civil como apêndice diagnóstico.
4. Autorizar e transmitir a consulta técnica pronta; depois obter confirmação
   do IBGE e acesso à SAR para testar o desenho principal com idade na celebração.
5. Não usar a série pública da classe TPU 143 do DataJud para estimação: sigilo, datas corrompidas, cobertura pré-2019 insuficiente e mistura entre suprimento de idade e consentimento.

## Estado operacional

- Nenhum commit, push, upload ou pedido institucional foi realizado na retomada.
- O worktree contém alterações e arquivos não rastreados do projeto; preservá-los.
- O G0 diário leu os seis ZIPs sequencialmente em 1,53 minuto, com pico observado
  abaixo de 620 MB de RSS, sem expandir arquivos nem persistir microdados.
- O G1 diário leu os mesmos seis ZIPs sequencialmente em 1,80 minuto, com pico
  observado abaixo de 0,9 GB de RSS; persistiu somente agregados, tabelas de
  diagnóstico e a figura de densidade.
- O G2 diário leu 11 ZIPs sequencialmente em 4,13 minutos, ajustou exatamente
  24 modelos autorizados e teve pico observado de aproximadamente 740 MB de
  RSS. Uma tentativa anterior parou antes de qualquer ajuste por sintaxe estrita
  de seleção lógica no `data.table`; a linha foi corrigida antes da primeira
  abertura de coeficientes, e a execução completa posterior foi validada.
- O G3 diário leu seis ZIPs sequencialmente em 1,89 minuto, ajustou 16 modelos
  `fixest` e dez modelos `rdrobust`, teve pico observado de aproximadamente
  1,4 GB de RSS e persistiu somente agregados. Três tentativas interrompidas
  estão preservadas: as duas primeiras pararam antes de qualquer regressão; a
  terceira expôs duas falhas mecânicas de codificação, corrigidas sem alterar
  A004 ou qualquer especificação. A execução final passou 42/42 checks.
- O R0 Registro Civil/SAR usa somente agregados públicos e dados sintéticos.
  Produziu 288 células de exposição, 108 cenários de potência e 51.623 células
  sintéticas; a validação final passou 30/30 checks. Nenhuma solicitação, dado
  restrito, upload, commit ou push foi realizado.
- Antes de novo processamento pesado, conferir `free -h`, `df -h .`, processos ativos, arquivos `.part` e checkpoints existentes.
