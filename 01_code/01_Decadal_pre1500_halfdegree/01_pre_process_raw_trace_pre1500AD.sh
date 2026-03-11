#!/bin/bash

conda activate nco_stable

cd /mnt/Data/TraCE21/

# Colours
RED="\033[38;5;196m"
BLUE="\033[38;5;33m"
YELLOW="\033[38;5;226m"
GREEN="\033[38;5;34m"
RESET="\033[0m"

# One-off 3.75° map generation
ncremap -g ~/Documents/GitHub/TraCE_Sahul/02_data/sahul_coarse.nc -G latlon=17,17#snwe=-48.75,15.0,101.25,165.0

ncremap -a bilinear -V TS --preserve=mean -R '--rgn_dst --rnr_thr=0.0' \
    -g ~/Documents/GitHub/TraCE_Sahul/02_data/sahul_coarse.nc \
    -s /mnt/Data/TraCE21/TS/trace.01.22000-20001BP.cam2.h0.TS.0000101-0200012.nc \
    -m ~/Documents/GitHub/TraCE_Sahul/02_data/trace_to_sahul_coarse_bilin.nc \
    -o ~/Documents/GitHub/TraCE_Sahul/02_data/temp_output.nc

output_root="/mnt/Data/TraCE21_Sahul/"
mkdir -p "$output_root"
map_location="/home/dafcluster4/Documents/GitHub/TraCE_Sahul/02_data/trace_to_sahul_coarse_bilin.nc"

# output_root="/mnt/Data/TraCE21_SahulHalfDeg/"
# mkdir -p "$output_root"
# map_location="/home/dafcluster4/Documents/GitHub/TraCE_Sahul/02_data/trace_to_sahul_05deg_bilin.nc"

# region GLOBAL TO SAHUL 3.75

# remap and process all the global monthly trace data to Sahul at 3.75° res
for file in ./*/*.nc; do
    var=$(echo "$file" | cut -f 7 -d ".")
    echo -e "${GREEN}Processing: $file${RESET}"
    echo -e "   ${GREEN}Variable: $var${RESET}"
    outdir="${output_root}/${var}"
    mkdir -p "$outdir"
    base=$(basename "$file" .nc)
    final="${outdir}/${base}.Sahul.preProc.nc"
    # Skip if final output already exists
    if [[ -f "$final" ]]; then
        echo -e "${YELLOW}Skipping: $final already exists.${RESET}"
        continue
    fi
    # remap with ncremap
    regridded="${outdir}/${base}.Sahul.nc"
    ncremap -v "$var" -m "$map_location" -i "$file" -o "$regridded"
    # variable-specific processing
    if [[ "$var" == "T" || "$var" == "Z3" ]]; then
        cdo -s -w -L -setcalendar,365_day \
            -sellevidx,20,26 \
            "$regridded" "$final"
    elif [[ "$var" == "RELHUM" || "$var" == "U" || "$var" == "V" ]]; then
        cdo -s -w -L --reduce_dim \
            -setcalendar,365_day \
            -sellevidx,26 \
            "$regridded" "$final"
    elif [[ "$var" == "PRECC" || "$var" == "PRECL" ]]; then
        cdo -s -w -L chunit,'m/s','kg/m2/s' \
            -mulc,1000 \
            -setcalendar,365_day \
            "$regridded" "$final"
    else
        cdo -s -w -L -setcalendar,365_day \
            "$regridded" "$final"
    fi
    # clean up
    rm -f "$regridded"
    echo -e "${GREEN}Done.${RESET}"
done

# endregion

# region CONCAT SAHUL FILES

# Loop directly over the subdirectories of $output_dir and concatenate
for folder_path in "$output_root"/*/; do
    [[ -d "$folder_path" ]] || continue # skip if no match
    folder_name=$(basename "$folder_path")
    echo -e "${GREEN}Iterating through: $folder_name${RESET}"
    # Skip if final output already exists
    output_file="${folder_path}/trace.01-36.22000BP-1990CE.cam2.h0.${folder_name}.0000101-2204012.Sahul.concat.nc"
    if [[ -f "$output_file" ]]; then
        echo -e "   ${YELLOW}Skipping: $output_file already exists.${RESET}"
        continue
    fi
    # Grab all NetCDF files in that folder, sorted naturally 01,02,03 etc...
    mapfile -t nc_files < <(ls -v1 "$folder_path"/*.nc 2>/dev/null)
    # Save the order to text for checking
    printf '%s\n' "${nc_files[@]}" >"${folder_path}/input_order.txt"
    file_count=${#nc_files[@]}
    if ((file_count == 36)); then # if all timesteps are present, then concatenate
        echo -e "   ${GREEN}Processing $folder_name with $file_count files…${RESET}"        
        # Concatenate in that exact order
        echo -e "   ${YELLOW}Concatenating $file_count files${RESET}"
        cdo -s -w -L -b F32 -f nc4 -P 100 -O cat "${nc_files[@]}" "$output_file"
        # correct the time dimension
        echo -e "   ${YELLOW}Adjusting time dimension...${RESET}"
        ncap2 -O -s 'time=array(-264479,1,$time)' "$output_file" "$output_file"
        ncatted -O -a units,time,o,c,"months before 1989-12-16" -a calendar,time,o,c,"365_day" -a axis,time,o,c,"T" -a long_name,time,o,c,"time" "$output_file"
        # add calendar month and year helper variable
        ncap2 -O -s 'base_yr=1989; month[$time]=12 - ((-time[$time]) % 12); month@long_name="calendar month (1-12)"; year[$time]=base_yr + long(time[$time]/12); year@long_name="calendar year";' "$output_file" "$output_file"
    else
        echo -e "${RED}Skipping $folder_name. Found $file_count files, expected 36.${RESET}"
    fi
    echo -e "${GREEN}Finished: $folder_name${RESET}"
done

# endregion

# region SUMMARISE AND REMAP TO FINE GRID

# folder for storing decadal outputs
mkdir -p /media/dafcluster4/storage/TraCE_Decadal_halfDeg/

# make template for Sahul
cat > /home/dafcluster4/Documents/GitHub/TraCE_Sahul/02_data/grid_description_halfdeg.txt << 'EOF'
gridtype  = lonlat
xsize     = 113
ysize     = 113
xfirst    = 105.25
yfirst    = -44.75
xinc      = 0.5
yinc      = 0.5
EOF

grid="/home/dafcluster4/Documents/GitHub/TraCE_Sahul/02_data/grid_description_halfdeg.txt"
cdo -f nc const,1,$grid /home/dafcluster4/Documents/GitHub/TraCE_Sahul/02_data/trace_to_sahul_half_degree_bilin.nc
map_location="/home/dafcluster4/Documents/GitHub/TraCE_Sahul/02_data/trace_to_sahul_half_degree_bilin.nc"

# Define output paths
output_dir="/mnt/Data/TraCE21_SahulHalfDeg/"
mkdir -p "$output_dir"

for concat_file in "$output_root"/*/*Sahul.concat.nc; do
    echo -e "${GREEN}Processing: $concat_file${RESET}"
    filepath=$(dirname "$concat_file")
    #var=$(echo basename "$concat_file" | cut -f 6 -d ".")
    var=$(basename "$concat_file" | cut -f 6 -d ".")
    outroot="${output_dir}/${var}"
    mkdir -p "${outroot}"
    output_file="${outroot}/trace.01-35.22000BP-1500CE.cam2.h0.${var}.0000101-258600.Sahul.decavg.concat.nc"
    # if final final exists, skip
    if [[ -f "$output_file" ]]; then
        echo -e "${YELLOW}Skipping ${var} - already processed: $output_file${RESET}"
        continue
    fi
    # else, loop through decades here
    echo -e "${GREEN}Remapping and calculating averages for: $concat_file${RESET}"
    for ((step = 1; step <= 258600; step += 120)); do
        end=$((step + 119))
        outfile="${outroot}/decadal_mon_avg_${step}_${end}.nc"
        if [[ -f "$outfile" ]]; then
            echo -e "${YELLOW}Skipping - already processed: $outfile${RESET}"
            continue
        fi
        # generate temporary file of 120 steps
        # Then calculate the multiyear-monthly mean of each of these files
        tmpfile="$filepath"/temp_decadal_${step}.nc
        # remap with bilinear interpolation after calculating multiyear monthly averages
        # time is irrelevant here, just for assigning months for averages
        last_grid=$(cdo griddes "$concat_file" 2>/dev/null | grep "^# gridID" | tail -1 | awk '{print $3}')
        # echo $last_grid        
        cdo -L -w -s remapbil,"$map_location" \
                -selgrid,$last_grid \
                -ymonmean \
                -settaxis,2000-01-16,,1month \
                -setcalendar,365_day \
                -seltimestep,$step/$end,1 \
                "$concat_file" "$tmpfile"
        # echo -e "${GREEN}Correcting time dimension for: $concat_file${RESET}"
        # now correct the time scale. start and end years stored as helper variables.
        # mid=$(((step + end) / 2))
        mid=$(echo "scale=1; ($step + $end) / 2" | bc)
        ncap2 -O -s 'time=array(0.083f,0.083f,$time)' "$tmpfile" "$tmpfile"
        # ncap2 -O -s "base_dec=$mid" "$tmpfile" "$tmpfile"
        # ncap2 -O -s 'base_dec=base_dec.convert(NC_FLOAT);' "$tmpfile" "$tmpfile"
        # ncap2 -O -s 'time=time+base_dec;' "$tmpfile" "$tmpfile"
        ncap2 -O -s "base_dec=${mid}f; time=time+base_dec;" "$tmpfile" "$tmpfile"
        ncap2 -O -s "start_cal_year=$step; end_cal_year=$end; mid_cal_year=$mid" "$tmpfile" "$tmpfile"
        ncatted -O -a units,time,o,c,"years from 22ka BP" -a calendar,time,o,c,"365_day" -a axis,time,o,c,"T" -a long_name,time,o,c,"time" "$tmpfile"
        # outfile
        # echo -e "${GREEN}Writing: $outfile${RESET}"
        cp $tmpfile $outfile
        ncks -O --glb input_steps=${step}-${end} $outfile $outfile
        ncks -O --glb infile=${concat_file} $outfile $outfile
        rm -f $tmpfile
    done
    # now concatenate the files
    mapfile -t nc_files < <(ls -v1 "$outroot"/*.nc 2>/dev/null)
    # Save the order to text for checking
    printf '%s\n' "${nc_files[@]}" >"${outroot}/input_order.txt"
    file_count=${#nc_files[@]}
    if ((file_count == 2155)); then # if all timesteps are present, then concatenate
        echo -e "${GREEN}Processing $outroot with $file_count files…${RESET}"
        output_file="${outroot}/trace.01-35.22000BP-1500CE.cam2.h0.${var}.0000101-258600.Sahul.decavg.concat.nc"
        # Concatenate in that exact order
        cdo -L -s -w -b F32 -f nc4 -P 100 -O cat "${nc_files[@]}" "$output_file"
    else
        echo -e "${RED}Skipping $outroot. Found $file_count files, expected 36.${RESET}"
    fi
done

# endregion