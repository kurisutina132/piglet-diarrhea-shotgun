# Piglet diarrhoea shotgun metagenomics: a reproducible reanalysis

A Nextflow pipeline that reanalyses the public shotgun metagenomes of PRJNA979345 (faecal samples from
8 healthy and 8 diarrhoeic piglets): download from SRA, quality control, removal of host reads (pig and human),
and taxonomic profiling with MetaPhlAn 4.

Author: Cristy Medina Armijo. License: MIT.

> Status: working, reproducible pipeline with a validated two-sample demo. The full 16-sample reanalysis is fully specified and runnable (see Quickstart); it was not executed in this environment. This repository is published as a pipeline-engineering reference, not a results report.

## Dataset

- BioProject: PRJNA979345, 16 faecal samples, DNBSEQ-G50 paired-end 100 bp.
- Paper: DOI 10.3390/ani13142303 (PMC10376196).
- Group assignment: the SRA records do not carry clinical status. Groups (`Control` = healthy,
  `Diarrhoea` = diarrhea) were taken from the column headers of the paper's supplementary Tables S1-S3, which agree
  with each other. See [data/README.md](data/README.md) for the provenance of `data/metadata.tsv`, the samplesheet.

## Pipeline

```
VERIFY_REFERENCES (md5 of host indices, gates host removal)
SRA -> FETCH_SRA -> [SUBSAMPLE, demo only] -> FASTP -> HOST_REMOVAL (Sscrofa11.1) -> HOST_REMOVAL (GRCh38)
    -> READ_COUNTS (raw / post-subsample / post-fastp / post-pig / post-human)
    -> METAPHLAN -> PUBLISH_PROFILES (header paths stripped) -> merged and species-only tables
```

Pairs are kept after host removal only if both mates are unmapped (SAM flag 12). Software versions of every run
are written to `results/pipeline_info/versions.tsv`.

## Quickstart

Requirements: Nextflow >= 24.04, Java 17+, micromamba (conda profile) or Docker (docker profile), about 20 cores
and 39 GB RAM for the real run (MetaPhlAn needs 20+ GB).

1. Environments. Pinned files are in `envs/`. On WSL2 the solver needs the glibc override:

   ```bash
   export CONDA_OVERRIDE_GLIBC=2.35
   export MAMBA_NO_RC=true MAMBA_CHANNEL_PRIORITY=strict   # same as --no-rc --strict-channel-priority
   # Optional, to build one environment by hand:
   micromamba create -n fastp --no-rc --strict-channel-priority -c conda-forge -c bioconda -f envs/fastp.yml
   ```

   The `conda` profile uses micromamba (`conda.useMicromamba = true`) and builds the environments on first use.

2. Databases and indices (stored outside the repository):

   ```bash
   scripts/download_metaphlan_db.sh /data/dbs/metaphlan        # needs the metaphlan env on PATH
   scripts/build_grch38_index.sh    /data/dbs/grch38 16        # needs the host-removal env on PATH
   scripts/build_sscrofa_index.sh   /data/dbs/sscrofa11.1 16
   ```

   Both index builders download the genomic FASTA from NCBI, enforce its provider-published md5 (the build
   fails on a mismatch), build under a temporary prefix and move the six index files into place only after
   `bowtie2-build` succeeds, then write a `<prefix>.complete` marker. Each script prints the exact `--...`
   value to pass to the pipeline. If you already have these databases,
   point the parameters at them instead; machine-specific paths go in `conf/local.config`
   (copy of `conf/local.config.example`, git-ignored).

3. Run. The parameters below have no default on purpose and the pipeline stops if one is missing:

   ```bash
   nextflow run workflow/main.nf -profile conda \
       --outdir results \
       --sscrofa_index /data/dbs/sscrofa11.1/sscrofa11.1 \
       --human_index   /data/dbs/grch38/grch38 \
       --metaphlan_index mpa_vJan25_CHOCOPhlAnSGB_202503 \
       --metaphlan_db  /data/dbs/metaphlan
   ```

   - Two-sample check (one healthy, one diarrhoea): add the `test` profile (`-profile test,conda`), or select runs
     with `--runs SRR34060196,SRR34060199`.
   - Wiring check without tools or data: add `-stub` (needs dummy index and database paths that exist).
   - `-profile docker` uses pinned `quay.io/biocontainers` images instead of conda.

### `--subsample N` (demo only)

`--subsample N` keeps N read pairs per sample (`seqtk sample`, seed `--seed`, default 42, same seed on both
mates). It exists to make demo runs fast. It is not used for the main results,
which are produced from the full data.

## Sealed references

`references/checksums.tsv` pins the md5 of each host reference FASTA (provider-published, from NCBI) and of
each of the six bowtie2 index files of the indices used for the reported results (computed locally). Before host
removal, the `VERIFY_REFERENCES` step checks the index files of both hosts against this table and stops the
run with the list of offending files if anything is missing or differs. The result is written to
`results/pipeline_info/reference_checks.tsv`. Disable with `--verify_references false` (not recommended); a
different table can be given with `--references_checksums`.

The binding seal is the FASTA md5. Rebuilding an index with the scripts may give different index-file md5s
(the GRCh38 index in the table was built with an unrecorded bowtie2 version), in which case
`VERIFY_REFERENCES` will report a mismatch for the rebuilt index; that is expected and means the table must be
updated deliberately, with the new sums recorded as `computed-locally` and the date, never silently.

## Results

This repository publishes the pipeline, not a results report. The workflow runs end-to-end on a two-sample demo (`-profile test`); the full 16-sample reanalysis is specified in the Quickstart and left as the documented next step.

## Deviations from the paper

| Item | Paper | This reanalysis | Reason |
| --- | --- | --- | --- |
| Host reference | `GCA_017957985.1` (Meishan assembly) | `Sscrofa11.1`, `GCF_000003025.6` | Standard, widely used pig reference with a checksummed NCBI release; the paper's choice is documented, not replicated |
| Taxonomic profiler | Kraken2 | MetaPhlAn 4 (`mpa_vJan25_CHOCOPhlAnSGB_202503`) | Marker-based profiling with a pinned, versioned database |

Other choices not specified in the paper (fastp minimum length, aligner preset) are parameters in
`workflow/nextflow.config` and are listed in the methods of the report.

## Repository layout

```
workflow/   Nextflow pipeline (main.nf, nextflow.config, modules/)
envs/       pinned conda environments, one per step
scripts/    database download and index build scripts
references/ checksums.tsv: pinned md5 sums of the host references and indices
analysis/   verify_group_labels.py: checks of the group labels against the paper
conf/       local.config.example (machine-specific paths, not committed once copied)
data/       samplesheet (metadata.tsv) and its provenance
results/    figures and small summary tables only
```
