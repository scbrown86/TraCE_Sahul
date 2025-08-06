#!/bin/bash

conda activate nco_stable

# Define paths
base_dir="/mnt/Data/TraCE21_Sahul"
output_dir="/media/dafcluster4/storage/TraCE_Monthly"

cd "$base_dir" || exit 1

# Loop over each subdirectory
for folder in */; do
    var="${folder%/}" # Remove trailing slash to get the variable name
    if [[ "$var" == "LANDFRAC" ]]; then
        continue
    fi
    echo "$var"
    # make the output dir
    mkdir -p "$output_dir/$var"
    # Construct expected file path
    infile="${base_dir}/${var}/trace.01-36.22000BP-1990CE.cam2.h0.${var}.0000101-2204012.Sahul.concat.nc"
    # Check if file exists
    if [[ ! -f "$infile" ]]; then
        echo "File not found for variable $var: $infile"
        continue
    fi
    echo "Processing $infile"
    # Create output filename
    oname="$(basename "$infile" .nc)"
    outname="${output_dir}/${var}/${oname}.1500_1989CE.nc"
    # Run CDO processing based on variable
    # the inputs have already been remapped, cropped to Sahul, and adjusted as needed
    # just need to grab the appropriate timesteps and reset the calendar
    if [[ "$var" == "T" || "$var" == "Z3" ]]; then
        cdo -w -s -L -setreftime,1500-01-16,,1month \
            -settaxis,1500-01-16,,1month \
            -setcalendar,365_day \
            -seltimestep,258601/264480 \
            "$infile" "$outname"
    elif [[ "$var" == "RELHUM" || "$var" == "U" || "$var" == "V" ]]; then
        cdo -w -s -L --reduce_dim \
            -setreftime,1500-01-16,,1month \
            -settaxis,1500-01-16,,1month \
            -setcalendar,365_day \
            -seltimestep,258601/264480 \
            "$infile" "$outname"
    elif [[ "$var" == "PRECC" || "$var" == "PRECL" ]]; then
        cdo -w -s -L -setreftime,1500-01-16,,1month \
            -settaxis,1500-01-16,,1month \
            -setcalendar,365_day \
            -seltimestep,258601/264480 \
            "$infile" "$outname"
    else
        cdo -w -s -L -setreftime,1500-01-16,,1month \
            -settaxis,1500-01-16,,1month \
            -setcalendar,365_day \
            -seltimestep,258601/264480 \
            "$infile" "$outname"
    fi
    echo "Output written: $outname"
done

cd "$output_dir"
