#!/bin/bash

cd "/media/dafcluster4/storage/" || {
    echo "Failed to change directory. Exiting."
    exit 1
}

conda deactivate || true
conda activate nco_stable

output_dir="/media/dafcluster4/storage/TraCE_22k_1990CE_CoarseSummary"
mkdir -p "$output_dir" # create it if it doesn’t exist

# target grid for aggregation
cdo -f nc sellonlatbox,105,161.25,-52.5,11.25 -const,1,global_2.5 "${output_dir}/agg_target.nc"
targetgrid="${output_dir}/agg_target.nc"

# create weight files if they don't already exist
pr_weights="${output_dir}/coarse_pr_weights.nc"
pr_weights_ann="${output_dir}/coarse_pr_weights_ann.nc"
tas_weights="${output_dir}/coarse_tas_weights.nc"
tas_weights_ann="${output_dir}/coarse_tas_weights_ann.nc"
src_pr="/media/dafcluster4/storage/TraCE_22k_1500CE/out/pr/TraCE_22ka_downscaled_pr_decadal_21k_1500CE_biascorr.nc"
src_tas="/media/dafcluster4/storage/TraCE_22k_1500CE/out/tasmax/TraCE_22ka_downscaled_tasmax_decadal_21k_1500CE_biascorr.nc"
src_pr_ann="/media/dafcluster4/storage/TraCE_1500_1990CE/1500_1990/out/pr/TraCE_22ka_downscaled_pr_1500_1990_biascorr.nc"
src_tas_ann="/media/dafcluster4/storage/TraCE_1500_1990CE/1500_1990/out/tasmax/TraCE_22ka_downscaled_tasmax_1500_1990_biascorr.nc"

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
    export CDO_REMAP_NORM="fracarea"
    export REMAP_AREA_MIN=0.10
    cdo -P 100 gencon,"$targetgrid" "$src_tas" "$tas_weights"
    cdo -P 100 gencon,"$targetgrid" "$src_tas_ann" "$tas_weights_ann"
fi

vars=(pr tasmax tasmin)

for var in "${vars[@]}"; do
    # sums for precipitation, means otherwise
    if [[ $var == "pr" ]]; then
        export CDO_REMAP_NORM="destarea"
        export REMAP_AREA_MIN=0.10
        op_dec="timselsum,120" # Centennial sums (120 steps = 10 decades =  1 century). 2155 decades = 215.5 centuries, last "century" is only 50 years.
        op_dec3="timselsum,12" # decadal sum. Each 12 steps (months) is decadal average of those months. Sum/Avg 12 "months" to get decadal total/sum
        op_yr="yearsum"        # annual sums
        wgt="$pr_weights"
        wgt_ann="$pr_weights_ann"
    else
        export CDO_REMAP_NORM="fracarea"
        export REMAP_AREA_MIN=0.10
        op_dec="timselmean,120" # Centennial means
        op_dec3="timselmean,12" # decadal mean
        op_yr="yearmean"        # annual mean
        wgt="$tas_weights"
        wgt_ann="$tas_weights_ann"
    fi

    # TraCE_22k_1500CE decadal steps
    in_dec="/media/dafcluster4/storage/TraCE_22k_1500CE/out/${var}/TraCE_22ka_downscaled_${var}_decadal_21k_1500CE_biascorr.nc"
    out_dec="${output_dir}/TraCE_22ka_downscaled_${var}_centennial_21k_1500CE_biascorr.nc"
    out_dec2="${output_dir}/TraCE_22ka_downscaled_${var}_centennial_21k_1500CE_biascorr_noSpat.nc"
    out_dec3="${output_dir}/TraCE_22ka_downscaled_${var}_decadal_21k_1500CE_biascorr_coarseAgg.nc"

    if [[ -f "$out_dec" ]]; then
        echo "Skipping ${out_dec} (already exists)"
    # else
    #     echo "Regridding and then temporally aggregating ${in_dec} -> ${out_dec}"
    #     cdo -s -b F32 -P 100 "$op_dec" -remap,"$targetgrid","$wgt" "$in_dec" "$out_dec"
    #     ncap2 -O -s 'time=array(1,1,$time); time@units=""' "$out_dec" "$out_dec"
    fi

    if [[ -f "$out_dec2" ]]; then
        echo "Skipping ${out_dec2} (already exists)"
    else
        echo "Temporally aggregating ${in_dec} -> ${out_dec2}"
        cdo -s -b F32 -P 100 "$op_dec" "$in_dec" "$out_dec2"
    fi

    if [[ -f "$out_dec3" ]]; then
        echo "Skipping ${out_dec3} (already exists)"
    # else
    #     echo "Regridding ${in_dec} -> ${out_dec3}"
    #     cdo -s -b F32 -P 100 "$op_dec3" -remap,"$targetgrid","$wgt" "$in_dec" "$out_dec3"
    fi

    # TraCE_1500_1990CE annual steps
    in_yr="/media/dafcluster4/storage/TraCE_1500_1990CE/1500_1990/out/${var}/TraCE_22ka_downscaled_${var}_1500_1990_biascorr.nc"
    out_yr="${output_dir}/TraCE_22ka_downscaled_${var}_annual_1500_1990_biascorr.nc"
    out_yr2="${output_dir}/TraCE_22ka_downscaled_${var}_annual_1500_1990_biascorr_noSpat.nc"

    if [[ -f "$out_yr" ]]; then
        echo "Skipping ${out_yr} (already exists)"
    # else
    #     echo "Regridding and then temporally aggregating ${in_yr} -> ${out_yr}"
    #     cdo -s -b F32 -P 100 "$op_yr" -remap,"$targetgrid","$wgt_ann" "$in_yr" "$out_yr"
    fi

    if [[ -f "$out_yr2" ]]; then
        echo "Skipping ${out_yr2} (already exists)"
    else
        echo "Temporally aggregating ${in_yr} -> ${out_yr2}"
        cdo -s -b F32 -P 100 "$op_yr" "$in_yr" "$out_yr2"
    fi
done