# Data provenance

`metadata.tsv` is the single source of truth for run accessions and group labels.
The pipeline reads it as its samplesheet; no other file assigns groups.

Source study: BioProject PRJNA979345; paper DOI 10.3390/ani13142303 (PMC10376196).
16 faecal samples from piglets: 8 healthy (control) and 8 with diarrhoea, sequenced on DNBSEQ-G50 (paired-end, 100 bp).

## Columns

| Column | Content |
| --- | --- |
| `run_accession` | SRA run (SRR), used to download the reads |
| `sample_id` | Animal/sample number used in the paper's supplementary tables |
| `biosample` | NCBI BioSample accession |
| `experiment` | SRA experiment accession |
| `group` | Normalised label used by the pipeline: `healthy` or `diarrhea` |
| `group_label_original` | Label exactly as written in the supplementary table headers: `Control` or `Diarrhoea` |
| `group_label_source` | Where the label was taken from (`PMC10376196_TablesS1-S3`) |
| `library_layout` | `PAIRED` (from SRA run info) |
| `instrument_model` | Sequencer model (from SRA run info) |
| `read_pairs` | Spots (read pairs) per run as reported by SRA |
| `bases` | Total bases per run as reported by SRA |
| `collection_date` | Collection date, as deposited in the BioSample record |

## How the groups were assigned

The SRA/BioSample records do not carry the clinical status. The group of each sample was taken from the
headers of the paper's supplementary Tables S1, S2 and S3, where each sample column is labelled `Control` or
`Diarrhoea`. The three tables were compared sample by sample and agree on every label. `Control` was mapped
to `healthy` and `Diarrhoea` to `diarrhea`; the original wording is kept in `group_label_original`.

## Other notes

- Run accession, biosample, experiment, layout, instrument, read pairs and bases come from the SRA run info
  of PRJNA979345.
- `collection_date` is reproduced as deposited in BioSample. It was not checked against the paper and should
  not be used for inference without that check.
- Run accessions are not in sample-number order (for example, sample 111 is SRR34060210); always join on
  `run_accession`.
