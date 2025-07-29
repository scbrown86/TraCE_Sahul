#!/bin/bash

cd "/media/dafcluster4/storage/TraCE_1500_1990CE/" || {
    echo "Failed to change directory. Exiting."
    exit 1
}

conda deactivate
conda activate nco_stable

input_base="1500_1600/03_CHELSA_paleo/out"
input_extra="1600_1990/03_CHELSA_paleo/out"
variables=("pr" "tas" "tasmax" "tasmin")

for var in "${variables[@]}"; do
    input_t1=$(find "$input_base/$var" -type f -name "*_1500_1600_biascorr.nc" | head -n 1)
    input_t2=$(find "$input_extra/$var" -type f -name "*_1600_1990_biascorr.nc" | head -n 1)
    if [[ ! -f "$input_t1" ]]; then
        echo "Input file for variable '$var' not found."
        continue
    fi
    if [[ ! -f "$input_t2" ]]; then
        echo "Delta file for variable '$var' not found."
        continue
    fi
    echo "Processing variable: $var"
    echo "1500-1600: $input_t1"
    echo "1600-1990: $input_t2"
    # make temporary files
    tmp_unpacked_t1=$(mktemp --suffix "_${var}_unpacked_t1.nc")
    tmp_unpacked_t2=$(mktemp --suffix "_${var}_unpacked_t2.nc")
    tmp_merged=$(mktemp --suffix "_${var}_merged.nc")
    # unpack inputs to remove offset and scale
    cdo -b F32 unpack "$input_t1" "$tmp_unpacked_t1"
    cdo -b F32 unpack "$input_t2" "$tmp_unpacked_t2"
    # merge the unpacked files
    cdo -b F32 mergetime "$tmp_unpacked_t1" "$tmp_unpacked_t2" "$tmp_merged"
    # pack once merged
    output_file="CHELSA_${var}_1500_1990_biascorr.nc"
    cdo -P 36 pack "$tmp_merged" "$output_file"
    # delete temp files
    rm -rf "$tmp_unpacked_t1" "$tmp_unpacked_t2" "$tmp_merged"
    echo "Finished $var: $output_file"
done
