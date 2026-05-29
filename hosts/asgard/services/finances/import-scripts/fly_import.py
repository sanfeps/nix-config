#!/usr/bin/env python3
"""fly-import: ingest external statements into Firefly III.

Subcommands:
  kutxabank PATH --account-id N   parse a Kutxabank PDF statement and POST
                                  transactions to Firefly III.
"""

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path

import pdfplumber
import requests


LINE_RE = re.compile(
    r"^\s*(\d{2}-\d{2}-\d{4})\s+(.+?)\s{2,}(-?[\d.]+,\d{2})\s+(-?[\d.]+,\d{2})\s*$"
)


def parse_amount(raw: str) -> float:
    return float(raw.replace(".", "").replace(",", "."))


def parse_date(raw: str) -> str:
    day, month, year = raw.split("-")
    return f"{year}-{month}-{day}"


def external_id(date: str, amount: float, concept: str) -> str:
    payload = f"{date}|{amount:.2f}|{concept}".encode()
    return hashlib.sha256(payload).hexdigest()[:32]


def extract_rows(pdf_path: Path):
    rows = []
    with pdfplumber.open(pdf_path) as pdf:
        for page in pdf.pages:
            text = page.extract_text(layout=True) or ""
            for line in text.splitlines():
                m = LINE_RE.match(line)
                if not m:
                    continue
                date_raw, concept, amount_raw, _balance = m.groups()
                rows.append(
                    {
                        "date": parse_date(date_raw),
                        "concept": concept.strip(),
                        "amount": parse_amount(amount_raw),
                    }
                )
    return rows


def post_transaction(session, base_url, account_id, row):
    amount = row["amount"]
    is_withdrawal = amount < 0
    tx_type = "withdrawal" if is_withdrawal else "deposit"
    body = {
        "error_if_duplicate_hash": True,
        "transactions": [
            {
                "type": tx_type,
                "date": row["date"],
                "amount": f"{abs(amount):.2f}",
                "description": row["concept"],
                "source_id": str(account_id) if is_withdrawal else None,
                "destination_id": str(account_id) if not is_withdrawal else None,
                "external_id": external_id(row["date"], amount, row["concept"]),
            }
        ],
    }
    body["transactions"][0] = {
        k: v for k, v in body["transactions"][0].items() if v is not None
    }
    r = session.post(f"{base_url}/api/v1/transactions", json=body)
    return r


def cmd_kutxabank(args):
    token = Path(args.token_file).read_text().strip()
    session = requests.Session()
    session.headers.update(
        {
            "Authorization": f"Bearer {token}",
            "Accept": "application/vnd.api+json",
            "Content-Type": "application/json",
        }
    )
    rows = extract_rows(Path(args.pdf))
    if not rows:
        print("no transactions parsed from PDF", file=sys.stderr)
        return 1
    created = duplicates = errors = 0
    for row in rows:
        r = post_transaction(session, args.firefly_url, args.account_id, row)
        if r.status_code == 200:
            created += 1
            print(f"+ {row['date']} {row['amount']:>10.2f}  {row['concept']}")
        elif r.status_code == 422:
            body = r.json() if r.content else {}
            msg = json.dumps(body.get("errors", body))
            if "Duplicate" in msg or "duplicate" in msg:
                duplicates += 1
                print(f"= {row['date']} {row['amount']:>10.2f}  {row['concept']}")
            else:
                errors += 1
                print(
                    f"! {row['date']} {row['amount']:>10.2f}  {row['concept']}: {msg}",
                    file=sys.stderr,
                )
        else:
            errors += 1
            print(
                f"! {row['date']} {row['amount']:>10.2f}  {row['concept']}: "
                f"HTTP {r.status_code} {r.text[:200]}",
                file=sys.stderr,
            )
    print(
        f"\ndone: {created} created, {duplicates} duplicates, {errors} errors",
        file=sys.stderr,
    )
    return 0 if errors == 0 else 2


def main():
    parser = argparse.ArgumentParser(prog="fly-import")
    sub = parser.add_subparsers(dest="cmd", required=True)

    k = sub.add_parser("kutxabank", help="ingest a Kutxabank PDF statement")
    k.add_argument("pdf", help="path to the Kutxabank PDF statement")
    k.add_argument(
        "--account-id",
        required=True,
        type=int,
        help="Firefly III asset account id to attach transactions to",
    )
    k.add_argument(
        "--firefly-url",
        default="http://localhost",
        help="Firefly III base URL (default: http://localhost)",
    )
    k.add_argument(
        "--token-file",
        default="/run/secrets/finances/firefly-access-token",
        help="path to a file containing the Firefly III personal access token",
    )
    k.set_defaults(func=cmd_kutxabank)

    args = parser.parse_args()
    sys.exit(args.func(args))


if __name__ == "__main__":
    main()
