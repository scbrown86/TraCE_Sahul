#!/bin/bash

conda activate nco_stable

set -uo pipefail

# Colours
RED="\033[38;5;196m"
YELLOW="\033[38;5;226m"
GREEN="\033[38;5;34m"
RESET="\033[0m"

# Process the daily data for NorESM2-MM model first
# Paths and config
INPUT_ROOT="/mnt/Data/CMIP6/CMIP6"
MODEL="NorESM2-MM"

# find all daily tasmax and tasmin files for NorESM2-MM
mapfile -t DAILY_FILES < <(find "${INPUT_ROOT}" \
    -path "*/${MODEL}/*" \
    -path "*/day/*" \
    -name "*.nc" \
    \( -name "tasmax*" -o -name "tasmin*" \) | sort)

echo -e "${GREEN}Found ${#DAILY_FILES[@]} daily files for ${MODEL}${RESET}"
# printf "${YELLOW}%s${RESET}\n" "${DAILY_FILES[@]}" | xargs -I{} basename {}

for nc in "${DAILY_FILES[@]}"; do
    # replace 'day' with 'Amon' in the input path to write to monthly folder
    out_dir=$(dirname "${nc}" | sed 's|/day/|/Amon/|')
    mkdir -p "${out_dir}"

    # build output filename and reformat timerange
    base=$(basename "${nc}" .nc)
    timerange=$(echo "${base}" | grep -oP '[0-9]{8}-[0-9]{8}')
    tstart=$(echo "${timerange}" | cut -d'-' -f1 | cut -c1-6)
    tend=$(echo "${timerange}" | cut -d'-' -f2 | cut -c1-6)
    outname=$(echo "${base}" | sed "s|_day_|_Amon_|;s|${timerange}|${tstart}-${tend}|")
    outfile="${out_dir}/${outname}.nc"

    if [[ -f "${outfile}" ]]; then
        echo -e "${YELLOW}Skipping: $(basename "${outfile}") already exists${RESET}"
        continue
    fi

    echo -e "${GREEN}Processing: $(basename "${nc}")${RESET}"
    echo -e "${GREEN}        --> $(basename "${outfile}")${RESET}"

    if ! cdo -s -w -L -b F32 -f nc4 -P 100 --timestat_date middle \
        -monmean "${nc}" "${outfile}"; then
        echo -e "${RED}monmean failed for $(basename "${nc}")${RESET}"
        continue
    fi

    echo -e "${GREEN}Written: ${outfile}${RESET}"
done

echo -e "${GREEN}NorESM2-MM monthly aggregation complete.${RESET}"

# Process all the monthly data

# Paths and config
INPUT_ROOT="/mnt/Data/CMIP6/CMIP6"
OUTPUT_ROOT="/mnt/Data/CMIP6"
GRID_REF="/media/dafcluster4/storage/TraCE_1500_1990CE/1500_1990/out/pr/TraCE-Sahul_1500_1990_pr.nc"
LONLATBOX="100,166.5,-50,16.5"
END_DATE="2100-12"
TMPDIR=$(mktemp -d)
trap 'rm -rf "${TMPDIR}"' EXIT

# Map the directories, making sure to exclude 'day'
mapfile -t NC_DIRS < <(find "${INPUT_ROOT}" -name "*.nc" \
    -not -path "*/day/*" | xargs -I{} dirname {} | sort -u)

# for testing
# dir="${NC_DIRS[0]}"
# dir="${NC_DIRS[41]}"

for dir in "${NC_DIRS[@]}"; do
    variable=$(basename "$(dirname "$(dirname "${dir}")")")
    experiment=$(basename "$(dirname "$(dirname "$(dirname "$(dirname "$(dirname "${dir}")")")")")")

    case "${variable}" in
    pr | tasmax | tasmin) ;;
    *)
        echo -e "${YELLOW}Skipping ${dir} (variable: ${variable})${RESET}"
        continue
        ;;
    esac
    # map the files in the directory
    mapfile -t NC_FILES < <(find "${dir}" -name "*.nc" | sort)
    # for nc in "${NC_FILES[@]}"; do
    #     echo -e "   ${GREEN}$(basename "${nc}")${RESET}"
    # done
    if [[ ${#NC_FILES[@]} -eq 0 ]]; then
        echo -e "${RED}No files found in ${dir}, skipping${RESET}"
        continue
    fi
    # extract details from filename
    BASE=$(basename "${NC_FILES[0]}" .nc)
    IFS='_' read -r var table model expid variant gridlabel timerange <<<"${BASE}"
    if [[ "${expid}" == "historical" ]]; then
        TSTART="185001"
        DATE_START="1850-01-16"
        TEND="201412"
    else
        TSTART="201501"
        DATE_START="2015-01-16"
        TEND="210012"
    fi

    # define outname and output file
    OUTNAME="${var}_${model}_${expid}_${variant}_${TSTART}-${TEND}.nc"
    OUTDIR="${OUTPUT_ROOT}/${experiment}/${var}"
    mkdir -p "${OUTDIR}"
    OUTFILE="${OUTDIR}/${OUTNAME}"
    if [[ -f "${OUTFILE}" ]]; then
        echo -e "${YELLOW}Skipping: ${OUTFILE} already exists${RESET}"
        continue
    fi
    # process
    echo -e "${GREEN}Processing: ${variable} | ${experiment} | ${model}${RESET}"
    for nc in "${NC_FILES[@]}"; do
        echo -e "   ${YELLOW}$(basename "${nc}")${RESET}"
    done
    TMP_MERGE="${TMPDIR}/merge_${var}_${model}_${expid}.nc"
    TMP_CUT="${TMPDIR}/cut_${var}_${model}_${expid}.nc"

    # Crop to buffered Sahul extent
    echo -e "${GREEN}Cropping...${RESET}"
    TMP_CROPS=()
    for nc in "${NC_FILES[@]}"; do
        tmp_c="${TMPDIR}/crop_$(basename "${nc}")"
        if ! cdo -s -L -P 100 -b F32 -f nc4 sellonlatbox,${LONLATBOX} "${nc}" "${tmp_c}"; then
            echo -e "${RED}sellonlatbox failed for ${nc}${RESET}"
            continue 2
        fi
        TMP_CROPS+=("${tmp_c}")
    done

    # Merge along temporal axis
    echo -e "${GREEN}Time concatenation and leap day removal...${RESET}"
    if ! cdo -s -L -P 8 -b F32 -f nc4 \
        -delete,month=2,day=29 \
        [ -mergetime "${TMP_CROPS[@]}" ] "${TMP_MERGE}"; then
        echo -e "${RED}mergetime/delete failed for ${var} ${model} ${expid}${RESET}"
        continue
    fi

    # Don't extend past 2100
    if ! cdo -s -L -P 100 -b F32 -f nc4 seldate,1850-01-01,${END_DATE}-31 "${TMP_MERGE}" "${TMP_CUT}"; then
        echo -e "${RED}seldate failed for ${var} ${model} ${expid}${RESET}"
        continue
    fi

    # Remap and convert units
    echo -e "${GREEN}Regridding and converting units...${RESET}"
    if [[ "${variable}" == "pr" ]]; then
        if ! cdo -s -L -P 100 -b F32 -f nc4 \
            -setrtoc,-inf,0,0 \
            -setunit,'mm/month' \
            -muldpm \
            -mulc,86400 \
            -setcalendar,365_day \
            -settaxis,"${DATE_START}",,1month \
            -remapbil,"${GRID_REF}" "${TMP_CUT}" "${OUTFILE}"; then
            echo -e "${RED}remap/unit conversion failed for ${var} ${model} ${expid}${RESET}"
            continue
        fi
    else
        if ! cdo -s -L -P 100 -b F32 -f nc4 \
            -setunit,'deg_C' \
            -subc,273.15 \
            -setcalendar,365_day \
            -settaxis,"${DATE_START}",,1month \
            -remapbil,"${GRID_REF}" "${TMP_CUT}" "${OUTFILE}"; then
            echo -e "${RED}remap/unit conversion failed for ${var} ${model} ${expid}${RESET}"
            continue
        fi
    fi

    echo -e "${GREEN}Written: ${OUTFILE}${RESET}"
done

echo -e "${GREEN}All done.${RESET}"
