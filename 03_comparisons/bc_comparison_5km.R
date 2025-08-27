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

## CHELSA at 0.05°
chelsa_max <- rast("02_data/02_processed/CHELSA/CHELSA_coarse_tasmax_climatology.nc")
chelsa_min <- round(rast("02_data/02_processed/CHELSA/CHELSA_coarse_tasmin_climatology.nc"), 2)
chelsa_mean <- round(0.5 * (chelsa_max + chelsa_min), 2)
chelsa_dtr <- chelsa_max - chelsa_min
plot(chelsa_dtr, range = c(0, 15), fill_range = TRUE,
     main = paste0(month.abb, " CHELSA V1.2 DTR"),
     col = hcl.colors(100, "inferno"),
     fun = function() lines(land))

## TraCE at 0.5°
### following Karger et al. raw TraCE (3.75°) has been downscaled to 0.5° using
### multi-level b-sline interpolation
trace_max <- round(rast("02_data/02_processed/TRACE/TraCE_coarse_tasmax_climatology.nc"), 2)
trace_min <- round(rast("02_data/02_processed/TRACE/TraCE_coarse_tasmin_climatology.nc"), 2)
trace_mean <- round(0.5 * (trace_max + trace_min), 2)
trace_dtr <- trace_max - trace_min
sum(values(trace_dtr) == 0) #107

# some negatives in the DTR. Need to investigate a fix
plot(app(trace_max < trace_min, sum), fun = function() lines(land, col = "white"))

# negative dtr in non-sensical. If < 0, set to 0.05°C
trace_dtr <- ifel(trace_dtr < 0, 0.05, trace_dtr)

plot(trace_dtr, range = c(0, 15), fill_range = TRUE,
     main = paste0(month.abb, " TraCE-22ka DTR"),
     col = hcl.colors(100, "inferno"),
     fun = function() lines(land))

# Check with the raw TraCE temperatures
plot(app(rast("/media/dafcluster4/storage/TraCE_Monthly/TSMX/trace.01-36.22000BP-1990CE.cam2.h0.TSMX.0000101-2204012.Sahul.concat.1500_1989CE.nc",
     lyrs = 5761:5880) <
      rast("/media/dafcluster4/storage/TraCE_Monthly/TSMN/trace.01-36.22000BP-1990CE.cam2.h0.TSMN.0000101-2204012.Sahul.concat.1500_1989CE.nc",
           lyrs = 5761:5880), sum),
     fun = function() lines(land))

## Additive bias for mean temperature
delta_tmean <- chelsa_mean - trace_mean
varnames(delta_tmean) <- "tas"
longnames(delta_tmean) <- "mean air temperature delta"
units(delta_tmean) <- "deg_C"
delta_tmean_fine <- interpolate_bspline(delta_tmean,
                                      output_dir = "03_comparisons/scratch",
                                      bspline_ext = ext(rast_template),
                                      target_size = res(rast_template)[1],
                                      parallel_cores = 12,
                                      start_date = as.Date("1985-01-16"),
                                      outname_template = "dtas_%s_fine.nc",
                                      load_exist = TRUE,
                                      delta = TRUE)
delta_tmean_fine <- project(delta_tmean_fine, rast_template, "cubicspline")
delta_tmean_fine
plot(delta_tmean_fine, range = c(-10, 10), fill_range = TRUE,
     main = paste0(month.abb, " delta tas"),
     col = hcl.colors(100, "Spectral", rev = TRUE),
     fun = function() lines(land))

# simple bias for tmax and tmin
simple_tmax <- chelsa_max - trace_max
simple_tmin <- chelsa_min - trace_min

if (!dir.exists("03_comparisons/scratch")) {
  dir.create("03_comparisons/scratch", recursive = TRUE)
}

# downscale the simple bias corrections to 0.05°
## this approach follows Karger et al.
simple_delta <- list(simple_tmax, simple_tmin)
simple_delta_fine <- lapply(simple_delta, interpolate_bspline,
                      output_dir = "03_comparisons/scratch",
                      bspline_ext = ext(rast_template),
                      target_size = res(rast_template)[1],
                      parallel_cores = 12,
                      start_date = as.Date("1985-01-16"),
                      outname_template = "simple_%s_fine.nc",
                      load_exist = TRUE,
                      delta = TRUE)
simple_delta_fine <- lapply(simple_delta_fine, function(x) project(x, rast_template, "cubicspline"))
names(simple_delta_fine) <- c("tasmax", "tasmin")
simple_delta_fine
plot(simple_delta_fine$tasmax, range = c(-10, 10), fill_range = TRUE,
     main = paste0(month.abb, " additive delta tmax"),
     col = hcl.colors(100, "Spectral", rev = TRUE),
     fun = function() lines(land))
plot(simple_delta_fine$tasmin, range = c(-10, 10), fill_range = TRUE,
     main = paste0(month.abb, " additive delta tmin"),
     col = hcl.colors(100, "Spectral", rev = TRUE),
     fun = function() lines(land))

## Multiplicative bias for DTR (avoid division by zero)
delta_dtr <- chelsa_dtr / trace_dtr
delta_dtr[!is.finite(delta_dtr)] <- 1 # if mod_dtr=0, set ratio=1
plot(delta_dtr, range = c(-3, 3), fill_range = TRUE,
     main = paste0(month.abb, " delta DTR"),
     col = hcl.colors(100, "Spectral", rev = TRUE),
     fun = function() lines(land))
varnames(delta_dtr) <- "dtr"
longnames(delta_dtr) <- "diurnal temperature range delta"
units(delta_dtr) <- "deg_C"

delta_dtr_fine <- interpolate_bspline(delta_dtr,
                                      output_dir = "03_comparisons/scratch",
                                      bspline_ext = ext(rast_template),
                                      target_size = res(rast_template)[1],
                                      parallel_cores = 12,
                                      start_date = as.Date("1985-01-16"),
                                      outname_template = "dtr_%s_fine.nc",
                                      load_exist = TRUE,
                                      delta = TRUE)
delta_dtr_fine <- project(delta_dtr_fine, rast_template, "cubicspline")
plot(delta_dtr_fine, range = c(-3, 3), fill_range = TRUE,
     main = paste0(month.abb, " delta DTR"),
     col = hcl.colors(100, "Spectral", rev = TRUE),
     fun = function() lines(land))

# Correct the downscaled TraCE data
## data is masked to land only
## projection step here is only to ensure the extents align
downTrace_max <- rast("/media/dafcluster4/storage/TraCE_1500_1990CE/1500_1990/out/tasmax/TraCE_downscaled_1980_1990_monthly.nc")
compareGeom(downTrace_max, delta_dtr_fine)
downTrace_min <- rast("/media/dafcluster4/storage/TraCE_1500_1990CE/1500_1990/out/tasmin/TraCE_downscaled_1980_1990_monthly.nc")
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

# Compare to simple bias corrections of tmax and tmin
simple_corr_tasmax <- round(downTrace_max + simple_delta_fine$tasmax, 2)
simple_corr_tasmax
plot(tapp(simple_corr_tasmax, "month", mean),
     range = c(0, 35), fill_range = TRUE,
     main = paste0(month.abb, " simple delta corr. tasmax"),
     col = hcl.colors(100, "spectral", rev = TRUE),
     fun = function() lines(land))

simple_corr_tasmin <- round(downTrace_min + simple_delta_fine$tasmin, 2)
simple_corr_tasmin
plot(tapp(simple_corr_tasmin, "month", mean),
     range = c(0, 35), fill_range = TRUE,
     main = paste0(month.abb, " simple delta corr. tasmin"),
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
# name        :   sum
# min value   :  0.00
# max value   : 41.67
plot(dtr_temp_anoms, range = c(0, 100), fill_range = TRUE,
     main = expression("percentage of time where DTR corrected " * t[max] <= " corrected " * t[min]),
     col = hcl.colors(100, rev = TRUE), fun = function() lines(land))

# what about simple delta correction?
simple_temp_anoms <- app(simple_corr_tasmax < simple_corr_tasmin, sum)
simple_temp_anoms <- round((simple_temp_anoms / nlyr(simple_corr_tasmax)) * 100, 2)
simple_temp_anoms
# class       : SpatRaster
# size        : 1275, 1125, 1  (nrow, ncol, nlyr)
# resolution  : 0.05, 0.05  (x, y)
# extent      : 105, 161.25, -52.5, 11.25  (xmin, xmax, ymin, ymax)
# coord. ref. : lon/lat WGS 84 (EPSG:4326)
# source(s)   : memory
# name        : sum
# min value   :   0
# max value   : 100
plot(simple_temp_anoms, range = c(0, 100), fill_range = TRUE,
     main = expression("percentage of time where simple corrected " * t[max] <= " corrected " * t[min]),
     col = hcl.colors(100, rev = TRUE), fun = function() lines(land))

# Lets look at what happens at 22ka BP
## all in Kelvin
trace_22tmax <- rast(list.files("/media/dafcluster4/storage/TraCE_22k_1500CE/chunk_out/00001_00012/out/tasmax/",
                                full.names = TRUE))-273.15
trace_22tmin <- rast(list.files("/media/dafcluster4/storage/TraCE_22k_1500CE/chunk_out/00001_00012/out/tasmin/",
                                full.names = TRUE))-273.15
trace_22tas <- 0.5 * (trace_22tmax + trace_22tmin) # mean
trace_22dtr <- downTrace_dtr <- trace_22tmax - trace_22tmin # dtr

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
plot(dtr22k_temp_anoms, range = c(0, 100), fill_range = TRUE,
     main = expression("percentage of time where corrected " * t[max] <= " corrected " * t[min]),
     col = hcl.colors(100, rev = TRUE), fun = function() lines(land))

# simple bias correction for 22k BP
# Compare to simple bias corrections of tmax and tmin
simple_corr_22k_tasmax <- round(trace_22tmax + simple_delta_fine$tasmax, 2)
simple_corr_22k_tasmax
plot(simple_corr_22k_tasmax,
     range = c(0, 35), fill_range = TRUE,
     main = paste0(month.abb, " simple delta 22ka BP corr. tasmax"),
     col = hcl.colors(100, "spectral", rev = TRUE),
     fun = function() lines(land))

simple_corr_22k_tasmin <- round(trace_22tmin + simple_delta_fine$tasmin, 2)
simple_corr_22k_tasmin
plot(simple_corr_22k_tasmin,
     range = c(0, 35), fill_range = TRUE,
     main = paste0(month.abb, " simple delta 22ka BP corr. tasmin"),
     col = hcl.colors(100, "spectral", rev = TRUE),
     fun = function() lines(land))

# How often is tmax < tmin for dtr corrected
simple22k_temp_anoms <- app(simple_corr_22k_tasmax < simple_corr_22k_tasmin, sum)
simple22k_temp_anoms <- round((simple22k_temp_anoms / nlyr(trace22_tmax_corr)) * 100, 2)
simple22k_temp_anoms
plot(simple22k_temp_anoms, range = c(0, 100), fill_range = TRUE,
     main = expression("percentage of time where corrected " * t[max] <= " corrected " * t[min]),
     col = hcl.colors(100, rev = TRUE), fun = function() lines(land))
