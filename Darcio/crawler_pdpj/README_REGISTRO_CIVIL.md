# Crawler do Registro Civil/IBGE

## Veredito de acesso

O adaptador `crawler_registro_civil_ibge.py` consegue descobrir e baixar os
arquivos oficiais de **tabelas públicas agregadas** de casamentos. Ele não baixa
microdados evento a evento: o catálogo público `Registro_Civil/` anuncia somente
`Codigos_dos_paises/` e `Tabelas_de_Resultados/`, e a política de confidencialidade
do IBGE informa que os microdados do Registro Civil não têm divulgação pública.

O código não tenta adivinhar URLs ocultas, usar credenciais da PDPJ no IBGE nem
contornar a Sala de Acesso a Dados Restritos (SAR). Se o projeto for aprovado na
SAR, os registros continuam no ambiente controlado; normalmente exportam-se apenas
resultados revisados pelo IBGE.

## Uso

Da raiz `Darcio/`:

```bash
python3 crawler_pdpj/crawler_registro_civil_ibge.py --probe-only
python3 crawler_pdpj/crawler_registro_civil_ibge.py --years 2013:2024 --dry-run
python3 crawler_pdpj/crawler_registro_civil_ibge.py --years 2013:2024
```

O formato `auto` prefere `xlsx`, usa `xls` nos anos antigos e recorre a `ods`
somente se necessário. Para escolher explicitamente:

```bash
python3 crawler_pdpj/crawler_registro_civil_ibge.py --years 2024 --format xlsx
```

Por padrão, os arquivos ficam em
`crawler_pdpj/dados_registro_civil_publico/<ano>/`. Os principais artefatos são:

- `catalog_probe.json`: entradas anunciadas no catálogo raiz e conclusão de escopo;
- `manifest.csv`: URL, nível dos dados, formato, bytes, SHA-256, membros do ZIP,
  horário e uso ou não do checkpoint;
- `04casamentos_*.zip`: planilhas oficiais da árvore `Tabelas_de_Resultados`.

Downloads são sequenciais, têm retentativas e intervalo mínimo entre requisições.
Cada arquivo é gravado primeiro como `.part`, validado por estrutura e CRC e só
então movido atomicamente. Um ZIP já existente e válido é reutilizado. Use
`--force` apenas para obter novamente uma revisão oficial.

## Testes

```bash
python3 -m unittest crawler_pdpj/test_crawler_registro_civil_ibge.py
```

Teste de integração sem guardar dados no repositório:

```bash
python3 crawler_pdpj/crawler_registro_civil_ibge.py \
  --years 2013,2024 \
  --output-dir /tmp/registro_civil_ibge_integration
```

### Resultado da validação de 2026-09-02

- testes unitários: 6/6 passaram;
- catálogo raiz: duas entradas (`Codigos_dos_paises/` e
  `Tabelas_de_Resultados/`) e nenhum link anunciado de microdados;
- descoberta sem download: 12/12 anos de 2013 a 2024 encontrados;
- integração 2013: ZIP XLS de 4.295.919 bytes, 47 planilhas válidas,
  SHA-256 `579e5058e9de5311dce331d439abaa9de5cf2f18abe6dd2db5aba1103b1c7ab6`;
- integração 2024: ZIP XLSX de 673.885 bytes, 24 planilhas válidas,
  SHA-256 `7ec70571af774c5a9c384434ff1eba70255fd712988c13883c665043c09e000c`;
- segunda execução: ambos os arquivos foram validados e reutilizados pelo
  checkpoint, sem novo download.

Após a retomada, a aquisição sequencial completa também passou:

- 12/12 arquivos de 2013 a 2024 baixados e validados;
- 29,83 MiB no total, sem expansão das planilhas no disco;
- 12/12 arquivos reutilizados por checkpoint na execução seguinte;
- todos os ZIPs passaram na verificação independente de CRC;
- nenhum arquivo `.part` permaneceu após a execução;
- manifesto portátil com URLs e SHA-256 preservado em
  `outputs/audit/REGISTRY_PUBLIC_TABLES_ACQUISITION.csv`.

O teste inicial de 2013/2024 foi mantido somente em `/tmp`. A aquisição completa
fica em `dados_registro_civil_publico/`, que é ignorado pelo Git; apenas o código,
os testes e esta documentação entram no controle de versão.

## O que estes arquivos permitem

As planilhas públicas acrescentam tabelas prontas por mês, idade agrupada, sexo,
estado civil anterior e lugar do registro, conforme o ano. Elas são úteis para
reconciliação e análises agregadas. Não entregam simultaneamente, por casamento,
datas exatas de nascimento e celebração e residência de ambos os cônjuges — os
campos necessários para o redesenho causal com idade em dias.

Fontes oficiais:

- catálogo: <https://ftp.ibge.gov.br/Registro_Civil/>;
- tabelas: <https://ftp.ibge.gov.br/Registro_Civil/Tabelas_de_Resultados/>;
- confidencialidade: <https://biblioteca.ibge.gov.br/visualizacao/livros/liv101636.pdf>;
- SAR: <https://www.gov.br/pt-br/servicos/solicitacao-de-acesso-a-sala-de-dados-restritos>.
