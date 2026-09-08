#!/bin/bash
# Deletes original files listed in files_for_masking.txt and renames their
# corresponding _masked.nc file to take the place of the original.
# Only touches an original file if its _masked.nc counterpart exists.

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

FILE_LIST="/home/dafcluster4/Desktop/files_for_masking.txt"

while IFS= read -r FILE; do
    [ -z "$FILE" ] && continue
    MASKED_FILE="${FILE%.nc}_masked.nc"
    if [ ! -f "$MASKED_FILE" ]; then
        echo -e "${YELLOW}No masked file found for ${FILE}, skipping${RESET}"
        continue
    fi
    if [ ! -f "$FILE" ]; then
        echo -e "${YELLOW}Original file ${FILE} not found, skipping${RESET}"
        continue
    fi
    echo -e "${BLUE}Deleting ${FILE}${RESET}"
    if ! rm "$FILE"; then
        echo -e "${RED}Failed to delete ${FILE}${RESET}"
        if [ "$SOURCED" -eq 1 ]; then
            return 1
        else
            exit 1
        fi
    fi
    echo -e "${BLUE}Renaming ${MASKED_FILE} -> ${FILE}${RESET}"
    if mv "$MASKED_FILE" "$FILE"; then
        echo -e "${GREEN}Restored ${FILE}${RESET}"
    else
        echo -e "${RED}Failed to rename ${MASKED_FILE}${RESET}"
        if [ "$SOURCED" -eq 1 ]; then
            return 1
        else
            exit 1
        fi
    fi
done < "$FILE_LIST"

echo -e "${GREEN}Done. Original files have been replaced with their masked versions.${RESET}"
