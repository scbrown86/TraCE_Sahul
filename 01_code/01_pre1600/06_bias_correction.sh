#!/bin/bash

cd "/media/dafcluster4/storage/TraCE_22k_1500CE/" || {
    echo "Failed to change directory. Exiting."
    exit 1
}

conda deactivate || true
conda activate nco_stable 

input_base="/media/dafcluster4/storage/TraCE_22k_1500CE/chunk_out"
delta_base="/home/dafcluster4/Documents/GitHub/TraCE_Sahul/02_data/02_processed/deltas"
variables=("pr" "tas" "tasmax" "tasmin")

for chunk_dir in "${input_base}"/[0-9][0-9][0-9][0-9][0-9]_[0-9][0-9][0-9][0-9][0-9]; do
    chunk_name=$(basename "$chunk_dir")          # e.g. 00001_00012 ... 25849_25860
    out_dir="${chunk_dir}/out"

    echo "Processing chunk: ${chunk_name}"

    for var in "${variables[@]}"; do
        var_dir="${out_dir}/${var}"
        concat_file="${var_dir}/CHELSA_${var}_${chunk_name}_concat.nc"
        biascorr_file="${var_dir}/CHELSA_${var}_${chunk_name}_concat_biascorr.nc"
        # concatenate chunk
        echo "  Concatenating ${var} in ${chunk_name}"
        cdo -O cat $(ls -v1 "${var_dir}"/*.nc) "${concat_file}"
        # grab corresponding delta file
        delta_file=$(find "${delta_base}" -type f -name "delta_fine_delta_${var}_climatology_ncdf4.nc" | head -n 1)
        if [[ ! -f "${delta_file}" ]]; then
            echo "  Delta file not found for ${var}; skipping"
            continue
        fi
       
        # temp files
        tmp_unpacked=$(mktemp --suffix "_${var}_unpacked.nc")
        tmp_delta=$(mktemp   --suffix "_${var}_remap.nc")
        tmp_biascorr=$(mktemp --suffix "_${var}_biascorr.nc")
        grid_desc=$(mktemp   --suffix ".txt")
        
        # Unpack to remove scale/offset
        cdo -b -s -w F32 unpack "${concat_file}" "${tmp_unpacked}"
        
        # Choose remap method
        if [[ "${var}" == "pr" ]]; then
            remap_method="remapcon"
        else
            remap_method="remapbil"
        fi
        
        # remap delta to ensure that grids align
        # Could probably use remapnn as there should be no actual regridding?
        cdo griddes "${concat_file}" > "${grid_desc}"
        cdo -P 64 -s -w "${remap_method},${grid_desc}" "${delta_file}" "${tmp_delta}"

        # Apply bias correction
        if [[ "${var}" == "pr" ]]; then
            # needs a time axis to multiple by days per month!
            cdo -s -w -b F32 \
                -muldpm \
                -setreftime,1600-01-16,,1month \
                -settaxis,1600-01-16,,1month \
                -setcalendar,365_day \
                -setunit,'mm/month' \
                -mulc,86400 \
                -mul "${tmp_unpacked}" "${tmp_delta}" "${tmp_biascorr}"
        else
            cdo -s -w -b F32 \
                -setreftime,1600-01-16,,1month \
                -settaxis,1600-01-16,,1month \
                -setcalendar,365_day \
                -setunit,'deg_C' \
                -subc,273.15 \
                -add "${tmp_unpacked}" "${tmp_delta}" "${tmp_biascorr}"
        fi

        # Pack final output
        echo "  Writing bias‑corrected file: ${biascorr_file}"
        cdo pack "${tmp_biascorr}" "${biascorr_file}"

        # Clean up temporary files
        find "${var_dir}" -type f -name "$(basename "${concat_file}")" -delete
        rm -f "${tmp_unpacked}" "${tmp_delta}" "${tmp_biascorr}" "${grid_desc}"

        echo "  Finished ${var} for chunk ${chunk_name}"
    done

    echo "Finished chunk ${chunk_name}"
    echo "----------------------------------------"
done

# concatentate the bias corrected files
out_dir="/media/dafcluster4/storage/TraCE_22k_1500CE"
for var in "${variables[@]}"; do
	echo "processing variable: ${var}..."
	
	outfile="${out_dir}/TraCE_22k_1500CE_decadal_${var}_concat_biascorr.nc"
	echo "outfile = ${outfile}"
	
	find "${input_base}"/*/out/"${var}" -type f -name '*biascorr.nc' > "${out_dir}/${var}_concat_input_order.txt"
	
	cdo -s -w -O --absolute_taxis pack -cat -unpack \
		$(find "${input_base}"/*/out/"${var}" -type f -name '*biascorr.nc') \
		"${outfile}"
		
	echo "resetting time dimension..."
	ncap2 -O -s 'time=array(1,1,$time); time@units=""' "${outfile}" "${outfile}"
	
	echo "Done for variable: ${var}"
done