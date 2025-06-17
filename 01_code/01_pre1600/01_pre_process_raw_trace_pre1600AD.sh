#!/bin/bash

conda activate nco_stable

cd /media/dafcluster4/Stu_External/TraCE21/

ncremap -g ~/Documents/GitHub/TraCE_Sahul/02_data/sahul_coarse.nc -G latlon=17,15#snwe=-52.5,11.25,105.0,161.25 #3.75 grid

# generate a map file to place raw trace-data on 3.75x3.75 grid
ncremap -a bilinear -V Z3 --preserve=mean -R '--rgn_dst --rnr_thr=0.0' -g ~/Documents/GitHub/TraCE_Sahul/02_data/sahul_coarse.nc -s /home/dafcluster4/Desktop/TraCE_Data/raw/monthly/others/trace.36.400BP-1990CE.cam2.h0.Z3.2160101-2204012.nc -m ~/Documents/GitHub/TraCE_Sahul/02_data/trace_to_sahul_coarse_bilin.nc -o ~/Documents/GitHub/TraCE_Sahul/02_data/temp_output.nc

output_dir="/media/dafcluster4/Stu_External/TraceSahul/"
map_location="/home/dafcluster4/Documents/GitHub/TraCE_Sahul/02_data/trace_to_sahul_coarse_bilin.nc"

for file in ./*/*.nc; do
    echo "$file"
    # Get variable from filename
    var=$(echo "$file" | cut -f 7 -d ".")
    echo -e "$var"
    output_dir="/media/dafcluster4/Stu_External/TraceSahul"
    output_dir="$output_dir/$var/"
    mkdir -p "$output_dir"
    # Remap with ncremap
    oname="$(basename "$file" .nc)"
    outname="${output_dir}${oname}.Sahul.nc"
    ncremap -v "$var" -m "$map_location" -i "$file" -o "$outname"
    infile="$outname"
    # Prepare output filename for processed file
    unset oname outname
    oname="$(basename "$infile" .nc)"
    outname="${output_dir}${oname}.preProc.nc"
    # Process based on variable name
    if [[ "$var" == "T" || "$var" == "Z3" ]]; then
        cdo -setcalendar,365_day \
            -sellevidx,20,26 \
            "$infile" "$outname"
    elif [[ "$var" == "RELHUM" || "$var" == "U" || "$var" == "V" ]]; then
        cdo --reduce_dim \
            -setcalendar,365_day \
            -sellevidx,26 \
            "$infile" "$outname"
    elif [[ "$var" == "PRECC" || "$var" == "PRECL" ]]; then
        cdo chunit,'m/s','kg/m2/s' \
            -mulc,1000 \
            -setcalendar,365_day \
            "$infile" "$outname"
    else
        cdo -setcalendar,365_day \
            "$infile" "$outname"
    fi
    rm -rf "$output_dir"/*.Sahul.nc
    unset mapfile oname outname
done

cd "$output_dir"
