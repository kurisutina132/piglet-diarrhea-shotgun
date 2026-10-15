// Demo / CI only. Never used for the main results (see README).
// The same seed on both mates keeps the pairs in sync.
process SUBSAMPLE {
    tag "${meta.id}"
    label 'process_low'
    conda "${params.envs_dir}/seqtk.yml"
    container params.container_seqtk

    input:
    tuple val(meta), path(r1), path(r2)

    output:
    tuple val(meta), path("${meta.id}.sub_1.fastq.gz"), path("${meta.id}.sub_2.fastq.gz"), emit: reads
    tuple val(meta.id), path("${meta.id}.post_subsample.count"),                           emit: counts
    path "versions.tsv",                                                                   emit: versions

    script:
    def id = meta.id
    """
    seqtk sample -s ${params.seed} ${r1} ${params.subsample} | gzip > ${id}.sub_1.fastq.gz
    seqtk sample -s ${params.seed} ${r2} ${params.subsample} | gzip > ${id}.sub_2.fastq.gz

    n=\$(( \$(gzip -dc ${id}.sub_1.fastq.gz | wc -l) / 4 ))
    printf '%s\\tpost_subsample\\t%s\\n' ${id} "\$n" > ${id}.post_subsample.count
    printf 'SUBSAMPLE\\tseqtk\\t%s\\n' "\$(seqtk 2>&1 | sed -n 's/^Version: *//p')" > versions.tsv
    """

    stub:
    def id = meta.id
    """
    for m in 1 2; do echo "@r\${m}" | gzip > ${id}.sub_\${m}.fastq.gz; done
    printf '%s\\tpost_subsample\\t1\\n' ${id} > ${id}.post_subsample.count
    printf 'SUBSAMPLE\\tseqtk\\tstub\\n' > versions.tsv
    """
}
