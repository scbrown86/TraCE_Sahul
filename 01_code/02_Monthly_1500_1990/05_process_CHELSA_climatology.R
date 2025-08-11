library(terra)
setGDALconfig("GDAL_PAM_ENABLED", "FALSE") # don't write aux files!
terraOptions(memfrac = 0.85, memmax = 20)
library(gtools)
library(pbapply)
library(rnaturalearthhires)
library(qgisprocess)

# safe
safe_spline <- purrr::safely(qgisprocess::qgis_run_algorithm,
  otherwise = NULL, quiet = TRUE
)

land <- vect(rnaturalearthhires::countries10)
land <- crop(land, ext(105.0, 161.25, -52.5, 11.25))
land <- aggregate(land)
land
plot(land)

source("01_code/00_functions/interpolate_bspline.R")
source("01_code/00_functions/chelsa_proc.R")
source("01_code/00_functions/qmap_precip_delta.R")

#### CHELSA ####

# load in CHELSA V1.2 data at original res
# calculate averages between 1980 and 1989
if (!dir.exists("02_data/02_processed/CHELSA")) {
  dir.create("02_data/02_processed/CHELSA", recursive = TRUE)
}
processed_chelsa <- lapply(c("prec", "tmin", "tmax", "tmean"),
  FUN = chelsa_proc,
  mask = NULL,
  ymin = 1980, ymax = 1989,
  tras_ext = ext(105.0, 161.25, -52.5, 11.25),
  load_exist = TRUE,
  dir = "/mnt/Data/CHELSA/v1.2",
  outdir = "02_data/02_processed/CHELSA",
  cores = 5L)
names(processed_chelsa) <- c("pr", "tasmin", "tasmax", "tas")
str(processed_chelsa)

# Calculate the climatological averages
terraOptions(memfrac = 0.85, memmax = 50)
pr_avg <- rast(processed_chelsa$pr)
pr_avg
plot(pr_avg[[1]], col = hcl.colors(100, "Batlow"), fun = function() lines(land))

tmn_avg <- rast(processed_chelsa$tasmin)
tmx_avg <- rast(processed_chelsa$tasmax)
tas_avg <- rast(processed_chelsa$tas)
time(tmn_avg) <- time(tmx_avg) <- time(tas_avg) <- time(pr_avg)
tas_avg
plot(tas_avg[[1]], col = hcl.colors(100, "Batlow"), fun = function() lines(land))
idx <- format(time(pr_avg), "%b")

chelsa_climatologies <- c(
  "02_data/02_processed/CHELSA/CHELSA_pr_climatology.nc",
  "02_data/02_processed/CHELSA/CHELSA_tasmin_climatology.nc",
  "02_data/02_processed/CHELSA/CHELSA_tasmax_climatology.nc",
  "02_data/02_processed/CHELSA/CHELSA_tas_climatology.nc")

if (!all(file.exists(chelsa_climatologies))) {
  pr_avg <- tapp(pr_avg, idx, mean, cores = 12L)
  tmn_avg <- tapp(tmn_avg, idx, mean, cores = 12L)
  tmx_avg <- tapp(tmx_avg, idx, mean, cores = 12L)
  tas_avg <- tapp(tas_avg, idx, mean, cores = 12L)
  tas_avg
  # set time for variables
  time(pr_avg) <- time(tmn_avg) <- time(tas_avg) <- time(tmx_avg) <- seq(as.Date("1985-01-16"), by = "month", l = 12)
  # precip units
  units(pr_avg) <- "kg/m2/s"
  varnames(pr_avg) <- "precip"
  terra::longnames(pr_avg) <- "precipitation"
  # temperature units
  units(tmn_avg) <- units(tmx_avg) <- units(tas_avg) <- "deg_C"
  writeCDF(pr_avg, "02_data/02_processed/CHELSA/CHELSA_pr_climatology.nc",
    varname = "pr", longname = "precipitation", # compression = 6L,
    unit = "kg/m2/s", zname = "time", prec = "float",
    overwrite = TRUE)
  writeCDF(tmn_avg, "02_data/02_processed/CHELSA/CHELSA_tasmin_climatology.nc",
    varname = "tasmin",
    longname = "minimum near surface air temperature",
    unit = "deg_C", zname = "time", prec = "float",
    overwrite = TRUE)
  writeCDF(tmx_avg, "02_data/02_processed/CHELSA/CHELSA_tasmax_climatology.nc",
    varname = "tasmax",
    longname = "maximum near surface air temperature",
    unit = "deg_C", zname = "time", prec = "float",
    overwrite = TRUE)
  writeCDF(tas_avg, "02_data/02_processed/CHELSA/CHELSA_tas_climatology.nc",
    varname = "tas",
    longname = "mean near surface air temperature",
    unit = "deg_C", zname = "time", prec = "float",
    overwrite = TRUE)
} else {
  pr_avg <- rast("02_data/02_processed/CHELSA/CHELSA_pr_climatology.nc")
  tmn_avg <- rast("02_data/02_processed/CHELSA/CHELSA_tasmin_climatology.nc")
  tmx_avg <- rast("02_data/02_processed/CHELSA/CHELSA_tasmax_climatology.nc")
  tas_avg <- rast("02_data/02_processed/CHELSA/CHELSA_tas_climatology.nc")
}

### RUN THIS IN A TERMINAL ####
# conda activate nco_stable
# BASE_DIR="/home/dafcluster4/Documents/GitHub/TraCE_Sahul/02_data/02_processed/CHELSA"
# cdo -f nc sellonlatbox,105,161.25,-52.5,11.25 -const,1,global_0.5 "${BASE_DIR}/agg_target.nc"
# export CDO_REMAP_NORM="destarea"
# export REMAP_AREA_MIN=0.10
# gdal_translate "${BASE_DIR}/CHELSA_pr_climatology.nc" "${BASE_DIR}/CHELSA_pr_climatology_gdal.nc"
# cdo -P 100 gencon,"${BASE_DIR}/agg_target.nc" "${BASE_DIR}/CHELSA_pr_climatology_gdal.nc" "${BASE_DIR}/pr_weights.nc"
# export CDO_REMAP_NORM="fracarea"
# export REMAP_AREA_MIN=0.10
# gdal_translate "${BASE_DIR}/CHELSA_tas_climatology.nc" "${BASE_DIR}/CHELSA_tas_climatology_gdal.nc"
# cdo -P 100 gencon,"${BASE_DIR}/agg_target.nc" "${BASE_DIR}/CHELSA_tas_climatology_gdal.nc" "${BASE_DIR}/tas_weights.nc"

# export CDO_REMAP_NORM="destarea"
# export REMAP_AREA_MIN=0.10
# cdo -s -b F32 -P 100 \
#             -remap,"${BASE_DIR}/agg_target.nc","${BASE_DIR}/pr_weights.nc"  \
#             -setunit,'mm/month' \
#             -muldpm \
#             -mulc,86400 \
#             "${BASE_DIR}/CHELSA_pr_climatology_gdal.nc" "${BASE_DIR}/CHELSA_pr_climatology_coarse_remapcon.nc"

# export CDO_REMAP_NORM="fracarea"
# export REMAP_AREA_MIN=0.10
# gdal_translate "${BASE_DIR}/CHELSA_tasmax_climatology.nc" "${BASE_DIR}/CHELSA_tasmax_climatology_gdal.nc"
# gdal_translate "${BASE_DIR}/CHELSA_tasmin_climatology.nc" "${BASE_DIR}/CHELSA_tasmin_climatology_gdal.nc"
# cdo -s -b F32 -P 100 remap,"${BASE_DIR}/agg_target.nc","${BASE_DIR}/tas_weights.nc" "${BASE_DIR}/CHELSA_tas_climatology_gdal.nc" "${BASE_DIR}/CHELSA_tas_climatology_coarse_remapcon.nc"
# cdo -s -b F32 -P 100 remap,"${BASE_DIR}/agg_target.nc","${BASE_DIR}/tas_weights.nc" "${BASE_DIR}/CHELSA_tasmax_climatology_gdal.nc" "${BASE_DIR}/CHELSA_tasmax_climatology_coarse_remapcon.nc"
# cdo -s -b F32 -P 100 remap,"${BASE_DIR}/agg_target.nc","${BASE_DIR}/tas_weights.nc" "${BASE_DIR}/CHELSA_tasmin_climatology_gdal.nc" "${BASE_DIR}/CHELSA_tasmin_climatology_coarse_remapcon.nc"

# rm -rf "${BASE_DIR}/CHELSA_pr_climatology_gdal.nc" "${BASE_DIR}/CHELSA_tas_climatology_gdal.nc" "${BASE_DIR}/CHELSA_tasmax_climatology_gdal.nc" "${BASE_DIR}/CHELSA_tasmin_climatology_gdal.nc"

#### END ####

# pr_avg <- rast("02_data/02_processed/CHELSA/CHELSA_pr_climatology_coarse_remapcon.nc")
# tmn_avg <- rast("02_data/02_processed/CHELSA/CHELSA_tasmin_climatology_coarse_remapcon.nc")
# tmx_avg <- rast("02_data/02_processed/CHELSA/CHELSA_tasmax_climatology_coarse_remapcon.nc")
# tas_avg <- rast("02_data/02_processed/CHELSA/CHELSA_tas_climatology_coarse_remapcon.nc")

plot(pr_avg, range = c(0, 0.0003), fill_range = TRUE, fun = function() lines(land), col = hcl.colors(100, "YlGnBu", rev = TRUE))
plot(app(pr_avg, sum), range = c(0, 0.002), fill_range = TRUE, fun = function() lines(land), col = hcl.colors(100, "YlGnBu", rev = TRUE))
plot(tas_avg, range = c(5, 30), fill_range = TRUE, fun = function() lines(land), col = hcl.colors(100, "Spectral", rev = TRUE))
# convert the CHELSA climatology data to 0.5 degree using b-splines
source("01_code/00_functions/interpolate_bspline.R")
fine_clim <- list(pr_avg, tas_avg, tmn_avg, tmx_avg)
varnames(fine_clim[[1]]) <- "pr"
varnames(fine_clim[[2]]) <- "tas"
varnames(fine_clim[[3]]) <- "tasmin"
varnames(fine_clim[[4]]) <- "tasmax"
# convert back to kg/m2/s
## fine_clim[[1]] <- fine_clim[[1]] / (86400 * c(31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31))
coarse_chelsa_clim <- lapply(fine_clim, interpolate_bspline,
  output_dir = "02_data/02_processed/CHELSA",
  bspline_ext = ext(105.0, 161.25, -52.5, 11.25),
  target_size = 0.5,
  parallel_cores = 12,
  start_date = as.Date("1985-01-16"),
  outname_template = "CHELSA_coarse_%s_climatology.nc",
  load_exist = TRUE)
names(coarse_chelsa_clim) <- c("pr", "tas", "tasmin", "tasmax")
coarse_chelsa_clim

plot(app(coarse_chelsa_clim$pr, sum)*86400*12, range = c(0, 1600), fill_range = TRUE, fun = function() lines(land), col = hcl.colors(100, "YlGnBu", rev = TRUE))

#### TRACE ####
# load in the raw trace data
brown <- rast("/media/dafcluster4/storage/TraCE_Monthly/PRECC/trace.01-36.22000BP-1990CE.cam2.h0.PRECC.0000101-2204012.Sahul.concat.1500_1989CE.nc",
              lyrs = 5761:5880) +
          rast("/media/dafcluster4/storage/TraCE_Monthly/PRECL/trace.01-36.22000BP-1990CE.cam2.h0.PRECL.0000101-2204012.Sahul.concat.1500_1989CE.nc",
              lyrs = 5761:5880)
time(brown) <- seq(as.Date("1980-01-16"), by = "month", l = 120)
brown <- tapp(brown, index = "month", fun = "mean")
varnames(brown) <- "pr"
units(brown) <- "kg/m2/s"
brown

brown_down <- list.files("/media/dafcluster4/storage/TraCE_1500_1990CE/1500_1990/out",
  recursive = TRUE, pattern = "1980_1990",
  full.names = TRUE)
brown_down <- brown_down[!grepl("coarse|pr", brown_down)]
brown_down <- lapply(brown_down, rast)
brown <- list(brown, brown_down[[1]], brown_down[[2]], brown_down[[3]])
rm(brown_down)
brown

brown_climatologies <- c(
  "02_data/02_processed/TRACE/TraCE_coarse_pr_climatology_coarse.nc",
  "02_data/02_processed/TRACE/TraCE_coarse_tas_climatology.nc",
  "02_data/02_processed/TRACE/TraCE_coarse_tasmax_climatology.nc",
  "02_data/02_processed/TRACE/TraCE_coarse_tasmin_climatology.nc")

if (!all(file.exists(brown_climatologies))) {
  # climatologies
  brown <- pblapply(brown, function(i) {
    if(!inherits(i, "SpatRaster")) {
      r <- rast(i)
    } else {
      r <- i
    }    
    time(r) <- seq(as.Date("1985-01-16"), by = "month", l = nlyr(r))
    r_u <- units(r)[1]
    r_v <- varnames(r[[1]])
    l_v <- longnames(r[[1]])
    r <- r*1
    units(r) <- r_u
    crs(r) <- "EPSG:4326"
    if (r_u == "K") {
      r <- setValues(r, values(r) - 273.15)
      units(r) <- "deg_C"
    }
    if (r_u == "mm/month") {
      r <- setValues(r, values(r) / (c(31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31) * 86400))
      units(r) <- "kg/m2/s"
    }
    varnames(r) <- r_v
    longnames(r) <- l_v
    time(r) <- seq(as.Date("1985-01-16"), by = "month", l = 12)
    names(r) <- month.abb
    return(r)
  })
  names(brown) <- c("pr", "tas", "tasmax", "tasmin")
  brown
  # convert TraCE climatology to 0.5 degrees
  if (!dir.exists("02_data/02_processed/TRACE")) {
    dir.create("02_data/02_processed/TRACE", recursive = TRUE)
  }
  coarse_trace_clim <- lapply(brown, interpolate_bspline,
    output_dir = "02_data/02_processed/TRACE",
    bspline_ext = ext(105.0, 161.25, -52.5, 11.25),
    target_size = 0.5,
    parallel_cores = 12,
    start_date = as.Date("1985-01-16"),
    outname_template = "TraCE_coarse_%s_climatology.nc",
    load_exist = TRUE)
  names(coarse_trace_clim) <- c("pr", "tas", "tasmax", "tasmin")
  coarse_trace_clim
} else {
  coarse_trace_clim <- lapply(brown_climatologies, rast)
  names(coarse_trace_clim) <- c("pr", "tas", "tasmax", "tasmin")
}
coarse_trace_clim

#### DELTAS ####
# create delta between the CHELSA and downscaled TraCE climatology
rbind(
  minmax(coarse_chelsa_clim$pr * (c(31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31) * 86400)),
  minmax(coarse_trace_clim$pr * (c(31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31) * 86400)))

# oro_mask <- rast("/media/dafcluster4/storage/TraCE_22k_1500CE/orog/oro_high.nc",
#                  lyrs = 1)*1
# oro_mask <- ifel(is.na(oro_mask), NA, 1)
# oro_mask <- resample(oro_mask, coarse_trace_clim$pr, "near")
# oro_mask

# plot(coarse_trace_clim$pr[[1]], fun = function() lines(as.polygons(oro_mask)))
# plot(mask(coarse_chelsa_clim$pr / coarse_trace_clim$pr, oro_mask))

# # use qmap procedure for generating pr delta
# delta_pr <- qmap_pr_delta(chelsa_coarse_clim = mask(coarse_chelsa_clim$pr, oro_mask),
#                           trace_coarse_clim = mask(coarse_trace_clim$pr, oro_mask),
#                           high_res_template = rast(brown[1], lyrs = 1), # downscaled output
#                           wet.day = TRUE, smooth = TRUE,
#                           resample_delta = "cubicspline")
# delta_pr
# plot(delta_pr[[1]], fun = function() lines(land, col = "#FFFFFF"),
#      range = c(0.5, 2.5), fill_range = TRUE,
#      col = hcl.colors(100, "Batlow", rev = TRUE))

# # quick test of delta pr
# test_pr <- rast(brown[1])
# time(test_pr) <- time(coarse_trace_clim$pr)
# plot(app(test_pr, sum), range = c(200, 4500), fill_range = TRUE,
#      main = "raw total rainfall",
#      fun = function() lines(land),
#      col = hcl.colors(100, "YlGnBu", rev = TRUE))
# plot(app(test_pr * delta_pr, sum),
#      main = "bias corrected total rainfall",
#      fun = function() lines(land),
#      range = c(200, 4500), fill_range = TRUE,
#      col = hcl.colors(100, "YlGnBu", rev = TRUE))

# # save to netcdf
# time(delta_pr) <- seq(as.Date("1985-01-16"), by = "month", length.out = 12)
# units(delta_pr) <- ""
# varnames(delta_pr) <- "delta"
# longnames(delta_pr) <- "precipitation delta (multiplicative)"
# message("Writing b-spline files to netcdf...")
# writeCDF(delta_pr,
#          filename = "02_data/02_processed/deltas/delta_fine_delta_pr_climatology.nc",
#          varname = "delta",
#          longname = "precipitation delta (multiplicative)",
#          unit = "",
#          zname = "time",
#          prec = "float",
#          overwrite = TRUE)

delta_pr <-( coarse_chelsa_clim$pr + 1e-4) / (coarse_trace_clim$pr + 1e-4)
delta_pr
plot(delta_pr, fun = function() lines(land, col = "#000000"),
     range = c(0, 2), fill_range = TRUE,
     breaks = seq(0, 2, by = 0.1),
     col = hcl.colors(20, "Spectral"))
# temperature delta
delta_tas <- coarse_chelsa_clim$tas - coarse_trace_clim$tas
delta_tas
plot(delta_tas, fun = function() lines(land, col = "#FFFFFF"))

delta_tasmin <- coarse_chelsa_clim$tasmin - coarse_trace_clim$tasmin
delta_tasmin
plot(delta_tasmin, fun = function() lines(land, col = "#FFFFFF"))

delta_tasmax <- coarse_chelsa_clim$tasmax - coarse_trace_clim$tasmax
delta_tasmax
plot(delta_tasmax, fun = function() lines(land, col = "#FFFFFF"))

# convert the delta back to 0.05 degrees using b-splines
## don't need to do this for pr, already 0.05°
if (!dir.exists("02_data/02_processed/deltas")) {
  dir.create("02_data/02_processed/deltas", recursive = TRUE)
}
deltas <- list(delta_pr, delta_tas, delta_tasmin, delta_tasmax)
deltas_fine <- lapply(deltas, interpolate_bspline,
  output_dir = "02_data/02_processed/deltas",
  bspline_ext = ext(105.0, 161.25, -52.5, 11.25),
  target_size = 0.05,
  parallel_cores = 12,
  start_date = as.Date("1985-01-16"),
  outname_template = "delta_fine_%s_climatology.nc",
  load_exist = TRUE,
  delta = TRUE)
names(deltas_fine) <- c("pr", "tas", "tasmin", "tasmax")
deltas_fine
deltas_fine$pr*1
plot(deltas_fine$pr)

# save the deltas to netcdf
source("01_code/00_functions/spatraster_to_netcdf.r")

time(deltas_fine$pr, tstep = "months") <- 1:12
time(deltas_fine$tas, tstep = "months") <- 1:12
time(deltas_fine$tasmax, tstep = "months") <- 1:12
time(deltas_fine$tasmin, tstep = "months") <- 1:12

write_spatraster_ncdf(
  deltas_fine$pr,
  "02_data/02_processed/deltas/delta_fine_delta_pr_climatology_ncdf4.nc")
write_spatraster_ncdf(
  deltas_fine$tas,
  "02_data/02_processed/deltas/delta_fine_delta_tas_climatology_ncdf4.nc")
write_spatraster_ncdf(
  deltas_fine$tasmax,
  "02_data/02_processed/deltas/delta_fine_delta_tasmax_climatology_ncdf4.nc")
write_spatraster_ncdf(
  deltas_fine$tasmin,
  "02_data/02_processed/deltas/delta_fine_delta_tasmin_climatology_ncdf4.nc")
