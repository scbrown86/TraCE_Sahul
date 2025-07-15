#!/bin/bash

cd "/media/dafcluster4/storage/" || {
    echo "Failed to change directory. Exiting."
    exit 1
}

conda deactivate || true
conda activate nco_stable 

output_dir="/media/dafcluster4/storage/TraCE_22k_1990CE_CoarseSummary"
mkdir -p "$output_dir"     # create it if it doesn’t exist

# target grid for aggregation
cdo -f nc sellonlatbox,105,161.25,-52.5,11.25 -const,1,global_2.5 "${output_dir}/agg_target.nc"
targetgrid="${output_dir}/agg_target.nc"

# create weight files if they don't already exist
pr_weights="${output_dir}/coarse_pr_weights.nc"
tas_weights="${output_dir}/coarse_tas_weights.nc"
src_pr="/media/dafcluster4/storage/TraCE_22k_1500CE/TraCE_22k_1500CE_decadal_pr_concat_biascorr.nc"
src_tas="/media/dafcluster4/storage/TraCE_22k_1500CE/TraCE_22k_1500CE_decadal_tas_concat_biascorr.nc"

# Conservative weights for precipitation
if [[ ! -f "$pr_weights" ]]; then
    echo "Making conservative weights for pr..."
    cdo -P 100 gencon,"$targetgrid" "$src_pr" "$pr_weights"
fi

# Bilinear weights for temperatures (tas, tasmax, tasmin)
if [[ ! -f "$tas_weights" ]]; then
    echo "Making bilinear weights for tas..."
    cdo -P 100 genbil,"$targetgrid" "$src_tas" "$tas_weights"
fi

vars=(tas tasmax tasmin pr)

for var in "${vars[@]}"; do
    # sums for precipitation, means otherwise
    if [[ $var == pr ]]; then
        op_dec="timselsum,120"   # Centennial sums (120 months = 10 decades =  1 century). 2155 decades = 215.5 centuries, last "century" is only be 50 years.
        op_yr="yearmean"          # annual sums
        wgt="$pr_weights"
    else
        op_dec="timselmean,120"  # Centennial means
        op_yr="yearmean"         # annual means
        wgt="$tas_weights"
    fi

    # TraCE_22k_1500CE decadal steps
    in_dec="/media/dafcluster4/storage/TraCE_22k_1500CE/TraCE_22k_1500CE_decadal_${var}_concat_biascorr.nc"
    out_dec="${output_dir}/TraCE_22k_1500CE_centennial_${var}_biascorr_coarse.nc"
    out_dec2="${output_dir}/TraCE_22k_1500CE_centennial_${var}_biascorr_coarse_noSpat.nc"
    echo "Regridding and then temporally aggregating ${in_dec}"
    # Need to divide the cenntennial sum by 100 to get mm/year average. Do later for plotting as last time step needs to be div by 50
    cdo -s -b F32 -P 100 "$op_dec" -remap,"$targetgrid","$wgt" "$in_dec" "$out_dec"
    echo "Temporally aggregating ${in_dec}"
    cdo -b F32 -P 100 "$op_dec" "$in_dec" "$out_dec2"

    # TraCE_1500_1990CE annual steps
    in_yr="/media/dafcluster4/storage/TraCE_1500_1990CE/CHELSA_${var}_1500_1990_biascorr.nc"
    out_yr="${output_dir}/TraCE_1500_1990CE_annual_${var}_biascorr_coarse.nc"
    out_yr2="${output_dir}/TraCE_1500_1990CE_annual_${var}_biascorr_coarse_noSpat.nc"
    echo "Regridding and then temporally aggregating ${in_yr}"
    cdo -s -b F32 -P 100 "$op_yr" -remap,"$targetgrid","$wgt" "$in_dec" "$out_dec"
    echo "Temporally aggregating ${in_yr}"
    cdo -b F32 -P 100 "$op_yr" "$in_yr" "$out_yr2"
done