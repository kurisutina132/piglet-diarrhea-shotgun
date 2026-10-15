// MetaPhlAn 4 profiling of host-depleted pairs, then merge across samples.
process METAPHLAN {
    tag "${meta.id}"
    label 'process_metaphlan'
    conda "${params.envs_dir}/metaphlan.yml"
    container params.container_metaphlan

    publishDir "${params.outdir}/taxonomy/profiles", mode: 'copy', pattern: '*.profile.txt'
    publishDir "${params.outdir}/taxonomy/mapout", mode: 'copy', pattern: '*.mapout.bz2'

    input:
    tuple val(meta), path(r1), path(r2)
    path db_dir
    val index

    output:
    path "${meta.id}.profile.txt",     emit: profile
    path "${meta.id}.mapout.bz2",  emit: mapout
    path "versions.tsv",               emit: versions

    script:
    def id = meta.id
    // MetaPhlAn 4.2 estimates the unclassified fraction by default; the only switch is --skip_unclassified_estimation.
    def unclass = params.metaphlan_unclassified_estimation ? '' : '--skip_unclassified_estimation'
    """
    metaphlan ${r1},${r2} \\
        --input_type fastq \\
        --index ${index} --db_dir ${db_dir} \\
        --nproc ${task.cpus} \\
        -t ${params.metaphlan_analysis_type} ${unclass} \\
        --mapout ${id}.mapout.bz2 \\
        -o ${id}.profile.txt

    printf 'METAPHLAN\\tmetaphlan\\t%s\\n' "\$(metaphlan --version 2>&1 | sed -n 's/^MetaPhlAn version \\([0-9.]*\\).*/\\1/p')" > versions.tsv
    printf 'METAPHLAN\\tdatabase\\t%s\\n' ${index} >> versions.tsv
    """

    stub:
    def id = meta.id
    """
    printf '#mpa_stub\\nclade_name\\tNCBI_tax_id\\trelative_abundance\\tcoverage\\testimated_number_of_reads_from_the_clade\\nk__Bacteria\\t2\\t100.0\\t1\\t1\\nk__Bacteria|p__Firmicutes|c__Clostridia|o__Eubacteriales|f__X|g__Y|s__Y_z\\t2|1\\t100.0\\t1\\t1\\n' > ${id}.profile.txt
    echo stub | bzip2 > ${id}.mapout.bz2
    printf 'METAPHLAN\\tmetaphlan\\tstub\\n' > versions.tsv
    """
}

process MERGE_METAPHLAN {
    label 'process_low'
    conda "${params.envs_dir}/metaphlan.yml"
    container params.container_metaphlan

    publishDir "${params.outdir}/taxonomy", mode: 'copy', pattern: 'metaphlan_*.tsv'

    input:
    path profiles

    output:
    path "metaphlan_merged.tsv",   emit: merged
    path "metaphlan_species.tsv",  emit: species
    path "versions.tsv",           emit: versions

    script:
    """
    # The merged table holds relative abundances only (per-sample read statistics stay in the profiles).
    # Column names come from the file names; strip the ".profile" suffix to leave the run accession.
    # Sort inputs by name so column order never depends on task completion order.
    merge_metaphlan_tables.py \$(printf "%s\\n" ${profiles} | LC_ALL=C sort) | sed '/^clade_name/ s/\\.profile//g' > metaphlan_merged.tsv

    # Species level only: keep header lines and rows ending at s__ (no strain/SGB t__ rows, no UNCLASSIFIED).
    awk -F'\\t' '/^#/ || \$1 == "clade_name" || (\$1 ~ /s__/ && \$1 !~ /t__/)' metaphlan_merged.tsv > metaphlan_species.tsv
    printf 'MERGE_METAPHLAN\\tmetaphlan\\t%s\\n' "\$(metaphlan --version 2>&1 | sed -n 's/^MetaPhlAn version \\([0-9.]*\\).*/\\1/p')" > versions.tsv
    """

    stub:
    """
    printf 'clade_name\\tsample\\n' > metaphlan_merged.tsv
    printf 'k__Bacteria|s__Y_z\\t100.0\\n' >> metaphlan_merged.tsv
    awk -F'\\t' '/^#/ || \$1 == "clade_name" || (\$1 ~ /s__/ && \$1 !~ /t__/)' metaphlan_merged.tsv > metaphlan_species.tsv
    printf 'MERGE_METAPHLAN\\tmetaphlan\\tstub\\n' > versions.tsv
    """
}
