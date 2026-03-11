#!/bin/bash

# deactivate any conda environment
conda deactivate || true

# CD
cd /home/dafcluster4/Documents/GitHub/TraCE_Sahul

# Input directories
BASE_DIR="/media/dafcluster4/storage/TraCE_22k_1500CE"
CLIM_DIR="${BASE_DIR}/clim"
ORO_DIR="${BASE_DIR}/orog"
STATIC_FILE="${BASE_DIR}/static/merc_template.nc"
LOG_FILE="${BASE_DIR}/processing_time.txt"

# Output base
OUTPUT_BASE="/home/dafcluster4/Documents/GitHub/TraCE_Sahul/02_data/03_CHELSA_paleo"
CLIM_OUT="${OUTPUT_BASE}/clim"
ORO_OUT="${OUTPUT_BASE}/orog"
STATIC_OUT="${OUTPUT_BASE}/static"

# Local temporary output dir
LOCAL_OUT="${OUTPUT_BASE}/out"
mkdir -p "$LOCAL_OUT/pr" "$LOCAL_OUT/tas" "$LOCAL_OUT/tasmax" "$LOCAL_OUT/tasmin"

mkdir -p "$CLIM_OUT" "$ORO_OUT" "$STATIC_OUT"
cp -n "$STATIC_FILE" "$STATIC_OUT/" # only copy if not already there

# Constants
TOTAL_TIMESTEPS=25860
CHUNK_SIZE=12

# deactivate conda environment
conda deactivate || true

# Singularity setup
export SINGULARITY_IMG="/home/dafcluster4/chelsa_paleo/singularity/chelsa_paleo.sif"
export SCRIPT="/home/dafcluster4/chelsa_paleo/src/chelsa.py"
export INPUT_DIR="$OUTPUT_BASE/"
export SCRATCH_DIR="/home/dafcluster4/scratch/"

# File list
CLIM_FILES=(huss.nc pr.nc ta_high.nc ta_low.nc tasmax.nc tasmin.nc tas.nc uwind.nc vwind.nc zg_high.nc zg_low.nc)
ORO_FILES=(oro.nc oro_high.nc)

# Start the log file
echo "Processing started: $(date)" >"$LOG_FILE"
echo "------------------------------------------" >>"$LOG_FILE"

# Loop over each time chunk
for ((t = 1; t <= TOTAL_TIMESTEPS; t += CHUNK_SIZE)); do
    t_end=$((t + CHUNK_SIZE - 1))
    aux_step=$(((t - 1) / CHUNK_SIZE + 1)) # 1-indexed
    echo "Processing timestep range: ${t}-${t_end} (aux_step: $aux_step)"
    START_TIME=$(date +%s)
    conda activate nco_stable
    # Subset clim files
    for file in "${CLIM_FILES[@]}"; do
        infile="${CLIM_DIR}/${file}"
        outfile="${CLIM_OUT}/${file}"
        cdo -L -w -s seltimestep,"${t}/${t_end}" "$infile" "$outfile" >/dev/null 2>&1
    done
    # Subset oro files
    for file in "${ORO_FILES[@]}"; do
        infile="${ORO_DIR}/${file}"
        outfile="${ORO_OUT}/${file}"
        cdo -L -w -s seltimestep,"${aux_step}" "$infile" "$outfile" >/dev/null 2>&1
    done
    # need to remap the oro_high to the coarse resolution
    ## "Clean" the netcdf files
    gdal_translate "${ORO_OUT}/oro_high.nc" "${ORO_OUT}/oro_high.tif" >/dev/null 2>&1
    gdal_translate "${ORO_OUT}/oro_high.tif" "${ORO_OUT}/oro_high.nc" >/dev/null 2>&1
    gdal_translate "${ORO_OUT}/oro.nc" "${ORO_OUT}/oro.tif" >/dev/null 2>&1
    gdal_translate "${ORO_OUT}/oro.tif" "${ORO_OUT}/oro.nc" >/dev/null 2>&1
    # regridding high res to coarse res
    ncpdq -D 0 -O -U "${ORO_OUT}/oro_high.nc" "${ORO_OUT}/oro_high.nc" # need to "unpack" data before regridding
    ncremap -D 0 -a nco_con -t 100 -d "${ORO_OUT}/oro.nc" "${ORO_OUT}/oro_high.nc" "${ORO_OUT}/oro_remap.nc" >/dev/null 2>&1
    cdo -s -w -L -b F32 -selgrid,2 "${ORO_OUT}/oro_remap.nc" "${ORO_OUT}/oro_remap2.nc"
    cdo -s -w -L -b F32 setmisstoc,0 -remapnn,"${ORO_OUT}/oro_remap2.nc" "${ORO_OUT}/oro_remap2.nc" "${ORO_OUT}/oro_remap.nc"
    rm -f "${ORO_OUT}/oro_remap2.nc"
    # ensure orographic and bathymetric coverage at coarse resolution
    cdo -O -b F32 -s -w -L ifthenelse "${ORO_OUT}/oro_remap.nc" "${ORO_OUT}/oro_remap.nc" "${ORO_OUT}/oro.nc" "${ORO_OUT}/oro_remap2.nc"
    cdo -s -w -L copy "${ORO_OUT}/oro_remap2.nc" "${ORO_OUT}/oro.nc"
    rm -f "${ORO_OUT}/oro_remap.nc" "${ORO_OUT}/oro_remap2.nc" "${ORO_OUT}/oro_high.tif" "${ORO_OUT}/oro.tif"
    # "Clean" final version
    gdal_translate "${ORO_OUT}/oro.nc" "${ORO_OUT}/oro.tif" >/dev/null 2>&1
    gdal_translate "${ORO_OUT}/oro.tif" "${ORO_OUT}/oro.nc" >/dev/null 2>&1
    rm -f "${ORO_OUT}/oro.tif"
    export OUTPUT_DIR="$LOCAL_OUT/"
    export START=1
    export END=12
    conda deactivate || true
    conda activate CHELSA_paleo
    # Run Python script in parallel (-j 12 == 12 cores)
    seq $END -1 $START | parallel --bar -j 12 -k '
        TMP_PREFIX=$(printf "%04d" {}) &&
        TMP_DIR="$SCRATCH_DIR/tmp_$TMP_PREFIX/" &&
        mkdir -p "$TMP_DIR" &&
        singularity exec "$SINGULARITY_IMG" python "$SCRIPT" -t {} -i "$INPUT_DIR" -o "$OUTPUT_DIR" -tmp "$TMP_DIR" > /dev/null 2>&1 &&
        rm -rf "$TMP_DIR"
    '
    # Output dir for this chunk
    TIME_DIR="${BASE_DIR}/chunk_out/$(printf "%05d_%05d" "$t" "$t_end")/out"
    mkdir -p "$TIME_DIR/pr" "$TIME_DIR/tas" "$TIME_DIR/tasmax" "$TIME_DIR/tasmin"
    # Move outputs to external chunk directory
    mv "$LOCAL_OUT/pr"/* "$TIME_DIR/pr/" 2>/dev/null || true
    mv "$LOCAL_OUT/tas"/* "$TIME_DIR/tas/" 2>/dev/null || true
    mv "$LOCAL_OUT/tasmax"/* "$TIME_DIR/tasmax/" 2>/dev/null || true
    mv "$LOCAL_OUT/tasmin"/* "$TIME_DIR/tasmin/" 2>/dev/null || true
    # Clean up local output dir and scratch
    find "$LOCAL_OUT" -type f -name "*.nc" -delete
    find "$CLIM_OUT" -type f -name "*.nc" -delete
    find "$ORO_OUT" -type f -name "*.nc" -delete
    find "$SCRATCH_DIR" -type f -delete
    # Log progress
    ELAPSED=$(($(date +%s) - START_TIME))
    LOG_LINE=$(printf "Chunk %05d-%05d | Elapsed time: %d days %02d hours %02d min %02d sec\n" \
        "$t" "$t_end" \
        $((ELAPSED / 86400)) $((ELAPSED % 86400 / 3600)) $((ELAPSED % 3600 / 60)) $((ELAPSED % 60)))
    echo "$LOG_LINE"
    echo "$LOG_LINE" >>"$LOG_FILE"
    # Estimate remaining time
    COMPLETED_STEPS=$((aux_step))
    REMAINING_STEPS=$((TOTAL_TIMESTEPS / CHUNK_SIZE - COMPLETED_STEPS))
    AVG_TIME_PER_CHUNK=$((ELAPSED / 1))
    if [ $COMPLETED_STEPS -eq 1 ]; then
        TOTAL_ELAPSED=$ELAPSED
    else
        TOTAL_ELAPSED=$((TOTAL_ELAPSED + ELAPSED))
        AVG_TIME_PER_CHUNK=$((TOTAL_ELAPSED / COMPLETED_STEPS))
    fi
    REMAINING_SECONDS=$((AVG_TIME_PER_CHUNK * REMAINING_STEPS))
    PROGRESS_PERCENT=$(printf "%.2f" "$(echo "$COMPLETED_STEPS * 100 / ($TOTAL_TIMESTEPS / $CHUNK_SIZE)" | bc -l)")
    ETA_LINE=$(printf "Estimated time remaining: %d days %02d hours %02d min %02d sec\n" \
        $((REMAINING_SECONDS / 86400)) \
        $((REMAINING_SECONDS % 86400 / 3600)) \
        $((REMAINING_SECONDS % 3600 / 60)) \
        $((REMAINING_SECONDS % 60)))
    echo "$ETA_LINE"
    echo "Progress: $PROGRESS_PERCENT% complete\n"
done

# Finish the log
echo "Processing finished: $(date)" >>"$LOG_FILE"
echo "------------------------------------------" >>"$LOG_FILE"
