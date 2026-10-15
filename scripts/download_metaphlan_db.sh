#!/usr/bin/env bash
# Download the pinned MetaPhlAn database (index mpa_vJan25_CHOCOPhlAnSGB_202503).
#
# Usage:  scripts/download_metaphlan_db.sh <target_dir>
# Needs `metaphlan` on PATH (activate the env built from envs/metaphlan.yml).
# Idempotent: exits 0 without downloading if the index is already complete.
# The database is large (tens of GB unpacked); it is never committed to git.
set -euo pipefail

INDEX="mpa_vJan25_CHOCOPhlAnSGB_202503"

if [[ $# -ne 1 ]]; then
    echo "usage: $0 <target_dir>" >&2
    exit 2
fi
db_dir="$1"

command -v metaphlan >/dev/null 2>&1 || {
    echo "error: 'metaphlan' not found on PATH; activate the envs/metaphlan.yml environment" >&2
    exit 1
}

mkdir -p "$db_dir"

if [[ -s "$db_dir/$INDEX.pkl" ]] && compgen -G "$db_dir/$INDEX.1.bt2*" >/dev/null; then
    echo "MetaPhlAn index $INDEX already present in $db_dir; nothing to do."
    exit 0
fi

echo "Installing MetaPhlAn index $INDEX into $db_dir ..."
metaphlan --install --index "$INDEX" --db_dir "$db_dir"

if [[ ! -s "$db_dir/$INDEX.pkl" ]] || ! compgen -G "$db_dir/$INDEX.1.bt2*" >/dev/null; then
    echo "error: installation finished but the index files are incomplete in $db_dir" >&2
    exit 1
fi
echo "Done. Use: --metaphlan_index $INDEX --metaphlan_db $db_dir"
