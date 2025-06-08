#!/bin/bash

conda activate nco_stable

cd /home/dafcluster4/Desktop/TraCE_Data/

ncremap -g ~/Documents/GitHub/TraCE_Sahul/02_data/sahul_coarse.nc -G latlon=17,15#snwe=-52.5,11.25,105.0,161.25 #3.75 grid

# generate a map file to place raw trace-data on 3.75x3.75 grid
ncremap -a bilinear -V Z3 --preserve=mean -R '--rgn_dst --rnr_thr=0.0' -g ~/Documents/GitHub/TraCE_Sahul/02_data/sahul_coarse.nc -s ./raw/monthly/others/trace.36.400BP-1990CE.cam2.h0.Z3.2160101-2204012.nc -m ~/Documents/GitHub/TraCE_Sahul/02_data/trace_to_sahul_coarse_bilin.nc -o ~/Documents/GitHub/TraCE_Sahul/02_data/temp_output.nc

# remap TraCE21 data to 0.5 degree grid
output_dir="/home/dafcluster4/Documents/GitHub/TraCE_Sahul/02_data/01_inputs/"
map_location="/home/dafcluster4/Documents/GitHub/TraCE_Sahul/02_data/trace_to_sahul_coarse_bilin.nc"

for file in ./raw/monthly/*/*.nc; do
    echo "$file"
    # Get variable from filename
    var=$(echo "$file" | cut -f 7 -d ".")
    echo -e "$var"
    # Remap with ncremap
    oname="$(basename "$file" .nc)"
    outname="${output_dir}${oname}.Sahul.nc"
    ncremap -v "$var" -m "$map_location" -i "$file" -o "$outname"
    infile="$outname"
    # Prepare output filename for processed file
    unset oname outname
    oname="$(basename "$infile" .nc)"
    outname="${output_dir}${oname}.1600_1989CE.nc"
    # Process based on variable name
    if [[ "$var" == "T" || "$var" == "Z3" ]]; then
        cdo -setreftime,1600-01-16,,1month \
            -settaxis,1600-01-16,,1month \
            -setcalendar,365_day \
            -seltimestep,601/5280 \
            -sellevidx,20,26 \
            "$infile" "$outname"
    elif [[ "$var" == "RELHUM" || "$var" == "U" || "$var" == "V" ]]; then
        cdo --reduce_dim \
            -setreftime,1600-01-16,,1month \
            -settaxis,1600-01-16,,1month \
            -setcalendar,365_day \
            -seltimestep,601/5280 \
            -sellevidx,26 \
            "$infile" "$outname"
    elif [[ "$var" == "PRECC" || "$var" == "PRECL" ]]; then
        cdo chunit,'m/s','kg/m2/s' \
            -mulc,1000 \
            -setreftime,1600-01-16,,1month \
            -settaxis,1600-01-16,,1month \
            -setcalendar,365_day \
            -seltimestep,601/5280 \
            "$infile" "$outname"
    else
        cdo -setreftime,1600-01-16,,1month \
            -settaxis,1600-01-16,,1month \
            -setcalendar,365_day \
            -seltimestep,601/5280 \
            "$infile" "$outname"
    fi
    unset mapfile oname outname
done

cd "$output_dir"

rm -rf *.Sahul.nc
