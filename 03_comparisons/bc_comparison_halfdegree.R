library(terra)
library(pbapply)

land <- vect(rnaturalearthhires::countries10)
land <- crop(land, ext(105, 161.25, -52.5, 11.25))
land <- aggregate(land)
plot(land)

# Calculate delta between CHELSA and raw TraCE data
## this approach using CHELSA V1.2 and TraCE data follows Karger et al.
## except here I'm going to correct with the DTR approach to ensure
## maximum temps are always greater than minimum temps

## CHELSA at 0.5°
chelsa_max <- round(rast("02_data/02_processed/CHELSA/CHELSA_coarse_tasmax_climatology.nc"), 2)
chelsa_min <- round(rast("02_data/02_processed/CHELSA/CHELSA_coarse_tasmin_climatology.nc"), 2)
chelsa_mean <- round(0.5 * (chelsa_max + chelsa_min), 2)
chelsa_dtr <- chelsa_max - chelsa_min

## TraCE at 0.5°
### following Karger et al. raw TraCE (3.75°) has been downscaled to 0.5° using
### multi-level b-sline interpolation
trace_max <- round(rast("02_data/02_processed/TRACE/TraCE_coarse_tasmax_climatology.nc"), 2)
trace_min <- round(rast("02_data/02_processed/TRACE/TraCE_coarse_tasmin_climatology.nc"), 2)
trace_mean <- round(0.5 * (trace_max + trace_min), 2)
trace_dtr <- trace_max - trace_min

## Additive bias for mean temperature
delta_tmean <- chelsa_mean - trace_mean
plot(delta_tmean, range = c(-10, 10), fill_range = TRUE,
     main = paste0(month.abb, " delta tmean"),
     col = hcl.colors(100, "Spectral", rev = TRUE),
     fun = function() lines(land))

# simple bias for tmax and tmin
simple_tmax <- chelsa_max - trace_max
simple_tmin <- chelsa_min - trace_min

## Multiplicative bias for DTR (avoid division by zero)
delta_dtr <- chelsa_dtr / trace_dtr
delta_dtr[!is.finite(delta_dtr)] <- 1 # if mod_dtr=0, set ratio=1
plot(delta_dtr, range = c(-3, 3), fill_range = TRUE,
     main = paste0(month.abb, " delta DTR"),
     col = hcl.colors(100, "Spectral", rev = TRUE),
     fun = function() lines(land))

# Correct the downscaled TraCE data
## data is masked to land only
## projection step here is only to ensure the extents align
downTrace_max <- round(project(rast("/media/dafcluster4/storage/TraCE_1500_1990CE/1500_1990/out/tasmax/TraCE_downscaled_1980_1990_monthly_coarse.nc"),
                         delta_tmean, "near"), 2)
downTrace_min <- round(project(rast("/media/dafcluster4/storage/TraCE_1500_1990CE/1500_1990/out/tasmin/TraCE_downscaled_1980_1990_monthly_coarse.nc"),
                         delta_tmean, "near"), 2)
time(downTrace_max) <- time(downTrace_min) <- seq(as.Date("1980-01-16"), by = "month", l = nlyr(downTrace_max))
downTrace_mean <- round(0.5 * (downTrace_max + downTrace_min), 2)
downTrace_dtr <- downTrace_max - downTrace_min
plot(tapp(downTrace_dtr, "month", mean),
     main = paste0(month.abb, " DTR"),
     range = c(5, 40), fill_range = TRUE,
     col = hcl.colors(100, "Spectral", rev = TRUE),
     fun = function() lines(land))

# correct the mean temperature first
downTrace_mean_corr <- downTrace_mean + delta_tmean

# correct the DTR
downTrace_dtr_corr <- round(downTrace_dtr * delta_dtr, 2)

# Now reconstruct the downscaled max and min from the bias corrected DTR
downTrace_tmax_corr <- round(downTrace_mean_corr + (downTrace_dtr_corr/2), 2)
downTrace_tmin_corr <- round(downTrace_mean_corr - (downTrace_dtr_corr/2))


# class       : SpatRaster
# size        : 128, 113, 1  (nrow, ncol, nlyr)
# resolution  : 0.5, 0.5  (x, y)
# extent      : 104.75, 161.25, -52.75, 11.25  (xmin, xmax, ymin, ymax)
# coord. ref. : lon/lat WGS 84 (EPSG:4326)
# source(s)   : memory
# name        : sum
# min value   :   0
# max value   : 100
plot(sqrt(temp_anoms), range = c(0, 10), fill_range = TRUE,
     main = expression("percentage (" * sqrt(x) * ") of time where simple corrected " * t[max] <= " corrected " * t[min]),
     col = hcl.colors(100, rev = TRUE), fun = function() lines(land))

# what about the dtr method?
dtr_temp_anoms <- app(downTrace_tmax_corr < downTrace_tmin_corr, sum)
dtr_temp_anoms <- round((dtr_temp_anoms / nlyr(downTrace_tmax_corr)) * 100, 2)
# class       : SpatRaster
# size        : 128, 113, 1  (nrow, ncol, nlyr)
# resolution  : 0.5, 0.5  (x, y)
# extent      : 104.75, 161.25, -52.75, 11.25  (xmin, xmax, ymin, ymax)
# coord. ref. : lon/lat WGS 84 (EPSG:4326)
# source(s)   : memory
# name        :   sum
# min value   :  0.00
# max value   : 35.83
plot(sqrt(dtr_temp_anoms), range = c(0, 10), fill_range = TRUE,
     main = expression("percentage (" * sqrt(x) * ") of time where DTR corrected " * t[max] <= " corrected " * t[min]),
     col = hcl.colors(100, rev = TRUE), fun = function() lines(land))
