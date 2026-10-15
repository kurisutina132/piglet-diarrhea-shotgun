# Verification of the group labels

## Purpose

The SRA and BioSample records of PRJNA979345 do not carry the clinical status of the piglets. The labels in
`data/metadata.tsv` (`healthy` / `diarrhea`) come only from the column headers (`Control` / `Diarrhoea`) of the
supplementary Tables S1-S3 of the source paper (DOI 10.3390/ani13142303, PMC10376196). Because every downstream
comparison depends on them, they are checked independently here, in three ways: against the numbers the paper
reports, against each other, and (once the full run is finished) against the reads themselves.

Everything is reproduced by one script:

```bash
python3 analysis/verify_group_labels.py                                              # Checks 1 and 2
python3 analysis/verify_group_labels.py --metaphlan results/taxonomy/metaphlan_species.tsv   # adds Check 3
```

The script downloads the supplementary archive from Europe PMC
(`https://www.ebi.ac.uk/europepmc/webservices/rest/PMC10376196/supplementaryFiles`) into `analysis/.cache/`
(git-ignored), records its SHA-256, and writes a machine-readable summary to
`data/label_verification/checks.tsv`. It exits non-zero if Check 1 or Check 2 fails. The only dependency is
`openpyxl` (`envs/analysis-py.yml`).

Supplement archive SHA-256 (as downloaded on 2026-10-15):
`11a131cfe9c8d4c33e115996a79b9800f74da2d9167e04f61387842c4123317f`

## Check 1: the headers reproduce the paper

Table S1 holds Kraken2 read counts per lineage (rows) and sample (columns); header row 1 gives the group
(`Control` / `Diarrhoea`, spanning its columns) and header row 2 the sample ID. For each sample the counts were
converted to relative abundance (%) of the column total, then averaged within each group. A phylum is matched by
`|p__X|` in the lineage string, a species by the last lineage field. These are compared with the group means that
the paper quotes in its Results text. Tolerance: 0.015 percentage points (the paper rounds to two decimals; the
Bacteroidetes value for diarrhoea is 27.94 here against 27.95 in the paper, a rounding difference).

| Rank | Taxon | Group | Paper (%) | Reproduced (%) | Match | Value if labels were swapped |
| --- | --- | --- | ---: | ---: | :---: | ---: |
| phylum | Firmicutes | Control | 36.52 | 36.52 | yes | 34.15 |
| phylum | Firmicutes | Diarrhoea | 34.15 | 34.15 | yes | 36.52 |
| phylum | Bacteroidetes | Control | 29.62 | 29.62 | yes | 27.94 |
| phylum | Bacteroidetes | Diarrhoea | 27.95 | 27.94 | yes | 29.62 |
| phylum | Proteobacteria | Control | 29.01 | 29.01 | yes | 27.68 |
| phylum | Proteobacteria | Diarrhoea | 27.68 | 27.68 | yes | 29.01 |
| phylum | Actinobacteria | Control | 2.98 | 2.98 | yes | 3.52 |
| phylum | Actinobacteria | Diarrhoea | 3.52 | 3.52 | yes | 2.98 |
| phylum | Fusobacteria | Control | 0.46 | 0.46 | yes | 5.73 |
| phylum | Fusobacteria | Diarrhoea | 5.73 | 5.73 | yes | 0.46 |
| species | Bacteroides fragilis | Control | 16.43 | 16.43 | yes | 8.84 |
| species | Bacteroides fragilis | Diarrhoea | 8.84 | 8.84 | yes | 16.43 |
| species | Escherichia coli | Control | 14.03 | 14.03 | yes | 8.68 |
| species | Escherichia coli | Diarrhoea | 8.68 | 8.68 | yes | 14.03 |
| species | Clostridium perfringens | Control | 13.07 | 13.07 | yes | 1.33 |
| species | Clostridium perfringens | Diarrhoea | 1.33 | 1.33 | yes | 13.07 |
| species | Enterococcus faecium | Control | 6.71 | 6.71 | yes | 0.14 |
| species | Fusobacterium mortiferum | Diarrhoea | 5.19 | 5.19 | yes | 0.09 |
| species | Prevotella copri | Diarrhoea | 1.80 | 1.80 | yes | 0.80 |

Result: 19 of 19 values match with the labels as written in the headers; 0 of 19 would match if the two labels
were swapped. The headers therefore reproduce the paper's own group assignment. This shows that the table
headers are consistent with the paper's text, not that the paper's assignment is correct (see Check 3).

## Check 2: header groups agree across tables and with the samplesheet

For every `sample_id` in `data/metadata.tsv`, the group in the header of Table S1, Table S2 and Table S3 was
compared with `group_label_original`, and `group_label_original` with the normalised `group`
(`Control` -> `healthy`, `Diarrhoea` -> `diarrhea`).

Result: all 16 samples are present in all three tables and the three tables agree with `metadata.tsv` on every
label. No discrepancies.

## Check 3: sample identity from the reads

Pending the full run. When `results/taxonomy/metaphlan_species.tsv` exists, the script will map each MetaPhlAn
column (a run accession) to its `sample_id`, aggregate genus-level and family-level relative abundance from both
MetaPhlAn and Table S1 (Kraken2), compute the Spearman correlation of every MetaPhlAn profile against every
Table S1 sample over the union of taxa, and report for each run the best-matching Table S1 sample and whether
it is the run's own `sample_id` (the diagonal of the matrix). The matrices are written to
`data/label_verification/identity_matrix_<level>.tsv`.

Two caveats are built into the design. MetaPhlAn (marker-based, its own taxonomy) and Kraken2 (k-mer based, NCBI
taxonomy) use different naming for some taxa (for example Prevotella versus Segatella, Leyella or
Xylanibacter), which is why family level is reported next to genus level. Kraken2 also reports thousands of
near-zero taxa that carry no identity signal, so matrices are written both for the full union of taxa and for taxa
at or above a 0.5 % abundance floor (`identity_matrix_<level>_min0.5.tsv`). A smoke test on the two-sample pilot
exercised the code path only and is not evidence either way.

A diagonal result would confirm that each run accession is attached to the right sample number, which is what
links the SRA run to the group label. It would not by itself confirm the clinical status.

## Qualitative concordance with the pilot

The paper itself reports the healthy (`Control`) group as rich in *E. coli* and *C. perfringens* and with lower
alpha diversity than the diarrhoea group. The two-sample pilot run of this pipeline (one sample per group) is
consistent with that description: the healthy sample SRR34060196 (sample 147) is dominated by *E. coli*
(41.5 % relative abundance, 14 species detected), whereas the diarrhoea sample SRR34060199 (sample 106) is
Prevotella-rich (*Prevotella pectinovora* 28.9 %, *Leyella stercorea* 16.6 %) with more species detected
(57). One sample per group cannot support a statistical statement; this is a plausibility check only, to be
replaced by the full 8-versus-8 comparison.
