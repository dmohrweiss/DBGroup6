"""Download the two open datasets (and BRFSS documentation) into data/raw/.

Sources
  A. CDC Behavioral Risk Factor Surveillance System (BRFSS) 2023 - public domain
  B. BEA Regional Price Parities by state (SARPP)              - public domain

The raw files are large (~60 MB) and are NOT committed (see .gitignore).
A MANIFEST.txt records the URL, server Last-Modified date and download date of
every file so the exact version used can be traced.

Usage:  python etl/fetch_data.py
"""
import datetime
import pathlib
import urllib.request

RAW = pathlib.Path(__file__).resolve().parent.parent / "data" / "raw"

FILES = {
    # BRFSS 2023, combined landline + cell phone data, ASCII fixed-width format
    "LLCP2023ASC.zip": "https://www.cdc.gov/brfss/annual_data/2023/files/LLCP2023ASC.zip",
    # BRFSS 2023 variable layout (column positions of every variable)
    "llcp_varlayout_23_onecolumn.html": "https://www.cdc.gov/brfss/annual_data/2023/llcp_varlayout_23_onecolumn.html",
    # BRFSS 2023 codebook (value labels and frequencies)
    "codebook23_llcp-v2-508.zip": "https://www.cdc.gov/brfss/annual_data/2023/zip/codebook23_llcp-v2-508.zip",
    # BEA Regional Price Parities by state, 2008-2024
    "SARPP.zip": "https://apps.bea.gov/regional/zip/SARPP.zip",
}


def main():
    RAW.mkdir(parents=True, exist_ok=True)
    lines = [f"Downloaded: {datetime.date.today().isoformat()}", ""]
    for name, url in FILES.items():
        target = RAW / name
        print(f"Downloading {url}")
        # CDC's CDN rejects some browser-like User-Agents; a plain client UA is accepted.
        req = urllib.request.Request(url, headers={"User-Agent": "curl/8.5.0"})
        with urllib.request.urlopen(req) as resp:
            target.write_bytes(resp.read())
            last_modified = resp.headers.get("Last-Modified", "unknown")
        lines.append(f"{name}\n  url: {url}\n  last-modified: {last_modified}\n  bytes: {target.stat().st_size}")
    (RAW / "MANIFEST.txt").write_text("\n".join(lines) + "\n", encoding="utf-8")
    print("Done. See data/raw/MANIFEST.txt")


if __name__ == "__main__":
    main()
