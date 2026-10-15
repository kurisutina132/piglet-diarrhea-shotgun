// Download from SRA and convert to gzipped paired FASTQ.
process FETCH_SRA {
    tag "${meta.id}"
    label 'process_medium'
    conda "${params.envs_dir}/sra-tools.yml"
    container params.container_sra

    // Network downloads are the only retried step.
    errorStrategy { task.attempt <= params.fetch_retries ? 'retry' : 'terminate' }
    maxRetries params.fetch_retries

    input:
    val meta

    output:
    tuple val(meta), path("${meta.id}_1.fastq.gz"), path("${meta.id}_2.fastq.gz"), emit: reads
    tuple val(meta.id), path("${meta.id}.raw.count"),                              emit: counts
    path "versions.tsv",                                                           emit: versions

    script:
    def acc = meta.id
    """
    prefetch --max-size 100G --output-directory . ${acc}
    fasterq-dump --split-files --threads ${task.cpus} --temp . ${acc}/${acc}.sra

    # Paired layout is mandatory for this project (see data/metadata.tsv).
    for m in 1 2; do
        [ -s ${acc}_\${m}.fastq ] || { echo "missing mate \${m} for ${acc}" >&2; exit 1; }
        gzip -f ${acc}_\${m}.fastq
    done
    rm -rf ${acc}

    n=\$(( \$(gzip -dc ${acc}_1.fastq.gz | wc -l) / 4 ))
    printf '%s\\traw\\t%s\\n' ${acc} "\$n" > ${acc}.raw.count
    printf 'FETCH_SRA\\tsra-tools\\t%s\\n' "\$(fasterq-dump --version | grep -o '[0-9][0-9.]*' | head -1)" > versions.tsv
    """

    stub:
    def acc = meta.id
    """
    for m in 1 2; do echo "@r\${m}" | gzip > ${acc}_\${m}.fastq.gz; done
    printf '%s\\traw\\t1\\n' ${acc} > ${acc}.raw.count
    printf 'FETCH_SRA\\tsra-tools\\tstub\\n' > versions.tsv
    """
}
