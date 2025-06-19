#!/bin/bash

conda activate nco_stable

cd /mnt/Data/TraCE21/

# One-off map generation
ncremap -g ~/Documents/GitHub/TraCE_Sahul/02_data/sahul_coarse.nc -G latlon=17,15#snwe=-52.5,11.25,105.0,161.25

ncremap -a bilinear -V Z3 --preserve=mean -R '--rgn_dst --rnr_thr=0.0' \
    -g ~/Documents/GitHub/TraCE_Sahul/02_data/sahul_coarse.nc \
    -s /home/dafcluster4/Desktop/TraCE_Data/raw/monthly/others/trace.36.400BP-1990CE.cam2.h0.Z3.2160101-2204012.nc \
    -m ~/Documents/GitHub/TraCE_Sahul/02_data/trace_to_sahul_coarse_bilin.nc \
    -o ~/Documents/GitHub/TraCE_Sahul/02_data/temp_output.nc

output_root="/mnt/Data/TraCE21_Sahul/"
mkdir -p "$output_root"
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

# Loop directly over the subdirectories of $output_dir and concatenate
for folder_path in "$output_root"/*/; do
    [[ -d "$folder_path" ]] || continue # skip if no match
    folder_name=$(basename "$folder_path")
    echo $folder_name
    # Grab all NetCDF files in that folder, sorted naturally 01,02,03 etc...
    mapfile -t nc_files < <(ls -v1 "$folder_path"/*.nc 2>/dev/null)
    # Save the order to text for checking
    printf '%s\n' "${nc_files[@]}" >"${folder_path}/input_order.txt"
    file_count=${#nc_files[@]}
    if ((file_count == 36)); then # if all timesteps are present, then concatenate
        echo "Processing $folder_name with $file_count files…"
        output_file="${folder_path}/trace.01-36.22000BP-1990CE.cam2.h0.${folder_name}.0000101-2204012.Sahul.concat.nc"
        # Concatenate in that exact order
        ncrcat --4 -t 100 "${nc_files[@]}" -o "$output_file"
        # add in the time dimension
        last_date="1989-12-16 00:00:00" # final timestep
        #ndays_per_mon=30 # 365/12
        ncap2 -O -s 'nt=$time.size; time[$time]=-(nt-1)+time[$time];' "$output_file" "$output_file"
        ncatted -O -a units,time,o,c,"months since 1989-12-16" -a calendar,time,o,c,"365_day" -a axis,time,o,c,"T" -a long_name,time,o,c,"time" "$output_file"
        # add calendar month and year helper variable
        ncap2 -O -s 'nt=$time.size; month[$time]=1 + ((nt-1-time[$time]) - 12*((nt-1-time[$time])/12)); year[$time]=1989 - ((nt-1 - time[$time])/12); month@long_name="calendar month (1–12)"; year@long_name="calendar year";' "$output_file" "$output_file"
    else
        echo "Skipping $folder_name — found $file_count files, expected 36"
    fi
done
