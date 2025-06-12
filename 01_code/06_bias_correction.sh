#!/bin/bash

cd "/home/dafcluster4/Documents/GitHub/TraCE_Sahul/" || {
    echo "Failed to change directory. Exiting."
    exit 1
}

conda deactivate
conda activate nco_stable

input_base="02_data/03_CHELSA_paleo/out"
delta_base="02_data/02_processed/deltas"

variables=("pr" "tas" "tasmax" "tasmin")

for var in "${variables[@]}"; do
    input_file=$(find "$input_base/$var" -type f -name "*_1600_1990.nc" | head -n 1)
    delta_file=$(find "$delta_base" -type f -name "delta_fine_delta_${var}_climatology.nc" | head -n 1)
    if [[ ! -f "$input_file" ]]; then
        echo "Input file for variable '$var' not found."
        continue
    fi
    if [[ ! -f "$delta_file" ]]; then
        echo "Delta file for variable '$var' not found."
        continue
    fi
    echo "Processing variable: $var"
    echo "Input: $input_file"
    echo "Delta: $delta_file"
    # Define output path
    output_file="$input_base/${var}/CHELSA_${var}_1600_1990_biascorr.nc"
    # Temporary remapped delta file
    tmp_delta="delta_remapped_tmp.nc"
    # Grid description of $delta_files is wrong (terra issue).
    # Set it to lat/lon
    cdo griddes $input_file >grid_desc.txt
    cdo setgrid,grid_desc.txt $delta_file $tmp_delta
    # Apply bias correction
    if [[ "$var" == "pr" ]]; then
        # if pr, convert to mm/month after applying bias correction
        cdo -b F32 \
            -pack \
            -setreftime,1600-01-16,,1month \
            -settaxis,1600-01-16,,1month \
            -setcalendar,365_day \
            -setunit,'mm/month' \
            -muldpm \
            -mulc,86400 \
            -mul "$input_file" "$tmp_delta" "$output_file"
    else
        # if temperature, convert to celcius after applying bias correction
        cdo -b F32 \
            -pack \
            -setreftime,1600-01-16,,1month \
            -settaxis,1600-01-16,,1month \
            -setcalendar,365_day \
            -setunit,'deg_C' \
            -subc,-273.15 \
            -add "$input_file" "$tmp_delta" "$output_file"
    fi
    # Clean up temporary file
    rm -f "$tmp_delta" "grid_desc.txt"
done
