library(terra)
library(pbapply)
library(qgisprocess)

setwd("~/Documents/GitHub/TraCE_Sahul")

# used for multi-level bspline
safe_spline <- purrr::safely(qgisprocess::qgis_run_algorithm,
                             otherwise = NULL, quiet = TRUE)
source("01_code/00_functions/interpolate_bspline.R")

land <- vect(rnaturalearthhires::countries10)
land <- crop(land, ext(105, 161.25, -52.5, 11.25))
land <- aggregate(land)

# Calculate delta between CHELSA and raw TraCE data
## this approach using CHELSA V1.2 and TraCE data follows Karger et al.
## except here I'm going to correct with the DTR approach to ensure
## maximum temps are always greater than minimum temps

# template raster at 0.05° res
rast_template <- rast(res = 0.05, crs = "EPSG:4326", vals = 0L,
                      extent = ext(105, 161.25, -52.5, 11.25))
rast_CoarseTemplate <- aggregate(rast_template, fact = 10)

r_test <- rast("/vsicurl/https://os.unil.cloud.switch.ch/chelsa02/chelsa/global/monthly/pr/1980/CHELSA_pr_01_1980_V.2.1.tif",
               win = ext(rast_template))
r_test

## CHELSA at 0.05°
chelsa_files <- pbapply::pblapply(seq(as.Date("1980-01-16"), as.Date("1989-12-16"), by = "month"),
                       function(d) {
                         TraCESahulMisc:::download_CHELSA(
                           x = d,
                           var = "pr",
                           dir = "scratch/chelsa/",
                           template = r_test,
                           algo = "cubicspline",
                           convert = TRUE,
                           mask = FALSE,
                           overwrite = FALSE
                           )})
chelsa_pr <- rast(lapply(chelsa_files, rast))
time(chelsa_pr) <- seq(as.Date("1980-01-16"), by = "month", l = nlyr(chelsa_pr))
chelsa_pr
chelsa_pr <- tapp(chelsa_pr, "month", mean)
varnames(chelsa_pr) <- "pr"
units(chelsa_pr) <- "kg m-2 s-1"
time(chelsa_pr) <- seq(as.Date("1985-01-16"), by = "month", l = 12)
chelsa_pr
plot(chelsa_pr[[1]])

writeCDF(chelsa_pr, "scratch/chelsa/chelsa_fine_climatology.nc",
         varname = "pr", longname = "precipitation",
         unit = "kg m-2 s-1")


#### RUN THIS IN THE TERMINAL ####

# # Activate environment
# conda activate nco_stable
#
# # Base directory
# BASE_DIR="/home/dafcluster4/Documents/GitHub/TraCE_Sahul/scratch/chelsa"
#
# # Create aggregation target raster (cropped to Sahul)
# cdo -f nc sellonlatbox,105,161.25,-52.5,11.25 \
#     -const,1,global_0.05 \
#     "${BASE_DIR}/agg_target.nc"
#
# # Precipitation weights (destarea)
# export CDO_REMAP_NORM="destarea"
# export REMAP_AREA_MIN=0.10
#
# gdal_translate \
#     "${BASE_DIR}/chelsa_fine_climatology.nc" \
#     "${BASE_DIR}/chelsa_fine_climatology_gdal.nc"
#
# cdo -P 100 gencon,"${BASE_DIR}/agg_target.nc" \
#     "${BASE_DIR}/chelsa_fine_climatology_gdal.nc" \
#     "${BASE_DIR}/pr_weights.nc"
#
# # Remap precipitation (destarea)
# export CDO_REMAP_NORM="destarea"
# export REMAP_AREA_MIN=0.10
#
# cdo -s -b F32 -P 100 \
#     -remap,"${BASE_DIR}/agg_target.nc","${BASE_DIR}/pr_weights.nc" \
#     "${BASE_DIR}/chelsa_fine_climatology_gdal.nc" \
#     "${BASE_DIR}/chelsa_fine_climatology_coarse_remapcon.nc"
#
# # Cleanup temporary GDAL translations
# rm -rf "${BASE_DIR}/chelsa_fine_climatology_gdal.nc"

#### STOP TERMINAL HERE ####

chelsa_pr <- rast("scratch/chelsa/chelsa_fine_climatology_coarse_remapcon.nc")
chelsa_pr

panel(chelsa_pr * 86400, range = c(0, 10), fill_range = TRUE,
      col = hcl.colors(100, "Roma"),
      fun = function() lines(land, col = "white"))


# downTraCE at 0.05°
trace_pr <- rast("/media/dafcluster4/storage/TraCE_1500_1990CE/1500_1990/out/pr/TraCE_downscaled_1500_1990_concat.nc",
                 lyrs = 5761:5880)
trace_pr
time(trace_pr) <- seq(as.Date("1980-01-16"), by = "month", l = 120)
trace_pr <- tapp(trace_pr, index = "month", fun = "mean")
varnames(trace_pr) <- "pr"
units(trace_pr) <- "kg m-2 s-1"
trace_pr
panel(trace_pr * 86400, range = c(0, 10), fill_range = TRUE,
      main = paste0(month.abb, " trace pr"),
      col = hcl.colors(100, "Roma"),
      fun = function() lines(land))

# interpolate with bsplines
coarse_trace_clim <- interpolate_bspline(trace_pr,
                            output_dir = "scratch/",
                            bspline_ext = ext(chelsa_pr),
                            target_size = res(chelsa_pr)[1],
                            parallel_cores = 12,
                            start_date = as.Date("1985-01-16"),
                            outname_template = "TraCE_coarse_%s_climatology.nc",
                            algo = "bspline", ## <
                            load_exist = FALSE)
coarse_trace_clim <- resample(coarse_trace_clim, chelsa_pr, "cubicspline")
names(coarse_trace_clim) <- month.abb
sum(values(coarse_trace_clim) < 0, na.rm = TRUE)
coarse_trace_clim

panel(coarse_trace_clim * 86400, range = c(0, 10), fill_range = TRUE,
      main = paste0(month.abb, " smoothed trace pr"),
      col = hcl.colors(100, "Roma"),
      fun = function() lines(land))

# Mask for delta layer
mask_delta <- rast("/media/dafcluster4/storage/TraCE_22k_1500CE/chunk_out/00001_00012/out/pr/CHELSA_pr_1_V.1.0.nc")
mask_delta <- ifel(is.na(mask_delta), NA_integer_, 1L)
plot(mask_delta)

## Multiplicative bias for pr (avoid division by zero)
delta_pr <- (chelsa_pr + 1e-4) / (coarse_trace_clim + 1e-4)
delta_pr
delta_pr[!is.finite(delta_pr)] <- 1
varnames(delta_pr) <- "pr"
longnames(delta_pr) <- "precip delta"
units(delta_pr) <- ""
sum(values(delta_pr) < 0)
delta_pr
delta_pr <- mask(delta_pr, mask_delta)

breaks <- unique(c(0, 1, seq(1, 5, length.out = 11)))
gradient_cols <- colorRampPalette(c("#c7e9b4", "#081d58"))(10)
cols <- c("red", gradient_cols)

panel(delta_pr,
      type = "interval",
      range = c(0, 5), fill_range = TRUE,
      breaks = breaks, col = cols,
      main = paste0(month.abb, " delta pr"),
      fun = function() lines(land))

# current delta
exis_delta <- rast("02_data/02_processed/deltas/delta_fine_delta_pr_climatology_ncdf4.nc")
exis_delta

panel(exis_delta,
      type = "interval",
      range = c(0, 5), fill_range = TRUE,
      breaks = breaks, col = cols,
      main = paste0(month.abb, " delta pr"),
      fun = function() lines(land))

# Correct the downscaled TraCE data
## data is masked to land only
## projection step here is only to ensure the extents align
downTrace_pr <- rast("/media/dafcluster4/storage/TraCE_1500_1990CE/1500_1990/out/pr/TraCE_downscaled_1500_1990_concat.nc",
                      lyrs = 5761:5880)
compareGeom(downTrace_pr, delta_pr)
time(downTrace_pr) <- seq(as.Date("1980-01-16"), by = "month", l = nlyr(downTrace_pr))
downTrace_pr

# monthly average across climatological period
plot(tapp(downTrace_pr, "month", mean) * 86400,
     main = paste0(month.abb, " 0.05° TraCE pr [1980-1989]"),
     range = c(0, 10), fill_range = TRUE,
     col = hcl.colors(100, "Roma"),
     fun = function() lines(land))

# correct the pr
downTrace_pr_corr <- downTrace_pr * delta_pr
downTrace_pr_corr <- tapp(downTrace_pr_corr, "month", mean)
plot(downTrace_pr_corr * 86400,
     range = c(0, 10), fill_range = TRUE,
     main = paste0(month.abb, " corrected pr"),
     col = hcl.colors(100, "Roma"),
     fun = function() lines(land))

# correct using the existing delta
downTrace_pr_corrExis <- downTrace_pr * exis_delta
downTrace_pr_corrExis <- tapp(downTrace_pr_corrExis, "month", mean)
plot(downTrace_pr_corrExis * 86400,
     range = c(0, 10), fill_range = TRUE,
     main = paste0(month.abb, " corrected pr"),
     col = hcl.colors(100, "Roma"),
     fun = function() lines(land))

# difference between the two?
diff_pr <- ((downTrace_pr_corrExis - downTrace_pr_corr) / downTrace_pr_corr) * 100
diff_pr
panel(diff_pr, range = c(-100, 100),
      fill_range = TRUE,
      col = cptcity::cpt("rc_wildwinds", 100))


# Lets look at what happens at 22ka BP
## all in Kelvin
trace_22pr <- rast("/media/dafcluster4/storage/TraCE_22k_1500CE/chunk_out/00001_00012/out/pr/CHELSA_pr_00001_00012_concat.nc")

# correct mean temperature
trace_22pr_corr <- trace_22pr * delta_pr
trace_22pr_corrExis <- trace_22pr * exis_delta
trace_22ka_diff <- ((trace_22pr_corrExis - trace_22pr_corr) / trace_22pr_corr) * 100

panel(trace_22pr_corr * 86400,
     range = c(0, 10), fill_range = TRUE,
     main = paste0(month.abb, " 22ka BP corr. pr"),
     col = hcl.colors(100, "roma"),
     fun = function() lines(land))

panel(trace_22pr_corrExis * 86400,
     range = c(0, 10), fill_range = TRUE,
     main = paste0(month.abb, " 22ka BP exis. corr. pr"),
     col = hcl.colors(100, "Roma"),
     fun = function() lines(land))

panel(trace_22ka_diff,
     range = c(-100, 100), fill_range = TRUE,
     main = month.abb,
     col = cptcity::cpt("rc_wildwinds", 100),
     fun = function() lines(land))

