#!/usr/bin/env bash
# Download the prebuilt GRCh38 no-alt analysis-set bowtie2 index (Langmead lab).
#
# Usage:  scripts/download_grch38_index.sh <target_dir>
# Optional: EXPECTED_SHA256=<hex> to enforce a checksum.
#
# The provider does not publish a checksum for this archive (the S3 ETag of a
# multipart upload is not an MD5 of the content). The script therefore always
# computes the SHA-256 of the download, stores it next to the archive and prints
# it, so the value can be recorded and pinned via EXPECTED_SHA256 on later runs.
# Idempotent: skips download/extraction when the index is already in place.
set -euo pipefail

URL="https://genome-idx.s3.amazonaws.com/bt/GRCh38_noalt_as.zip"
ZIP="GRCh38_noalt_as.zip"
EXPECTED_SHA256="${EXPECTED_SHA256:-}"

if [[ $# -ne 1 ]]; then
    echo "usage: $0 <target_dir>" >&2
    exit 2
fi
dest="$1"
mkdir -p "$dest"

find_prefix() {
    local f
    f="$(find "$dest" -maxdepth 3 -name '*.rev.2.bt2' -print -quit)"
    [[ -n "$f" ]] && echo "${f%.rev.2.bt2}"
    return 0
}

prefix="$(find_prefix)"
if [[ -n "$prefix" ]]; then
    echo "GRCh38 index already present. Use: --human_index $prefix"
    exit 0
fi

command -v curl >/dev/null 2>&1 || { echo "error: curl not found" >&2; exit 1; }
command -v unzip >/dev/null 2>&1 || { echo "error: unzip not found" >&2; exit 1; }

if [[ ! -s "$dest/$ZIP" ]]; then
    echo "Downloading $URL ..."
    curl -fL --retry 3 -C - -o "$dest/$ZIP.part" "$URL"
    mv "$dest/$ZIP.part" "$dest/$ZIP"
fi

sha="$(sha256sum "$dest/$ZIP" | cut -d' ' -f1)"
echo "$sha  $ZIP" > "$dest/$ZIP.sha256"
echo "SHA-256 of $ZIP: $sha"
if [[ -n "$EXPECTED_SHA256" && "$sha" != "$EXPECTED_SHA256" ]]; then
    echo "error: checksum mismatch (expected $EXPECTED_SHA256)" >&2
    exit 1
fi

unzip -n -q "$dest/$ZIP" -d "$dest"
prefix="$(find_prefix)"
if [[ -z "$prefix" ]]; then
    echo "error: no bowtie2 index (*.rev.2.bt2) found after extraction in $dest" >&2
    exit 1
fi
echo "Done. Use: --human_index $prefix"
