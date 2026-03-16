#!/bin/bash
 
# Run 100-year chunks for 1500-1990CE
 
# deactivate any conda environment
conda deactivate || true
 
# CD
cd /home/dafcluster4/Documents/GitHub/TraCE_Sahul
 
# Input directories
BASE_DIR="/media/dafcluster4/storage/TraCE_1500_1990CE/1500_1990"
CLIM_DIR="${BASE_DIR}/clim"
ORO_DIR="${BASE_DIR}/orog" # constant for 1500 onwards
STATIC_FILE="${BASE_DIR}/static/merc_template.nc" # static template
LOG_FILE="${BASE_DIR}/processing_time.txt"
 
# Output base
OUTPUT_BASE="/home/dafcluster4/Documents/GitHub/TraCE_Sahul/02_data/03_CHELSA_paleo"
CLIM_OUT="${OUTPUT_BASE}/clim/"
ORO_OUT="${OUTPUT_BASE}/orog"
STATIC_OUT="${OUTPUT_BASE}/static"
 
# Local temporary output dir
LOCAL_OUT="${OUTPUT_BASE}/out/"
mkdir -p "$LOCAL_OUT/pr" "$LOCAL_OUT/tas" "$LOCAL_OUT/tasmax" "$LOCAL_OUT/tasmin"
 
# Copy orography as static for 1500 onwards
cp -r "${ORO_DIR}/." "${ORO_OUT}/"
cp "${STATIC_FILE}" "${STATIC_OUT}/"
 
# Constants
TOTAL_TIMESTEPS=5880 # 01/1500 to 12/1989
CHUNK_SIZE=1200
TOTAL_CHUNKS=$(( (TOTAL_TIMESTEPS + CHUNK_SIZE - 1) / CHUNK_SIZE ))
 
# Singularity setup
export SINGULARITY_IMG="/home/dafcluster4/chelsa_paleo/singularity/chelsa_paleo.sif"
export SCRIPT="/home/dafcluster4/chelsa_paleo/src/chelsa.py"
export INPUT_DIR="$OUTPUT_BASE/"
export OUTPUT_DIR="$OUTPUT_BASE/out/"
export SCRATCH_DIR="/home/dafcluster4/scratch/"
 
# singularity exec "$SINGULARITY_IMG" python "$SCRIPT" -t 1 -i "$INPUT_DIR" -o "$OUTPUT_DIR" -tmp "$SCRATCH_DIR" # TEST 1 timestep
 
# File list
CLIM_FILES=(huss.nc pr.nc ta_high.nc ta_low.nc tasmax.nc tasmin.nc tas.nc uwind.nc vwind.nc zg_high.nc zg_low.nc)
 
# Start the log file
echo "Processing started: $(date)" >"$LOG_FILE"
echo "------------------------------------------" >>"$LOG_FILE"
 
TOTAL_ELAPSED=0
 
# Loop over each time chunk
for ((t = 1; t <= TOTAL_TIMESTEPS; t += CHUNK_SIZE)); do
    t_end=$((t + CHUNK_SIZE - 1))
    # Cap t_end at TOTAL_TIMESTEPS if it exceeds it
    if ((t_end > TOTAL_TIMESTEPS)); then
        t_end=$TOTAL_TIMESTEPS
    fi
    aux_step=$(((t - 1) / CHUNK_SIZE + 1)) # 1-indexed
    echo "Processing timestep range: ${t}-${t_end}"
    START_TIME=$(date +%s)
    conda activate nco_stable
    # Subset clim files
    for file in "${CLIM_FILES[@]}"; do
        infile="${CLIM_DIR}/${file}"
        outfile="${CLIM_OUT}/${file}"
        cdo -L -w -s seltimestep,"${t}/${t_end}" "$infile" "$outfile" >/dev/null 2>&1
    done
    export OUTPUT_DIR="$LOCAL_OUT/"
    export START=1
    export END=$CHUNK_SIZE
    # if processing final chunk, only 1080 steps
    if ((t_end == TOTAL_TIMESTEPS)); then
        export END=1080
    fi
    conda deactivate || true
    conda activate CHELSA_paleo
    # TMP_PREFIX=$(printf "%04d" 1) &&
    # TMP_DIR="$SCRATCH_DIR/tmp_$TMP_PREFIX/" &&
    # mkdir -p "$TMP_DIR" &&
    # singularity exec "$SINGULARITY_IMG" python "$SCRIPT" -t 1 -i "$INPUT_DIR" -o "$OUTPUT_DIR" -tmp "$TMP_DIR" &&
    # rm -rf "$TMP_DIR"
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
    # find "$ORO_OUT" -type f -name "*.nc" -delete
    find "$SCRATCH_DIR" -type f -delete
    # Log progress
    ELAPSED=$(($(date +%s) - START_TIME))
    LOG_LINE=$(printf "Chunk %05d-%05d | Elapsed time: %d days %02d hours %02d min %02d sec\n" \
        "$t" "$t_end" \
        $((ELAPSED / 86400)) $((ELAPSED % 86400 / 3600)) $((ELAPSED % 3600 / 60)) $((ELAPSED % 60)))
    echo "$LOG_LINE"
    echo "$LOG_LINE" >>"$LOG_FILE"
    TOTAL_ELAPSED=$((TOTAL_ELAPSED + ELAPSED))
    AVG_TIME_PER_CHUNK=$((TOTAL_ELAPSED / aux_step))
    COMPLETED_STEPS=$((aux_step))
    REMAINING_STEPS=$((TOTAL_CHUNKS - COMPLETED_STEPS))
    REMAINING_SECONDS=$((AVG_TIME_PER_CHUNK * REMAINING_STEPS))
    PROGRESS_PERCENT=$(printf "%.2f" "$(echo "$COMPLETED_STEPS * 100 / $TOTAL_CHUNKS" | bc -l)")
    ETA_LINE=$(printf "Estimated time remaining: %d days %02d hours %02d min %02d sec\n" \
        $((REMAINING_SECONDS / 86400)) \
        $((REMAINING_SECONDS % 86400 / 3600)) \
        $((REMAINING_SECONDS % 3600 / 60)) \
        $((REMAINING_SECONDS % 60)))
    echo "$ETA_LINE"
    printf "Progress: $PROGRESS_PERCENT%% complete\n"
done

# Finish the log
echo "Processing finished: $(date)" >>"$LOG_FILE"
echo "------------------------------------------" >>"$LOG_FILE"

# concatentate the files
conda deactivate || true
conda activate nco_stable

variables=("pr" "tas" "tasmax" "tasmin")

for var in "${variables[@]}"; do
    echo "processing variable: ${var}..."
    outfile="${BASE_DIR}/out/${var}/TraCE_downscaled_1500_1990_concat.nc"
    echo "outfile = ${outfile}"
    find "${BASE_DIR}"/chunk_out/*/out/"${var}" -type f -name '*.nc' | sort -V >"${BASE_DIR}/${var}_concat_input_order.txt"
    cdo -O -L \
        -settaxis,1500-01-16,,1month \
        -setcalendar,365_day \
        -cat \
        -unpack \
        $(find "${BASE_DIR}"/chunk_out/*/out/"${var}" -type f -name '*.nc' | sort -V) \
        "${outfile}"
    # use $outfile to generate monthly climatology from 1980 onwards
    outclim="${BASE_DIR}/out/${var}/TraCE_downscaled_1980_1990_climatology.nc"
    if [[ $var = "pr" ]]; then
        cdo -O -L setunit,'mm/month' \
            -muldpm \
            -mulc,86400 \
            -ymonmean -selyear,1980/1989 \
            ${outfile} ${outclim}
    else
        cdo -O -L setunit,'deg_C' \
            -subc,273.15 \
            -ymonmean -selyear,1980/1989 \
            ${outfile} ${outclim}
    fi
    echo "Done for variable: ${var}"
done

cdo -f nc sellonlatbox,105,161.25,-52.5,11.25 -const,1,global_0.5 "${BASE_DIR}/out/agg_target.nc"
export CDO_REMAP_NORM="destarea"
export REMAP_AREA_MIN=0.10
cdo -P 100 gencon,"${BASE_DIR}/out/agg_target.nc" "${BASE_DIR}/out/pr/TraCE_downscaled_1980_1990_climatology.nc" "${BASE_DIR}/out/pr_weights.nc"
export CDO_REMAP_NORM="fracarea"
export REMAP_AREA_MIN=0.10
cdo -P 100 gencon,"${BASE_DIR}/out/agg_target.nc" "${BASE_DIR}/out/tas/TraCE_downscaled_1980_1990_climatology.nc" "${BASE_DIR}/out/tas_weights.nc"

export CDO_REMAP_NORM="destarea"
export REMAP_AREA_MIN=0.10
cdo -s -b F32 -P 100 remap,"${BASE_DIR}/out/agg_target.nc","${BASE_DIR}/out/pr_weights.nc" "${BASE_DIR}/out/pr/TraCE_downscaled_1980_1990_climatology.nc" "${BASE_DIR}/out/pr/TraCE_downscaled_1980_1990_climatology_coarse.nc"

export CDO_REMAP_NORM="fracarea"
export REMAP_AREA_MIN=0.10
cdo -s -b F32 -P 100 remap,"${BASE_DIR}/out/agg_target.nc","${BASE_DIR}/out/tas_weights.nc" "${BASE_DIR}/out/tas/TraCE_downscaled_1980_1990_climatology.nc" "${BASE_DIR}/out/tas/TraCE_downscaled_1980_1990_climatology_coarse.nc"
cdo -s -b F32 -P 100 remap,"${BASE_DIR}/out/agg_target.nc","${BASE_DIR}/out/tas_weights.nc" "${BASE_DIR}/out/tasmax/TraCE_downscaled_1980_1990_climatology.nc" "${BASE_DIR}/out/tasmax/TraCE_downscaled_1980_1990_climatology_coarse.nc"
cdo -s -b F32 -P 100 remap,"${BASE_DIR}/out/agg_target.nc","${BASE_DIR}/out/tas_weights.nc" "${BASE_DIR}/out/tasmin/TraCE_downscaled_1980_1990_climatology.nc" "${BASE_DIR}/out/tasmin/TraCE_downscaled_1980_1990_climatology_coarse.nc"

