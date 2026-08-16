#!/bin/bash

conda activate nco_stable
set -uo pipefail

RED="\033[38;5;196m"
YELLOW="\033[38;5;226m"
GREEN="\033[38;5;34m"
RESET="\033[0m"

VARIABLES=("pr" "tasmax" "tasmin")
EXPERIMENTS=("historical")
BIAS_ROOT="/mnt/Data/CMIP6/bias_corrected"
CMIP6_ROOT="/mnt/Data/CMIP6"
TRACE_ROOT="/mnt/Data/TraCE-Sahul"
OUT_ROOT="/home/dafcluster4/Desktop/validation_datasets_traceSahul_CMIP6"

process_file() {
    local infile="$1"
    local outdir="$2"
    mkdir -p "${outdir}"
    local base
    base="$(basename "${infile}" .nc)"
    # seasonal averages (annual)
    local outfile_seas="${outdir}/${base}_seasmean.nc"
    if [[ -f "${outfile_seas}" ]]; then
        echo -e "${YELLOW}  Skipping: ${outfile_seas} already exists${RESET}"
    else
        echo -e "${GREEN}   Seasonal climatology: $(basename "${infile}")${RESET}"
        if ! cdo -b F32 -f nc4 seasmean -selyear,1910/1989 "${infile}" "${outfile_seas}"; then
            echo -e "${RED}   seasmean failed for ${infile}${RESET}"
            rm -f "${outfile_seas}"
        else
            echo -e "${GREEN}   Written: ${outfile_seas}${RESET}"
        fi
    fi
    # seasonal climatology
    local outfile_yseas="${outdir}/${base}_yseasmean.nc"
    if [[ -f "${outfile_yseas}" ]]; then
        echo -e "${YELLOW}  Skipping: ${outfile_yseas} already exists${RESET}"
    else
        echo -e "${GREEN}   Seasonal climatology: $(basename "${infile}")${RESET}"
        if ! cdo -b F32 -f nc4 yseasmean -selyear,1910/1989 "${infile}" "${outfile_yseas}"; then
            echo -e "${RED}   yseasmean failed for ${infile}${RESET}"
            rm -f "${outfile_yseas}"
        else
            echo -e "${GREEN}   Written: ${outfile_yseas}${RESET}"
        fi
    fi
    # monthly climatology
    local outfile_clim="${outdir}/${base}_ymonmean.nc"
    if [[ -f "${outfile_clim}" ]]; then
        echo -e "${YELLOW}  Skipping: ${outfile_clim} already exists${RESET}"
    else
        echo -e "${GREEN}   Monthly climatology: $(basename "${infile}")${RESET}"
        if ! cdo -b F32 -f nc4 ymonmean -selyear,1910/1989 "${infile}" "${outfile_clim}"; then
            echo -e "${RED}   ymonmean failed for ${infile}${RESET}"
            rm -f "${outfile_clim}"
        else
            echo -e "${GREEN}   Written: ${outfile_clim}${RESET}"
        fi
    fi
}

# bias corrected, ensemble mean, raw CMIP6 historical, and TraCE-Sahul files
for var in "${VARIABLES[@]}"; do
    echo -e "${GREEN}Variable: ${var}${RESET}"
    # bias corrected individual model files
    for experiment in "${EXPERIMENTS[@]}"; do
        echo -e "${GREEN}   Bias corrected ${experiment} files${RESET}"
        while IFS= read -r -d '' f; do
            [[ "${f}" == *climatology* ]] && continue
            process_file "${f}" "${OUT_ROOT}/${var}/CMIP6_bias_corrected"
        done < <(find "${BIAS_ROOT}/${var}" -maxdepth 1 -name "${var}_*_${experiment}_*.nc" -print0 2>/dev/null)
    done
    # ensemble mean file
    echo -e "${GREEN}   Ensemble mean file${RESET}"
    while IFS= read -r -d '' f; do
        process_file "${f}" "${OUT_ROOT}/${var}/ensemble"
    done < <(find "${BIAS_ROOT}/ensemble/${var}" -maxdepth 1 -name "${var}_ensmean_historical_*.nc" -print0 2>/dev/null)
    # raw CMIP6 historical files
    for experiment in "${EXPERIMENTS[@]}"; do
        echo -e "${GREEN}   CMIP6 ${experiment} files${RESET}"
        while IFS= read -r -d '' f; do
            [[ "${f}" == *climatology* ]] && continue
            process_file "${f}" "${OUT_ROOT}/${var}/CMIP6_${experiment}"
        done < <(find "${CMIP6_ROOT}/${experiment}/${var}" -maxdepth 1 -name "*.nc" -print0 2>/dev/null)
    done
    # TraCE-Sahul file
    echo -e "${GREEN}   TraCE-Sahul file${RESET}"
    trace_file="${TRACE_ROOT}/${var}/TraCE-Sahul_annual_1500_1990_${var}.nc"
    if [[ -f "${trace_file}" ]]; then
        process_file "${trace_file}" "${OUT_ROOT}/${var}/TraCE-Sahul"
    else
        echo -e "${RED}   Missing TraCE-Sahul file: ${trace_file}${RESET}"
    fi
done
echo -e "${GREEN}All field means done.${RESET}"