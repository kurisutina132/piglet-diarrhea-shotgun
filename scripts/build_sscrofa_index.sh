#!/usr/bin/env bash
# Build the bowtie2 index for the pig reference Sscrofa11.1 (GCF_000003025.6).
#
# Usage:  scripts/build_sscrofa_index.sh <target_dir> [threads]
# Needs `bowtie2-build` and `curl` on PATH (envs/host-removal.yml).
# The genomic FASTA is verified against the md5 published by NCBI
# (md5checksums.txt in the same FTP directory) and against the pinned value below.
# Idempotent: skips download and build when their outputs already exist.
set -euo pipefail

BASE="https://ftp.ncbi.nlm.nih.gov/genomes/all/GCF/000/003/025/GCF_000003025.6_Sscrofa11.1"
FASTA="GCF_000003025.6_Sscrofa11.1_genomic.fna.gz"
EXPECTED_MD5="7e8201799720ce3e2ba63cc83f0326aa"
PREFIX_NAME="Sscrofa11.1"

if [[ $# -lt 1 || $# -gt 2 ]]; then
    echo "usage: $0 <target_dir> [threads]" >&2
    exit 2
fi
dest="${1:?target_dir required}"
threads="${2:-8}"
mkdir -p "$dest"

for tool in curl bowtie2-build md5sum; do
    command -v "$tool" >/dev/null 2>&1 || { echo "error: '$tool' not found on PATH" >&2; exit 1; }
done

if compgen -G "$dest/$PREFIX_NAME.rev.2.bt2*" >/dev/null; then
    echo "Index already present. Use: --sscrofa_index $dest/$PREFIX_NAME"
    exit 0
fi

if [[ ! -s "$dest/$FASTA" ]]; then
    echo "Downloading $FASTA ..."
    curl -fL --retry 3 -C - -o "$dest/$FASTA.part" "$BASE/$FASTA"
    mv "$dest/$FASTA.part" "$dest/$FASTA"
fi

# Cross-check the pinned md5 against what NCBI currently publishes, then the file.
published="$(curl -fsL --retry 3 "$BASE/md5checksums.txt" | awk -v f="./$FASTA" '$2 == f {print $1}')"
if [[ "$published" != "$EXPECTED_MD5" ]]; then
    echo "error: NCBI md5 ($published) differs from the pinned value ($EXPECTED_MD5)" >&2
    exit 1
fi
actual="$(md5sum "$dest/$FASTA" | cut -d' ' -f1)"
if [[ "$actual" != "$EXPECTED_MD5" ]]; then
    echo "error: md5 mismatch for $FASTA: got $actual, expected $EXPECTED_MD5; delete the file and rerun" >&2
    exit 1
fi
echo "md5 OK: $actual"

bowtie2-build --threads "$threads" "$dest/$FASTA" "$dest/$PREFIX_NAME"
echo "Done. Use: --sscrofa_index $dest/$PREFIX_NAME"
