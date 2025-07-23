#!/bin/bash
conda deactivate

END=5880
START=1

export SINGULARITY_IMG="/home/dafcluster4/chelsa_paleo/singularity/chelsa_paleo.sif"
export SCRIPT="/home/dafcluster4/chelsa_paleo/src/chelsa.py"
export INPUT_DIR="/home/dafcluster4/Documents/GitHub/TraCE_Sahul/02_data/03_CHELSA_paleo/"
export OUTPUT_DIR="/home/dafcluster4/Documents/GitHub/TraCE_Sahul/02_data/03_CHELSA_paleo/out/"
export SCRATCH_DIR="/home/dafcluster4/scratch"

conda activate nco_stable

# need to ensure the coarse elevation is the same as used in the paleo runs
cp "/media/dafcluster4/storage/TraCE_22k_1500CE/static/merc_template.nc" "${INPUT_DIR}/static/merc_template.nc" # static template
in_high_oro="/media/dafcluster4/storage/TraCE_22k_1500CE/orog/oro_high.nc"
out_high_oro="/home/dafcluster4/Documents/GitHub/TraCE_Sahul/02_data/03_CHELSA_paleo/orog/oro_high.nc"
in_oro="/media/dafcluster4/storage/TraCE_22k_1500CE/orog/oro.nc"
out_oro="/home/dafcluster4/Documents/GitHub/TraCE_Sahul/02_data/03_CHELSA_paleo/orog/oro.nc"
cdo -L -w -s seltimestep,2155 "$in_high_oro" "$out_high_oro"
cdo -L -w -s seltimestep,2155 "$in_oro" "$out_oro"
# need to remap the oro_high to the coarse resolution
## "Clean" the netcdf files
gdal_translate "${INPUT_DIR}/orog/oro_high.nc" "${INPUT_DIR}/orog/oro_high.tif" > /dev/null 2>&1
gdal_translate "${INPUT_DIR}/orog/oro_high.tif" "${INPUT_DIR}/orog/oro_high.nc" > /dev/null 2>&1
gdal_translate "${INPUT_DIR}/orog/oro.nc" "${INPUT_DIR}/orog/oro.tif" > /dev/null 2>&1
gdal_translate "${INPUT_DIR}/orog/oro.tif" "${INPUT_DIR}/orog/oro.nc" > /dev/null 2>&1
    
# regridding high res to coarse res
ncpdq -D 0 -O -U "${INPUT_DIR}/orog/oro_high.nc" "${INPUT_DIR}/orog/oro_high.nc" # need to "unpack" data before regridding
# ncatted -O -a _FillValue,elevation,m,f,1.0e36 "${INPUT_DIR}/orog/oro_high.nc" "${INPUT_DIR}/orog/oro_high.nc"
# ncatted -O -a _FillValue,elevation,m,f,1.0e36 "${INPUT_DIR}/orog/oro.nc" "${INPUT_DIR}/orog/oro.nc"
ncremap -D 0 -a nco_con -t 100 -d "${INPUT_DIR}/orog/oro.nc" "${INPUT_DIR}/orog/oro_high.nc" "${INPUT_DIR}/orog/oro_remap.nc" > /dev/null 2>&1
cdo -s -w -L -b F32 -selgrid,2 "${INPUT_DIR}/orog/oro_remap.nc" "${INPUT_DIR}/orog/oro_remap2.nc"
cdo -s -w -L -b F32 setmisstoc,0 -remapnn,"${INPUT_DIR}/orog/oro_remap2.nc" "${INPUT_DIR}/orog/oro_remap2.nc" "${INPUT_DIR}/orog/oro_remap.nc"
rm -f "${INPUT_DIR}/orog/oro_remap2.nc"
    
# ensure orographic and bathymetric coverage at coarse resolution
cdo -O -b F32 -s -w -L ifthenelse "${INPUT_DIR}/orog/oro_remap.nc" "${INPUT_DIR}/orog/oro_remap.nc" "${INPUT_DIR}/orog/oro.nc" "${INPUT_DIR}/orog/oro_remap2.nc" 
cdo -s -w -L copy "${INPUT_DIR}/orog/oro_remap2.nc" "${INPUT_DIR}/orog/oro.nc"
rm -f "${INPUT_DIR}/orog/oro_remap.nc" "${INPUT_DIR}/orog/oro_remap2.nc" "${INPUT_DIR}/orog/oro_high.tif" "${INPUT_DIR}/orog/oro.tif"
    
# "Clean" final version
gdal_translate "${INPUT_DIR}/orog/oro.nc" "${INPUT_DIR}/orog/oro.tif" > /dev/null 2>&1
gdal_translate "${INPUT_DIR}/orog/oro.tif" "${INPUT_DIR}/orog/oro.nc" > /dev/null 2>&1
rm -f "${INPUT_DIR}/orog/oro.tif"

conda deactivate
conda activate CHELSA_paleo

# singularity exec $SINGULARITY_IMG python $SCRIPT -t 1 -i $INPUT_DIR -o $OUTPUT_DIR -tmp $SCRATCH_DIR

START_TIME=$(date +%s)

seq $END -1 $START | parallel --bar -j 12 -k ' # will start at 12/1989 and work backwards
    TMP_PREFIX=$(printf "%04d" {}) &&
    TMP_DIR="$SCRATCH_DIR/tmp_$TMP_PREFIX/" &&
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

# Loop through each folder and concatenate files
for foldername in "${folders[@]}"; do
    folder_path="$OUTPUT_DIR/$foldername"
    if [ -d "$folder_path" ]; then
        file_count=$(find "$folder_path" -maxdepth 1 -type f -name "*.nc" | wc -l)
        if [ "$file_count" -eq "$END" ]; then
            echo "Processing $foldername with $file_count files (expected: $END)..."
            cd "$folder_path" || {
                echo "Failed to enter $folder_path"
                continue
            }
            output_file="${folder_path}/CHELSA_${foldername}_1600_1990.nc"
            # create a text file to ensure order is correct!
            ls -v1 "$folder_path" >input_order.txt
            # concatenate
            cdo settaxis,1600-01-16,,1month -setcalendar,365_day -cat $(ls -v1 "$folder_path"/*.nc) "$output_file"
        else
            echo "Skipping $foldername — found $file_count files, expected $END"
        fi
    else
        echo "Directory $folder_path does not exist."
    fi
done
