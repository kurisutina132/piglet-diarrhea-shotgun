// Adapter/quality trimming. Pairs are kept or dropped together (no singleton output).
process FASTP {
    tag "${meta.id}"
    label 'process_medium'
    conda "${params.envs_dir}/fastp.yml"
    container params.container_fastp

    publishDir "${params.outdir}/qc/fastp", mode: 'copy', pattern: '*.{json,html}'

    input:
    tuple val(meta), path(r1), path(r2)

    output:
    tuple val(meta), path("${meta.id}.fastp_1.fastq.gz"), path("${meta.id}.fastp_2.fastq.gz"), emit: reads
    tuple val(meta.id), path("${meta.id}.post_fastp.count"),                                   emit: counts
    path "${meta.id}.fastp.{json,html}",                                                       emit: reports
    path "versions.tsv",                                                                       emit: versions

    script:
    def id = meta.id
    """
    fastp \\
        -i ${r1} -I ${r2} \\
        -o ${id}.fastp_1.fastq.gz -O ${id}.fastp_2.fastq.gz \\
        --cut_front --cut_tail \\
        --cut_window_size ${params.fastp_cut_window} \\
        --cut_mean_quality ${params.fastp_cut_quality} \\
        --qualified_quality_phred ${params.fastp_qualified_quality} \\
        --unqualified_percent_limit ${params.fastp_unqualified_percent} \\
        --length_required ${params.fastp_min_length} \\
        --detect_adapter_for_pe \\
        --thread ${task.cpus} \\
        --json ${id}.fastp.json --html ${id}.fastp.html

    # Reads after filtering come from the first "after_filtering" block of the JSON summary.
    reads=\$(tr -d '[:space:]' < ${id}.fastp.json | grep -o '"after_filtering":{"total_reads":[0-9]*' | head -1 | grep -o '[0-9]*\$')
    [ -n "\$reads" ] || { echo "could not parse fastp JSON" >&2; exit 1; }
    printf '%s\\tpost_fastp\\t%s\\n' ${id} \$(( reads / 2 )) > ${id}.post_fastp.count
    printf 'FASTP\\tfastp\\t%s\\n' "\$(fastp --version 2>&1 | grep -o '[0-9][0-9.]*')" > versions.tsv
    """

    stub:
    def id = meta.id
    """
    for m in 1 2; do echo "@r\${m}" | gzip > ${id}.fastp_\${m}.fastq.gz; done
    echo '{}' > ${id}.fastp.json
    echo '<html></html>' > ${id}.fastp.html
    printf '%s\\tpost_fastp\\t1\\n' ${id} > ${id}.post_fastp.count
    printf 'FASTP\\tfastp\\tstub\\n' > versions.tsv
    """
}
