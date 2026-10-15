#!/usr/bin/env nextflow
/*
 * piglet-diarrhea-shotgun
 * Reanalysis of PRJNA979345: SRA fetch -> (optional subsample) -> fastp ->
 * host removal (Sscrofa11.1, then GRCh38) -> read counts -> MetaPhlAn 4.
 *
 * Usage (see README.md):
 *   nextflow run workflow/main.nf -profile conda \
 *       --outdir results \
 *       --sscrofa_index /path/to/Sscrofa11.1 --human_index /path/to/GRCh38_noalt_as \
 *       --metaphlan_index mpa_vJan25_CHOCOPhlAnSGB_202503 --metaphlan_db /path/to/metaphlan_db
 */

nextflow.enable.dsl = 2

include { FETCH_SRA                                  } from './modules/fetch_sra'
include { SUBSAMPLE                                  } from './modules/subsample'
include { FASTP                                      } from './modules/fastp'
include { HOST_REMOVAL as HOST_REMOVAL_PIG           } from './modules/host_removal'
include { HOST_REMOVAL as HOST_REMOVAL_HUMAN         } from './modules/host_removal'
include { READ_COUNTS; MERGE_READ_COUNTS             } from './modules/read_counts'
include { METAPHLAN; MERGE_METAPHLAN                 } from './modules/metaphlan'

// ---------------------------------------------------------------------------
// Guards: every parameter that gates behaviour must be given explicitly.
// ---------------------------------------------------------------------------
def requireParams() {
    def required = ['outdir', 'sscrofa_index', 'human_index', 'metaphlan_index', 'metaphlan_db']
    def missing  = required.findAll { params[it] == null }
    if (missing) {
        error "Missing required parameter(s): ${missing.collect { '--' + it }.join(', ')}. " +
              "They have no default on purpose; see README.md (quickstart)."
    }
    if (params.subsample != null) {
        if (!(params.subsample instanceof Integer) || params.subsample < 1) {
            error "--subsample must be a positive integer (read pairs per sample), got '${params.subsample}'"
        }
    }
    if (!file(params.samplesheet).exists()) {
        error "Samplesheet not found: ${params.samplesheet}"
    }
    // Host indices are bowtie2 PREFIXES: check the directory and the first index file.
    ['sscrofa_index', 'human_index'].each { p ->
        def prefix = file(params[p])
        if (!prefix.parent?.exists() || !(prefix.parent.list() ?: []).any { it.startsWith(prefix.name + '.') }) {
            error "--${p}: no bowtie2 index files with prefix '${params[p]}'"
        }
    }
    if (!file(params.metaphlan_db).isDirectory()) {
        error "--metaphlan_db is not a directory: ${params.metaphlan_db}"
    }
}

workflow {
    requireParams()

    // Samplesheet: data/metadata.tsv is the source of truth for run -> group.
    def wanted = params.runs ? params.runs.toString().split(',').collect { it.trim() } as Set : null
    def sheet  = file(params.samplesheet).splitCsv(header: true, sep: '\t')
    if (wanted) {
        def known = sheet.collect { it.run_accession } as Set
        def unknown = wanted - known
        if (unknown) error "--runs contains accessions not in the samplesheet: ${unknown.join(', ')}"
    }
    def samples = sheet
        .findAll { wanted == null || it.run_accession in wanted }
        .collect { [id: it.run_accession, sample_id: it.sample_id, group: it.group] }
    if (!samples) error "No samples selected from ${params.samplesheet}"

    ch_meta = Channel.fromList(samples)

    // 1. Fetch (+ optional demo subsample)
    FETCH_SRA(ch_meta)
    ch_reads  = FETCH_SRA.out.reads
    ch_counts = FETCH_SRA.out.counts
    ch_versions = FETCH_SRA.out.versions

    if (params.subsample != null) {
        SUBSAMPLE(ch_reads)
        ch_reads    = SUBSAMPLE.out.reads
        ch_counts   = ch_counts.mix(SUBSAMPLE.out.counts)
        ch_versions = ch_versions.mix(SUBSAMPLE.out.versions)
    }

    // 2. QC / trimming
    FASTP(ch_reads)

    // 3. Host removal: pig first, then human
    def pig   = file(params.sscrofa_index)
    def human = file(params.human_index)
    HOST_REMOVAL_PIG(FASTP.out.reads, Channel.value(pig.parent), pig.name, 'pig')
    HOST_REMOVAL_HUMAN(HOST_REMOVAL_PIG.out.reads, Channel.value(human.parent), human.name, 'human')

    // 4. Read counts per stage
    ch_all_counts = ch_counts
        .mix(FASTP.out.counts, HOST_REMOVAL_PIG.out.counts, HOST_REMOVAL_HUMAN.out.counts)
        .groupTuple()
        .join(ch_meta.map { [it.id, it] })
        .map { id, files, meta -> [meta, files] }
    READ_COUNTS(ch_all_counts)
    MERGE_READ_COUNTS(READ_COUNTS.out.table.collect())

    // 5. Taxonomic profiling
    METAPHLAN(HOST_REMOVAL_HUMAN.out.reads, file(params.metaphlan_db), params.metaphlan_index)
    MERGE_METAPHLAN(METAPHLAN.out.profile.collect(sort: true))   // sorted: deterministic column order

    // 6. Software versions
    FASTP.out.versions
        .mix(ch_versions, HOST_REMOVAL_PIG.out.versions, HOST_REMOVAL_HUMAN.out.versions,
             METAPHLAN.out.versions, MERGE_METAPHLAN.out.versions)
        .splitText()
        .map { it.trim() }
        .unique()
        .collectFile(name: 'versions.tsv', newLine: true, sort: true,
                     seed: 'process\ttool\tversion',
                     storeDir: "${params.outdir}/pipeline_info")
}
