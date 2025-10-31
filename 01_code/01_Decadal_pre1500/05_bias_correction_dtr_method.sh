#!/bin/bash

# ================================================================================
# IMPORTANT:
# Monthly data downscaling must be done before bias-correcting the decadal data!
#
# Run all scripts in 01_code/02_Monthly_1500_1990/ up to and including:
# '02_Monthly_1500_1990/05_process_CHELSA_climatology.R' before proceeding.
# ================================================================================

# Colours
RED="\033[38;5;196m"
BLUE="\033[38;5;33m"
YELLOW="\033[38;5;226m"
GREEN="\033[38;5;34m"
RESET="\033[0m"

# List of required delta files
required_delta_files=(
    "/home/dafcluster4/Documents/GitHub/TraCE_Sahul/02_data/02_processed/deltas/delta_fine_delta_pr_climatology_ncdf4.nc"
    "/home/dafcluster4/Documents/GitHub/TraCE_Sahul/02_data/02_processed/deltas/delta_fine_delta_tas_climatology_ncdf4.nc"
    "/home/dafcluster4/Documents/GitHub/TraCE_Sahul/02_data/02_processed/deltas/delta_fine_delta_dtr_climatology_ncdf4.nc")

# Check that delta files exist or exit.
for file in "${required_delta_files[@]}"; do
    if [[ ! -f "$file" ]]; then
        echo -e "${RED}ERROR: Required file not found: $(basename $file)${RESET}"
        echo ""
        echo -e "${YELLOW}IMPORTANT:${RESET}"
        echo -e "${YELLOW}Monthly data downscaling must be completed before bias-correcting the decadal data! ${RESET}"
        echo -e "${YELLOW}Run all scripts up to and including:${RESET}"
        echo -e "${YELLOW}'02_Monthly_1500_1990/05_process_CHELSA_climatology.R' before proceeding.${RESET}"
        exit 1
    fi
done

cd "/media/dafcluster4/storage/TraCE_22k_1500CE/" || {
    echo "Failed to change directory. Exiting."
    exit 1
}

conda deactivate || true
conda activate nco_stable

input_base="/media/dafcluster4/storage/TraCE_22k_1500CE/chunk_out"
delta_base="/home/dafcluster4/Documents/GitHub/TraCE_Sahul/02_data/02_processed/deltas"
# variables to process
variables=("tas" "pr")

for chunk_dir in "${input_base}"/[0-9][0-9][0-9][0-9][0-9]_[0-9][0-9][0-9][0-9][0-9]; do
    chunk_name=$(basename "$chunk_dir") # e.g. 00001_00012
    out_dir="${chunk_dir}/out"
    echo -e "${YELLOW}Processing chunk: ${chunk_name}${RESET}"
    # Concatenate inputs within each chunk
    for var in "${variables[@]}"; do
        var_dir="${out_dir}/${var}"

        if [[ $var == "tas" ]]; then
            tasmax_dir="${out_dir}/tasmax"
            tasmin_dir="${out_dir}/tasmin"

            # check the number of files before processing any further
            nfiles_tasmax=$(find "$tasmax_dir" -maxdepth 1 -type f -name "*.nc" | wc -l)
            if [[ $nfiles_tasmax -ne 12 ]]; then
                echo -e "${RED}ERROR: ${tasmax_dir} has ${nfiles_tasmax} files (expected 12). Stopping.${RESET}"
                exit 1
            fi
            nfiles_tasmin=$(find "$tasmin_dir" -maxdepth 1 -type f -name "*.nc" | wc -l)
            if [[ $nfiles_tasmin -ne 12 ]]; then
                echo -e "${RED}ERROR: ${tasmin_dir} has ${nfiles_tasmin} files (expected 12). Stopping.${RESET}"
                exit 1
            fi
            # concat outputs
            concat_tasmax="${tasmax_dir}/CHELSA_tasmax_${chunk_name}_concat.nc"
            concat_tasmin="${tasmin_dir}/CHELSA_tasmin_${chunk_name}_concat.nc"
            echo -e "${GREEN}   Concatenating tasmax in ${chunk_name} ...${RESET}"
            cdo -s -w -b F32 -P 100 -O cat $(ls -v1 "${tasmax_dir}"/*.nc) "$concat_tasmax"
            echo -e "${GREEN}   Concatenating tasmin in ${chunk_name} ...${RESET}"
            cdo -s -w -b F32 -P 100 -O cat $(ls -v1 "${tasmin_dir}"/*.nc) "$concat_tasmin"
        else
            concat_file="${var_dir}/CHELSA_${var}_${chunk_name}_concat.nc"
            echo -e "   ${GREEN}Concatenating ${var} in ${chunk_name}...${RESET}"
            cdo -s -w -b F32 -P 100 -O cat $(ls -v1 "${var_dir}"/*.nc) "$concat_file"
        fi
    done
    # Now do the bias correction
    for var in "${variables[@]}"; do
        if [[ $var == "tas" ]]; then
            input_file_tasmax="${out_dir}/tasmax/CHELSA_tasmax_${chunk_name}_concat.nc"
            input_file_tasmin="${out_dir}/tasmin/CHELSA_tasmin_${chunk_name}_concat.nc"
            delta_file=$(find "$delta_base" -type f -name "delta_fine_delta_${var}_climatology_ncdf4.nc" | head -n 1)
            delta_file_dtr=$(find "$delta_base" -type f -name "delta_fine_delta_dtr_climatology_ncdf4.nc" | head -n 1)
            if [[ ! -f "$input_file_tasmax" ]]; then
                echo "Input file for tasmax not found."
                continue
            fi
            echo -e "${GREEN}  Bias correcting: $var${RESET}"
            echo -e "${BLUE}      Inputs: $(basename "$(dirname "$input_file_tasmax")")/$(basename "$input_file_tasmax"), \
                    $(basename "$(dirname "$input_file_tasmin")")/$(basename "$input_file_tasmin")${RESET}"
            echo -e "${BLUE}      Deltas: $(basename "$(dirname "$delta_file")")/$(basename "$delta_file"), \
                    $(basename "$(dirname "$delta_file_dtr")")/$(basename "$delta_file_dtr")${RESET}"
            # temp files
            tmp_unpacked_tasmax=$(mktemp --suffix "_tasmax_unpacked.nc")
            tmp_unpacked_tasmin=$(mktemp --suffix "_tasmin_unpacked.nc")
            tmp_unpacked_tas=$(mktemp --suffix "_tas_unpacked.nc")
            tmp_delta_tas=$(mktemp --suffix "_tas_remap.nc")
            tmp_delta_dtr=$(mktemp --suffix "_dtr_remap.nc")
            tmp_biascorr=$(mktemp --suffix "_${var}_biascorr.nc")
            tmp_dtr=$(mktemp --suffix "_dtr_unpacked.nc")
            tmp_biascorr_dtr=$(mktemp --suffix "_dtr_biascorr.nc")
            tmp_biascorr_halfdtr=$(mktemp --suffix "_halfdtr_biascorr.nc")
            tmp_biascorr_tasmax=$(mktemp --suffix "_tasmax_biascorr.nc")
            tmp_biascorr_tasmin=$(mktemp --suffix "_tasmin_biascorr.nc")
            grid_desc=$(mktemp --suffix ".txt")
            # unpack
            cdo -L -w -P 100 -s -b F32 unpack "$input_file_tasmax" "$tmp_unpacked_tasmax"
            cdo -L -w -P 100 -s -b F32 unpack "$input_file_tasmin" "$tmp_unpacked_tasmin"
            # align deltas
            remap_method="remapnn"
            cdo griddes "$input_file_tasmax" >"$grid_desc"
            cdo -P 100 -s -w -L "$remap_method","$grid_desc" "$delta_file" "$tmp_delta_tas"
            cdo -P 100 -s -w -L "$remap_method","$grid_desc" "$delta_file_dtr" "$tmp_delta_dtr"
            # calculate tas = mean(tasmax,tasmin)
            cdo -O -b F32 -P 100 -s -w \
                -settaxis,2000-01-16,,1month \
                -setcalendar,365_day \
                -setunit,'deg_C' \
                -subc,273.15 \
                -ensmean "$tmp_unpacked_tasmax" "$tmp_unpacked_tasmin" \
                "$tmp_unpacked_tas"
            # add tas delta
            cdo -O -b F32 -P 100 -s -w -add "$tmp_unpacked_tas" "$tmp_delta_tas" "$tmp_biascorr"
            # dtr and correction
            cdo -O -b F32 -P 100 -s -w \
                -expr,'dtr=((dtr<0.05)?0.05:dtr)' \
                -setunit,'.' \
                -setname,"dtr" \
                -sub "$tmp_unpacked_tasmax" "$tmp_unpacked_tasmin" \
                "$tmp_dtr"
            cdo -O -b F32 -P 100 -s -w -mul "$tmp_dtr" "$tmp_delta_dtr" "$tmp_biascorr_dtr"
            cdo -O -b F32 -P 100 -s -w -mulc,0.5 "$tmp_biascorr_dtr" "$tmp_biascorr_halfdtr"
            # corrected tasmax / tasmin
            output_tasmax="${out_dir}/tasmax/CHELSA_tasmax_${chunk_name}_concat_biascorr.nc"
            output_tasmin="${out_dir}/tasmin/CHELSA_tasmin_${chunk_name}_concat_biascorr.nc"
            cdo -O -b F32 -P 100 -s -w \
                -setunit,"Celcius" -setname,"tasmax" \
                -add "$tmp_biascorr" "$tmp_biascorr_halfdtr" \
                "$tmp_biascorr_tasmax"
            ncatted -O \
                -a long_name,tasmax,o,c,"Daily Maximum Near-Surface Air Temperatures" \
                -a standard_name,tasmax,o,c,"maximum_air_temperature" \
                "$tmp_biascorr_tasmax"

            cdo -O -b F32 -P 100 -s -w \
                -setunit,"Celcius" -setname,"tasmin" \
                -sub "$tmp_biascorr" "$tmp_biascorr_halfdtr" \
                "$tmp_biascorr_tasmin"
            ncatted -O \
                -a long_name,tasmin,o,c,"Daily Minimum Near-Surface Air Temperatures" \
                -a standard_name,tasmin,o,c,"minimum_air_temperature" \
                "$tmp_biascorr_tasmin"
            # dont pack, but copy
            cdo -f nc4 -O -P 100 -L -w -s copy "$tmp_biascorr_tasmax" "$output_tasmax"
            cdo -f nc4 -O -P 100 -L -w -s copy "$tmp_biascorr_tasmin" "$output_tasmin"
            # cleanup
            rm -f "$tmp_unpacked_tasmax" "$tmp_unpacked_tasmin" "$tmp_unpacked_tas" \
                "$tmp_delta_tas" "$tmp_delta_dtr" "$tmp_biascorr" "$tmp_dtr" \
                "$tmp_biascorr_dtr" "$tmp_biascorr_halfdtr" "$tmp_biascorr_tasmax" \
                "$tmp_biascorr_tasmin" "$grid_desc"
        else
            input_file="${out_dir}/${var}/CHELSA_${var}_${chunk_name}_concat.nc"
            delta_file=$(find "$delta_base" -type f -name "delta_fine_delta_${var}_climatology_ncdf4.nc" | head -n 1)
            if [[ ! -f "$input_file" ]]; then
                echo "Input file for ${var} not found."
                continue
            fi
            echo -e "${GREEN}   Bias correcting: $var${RESET}"
            echo -e "${BLUE}        Input: $(basename "$(dirname "$input_file")")/$(basename "$input_file")${RESET}"
            echo -e "${BLUE}        Delta: $(basename "$(dirname "$delta_file")")/$(basename "$delta_file")${RESET}"
            # temp
            tmp_unpacked=$(mktemp --suffix "_${var}_unpacked.nc")
            tmp_delta=$(mktemp --suffix "_${var}_remap.nc")
            tmp_biascorr=$(mktemp --suffix "_${var}_biascorr.nc")
            grid_desc=$(mktemp --suffix ".txt")
            # unpack
            cdo -L -w -s -P 100 -b F32 unpack "$input_file" "$tmp_unpacked"
            # align delta
            remap_method="remapnn"
            cdo griddes "$input_file" >"$grid_desc"
            cdo -P 100 -s -w -L "$remap_method","$grid_desc" "$delta_file" "$tmp_delta"
            # bias correction
            # set arbitrary date
            cdo -O -b F32 -P 100 -s -w \
                -setunit,"kg m-2 s-1" \
                -setname,"pr" \
                -settaxis,2000-01-16,,1month \
                -setcalendar,365_day \
                -mul "$tmp_unpacked" "$tmp_delta" "$tmp_biascorr"
            ncatted -O \
                -a long_name,pr,o,c,"precipitation" \
                -a standard_name,pr,o,c,"precipitation_flux" \
                "$tmp_biascorr"
            # don't pack, but make a copy
            output_file="${out_dir}/${var}/CHELSA_${var}_${chunk_name}_concat_biascorr.nc"
            cdo -f nc4 -O -P 100 -L -s -w copy "$tmp_biascorr" "$output_file"
            # delete temp files
            rm -rf "$tmp_unpacked" "$tmp_delta" "$tmp_biascorr" "$grid_desc"
        fi
    done
    echo -e "${YELLOW}Finished chunk: ${chunk_name}${RESET}"
done

# concatentate the bias corrected files
out_dir="/media/dafcluster4/storage/TraCE_22k_1500CE"
unset variables
variables=("pr" "tasmax" "tasmin")
for var in "${variables[@]}"; do
    echo -e "${GREEN}Concatenating ${var}...${RESET}"
    # create temp file and output
    tmp_outvar=$(mktemp --suffix "_${var}_concat.nc")
    outfile="${out_dir}/out/${var}/TraCE_22ka_downscaled_${var}_decadal_21k_1500CE_biascorr.nc"
    echo -e "${BLUE}    Outfile: $(basename $outfile)${RESET}"
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

# split the decadal data into 12 files 
split_num=2155
base_dir="/media/dafcluster4/storage/TraCE_22k_1500CE/out"
vars=(pr tasmax tasmin)

for var in "${vars[@]}"; do
    infile="${base_dir}/${var}/TraCE_22ka_downscaled_${var}_decadal_21k_1500CE_biascorr.nc"
    outfile="${base_dir}/${var}/TraCE_22ka_downscaled_${var}_decadal_21k_1500CE_biascorr_"
    echo -e "${GREEN}Splitting $var...${RESET}"
    cdo -f nc4 -P 100 -L -splitsel,${split_num} "$infile" "$outfile"
done

# Now pass the split files through the R script to correct the time-index
conda deactivate # need to deactivate the nco_stable env to use R
for var in "${vars[@]}"; do
    echo -e "${GREEN}Processing $var...${RESET}"
    files=$(ls ${base_dir}/${var}/*.nc | grep "biascorr\\.nc$")
    for f in $files; do
        echo -e "${YELLOW} Processing $(basename "$f")...${RESET}"
        Rscript /home/dafcluster4/Documents/GitHub/TraCE_Sahul/01_code/01_Decadal_pre1500/06_split_and_add_timedims.R "$f"
        echo -e "${YELLOW} Finished $(basename "$f")...${RESET}"
    done
    echo -e "${GREEN}Finished $var...${RESET}"
done
