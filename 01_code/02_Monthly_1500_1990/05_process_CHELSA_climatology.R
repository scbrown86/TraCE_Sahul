library(terra)
setGDALconfig("GDAL_PAM_ENABLED", "FALSE") # don't write aux files!
terraOptions(memfrac = 0.85, memmax = 20)
library(gtools)
library(pbapply)
library(rnaturalearthhires)
library(qgisprocess)
library(data.table)

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
  # calculate the climatological average, and mask to land only
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

# Load in the land/sea mask
chelsa_mask <- rast("/mnt/Data/CHELSA_Trace21/Input/CHELSA_TraCE21k_dem_20_V1.0.tif",
                    win = ext(105.0, 161.25, -52.5, 11.25))
chelsa_mask <- ifel(is.na(chelsa_mask), NA_integer_, 1L)
chelsa_mask <- project(chelsa_mask, pr_avg, "near")

# Mask the CHELSA v1.2 data
pr_avg <- mask(pr_avg, chelsa_mask)
tmn_avg <- mask(tmn_avg, chelsa_mask)
tmx_avg <- mask(tmx_avg, chelsa_mask)
tas_avg <- mask(tas_avg, chelsa_mask)

plot(pr_avg[[1]], range = c(0, 0.0003), fill_range = TRUE, fun = function() lines(land), col = hcl.colors(100, "YlGnBu", rev = TRUE))
plot(tas_avg[[1]], range = c(5, 30), fill_range = TRUE, fun = function() lines(land), col = hcl.colors(100, "Spectral", rev = TRUE))
plot(app(pr_avg, sum), range = c(0, 0.002), fill_range = TRUE, fun = function() lines(land), col = hcl.colors(100, "YlGnBu", rev = TRUE))
plot(tmx_avg[[1]] - tmn_avg[[1]])

# convert the CHELSA climatology data to 0.5 degree using b-splines
source("01_code/00_functions/interpolate_bspline.R")

fine_clim <- list(pr_avg, tmn_avg, tmx_avg)
varnames(fine_clim[[1]]) <- "pr"
varnames(fine_clim[[2]]) <- "tasmin"
varnames(fine_clim[[3]]) <- "tasmax"
fine_clim

# multilevel b-spline to 0.05°
# plot(pr_avg[[1]])
# pr_avg <- mask(pr_avg, chelsa_mask)
# varnames(pr_avg) <- "pr"
# longnames(pr_avg) <- "precipitation"
# pr_avg
# upscaled_CHELSA_pr <- interpolate_bspline(pr_avg,
#                                           output_dir = "02_data/02_processed/CHELSA",
#                                           bspline_ext = ext(105.0, 161.25, -52.5, 11.25),
#                                           target_size = 0.05, ## <
#                                           parallel_cores = 12L,
#                                           start_date = as.Date("1980-01-16"),
#                                           outname_template = "CHELSA_0p05_%s_climatology.nc",
#                                           algo = "bspline", ## <
#                                           load_exist = TRUE)

# multilevel b-spline to 0.5°
coarse_chelsa_clim <- lapply(fine_clim, interpolate_bspline,
  output_dir = "02_data/02_processed/CHELSA",
  bspline_ext = ext(105.0, 161.25, -52.5, 11.25),
  target_size = 0.5,
  parallel_cores = 12L,
  start_date = as.Date("1985-01-16"),
  outname_template = "CHELSA_coarse_%s_climatology.nc",
  algo = "bspline", ## <
  load_exist = TRUE)
names(coarse_chelsa_clim) <- c("pr", "tasmin", "tasmax")
coarse_chelsa_clim

plot(app(coarse_chelsa_clim$pr, sum)*86400*12, range = c(0, 3000), fill_range = TRUE, fun = function() lines(land), col = hcl.colors(100, "YlGnBu", rev = TRUE))
panel(coarse_chelsa_clim$tasmin, range = c(5, 30), fill_range = TRUE, fun = function() lines(land), col = hcl.colors(100, "Spectral", rev = TRUE))
panel(coarse_chelsa_clim$tasmax, range = c(5, 30), fill_range = TRUE, fun = function() lines(land), col = hcl.colors(100, "Spectral", rev = TRUE))
panel(coarse_chelsa_clim$tasmax - coarse_chelsa_clim$tasmin, range = c(0, 10), fill_range = TRUE, fun = function() lines(land), col = hcl.colors(100, "Spectral", rev = TRUE))


#### TRACE ####
# load in our downscaled TraCE data
brown <- list(rast("/media/dafcluster4/storage/TraCE_1500_1990CE/1500_1990/out/pr/TraCE_downscaled_1500_1990_concat.nc",
                   lyrs = 5761:5880),
              rast("/media/dafcluster4/storage/TraCE_1500_1990CE/1500_1990/out/tasmin/TraCE_downscaled_1500_1990_concat.nc",
                   lyrs = 5761:5880)-273.15,
              rast("/media/dafcluster4/storage/TraCE_1500_1990CE/1500_1990/out/tasmax/TraCE_downscaled_1500_1990_concat.nc",
                   lyrs = 5761:5880)-273.15)
brown
# make climatological monthly averages from 1980-1989
brown <- pblapply(brown, function(i) {
  if (nlyr(i) != 12) {
    time(i) <- seq(as.Date("1980-01-16"), by = "month", l = 120)
    i <- tapp(i, index = "month", fun = "mean")
    i
  } else {
    time(i) <- seq(as.Date("1985-01-16"), by = "month", l = 12)
    i
  }
})
varnames(brown[[1]]) <- "pr"
varnames(brown[[2]]) <- "tasmin"
varnames(brown[[3]]) <- "tasmax"
units(brown[[1]]) <- "kg/m2/s"
units(brown[[2]]) <- units(brown[[3]]) <- "deg_C"
names(brown) <- c("pr", "tasmin", "tasmax")
brown
minmax(brown$tasmax - brown$tasmin)

brown_pr <- rast("/media/dafcluster4/storage/TraCE_1500_1990CE/1500_1990/out/pr/TraCE_downscaled_1500_1990_concat.nc",
                   lyrs = 5761:5880)
time(brown_pr) <- seq(as.Date("1980-01-16"), by = "month", l = 120)
brown_pr <- tapp(brown_pr, "months", mean)
varnames(brown_pr) <- "pr"
units(brown_pr) <- "kg/m2/s"
brown_pr
plot(brown_pr[[1]])
expanded_downTrace_pr <- interpolate_bspline(brown_pr,
                                          output_dir = "02_data/02_processed/TRACE",
                                          bspline_ext = ext(105.0, 161.25, -52.5, 11.25),
                                          target_size = 0.05, ## <
                                          parallel_cores = 12L,
                                          start_date = as.Date("1980-01-16"),
                                          outname_template = "TraCE_0p05_%s_climatology.nc",
                                          algo = "bspline", ## <
                                          load_exist = TRUE)

brown_climatologies <- c(
  "02_data/02_processed/TRACE/TraCE_coarse_pr_climatology.nc",
  #"02_data/02_processed/TRACE/TraCE_coarse_tas_climatology.nc",
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
  names(brown) <- c("pr", "tasmin", "tasmax")
  brown
  # convert TraCE climatology to 0.5 degrees
  if (!dir.exists("02_data/02_processed/TRACE")) {
    dir.create("02_data/02_processed/TRACE", recursive = TRUE)
  }
  # multilevel b-spline to 0.5°
  coarse_trace_clim <- lapply(brown, interpolate_bspline,
    output_dir = "02_data/02_processed/TRACE",
    bspline_ext = ext(105.0, 161.25, -52.5, 11.25),
    target_size = 0.5,
    parallel_cores = 12,
    start_date = as.Date("1985-01-16"),
    outname_template = "TraCE_coarse_%s_climatology.nc",
    algo = "bspline", ## <
    load_exist = TRUE)
  names(coarse_trace_clim) <- c("pr", "tasmin", "tasmax")
  coarse_trace_clim
} else {
  coarse_trace_clim <- lapply(brown_climatologies, rast)
  names(coarse_trace_clim) <- c("pr", "tasmax", "tasmin")
}
coarse_trace_clim

panel(0.5 * (coarse_trace_clim$tasmax + coarse_trace_clim$tasmin), # avg temps
     fun = function() lines(land),
     range = c(5, 35), fill_range = TRUE,
     col = hcl.colors(100, "spectral", rev = TRUE))
panel(coarse_trace_clim$tasmax - coarse_trace_clim$tasmin, # DTR
     range = c(0, 16), fill_range = TRUE, 
     col = hcl.colors(100, "spectral", rev = TRUE),
     fun = function() lines(land))
minmax(coarse_trace_clim$tasmax - coarse_trace_clim$tasmin) # some negative dtr values


#### DELTAS ####
# create delta between the CHELSA and downscaled TraCE climatology
rbind(
  minmax(coarse_chelsa_clim$pr * (c(31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31) * 86400)),
  minmax(coarse_trace_clim$pr * (c(31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31) * 86400)))

# simple delta correction for precip.
delta_pr <- (coarse_chelsa_clim$pr + 1e-4) / (coarse_trace_clim$pr + 1e-4)
varnames(delta_pr) <- "pr"
longnames(delta_pr) <- "precipitation delta"
units(delta_pr) <- ""
delta_pr
panel(delta_pr[[1:4]], fun = function() lines(land, col = "#000000"),
     range = c(0, 2), fill_range = TRUE,
     col = hcl.colors(100, "mako"))

# Tempaerture correction is a multi step process. 
# correct mean temperature with additive delta
# correct dtr with ratio
# calculate new min/max as corr. tas +/- 0.5 * corr. dtr

# average temperature delta
## average chelsa - average downscaled TraCE
delta_tmean <- (0.5 * (coarse_chelsa_clim$tasmax + coarse_chelsa_clim$tasmin)) - 
                (0.5 * (coarse_trace_clim$tasmax + coarse_trace_clim$tasmin))
varnames(delta_tmean) <- "tas"
longnames(delta_tmean) <- "mean air temperature delta"
units(delta_tmean) <- "deg_C"
delta_tmean
panel(delta_tmean, fun = function() lines(land),
     range = c(-10, 10), fill_range = TRUE, col = hcl.colors(100, "Spectral", rev = TRUE))

# diurnal temperature range
## any negative oe zero values will be changed to 0.05°C
## downscaled TraCE
downTrace_dtr <- coarse_trace_clim$tasmax - coarse_trace_clim$tasmin
sum(values(downTrace_dtr) <= 0, na.rm = TRUE)/(ncell(downTrace_dtr)*nlyr(downTrace_dtr)) * 100 # ~1%
downTrace_dtr <- ifel(downTrace_dtr <= 0, 0.05, downTrace_dtr)

chelsa_dtr <- coarse_chelsa_clim$tasmax - coarse_chelsa_clim$tasmin
sum(values(chelsa_dtr) <= 0, na.rm = TRUE)/(ncell(chelsa_dtr)*nlyr(chelsa_dtr)) * 100 # ~ 0.002% (4 cells in total)
chelsa_dtr <- ifel(chelsa_dtr <= 0, 0.05, chelsa_dtr)

delta_dtr <- chelsa_dtr / downTrace_dtr
delta_dtr[!is.finite(delta_dtr)] <- 1 # set any infinite to 1
sum(values(delta_dtr) <= 0, na.rm = TRUE) # 0
varnames(delta_dtr) <- "dtr"
longnames(delta_dtr) <- "diurnal temperature range delta"
units(delta_dtr) <- ""
delta_dtr
panel(delta_dtr, range = c(0, 5), fill_range = TRUE, 
     col = hcl.colors(100, "Spectral", rev = TRUE),
     fun = function() lines(land))

# convert the delta back to 0.05 degrees using bilinear interpolation
if (!dir.exists("02_data/02_processed/deltas")) {
  dir.create("02_data/02_processed/deltas", recursive = TRUE)
}
deltas <- list(delta_pr, delta_tmean, delta_dtr)
deltas
deltas_fine <- lapply(deltas, interpolate_bspline,
  output_dir = "02_data/02_processed/deltas",
  bspline_ext = ext(105.0, 161.25, -52.5, 11.25),
  target_size = 0.05,
  parallel_cores = 12,
  start_date = as.Date("1985-01-16"),
  outname_template = "delta_fine_%s_climatology.nc",
  algo = "bilinear", ## <
  delta = TRUE, ## <
  load_exist = FALSE)
names(deltas_fine) <- c("pr", "tas", "dtr")
deltas_fine
deltas_fine$pr*1
panel(deltas_fine$pr, fun = function() lines(land),
     range = c(0, 2), fill_range = TRUE,
     breaks = seq(0, 2, by = 0.1),
     col = hcl.colors(20, "Spectral"))
panel(deltas_fine$tas, fun = function() lines(land),
     range = c(-10, 10), fill_range = TRUE, col = hcl.colors(100, "Spectral"))
plot(deltas_fine$dtr, fun = function() lines(land),
     range = c(0, 5), fill_range = TRUE, col = hcl.colors(100, "Spectral", rev = TRUE))

# test the corrections on the 1980-1989 data
## read the data back in
brown_8089 <- list(rast("/media/dafcluster4/storage/TraCE_1500_1990CE/1500_1990/out/pr/TraCE_downscaled_1500_1990_concat.nc",
                   lyrs = 5761:5880),
              rast("/media/dafcluster4/storage/TraCE_1500_1990CE/1500_1990/out/tasmin/TraCE_downscaled_1500_1990_concat.nc",
                   lyrs = 5761:5880)-273.15,
              rast("/media/dafcluster4/storage/TraCE_1500_1990CE/1500_1990/out/tasmax/TraCE_downscaled_1500_1990_concat.nc",
                   lyrs = 5761:5880)-273.15)
names(brown_8089) <- c("pr", "tasmin", "tasmax")
brown_8089

brown_pr_corr <- (brown_8089$pr * deltas_fine$pr) * 86400 * c(31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31)
brown_pr_corr
panel(tapp(brown_pr_corr, "month", mean), range = c(0, 400), 
     col = hcl.colors(100, "YlGnBu", rev = TRUE),
     fill_range = TRUE, fun = function() lines(land))

brown_tas_corr <- (0.5 * (brown_8089$tasmax + brown_8089$tasmin)) + deltas_fine$tas
panel(tapp(brown_tas_corr, "month", mean), 
     range = c(5, 30), fill_range = TRUE,
     col = hcl.colors(100, "spectral", rev = TRUE),
     fun = function() lines(land))

# dtr correction
brown_dtr_corr <- (brown_8089$tasmax - brown_8089$tasmin)
brown_dtr_corr <- ifel(brown_dtr_corr <= 0, 0.05, brown_dtr_corr)
brown_dtr_corr <- brown_dtr_corr * deltas_fine$dtr # multiply by the dtr correction

plot(tapp(brown_dtr_corr, "month", mean), 
     range = c(0, 16), fill_range = TRUE, 
     col = hcl.colors(100, "spectral", rev = TRUE),
     fun = function() lines(land))

# Quick check for unusually high dtr values
high_dtr <- setorder(setDT(as.data.frame(where.max(brown_dtr_corr))), -value)
hist(high_dtr[["value"]])
abline(v = quantile(high_dtr[["value"]], c(0.25, 0.5, 0.75, 0.90)))

high_locs <- copy(high_dtr)[, .(value = max(value)), by = c("cell", "layer")][value >= 35, ]
high_locs <- vect(xyFromCell(brown_dtr_corr, high_locs[["cell"]]), 
                  crs = "EPSG:4326")
plot(app(brown_dtr_corr, max),
     breaks = c(-Inf, 35, Inf),
     col = c("#4daf4a", "#e41a1c"),
     fun = function() {
       lines(land)
       points(high_locs, pch = 19, bg = "#e41a1c")
     },
     buffer = TRUE)

# What are the DTR correction factors at those locations?
extract(deltas_fine$dtr, high_locs)

# very high values in May (layer 5) and August (layer 8)
hist(as.vector(values(deltas_fine$dtr[[c(5, 8)]])))
abline(v = quantile(as.vector(values(deltas_fine$dtr[[c(5, 8)]])), 
                    c(0.25, 0.5, 0.75, 0.95)))

# Mask to 22k BP mask (maximum extent ever seen)
mask_22k <- rast("/mnt/Data/CHELSA_Trace21/Input/CHELSA_TraCE21k_dem_-200_V1.0.tif",
                win = ext(105.0, 161.25, -52.5, 11.25),
                snap = "out")
mask_22k <- ifel(is.na(mask_22k), 0L, 1L)
mask_22k <- project(mask_22k, deltas_fine$pr, method = "mode")
mask_22k <- ifel(mask_22k == 0, NA_integer_, 1L)
mask_22k
plot(mask_22k, fun = function() lines(land))
deltas_fineMasked <- pblapply(deltas_fine, function(i) {
  mask(i, mask_22k)
})
deltas_fineMasked

# what are the percentiles for those masked layers
minmax(deltas_fineMasked$dtr[[c(5,8)]])
quantile(as.vector(values(deltas_fineMasked$dtr[[5]])), c(0.25, 0.5, 0.75, 0.95, 0.99), na.rm = TRUE)
quantile(as.vector(values(deltas_fineMasked$dtr[[8]])), c(0.25, 0.5, 0.75, 0.95, 0.99), na.rm = TRUE)

# replace extreme values with 99th percentile
dtr5_99 <- quantile(as.vector(values(deltas_fineMasked$dtr[[5]])), 0.99, na.rm = TRUE)
dtr8_99 <- quantile(as.vector(values(deltas_fineMasked$dtr[[8]])), 0.99, na.rm = TRUE)
deltas_fineMasked$dtr[[5]] <- ifel(deltas_fineMasked$dtr[[5]] > dtr5_99, dtr5_99, deltas_fineMasked$dtr[[5]])
deltas_fineMasked$dtr[[8]] <- ifel(deltas_fineMasked$dtr[[8]] > dtr5_99, dtr5_99, deltas_fineMasked$dtr[[8]])

# multiply by the correction (again)
brown_dtr_corr <- (brown_8089$tasmax - brown_8089$tasmin)
brown_dtr_corr <- ifel(brown_dtr_corr <= 0, 0.05, brown_dtr_corr)
brown_dtr_corr <- brown_dtr_corr * deltas_fineMasked$dtr
brown_dtr_corr

# what does the corrected monthly DTR look like?
plot(tapp(brown_dtr_corr, "month", mean), 
     range = c(0, 16), fill_range = TRUE, 
     col = hcl.colors(100, "spectral", rev = TRUE),
     fun = function() lines(land))

brown_tmax_corr <- round(brown_tas_corr + (0.5 * deltas_fineMasked$dtr), 2)
varnames(brown_tmax_corr) <- "tasmax"
longnames(brown_tmax_corr) <- "maximum air temperature"
units(brown_tmax_corr) <- "deg_C"
time(brown_tmax_corr) <- seq(as.Date("1980-01-16"), by = "month", l = nlyr(brown_tmax_corr))
brown_tmax_corr

# what do the corrected monthly avg max temps look like?
panel(tapp(brown_tmax_corr, "month", mean),
     range = c(5, 35), fill_range = TRUE,
     main = paste0(month.abb, " corrected tasmax"),
     col = hcl.colors(100, "spectral", rev = TRUE),
     fun = function() lines(land))

## tmin = avg tas - 0.5*dtr
brown_tmin_corr <- round(brown_tas_corr - (0.5 * deltas_fineMasked$dtr), 2)
varnames(brown_tmin_corr) <- "tasmin"
longnames(brown_tmin_corr) <- "minimum air temperature"
units(brown_tmin_corr) <- "deg_C"
time(brown_tmin_corr) <- seq(as.Date("1980-01-16"), by = "month", l = nlyr(brown_tmin_corr))
brown_tmin_corr

# what do the corrected monthly avg max temps look like?
panel(tapp(brown_tmin_corr, "month", mean),
     range = c(5, 35), fill_range = TRUE,
     main = paste0(month.abb, " corrected tasmin"),
     col = hcl.colors(100, "spectral", rev = TRUE),
     fun = function() lines(land))

# Is corrected tmax ever less than tmin?
dtr_temp_anoms <- app(brown_tmax_corr < brown_tmin_corr, sum)
dtr_temp_anoms

# save the masked deltas to netcdf
source("01_code/00_functions/spatraster_to_netcdf.r")

time(deltas_fineMasked$pr, tstep = "months") <- 1:12
time(deltas_fineMasked$tas, tstep = "months") <- 1:12
time(deltas_fineMasked$dtr, tstep = "months") <- 1:12

write_spatraster_ncdf(
  deltas_fineMasked$pr,
  "02_data/02_processed/deltas/delta_fine_delta_pr_climatology_ncdf4.nc")
write_spatraster_ncdf(
  deltas_fineMasked$tas,
  "02_data/02_processed/deltas/delta_fine_delta_tas_climatology_ncdf4.nc")
write_spatraster_ncdf(
  deltas_fineMasked$dtr,
  "02_data/02_processed/deltas/delta_fine_delta_dtr_climatology_ncdf4.nc")
