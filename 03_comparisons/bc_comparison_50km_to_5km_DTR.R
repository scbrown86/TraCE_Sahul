library(terra)
library(pbapply)
library(qgisprocess)

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

## CHELSA at 0.05°
chelsa_max <- rast("02_data/02_processed/CHELSA/CHELSA_tasmax_climatology.nc")
chelsa_min <- rast("02_data/02_processed/CHELSA/CHELSA_tasmin_climatology.nc")
chelsa_mean <- round(0.5 * (chelsa_max + chelsa_min), 2)
chelsa_dtr <- chelsa_max - chelsa_min
panel(chelsa_dtr, range = c(0, 15), fill_range = TRUE,
     main = paste0(month.abb, " CHELSA V1.2 DTR"),
     col = hcl.colors(100, "inferno"),
     fun = function() lines(land))

## downTraCE at 0.05°
### following Karger et al. raw TraCE (3.75°) has been downscaled to 0.5° using
### multi-level b-sline interpolation
trace_max <- rast("/media/dafcluster4/storage/TraCE_1500_1990CE/1500_1990/out/tasmax/TraCE_downscaled_1500_1990_concat.nc",
                 lyrs = 5761:5880) - 273.15
trace_min <- rast("/media/dafcluster4/storage/TraCE_1500_1990CE/1500_1990/out/tasmin/TraCE_downscaled_1500_1990_concat.nc",
                  lyrs = 5761:5880) - 273.15
time(trace_max) <- time(trace_min) <- seq(as.Date("1980-01-16"), by = "month", l = 120)
trace_max <- tapp(trace_max, index = "month", fun = "mean")
trace_min <- tapp(trace_min, index = "month", fun = "mean")
varnames(trace_max) <- "tasmax"
varnames(trace_min) <- "tasmin"
units(trace_max) <- units(trace_min) <- "C"
trace_max
trace_mean <- round(0.5 * (trace_max + trace_min), 2)
trace_dtr <- trace_max - trace_min
sum(values(trace_dtr) <= 0, na.rm = TRUE)
panel(trace_dtr, range = c(0, 15), fill_range = TRUE,
      main = paste0(month.abb, " downTraCE DTR"),
      col = hcl.colors(100, "inferno"),
      fun = function() lines(land))

brown <- list(trace_max, trace_min)

coarse_trace_clim <- lapply(brown, interpolate_bspline,
                            output_dir = "scratch/",
                            bspline_ext = ext(105.0, 161.25, -52.5, 11.25),
                            target_size = 0.5,
                            parallel_cores = 12,
                            start_date = as.Date("1985-01-16"),
                            outname_template = "TraCE_coarse_%s_climatology.nc",
                            algo = "bspline", ## <
                            load_exist = TRUE)
names(coarse_trace_clim) <- c("tasmax", "tasmin")
coarse_trace_clim$dtr <- coarse_trace_clim$tasmax - coarse_trace_clim$tasmin
sum(values(coarse_trace_clim$dtr) <= 0, na.rm = TRUE)

panel(coarse_trace_clim$dtr)

# some negatives in the DTR. Need to investigate a fix
plot(app(coarse_trace_clim$tasmax < coarse_trace_clim$tasmin, sum, na.rm = FALSE),
     fun = function() lines(land, col = "white"))

# negative dtr in non-sensical. If < 0, set to 0.05°C
coarse_trace_clim$dtr <- ifel(coarse_trace_clim$dtr < 0, 0.5, coarse_trace_clim$dtr)

plot(coarse_trace_clim$dtr, range = c(0, 15), fill_range = TRUE,
     main = paste0(month.abb, " downTraCE DTR"),
     col = hcl.colors(100, "inferno"),
     fun = function() lines(land))

# Check with the raw TraCE temperatures
plot(app(rast("/media/dafcluster4/storage/TraCE_Monthly/TSMX/trace.01-36.22000BP-1990CE.cam2.h0.TSMX.0000101-2204012.Sahul.concat.1500_1989CE.nc",
     lyrs = 5761:5880) <
      rast("/media/dafcluster4/storage/TraCE_Monthly/TSMN/trace.01-36.22000BP-1990CE.cam2.h0.TSMN.0000101-2204012.Sahul.concat.1500_1989CE.nc",
           lyrs = 5761:5880), sum),
     fun = function() lines(land))

# Upscale the CHELSA data to 50km
chelsa_clim <- list(chelsa_max, chelsa_min)
coarse_chelsa_clim <- lapply(chelsa_clim, interpolate_bspline,
                            output_dir = "scratch/",
                            bspline_ext = ext(105.0, 161.25, -52.5, 11.25),
                            target_size = 0.5,
                            parallel_cores = 12,
                            start_date = as.Date("1985-01-16"),
                            outname_template = "CHELSA_coarse_%s_climatology.nc",
                            algo = "bspline", ## <
                            load_exist = FALSE)
names(coarse_chelsa_clim) <- c("tasmax", "tasmin")
coarse_chelsa_clim$dtr <- coarse_chelsa_clim$tasmax - coarse_chelsa_clim$tasmin
sum(values(coarse_chelsa_clim$dtr) <= 0, na.rm = TRUE)
plot(coarse_chelsa_clim$dtr, range = c(0, 15), fill_range = TRUE,
     main = paste0(month.abb, " coarse CHELSA V1.2 DTR"),
     col = hcl.colors(100, "inferno"),
     fun = function() lines(land))

## Additive bias for mean temperature
delta_tmean <- (0.5*(coarse_chelsa_clim$tasmax + coarse_chelsa_clim$tasmin)) -
  (0.5*(coarse_trace_clim$tasmax + coarse_trace_clim$tasmin))
varnames(delta_tmean) <- "tas"
longnames(delta_tmean) <- "mean air temperature delta"
units(delta_tmean) <- "deg_C"
delta_tmean
panel(delta_tmean, range = c(-7, 7), fill_range = TRUE,
      col = hcl.colors(100 ,"Roma", rev = TRUE),
      fun = function() lines(land))

delta_tmean_fine <- interpolate_bspline(delta_tmean,
                                      output_dir = "scratch/",
                                      bspline_ext = ext(rast_template),
                                      target_size = res(rast_template)[1],
                                      parallel_cores = 12,
                                      start_date = as.Date("1985-01-16"),
                                      outname_template = "dtas_%s_fine.nc",
                                      load_exist = FALSE,
                                      algo = "cubicspline",
                                      delta = TRUE)
delta_tmean_fine <- project(delta_tmean_fine, rast_template, "cubicspline")
delta_tmean_fine
plot(delta_tmean_fine, range = c(-7, 7), fill_range = TRUE,
     main = paste0(month.abb, " delta tas"),
     col = hcl.colors(100, "Roma", rev = TRUE),
     fun = function() lines(land))

## Multiplicative bias for DTR (avoid division by zero)
delta_dtr <- coarse_chelsa_clim$dtr / coarse_trace_clim$dtr
delta_dtr
delta_dtr[!is.finite(delta_dtr)] <- 1 # if mod_dtr=0, set ratio=1
plot(delta_dtr, range = c(0, 3), fill_range = TRUE,
     main = paste0(month.abb, " delta DTR"),
     col = hcl.colors(100, "inferno"),
     fun = function() lines(land))
varnames(delta_dtr) <- "dtr"
longnames(delta_dtr) <- "diurnal temperature range delta"
units(delta_dtr) <- "deg_C"
sum(values(delta_dtr) < 0)

delta_dtr_fine <- interpolate_bspline(delta_dtr,
                                      output_dir = "scratch",
                                      bspline_ext = ext(rast_template),
                                      target_size = res(rast_template)[1],
                                      parallel_cores = 12,
                                      start_date = as.Date("1985-01-16"),
                                      outname_template = "dtr_%s_fine.nc",
                                      algo = "cubicspline",
                                      load_exist = FALSE,
                                      delta = TRUE)
delta_dtr_fine <- project(delta_dtr_fine, rast_template, "cubicspline")
delta_dtr_fine
sum(values(delta_dtr) <= 0)
plot(delta_dtr_fine, range = c(0, 3), fill_range = TRUE,
     main = paste0(month.abb, " delta DTR"),
     col = hcl.colors(100, "Spectral", rev = TRUE),
     fun = function() lines(land))

# Correct the downscaled TraCE data
## data is masked to land only
## projection step here is only to ensure the extents align
downTrace_max <- rast("/media/dafcluster4/storage/TraCE_1500_1990CE/1500_1990/out/tasmax/TraCE_downscaled_1500_1990_concat.nc",
                      lyrs = 5761:5880) - 273.15
compareGeom(downTrace_max, delta_dtr_fine)
downTrace_min <- rast("/media/dafcluster4/storage/TraCE_1500_1990CE/1500_1990/out/tasmin/TraCE_downscaled_1500_1990_concat.nc",
                      lyrs = 5761:5880) - 273.15
compareGeom(downTrace_max, delta_tmean_fine)
time(downTrace_max) <- time(downTrace_min) <- seq(as.Date("1980-01-16"), by = "month", l = nlyr(downTrace_max))

# monthly average across climatological period
downTrace_mean <- 0.5 * (downTrace_max + downTrace_min)
downTrace_mean
varnames(downTrace_mean) <- "tas"
longnames(downTrace_mean) <- "mean air temperature"
units(downTrace_mean) <- "deg_C"
time(downTrace_mean) <- seq(as.Date("1980-01-16"), by = "month", l = nlyr(downTrace_mean))
downTrace_mean
plot(tapp(downTrace_mean, "month", mean),
     main = paste0(month.abb, " 0.05° TraCE tas [1980-1989]"),
     range = c(5, 30), fill_range = TRUE,
     col = hcl.colors(100, "inferno"),
     fun = function() lines(land))

# diurnal temperature range
downTrace_dtr <- downTrace_max - downTrace_min
varnames(downTrace_dtr) <- "dtr"
longnames(downTrace_dtr) <- "dirunal temperature range"
units(downTrace_dtr) <- "deg_C"
time(downTrace_dtr) <- seq(as.Date("1980-01-16"), by = "month", l = nlyr(downTrace_mean))
downTrace_dtr
sum(values(downTrace_dtr) <= 0, na.rm = TRUE)
downTrace_dtr <- ifel(downTrace_dtr <= 0, 0.5, downTrace_dtr)

plot(tapp(downTrace_dtr, "month", mean),
     main = paste0(month.abb, " 0.05° TraCE DTR [1980-1989]"),
     range = c(0, 20), fill_range = TRUE,
     col = hcl.colors(100, "inferno"),
     fun = function() lines(land))

# correct the mean temperature first
downTrace_mean_corr <- downTrace_mean + delta_tmean_fine
downTrace_mean_corr

# correct the DTR
downTrace_dtr_corr <- downTrace_dtr * delta_dtr_fine
downTrace_dtr_corr

# Now reconstruct the downscaled max and min from the bias corrected mean and DTR
downTrace_tmax_corr <- round(downTrace_mean_corr + (downTrace_dtr_corr/2), 2)
varnames(downTrace_tmax_corr) <- "tasmax"
longnames(downTrace_tmax_corr) <- "maximum air temperature"
units(downTrace_tmax_corr) <- "deg_C"
time(downTrace_tmax_corr) <- seq(as.Date("1980-01-16"), by = "month", l = nlyr(downTrace_tmax_corr))
downTrace_tmax_corr

plot(tapp(downTrace_tmax_corr, "month", mean),
     range = c(0, 35), fill_range = TRUE,
     main = paste0(month.abb, " corrected tasmax"),
     col = hcl.colors(100, "spectral", rev = TRUE),
     fun = function() lines(land))

downTrace_tmin_corr <- round(downTrace_mean_corr - (downTrace_dtr_corr/2), 2)
varnames(downTrace_tmin_corr) <- "tasmin"
longnames(downTrace_tmin_corr) <- "minimum air temperature"
units(downTrace_tmin_corr) <- "deg_C"
time(downTrace_tmin_corr) <- seq(as.Date("1980-01-16"), by = "month", l = nlyr(downTrace_tmin_corr))
downTrace_tmin_corr

plot(tapp(downTrace_tmin_corr, "month", mean),
     range = c(0, 35), fill_range = TRUE,
     main = paste0(month.abb, " corrected tasmin"),
     col = hcl.colors(100, "spectral", rev = TRUE),
     fun = function() lines(land))

# How often is tmax < tmin for dtr corrected
dtr_temp_anoms <- app(downTrace_tmax_corr < downTrace_tmin_corr, sum)
dtr_temp_anoms <- round((dtr_temp_anoms / nlyr(downTrace_tmax_corr)) * 100, 2)
dtr_temp_anoms
# class       : SpatRaster
# size        : 1275, 1125, 1  (nrow, ncol, nlyr)
# resolution  : 0.05, 0.05  (x, y)
# extent      : 105, 161.25, -52.5, 11.25  (xmin, xmax, ymin, ymax)
# coord. ref. : lon/lat WGS 84 (EPSG:4326)
# source(s)   : memory
# name        : sum
# min value   :   0
# max value   :   0
plot(dtr_temp_anoms, range = c(0, 100), fill_range = TRUE,
     main = expression("percentage of time where DTR corrected " * t[max] <= " corrected " * t[min]),
     col = hcl.colors(100, rev = TRUE), fun = function() lines(land))

# Lets look at what happens at 22ka BP
## all in Kelvin
trace_22tmax <- rast("/media/dafcluster4/storage/TraCE_22k_1500CE/chunk_out/00001_00012/out/tasmax/CHELSA_tasmax_00001_00012_concat.nc") - 273.15
trace_22tmin <- rast("/media/dafcluster4/storage/TraCE_22k_1500CE/chunk_out/00001_00012/out/tasmin/CHELSA_tasmin_00001_00012_concat.nc") - 273.15
trace_22tas <- 0.5 * (trace_22tmax + trace_22tmin) # mean
trace_22dtr <- trace_22tmax - trace_22tmin # dtr
trace_22dtr <- ifel(trace_22dtr <= 0, 0.5, trace_22dtr)
trace_22dtr

# correct mean temperature
trace_22tas_corr <- trace_22tas + delta_tmean_fine

# correct dtr
trace_22dtr_corr <- trace_22dtr * delta_dtr_fine

# Now reconstruct the downscaled max and min from the bias corrected mean and DTR
trace22_tmax_corr <- round(trace_22tas_corr + (trace_22dtr_corr/2), 2)
trace22_tmin_corr <- round(trace_22tas_corr - (trace_22dtr_corr/2), 2)

plot(trace22_tmax_corr,
     range = c(0, 35), fill_range = TRUE,
     main = paste0(month.abb, " 22ka BP corr. tasmax"),
     col = hcl.colors(100, "spectral", rev = TRUE),
     fun = function() lines(land))

plot(trace22_tmin_corr,
     range = c(0, 35), fill_range = TRUE,
     main = paste0(month.abb, " 22ka BP corr. tasmin"),
     col = hcl.colors(100, "spectral", rev = TRUE),
     fun = function() lines(land))

# How often is tmax < tmin for dtr corrected
dtr22k_temp_anoms <- app(trace22_tmax_corr < trace22_tmin_corr, sum)
dtr22k_temp_anoms <- round((dtr22k_temp_anoms / nlyr(trace22_tmax_corr)) * 100, 2)
dtr22k_temp_anoms
# class       : SpatRaster
# size        : 1275, 1125, 1  (nrow, ncol, nlyr)
# resolution  : 0.05, 0.05  (x, y)
# extent      : 105, 161.25, -52.5, 11.25  (xmin, xmax, ymin, ymax)
# coord. ref. : lon/lat WGS 84 (EPSG:4326)
# source(s)   : memory
# name        : sum
# min value   :   0
# max value   :   0

plot(dtr22k_temp_anoms, range = c(0, 100), fill_range = TRUE,
     main = expression("percentage of time where corrected " * t[max] <= " corrected " * t[min]),
     col = hcl.colors(100, rev = TRUE), fun = function() lines(land))

# Change between 21ka and contemporary
trace22_tas <- 0.5 * (trace22_tmax_corr + trace22_tmin_corr)
downTrace_tas <- 0.5 * (tapp(downTrace_tmax_corr, "month", mean) + tapp(downTrace_tmin_corr, "month", mean))
trace22_tas; downTrace_tas

plot(downTrace_tas - trace22_tas)
