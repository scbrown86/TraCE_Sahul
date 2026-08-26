#!/bin/bash

conda activate nco_stable

# Colours
RED="\033[38;5;196m"
BLUE="\033[38;5;33m"
YELLOW="\033[38;5;226m"
GREEN="\033[38;5;34m"
RESET="\033[0m"

base_dir="/mnt/Data/CMIP6/bias_corrected/ensemble"
vars=(pr tasmax tasmin)
scenarios=(historical ssp126 ssp245 ssp370 ssp585)

for var in "${vars[@]}"; do
    echo -e "${GREEN}Processing $var...${RESET}"
    for scenario in "${scenarios[@]}"; do
        if [ "$scenario" = "historical" ]; then
            daterange="190001-201412"
        else
            daterange="201501-210012"
        fi
        f="${base_dir}/${var}/${var}_ensmean_${scenario}_${daterange}.nc"
        if [ ! -f "$f" ]; then
            echo -e "${RED} Missing $f, skipping...${RESET}"
            continue
        fi
        echo -e "${YELLOW} Processing $(basename "$(dirname "$f")")/$(basename "$f")...${RESET}"
        outdir="/home/dafcluster4/Desktop/TraCE-Sahul/CMIP6/$var"
        mkdir -p "$outdir"
        outfil="$outdir/$(basename "$f")"
        cdo -L -s sellonlatbox,125.0,135.0,-13.0,-8.0 "$f" "$outfil"
        echo -e "${YELLOW} Finished $(basename "$(dirname "$f")")/$(basename "$f")...${RESET}"
    done
    echo -e "${GREEN}Finished $var...${RESET}"
done