#!/bin/bash

conda activate nco_stable

set -uo pipefail

RED="\033[38;5;196m"
YELLOW="\033[38;5;226m"
GREEN="\033[38;5;34m"
RESET="\033[0m"

# Paths and model config
INPUT_ROOT="/mnt/Data/CMIP6"
TRACE_ROOT="/mnt/Data/TraCE-Sahul"
OUT_ROOT="/mnt/Data/CMIP6/bias_corrected"
# Define mask file
MASK_FILE="/mnt/Data/TraCE-Sahul/TraCE-Sahul_1500_1990_mask.nc"
# models, variables, and experiments
MODELS=("ACCESS-ESM1-5" "CMCC-ESM2" "EC-Earth3" "MPI-ESM1-2-HR" "MRI-ESM2-0" "NorESM2-MM")
VARIABLES=("pr" "tasmax" "tasmin")
EXPERIMENTS=("ssp126" "ssp245" "ssp370" "ssp585")
CLIM_START="1960-01-01"
CLIM_END="1989-12-31"


TMPDIR=$(mktemp -d)
trap 'rm -rf "${TMPDIR}"' EXIT

# Calculate TraCE-Sahul climatology for each variable
## make an array to store files so we can easily grab them later
declare -A TRACE_CLIM_FILES
for var in "${VARIABLES[@]}"; do
    TRACE_FILE="${TRACE_ROOT}/${var}/TraCE-Sahul_1500_1990_${var}.nc"
    mkdir -p "${TRACE_ROOT}/Climatology/${var}"
    TRACE_CLIM_FILE="${TRACE_ROOT}/Climatology/${var}/TraCE-Sahul_1500_1990_${var}.nc"
    if [[ ! -f "${TRACE_FILE}" ]]; then
        echo -e "${RED}Missing TraCE-Sahul file: ${TRACE_FILE}, skipping variable ${var}${RESET}"
        continue
    fi
    if [[ -f "${TRACE_CLIM_FILE}" ]]; then
        echo -e "${YELLOW}Skipping TraCE-Sahul climatology: ${TRACE_CLIM_FILE} already exists${RESET}"
    else
        echo -e "${GREEN}Calculating TraCE-Sahul climatology for ${var}...${RESET}"
        if ! cdo -s -L -P 32 -b F32 -f nc4 \
            ymonmean -seldate,${CLIM_START},${CLIM_END} "${TRACE_FILE}" "${TRACE_CLIM_FILE}"; then
            echo -e "${RED}ymonmean failed for TraCE-Sahul ${var}${RESET}"
            continue
        fi
        echo -e "${GREEN}Written: ${TRACE_CLIM_FILE}${RESET}"
    fi
    TRACE_CLIM_FILES[${var}]="${TRACE_CLIM_FILE}"
done

# loop through each of the models
for model in "${MODELS[@]}"; do
    echo -e "${GREEN}Model: ${model} ${RESET}"

    for var in "${VARIABLES[@]}"; do
        echo -e "${GREEN}   Variable: ${var} ${RESET}"

        HIST_FILE="${INPUT_ROOT}/historical/${var}/${var}_${model}_historical_r1i1p1f1_185001-201412.nc"
        CMIP6_CLIM_FILE="${INPUT_ROOT}/historical/${var}/${var}_${model}_historical_r1i1p1f1_climatology.nc"
        TRACE_CLIM_FILE="${TRACE_CLIM_FILES[${var}]:-}"

        if [[ ! -f "${HIST_FILE}" ]]; then
            echo -e "${RED}    Missing historical file: ${HIST_FILE}, skipping variable${RESET}"
            continue
        fi
        if [[ -z "${TRACE_CLIM_FILE}" || ! -f "${TRACE_CLIM_FILE}" ]]; then
            echo -e "${RED}    TraCE-Sahul climatology unavailable for ${var}, skipping variable${RESET}"
            continue
        fi

        # Calculate CMIP6 historical climatology (1960-1989)
        if [[ -f "${CMIP6_CLIM_FILE}" ]]; then
            echo -e "${YELLOW}    Skipping climatology: ${CMIP6_CLIM_FILE} already exists${RESET}"
        else
            echo -e "${GREEN}    Calculating CMIP6 climatology...${RESET}"
            if ! cdo -s -L -P 32 -b F32 -f nc4 \
                ymonmean -seldate,${CLIM_START},${CLIM_END} "${HIST_FILE}" "${CMIP6_CLIM_FILE}"; then
                echo -e "${RED}    ymonmean failed for ${model} ${var}, skipping variable${RESET}"
                continue
            fi
            echo -e "${GREEN}    Written: ${CMIP6_CLIM_FILE}${RESET}"
        fi

        # Calculate bias and mask
        BIAS_FILE="${TMPDIR}/bias_${var}_${model}.nc"
        echo -e "${GREEN}    Calculating bias...${RESET}"
        if [[ "${var}" == "pr" ]]; then
            if ! cdo -s -L -P 32 -b F32 -f nc4 \
                ifthen "${MASK_FILE}" \
                -div -addc,1 "${TRACE_CLIM_FILE}" -addc,1 "${CMIP6_CLIM_FILE}" "${BIAS_FILE}"; then
                echo -e "${RED}    bias calculation failed for ${model} ${var}, skipping variable${RESET}"
                continue
            fi
        else
            if ! cdo -s -L -P 32 -b F32 -f nc4 \
                ifthen "${MASK_FILE}" \
                -sub "${TRACE_CLIM_FILE}" "${CMIP6_CLIM_FILE}" "${BIAS_FILE}"; then
                echo -e "${RED}    bias calculation failed for ${model} ${var}, skipping variable${RESET}"
                continue
            fi
        fi

        # Apply bias correction to historical period (1900-2014)
        HIST_SCEN_FILE="${INPUT_ROOT}/historical/${var}/${var}_${model}_historical_r1i1p1f1_185001-201412.nc"
        HIST_CROP_TMP="${TMPDIR}/hist_1900_2014_${var}_${model}.nc"

        echo -e "${GREEN}    Subsetting historical to 1900-2014...${RESET}"
        if ! cdo -s -L -P 32 -b F32 -f nc4 \
            seldate,1900-01-01,2014-12-31 "${HIST_SCEN_FILE}" "${HIST_CROP_TMP}"; then
            echo -e "${RED}    seldate failed for ${model} ${var} historical${RESET}"
        else
            HIST_OUT_DIR="${OUT_ROOT}/${var}"
            mkdir -p "${HIST_OUT_DIR}"
            HIST_OUT_FILE="${HIST_OUT_DIR}/${var}_${model}_historical_r1i1p1f1_190001-201412.nc"

            if [[ -f "${HIST_OUT_FILE}" ]]; then
                echo -e "${YELLOW}    Skipping: ${HIST_OUT_FILE} already exists${RESET}"
            else
                echo -e "${GREEN}    Applying bias correction: historical (1900-2014)${RESET}"

                if [[ "${var}" == "pr" ]]; then
                    if ! cdo -s -L -P 32 -b F32 -f nc4 \
                        ifthen "${MASK_FILE}" \
                        -ymonmul "${HIST_CROP_TMP}" "${BIAS_FILE}" "${HIST_OUT_FILE}"; then
                        echo -e "${RED}    bias application failed for ${model} ${var} historical${RESET}"
                    else
                        echo -e "${GREEN}    Written: ${HIST_OUT_FILE}${RESET}"
                    fi
                else
                    if ! cdo -s -L -P 32 -b F32 -f nc4 \
                        ifthen "${MASK_FILE}" \
                        -ymonadd "${HIST_CROP_TMP}" "${BIAS_FILE}" "${HIST_OUT_FILE}"; then
                        echo -e "${RED}    bias application failed for ${model} ${var} historical${RESET}"
                    else
                        echo -e "${GREEN}    Written: ${HIST_OUT_FILE}${RESET}"
                    fi
                fi
            fi
        fi

        # Apply bias correction to each SSP experiment (2015-2100)
        for experiment in "${EXPERIMENTS[@]}"; do
            SSP_FILE="${INPUT_ROOT}/${experiment}/${var}/${var}_${model}_${experiment}_r1i1p1f1_201501-210012.nc"

            if [[ ! -f "${SSP_FILE}" ]]; then
                echo -e "${YELLOW}    Missing SSP file: ${SSP_FILE}, skipping${RESET}"
                continue
            fi

            OUT_DIR="${OUT_ROOT}/${var}"
            mkdir -p "${OUT_DIR}"
            OUT_FILE="${OUT_DIR}/${var}_${model}_${experiment}_r1i1p1f1_201501-210012.nc"

            if [[ -f "${OUT_FILE}" ]]; then
                echo -e "${YELLOW}    Skipping: ${OUT_FILE} already exists${RESET}"
                continue
            fi

            echo -e "${GREEN}    Applying bias correction: ${experiment}${RESET}"

            if [[ "${var}" == "pr" ]]; then
                if ! cdo -s -L -P 32 -b F32 -f nc4 \
                    ifthen "${MASK_FILE}" \
                    -ymonmul "${SSP_FILE}" "${BIAS_FILE}" "${OUT_FILE}"; then
                    echo -e "${RED}    bias application failed for ${model} ${var} ${experiment}${RESET}"
                    continue
                fi
            else
                if ! cdo -s -L -P 32 -b F32 -f nc4 \
                    ifthen "${MASK_FILE}" \
                    -ymonadd "${SSP_FILE}" "${BIAS_FILE}" "${OUT_FILE}"; then
                    echo -e "${RED}    bias application failed for ${model} ${var} ${experiment}${RESET}"
                    continue
                fi
            fi

            echo -e "${GREEN}    Written: ${OUT_FILE}${RESET}"
        done
    done
done

echo -e "${GREEN}All done.${RESET}"

# Calculate ensemble mean, 10th, and 90th percentile across all models
echo -e "${GREEN}Calculating ensemble statistics${RESET}"

ENS_OUT_ROOT="/mnt/Data/CMIP6/bias_corrected/ensemble"
ALL_EXPERIMENTS=("historical" "${EXPERIMENTS[@]}")

for var in "${VARIABLES[@]}"; do
    echo -e "${GREEN}Variable: ${var}${RESET}"

    for experiment in "${ALL_EXPERIMENTS[@]}"; do
        echo -e "${GREEN}   Experiment: ${experiment}${RESET}"

        if [[ "${experiment}" == "historical" ]]; then
            TIMERANGE="190001-201412"
        else
            TIMERANGE="201501-210012"
        fi

        ENS_FILES=()
        for model in "${MODELS[@]}"; do
            f="${OUT_ROOT}/${var}/${var}_${model}_${experiment}_r1i1p1f1_${TIMERANGE}.nc"
            if [[ -f "${f}" ]]; then
                ENS_FILES+=("${f}")
            else
                echo -e "${YELLOW}      Missing: ${f}${RESET}"
            fi
        done

        if [[ ${#ENS_FILES[@]} -eq 0 ]]; then
            echo -e "${RED}      No files found for ${var} ${experiment}, skipping${RESET}"
            continue
        fi

        echo -e "${GREEN}   Found ${#ENS_FILES[@]} model files${RESET}"

        for nc in "${ENS_FILES[@]}"; do
            echo -e "      ${YELLOW}$(basename "${nc}")${RESET}"
        done

        ENS_OUT_DIR="${ENS_OUT_ROOT}/${var}"
        mkdir -p "${ENS_OUT_DIR}"

        MEAN_FILE="${ENS_OUT_DIR}/${var}_ensmean_${experiment}_${TIMERANGE}.nc"
        P10_FILE="${ENS_OUT_DIR}/${var}_enspctl10_${experiment}_${TIMERANGE}.nc"
        P90_FILE="${ENS_OUT_DIR}/${var}_enspctl90_${experiment}_${TIMERANGE}.nc"

        if [[ -f "${MEAN_FILE}" ]]; then
            echo -e "${YELLOW}  Skipping mean: ${MEAN_FILE} already exists${RESET}"
        else
            echo -e "${GREEN}   Calculating ensemble mean...${RESET}"
            if ! cdo -s -L -P 64 -b F32 -f nc4 \
                ensmedian "${ENS_FILES[@]}" "${MEAN_FILE}"; then
                echo -e "${RED} ensmean failed for ${var} ${experiment}${RESET}"
            else
                echo -e "${GREEN}   Written: ${MEAN_FILE}${RESET}"
            fi
        fi

        if [[ -f "${P10_FILE}" ]]; then
            echo -e "${YELLOW}  Skipping p10: ${P10_FILE} already exists${RESET}"
        else
            echo -e "${GREEN}   Calculating ensemble 10th percentile...${RESET}"
            if ! cdo -s -L -P 64 -b F32 -f nc4 \
                enspctl,10 "${ENS_FILES[@]}" "${P10_FILE}"; then
                echo -e "${RED} enspctl,10 failed for ${var} ${experiment}${RESET}"
            else
                echo -e "${GREEN}   Written: ${P10_FILE}${RESET}"
            fi
        fi

        if [[ -f "${P90_FILE}" ]]; then
            echo -e "${YELLOW}  Skipping p90: ${P90_FILE} already exists${RESET}"
        else
            echo -e "${GREEN}   Calculating ensemble 90th percentile...${RESET}"
            if ! cdo -s -L -P 64 -b F32 -f nc4 \
                enspctl,90 "${ENS_FILES[@]}" "${P90_FILE}"; then
                echo -e "${RED} enspctl,90 failed for ${var} ${experiment}${RESET}"
            else
                echo -e "${GREEN}   Written: ${P90_FILE}${RESET}"
            fi
        fi
    done
done

echo -e "${GREEN}All ensemble statistics done.${RESET}"