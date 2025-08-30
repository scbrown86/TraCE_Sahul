#!/bin/bash

# ================================================================================
# IMPORTANT:
# Monthly data downscaling must be done before bias-correcting the decadal data!
#
# Run all scripts in 01_code/02_Monthly_1500_1990/ up to and including:
# '02_Monthly_1500_1990/05_process_CHELSA_climatology.R' before proceeding.
# ================================================================================

# List of required delta files
required_delta_files=(
    "/home/dafcluster4/Documents/GitHub/TraCE_Sahul/02_data/02_processed/deltas/delta_fine_delta_pr_climatology_ncdf4.nc"
    "/home/dafcluster4/Documents/GitHub/TraCE_Sahul/02_data/02_processed/deltas/delta_fine_delta_tas_climatology_ncdf4.nc"
    "/home/dafcluster4/Documents/GitHub/TraCE_Sahul/02_data/02_processed/deltas/delta_fine_delta_dtr_climatology_ncdf4.nc")

# Check that delta files exist or exit.
for file in "${required_delta_files[@]}"; do
    if [[ ! -f "$file" ]]; then
        echo "ERROR: Required file not found: $file"
        echo ""
        echo "IMPORTANT:"
        echo "Monthly data downscaling must be completed before bias-correcting the decadal data!"
        echo "Run all scripts up to and including:"
        echo "'02_Monthly_1500_1990/05_process_CHELSA_climatology.R' before proceeding."
        exit 1
    fi
done

cd "/media/dafcluster4/storage/TraCE_22k_1500CE/" || {
    echo "Failed to change directory. Exiting."
    exit 1
}

conda deactivate || true
conda activate nco_stable

# Colours
GREEN="\033[0;32m"
RED="\033[0;31m"
YELLOW="\033[1;33m"
RESET="\033[0m"


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

            concat_tasmax="${tasmax_dir}/CHELSA_tasmax_${chunk_name}_concat.nc"
            concat_tasmin="${tasmin_dir}/CHELSA_tasmin_${chunk_name}_concat.nc"

            echo "Concatenating tasmax in ${chunk_name} ..."
            cdo -s -w -b F32 -P 100 -O cat $(ls -v1 "${tasmax_dir}"/*.nc) "$concat_tasmax"

            echo "Concatenating tasmin in ${chunk_name} ..."
            cdo -s -w -b F32 -P 100 -O cat $(ls -v1 "${tasmin_dir}"/*.nc) "$concat_tasmin"
        else
            concat_file="${var_dir}/CHELSA_${var}_${chunk_name}_concat.nc"
            echo "Concatenating ${var} in ${chunk_name} ..."
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

            echo "Bias correcting: $var"
            echo "      Inputs: $(basename $input_file_tasmax), $(basename $input_file_tasmin)"
            echo "      Deltas: $(basename $delta_file), $(basename $delta_file_dtr)"

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
                -settaxis,1500-01-16,,1month \
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

            cdo -O -b F32 -P 100  -s -w \
                -setunit,"Celcius" -setname,"tasmax" \
                -add "$tmp_biascorr" "$tmp_biascorr_halfdtr" \
                "$tmp_biascorr_tasmax"
            ncatted -O \
                -a long_name,tasmax,o,c,"Daily Maximum Near-Surface Air Temperatures" \
                -a standard_name,tasmax,o,c,"maximum_air_temperature" \
                "$tmp_biascorr_tasmax"

            cdo -O -b F32 -P 100  -s -w \
                -setunit,"Celcius" -setname,"tasmin" \
                -sub "$tmp_biascorr" "$tmp_biascorr_halfdtr" \
                "$tmp_biascorr_tasmin"
            ncatted -O \
                -a long_name,tasmin,o,c,"Daily Minimum Near-Surface Air Temperatures" \
                -a standard_name,tasmin,o,c,"minimum_air_temperature" \
                "$tmp_biascorr_tasmin"

            # dont pack, but copy
            cdo -O -P 100 -L -w -s copy "$tmp_biascorr_tasmax" "$output_tasmax"
            cdo -O -P 100 -L -w -s copy "$tmp_biascorr_tasmin" "$output_tasmin"
            
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

            echo "Bias correcting: $var"
            echo "      Input: $(basename $input_file)"
            echo "      Delta: $(basename $delta_file)"

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
            cdo -O -P 100 -L -s -w copy "$tmp_biascorr" "$output_file"
            # delete temp files
            rm -rf "$tmp_unpacked" "$tmp_delta" "$tmp_biascorr" "$grid_desc"
        fi
    done
    echo -e "${YELLOW}Finished chunk: ${chunk_name}${RESET}"
done


# concatentate the bias corrected files
out_dir="/media/dafcluster4/storage/TraCE_22k_1500CE"
for var in "${variables[@]}"; do
    echo "processing variable: ${var}..."

    outfile="${out_dir}/out/${var}/TraCE_22ka_downscaled_${var}_decadal_21k_1500CE_biascorr.nc"
    echo "outfile = ${outfile}"

    find "${input_base}"/*/out/"${var}" -type f -name '*biascorr.nc' | sort -V >"${out_dir}/${var}_concat_input_order.txt"

    cdo -P 100 -L -s -O --absolute_taxis pack -cat -unpack \
        $(find "${input_base}"/*/out/"${var}" -type f -name '*biascorr.nc' | sort -V) \
        "${outfile}"

    echo "resetting time dimension..."
    ncap2 -O -s 'time=array(1,1,$time); time@units=""' "${outfile}" "${outfile}"

    echo "Done for variable: ${var}"
done
