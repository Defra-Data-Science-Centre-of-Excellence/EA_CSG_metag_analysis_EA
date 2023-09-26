"""
Author: Susheel Bhanu BUSI
Affiliation: Molecular Ecology group, UKCEH
Date: [2023-09-23]
Run: snakemake -s workflow/rules/eukaryotes.smk --use-conda --cores 4 -rp
Latest modification:
Purpose: To classify eukaryotes from contigs
"""


############################################
rule eukaryotes:
    input:
        os.path.join(RESULTS_DIR, "eukulele_output")
    output:
        touch("status/eukaryotes.done")


############################################
# localrules:


############################################
# Preparing the files for eukaryote classification
rule file_prep:
    input:
        os.path.join(RESULTS_DIR, "prodigal/{sid}/{sid}.faa")
    output:
        os.path.join(RESULTS_DIR, "eukulele_input/{sid}.faa")
    log:
        os.path.join(RESULTS_DIR, "logs/eukulele/{sid}.log")
    message:
        "Symlinking {wildcards.sid} for eukulele"
    shell:
        "(date && ln -vs {input} {output} && date) &> >(tee {log})"


rule eukulele:
    input:
        os.path.join(RESULTS_DIR, "eukulele_input")
    output:
        directory(os.path.join(RESULTS_DIR, "eukulele_output"))
    conda:
        os.path.join(ENV_DIR, "eukulele.yaml")
    threads:
        config["eukulele"]["threads"]
    log:
        os.path.join(RESULTS_DIR, "logs/eukulele.log")
    message:
        "Running EUKULELE"
    shell:
        "(date && EUKulele all -m mets --sample_dir {input} --out_dir {output[0]} --database {config[eukulele][db]} --scratch {config[eukulele][scratch]} --CPUs {threads} --alignment_choice diamond && "
        "date) &> >(tee {log})"

