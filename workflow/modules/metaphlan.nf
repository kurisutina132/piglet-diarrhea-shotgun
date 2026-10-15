// MetaPhlAn 4 profiling of host-depleted pairs, then merge across samples.
process METAPHLAN {
    tag "${meta.id}"
    label 'process_metaphlan'
    conda "${params.envs_dir}/metaphlan.yml"
    container params.container_metaphlan

    // Profiles are published by PUBLISH_PROFILES, which strips absolute paths from the header.
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

// MetaPhlAn writes its full command line, including the absolute path of the conda
// environment, into line 2 of each profile. Profiles are tracked in git, so they are
// republished with every absolute path reduced to its basename (binary -> `metaphlan`).
process PUBLISH_PROFILES {
    tag "${profile.simpleName}"
    label 'process_low'

    publishDir "${params.outdir}/taxonomy/profiles", mode: 'copy', saveAs: { it.tokenize('/').last() }

    input:
    path profile, stageAs: 'raw/*'

    output:
    path "clean/*.profile.txt", emit: profile

    script:
    def n = profile.toString().tokenize('/').last()
    """
    mkdir -p clean
    sanitize_metaphlan_profile.sh raw/${n} > clean/${n}
    # Fail loudly if any absolute path is left in a header line.
    if grep -En '^#.*(^|[[:space:]=,"#])/[^[:space:]]*/' clean/${n}; then
        echo "error: absolute path left in the header of ${n}" >&2
        exit 1
    fi
    """

    stub:
    def n = profile.toString().tokenize('/').last()
    """
    mkdir -p clean
    sanitize_metaphlan_profile.sh raw/${n} > clean/${n}
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
    # Merged tables must not carry machine-specific absolute paths.
    if grep -En '(^|[[:space:]=,])/[^[:space:]]*/' metaphlan_merged.tsv metaphlan_species.tsv; then
        echo "error: absolute path found in a merged table" >&2
        exit 1
    fi
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
