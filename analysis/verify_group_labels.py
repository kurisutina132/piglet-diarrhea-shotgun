#!/usr/bin/env python3
"""Verify the group labels (Control / Diarrhoea) of PRJNA979345 used in data/metadata.tsv.

The SRA records carry no clinical status, so the labels come only from the column
headers of the supplementary Tables S1-S3 of the paper (DOI 10.3390/ani13142303,
PMC10376196). This script checks them independently.

  Check 1  Headers reproduce the paper: per-group means of per-sample relative abundance
           computed from Table S1 (Kraken2 counts) match the values the paper reports in its
           Results text. A swapped-label alternative is reported to show it would not match.
  Check 2  The header groups of Tables S1, S2 and S3 agree with each other and with
           data/metadata.tsv for every sample_id.
  Check 3  (optional, --metaphlan) Sample identity: each MetaPhlAn profile is correlated
           (Spearman, genus and family level, full union of taxa and a 0.5 % floor) with every Table S1 sample; the best match
           should be the sample's own sample_id (diagonal of the matrix).

Exit status: 0 when Checks 1 and 2 pass, 1 otherwise, 2 on usage or input errors.
Check 3 is informative and does not change the exit status.

Dependency: openpyxl (envs/analysis-py.yml). Network: Europe PMC (cached after first download).
"""
import argparse
import csv
import hashlib
import io
import sys
import urllib.request
import zipfile
from collections import defaultdict
from pathlib import Path

import openpyxl

PMCID = "PMC10376196"
SUPP_URL = f"https://www.ebi.ac.uk/europepmc/webservices/rest/{PMCID}/supplementaryFiles"
INNER_ZIP = "animals-13-02303-s001.zip"
GROUP_MAP = {"Control": "healthy", "Diarrhoea": "diarrhea"}
TOL = 0.015  # percentage points; the paper rounds to two decimals (and Bacteroidetes/diarrhoea is 27.94 vs 27.95)

# (rank, taxon, paper value Control, paper value Diarrhoea); None = not reported for that group
PAPER_VALUES = [
    ("phylum", "Firmicutes", 36.52, 34.15),
    ("phylum", "Bacteroidetes", 29.62, 27.95),
    ("phylum", "Proteobacteria", 29.01, 27.68),
    ("phylum", "Actinobacteria", 2.98, 3.52),
    ("phylum", "Fusobacteria", 0.46, 5.73),
    ("species", "Bacteroides fragilis", 16.43, 8.84),
    ("species", "Escherichia coli", 14.03, 8.68),
    ("species", "Clostridium perfringens", 13.07, 1.33),
    ("species", "Enterococcus faecium", 6.71, None),
    ("species", "Fusobacterium mortiferum", None, 5.19),
    ("species", "Prevotella copri", None, 1.80),
]


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def fetch_supplement(cache_dir):
    cache_dir.mkdir(parents=True, exist_ok=True)
    target = cache_dir / f"{PMCID}_supplementary.zip"
    if not target.exists() or target.stat().st_size == 0:
        print(f"Downloading {SUPP_URL}", file=sys.stderr)
        req = urllib.request.Request(SUPP_URL, headers={"User-Agent": "piglet-diarrhea-shotgun/verify_group_labels"})
        with urllib.request.urlopen(req, timeout=120) as resp:
            data = resp.read()
        tmp = target.with_suffix(".part")
        tmp.write_bytes(data)
        tmp.replace(target)
    return target, sha256_file(target)


def load_tables(outer_zip):
    """Return {'S1': (groups, lineages, matrix), ...}; groups = {sample_id: label}."""
    with zipfile.ZipFile(outer_zip) as outer:
        inner = zipfile.ZipFile(io.BytesIO(outer.read(INNER_ZIP)))
    tables = {}
    for name in inner.namelist():
        key = next((k for k in ("TableS1", "TableS2", "TableS3") if k in name), None)
        if key is None:
            continue
        wb = openpyxl.load_workbook(io.BytesIO(inner.read(name)), read_only=True, data_only=True)
        rows = list(wb[wb.sheetnames[0]].iter_rows(values_only=True))
        header_groups, header_ids = rows[0], rows[1]
        groups, cols, current = {}, [], None
        for j in range(1, len(header_ids)):
            if header_groups[j] is not None:
                current = str(header_groups[j]).strip()
            if header_ids[j] is None:
                continue
            sid = str(header_ids[j]).strip()
            groups[sid] = current
            cols.append((j, sid))
        lineages, matrix = [], []
        for r in rows[2:]:
            if r[0] is None:
                continue
            lineages.append(str(r[0]).strip())
            matrix.append({sid: float(r[j] or 0) for j, sid in cols})
        tables[key[-2:]] = (groups, lineages, matrix)
    missing = {"S1", "S2", "S3"} - set(tables)
    if missing:
        raise SystemExit(f"error: tables not found in the supplement: {sorted(missing)}")
    return tables


def relative_abundance(matrix, sids):
    totals = {s: sum(row[s] for row in matrix) for s in sids}
    return [{s: (100.0 * row[s] / totals[s] if totals[s] else 0.0) for s in sids} for row in matrix]


def group_means(rel, lineages, groups, rank, taxon):
    if rank == "phylum":
        sel = [i for i, l in enumerate(lineages) if f"|p__{taxon}|" in l]
    else:
        sel = [i for i, l in enumerate(lineages) if l.split("|")[-1] == f"s__{taxon}"]
    out = {}
    for g in sorted(set(groups.values())):
        members = [s for s, gg in groups.items() if gg == g]
        per_sample = [sum(rel[i][s] for i in sel) for s in members]
        out[g] = sum(per_sample) / len(per_sample)
    return out


def check1(tables):
    groups, lineages, matrix = tables["S1"]
    sids = list(groups)
    rel = relative_abundance(matrix, sids)
    swap = {"Control": "Diarrhoea", "Diarrhoea": "Control"}
    rows, n_ok, n_cmp, n_swap_ok = [], 0, 0, 0
    for rank, taxon, pc, pd in PAPER_VALUES:
        m = group_means(rel, lineages, groups, rank, taxon)
        for label, paper in (("Control", pc), ("Diarrhoea", pd)):
            if paper is None:
                continue
            got = m[label]
            ok = abs(got - paper) <= TOL
            alt = m[swap[label]]
            alt_ok = abs(alt - paper) <= TOL
            n_cmp += 1
            n_ok += ok
            n_swap_ok += alt_ok
            rows.append((rank, taxon, label, paper, got, ok, alt, alt_ok))
    return rows, n_ok, n_cmp, n_swap_ok


def check2(tables, metadata):
    problems = []
    meta = {r["sample_id"]: r["group_label_original"] for r in metadata}
    meta_norm = {r["sample_id"]: r["group"] for r in metadata}
    for sid, label in meta.items():
        if GROUP_MAP.get(label) != meta_norm[sid]:
            problems.append(f"metadata: sample {sid}: group_label_original '{label}' != group '{meta_norm[sid]}'")
    for key in ("S1", "S2", "S3"):
        groups = tables[key][0]
        for sid in sorted(set(meta) | set(groups)):
            if sid not in groups:
                problems.append(f"{key}: sample {sid} missing from table header")
            elif sid not in meta:
                problems.append(f"{key}: sample {sid} not in metadata.tsv")
            elif groups[sid] != meta[sid]:
                problems.append(f"{key}: sample {sid} header '{groups[sid]}' != metadata '{meta[sid]}'")
    return problems


# ---------------------------------------------------------------- Check 3

def clade_field(lineage, prefix):
    for f in lineage.split("|"):
        if f.startswith(prefix):
            return f[len(prefix):].strip()
    return None


def kraken_level(tables, level):
    groups, lineages, matrix = tables["S1"]
    sids = list(groups)
    rel = relative_abundance(matrix, sids)
    prefix = {"genus": "g__", "family": "f__"}[level]
    out = {s: defaultdict(float) for s in sids}
    for lin, row in zip(lineages, rel):
        name = clade_field(lin, prefix)
        if name:
            for s in sids:
                out[s][name] += row[s]
    return out


def metaphlan_level(path, level, metadata):
    run_to_sid = {r["run_accession"]: r["sample_id"] for r in metadata}
    prefix = {"genus": "g__", "family": "f__"}[level]
    with open(path, newline="") as fh:
        lines = [l.rstrip("\n").split("\t") for l in fh if not l.startswith("#")]
    header, body = lines[0], lines[1:]
    runs = header[1:]
    unknown = [r for r in runs if r not in run_to_sid]
    if unknown:
        raise SystemExit(f"error: MetaPhlAn columns not in metadata.tsv: {unknown}")
    out = {r: defaultdict(float) for r in runs}
    for row in body:
        if not row or "s__" not in row[0] or "t__" in row[0]:
            continue
        name = clade_field(row[0], prefix)
        if name:
            for r, v in zip(runs, row[1:]):
                out[r][name] += float(v)
    return runs, run_to_sid, out


def ranks(values):
    order = sorted(range(len(values)), key=lambda i: values[i])
    r = [0.0] * len(values)
    i = 0
    while i < len(order):
        j = i
        while j + 1 < len(order) and values[order[j + 1]] == values[order[i]]:
            j += 1
        for k in range(i, j + 1):
            r[order[k]] = (i + j) / 2.0 + 1.0
        i = j + 1
    return r


def spearman(x, y):
    rx, ry = ranks(x), ranks(y)
    n = len(rx)
    mx, my = sum(rx) / n, sum(ry) / n
    sxx = sum((a - mx) ** 2 for a in rx)
    syy = sum((b - my) ** 2 for b in ry)
    sxy = sum((a - mx) * (b - my) for a, b in zip(rx, ry))
    return sxy / (sxx * syy) ** 0.5 if sxx and syy else float("nan")


def check3(tables, metaphlan_path, metadata, out_dir, thresholds):
    """Spearman of every MetaPhlAn run against every Table S1 sample, per level and abundance floor.

    A floor t (percent) keeps the taxa with relative abundance >= t in at least one profile;
    t = 0 is the full union of taxa. Kraken2 reports thousands of near-zero taxa that carry
    no identity signal, so the floors are reported side by side.
    """
    results = []
    for level, thr in [(l, t) for l in ("genus", "family") for t in thresholds]:
        kr = kraken_level(tables, level)
        runs, run_to_sid, mp = metaphlan_level(metaphlan_path, level, metadata)
        ksids = list(kr)
        taxa = sorted({t for d in list(kr.values()) + list(mp.values()) for t, v in d.items() if v >= thr and (v > 0 or thr == 0)})
        tag = level if thr == 0 else f"{level}_min{thr:g}"
        kvec = {s: [kr[s].get(t, 0.0) for t in taxa] for s in ksids}
        lines = ["run_accession\texpected_sample_id\t" + "\t".join(ksids)]
        best_rows = []
        for r in runs:
            mvec = [mp[r].get(t, 0.0) for t in taxa]
            rho = {s: spearman(mvec, kvec[s]) for s in ksids}
            lines.append("\t".join([r, run_to_sid[r]] + [f"{rho[s]:.4f}" for s in ksids]))
            best = max(ksids, key=lambda s: rho[s])
            best_rows.append((r, run_to_sid[r], best, rho[best], rho[run_to_sid[r]]))
        out_dir.mkdir(parents=True, exist_ok=True)
        (out_dir / f"identity_matrix_{tag}.tsv").write_text("\n".join(lines) + "\n")
        results.append((tag, len(taxa), best_rows))
    return results


# ---------------------------------------------------------------- main

def main():
    here = Path(__file__).resolve().parent
    repo = here.parent
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--metadata", type=Path, default=repo / "data" / "metadata.tsv")
    ap.add_argument("--cache-dir", type=Path, default=repo / "analysis" / ".cache")
    ap.add_argument("--out-dir", type=Path, default=repo / "data" / "label_verification")
    ap.add_argument("--min-abundance", default="0,0.5",
                    help="comma-separated abundance floors (percent) for Check 3; 0 = full union of taxa")
    ap.add_argument("--metaphlan", type=Path, default=None,
                    help="merged MetaPhlAn species table (enables Check 3 when the file exists)")
    args = ap.parse_args()

    with open(args.metadata, newline="") as fh:
        metadata = list(csv.DictReader(fh, delimiter="\t"))

    zip_path, sha = fetch_supplement(args.cache_dir)
    print(f"Supplement: {SUPP_URL}\n  sha256 {sha}")
    tables = load_tables(zip_path)
    checks = [("supplement", "outer_zip_sha256", "recorded", sha, "INFO", SUPP_URL)]

    # Check 1
    rows, n_ok, n_cmp, n_swap_ok = check1(tables)
    print("\nCheck 1: per-group mean relative abundance (%%), Table S1 vs paper (tolerance %.3f)" % TOL)
    print(f"{'rank':8} {'taxon':26} {'group':10} {'paper':>7} {'repro':>7} {'ok':>4} | {'swapped':>7} {'ok':>4}")
    for rank, taxon, label, paper, got, ok, alt, alt_ok in rows:
        print(f"{rank:8} {taxon:26} {label:10} {paper:7.2f} {got:7.2f} {'yes' if ok else 'NO':>4} | {alt:7.2f} {'yes' if alt_ok else 'no':>4}")
        checks.append(("check1", f"{rank}:{taxon}:{label}", f"{paper:.2f}", f"{got:.2f}", "PASS" if ok else "FAIL",
                       f"swapped-label value {alt:.2f} ({'matches' if alt_ok else 'does not match'})"))
    c1 = n_ok == n_cmp
    print(f"  as labelled: {n_ok}/{n_cmp} match; swapped labels: {n_swap_ok}/{n_cmp} match")
    checks.append(("check1", "summary", f"{n_cmp}/{n_cmp}", f"{n_ok}/{n_cmp}", "PASS" if c1 else "FAIL",
                   f"swapped labels would match {n_swap_ok}/{n_cmp}"))

    # Check 2
    problems = check2(tables, metadata)
    c2 = not problems
    print("\nCheck 2: header groups of S1, S2, S3 vs data/metadata.tsv")
    print("  " + ("all %d samples agree in all three tables and with metadata.tsv" % len(metadata) if c2 else "FAILED"))
    for p in problems:
        print("  - " + p)
    checks.append(("check2", "header_groups", "agree", "agree" if c2 else f"{len(problems)} problem(s)",
                   "PASS" if c2 else "FAIL", "; ".join(problems)))

    # Check 3
    if args.metaphlan and args.metaphlan.exists():
        print(f"\nCheck 3: sample identity (Spearman) using {args.metaphlan.name}")
        for level, ntaxa, best_rows in check3(tables, args.metaphlan, metadata, args.out_dir,
                                                         [float(x) for x in args.min_abundance.split(',')]):
            n_diag = sum(1 for r in best_rows if r[1] == r[2])
            print(f"  [{level}] {ntaxa} taxa; diagonal best match: {n_diag}/{len(best_rows)}")
            for run, own, best, rho_best, rho_own in best_rows:
                print(f"    {run} (sample {own}): best {best} rho={rho_best:.3f}; own rho={rho_own:.3f}"
                      f"  {'diagonal' if own == best else 'OFF-DIAGONAL'}")
                checks.append(("check3", f"{level}:{run}", own, best, "PASS" if own == best else "REVIEW",
                               f"rho_best={rho_best:.3f}; rho_own={rho_own:.3f}"))
            checks.append(("check3", f"{level}:summary", f"{len(best_rows)}/{len(best_rows)}",
                           f"{n_diag}/{len(best_rows)}", "INFO", "diagonal = best match is the run's own sample_id"))
    else:
        print("\nCheck 3: skipped (no --metaphlan table given or file not found)")
        checks.append(("check3", "identity", "-", "-", "SKIPPED", "no MetaPhlAn table"))

    args.out_dir.mkdir(parents=True, exist_ok=True)
    with open(args.out_dir / "checks.tsv", "w", newline="") as fh:
        w = csv.writer(fh, delimiter="\t", lineterminator="\n")
        w.writerow(["check", "item", "expected", "observed", "status", "detail"])
        w.writerows(checks)
    ok = c1 and c2
    print("\nResult: " + ("PASS (Checks 1 and 2)" if ok else "FAIL"))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
