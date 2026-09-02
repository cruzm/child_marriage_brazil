#!/usr/bin/env python3
"""Cross-country pilot — mechanical implementation of PILOT_PROTOCOL.md
(frozen 2026-09-02T16:25:05-03:00, SHA256 cb3c503c...). Implementation details
not fixed by the protocol, decided BEFORE any value was fetched:
  - cohort year c = SurveyYear - (agegroup_mid - 18); exact-duplicate cohorts
    merged by unweighted mean (denominators not consistently exposed);
  - values at reform and reform-10 by linear interpolation within the observed
    cohort span only; if the target lies outside the span, the nearest observed
    cohort within 3 years is used (flagged); otherwise NA (data gap);
  - M3 uses the survey closest before the reform year; if none, closest after
    (flagged), per protocol.
Raw API responses are saved under outputs/raw/ for audit."""

import json, math, os, urllib.request, urllib.parse

BASE = "https://api.dhsprogram.com/rest/dhs/data"
HERE = os.path.dirname(os.path.abspath(__file__))
RAW = os.path.join(HERE, "outputs", "raw")
OUT = os.path.join(HERE, "outputs")
os.makedirs(RAW, exist_ok=True)

# Roster per frozen protocol (country -> (DHS code or None, reform decimal year, date status))
ROSTER = {
    "Benin":       ("BJ", 2004 + 7/12,  "verified (B&P Table 1: 08/2004)"),
    "Bhutan":      (None, 1996 + 6/12,  "verified (B&P Table 1: 07/1996); no DHS -> data gap"),
    "Kazakhstan":  ("KZ", 1998 + 11/12, "verified (B&P Table 1: 12/1998)"),
    "Mauritania":  ("MR", 2001 + 6/12,  "verified (B&P Table 1: 07/2001)"),
    "Nepal":       ("NP", 2002 + 8/12,  "verified (B&P Table 1: 09/2002)"),
    "Tajikistan":  ("TJ", 2010 + 6/12,  "verified (B&P Table 1: 07/2010)"),
    "Ethiopia":    ("ET", 2000.5,       "verified (McGavock 2021: Family Code 2000)"),
    "Bangladesh":  ("BD", 2017.2,       "verified (Amirapu et al. 2026: CMRA 2017)"),
    "Indonesia":   ("ID", 2019.75,      "partially verified (Law 16/2019) - confirm primary text"),
    "Mozambique":  ("MZ", 2019.75,      "partially verified (Law 19/2019) - confirm primary text"),
}
ALTERNATE = {"Honduras": ("HN", 2017.6, "partially verified (2017 ban) - alternate, enters only for API-empty roster country")}

IND_COHORT = ["MA_MBAG_W_B18", "MA_MBAG_W_B15"]
IND_STATUS = ["MA_MSTA_W_MAR", "MA_MSTA_W_LTG"]
AGE_MID = {"20-24": 22, "25-29": 27, "30-34": 32, "35-39": 37, "40-44": 42, "45-49": 47}

def api(params, cache_name):
    path = os.path.join(RAW, cache_name)
    if os.path.exists(path):
        return json.load(open(path))
    url = BASE + "?" + urllib.parse.urlencode(params)
    with urllib.request.urlopen(url, timeout=60) as r:
        d = json.load(r)
    json.dump(d, open(path, "w"))
    return d

def fetch(country_code, indicator):
    rows, page = [], 1
    while True:
        d = api({"indicatorIds": indicator, "countryIds": country_code,
                 "breakdown": "all", "perPage": 5000, "page": page, "f": "json"},
                f"{country_code}_{indicator}_p{page}.json")
        rows += d.get("Data", [])
        if page >= d.get("TotalPages", 1):
            return rows
        page += 1

def cohort_series(rows):
    pts = {}
    for r in rows:
        lab = str(r.get("CharacteristicLabel", "")).strip()
        if lab not in AGE_MID:
            continue
        c = int(r["SurveyYear"]) - (AGE_MID[lab] - 18)
        pts.setdefault(c, []).append(float(r["Value"]))
    return {c: sum(v) / len(v) for c, v in sorted(pts.items())}

def value_at(series, year):
    if not series:
        return None, "no data"
    xs = sorted(series)
    if xs[0] <= year <= xs[-1]:
        lo = max(x for x in xs if x <= year)
        hi = min(x for x in xs if x >= year)
        if lo == hi:
            return series[lo], "observed"
        w = (year - lo) / (hi - lo)
        return series[lo] * (1 - w) + series[hi] * w, "interpolated"
    near = min(xs, key=lambda x: abs(x - year))
    if abs(near - year) <= 3:
        return series[near], f"nearest ({near})"
    return None, f"outside span ({xs[0]}-{xs[-1]})"

def status_share(mar_rows, ltg_rows, reform_year):
    def by_survey(rows):
        out = {}
        for r in rows:
            if str(r.get("CharacteristicLabel", "")).strip() == "15-19":
                out[int(r["SurveyYear"])] = float(r["Value"])
        return out
    m, l = by_survey(mar_rows), by_survey(ltg_rows)
    years = sorted(set(m) & set(l))
    if not years:
        return None, None, "no 15-19 status data"
    pre = [y for y in years if y < reform_year]
    y = max(pre) if pre else min(years)
    flag = "pre-reform survey" if pre else "POST-reform survey (no pre available)"
    tot = m[y] + l[y]
    return (100 * m[y] / tot if tot > 0 else None), y, flag

rows_out, cohort_out = [], []
for country, (code, reform, status) in ROSTER.items():
    if code is None:
        rows_out.append(dict(country=country, reform=round(reform, 2), law_status=status,
                             M1=None, M2=None, M1b=None, M2b=None, M3=None,
                             notes="no DHS in API - data gap (reported, not replaced)"))
        continue
    b18 = cohort_series(fetch(code, "MA_MBAG_W_B18"))
    b15 = cohort_series(fetch(code, "MA_MBAG_W_B15"))
    for c, v in b18.items():
        cohort_out.append(dict(country=country, cohort_year=c, married_by_18=round(v, 2)))
    v18r, f18r = value_at(b18, reform)
    v18p, f18p = value_at(b18, reform - 10)
    v15r, _ = value_at(b15, reform)
    v15p, _ = value_at(b15, reform - 10)
    M1 = v18r
    M2 = 100 * (v18r / v18p - 1) if (v18r and v18p) else None
    M1b = v15r
    M2b = 100 * (v15r / v15p - 1) if (v15r and v15p) else None
    m3, m3y, m3flag = status_share(fetch(code, "MA_MSTA_W_MAR"),
                                   fetch(code, "MA_MSTA_W_LTG"), reform)
    rows_out.append(dict(country=country, reform=round(reform, 2), law_status=status,
                         M1=round(M1, 1) if M1 else None,
                         M2=round(M2, 1) if M2 is not None else None,
                         M1b=round(M1b, 1) if M1b else None,
                         M2b=round(M2b, 1) if M2b is not None else None,
                         M3=round(m3, 1) if m3 is not None else None,
                         notes=f"M1 {f18r}; M1(-10) {f18p}; M3 {m3flag} ({m3y})"))

# classification per frozen rules
for r in rows_out:
    r["margin_class"] = (None if r["M2"] is None else
                         ("declining" if r["M2"] <= -20 else "alive"))
    r["formality_class"] = (None if r["M3"] is None else
                            ("formal-relevant" if r["M3"] >= 50 else "informal-dominant"))

import csv
with open(os.path.join(OUT, "PILOT_COHORT_SERIES.csv"), "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=["country", "cohort_year", "married_by_18"])
    w.writeheader(); w.writerows(cohort_out)
with open(os.path.join(OUT, "PILOT_METRICS.csv"), "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=list(rows_out[0].keys()))
    w.writeheader(); w.writerows(rows_out)

computable = [r for r in rows_out if r["M2"] is not None]
declining = [r for r in computable if r["margin_class"] == "declining"]
verdict = ("REGRA (padrão Brasil)" if len(declining) >= 6 else
           "EXCEÇÃO" if len(declining) <= 3 else "ZONA CINZENTA")
print(f"computable={len(computable)} declining={len(declining)} verdict={verdict}")
for r in rows_out:
    print(r)
