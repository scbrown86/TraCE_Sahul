#!/bin/bash

cd "/home/dafcluster4/Documents/GitHub/TraCE_Sahul/" || {
    echo "Failed to change directory. Exiting."
    exit 1
}

conda deactivate
conda activate nco_stable

input_base="/media/dafcluster4/storage/TraCE_1500_1990CE/1500_1990/out"
delta_base="02_data/02_processed/deltas"
variables=("pr" "tas")

for var in "${variables[@]}"; do
    if [[ $var == "tas" ]]; then
        input_file_tasmax=$(find "$input_base/$var"max -type f -name "*_1500_1990_concat.nc" | head -n 1)
        input_file_tasmin=$(find "$input_base/$var"min -type f -name "*_1500_1990_concat.nc" | head -n 1)
        delta_file=$(find "$delta_base" -type f -name "delta_fine_delta_${var}_climatology_ncdf4.nc" | head -n 1)
        delta_file_dtr=$(find "$delta_base" -type f -name "delta_fine_delta_dtr_climatology_ncdf4.nc" | head -n 1)
        if [[ ! -f "$input_file_tasmax" ]]; then
            echo "Input file for variable '$var' not found."
            continue
        fi
        echo "Processing variable: $var"
        echo "Inputs: $(basename $input_file_tasmax), $(basename $input_file_tasmin)"
        echo "Deltas: $(basename $delta_file), $(basename $delta_file_dtr)"
        # make temporary files
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
        # unpack inputs to remove offset and scale
        echo "Unpacking $(basename ${input_file_tasmax}) to ${tmp_unpacked_tasmax}..."
        cdo -L -w -P 100 -b F32 unpack "$input_file_tasmax" "$tmp_unpacked_tasmax"

        echo "Unpacking $(basename ${input_file_tasmin}) to ${tmp_unpacked_tasmin}..."
        cdo -L -w -P 100 -b F32 unpack "$input_file_tasmin" "$tmp_unpacked_tasmin"
        # remap delta to ensure that grids align
        # use remapnn as there should be no actual regridding?
        echo "aligning deltas for: $var"
        remap_method="remapnn"
        cdo griddes "$input_file_tasmax" >"$grid_desc"
        cdo -P 100 -s -w "$remap_method","$grid_desc" "$delta_file" "$tmp_delta_tas"
        cdo -P 100 -s -w "$remap_method","$grid_desc" "$delta_file_dtr" "$tmp_delta_dtr"
        # apply the bias correction
        echo "bias correcting: $var"
        ## first step is to calculate tas
        cdo -O -b F32 -P 100 \
            -settaxis,1500-01-16,,1month \
            -setcalendar,365_day \
            -setunit,'deg_C' \
            -subc,273.15 \
            -ensmean "$tmp_unpacked_tasmax" "$tmp_unpacked_tasmin" \
            $tmp_unpacked_tas
        ## then add the tas delta to $tmp_unpacked_tas
        cdo -O -b F32 -P 100 \
            -add "$tmp_unpacked_tas" "$tmp_delta_tas" \
            "$tmp_biascorr" # this is biascorrected tas
        ## Now need to calculate DTR. Set any values < 0.05°C to 0.05°C
        echo "calculating and bias correcting diurnal temperature range..."
        cdo -O -b F32 -P 100 \
            -expr,'dtr=((dtr<0.05)?0.05:dtr)' \
            -setunit,'.' \
            -setname,"dtr" \
            -sub "$tmp_unpacked_tasmax" "$tmp_unpacked_tasmin" \
            "$tmp_dtr"
        ## now correct the dtr
        cdo -O -b F32 -P 100 \
            -mul "$tmp_dtr" "$tmp_delta_dtr" \
            "$tmp_biascorr_dtr" # this is biascorrected dtr
        ## calculate half the dtr so we can calc a new min and max
        cdo -O -b F32 -P 100 \
            -mulc,0.5 "$tmp_biascorr_dtr" \
            "$tmp_biascorr_halfdtr" # this is half biascorrected dtr
        # Calculate a new min/max
        ## biascorrect_tas +/- 0.5dtr
        echo "calculating bias corrected maximum temperature..."
        cdo -O -b F32 -P 100 \
            -setunit,"Celcius" \
            -setname,"tasmax" \
            -add "$tmp_biascorr" "$tmp_biascorr_halfdtr" \
            "$tmp_biascorr_tasmax" # this is biascorrected max tas
        ncatted -O \
            -a long_name,tasmax,o,c,"Daily Maximum Near-Surface Air Temperatures" \
            -a standard_name,tasmax,o,c,"maximum_air_temperature" \
            "$tmp_biascorr_tasmax"
        echo "calculating bias corrected minimum temperature..."
        cdo -O -b F32 -P 100 \
            -setunit,"Celcius" \
            -setname,"tasmin" \
            -sub "$tmp_biascorr" "$tmp_biascorr_halfdtr" \
            "$tmp_biascorr_tasmin" # this is biascorrected min tas
        ncatted -O \
            -a long_name,tasmin,o,c,"Daily Minimum Near-Surface Air Temperatures" \
            -a standard_name,tasmin,o,c,"minimum_air_temperature" \
            "$tmp_biascorr_tasmin"
        # pack once bias corrected
        ## only store in 2 decimal places
        output_tasmax="$input_base/tasmax/TraCE_22ka_downscaled_tasmax_1500_1990_biascorr.nc"
        output_tasmin="$input_base/tasmin/TraCE_22ka_downscaled_tasmin_1500_1990_biascorr.nc"
        echo "Copying and packing bias corrected files to $(basename ${output_tasmax}), $(basename ${output_tasmin})"
        ncap2 --4 -t 100 -O -s 'tasmax=short(tasmax/0.01); tasmax@scale_factor=0.01' "$tmp_biascorr_tasmax" "${output_tasmax}"
        ncap2 --4 -t 100 -O -s 'tasmin=short(tasmin/0.01); tasmin@scale_factor=0.01' "$tmp_biascorr_tasmin" "${output_tasmin}"
        # delete temp files
        echo "Deleting temporary files..."
        rm -f "$tmp_unpacked_tasmax" "$tmp_unpacked_tasmin" "$tmp_unpacked_tas" \
            "$tmp_delta_tas" "$tmp_delta_dtr" "$tmp_biascorr" "$tmp_dtr" \
            "$tmp_biascorr_dtr" "$tmp_biascorr_halfdtr" "$tmp_biascorr_tasmax" \
            "$tmp_biascorr_tasmin" "$grid_desc"
    else
        input_file=$(find "$input_base/$var" -type f -name "*_1500_1990_concat.nc" | head -n 1)
        delta_file=$(find "$delta_base" -type f -name "delta_fine_delta_${var}_climatology_ncdf4.nc" | head -n 1)
        if [[ ! -f "$input_file" ]]; then
            echo "Input file for variable '$var' not found."
            continue
        fi
        echo "Processing variable: $var"
        echo "Input: $(basename $input_file)"
        echo "Delta: $(basename $delta_file)"
        # make temporary files
        tmp_unpacked=$(mktemp --suffix "_${var}_unpacked.nc")
        tmp_delta=$(mktemp --suffix "_${var}_remap.nc")
        tmp_biascorr=$(mktemp --suffix "_${var}_biascorr.nc")
        grid_desc=$(mktemp --suffix ".txt")
        # unpack input to remove offset and scale
        echo "Unpacking ${input_file} to ${tmp_unpacked}..."
        cdo -L -w -P 100 -b F32 unpack "$input_file" "$tmp_unpacked"
        # remap delta to ensure that grids align
        # use remapnn as there should be no actual regridding?
        echo "aligning delta for: $var"
        remap_method="remapnn"
        cdo griddes "$input_file" >"$grid_desc"
        cdo -P 100 -s -w "$remap_method","$grid_desc" "$delta_file" "$tmp_delta"
        # apply the bias correction
        echo "bias correcting: $var"
        cdo -O -b F32 -P 100 \
            -setunit,"kg m-2 s-1" \
            -setname,"pr" \
            -settaxis,1500-01-16,,1month \
            -setcalendar,365_day \
            -mul "$tmp_unpacked" "$tmp_delta" "$tmp_biascorr"
        ncatted -O \
            -a long_name,pr,o,c,"precipitation" \
            -a standard_name,pr,o,c,"precipitation_flux" \
            "$tmp_biascorr"
        # pack once bias corrected
        output_file="$input_base/$var/TraCE_22ka_downscaled_${var}_1500_1990_biascorr.nc"
        echo "Copying and packing bias corrected files to $(basename ${output_file})"
        cdo -O -P 100 -L -w -s pack "$tmp_biascorr" "$output_file"
        # delete temp files
        rm -rf "$tmp_unpacked" "$tmp_delta" "$tmp_biascorr" "$grid_desc"
    fi
    echo "Finished $var"
done
