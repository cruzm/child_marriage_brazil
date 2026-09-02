# Geography selection from denominator precision

Created: 2026-09-02T02:33:42-0300

This decision uses only PNADC denominator precision, before any post-reform effect is estimated.
The annual calibrated first-visit weight is V1032 and is not divided by four.
A cell passes when unweighted n >= 30 and CV <= 20%.
A geography is eligible when at least 95% of age-15 sex-specific/combined cells pass and no CV exceeds 35%.

| Level | Cells | Share passing | Minimum n | Median n | Maximum CV | Median CV | Eligible | Selected |
|---|---:|---:|---:|---:|---:|---:|:---:|:---:|
| UF | 891 | 0.983 |   23 | 153.0 | 0.252 | 0.095 | TRUE |  TRUE |
| region | 165 | 1.000 |  240 | 790.0 | 0.080 | 0.045 | TRUE | FALSE |
| Brazil |  33 | 1.000 | 2560 | 4265.0 | 0.033 | 0.021 | TRUE | FALSE |

**Selected primary geography: UF.**

UF estimates remain available as a pre-specified sensitivity analysis. Normal-approximation intervals use Taylor linearization with the official strata, UPAs, and weights; lonely PSUs use the documented `adjust` rule.
