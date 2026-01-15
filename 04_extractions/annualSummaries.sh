#!/bin/bash

conda activate nco_stable

# Colours
RED="\033[38;5;196m"
BLUE="\033[38;5;33m"
YELLOW="\033[38;5;226m"
GREEN="\033[38;5;34m"
RESET="\033[0m"

base_dir="/mnt/Data/TraCE-Sahul"
out_base="/home/dafcluster4/Desktop/TraCESahul_annSummaries"
vars=(pr tasmax tasmin)

# decadal data (21k BP to 1500 CE)
for var in "${vars[@]}"; do
  echo -e "${GREEN}Processing ${var}...${RESET}"

  indir="${base_dir}/${var}"
  outdir="${out_base}/${var}"
  mkdir -p "${outdir}"

  files=$(printf '%s\n' "${indir}"/*.nc | grep -E "_0[1-6]\.nc$" | grep -vE "_biascorr\.nc$")

  if [ -z "${files}" ]; then
    echo -e "${RED}No .nc files found in ${indir}${RESET}"
    continue
  fi

  for f in $files; do
    bn="$(basename "${f}")"
    outfil="${outdir}/${bn%.nc}_ann.nc"

    echo -e "${YELLOW} Processing ${var}/${bn}...${RESET}"

    if [ "${var}" = "tasmin" ] || [ "${var}" = "tasmax" ]; then
      cdo -s -w -f nc4 -b F32 -P 100 \
        timselmean,12 \
        "${f}" "${outfil}"
    elif [ "${var}" = "pr" ]; then
      # Monthly mean flux (kg m-2 s-1) -> annual total (mm/year) using actual month lengths
      cdo -s -w -f nc4 -b F32 -P 100 \
        -timselsum,12 \
        -mulc,86400 \
        -muldpm \
        -settaxis,0001-01-01,,1mon \
        -setcalendar,365_day \
        "${f}" "${outfil}"
    else
      echo -e "${RED}Unknown variable ${var}; skipping.${RESET}"
      continue
    fi

    echo -e "${YELLOW} Finished ${var}/${bn} -> $(basename "${outfil}")${RESET}"
  done

  echo -e "${GREEN}Finished ${var}.${RESET}"
done

# 1500 - 1989
for var in "${vars[@]}"; do
  echo -e "${GREEN}Processing ${var} biascorr file...${RESET}"
  indir="${base_dir}/${var}"
  outdir="${out_base}/${var}"
  mkdir -p "${outdir}"
  for f in "${indir}"/*_biascorr.nc; do
    [ -e "${f}" ] || continue
    bn="$(basename "${f}")"
    outfil="${outdir}/${bn%.nc}_ann.nc"
    echo -e "${YELLOW} Processing ${var}/${bn}...${RESET}"
    if [ "${var}" = "tasmin" ] || [ "${var}" = "tasmax" ]; then
      cdo -s -w -f nc4 -b F32 -P 100 \
        yearmean \
        "${f}" "${outfil}"
    elif [ "${var}" = "pr" ]; then
      # Monthly mean flux (kg m-2 s-1) -> annual total (mm/year), with CF-compliant time axis
      cdo -s -w -f nc4 -b F32 -P 100 \
        yearsum \
        -muldpm \
        -mulc,86400 \
        "${f}" "${outfil}"
    else
      echo -e "${RED}Unknown variable ${var}; skipping.${RESET}"
      continue
    fi
    echo -e "${YELLOW} Finished ${var}/${bn} -> $(basename "${outfil}")${RESET}"
  done
  echo -e "${GREEN}Finished ${var} biascorr file.${RESET}"
done