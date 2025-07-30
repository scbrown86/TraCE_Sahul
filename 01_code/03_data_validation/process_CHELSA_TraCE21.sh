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
find . -maxdepth 1 -name '*.tif' | \
parallel --bar -P 64 'gdalwarp -te 105 -52.5 161.25 11.25 -tr 0.05 0.05 -r average -of netCDF -ot Float32 {} sahul_cropped/{/.}.nc > /dev/null 2>&1'

# grab the cropped files, stack, and convert to netcdf
cropped_dir="/mnt/Data/CHELSA_Trace21/sahul_cropped"
mkdir -p "/mnt/Data/CHELSA_Trace21/Sahul"
variables=("pr" "tas" "tasmax" "tasmin")

for var in "${variables[@]}"; do
  echo "Processing variable: $var"

  if [[ "${var}" == "pr" ]]; then
      units="mm/month"
      vname="pr"
      vlname="precipitation"
  else
      units="deg_C"
      vname=$var
      vlname=$var
  fi

  # Find and sort files based on timestep and month
  # concatente, change units, and add time dimension
  # keep unpacked so faster to process later
  cdo -P 100 -L -O --absolute_taxis setunit,$units -setname,$vname \
   -cat \
  $(find "$cropped_dir" -name "CHELSA_TraCE21k_${var}_*.nc" | \
      #head -10 | \
          awk -F'[_.]' '{
                month = $6
                timestep = $7
                printf "%d %02d %s\n", timestep, month, $0
          }' | sort -k1,1n -k2,2n | \
      cut -d' ' -f3-) "./Sahul/CHELSA_TraCE21k_${var}_stack.nc"
  ncatted -O -a long_name,"$vname",o,c,"$vlname" "./Sahul/CHELSA_TraCE21k_${var}_stack.nc" "./Sahul/CHELSA_TraCE21k_${var}_stack.nc"
	ncap2 -O -s 'time=array(1,1,$time); time@units=""' "./Sahul/CHELSA_TraCE21k_${var}_stack.nc" "./Sahul/CHELSA_TraCE21k_${var}_stack.nc"
done