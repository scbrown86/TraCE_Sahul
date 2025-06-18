#!/bin/bash

conda activate nco_stable

cd /media/dafcluster4/Stu_External/TraCE21/

# One-off map generation
ncremap -g ~/Documents/GitHub/TraCE_Sahul/02_data/sahul_coarse.nc -G latlon=17,15#snwe=-52.5,11.25,105.0,161.25

ncremap -a bilinear -V Z3 --preserve=mean -R '--rgn_dst --rnr_thr=0.0' \
    -g ~/Documents/GitHub/TraCE_Sahul/02_data/sahul_coarse.nc \
    -s /home/dafcluster4/Desktop/TraCE_Data/raw/monthly/others/trace.36.400BP-1990CE.cam2.h0.Z3.2160101-2204012.nc \
    -m ~/Documents/GitHub/TraCE_Sahul/02_data/trace_to_sahul_coarse_bilin.nc \
    -o ~/Documents/GitHub/TraCE_Sahul/02_data/temp_output.nc

output_root="/media/dafcluster4/Stu_External/TraceSahul"
map_location="/home/dafcluster4/Documents/GitHub/TraCE_Sahul/02_data/trace_to_sahul_coarse_bilin.nc"

for file in ./*/*.nc; do
    echo "$file"
    var=$(echo "$file" | cut -f 7 -d ".")
    echo "$var"
    outdir="${output_root}/${var}"
    mkdir -p "$outdir"
    base=$(basename "$file" .nc)
    final="${outdir}/${base}.Sahul.preProc.nc"
    # Skip if final output already exists
    if [[ -f "$final" ]]; then
        echo "Skipping: $final already exists."
        continue
    fi
    # remap with ncremap
    regridded="${outdir}/${base}.Sahul.nc"
    ncremap -v "$var" -m "$map_location" -i "$file" -o "$regridded"
    # variable-specific processing
    if [[ "$var" == "T" || "$var" == "Z3" ]]; then
        cdo -setcalendar,365_day \
            -sellevidx,20,26 \
            "$regridded" "$final"
    elif [[ "$var" == "RELHUM" || "$var" == "U" || "$var" == "V" ]]; then
        cdo --reduce_dim \
            -setcalendar,365_day \
            -sellevidx,26 \
            "$regridded" "$final"
    elif [[ "$var" == "PRECC" || "$var" == "PRECL" ]]; then
        cdo chunit,'m/s','kg/m2/s' \
            -mulc,1000 \
            -setcalendar,365_day \
            "$regridded" "$final"
    else
        cdo -setcalendar,365_day \
            "$regridded" "$final"
    fi
    # clean up
    rm -f "$regridded"
done

cd "$output_root"
