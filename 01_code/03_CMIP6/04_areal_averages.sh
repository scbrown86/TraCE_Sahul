#!/bin/bash

conda activate nco_stable

set -uo pipefail

RED="\033[38;5;196m"
YELLOW="\033[38;5;226m"
GREEN="\033[38;5;34m"
RESET="\033[0m"

VARIABLES=("pr" "tasmax" "tasmin")
EXPERIMENTS=("historical" "ssp126" "ssp245" "ssp370" "ssp585")
BIAS_ROOT="/mnt/Data/CMIP6/bias_corrected"
CMIP6_ROOT="/mnt/Data/CMIP6"
TRACE_ROOT="/mnt/Data/TraCE-Sahul"

process_file() {
    local infile="$1"
    local outfile="${infile%.nc}.txt"
    if [[ -f "${outfile}" ]]; then
        echo -e "${YELLOW}  Skipping: ${outfile} already exists${RESET}"
        return
    fi
    echo -e "${GREEN}   Processing: $(basename "${infile}")${RESET}"
    if ! cdo -s -outputtab,date,value -fldmean "${infile}" > "${outfile}"; then
        echo -e "${RED}   fldmean failed for ${infile}${RESET}"
        rm -f "${outfile}"
        return
    fi
    echo -e "${GREEN}   Written: ${outfile}${RESET}"
}

# bias corrected files and ensemble files
for var in "${VARIABLES[@]}"; do
    echo -e "${GREEN}Variable: ${var}${RESET}"
    # bias corrected individual model files
    echo -e "${GREEN}   Bias corrected files${RESET}"
    while IFS= read -r -d '' f; do
        [[ "${f}" == *climatology* ]] && continue
        process_file "${f}"
    done < <(find "${BIAS_ROOT}/${var}" -maxdepth 1 -name "*.nc" -print0 2>/dev/null)
    # ensemble files
    echo -e "${GREEN}   Ensemble files${RESET}"
    while IFS= read -r -d '' f; do
        process_file "${f}"
    done < <(find "${BIAS_ROOT}/ensemble/${var}" -maxdepth 1 -name "*.nc" -print0 2>/dev/null)
    # raw CMIP6 files per experiment
    for experiment in "${EXPERIMENTS[@]}"; do
        echo -e "${GREEN}   CMIP6 ${experiment} files${RESET}"
        while IFS= read -r -d '' f; do
            [[ "${f}" == *climatology* ]] && continue
            process_file "${f}"
        done < <(find "${CMIP6_ROOT}/${experiment}/${var}" -maxdepth 1 -name "*.nc" -print0 2>/dev/null)
    done
    # TraCE-Sahul file
    echo -e "${GREEN}   TraCE-Sahul file${RESET}"
    trace_file="${TRACE_ROOT}/${var}/TraCE-Sahul_1500_1990_${var}.nc"
    if [[ -f "${trace_file}" ]]; then
        process_file "${trace_file}"
    else
        echo -e "${RED}   Missing TraCE-Sahul file: ${trace_file}${RESET}"
    fi
done

echo -e "${GREEN}All field means done.${RESET}"