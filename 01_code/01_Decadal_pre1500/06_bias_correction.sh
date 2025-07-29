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
        cdo -b F32 -P 100 -O unpack -cat $(ls -v1 "${var_dir}"/*.nc) "${concat_file}"
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
        cdo -P 100 -b F32 unpack "${concat_file}" "${tmp_unpacked}"
        
        # Choose remap method
        if [[ "${var}" == "pr" ]]; then
            remap_method="-remapcon"
        else
            remap_method="-remapnn"
        fi
        
        # remap delta to ensure that grids align
        # Could probably use remapnn as there should be no actual regridding?
        cdo griddes "${tmp_unpacked}" > "${grid_desc}"
        cdo -s -w -P 100 unpack "${remap_method},${grid_desc}" "${delta_file}" "${tmp_delta}"

        # Apply bias correction
        if [[ "${var}" == "pr" ]]; then
            # needs a time axis to multiply by days per month
            cdo -P 100 -b F32 \
                setunit,'mm/month' \
                -muldpm \
                -setreftime,2000-01-16,,1month \
                -settaxis,2000-01-16,,1month \
                -setcalendar,365_day \
                -mulc,86400 \
                -mul "${tmp_unpacked}" "${tmp_delta}" "${tmp_biascorr}"
        else
            cdo -P 100 -b F32 \
                -setreftime,2000-01-16,,1month \
                -settaxis,2000-01-16,,1month \
                -setcalendar,365_day \
                -setunit,'deg_C' \
                -subc,273.15 \
                -add "${tmp_unpacked}" "${tmp_delta}" "${tmp_biascorr}"
        fi

        # Don't store with compressed data
        echo "  Writing bias‑corrected file: ${biascorr_file}"
        cdo -b F32 unpack "${tmp_biascorr}" "${biascorr_file}"

        # Clean up temporary files
        # find "${var_dir}" -type f -name "$(basename "${concat_file}")" -delete
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
	
	outfile="${out_dir}/out/${var}/TraCE_22ka_downscaled_${var}_decadal_21k_1500CE_biascorr.nc"
	echo "outfile = ${outfile}"
	
	find "${input_base}"/*/out/"${var}" -type f -name '*biascorr.nc' | sort -V > "${out_dir}/${var}_concat_input_order.txt"
	
	cdo -P 100 -L -s -O --absolute_taxis pack -cat -unpack \
		$(find "${input_base}"/*/out/"${var}" -type f -name '*biascorr.nc' | sort -V) \
		"${outfile}"
		
	echo "resetting time dimension..."
	ncap2 -O -s 'time=array(1,1,$time); time@units=""' "${outfile}" "${outfile}"
	
	echo "Done for variable: ${var}"
done