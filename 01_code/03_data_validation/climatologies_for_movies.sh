#!/usr/bin/env bash

conda activate nco_stable

decadal_base="/media/dafcluster4/storage/TraCE_22k_1500CE/out"
annual_base="/mnt/Data/TraCE-Sahul"
out_base="/mnt/Data/TraCE-Sahul/30yr_clims"

decadal_window=36
decadal_offset=12

annual_window=360
annual_offset=120

vars=(pr tasmax tasmin)

for var in "${vars[@]}"; do
    out_dir="${out_base}/${var}"
    mkdir -p "${out_dir}"

    decadal_in="${decadal_base}/${var}/TraCE-Sahul_decadal_21k_1500CE_${var}.nc"
    if [[ -e "${decadal_in}" ]]; then
        fname=$(basename "${decadal_in}" .nc)
        fname="${fname/21k/22k}"
        outfile="${out_dir}/${fname}_30yrClim.nc"
        if [[ "${var}" == "pr" ]]; then
            cdo --timestat_date last --precision 1,1 -C all -b F32 -O -s -L -P 36 \
            mulc,12 -timselmean,${decadal_window},${decadal_offset} "${decadal_in}" "${outfile}"
        else
            cdo --timestat_date last --precision 1,1 -C all -b F32 -O -s -L -P 36 \
            -s timselmean,${decadal_window},${decadal_offset} "${decadal_in}" "${outfile}"
        fi
    fi

    annual_in="${annual_base}/${var}/TraCE-Sahul_annual_1500_1990_${var}.nc"
    if [[ -e "${annual_in}" ]]; then
        fname=$(basename "${annual_in}" .nc)
        outfile="${out_dir}/${fname}_30yrClim.nc"
        if [[ "${var}" == "pr" ]]; then
            cdo --timestat_date last --precision 1,1 -C all -b F32 -O -s -L -P 36 \
            -s mulc,12 -timselmean,${annual_window},${annual_offset} "${annual_in}" "${outfile}"
        else
            cdo --timestat_date last --precision 1,1 -C all -b F32 -O -s -L -P 36 \
            -s timselmean,${annual_window},${annual_offset} "${annual_in}" "${outfile}"
        fi
    fi
done