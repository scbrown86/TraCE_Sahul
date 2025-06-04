#!/bin/bash
conda deactivate
conda activate CHELSA_paleo

END=1080
START=1
START_TIME=$(date +%s)

export SINGULARITY_IMG="/home/dafcluster4/chelsa_paleo/singularity/chelsa_paleo.sif"
export SCRIPT="/home/dafcluster4/chelsa_paleo/src/chelsa.py"
export INPUT_DIR="/home/dafcluster4/Documents/GitHub/temperature_test/02_data/03_CHELSA_paleo/"
export OUTPUT_DIR="/home/dafcluster4/Documents/GitHub/temperature_test/02_data/03_CHELSA_paleo/out/"
export SCRATCH_DIR="/home/dafcluster4/Documents/GitHub/temperature_test/02_data/03_CHELSA_paleo/scratch/"

seq $END -1 $START | parallel --bar -j 12 -k '
    TMP_PREFIX=$(printf "%04d" {}) &&
    TMP_DIR="$SCRATCH_DIR/tmp_$TMP_PREFIX" &&
    mkdir -p "$TMP_DIR" &&
    singularity exec "$SINGULARITY_IMG" python "$SCRIPT" -t {} -i "$INPUT_DIR" -o "$OUTPUT_DIR" -tmp "$TMP_DIR" > /dev/null 2>&1 &&
    rm -rf "$SCRATCH_DIR/tmp_$TMP_PREFIX"*
'

ELAPSED=$(($(date +%s) - START_TIME))
printf "Elapsed time: %d days %02d hours %02d min %02d sec\n" \
    $((ELAPSED / 86400)) $((ELAPSED % 86400 / 3600)) $((ELAPSED % 3600 / 60)) $((ELAPSED % 60))

# concatenate files when finished
# Define the list of folder names

conda deactivate
conda activate nco_stable

folders=("pr" "tas" "tasmax" "tasmin")

# Loop through each folder
for foldername in "${folders[@]}"; do
    folder_path="$OUTPUT_DIR/$foldername"
    if [ -d "$folder_path" ]; then
        file_count=$(find "$folder_path" -maxdepth 1 -type f -name "*.nc" | wc -l)
        if [ "$file_count" -eq "$END" ]; then
            echo "Processing $foldername with 1080 files..."
            cd "$folder_path" || {
                echo "Failed to enter $folder_path"
                continue
            }
            output_file="${folder_path}/CHELSA_${foldername}_1900_1990.nc"
            cdo invertlat -settaxis,1900-01-16,,1month -setcalendar,365_day -cat $(ls -v1 "$folder_path") "$output_file"
            # create a text file to ensure order is correct!
            ls -v1 "$folder_path" >input_order.txt
        else
            echo "Found $file_count files. Expected 1080"
        fi
    else
        echo "Directory $folder_path does not exist."
    fi
done
