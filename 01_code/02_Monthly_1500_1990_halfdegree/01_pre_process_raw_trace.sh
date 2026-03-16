#!/bin/bash

conda activate nco_stable

# make template for Sahul
# cdo -f nc const,1,/home/dafcluster4/Documents/GitHub/TraCE_Sahul/02_data/grid_description_halfdeg.txt /home/dafcluster4/Documents/GitHub/TraCE_Sahul/02_data/trace_to_sahul_half_degree_bilin.nc

map_location="/home/dafcluster4/Documents/GitHub/TraCE_Sahul/02_data/trace_to_sahul_half_degree_bilin.nc"

# Define paths
base_dir="/mnt/Data/TraCE21_Sahul"
output_dir="/media/dafcluster4/storage/TraCE_Monthly_halfDeg"

cd "$base_dir" || exit 1

# Loop over each subdirectory
for folder in */; do
    var="${folder%/}"
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
    last_grid=$(cdo griddes "$infile" 2>/dev/null | grep "^# gridID" | tail -1 | awk '{print $3}')
    # echo $last_grid
    # Run CDO processing based on variable
    # the inputs have already been remapped to 3.75, cropped to Sahul, and adjusted as needed
    # just need to grab the appropriate timesteps and reset the calendar
    # files also need to be remapped bilinearly to the smoother 0.5 resolution
    if [[ "$var" == "T" || "$var" == "Z3" ]]; then        
        cdo -w -s -L -setreftime,1500-01-16,,1month \
            -settaxis,1500-01-16,,1month \
            -setcalendar,365_day \
            -remapbil,$map_location \
            -selgrid,$last_grid \
            -seltimestep,258601/264480 \
            "$infile" "$outname"
    elif [[ "$var" == "RELHUM" || "$var" == "U" || "$var" == "V" ]]; then
        cdo -w -s -L --reduce_dim \
            -setreftime,1500-01-16,,1month \
            -settaxis,1500-01-16,,1month \
            -setcalendar,365_day \
            -remapbil,$map_location \
            -selgrid,$last_grid \
            -seltimestep,258601/264480 \
            "$infile" "$outname"
    elif [[ "$var" == "PRECC" || "$var" == "PRECL" ]]; then
        export CDO_REMAP_NORM="destarea"
        export REMAP_AREA_MIN=0.10
        cdo -w -s -L -setreftime,1500-01-16,,1month \
            -settaxis,1500-01-16,,1month \
            -setcalendar,365_day \
            -remapbil,$map_location \
            -seltimestep,258601/264480 \
            -selgrid,$last_grid \
            "$infile" "$outname"
        unset CDO_REMAP_NORM REMAP_AREA_MIN
    else
        cdo -w -s -L -setreftime,1500-01-16,,1month \
            -settaxis,1500-01-16,,1month \
            -setcalendar,365_day \
            -remapbil,$map_location \
            -seltimestep,258601/264480 \
            -selgrid,$last_grid \
            "$infile" "$outname"
    fi
    echo "Output written: $outname"
done

cd "$output_dir"
