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
        outdir="/mnt/Data/CMIP6/CMIP6-Sahul/$var"
        mkdir -p "$outdir"
		if [ "$scenario" = "historical" ]; then
            daterange="1990_2014"
        else
            daterange="2015_2100"
        fi
        outfil="$outdir/TraCE-Sahul_${scenario}_${daterange}.nc"
		if [ "$scenario" = "historical" ]; then
            cdo -s -L -O -P 64 -pack -selyear,1990/2014 "$f" "$outfil"
        else
            cdo -s -L -O -P 64 -pack -copy "$f" "$outfil"
        fi
        echo -e "${YELLOW} Finished $(basename "$(dirname "$f")")/$(basename "$f")...${RESET}"
    done
    echo -e "${GREEN}Finished $var...${RESET}"
done

# test input datasets
# /mnt/Data/CMIP6/bias_corrected/ensemble/pr/pr_ensmean_historical_190001-201412.nc
# /mnt/Data/CMIP6/bias_corrected/ensemble/tasmax/tasmax_ensmean_ssp585_201501-210012.nc

# test oututput datasets
# /mnt/Data/CMIP6/CMIP6-Sahul/pr/TraCE-Sahul_historical_1990_2014.nc
# /mnt/Data/CMIP6/CMIP6-Sahul/tasmax/TraCE-Sahul_ssp585_2015_2100.nc