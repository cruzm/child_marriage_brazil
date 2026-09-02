# Draft — IBGE SAR project form

**Status:** working draft; not submitted
**Official form:** [active Gov.br service](https://www.gov.br/pt-br/servicos/solicitacao-de-acesso-a-sala-de-dados-restritos),
last modified August 25, 2026
**Missing administrative fields:** researcher identity, institutional signatory, dates,
budget approval, and final list/file of any external aggregate denominator

## 1. Informações sobre o projeto

### Título

**Idade mínima legal, formalização e adiamento do casamento: evidência de datas exatas do
Registro Civil brasileiro**

### Resumo do projeto

O projeto avalia a Lei nº 13.811/2019, que eliminou as exceções ao casamento civil abaixo de
16 anos. As tabelas públicas permitem observar idade em anos completos, mês do registro e
local do cartório, mas não a combinação entre data exata do casamento, data de nascimento e
residência coletada pelo questionário RC.2. Essa limitação impede classificar corretamente a
idade na data da celebração, separar celebração de registro e construir um contraste local em
torno do aniversário de 16 anos.

Solicita-se acesso, dentro da SAR, aos microdados de casamentos do RC.2 de 2013 a 2024.
Serão produzidas apenas estatísticas, coeficientes e diagnósticos agregados submetidos à revisão
de confidencialidade. Não serão solicitados nem exportados nomes, endereços, números de livro
ou registro ou quaisquer identificadores diretos.

### Objetivos do projeto

1. Estimar a mudança na taxa de celebrações civis imediatamente abaixo de 16 anos após a
   vigência da Lei nº 13.811/2019, relativamente à taxa imediatamente acima de 16 anos e à
   mesma descontinuidade etária no período anterior.
2. Distinguir redução de celebrações abaixo de 16 anos de adiamento para os primeiros dias ou
   meses após o aniversário de 16 anos.
3. Medir a defasagem entre celebração e registro e avaliar a sensibilidade do resultado ao uso
   da data do registro.
4. Construir taxas por residência, eliminando a incompatibilidade entre local do cartório no
   numerador e residência no denominador.
5. Documentar cobertura, valores ausentes, crítica/imputação e estabilidade do RC.2 entre
   2013 e 2024, inclusive no fluxo recebido da Fundação SEADE para São Paulo.

### Metodologia do projeto

#### Universo e construção

O universo solicitado contém os registros de casamento civil e religioso com efeito civil do
RC.2, 2013--2024. Para cada cônjuge será calculada a idade exata, em dias, na data da
celebração. Os eventos serão convertidos em um painel agregado por faixa estreita de idade,
data da celebração, sexo/composição e geografia compatível. O mesmo evento será contado uma
única vez nos resultados por casamento e uma vez por cônjuge nos resultados de pessoa, com
identidades de contagem explicitamente separadas.

#### Estimando e modelo principal

O estimando principal é a mudança pós-reforma na taxa de casamento formal imediatamente
abaixo de 16 anos, relativa à taxa imediatamente acima de 16 e à descontinuidade observada no
mesmo limite etário antes da reforma. Trata-se de uma diferença em descontinuidades de taxa de
evento nos eixos idade-calendário; não será descrita como RD de outcome individual.

O modelo será Poisson/PPML para contagens por faixa estreita de idade e período, com exposição
populacional compatível, funções locais de idade permitidas em ambos os lados de 16 anos,
efeitos fixos de período e interações que permitam mudanças de inclinação após a lei. O
parâmetro principal será a interação `idade abaixo de 16 × período integralmente pós-lei`,
comparada com a descontinuidade pré-lei. A unidade de inferência será o período/calendário,
com inferência de série temporal e randomização de datas placebo conforme a quantidade de
períodos disponível.

As exposições populacionais serão agregadas e não identificáveis. A estratégia preferida é
construir denominadores fora da SAR a partir de fontes públicas oficiais e importar, se
necessário e autorizado, somente uma tabela agregada por período, idade/faixa de idade, sexo e
geografia. O arquivo e o dicionário serão entregues ao IBGE antes do uso, conforme o item 2.2
do Guia da SAR. Se a importação não for autorizada, os numeradores agregados aprovados serão
combinados com os denominadores somente após a liberação.

#### Diagnósticos e robustez

- reconciliação exata com totais públicos do IBGE por ano, idade completa, sexo/composição e
  local do registro;
- taxa de preenchimento e validade das datas e da residência por ano e fonte de coleta;
- distribuição da defasagem entre celebração e registro;
- heaping em datas de nascimento, casamento e aniversário;
- bandwidths de 90, 180 e 365 dias ao redor de 16 anos;
- funções locais lineares e quadráticas, com regra de seleção baseada apenas no pré-período;
- cutoffs placebo aos 15 e 17 anos e datas placebo antes de março de 2019;
- estabilidade pré-reforma da descontinuidade aos 16 anos;
- donut windows em torno do aniversário, se houver heaping administrativo;
- massa de eventos nos 30, 90, 180 e 365 dias após completar 16 anos para medir adiamento;
- janelas que terminam antes da pandemia e extensão posterior claramente separada;
- teste de poder/MDE definido antes da seleção da largura de banda final.

#### Hipótese de identificação

Na ausência da reforma, a mudança na descontinuidade da taxa de celebrações aos 16 anos teria
evoluído suavemente em março de 2019. Choques nacionais específicos de idade, antecipação,
heaping e mudança de composição ao redor do cutoff podem violar essa hipótese e serão
avaliados pelos diagnósticos acima. O desenho identifica a margem formal; não identifica, sem
dados adicionais, mudança na formação de união informal.

### Tabulações e saídas solicitadas

Todas as saídas serão nacionais ou suficientemente agregadas para cumprir as regras de
confidencialidade do IBGE. Células pequenas serão suprimidas ou substituídas por resultados de
modelos aprovados.

1. Cobertura anual e percentual de valores válidos para cada variável solicitada.
2. Reconciliação entre microdados e tabelas públicas, sem células identificáveis.
3. Histograma agregado da idade exata na celebração ao redor de 16 anos, por período pré/pós.
4. Distribuição agregada da defasagem celebração--registro.
5. Matriz agregada entre UF/região de residência e UF/região de registro.
6. Coeficientes, erros-padrão, intervalos e p-valores do modelo principal e das robustezes.
7. Resultados dos placebos, MDE e diagnósticos de heaping/missingness.
8. Figuras construídas a partir de células liberáveis ou de predições agregadas do modelo.

### Produto final

- artigo acadêmico em Economia sobre a reforma de 2019;
- apêndice de dados e mensuração;
- código de replicação sem microdados;
- data availability statement descrevendo o procedimento de acesso à SAR;
- tabelas/figuras agregadas aprovadas pelo IBGE.

### Disseminação dos resultados

Working paper, seminários acadêmicos, eventual submissão a periódico científico e repositório
de replicação contendo apenas código, documentação e resultados autorizados. Todo produto
conterá a nota institucional exigida pelo Anexo 3 do Guia da SAR. As interpretações serão de
responsabilidade exclusiva dos autores.

### Requisitos do projeto

- acesso presencial à SAR no Rio de Janeiro, salvo atualização posterior do procedimento;
- estação com R; Stata apenas se previamente autorizado e necessário;
- scripts preparados e testados em dados sintéticos construídos pelos autores;
- tempo estimado de uso: **[A ESTIMAR APÓS CONFIRMAÇÃO DO DICIONÁRIO E PILOTO]**;
- orçamento para taxa da SAR e deslocamento: **[PREENCHER]**.

### Bases que serão utilizadas

1. **IBGE — Estatísticas do Registro Civil, RC.2 Casamentos, 2013--2024**, microdados não
   desidentificados dentro da SAR.
2. **Fontes públicas oficiais agregadas para população/exposição**, arquivo e dicionário a
   serem definidos após a resposta técnica do IBGE. Não haverá nomes, endereços ou chaves de
   ligação individual.

### Bases externas

**[PREENCHER APÓS ESCOLHA DO DENOMINADOR]**. Candidatas: tabelas agregadas de população
do IBGE e/ou contagens agregadas de coortes de nascimento do SINASC. Antes da submissão, o
arquivo final, o dicionário e a URL oficial serão anexados conforme o item 2.2 do Guia.

### Software

R, com pacotes de manipulação de dados, PPML e gráficos. Stata somente se uma rotina de
inferência indispensável não puder ser reproduzida em R e após autorização.

## 2. Variáveis solicitadas e necessidade

| Campo conceitual | Necessidade científica | Regra de minimização |
|---|---|---|
| Data da celebração (dia/mês/ano) | timing legal e idade exata | indispensável |
| Data do registro (dia/mês/ano de referência) | medir defasagem e reconciliar com a série pública | indispensável |
| Data de nascimento de cada cônjuge | idade exata no evento | indispensável; não exportar datas |
| Sexo/composição | consistência de contagem e heterogeneidade pré-especificada | exportar apenas agregados |
| Estado civil anterior | validar primeira formalização como sensibilidade, sem chamar de primeira união | exportar apenas agregados |
| Município/UF de domicílio ou residência | numerador e denominador geograficamente compatíveis | códigos apenas; sem endereço |
| Município/UF do cartório | reconciliação e defasagem espacial | código não identificador da unidade; suprimir células pequenas |
| Chave interna do evento | impedir dupla contagem | uso exclusivo dentro da SAR; não exportar |
| Flags de crítica, imputação, ausência e forma de coleta | auditoria de qualidade e estabilidade | exportar taxas agregadas |

Variáveis explicitamente não solicitadas: nomes, CPF, RG, endereço, número do livro, número do
registro e qualquer texto livre que possa identificar pessoas.

## 3. Cadastro do solicitante

- Instituição: **[PREENCHER]**
- Pesquisador responsável: **[PREENCHER]**
- Demais pesquisadores, máximo de três: **[PREENCHER]**
- CPF/RG/data de nascimento/endereço/contatos: **[PREENCHER DIRETAMENTE NO GOV.BR;
  NÃO VERSIONAR NESTE REPOSITÓRIO]**
- Responsável institucional solidário: **[PREENCHER]**
- Carta do departamento, se aplicável: **[ANEXAR]**

## 4. Itens que devem ser resolvidos antes da submissão

1. Obter confirmação técnica do IBGE sobre retenção/codificação anual dos campos e fluxo
   SEADE.
2. Escolher e construir o denominador de exposição; entregar somente arquivo agregado e
   dicionário.
3. Fazer contagem aproximada de eventos por bandwidth usando as tabelas públicas para
   estimar poder e tempo de sala.
4. Produzir dados sintéticos com o layout conceitual e testar todos os scripts antes da visita.
5. Definir instituição, responsáveis, orçamento e software final.
6. Congelar um protocolo específico antes de visualizar qualquer estimativa nova na SAR.
