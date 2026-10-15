#!/usr/bin/env bash
# Verify the 6 bowtie2 index files of one host reference against references/checksums.tsv.
#
# Usage: verify_checksums.sh <checksums.tsv> <reference> <index_dir> <index_prefix_name>
#   <reference>         value of the `reference` column (sscrofa11.1 or grch38)
#   <index_prefix_name> prefix of the files in <index_dir> (may differ from <reference>)
#
# Prints one TSV line per index file: reference, file, expected_md5, observed_md5, status.
# Exit status: 0 when every file matches, 1 when any file is missing, mismatched or
# has no expected checksum, 2 on usage errors.
set -euo pipefail

if [[ $# -ne 4 ]]; then
    echo "usage: $0 <checksums.tsv> <reference> <index_dir> <index_prefix_name>" >&2
    exit 2
fi
sums="$1"; ref="$2"; dir="$3"; prefix="$4"
suffixes=(1.bt2 2.bt2 3.bt2 4.bt2 rev.1.bt2 rev.2.bt2)
[[ -s "$sums" ]] || { echo "error: checksums file not found or empty: $sums" >&2; exit 2; }

bad=0
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Hash the six files in parallel (each is several hundred MB).
for s in "${suffixes[@]}"; do
    f="$dir/$prefix.$s"
    if [[ -r "$f" ]]; then
        ( md5sum "$f" | cut -d' ' -f1 > "$tmp/$s" ) &
    else
        echo "MISSING" > "$tmp/$s"
    fi
done
wait

for s in "${suffixes[@]}"; do
    expected="$(awk -F'\t' -v r="$ref" -v f="$ref.$s" '$1 == r && $2 == f {print $3}' "$sums")"
    observed="$(cat "$tmp/$s")"
    if [[ -z "$expected" ]]; then
        status="NO_EXPECTED_CHECKSUM"; bad=1
    elif [[ "$observed" == "MISSING" ]]; then
        status="MISSING_FILE"; bad=1
    elif [[ "$observed" != "$expected" ]]; then
        status="MISMATCH"; bad=1
    else
        status="OK"
    fi
    printf '%s\t%s.%s\t%s\t%s\t%s\n' "$ref" "$prefix" "$s" "${expected:-NA}" "$observed" "$status"
done
exit "$bad"
