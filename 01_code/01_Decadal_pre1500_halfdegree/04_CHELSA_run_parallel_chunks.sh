#!/bin/bash

# deactivate any conda environment
conda deactivate || true

# CD
cd /home/dafcluster4/Documents/GitHub/TraCE_Sahul

# Input directories (where input data is stored)
BASE_DIR="/media/dafcluster4/storage/TraCE_22k_1500CE"
CLIM_DIR="${BASE_DIR}/clim"
ORO_DIR="${BASE_DIR}/orog"
STATIC_FOLDER="${BASE_DIR}/merc_template" # contains merc_template for each chunk

LOG_FILE="${BASE_DIR}/processing_time.txt"

# Output base  (where temporary [chunked] input data is stored)
OUTPUT_BASE="/home/dafcluster4/Documents/GitHub/TraCE_Sahul/02_data/03_CHELSA_paleo"
CLIM_OUT="${OUTPUT_BASE}/clim"
ORO_OUT="${OUTPUT_BASE}/orog"
STATIC_OUT="${OUTPUT_BASE}/static"
STATIC_FILE="${STATIC_OUT}/merc_template.nc" # needs to be created for each chunk

# Final output
FINAL_OUT="${BASE_DIR}/out"
mkdir -p "$FINAL_OUT/pr" "$FINAL_OUT/tas" "$FINAL_OUT/tasmax" "$FINAL_OUT/tasmin"

# Local temporary output dir
LOCAL_OUT="${OUTPUT_BASE}/out"
mkdir -p "$LOCAL_OUT/pr" "$LOCAL_OUT/tas" "$LOCAL_OUT/tasmax" "$LOCAL_OUT/tasmin"

# Constants
TOTAL_TIMESTEPS=25860
CHUNK_SIZE=12
TOTAL_CHUNKS=$(( (TOTAL_TIMESTEPS + CHUNK_SIZE - 1) / CHUNK_SIZE ))

# deactivate conda environment
conda deactivate || true

# Singularity setup
export SINGULARITY_IMG="/home/dafcluster4/chelsa_paleo/singularity/chelsa_paleo.sif"
export SCRIPT="/home/dafcluster4/chelsa_paleo/src/chelsa.py"
export INPUT_DIR="$OUTPUT_BASE/"
export OUTPUT_DIR="$OUTPUT_BASE/out/"
export SCRATCH_DIR="/home/dafcluster4/scratch/"

# singularity exec "$SINGULARITY_IMG" python "$SCRIPT" -t 1 -i "$INPUT_DIR" -o "$OUTPUT_DIR" -tmp "$SCRATCH_DIR" # TEST 1 timestep

# File list
CLIM_FILES=(huss.nc pr.nc ta_high.nc ta_low.nc tasmax.nc tasmin.nc tas.nc uwind.nc vwind.nc zg_high.nc zg_low.nc)
ORO_FILES=(oro.nc oro_high.nc)
MASK_FILE="/home/dafcluster4/Documents/GitHub/TraCE_Sahul/02_data/01_inputs/TraCE21_22kaBP_1500CE_mask_inttime.nc"

# Start the log file
echo "Processing started: $(date)" >"$LOG_FILE"
echo "------------------------------------------" >>"$LOG_FILE"

TOTAL_ELAPSED=0

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
    # Copy the relevant merc_template
    STATIC_FILE_SRC="${STATIC_FOLDER}/merc_template_$(printf '%04d' "$aux_step").nc"
    cp "$STATIC_FILE_SRC" "$STATIC_FILE"
    # Copy the relevant mask
    MASK_OUT="${INPUT_DIR}mask_${aux_step}.nc"
    mask_aux="${aux_step}"
    if ((mask_aux > 2151)); then
        mask_aux=2151
    fi
    cdo -L -w -s remapnn,/media/dafcluster4/storage/TraCE_1500_1990CE/1500_1990/out/pr/TraCE-Sahul_1500_1990_pr.nc \
        -seltimestep,"${mask_aux}" \
        "${MASK_FILE}" "${MASK_OUT}" >/dev/null 2>&1
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
    # Mask each of the output files
    conda deactivate || true
    conda activate nco_stable
    for var in pr tasmax tasmin; do
        # mask
        for FILE in "${LOCAL_OUT}/${var}"/CHELSA_${var}_*.nc; do
            cdo -s -w -L -f nc4 -b F32 \
                -div "$FILE" "$MASK_OUT" \
                "${FILE}_tmp.nc"
            cp -f "${FILE}_tmp.nc" "$FILE"
            rm "${FILE}_tmp.nc"
        done
        # concat, change units and pack
        tmp_outcat="${LOCAL_OUT}/${var}/CHELSA_${var}_1_V.1.0_chunk$(printf '%04d' "$aux_step").nc"
        if [[ $var = "pr" ]]; then            
            cdo -f nc4 -b U16 -P 100 -L -w -s -O \
                -pack \
                -setunit,'mm/month' \
                -muldpm \
                -mulc,86400 \
                -settaxis,2000-01-16,,1month \
                -setcalendar,365_day \
                -cat \
                -unpack \
                $(find "${LOCAL_OUT}/${var}/" -type f -name '*.nc' | sort -V) \
                "${tmp_outcat}"
        else
            cdo -f nc4 -b I16 -P 100 -L -w -s -O \
                -pack \
                -setunit,'deg_C' \
                -subc,273.15 \
                -settaxis,2000-01-16,,1month \
                -setcalendar,365_day \
                -cat \
                -unpack \
                $(find "${LOCAL_OUT}/${var}/" -type f -name '*.nc' | sort -V) \
                "${tmp_outcat}"
        fi
    done
    # Output dir for this chunk
    TIME_DIR="${BASE_DIR}/chunk_out/$(printf "%05d_%05d" "$t" "$t_end")/out"
    mkdir -p "$TIME_DIR/pr" "$TIME_DIR/tas" "$TIME_DIR/tasmax" "$TIME_DIR/tasmin"
    # Move outputs to external chunk directory
    mv "$LOCAL_OUT/pr"/* "$TIME_DIR/pr/" 2>/dev/null || true
    mv "$LOCAL_OUT/tasmax"/* "$TIME_DIR/tasmax/" 2>/dev/null || true
    mv "$LOCAL_OUT/tasmin"/* "$TIME_DIR/tasmin/" 2>/dev/null || true
    # Clean up local output dir and scratch
    rm -rf "$MASK_OUT"
    rm -rf "$STATIC_FILE"
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
    TOTAL_ELAPSED=$((TOTAL_ELAPSED + ELAPSED))
    AVG_TIME_PER_CHUNK=$((TOTAL_ELAPSED / COMPLETED_STEPS))
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

## TO DO: ALL BELOW!

# concatentate the bias corrected files
out_dir="/media/dafcluster4/storage/TraCE_22k_1500CE"
unset variables
variables=("pr" "tasmax" "tasmin")
for var in "${variables[@]}"; do
    echo -e "${GREEN}Concatenating ${var}...${RESET}"
    # create temp file and output
    tmp_outvar=$(mktemp --suffix "_${var}_concat.nc")
    outfile="${out_dir}/out/${var}/TraCE_22ka_downscaled_${var}_decadal_21k_1500CE_biascorr.nc"
    echo -e "${BLUE}    Outfile: $(basename "$(dirname "$outfile")")/$(basename "$outfile")${RESET}"
    # store input order for debugging
    find "${input_base}"/*/out/"${var}" -type f -name '*biascorr.nc' | sort -V >"${out_dir}/${var}_concat_input_order.txt"
    # concat with CDO
    cdo -f nc4 -P 100 -L -s -O \
        -cat \
        $(find "${input_base}"/*/out/"${var}" -type f -name '*biascorr.nc' | sort -V) \
        "${tmp_outvar}"
    # set time to 1...n with ncap2
    echo -e "       ${YELLOW}Resetting time dimension...${RESET}"
    ncap2 --4 -O -s 'time=array(1.0f,1.0f,$time); time@units=""' "${tmp_outvar}" "${tmp_outvar}"
    # compress output
    echo -e "       ${YELLOW}Packing output file...${RESET}"
    cdo -f nc4 -s -L -O -P 100 pack "${tmp_outvar}" "${outfile}"
    rm -f "${tmp_outvar}"
    echo -e "${GREEN}Finished variable: ${var}${RESET}"
done

# Split the files into chunks
base_dir="/media/dafcluster4/storage/TraCE_22k_1500CE/out"
vars=(pr tasmax tasmin)

# split the decadal data into 6 files
chunk_sizes=(4812 4812 4812 4812 4812 1800) # final chunk will contain only 1800 layers
for var in "${vars[@]}"; do
    infile="${base_dir}/${var}/TraCE_22ka_downscaled_${var}_decadal_21k_1500CE_biascorr.nc"
    echo -e "${GREEN}Splitting $var...${RESET}"
    start=1
    chunk_id=1
    for chunk in "${chunk_sizes[@]}"; do
        end=$(( start + chunk - 1 ))
        outfile="${base_dir}/${var}/TraCE_22ka_downscaled_${var}_decadal_21k_1500CE_biascorr_$(printf "%02d" $chunk_id).nc"
        echo -e "${YELLOW}      Creating $(basename "$(dirname "$outfile")")/$(basename "$outfile") (time ${start}-${end}${RESET})"
        # Use CDO to extract the chunk range
        cdo -f nc4 -P 100 -L seltimestep,${start}/${end} "$infile" "$outfile"
        start=$(( end + 1 ))
        ((chunk_id++))
    done
    echo "  Final timestep processed: $end"
    echo -e "${GREEN}Finished $var...${RESET}"
done

# Now pass the split files through the R script to correct the time-index
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