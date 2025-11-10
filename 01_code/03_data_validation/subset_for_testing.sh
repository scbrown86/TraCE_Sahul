#!/bin/bash

conda activate nco_stable

# Colours
RED="\033[38;5;196m"
BLUE="\033[38;5;33m"
YELLOW="\033[38;5;226m"
GREEN="\033[38;5;34m"
RESET="\033[0m"

base_dir="/media/dafcluster4/storage/TraCE_22k_1500CE/out"
vars=(pr tasmax tasmin)

for var in "${vars[@]}"; do
    echo -e "${GREEN}Processing $var...${RESET}"
    files=$(ls "${base_dir}/${var}"/*.nc | grep -E "biascorr(_[0-9]+)?\.nc$")
    for f in $files; do
        echo -e "${YELLOW} Processing $(basename "$(dirname "$f")")/$(basename "$f")...${RESET}"
		outdir="/home/dafcluster4/Desktop/TraCE-Sahul/$var"
		mkdir -p "$outdir"
		outfil="$outdir/$(basename "$f")"
		cdo -L -s -w sellonlatbox,125.0,135.0,-13.0,-8.0 "$f" "$outfil"
        echo -e "${YELLOW} Finished $(basename "$(dirname "$f")")/$(basename "$f")...${RESET}"
    done
    echo -e "${GREEN}Finished $var...${RESET}"
done

base_dir="/media/dafcluster4/storage/TraCE_1500_1990CE/1500_1990/out"
for var in "${vars[@]}"; do
    echo -e "${GREEN}Processing $var...${RESET}"
    files=$(ls "${base_dir}/${var}"/*.nc | grep -E "biascorr.nc$")
    for f in $files; do
        echo -e "${YELLOW} Processing $(basename "$(dirname "$f")")/$(basename "$f")...${RESET}"
		outdir="/home/dafcluster4/Desktop/TraCE-Sahul/$var"
		mkdir -p "$outdir"
		outfil="$outdir/$(basename "$f")"
		cdo -L -s -w sellonlatbox,125.0,135.0,-13.0,-8.0 "$f" "$outfil"
        echo -e "${YELLOW} Finished $(basename "$(dirname "$f")")/$(basename "$f")...${RESET}"
    done
    echo -e "${GREEN}Finished $var...${RESET}"
done

# Now pass the split files through the R script to correct the time-index which 
# would have been reset from the CDO subsetting
conda deactivate # deactivate the nco_stable env to use R
for var in "${vars[@]}"; do
    echo -e "${GREEN}Processing $var...${RESET}"
    files=$(ls "${base_dir}/${var}"/*.nc | grep -E "biascorr(_[0-9]+)?\.nc$")
    for f in $files; do
        echo -e "${YELLOW}      Processing $(basename "$(dirname "$f")")/$(basename "$f")...${RESET}"
        Rscript /home/dafcluster4/Documents/GitHub/TraCE_Sahul/01_code/01_Decadal_pre1500/06_split_and_add_timedims.R "$f"
        echo -e "${YELLOW}      Finished $(basename "$(dirname "$f")")/$(basename "$f")...${RESET}"
    done
    echo -e "${GREEN}Finished $var...${RESET}"
done