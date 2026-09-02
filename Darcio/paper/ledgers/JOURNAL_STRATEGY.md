# Journal Strategy — Paper 1 (2026-09-02)

**Base da avaliação:** manuscrito de 23 pp. pós red team, pós gate rolling-origin
(failed), com todos os ataques A1–A3/B1–B5 respondidos no texto, ledgers completos e
replicação 169/169. Probabilidades são FAIXAS condicionais às premissas declaradas;
nenhuma é promessa. Regra da casa: nunca prometer top 5.

## 1. Scorecard (0–10, com o fator que trava a nota)

| Dimensão | Nota | O que impede nota maior |
|---|---:|---|
| Importância da pergunta | 7 | Tema global (SDG 5.3), mas o caso brasileiro é margem vestigial — a importância vem da generalização, ainda não demonstrada |
| Novidade verificável | 7 | Primeira avaliação da 13.811 (protocolo rodado; Brasil ausente do painel de Le et al.); mecanismo de substituição já documentado no México |
| Identificação | 4 | Reforma nacional única; gate de calibração FALHOU; conclusão explicitamente condicional à especificação |
| Mensuração | 9 | Três margens (fluxo/estoque/status no parto), universos administrativos, defeito de 2015 detectado e tratado |
| Mecanismos | 5 | Substituição sugestiva (p=0,052; TOST falha); sem canal direto testável |
| Relevância externa | 6 | O caso-limite viaja; o paralelo etário com o México é contextual, não teste |
| Transparência/replicabilidade | 10 | Locks com hash, emendas, protocolo pós-resultado, manifesto com status causal por artefato, 169/169 |
| Clareza narrativa | 8 | Espinha "vanishing margin + como não avaliar" coesa; abstract denso |
| Fit com alvo pretendido | 6 | Excelente para field com gosto por credibilidade/mensuração; fraco para quem exige efeito causal líquido |
| Maturidade para submissão | 7 | Falta: checagem SSRN manual, aer.bst, title page, sweep final de DOIs |

**Classificação: `field-journal competitive`** — com identidade clara de *transparent
measurement and design-failure paper* (veredicto do red team pós-gate). Não é
`top-field competitive` hoje pela dimensão identificação; nenhuma reescrita muda isso —
só informação identificadora nova.

## 2. O que o paper É (para a cover letter)

Não é "avaliação com null". É: (i) a primeira avaliação da lei brasileira, com o
resultado de que a margem proibida já era vestigial e estável; (ii) uma demonstração
quantificada de como leis de idade mínima são mal avaliadas — a especificação ingênua
produz −37,8% e é exatamente a que reprova validação de forecast; um desenho igualmente
pré-comprometido no SINASC produz +29,3% espúrio pego por placebos; (iii) o aparato
mínimo de mensuração (fluxo × estoque × status) que a literatura deveria adotar.

## 3. Ladder recomendado (com premissas)

Premissas comuns: SSRN 6373839 checado; título/abstract mantêm o frame de
mensuração+desenho; sem novo concorrente Brasil até a submissão.

1. **Journal of Development Economics** — *primeira tentativa se e somente se* a
   extensão cross-country (ver §5) entrar. Sem ela: desk-reject 65–80%.
   Com ela: desk 45–60%; aceitação condicional a referees 15–25%.
2. **Journal of Human Resources** — a complementaridade com Bellés-Obrero & Lombardi é
   real, mas o JHR publicou o caso com efeito; o caso sem efeito e sem certificação de
   contrafactual tem desk 60–75%. Vale uma tentativa se o comitê de coautores prezar o
   sinal de ambição; não como primeira escolha racional.
3. **Journal of Population Economics** — fit forte (demografia econômica, tolerância a
   nulls honestos, público certo). Desk 30–45%; aceitação 25–40% condicional a
   referee mediano. **Primeira escolha do ladder sem a extensão cross-country.**
4. **World Development** — fit forte para o ângulo política/SDG; desk 25–40%;
   aceitação 25–40%. Alternativa quase equivalente ao JPopEcon; decide o par
   coautoral pelo público desejado (economia vs. desenvolvimento aplicado).
5. **Journal of Policy Analysis and Management** — o frame "como avaliar leis"
   encaixa; menor familiaridade com o contexto BR. Desk 35–50%.
6. **Economic Development and Cultural Change / Journal of Development Studies** —
   rede de segurança; probabilidade material.

## 4. Desk-risk memo (o que o editor vê em 10 minutos)

- Abstract: denso mas honesto; a frase final ("require separate measurement and
  credible counterfactual trends") diz ao editor qual literatura o paper serve. OK.
- Risco nº 1: "sofisticação a serviço de um não-resultado" — mitigado pela §Trend
  dependence e pela tabela de forecast (mostrar cedo que o "não-resultado" é o
  resultado). Manter TABLE_13 referenciada na introdução.
- Risco nº 2: extensão SINASC lida como "análise que falhou e ficou no paper" —
  a defesa é o critério simétrico; a introdução já o carrega.
- Risco nº 3: comprimento do aparato de locks para leitores não-metodológicos —
  considerar mover parte do §strategy para o appendix na versão de submissão.

## 5. A decisão que muda o teto: extensão cross-country

**Pergunta:** os bans recentes no mundo chegaram antes ou depois do colapso da própria
margem formal? Com DHS/MICS (idade na primeira união × ano-calendário) e as datas de
reforma já catalogadas por Collin & Talbot e Batyra & Pesando, constrói-se, por país
reformador, a trajetória da margem vinculada nos 10 anos pré-reforma — e testa-se se o
padrão Brasil (banir uma margem já vestigial) é a regra ou a exceção.

- **Se regra:** o paper vira "The World Is Banning a Vanishing Margin" — candidato
  real a JDE e a conversa com editores acima disso. Custo: 3–6 semanas de trabalho
  cuidadoso + novo pré-registro de medição.
- **Se exceção:** o Brasil volta a ser caso-limite; o paper atual segue exatamente
  como está, e o achado cross-country ainda rende um short paper demográfico.
- **EXECUTADO em 2026-09-02** (`pilot_crosscountry/`, protocolo congelado antes dos
  dados; API pública do DHS, 10 países + 1 alternate). **Veredicto: EXCEÇÃO — 0 de 7
  países computáveis tinham a margem em queda pré-reforma** (M2 de +1,6% a −19,9%;
  níveis 38–53% de married-by-18). O caminho "The World Is Banning a Vanishing
  Margin" está ENCERRADO; a rota JDE via generalização morreu; ladder do §3 fica
  como está (JPopEcon/World Development primeiro). Achado colateral valioso: a
  clivagem é de REGIME de formalidade (M3 formal 73–100% na África/Ásia vs 7,5% em
  Honduras, padrão Brasil) — explica por que Etiópia/México-16-17 acham efeitos e o
  Brasil não, e fornece o parágrafo de validade externa do Paper 1 (incorporação ao
  texto exige mini-protocolo, ver `PILOT_RESULTS.md` §2).

## 6. Sequência operacional

1. Checagem manual SSRN (você, 5 min) → fecha o Reference Ledger.
2. Piloto cross-country (decisão desta semana).
3. Title page (coautores, e-mail, acknowledgments), aer.bst, sweep de DOIs.
4. Submissão conforme §3; cover letter a partir do §2.
