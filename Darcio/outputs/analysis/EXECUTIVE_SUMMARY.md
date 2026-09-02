# Sumário executivo — Lei nº 13.811/2019

## Pergunta e desenho

A Lei nº 13.811/2019 entrou em vigor em 13 de março de 2019 e eliminou as exceções que permitiam casamento civil abaixo da idade núbil. Ela não proibiu todos os casamentos abaixo de 18: os de 16 e 17 anos continuaram regidos pelo art. 1.517 do Código Civil.

A avaliação combina a tabela oficial 4406 do Registro Civil/SIDRA (2013–2024) com microdados trimestrais da PNADC. Como a idade existe apenas em anos completos, o desenho é diferenças-em-diferenças por elegibilidade etária, não RD. A especificação foi congelada antes dos resultados: idade 15 é tratada, idades 17–19 são controles, 2019T1 é omitido e o pós curto é 2019T2–T4. O modelo principal é PPML regional com população como offset, efeitos fixos, sazonalidade e tendências específicas por idade; a inferência principal agrupa por período porque houve uma única reforma nacional.

## Resultado principal

A estimativa congelada é **-1,1%** nos registros aos 15 anos (razão de taxas 0,989; IC95% [-14,9%; 14,9%]; p=0,888). Em níveis: -0,022 por 100 mil e 2,1 eventos previstos evitados, com IC95% de -25,2 a 33,8.

O intervalo não exclui uma queda de 14,9% nem um aumento de 14,9%. A versão sem tendências encontra queda de 37,8%. Essa divergência, somada a placebo significativo em 2015T2 e sensibilidade à janela pré, mostra que a trajetória descendente anterior à lei é decisiva. O estudo não sustenta uma simples leitura antes/depois.

O protocolo pós-resultado de forecast foi congelado antes das estimativas da extensão. Nenhum dos cinco modelos passa a calibração pré-2019. O melhor RMSE produz 2,0% (intervalo [-17,6%; 23,4%]) e o ensemble, 3,0%; a faixa de pontos [-33,7%; 12,8%] não é intervalo nem bound causal. Logo, nem o −1,1% nem o −37,8% é design-wide.

## Adiamento e comportamento

Os pontos aos 16 e 17 anos são +0,6% e +3,3%, respectivamente, mas não são precisos após correção por múltiplos testes. A recaptura agregada tem intervalo extremamente amplo e só é definida em cerca de metade dos sorteios. Não há evidência confiável de adiamento.

Na PNADC, a união conservadora aos 15 anos aumenta relativamente em **0,399 p.p.**, IC95% [-0,003; 0,801] p.p. O MDE é 0,575 p.p. e a equivalência a ±0,50 p.p. não é demonstrada. Robustezes de microdados têm pontos semelhantes. Isso é sugestivo de maior coabitação relativa, mas não prova substituição para informalidade: o Registro mede fluxo formal, a PNADC mede estoque corresidente incompleto, e seus coeficientes não podem ser subtraídos.

## Conclusões que os dados permitem

- O número observado de casamentos com alguém abaixo de 16 caiu fortemente entre 2013 e 2024, mas grande parte da queda precede a lei.
- O modelo congelado não detecta queda adicional nos registros aos 15 anos em 2019T2–T4, mas todos os contrafactuais do gate falham; o estudo não estabelece queda nem efeito zero design-wide.
- Não há evidência precisa de adiamento para 16–17 anos.
- Não há evidência de redução da união corresidente; o sinal positivo é compatível, mas insuficiente, para informalização.

## Limitações decisivas

A fonte registra mês e idade no registro, não na celebração; cartório e residência não são a mesma geografia; não há idade exata para RD; 2019 oferece só três trimestres integralmente tratados; nenhum dos cinco modelos de tendência passa a calibração rolling-origin; a PNADC não acompanha confiavelmente quem deixa o domicílio; a união conservadora capta principalmente relações com a pessoa responsável; e o MDE de 19,3% é condicional ao modelo travado.

## Replicação

```bash
./Darcio/run_all.sh
```

Todos os arquivos, testes, resultados e limitações estão em `Darcio/outputs/`; o lock e suas emendas estão em `Darcio/config/` e `Darcio/outputs/analysis/`.
