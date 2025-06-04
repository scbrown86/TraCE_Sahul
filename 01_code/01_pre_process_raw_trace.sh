#!/bin/bash

conda activate nco_stable

cd /home/dafcluster4/Desktop/TraCE_Data/

ncremap -g /home/dafcluster4/Documents/GitHub/temperature_test/02_data/00_maps/sahul_0.5r.nc -G latlon=128,113#snwe=-52.5,11.5,105.0,161.50  # 0.5x0.5 Sahul grid
ncremap -g /home/dafcluster4/Documents/GitHub/temperature_test/02_data/00_maps/sahul_coarse.nc -G latlon=17,15#snwe=-52.5,11.25,105.0,161.25 #3.75 grid

# generate a map file to downscale the non temp and precip variables
ncremap -a bilinear -V Z3 --preserve=mean -R '--rgn_dst --rnr_thr=0.0' -g /home/dafcluster4/Documents/GitHub/temperature_test/02_data/00_maps/sahul_coarse.nc -s ./raw/monthly/others/trace.36.400BP-1990CE.cam2.h0.Z3.2160101-2204012.nc -m /home/dafcluster4/Documents/GitHub/temperature_test/02_data/00_maps/trace_to_sahul_coarse_neareststod.nc -o /home/dafcluster4/Documents/GitHub/temperature_test/02_data/00_maps/temp_output.nc

# remap TraCE21 data to 0.5 degree grid
output_dir="/home/dafcluster4/Documents/GitHub/temperature_test/02_data/01_inputs/"
map_location="/home/dafcluster4/Documents/GitHub/temperature_test/02_data/00_maps/trace_to_sahul_coarse_neareststod.nc"

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
    outname="${output_dir}${oname}.1900_1989CE.nc"
    # Conditional processing based on variable name
    if [[ "$var" == "T" || "$var" == "U" || "$var" == "V" || "$var" == "Z3" ]]; then
        cdo -setreftime,1900-01-16,,1month \
            -settaxis,1900-01-16,,1month \
            -setcalendar,365_day \
            -seltimestep,4201/5280 \
            -sellevidx,20,26 \
            "$infile" "$outname"
    elif [[ "$var" == "RELHUM" ]]; then
        cdo --reduce_dim \
            -setreftime,1900-01-16,,1month \
            -settaxis,1900-01-16,,1month \
            -setcalendar,365_day \
            -seltimestep,4201/5280 \
            -sellevidx,26 \
            "$infile" "$outname"
    elif [[ "$var" == "PRECC" || "$var" == "PRECL" ]]; then
        cdo chunit,'m/s','kg/m2/s' \
            -mulc,1000 \
            -setreftime,1900-01-16,,1month \
            -settaxis,1900-01-16,,1month \
            -setcalendar,365_day \
            -seltimestep,4201/5280 \
            "$infile" "$outname"
    else
        cdo -setreftime,1900-01-16,,1month \
            -settaxis,1900-01-16,,1month \
            -setcalendar,365_day \
            -seltimestep,4201/5280 \
            "$infile" "$outname"
    fi
    unset mapfile oname outname
done

cd "/home/dafcluster4/Documents/GitHub/temperature_test/02_data/01_inputs/single/"

rm -rf *.Sahul.nc

cd /home/dafcluster4/Desktop/TraCE_Data/

# convert PRECC and PRECL (m/s) to volume (kg/m2/s), assuming 1000 kg/m
# Precipitation rate (kg/m²/s) = Precipitation rate (m/s) × density

# cdo chunit,'m/s','kg/m2/s' -mulc,1000 -setreftime,1989-01-16,,1month -settaxis,1989-01-16,,1month -setcalendar,365_day -seltimestep,5269/5280 -sellonlatbox,105.0,161.25,-50.0,10.0 -selname,PRECC raw/monthly/pr/trace.36.400BP-1990CE.cam2.h0.PRECC.2160101-2204012.nc /home/dafcluster4/Documents/GitHub/temperature_test/02_data/01_inputs/single/trace.36.400BP-1990CE.cam2.h0.PRECC.2160101-2204012.Sahul.1900_1989CE.nc

# cdo chunit,'m/s','kg/m2/s' -mulc,1000 -setreftime,1989-01-16,,1month -settaxis,1989-01-16,,1month -setcalendar,365_day -seltimestep,5269/5280 -sellonlatbox,105.0,161.25,-50.0,10.0 -selname,PRECL raw/monthly/pr/trace.36.400BP-1990CE.cam2.h0.PRECL.2160101-2204012.nc /home/dafcluster4/Documents/GitHub/temperature_test/02_data/01_inputs/single/trace.36.400BP-1990CE.cam2.h0.PRECL.2160101-2204012.Sahul.1900_1989CE.nc

# cdo setreftime,1989-01-16,,1month -settaxis,1989-01-16,,1month -setcalendar,365_day -sellonlatbox,105.0,161.25,-50.0,10.0 -selname,TS -seltimestep,5269/5280 ./raw/monthly/ts/trace.36.400BP-1990CE.cam2.h0.TS.2160101-2204012.nc /home/dafcluster4/Documents/GitHub/temperature_test/02_data/01_inputs/single/trace.36.400BP-1990CE.cam2.h0.TS.2160101-2204012.Sahul.1900_1989CE.nc

# cdo setreftime,1989-01-16,,1month -settaxis,1989-01-16,,1month -setcalendar,365_day -sellonlatbox,105.0,161.25,-50.0,10.0 -selname,TSMN -seltimestep,5269/5280 ./raw/monthly/ts/trace.36.400BP-1990CE.cam2.h0.TSMN.2160101-2204012.nc /home/dafcluster4/Documents/GitHub/temperature_test/02_data/01_inputs/single/trace.36.400BP-1990CE.cam2.h0.TSMN.2160101-2204012.Sahul.1900_1989CE.nc

# cdo setreftime,1989-01-16,,1month -settaxis,1989-01-16,,1month -setcalendar,365_day -sellonlatbox,105.0,161.25,-50.0,10.0 -selname,TSMX -seltimestep,5269/5280 ./raw/monthly/ts/trace.36.400BP-1990CE.cam2.h0.TSMX.2160101-2204012.nc /home/dafcluster4/Documents/GitHub/temperature_test/02_data/01_inputs/single/trace.36.400BP-1990CE.cam2.h0.TSMX.2160101-2204012.Sahul.1900_1989CE.nc
