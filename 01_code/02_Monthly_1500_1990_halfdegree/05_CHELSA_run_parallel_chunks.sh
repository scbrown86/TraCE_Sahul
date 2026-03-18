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

variables=("pr" "tasmax" "tasmin")
mask="${BASE_DIR}/orog/oro_mask.nc"
mask_cf="${BASE_DIR}/orog/oro_mask_cf.nc"
first_file=$(find "${BASE_DIR}"/chunk_out/*/out/pr -type f -name '*.nc' | sort -V | head -1)

# set the static mask
gdal_translate \
    -of netCDF \
    -mo "long_name=mask" \
    /home/dafcluster4/Documents/GitHub/TraCE_Sahul/02_data/02_processed/oro_mask.tif \
    ${mask}
ncrename -v Band1,mask ${mask}
cdo -s -w -L -b F32 setmisstoc,0 \
    -remapnn,"${first_file}" \
    "${mask}" \
    "${mask_cf}"

for var in "${variables[@]}"; do
    echo "processing variable: ${var}..."
    outfile="${BASE_DIR}/out/${var}/TraCE-Sahul_1500_1990_${var}.nc"
    outfileM="${BASE_DIR}/out/${var}/TraCE-Sahul_1500_1990_${var}_masked.nc"
    outclim="${BASE_DIR}/out/${var}/TraCE-Sahul_1980_1990_${var}_climatology.nc"
    outclim2="${BASE_DIR}/out/${var}/TraCE-Sahul_1910_1990_${var}_climatology.nc"
    if [[ ! -e "${outfile}" ]]; then
        echo "outfile = ${outfile}"
        find "${BASE_DIR}"/chunk_out/*/out/"${var}" -type f -name '*.nc' | sort -V >"${BASE_DIR}/${var}_concat_input_order.txt"
        if [[ $var = "pr" ]]; then
            echo "concatenating variable: ${var}..."
            cdo -s -w -O -L -b F32 \
                -setunit,'mm/month' \
                -muldpm \
                -mulc,86400 \
                -settaxis,1500-01-16,,1month \
                -setcalendar,365_day \
                -cat \
                -unpack \
                $(find "${BASE_DIR}"/chunk_out/*/out/"${var}" -type f -name '*.nc' | sort -V) \
                "${outfile}"
            echo "masking variable: ${var}..."
            cdo -s -w -O -L div "${outfile}" "${mask_cf}" "${outfileM}"
            echo "packing variable: ${var}..."
            cdo -f nc4 -P 100 -L -w -s -O -b U16 pack "${outfileM}" "${outfile}"
            rm -rf "${outfileM}"
        else
            echo "concatenating variable: ${var}..."
            cdo -s -w -O -L \
                -setunit,'deg_C' \
                -subc,273.15 \
                -settaxis,1500-01-16,,1month \
                -setcalendar,365_day \
                -cat \
                -unpack \
                $(find "${BASE_DIR}"/chunk_out/*/out/"${var}" -type f -name '*.nc' | sort -V) \
                "${outfile}"
            echo "masking variable: ${var}..."
            cdo -s -w -O -L div "${outfile}" "${mask_cf}" "${outfileM}"
            echo "packing variable: ${var}..."
            cdo -f nc4 -P 100 -L -w -s -O -b I16 pack "${outfileM}" "${outfile}"
            rm -rf "${outfileM}"
        fi
    else
        echo "skipping concat for ${var}: ${outfile} already exists"
    fi
    echo "Calculating climatologies for variable: ${var}..."
    if [[ ! -e "${outclim}" ]]; then
        cdo -s -w -O -L \
            -ymonmean \
            -selyear,1980/1989 \
            "${outfile}" "${outclim}"
        if [[ $var = "pr" ]]; then
            cdo -f nc4 -P 100 -L -w -s -O -b U16 \
                pack "${outclim}" "${outclim}_tmp.nc"
        else
            cdo -f nc4 -P 100 -L -w -s -O -b I16 \
                pack "${outclim}" "${outclim}_tmp.nc"
        fi
        mv "${outclim}_tmp.nc" "${outclim}"
    else
        echo "skipping climatology: ${outclim} already exists"
    fi
    if [[ ! -e "${outclim2}" ]]; then
        cdo -s -w -O -L \
            -ymonmean \
            -selyear,1910/1989 \
            "${outfile}" "${outclim2}"
        if [[ $var = "pr" ]]; then
           cdo -f nc4 -P 100 -L -w -s -O -b U16 \
                pack "${outclim2}" "${outclim2}_tmp.nc"
        else
           cdo -f nc4 -P 100 -L -w -s -O -b I16 \
                pack "${outclim2}" "${outclim2}_tmp.nc"
        fi
        mv "${outclim2}_tmp.nc" "${outclim2}"
    else
        echo "skipping climatology: ${outclim2} already exists"
    fi
    echo "Done for variable: ${var}"
done