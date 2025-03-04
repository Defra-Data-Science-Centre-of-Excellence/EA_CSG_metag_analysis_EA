"""
Author: Susheel Bhanu BUSI
Affiliation: Molecular Ecology group, UKCEH
Date: [2023-11-20]
Run: snakemake -s workflow/rules/binning.smk --use-conda --cores 4 -rp
Latest modification:
Purpose: To prepare assemblies for binning
"""


############################################
rule binning:
    input:
        os.path.join(RESULTS_DIR, "bins/metabat"),
        os.path.join(RESULTS_DIR, "bins/metabinner_cov.txt"),
        os.path.join(RESULTS_DIR, "bins/concoct/concoct_clustering_merged.csv")
    output:
        touch("status/binning.done")


############################################
# localrules: 


############################################
# Setting up files for binning 
rule metabat2_mapping:
    input:
        expand(os.path.join(RESULTS_DIR,"bam/{sid}/cat_assembly_{sid}.bam"), sid=SAMPLES.index)
    output:
        os.path.join(RESULTS_DIR,"bins/cat_assembly_metabat_cov.txt")
    conda:
        os.path.join(ENV_DIR, "metabat2.yaml")
    threads:
        config["metabat2"]["threads"]
    log:
        out=os.path.join(RESULTS_DIR, "logs/metabat_mapping.out.log"),
        err=os.path.join(RESULTS_DIR, "logs/metabat_mapping.err.log")
    message:
        "Running the first part of metabat2 to estimate the coverage"
    shell:
        "(date && jgi_summarize_bam_contig_depths --outputDepth {output} {input} && "
        "date) 2> {log.err} > {log.out}"

rule metabat2:
    input:
        contig=os.path.join(RESULTS_DIR, "assembly/cat_assembly_filter.fasta"),
        cov=rules.metabat2_mapping.output
    output:
        directory(os.path.join(RESULTS_DIR,"bins/metabat/"))
    conda:
        os.path.join(ENV_DIR, "metabat2.yaml")
    threads:
        config["metabat2"]["threads"]
    log:
        out=os.path.join(RESULTS_DIR, "logs/metabat2.out.log"),
        err=os.path.join(RESULTS_DIR, "logs/metabat2.err.log")
    message:
        "Running metabat2 to obtain bins"
    shell:
        "(date && metabat2 -i {input.contig} -a {input.cov} -o {output}/metabat -t {threads} && "
        "date) 2> {log.err} > {log.out}"

rule concoct_prepare:
    input:
        contig=os.path.join(RESULTS_DIR, "assembly/cat_assembly_filter.fasta"),
        bam=expand(os.path.join(RESULTS_DIR,"bam/{sid}/cat_assembly_{sid}.bam"), sid=SAMPLES.index)
    output:
        bed=os.path.join(RESULTS_DIR,"bins/cat_assembly_10k.bed"),
        cont=os.path.join(RESULTS_DIR,"bins/cat_assembly_10k.fa"),
        cov=os.path.join(RESULTS_DIR,"bins/cat_assembly_concoct_cov.txt")
    conda:
        os.path.join(ENV_DIR, "concoct.yaml")
    log:
        out=os.path.join(RESULTS_DIR, "logs/concoct_prepare.out.log"),
        err=os.path.join(RESULTS_DIR, "logs/concoct_prepare.err.log")
    message:
        "Preparing files for Concoct"
    shell:
        "(date && cut_up_fasta.py {input.contig} -c 10000 -o 0 --merge_last -b {output.bed} > {output.cont} && "
        "concoct_coverage_table.py {output.bed} {input.bam} > {output.cov} && [[ -s {output.cov} ]] && "
        "date) 2> {log.err} > {log.out}"

rule concoct:
    input:
        contig=rules.concoct_prepare.output.cont,
        cov=rules.concoct_prepare.output.cov
    output:
        os.path.join(RESULTS_DIR,"bins/concoct/concoct_clustering_merged.csv")
    conda:
        os.path.join(ENV_DIR, "concoct.yaml")
    threads:
        config["concoct"]["threads"]
    log:
        out=os.path.join(RESULTS_DIR, "logs/concoct.out.log"),
        err=os.path.join(RESULTS_DIR, "logs/concoct.err.log")
    message:
        "Running concoct to obtain bins"
    shell:
        "(date && concoct --composition_file {input.contig} --coverage_file {input.cov} -b $(dirname {output})/concoct -t {threads} && "
        "merge_cutup_clustering.py $(dirname {output})/concoct_clustering_gt1000.csv > {output} && "
        "date) 2> {log.err} > {log.out}"        

rule metabinner_install:
    output:
        dbs=directory(os.path.join(DB_DIR, "MetaBinner"))
    conda:
        os.path.join(ENV_DIR, "metabinner.yaml")
    shell:
        "git clone https://github.com/ziyewang/MetaBinner.git &> /dev/null && "
        "mv MetaBinner $(dirname {output.dbs})"

rule metabinner_coverage:
    input:
        expand(os.path.join(RESULTS_DIR,"bam/{sid}/cat_assembly_{sid}.bam"), sid=SAMPLES.index)
    output:
        temp=temp(os.path.join(RESULTS_DIR,"bins/metabinner_temp.txt")),
        final=os.path.join(RESULTS_DIR,"bins/metabinner_cov.txt")
    conda:
        os.path.join(ENV_DIR, "metabat.yaml")
    threads:
        config["metabinner"]["threads"]
    log:
        out=os.path.join(RESULTS_DIR, "logs/metabinner_mapping.out.log"),
        err=os.path.join(RESULTS_DIR, "logs/metabinner_mapping.err.log")
    message:
        "Running the first part of metabinner to estimate the coverage"
    shell:
        """
        (date && jgi_summarize_bam_contig_depths --noIntraDepthVariance --outputDepth {output.temp} {input} && 
        cat {output.temp} | awk '{{if ($2>{config[metabinner][length]}) print $0 }}' | cut -f -1,4- > {output.final} && 
        date) 2> {log.err} > {log.out}
        """

rule metabinner_prepare:
    input:
        contig=os.path.join(RESULTS_DIR, "assembly/cat_assembly_filter.fasta"),
        bin=rules.metabinner_install.output.dbs
    output:
        cont_t=temp(RESULTS_DIR + "/assembly" + "/cat_assembly_filter_" + str(config["metabinner"]["length"]) + ".fa"),        
        cont=RESULTS_DIR + "/bins/metabinner_" + str(config["metabinner"]["length"]) + ".fa",        
        kmer_t=temp(RESULTS_DIR + "/assembly" + "/cat_assembly_filter_kmer_4_f" + str(config["metabinner"]["length"]) + ".csv"),
        kmer=RESULTS_DIR + "/bins/kmer_4_f" + str(config["metabinner"]["length"]) + ".csv"
    conda:
        os.path.join(ENV_DIR, "metabinner.yaml")
    log:
        out=os.path.join(RESULTS_DIR, "logs/metabinner_prepare.out.log"),
        err=os.path.join(RESULTS_DIR, "logs/metabinner_prepare.err.log")
    message:
        "Prepare fasta and kmer file for Metabinner"
    shell:
        "(date && python {input.bin}/scripts/Filter_tooshort.py {input.contig} {config[metabinner][length]} && "
        "cp {output.cont_t} {output.cont} && " 
        "python {input.bin}/scripts/gen_kmer.py {input.contig} {config[metabinner][length]} 4 && "
        "cp {output.kmer_t} {output.kmer} && date) 2> {log.err} > {log.out}"

rule metabinner:
    input:
        cont=rules.metabinner_prepare.output.cont,
        cov=rules.metabinner_coverage.output.final,
        kmer=rules.metabinner_prepare.output.kmer,    
        path=rules.metabinner_install.output.dbs
    output:
        os.path.join(RESULTS_DIR, "bins/Metabinner/metabinner_result.tsv")
    conda:
        os.path.join(ENV_DIR, "metabinner.yaml")
    log:
        out=os.path.join(RESULTS_DIR, "logs/metabinner.out.log"),
        err=os.path.join(RESULTS_DIR, "logs/metabinner.err.log")
    threads:
        config["metabinner"]["threads"]
    message:
        "Running Metabinner"
    shell:
        "(date && run_metabinner.sh -a {input.cont} -d {input.cov} -k {input.kmer} -p {input.path} -o $(dirname {output}) -t {threads} -s huge && "
        "mv $(dirname {output})/metabinner_res/* $(dirname {output}) && "
        "date) 2> {log.err} > {log.out}"        

