"""Extract, sample and clean CDC BRFSS 2023 respondents for healthcare_db.

Input : data/raw/LLCP2023ASC.zip (fixed-width ASCII, 433,323 records x 2111 chars)
Output (CSV, LF line endings, empty field = missing; loaded by healthcare_db_load_data.sql):
        data/extract/brfss_2023_sample_raw.csv   - the sampled rows with ORIGINAL codes
        data/processed/brfss_2023_clean.csv      - the same rows mapped to our schema
        data/processed/brfss_missing_profile.csv - how missing data is coded, per variable

Usage:  python etl/clean_brfss.py
"""
import csv
import datetime
import pathlib
import random
import sys
import zipfile
from collections import Counter

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from brfss_layout import field, load_layout  # noqa: E402

ROOT = pathlib.Path(__file__).resolve().parent.parent
RAW_ZIP = ROOT / "data" / "raw" / "LLCP2023ASC.zip"
EXTRACT_CSV = ROOT / "data" / "extract" / "brfss_2023_sample_raw.csv"
CLEAN_CSV = ROOT / "data" / "processed" / "brfss_2023_clean.csv"
PROFILE_CSV = ROOT / "data" / "processed" / "brfss_missing_profile.csv"

RECORD_LENGTH = 2111
SURVEY_YEAR = 2023
SAMPLE_PER_STATE = 100
RANDOM_SEED = 2023
# FIPS codes of the five states the project compares (high vs low cost of living)
STATES = {6: "California", 17: "Illinois", 28: "Mississippi", 36: "New York", 54: "West Virginia"}

# Source variables we keep in the raw extract (original BRFSS names and codes)
CHRONIC_FLAGS = ["CVDINFR4", "CVDCRHD4", "CVDSTRK3", "ASTHMA3", "CHCCOPD3",
                 "ADDEPEV3", "CHCKDNY2", "HAVARTH4", "CHCOCNC1", "DIABETE4"]
SOURCE_VARS = (["_STATE", "SEQNO", "IDATE", "SEXVAR", "_AGEG5YR", "_URBSTAT", "MSCODE",
                "NUMADULT", "HHADULT", "CHILDREN", "INCOME3", "GENHLTH", "MENTHLTH",
                "PRIMINS1", "_BMI5", "_SMOKER3", "EXERANY2", "EXEROFT1"] + CHRONIC_FLAGS)

# INCOME3 bracket -> midpoint in USD. Bracket 11 is open-ended ($200,000 or more):
# its lower bound is used. 77 = Don't know, 99 = Refused -> NULL.
INCOME_MIDPOINT = {1: 5000, 2: 12500, 3: 17500, 4: 22500, 5: 30000, 6: 42500,
                   7: 62500, 8: 87500, 9: 125000, 10: 175000, 11: 200000}

AGE_GROUPS = {1: "18-24", 2: "25-29", 3: "30-34", 4: "35-39", 5: "40-44", 6: "45-49",
              7: "50-54", 8: "55-59", 9: "60-64", 10: "65-69", 11: "70-74",
              12: "75-79", 13: "80+"}

# Labels of our lookup tables (see healthcare_db_lookup.sql). The cleaned CSV holds
# labels, not IDs: the generated SQL looks the AUTO_INCREMENT IDs up by label.
GENDER_FEMALE, GENDER_MALE = "Female", "Male"
RESIDENCE_URBAN, RESIDENCE_RURAL = "Urban", "Rural"
LABEL_OPTIMAL, LABEL_MODERATE, LABEL_HIGH, LABEL_CRITICAL = "Optimal", "Moderate Risk", "High Burden", "Critical Risk"

CLEAN_COLUMNS = [
    "SourceRecordKey", "StateID", "Year", "ResidenceType", "HouseholdIncome",
    "HouseholdSize", "NumEarners", "ChildrenUnderLegalAge", "Gender", "AgeGroup",
    "HealthLabel", "MeasurementDate", "DistanceToCareKM", "HasInsurance", "BMI",
    "ChronicConditionsCount", "SelfReportedHealth", "MentalHealthScore",
    "SmokingStatus", "ExerciseDaysPerWeek",
]


def to_int(code):
    return int(code) if code != "" else None


# ---------- per-variable cleaning rules (each returns None for missing) ----------

def clean_gender(sexvar):
    # BRFSS codes 1 = Male, 2 = Female (our Gender table also has "Other").
    return {1: GENDER_MALE, 2: GENDER_FEMALE}[to_int(sexvar)]


def clean_residence(urbstat):
    # BRFSS: 1 = Urban county, 2 = Rural county, blank = not geocoded. No suburban category.
    return {1: RESIDENCE_URBAN, 2: RESIDENCE_RURAL}.get(to_int(urbstat))


def clean_adults(numadult, hhadult):
    # Same concept, two variables: NUMADULT is asked on landline interviews,
    # HHADULT on cell phone interviews. Exactly one of them is filled in.
    n = to_int(numadult)
    if n is not None:
        return n
    h = to_int(hhadult)
    return None if h in (None, 77, 99) else h


def clean_children(children):
    c = to_int(children)
    if c == 88:          # 88 = "None" -> zero children, NOT missing
        return 0
    return None if c in (None, 99) else c


def clean_income(income3):
    return INCOME_MIDPOINT.get(to_int(income3))


def clean_age_group(ageg5yr):
    return AGE_GROUPS.get(to_int(ageg5yr))   # 14 = Don't know/Refused -> NULL


def clean_date(idate):
    # IDATE is a character field formatted MMDDYYYY
    return datetime.datetime.strptime(idate, "%m%d%Y").date().isoformat()


def clean_insurance(primins1):
    p = to_int(primins1)
    if p == 88:          # 88 = "No coverage of any type"
        return 0
    if p is not None and 1 <= p <= 10:
        return 1         # any listed plan type
    return None          # 77 Don't know, 99 Refused, blank


def clean_bmi(bmi5):
    b = to_int(bmi5)     # 2 implied decimal places: 2350 -> 23.50
    return None if b is None else round(b / 100, 1)


def clean_self_reported_health(genhlth):
    g = to_int(genhlth)
    # BRFSS: 1 = Excellent ... 5 = Poor. Ours: 5 = best ... 1 = worst -> reverse.
    return 6 - g if g is not None and 1 <= g <= 5 else None


def clean_mental_health(menthlth):
    d = to_int(menthlth)  # days in the past 30 with poor mental health
    if d == 88:
        d = 0             # 88 = "None"
    if d is None or not 0 <= d <= 30:
        return None       # 77 Don't know, 99 Refused
    # Band to our 1-5 scale (5 = best). 14+ days = CDC "frequent mental distress".
    if d == 0:
        return 5
    if d <= 5:
        return 4
    if d <= 13:
        return 3
    if d <= 20:
        return 2
    return 1


def clean_smoking(smoker3):
    s = to_int(smoker3)
    # 1/2 = current smoker (every/some days), 3 = former, 4 = never, 9 = unknown
    return {1: 1, 2: 1, 3: 0, 4: 0}.get(s)


def clean_exercise(exerany2, exeroft1):
    any_ex = to_int(exerany2)
    if any_ex == 2:
        return 0                         # no exercise in the past 30 days
    if any_ex != 1:
        return None                      # 7 / 9 / blank
    freq = to_int(exeroft1)              # 1xx = times per week, 2xx = times per month
    if freq is None or freq in (777, 999):
        return None
    if 101 <= freq <= 199:
        per_week = freq - 100
    elif 201 <= freq <= 299:
        per_week = round((freq - 200) / 4.33)
    else:
        return None
    return min(per_week, 7)              # "times" can exceed days; cap at 7 days/week


def clean_chronic_count(raw):
    # Count conditions answered 1 = "Yes". For DIABETE4 only 1 counts
    # (2 = pregnancy only, 4 = pre-diabetes). 7/9/blank are treated as "not reported".
    return sum(1 for v in CHRONIC_FLAGS if to_int(raw[v]) == 1)


def derive_health_label(chronic, srh, mhs, bmi, smoker):
    """Documented rule that assigns the HealthLabel category (derived attribute)."""
    poor_health = srh is not None and srh <= 2
    poor_mental = mhs is not None and mhs <= 2
    if chronic >= 4 or (chronic >= 3 and poor_health):
        return LABEL_CRITICAL
    if chronic >= 3 or (chronic >= 2 and (poor_health or poor_mental)):
        return LABEL_HIGH
    if chronic >= 1 or poor_health or poor_mental or smoker == 1 or (bmi is not None and bmi >= 30):
        return LABEL_MODERATE
    return LABEL_OPTIMAL


def clean_record(raw):
    state = int(raw["_STATE"])
    adults = clean_adults(raw["NUMADULT"], raw["HHADULT"])
    children = clean_children(raw["CHILDREN"])
    chronic = clean_chronic_count(raw)
    srh = clean_self_reported_health(raw["GENHLTH"])
    mhs = clean_mental_health(raw["MENTHLTH"])
    bmi = clean_bmi(raw["_BMI5"])
    smoker = clean_smoking(raw["_SMOKER3"])
    return {
        "SourceRecordKey": f"BRFSS{SURVEY_YEAR}-{state:02d}-{raw['SEQNO']}",
        "StateID": state,
        "Year": SURVEY_YEAR,
        "ResidenceType": clean_residence(raw["_URBSTAT"]),
        "HouseholdIncome": clean_income(raw["INCOME3"]),
        "HouseholdSize": adults + children if adults is not None and children is not None else None,
        "NumEarners": None,                      # not collected by BRFSS
        "ChildrenUnderLegalAge": children,
        "Gender": clean_gender(raw["SEXVAR"]),
        "AgeGroup": clean_age_group(raw["_AGEG5YR"]),
        "HealthLabel": derive_health_label(chronic, srh, mhs, bmi, smoker),
        "MeasurementDate": clean_date(raw["IDATE"]),
        "DistanceToCareKM": None,                # not collected by BRFSS
        "HasInsurance": clean_insurance(raw["PRIMINS1"]),
        "BMI": bmi,
        "ChronicConditionsCount": chronic,
        "SelfReportedHealth": srh,
        "MentalHealthScore": mhs,
        "SmokingStatus": smoker,
        "ExerciseDaysPerWeek": clean_exercise(raw["EXERANY2"], raw["EXEROFT1"]),
    }


# ---------- missing-data profile ----------

# Special codes per variable, taken from the 2023 codebook. The same number means
# different things in different variables (e.g. 7 = "Don't know" for GENHLTH, but
# 7 = "$50,000-$75,000" for INCOME3 and "age 50-54" for _AGEG5YR), so this cannot be generic.
YES_NO_CODES = {7: "dont_know", 9: "refused"}
SPECIAL_CODES = {
    **{v: YES_NO_CODES for v in CHRONIC_FLAGS},
    "GENHLTH": YES_NO_CODES,
    "EXERANY2": YES_NO_CODES,
    "EXEROFT1": {777: "dont_know", 999: "refused"},
    "MENTHLTH": {88: "88 = none (zero days, valid)", 77: "dont_know", 99: "refused"},
    "PRIMINS1": {88: "88 = no coverage (valid)", 77: "dont_know", 99: "refused"},
    "INCOME3": {77: "dont_know", 99: "refused"},
    "CHILDREN": {88: "88 = none (zero children, valid)", 99: "refused"},
    "HHADULT": {77: "dont_know", 99: "refused"},
    "_SMOKER3": {9: "dont_know_refused_or_missing"},
    "_AGEG5YR": {14: "dont_know_refused_or_missing"},
}


def missing_category(var, code):
    if code == "":
        return "blank (not asked / skip pattern / not computed)"
    return SPECIAL_CODES.get(var, {}).get(int(code), "valid")


def main():
    layout = load_layout()
    missing = [v for v in SOURCE_VARS if v not in layout]
    if missing:
        raise KeyError(f"Variables not in layout: {missing}")

    with zipfile.ZipFile(RAW_ZIP) as zf:
        member = zf.namelist()[0]          # note: CDC's member name has a trailing space
        by_state = {s: [] for s in STATES}
        seen_keys = Counter()
        total = 0
        with zf.open(member) as f:
            for line in f:
                record = line.decode("latin-1").rstrip("\r\n")
                if len(record) != RECORD_LENGTH:
                    raise ValueError(f"Record {total + 1} has length {len(record)}, expected {RECORD_LENGTH}")
                total += 1
                state = int(field(record, layout, "_STATE"))   # stored zero-padded, e.g. '06'
                if state in STATES:
                    raw = {v: field(record, layout, v) for v in SOURCE_VARS}
                    seen_keys[(state, raw["SEQNO"])] += 1
                    by_state[state].append(raw)

    duplicates = [k for k, n in seen_keys.items() if n > 1]
    print(f"Read {total} records; {sum(len(v) for v in by_state.values())} in the 5 states; "
          f"{len(duplicates)} duplicate (_STATE, SEQNO) keys")
    if duplicates:
        raise ValueError(f"Duplicate respondent keys: {duplicates[:5]}")

    # Missing-data profile over the full 5-state population (not just the sample)
    profile = Counter()
    for rows in by_state.values():
        for raw in rows:
            for v in SOURCE_VARS:
                profile[(v, missing_category(v, raw[v]))] += 1

    rng = random.Random(RANDOM_SEED)
    sample = []
    for state in sorted(STATES):
        print(f"  {STATES[state]:<14} population {len(by_state[state]):>6} -> sample {SAMPLE_PER_STATE}")
        sample.extend(rng.sample(by_state[state], SAMPLE_PER_STATE))

    EXTRACT_CSV.parent.mkdir(parents=True, exist_ok=True)
    CLEAN_CSV.parent.mkdir(parents=True, exist_ok=True)
    with EXTRACT_CSV.open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=SOURCE_VARS, lineterminator="\n")
        w.writeheader()
        w.writerows(sample)

    cleaned = [clean_record(r) for r in sample]
    with CLEAN_CSV.open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=CLEAN_COLUMNS, lineterminator="\n")
        w.writeheader()
        for row in cleaned:
            w.writerow({k: ("" if v is None else v) for k, v in row.items()})

    with PROFILE_CSV.open("w", newline="", encoding="utf-8") as f:
        w = csv.writer(f, lineterminator="\n")
        w.writerow(["variable", "category", "count_in_5_state_population"])
        for (v, cat), n in sorted(profile.items()):
            w.writerow([v, cat, n])

    nulls = Counter(k for row in cleaned for k, v in row.items() if v is None)
    print(f"Wrote {len(sample)} rows to {EXTRACT_CSV.relative_to(ROOT)} and {CLEAN_CSV.relative_to(ROOT)}")
    print("NULLs after cleaning:", dict(sorted(nulls.items())))


if __name__ == "__main__":
    main()
