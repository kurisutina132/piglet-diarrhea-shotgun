// Per-sample read-pair counts across stages, then one merged table.
// Stage order: raw, post_subsample, post_fastp, post_pig, post_human.
// A stage that did not run (e.g. post_subsample without --subsample) is NA.
process READ_COUNTS {
    tag "${meta.id}"
    label 'process_low'
    conda "${params.envs_dir}/host-removal.yml"
    container params.container_host

    input:
    tuple val(meta), path(count_files)

    output:
    path "${meta.id}.read_counts.tsv", emit: table

    script:
    def id = meta.id
    """
    row="${id}\\t${meta.group}"
    for s in raw post_subsample post_fastp post_pig post_human; do
        f=${id}.\$s.count
        if [ -s "\$f" ]; then v=\$(cut -f3 "\$f"); else v=NA; fi
        row="\$row\\t\$v"
    done
    printf '%b\\n' "\$row" > ${id}.read_counts.tsv
    """

    stub:
    """
    printf '${meta.id}\\t${meta.group}\\t1\\tNA\\t1\\t1\\t1\\n' > ${meta.id}.read_counts.tsv
    """
}

process MERGE_READ_COUNTS {
    label 'process_low'
    conda "${params.envs_dir}/host-removal.yml"
    container params.container_host

    publishDir "${params.outdir}/qc", mode: 'copy'

    input:
    path tables

    output:
    path "read_counts.tsv"

    script:
    """
    printf 'run_accession\\tgroup\\traw\\tpost_subsample\\tpost_fastp\\tpost_pig\\tpost_human\\n' > read_counts.tsv
    cat ${tables} | sort -k1,1 >> read_counts.tsv
    """

    stub:
    """
    printf 'run_accession\\tgroup\\traw\\tpost_subsample\\tpost_fastp\\tpost_pig\\tpost_human\\n' > read_counts.tsv
    cat ${tables} | sort -k1,1 >> read_counts.tsv
    """
}
