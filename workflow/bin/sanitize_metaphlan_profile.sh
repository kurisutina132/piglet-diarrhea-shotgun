#!/usr/bin/env bash
# Remove machine-specific absolute paths from the header of a MetaPhlAn profile.
#
# Usage: sanitize_metaphlan_profile.sh <in.profile.txt> > <out.profile.txt>
#
# MetaPhlAn writes the full command line (including the absolute path of the
# metaphlan binary and of its inputs) in a '#' header line. In every '#' line,
# each absolute path (a token starting with '/', also after '=', ',' or a quote)
# is reduced to its basename; the binary therefore becomes `metaphlan`.
# Data lines are copied unchanged.
set -euo pipefail
[[ $# -eq 1 && -r "$1" ]] || { echo "usage: $0 <profile.txt>" >&2; exit 2; }

sed -E "/^#/ s#(^|[#[:space:]\"'=,])(/[^[:space:]\"',=]*/)([^[:space:]\"',/]*)#\1\3#g" "$1"
