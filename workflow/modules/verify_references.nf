// Check the six bowtie2 index files of each host reference against the md5 sums
// pinned in references/checksums.tsv, before any host-removal task starts.
//
// The process only reads the indices; main.nf passes the SAME index-directory
// values on to HOST_REMOVAL after this process has finished, so the HOST_REMOVAL
// task hashes (script and inputs) do not change.
// Disabled with --verify_references false (not recommended).
process VERIFY_REFERENCES {
    label 'process_low'

    publishDir "${params.outdir}/pipeline_info", mode: 'copy', pattern: 'reference_checks.tsv'

    input:
    path checksums
    path pig_dir, stageAs: 'pig_index'
    val  pig_name
    path human_dir, stageAs: 'human_index'
    val  human_name

    output:
    path "reference_checks.tsv", emit: report

    script:
    """
    printf 'reference\\tfile\\texpected_md5\\tobserved_md5\\tstatus\\n' > reference_checks.tsv
    rc=0
    verify_checksums.sh ${checksums} sscrofa11.1 ${pig_dir} ${pig_name}   >> reference_checks.tsv || rc=1
    verify_checksums.sh ${checksums} grch38      ${human_dir} ${human_name} >> reference_checks.tsv || rc=1
    if [ "\$rc" -ne 0 ]; then
        echo "error: host reference verification FAILED. Offending files:" >&2
        awk -F'\\t' 'NR > 1 && \$5 != "OK" {printf "  %s  %s  expected=%s observed=%s  [%s]\\n", \$1, \$2, \$3, \$4, \$5}' reference_checks.tsv >&2
        echo "Rebuild the index with scripts/build_*_index.sh, or see README (Sealed references)." >&2
        exit 1
    fi
    """

    stub:
    """
    printf 'reference\\tfile\\texpected_md5\\tobserved_md5\\tstatus\\n' > reference_checks.tsv
    printf 'stub\\tstub\\tNA\\tNA\\tSKIPPED_STUB\\n' >> reference_checks.tsv
    """
}
