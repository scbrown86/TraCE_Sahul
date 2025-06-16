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
    delta_file=$(find "$delta_base" -type f -name "delta_fine_delta_${var}_climatology_ncdf4.nc" | head -n 1)

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

    # make temporary files
    tmp_unpacked=$(mktemp --suffix "_${var}_unpacked.nc")
    tmp_delta=$(mktemp --suffix "_${var}_remap.nc")
    tmp_biascorr=$(mktemp --suffix "_${var}_biascorr.nc")
    grid_desc=$(mktemp --suffix ".txt")

    # unpack input to remove offset and scale
    cdo -b F32 unpack "$input_file" "$tmp_unpacked"

    # remap delta to ensure that grids align
    # Could probably use remapnn as there should be no actual regridding?
    if [[ $var == "pr" ]]; then
        remap_method="remapcon"
    else
        remap_method="remapbil"
    fi
    cdo griddes "$input_file" >"$grid_desc"
    cdo -P 64 -s "$remap_method","$grid_desc" "$delta_file" "$tmp_delta"

    # apply the bias correction
    if [[ $var == "pr" ]]; then
        cdo -b F32 \
            -setreftime,1600-01-16,,1month \
            -settaxis,1600-01-16,,1month \
            -setcalendar,365_day \
            -setunit,'mm/month' \
            -muldpm \
            -mulc,86400 \
            -mul "$tmp_unpacked" "$tmp_delta" "$tmp_biascorr"
    else
        cdo -b F32 \
            -setreftime,1600-01-16,,1month \
            -settaxis,1600-01-16,,1month \
            -setcalendar,365_day \
            -setunit,'deg_C' \
            -subc,273.15 \
            -add "$tmp_unpacked" "$tmp_delta" "$tmp_biascorr"
    fi
    # pack once bias corrected
    output_file="$input_base/$var/CHELSA_${var}_1600_1990_biascorr.nc"
    cdo pack "$tmp_biascorr" "$output_file"
    # delete temp files
    rm -rf "$tmp_unpacked" "$tmp_delta" "$tmp_biascorr" "$grid_desc"
    echo "Finished $var: $output_file"
done
