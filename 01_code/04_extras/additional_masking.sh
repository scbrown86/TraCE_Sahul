#!/bin/bash
# Masks a list of CHELSA chunk files against layer-matched slices of a mask file.
# Mask extraction is cached per chunk number since pr/tasmax/tasmin files for the
# same chunk share an identical grid; the first file encountered for a chunk is
# used as the remap target for that chunk's mask.

if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    SOURCED=1
else
    SOURCED=0
fi

set -uo pipefail

# Colours
RED="\033[38;5;196m"
BLUE="\033[38;5;33m"
YELLOW="\033[38;5;226m"
GREEN="\033[38;5;34m"
RESET="\033[0m"

MASK_FILE="/home/dafcluster4/Documents/GitHub/TraCE_Sahul/02_data/01_inputs/TraCE21_22kaBP_1500CE_mask_inttime.nc"
FILE_LIST="/home/dafcluster4/Desktop/files_for_masking.txt"
MASK_DIR="/tmp/chunk_masks"

mkdir -p "$MASK_DIR"

unset MASK_CACHE
declare -A MASK_CACHE

while IFS= read -r FILE; do
    [ -z "$FILE" ] && continue
    CHUNK=$(echo "$FILE" | grep -oP 'chunk\K[0-9]+(?=\.nc$)' || true)
    if [ -z "$CHUNK" ]; then
        echo -e "${YELLOW}Could not parse chunk number from ${FILE}, skipping${RESET}"
        continue
    fi
    if [ -z "${MASK_CACHE[$CHUNK]+x}" ]; then
        MASK_OUT="${MASK_DIR}/mask_chunk${CHUNK}.nc"
        echo -e "${BLUE}Extracting mask layer ${CHUNK} -> ${MASK_OUT}${RESET}"
        if ! cdo -L -w -O -s remapnn,"$FILE" \
            -seltimestep,"$CHUNK" \
            "$MASK_FILE" "$MASK_OUT" >/dev/null 2>&1; then
            echo -e "${RED}Failed to extract mask layer ${CHUNK}${RESET}"
            if [ "$SOURCED" -eq 1 ]; then
                return 1
            else
                exit 1
            fi
        fi
        MASK_CACHE[$CHUNK]="$MASK_OUT"
    fi
    MASK_OUT="${MASK_CACHE[$CHUNK]}"
    VAR=$(echo "$FILE" | grep -oP 'CHELSA_\K(pr|tasmax|tasmin)(?=_)' || true)
    case "$VAR" in
        pr)
            DTYPE="U16"
            ;;
        tasmax|tasmin)
            DTYPE="I16"
            ;;
        *)
            echo -e "${RED}Could not determine variable (pr/tasmax/tasmin) from ${FILE}, skipping${RESET}"
            continue
            ;;
    esac
    OUT_FILE="${FILE%.nc}_masked.nc"
    echo -e "${BLUE}Masking ${FILE} -> ${OUT_FILE} (${DTYPE})${RESET}"
    if cdo -b "$DTYPE" -P 100 -f nc4 -L -w -O \
        -pack \
        -div "$FILE" "$MASK_OUT" \
        "$OUT_FILE"; then
        echo -e "${GREEN}Masked ${OUT_FILE}${RESET}"
    else
        echo -e "${RED}Failed to mask ${FILE}${RESET}"
        if [ "$SOURCED" -eq 1 ]; then
            return 1
        else
            exit 1
        fi
    fi
done < "$FILE_LIST"

echo -e "${GREEN}Done. Extracted masks are cached in ${MASK_DIR} and can be removed once you're satisfied with the output.${RESET}"
