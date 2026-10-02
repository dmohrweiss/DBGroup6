"""Clean BEA Regional Price Parities by state (SARPP) for healthcare_db.

Input : data/raw/SARPP.zip -> SARPP_STATE_2008_2024.csv
        (wide format: one row per state x price category, one column per year)
Output: data/extract/bea_sarpp_raw.csv        - the original CSV, untouched (small, committed)
        data/processed/bea_states.csv         - one row per state (Region table)
        data/processed/bea_cost_of_living.csv - one row per state x year (CostOfLiving table)

Usage:  python etl/clean_bea.py
"""
import csv
import io
import pathlib
import zipfile
from collections import Counter

ROOT = pathlib.Path(__file__).resolve().parent.parent
RAW_ZIP = ROOT / "data" / "raw" / "SARPP.zip"
MEMBER = "SARPP_STATE_2008_2024.csv"
EXTRACT_CSV = ROOT / "data" / "extract" / "bea_sarpp_raw.csv"
STATES_CSV = ROOT / "data" / "processed" / "bea_states.csv"
COL_CSV = ROOT / "data" / "processed" / "bea_cost_of_living.csv"

# BEA LineCode -> our CostOfLiving column
LINE_TO_COLUMN = {
    1: "CostIndex",               # RPPs: All items
    2: "GoodsCostIndex",          # RPPs: Goods
    3: "HousingCostIndex",        # RPPs: Services: Housing
    4: "UtilitiesCostIndex",      # RPPs: Services: Utilities
    5: "OtherServicesCostIndex",  # RPPs: Services: Other
}

# BEA publishes names and FIPS codes but no postal abbreviations
STATE_ABBREV = {
    "Alabama": "AL", "Alaska": "AK", "Arizona": "AZ", "Arkansas": "AR", "California": "CA",
    "Colorado": "CO", "Connecticut": "CT", "Delaware": "DE", "District of Columbia": "DC",
    "Florida": "FL", "Georgia": "GA", "Hawaii": "HI", "Idaho": "ID", "Illinois": "IL",
    "Indiana": "IN", "Iowa": "IA", "Kansas": "KS", "Kentucky": "KY", "Louisiana": "LA",
    "Maine": "ME", "Maryland": "MD", "Massachusetts": "MA", "Michigan": "MI", "Minnesota": "MN",
    "Mississippi": "MS", "Missouri": "MO", "Montana": "MT", "Nebraska": "NE", "Nevada": "NV",
    "New Hampshire": "NH", "New Jersey": "NJ", "New Mexico": "NM", "New York": "NY",
    "North Carolina": "NC", "North Dakota": "ND", "Ohio": "OH", "Oklahoma": "OK", "Oregon": "OR",
    "Pennsylvania": "PA", "Rhode Island": "RI", "South Carolina": "SC", "South Dakota": "SD",
    "Tennessee": "TN", "Texas": "TX", "Utah": "UT", "Vermont": "VT", "Virginia": "VA",
    "Washington": "WA", "West Virginia": "WV", "Wisconsin": "WI", "Wyoming": "WY",
}

# BEA's own "Region" column is a multi-state region code, not a state
BEA_REGIONS = {1: "New England", 2: "Mideast", 3: "Great Lakes", 4: "Plains",
               5: "Southeast", 6: "Southwest", 7: "Rocky Mountain", 8: "Far West"}
MISSING_MARKERS = {"(NA)", "(D)", "(NM)", "(L)", ""}


def main():
    with zipfile.ZipFile(RAW_ZIP) as zf:
        raw_bytes = zf.read(MEMBER)
    EXTRACT_CSV.parent.mkdir(parents=True, exist_ok=True)
    EXTRACT_CSV.write_bytes(raw_bytes)

    text = raw_bytes.decode("latin-1")   # BEA files are not UTF-8
    rows = list(csv.reader(io.StringIO(text)))
    header, body = rows[0], rows[1:]
    year_cols = [c for c in header if c.isdigit()]

    data_rows, footer_rows = [], []
    for r in body:
        (data_rows if len(r) == len(header) else footer_rows).append(r)
    print(f"{len(data_rows)} data rows, {len(footer_rows)} footer note rows dropped: {[f[0] for f in footer_rows]}")

    states, values = {}, {}
    key_counts = Counter()
    missing_cells, aggregate_rows = 0, 0
    for r in data_rows:
        rec = dict(zip(header, r))
        geofips = rec["GeoFIPS"].strip().strip('"').strip()   # raw value looks like ' "06000"'
        state_fips = int(geofips) // 1000                    # 06000 -> 6
        line = int(rec["LineCode"])
        key_counts[(geofips, line)] += 1
        if state_fips == 0:                                  # "United States" aggregate row
            aggregate_rows += 1
            continue
        name = rec["GeoName"].strip()
        region = rec["Region"].strip()
        states[state_fips] = {
            "StateID": state_fips,
            "StateName": name,
            "StateAbbrev": STATE_ABBREV[name],
            "BEARegionCode": int(region),
            "BEARegionName": BEA_REGIONS[int(region)],
        }
        # Unpivot: wide year columns (a repeating group) -> one value per (state, year)
        for year in year_cols:
            cell = rec[year].strip()
            if cell in MISSING_MARKERS:
                missing_cells += 1
                continue
            values.setdefault((state_fips, int(year)), {})[LINE_TO_COLUMN[line]] = float(cell)

    dups = [k for k, n in key_counts.items() if n > 1]
    if dups:
        raise ValueError(f"Duplicate (GeoFIPS, LineCode) rows: {dups}")
    print(f"{len(states)} states/DC, {aggregate_rows} US-aggregate rows dropped, "
          f"{missing_cells} missing cells, 0 duplicate (GeoFIPS, LineCode) keys")

    STATES_CSV.parent.mkdir(parents=True, exist_ok=True)
    with STATES_CSV.open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=["StateID", "StateName", "StateAbbrev", "BEARegionCode", "BEARegionName"], lineterminator="\n")
        w.writeheader()
        w.writerows(states[s] for s in sorted(states))

    cols = ["StateID", "Year"] + list(LINE_TO_COLUMN.values())
    with COL_CSV.open("w", newline="", encoding="utf-8") as f:
        w = csv.writer(f, lineterminator="\n")
        w.writerow(cols)
        for (state, year) in sorted(values):
            v = values[(state, year)]
            w.writerow([state, year] + [v.get(c, "") for c in LINE_TO_COLUMN.values()])
    print(f"Wrote {len(states)} states and {len(values)} state-year rows")


if __name__ == "__main__":
    main()
