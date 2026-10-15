// Host depletion against ONE reference. main.nf includes this module twice
// (pig, then human) under different aliases.
//
// Design choice: two sequential passes instead of one combined index.
//   + no combined index to build and version; each reference stays an independent,
//     checksummed artefact;
//   + yields per-reference read counts (pig -> human), which the project reports;
//   - reads are aligned twice (the second pass only sees the pig-depleted reads).
//
// Why samtools instead of `bowtie2 --un-conc-gz`: --un-conc keeps every pair that
// did not align *concordantly*, including pairs where one mate aligned alone.
// A pair is kept here only if BOTH mates are unmapped (SAM flag 12).
process HOST_REMOVAL {
    tag "${meta.id}:${label}"
    label 'process_host'
    conda "${params.envs_dir}/host-removal.yml"
    container params.container_host

    publishDir "${params.outdir}/host_removal", mode: 'copy', pattern: '*.bowtie2.log'

    input:
    tuple val(meta), path(r1), path(r2)
    path index_dir
    val index_name
    val label

    output:
    tuple val(meta), path("${meta.id}.${label}_1.fastq.gz"), path("${meta.id}.${label}_2.fastq.gz"), emit: reads
    tuple val(meta.id), path("${meta.id}.post_${label}.count"),                                      emit: counts
    path "${meta.id}.${label}.bowtie2.log",                                                          emit: logs
    path "versions.tsv",                                                                             emit: versions

    script:
    def id = meta.id
    """
    bowtie2 -x ${index_dir}/${index_name} -1 ${r1} -2 ${r2} \\
        -p ${task.cpus} ${params.bowtie2_preset} \\
        2> ${id}.${label}.bowtie2.log \\
    | samtools fastq -n -f 12 -F 256 -@ 2 \\
        -1 ${id}.${label}_1.fastq.gz -2 ${id}.${label}_2.fastq.gz \\
        -0 /dev/null -s /dev/null -

    n=\$(( \$(gzip -dc ${id}.${label}_1.fastq.gz | wc -l) / 4 ))
    printf '%s\\tpost_${label}\\t%s\\n' ${id} "\$n" > ${id}.post_${label}.count
    {
        printf 'HOST_REMOVAL\\tbowtie2\\t%s\\n' "\$(bowtie2 --version | sed -n '1s/.*version //p')"
        printf 'HOST_REMOVAL\\tsamtools\\t%s\\n' "\$(samtools --version | sed -n '1s/samtools //p')"
    } > versions.tsv
    """

    stub:
    def id = meta.id
    """
    for m in 1 2; do echo "@r\${m}" | gzip > ${id}.${label}_\${m}.fastq.gz; done
    echo "stub" > ${id}.${label}.bowtie2.log
    printf '%s\\tpost_${label}\\t1\\n' ${id} > ${id}.post_${label}.count
    printf 'HOST_REMOVAL\\tbowtie2\\tstub\\n' > versions.tsv
    """
}
