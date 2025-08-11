#!/bin/bash

cd /mnt/Data/CHELSA_Trace21/ || {
    echo "Failed to change directory. Exiting."
    exit 1
}

# deactivate any conda environment
conda deactivate || true

# activate the correct environment
conda activate nco_stable || true

mkdir -p sahul_cropped

# crop files and convert to netcdf in parallel
find . -maxdepth 1 -name '*.tif' |
    parallel --bar -P 64 'gdalwarp -te 105 -52.5 161.25 11.25 -tr 0.05 0.05 -r average -of netCDF -ot Float32 {} sahul_cropped/{/.}.nc > /dev/null 2>&1'

# grab the cropped files, stack, and convert to netcdf
cropped_dir="/mnt/Data/CHELSA_Trace21/sahul_cropped"
mkdir -p "/mnt/Data/CHELSA_Trace21/Sahul"
variables=("pr" "tasmax" "tasmin")

for var in "${variables[@]}"; do
    echo "Processing variable: $var"
    if [[ "${var}" == "pr" ]]; then
        units="mm/month"
        vname="pr"
        vlname="precipitation"
        com="setunit,${units} -setname,${vname} "
    else
        units="deg_C"
        vname=$var
        vlname=$var
        com="-setunit,${units} -setname,${vname} -subc,273.15 -mulc,0.1"
    fi
    # Find and sort files based on timestep and month
    # concatenate, change units, and add time dimension
    # keep unpacked so faster to process later
    cdo -P 100 -L -O --absolute_taxis ${com} \
        -cat \
        $(find "$cropped_dir" -name "CHELSA_TraCE21k_${var}_*.nc" |
            #head -10 | \
            awk -F'[_.]' '{
                month = $6
                timestep = $7
                printf "%d %02d %s\n", timestep, month, $0
          }' | sort -k1,1n -k2,2n |
            cut -d' ' -f3-) "./Sahul/CHELSA_TraCE21k_${var}_stack.nc"
    ncatted -O -a long_name,"$vname",o,c,"$vlname" "./Sahul/CHELSA_TraCE21k_${var}_stack.nc" "./Sahul/CHELSA_TraCE21k_${var}_stack.nc"
    ncap2 -O -s 'time=array(1,1,$time); time@units=""' "./Sahul/CHELSA_TraCE21k_${var}_stack.nc" "./Sahul/CHELSA_TraCE21k_${var}_stack.nc"
done

# # Aggregate to 2.5°

# # target grid for aggregation
# cdo -f nc sellonlatbox,105,161.25,-52.5,11.25 -const,1,global_2.5 ./Sahul/agg_target.nc
# targetgrid="./Sahul/agg_target.nc"

# # create weight files if they don't already exist
# pr_weights="./Sahul/coarse_pr_weights.nc"
# tas_weights="./Sahul/coarse_tas_weights.nc"
# src_pr="./Sahul/CHELSA_TraCE21k_pr_stack.nc"
# src_tas="./Sahul/CHELSA_TraCE21k_tasmax_stack.nc"

# # Conservative weights for precipitation
# if [[ ! -f "$pr_weights" ]]; then
#     echo "Making conservative weights for pr..."
#     export CDO_REMAP_NORM=destarea
#     export REMAP_AREA_MIN=0.10
#     cdo -P 100 gencon,"$targetgrid" "$src_pr" "$pr_weights"
# fi

# # Bilinear weights for temperatures (tasmax, tasmin)
# if [[ ! -f "$tas_weights" ]]; then
#     echo "Making bilinear weights for tas..."
#     unset REMAP_AREA_MIN
#     unset CDO_REMAP_NORM
#     cdo -P 100 genbil,"$targetgrid" "$src_tas" "$tas_weights"
# fi

for var in "${variables[@]}"; do
    # echo "Processing ${var}..."

    # sums for precipitation, means otherwise
    if [[ $var == "pr" ]]; then
        echo "Processing ${var}..."
        export CDO_REMAP_NORM=destarea
        export REMAP_AREA_MIN=0.10
        op_dec="timselsum,12" # Centennial sums
        wgt="$pr_weights"
    else
        echo "Processing ${var}..."
        unset CDO_REMAP_NORM
        unset REMAP_AREA_MIN
        op_dec="timselmean,12" # Centennial means
        wgt="$tas_weights"
    fi

    # Karger centennial data
    in_dec="./Sahul/CHELSA_TraCE21k_${var}_stack.nc"
    out_dec="./Sahul/CHELSA_TraCE21k_${var}_centennial_agg_noSpat.nc"
    echo "Temporally aggregating ${in_dec} -> ${out_dec}"
    cdo -b F32 -P 100 "$op_dec" "$in_dec" "$out_dec"
    ncap2 -O -s 'time=array(1,1,$time); time@units=""' "$out_dec" "$out_dec"
done
