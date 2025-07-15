#!/bin/bash

cd "/media/dafcluster4/storage/" || {
    echo "Failed to change directory. Exiting."
    exit 1
}

conda deactivate || true
conda activate nco_stable 

output_dir="/media/dafcluster4/storage/TraCE_22k_1990CE_CoarseSummary"
mkdir -p "$output_dir"     # create it if it doesn’t exist

vars=(tas tasmax tasmin pr)

for var in "${vars[@]}"; do
    # sums for precipitation, means otherwise
    if [[ $var == pr ]]; then
        op_dec="timselsum,120"   # half-centennial sums (60 months = 5 decades =  0.5 century). 2155 decades = 215.5 centuries, last "century" would only be 50 years if we used 120.
        op_yr="yearsum"          # annual sums
    else
        op_dec="timselmean,120"  # half-centennial means
        op_yr="yearmean"         # annual means
    fi

    # TraCE_22k_1500CE decadal steps
    in_dec="/media/dafcluster4/storage/TraCE_22k_1500CE/TraCE_22k_1500CE_decadal_${var}_concat_biascorr.nc"
    out_dec="${output_dir}/TraCE_22k_1500CE_centennial_${var}_biascorr_coarse.nc"
    out_dec2="${output_dir}/TraCE_22k_1500CE_centennial_${var}_biascorr_coarse_noSpat.nc"
    cdo -b F32 -P 100 "$op_dec" -gridboxmean,50,50 "$in_dec" "$out_dec"
    cdo -b F32 -P 100 "$op_dec" "$in_dec" "$out_dec2"

    # TraCE_1500_1990CE annual steps
    in_yr="/media/dafcluster4/storage/TraCE_1500_1990CE/CHELSA_${var}_1500_1990_biascorr.nc"
    out_yr="${output_dir}/TraCE_1500_1990CE_annual_${var}_biascorr_coarse.nc"
    out_yr2="${output_dir}/TraCE_1500_1990CE_annual_${var}_biascorr_coarse_noSpat.nc"
    cdo -b F32 -P 100 "$op_yr" -gridboxmean,50,50 "$in_yr" "$out_yr"
    cdo -b F32 -P 100 "$op_yr" "$in_yr" "$out_yr2"
done