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
pr_weights_ann="${output_dir}/coarse_pr_weights_ann.nc"
tas_weights="${output_dir}/coarse_tas_weights.nc"
tas_weights_ann="${output_dir}/coarse_tas_weights_ann.nc"
src_pr="/media/dafcluster4/storage/TraCE_22k_1500CE/out/pr/TraCE_22ka_downscaled_pr_decadal_21k_1500CE_biascorr.nc"
src_tas="/media/dafcluster4/storage/TraCE_22k_1500CE/out/tas/TraCE_22ka_downscaled_tas_decadal_21k_1500CE_biascorr.nc"
src_pr_ann="/media/dafcluster4/storage/TraCE_1500_1990CE/1500_1990/out/pr/TraCE_22ka_downscaled_pr_1500_1990_biascorr.nc"
src_tas_ann="/media/dafcluster4/storage/TraCE_1500_1990CE/1500_1990/out/tas/TraCE_22ka_downscaled_tas_1500_1990_biascorr.nc"

# Conservative weights for precipitation
if [[ ! -f "$pr_weights" ]]; then
    echo "Making conservative weights for pr..."
    export CDO_REMAP_NORM="destarea"
    export REMAP_AREA_MIN=0.10
    cdo -P 100 gencon,"$targetgrid" "$src_pr" "$pr_weights"
    cdo -P 100 gencon,"$targetgrid" "$src_pr_ann" "$pr_weights_ann"
fi

# Bilinear weights for temperatures (tas, tasmax, tasmin)
if [[ ! -f "$tas_weights" ]]; then
    echo "Making bilinear weights for tas..."
    unset REMAP_AREA_MIN
    unset CDO_REMAP_NORM
    cdo -P 100 genbil,"$targetgrid" "$src_tas" "$tas_weights"
    cdo -P 100 genbil,"$targetgrid" "$src_tas_ann" "$tas_weights_ann"
fi

vars=(tas tasmax tasmin pr)

for var in "${vars[@]}"; do
    # sums for precipitation, means otherwise
    if [[ $var == pr ]]; then
        export CDO_REMAP_NORM="destarea"
        export REMAP_AREA_MIN=0.10
        op_dec="timselsum,120"   # Centennial sums (120 months = 10 decades =  1 century). 2155 decades = 215.5 centuries, last "century" is only 50 years.
        op_yr="yearsum"          # annual sums
        wgt="$pr_weights"
        wgt_ann="$pr_weights_ann"
    else
        unset CDO_REMAP_NORM
        unset REMAP_AREA_MIN
        op_dec="timselmean,120"  # Centennial means
        op_yr="yearmean"         # annual means
        wgt="$tas_weights"
        wgt_ann="$tas_weights_ann"
    fi

    # TraCE_22k_1500CE decadal steps
    in_dec="/media/dafcluster4/storage/TraCE_22k_1500CE/out/${var}/TraCE_22ka_downscaled_${var}_decadal_21k_1500CE_biascorr.nc"
    out_dec="${output_dir}/TraCE_22ka_downscaled_${var}_centennial_21k_1500CE_biascorr.nc"
    out_dec2="${output_dir}/TraCE_22ka_downscaled_${var}_centennial_21k_1500CE_biascorr_noSpat.nc"
    echo "Regridding and then temporally aggregating ${in_dec}"
    # Need to divide the centennial sum by 100 to get mm/year average. Do later for plotting as last time step needs to be div by 50
    cdo -s -b F32 -P 100 "$op_dec" -remap,"$targetgrid","$wgt" "$in_dec" "$out_dec"
    ncap2 -O -s 'time=array(1,1,$time); time@units=""' "$out_dec" "$out_dec"
    echo "Temporally aggregating ${in_dec}"
    cdo -s -b F32 -P 100 "$op_dec" "$in_dec" "$out_dec2"

    # TraCE_1500_1990CE annual steps
    in_yr="/media/dafcluster4/storage/TraCE_1500_1990CE/1500_1990/out/${var}/TraCE_22ka_downscaled_${var}_1500_1990_biascorr.nc"
    out_yr="${output_dir}/TraCE_22ka_downscaled_${var}_annual_1500_1990_biascorr.nc"
    out_yr2="${output_dir}/TraCE_22ka_downscaled_${var}_annual_1500_1990_biascorr_noSpat.nc"
    echo "Regridding and then temporally aggregating ${in_yr}"
    cdo -s -b F32 -P 100 "$op_yr" -remap,"$targetgrid","$wgt_ann" "$in_yr" "$out_yr"
    echo "Temporally aggregating ${in_yr}"
    cdo -s -b F32 -P 100 "$op_yr" "$in_yr" "$out_yr2"
done