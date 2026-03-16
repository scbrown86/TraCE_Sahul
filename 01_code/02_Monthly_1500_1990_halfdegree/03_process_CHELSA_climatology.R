library(terra)
setGDALconfig("GDAL_PAM_ENABLED", "FALSE") # don't write aux files!
terraOptions(memfrac = 0.85, memmax = 20)
library(gtools)
library(pbapply)
library(rnaturalearthhires)
library(qgisprocess)
library(data.table)

dmon <- c(31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31)

# safe
safe_spline <- purrr::safely(qgisprocess::qgis_run_algorithm,
                             otherwise = NULL, quiet = TRUE)

template <- rast("02_data/trace_to_sahul_half_degree_bilin.nc")
template

land <- vect(rnaturalearthhires::countries10)
land <- crop(land, ext(template))
land <- aggregate(land)
land
plot(template, fun = function() lines(land))

source("01_code/00_functions/interpolate_bspline.R")
source("01_code/00_functions/chelsa_proc.R")

#### CHELSA ####

# load in CHELSA V2.1 data at original res
# calculate averages between 1980 and 1989
if (!dir.exists("02_data/02_processed/CHELSA_21/")) {
  dir.create("02_data/02_processed/CHELSA_21/", recursive = TRUE)
}

subset_chelsa <- function(files, year_start, year_end, var = "pr") {
    base <- basename(files)
    files <- files[grepl(paste0("_", var, "_"), base)]
    base <- basename(files)
    year <- as.integer(sub(".*_(\\d{4})_V.*", "\\1", base))
    month <- as.integer(sub(paste0(".*_", var, "_(\\d{2})_.*"), "\\1", base))
    idx <- which(year >= year_start & year <= year_end)
    idx <- idx[order(year[idx] * 100 + month[idx])]
    files[idx]
}

files <- list.files("/mnt/Data/CHELSA/v2.1", full.names = TRUE, recursive = TRUE)
rast(files[1])
resample(rast(files[1]), template, "bilinear")
processed_chelsa <- lapply(c("pr", "tasmax", "tasmin"), function(var,...) {
  fil <- subset_chelsa(files, 1980, 1989, var)
  r <- rast(lapply(fil, function(x) rast(x, win = ext(template), snap = "out")))
  varnames(r) <- var
  r
  })
names(processed_chelsa) <- c("pr", "tasmax", "tasmin")
str(processed_chelsa)

# Calculate the climatological averages
terraOptions(memfrac = 0.85, memmax = 50)
pr_avg <- processed_chelsa$pr
time(pr_avg) <- seq(as.Date("1980-01-16"), by = "month", l = nlyr(pr_avg))
plot(pr_avg[[1]], col = hcl.colors(100, "Batlow"), fun = function() lines(land))
tmn_avg <- processed_chelsa$tasmin
tmx_avg <- processed_chelsa$tasmax
time(tmn_avg) <- time(tmx_avg) <- time(pr_avg)
plot(0.5*(tmx_avg[[1]] + tmn_avg[[1]]), col = hcl.colors(100, "Batlow"), fun = function() lines(land))
idx <- format(time(pr_avg), "%b")

chelsa_climatologies <- c(
  "02_data/02_processed/CHELSA_21/CHELSA_pr_climatology.nc",
  "02_data/02_processed/CHELSA_21/CHELSA_tasmin_climatology.nc",
  "02_data/02_processed/CHELSA_21/CHELSA_tasmax_climatology.nc",
  "02_data/02_processed/CHELSA_21/CHELSA_tas_climatology.nc")

if (!all(file.exists(chelsa_climatologies))) {
  # calculate the climatological average
  pr_avg <- tapp(pr_avg, idx, mean, cores = 12L)
  tmn_avg <- tapp(tmn_avg, idx, mean, cores = 12L)
  tmx_avg <- tapp(tmx_avg, idx, mean, cores = 12L)
  # set time for variables
  time(pr_avg) <- time(tmn_avg) <- time(tmx_avg) <-
    seq(as.Date("1985-01-16"), by = "month", l = 12)
  # precip units
  units(pr_avg) <- "kg/m2/s"
  varnames(pr_avg) <- "precip"
  terra::longnames(pr_avg) <- "precipitation"
  # temperature units
  units(tmn_avg) <- units(tmx_avg) <- "deg_C"
  writeCDF(pr_avg, "02_data/02_processed/CHELSA_21/CHELSA_pr_climatology.nc",
           varname = "pr", longname = "precipitation",
           unit = "kg/m2/s", zname = "time", prec = "float",
           overwrite = TRUE)
  writeCDF(tmn_avg, "02_data/02_processed/CHELSA_21/CHELSA_tasmin_climatology.nc",
           varname = "tasmin",
           longname = "minimum near surface air temperature",
           unit = "deg_C", zname = "time", prec = "float",
           overwrite = TRUE)
  writeCDF(tmx_avg, "02_data/02_processed/CHELSA_21/CHELSA_tasmax_climatology.nc",
           varname = "tasmax",
           longname = "maximum near surface air temperature",
           unit = "deg_C", zname = "time", prec = "float",
           overwrite = TRUE)
} else {
  pr_avg <- rast("02_data/02_processed/CHELSA_21/CHELSA_pr_climatology.nc")
  tmn_avg <- rast("02_data/02_processed/CHELSA_21/CHELSA_tasmin_climatology.nc")
  tmx_avg <- rast("02_data/02_processed/CHELSA_21/CHELSA_tasmax_climatology.nc")
}

# convert the CHELSA climatology data to 0.05 degree using b-splines
source("01_code/00_functions/interpolate_bspline.R")

# multilevel b-spline to 0.05°
pr_avg <- rast("02_data/02_processed/CHELSA_21/CHELSA_pr_climatology.nc")
varnames(pr_avg) <- "pr"
longnames(pr_avg) <- "precipitation"
units(pr_avg) <- "kg/m2/s"
pr_avg
minmax(pr_avg*86400)
panel(pr_avg*86400, range = c(0, 15), fill_range = TRUE)

tmn_avg <- rast("02_data/02_processed/CHELSA_21/CHELSA_tasmin_climatology.nc")
varnames(tmn_avg) <- "tasmin"
longnames(tmn_avg) <- "minimum temperature"
units(tmn_avg) <- "deg_C"
tmn_avg

tmx_avg <- rast("02_data/02_processed/CHELSA_21/CHELSA_tasmax_climatology.nc")
varnames(tmx_avg) <- "tasmax"
longnames(tmx_avg) <- "maximum temperature"
units(tmx_avg) <- "deg_C"
tmx_avg

# bilinear to 0.05°
fine_clim <- list(pr_avg, tmx_avg, tmn_avg)
coarse_chelsa_clim <- lapply(fine_clim, interpolate_bspline,
  output_dir = "02_data/02_processed/CHELSA_21",
  bspline_ext = ext(template),
  target_size = res(template)[1],
  parallel_cores = 12L,
  start_date = as.Date("1985-01-16"),
  outname_template = "CHELSA_coarse_%s_climatology.nc",
  algo = "bilinear", ## <
  load_exist = FALSE)
names(coarse_chelsa_clim) <- c("pr", "tasmax", "tasmin")
coarse_chelsa_clim

minmax(coarse_chelsa_clim$pr)

plot(app(coarse_chelsa_clim$pr, sum)*86400*12, range = c(0, 3000),
     fill_range = TRUE, fun = function() lines(land),
     col = hcl.colors(100, "YlGnBu", rev = TRUE))
panel(coarse_chelsa_clim$tasmin, range = c(5, 30), fill_range = TRUE,
      fun = function() lines(land), col = hcl.colors(100, "Spectral", rev = TRUE))
panel(coarse_chelsa_clim$tasmax, range = c(5, 30), fill_range = TRUE,
      fun = function() lines(land), col = hcl.colors(100, "Spectral", rev = TRUE))

#### TRACE ####
# load in the 0.5° TraCE data for 1980:1989
idx <- which(rep(1500:1989, each = 12) >= 1980)
trace <- list(rast("/media/dafcluster4/storage/TraCE_Monthly_halfDeg/PRECC/trace.01-36.22000BP-1990CE.cam2.h0.PRECC.0000101-2204012.Sahul.concat.1500_1989CE.nc",
                   lyrs = idx) +
              rast("/media/dafcluster4/storage/TraCE_Monthly_halfDeg/PRECL/trace.01-36.22000BP-1990CE.cam2.h0.PRECL.0000101-2204012.Sahul.concat.1500_1989CE.nc",
                   lyrs = idx),     #1980 - 1989
              rast("/media/dafcluster4/storage/TraCE_Monthly_halfDeg/TSMX/trace.01-36.22000BP-1990CE.cam2.h0.TSMX.0000101-2204012.Sahul.concat.1500_1989CE.nc",
                   lyrs = idx)-273.15,
              rast("/media/dafcluster4/storage/TraCE_Monthly_halfDeg/TSMN/trace.01-36.22000BP-1990CE.cam2.h0.TSMN.0000101-2204012.Sahul.concat.1500_1989CE.nc",
                   lyrs = idx)-273.15)
trace
# make climatological monthly averages from 1980-1989
trace <- pblapply(trace, function(i) {
  if (nlyr(i) != 12) {
    time(i) <- seq(as.Date("1980-01-16"), by = "month", l = 120)
    i <- tapp(i, index = "month", fun = "mean")
    i
  } else {
    time(i) <- seq(as.Date("1985-01-16"), by = "month", l = 12)
    i
  }
})
varnames(trace[[1]]) <- "pr"
varnames(trace[[2]]) <- "tasmax"
varnames(trace[[3]]) <- "tasmin"
units(trace[[1]]) <- "kg/m2/s"
units(trace[[2]]) <- units(trace[[3]]) <- "deg_C"
names(trace) <- c("pr", "tasmax", "tasmin")
trace$pr <- ifel(trace$pr < 0, 0, trace$pr)
minmax(trace$tasmax - trace$tasmin) # no dtr issues

# trace_climatologies <- c(
#   "02_data/02_processed/TRACE_half/TraCE_coarse_pr_climatology.nc",
#  "02_data/02_processed/TRACE_half/TraCE_coarse_tasmax_climatology.nc",
#   "02_data/02_processed/TRACE_half/TraCE_coarse_tasmin_climatology.nc")

# if (!all(file.exists(trace_climatologies))) {
#   # convert TraCE climatology to 0.05 degrees
#   if (!dir.exists("02_data/02_processed/TRACE_half")) {
#     dir.create("02_data/02_processed/TRACE_half", recursive = TRUE)
#   }
#   # to make sure the extents are exactly the same, reprocess our
#   # downscaled data with bsplines
#   # multilevel b-spline to 0.05°
#   coarse_trace_clim <- lapply(trace, interpolate_bspline,
#                               output_dir = "02_data/02_processed/TRACE_half",
#                               bspline_ext = ext(template),
#                               target_size = res(template)[1],
#                               parallel_cores = 12,
#                               start_date = as.Date("1985-01-16"),
#                               outname_template = "TraCE_coarse_%s_climatology.nc",
#                               algo = "bspline", ## <
#                               load_exist = TRUE)
#   names(coarse_trace_clim) <- c("pr", "tasmax", "tasmin")
#   coarse_trace_clim
# } else {
#   coarse_trace_clim <- lapply(brown_climatologies, rast)
#   names(coarse_trace_clim) <- c("pr", "tasmax", "tasmin")
# }
coarse_trace_clim <- list()
coarse_trace_clim$pr <- ifel(trace$pr < 0, 0, trace$pr) * 1
coarse_trace_clim$tasmax <- trace$tasmax * 1
coarse_trace_clim$tasmin <- trace$tasmin * 1
coarse_trace_clim

panel(0.5 * (coarse_trace_clim$tasmax + coarse_trace_clim$tasmin), # avg temps
      fun = function() lines(land),
      range = c(5, 35), fill_range = TRUE,
      col = hcl.colors(100, "spectral", rev = TRUE))
minmax(coarse_trace_clim$tasmax - coarse_trace_clim$tasmin)
plot(coarse_trace_clim$tasmax - coarse_trace_clim$tasmin, # DTR
      breaks = c(-Inf, 0, Inf),
     fill_range = TRUE,
     fun = function() lines(land))


#### DELTAS ####
# create delta between the CHELSA and downscaled TraCE climatology
rbind(
  minmax(coarse_chelsa_clim$pr * 86400),
  minmax(coarse_trace_clim$pr * 86400))

compareGeom(coarse_chelsa_clim$pr, coarse_trace_clim$pr)

# coarse_chelsa_clim <- lapply(coarse_chelsa_clim, function(x) {
#   project(x, coarse_trace_clim$pr, "bilinear")
# })

# simple delta correction for precip.
# ? log ratio
# log_ratio <- log((obs_land + eps) / (mod_land + eps))
delta_pr <- (coarse_chelsa_clim$pr*(86400*dmon) + 1e-4) / (coarse_trace_clim$pr*(86400*dmon) + 1e-4)
varnames(delta_pr) <- "pr"
longnames(delta_pr) <- "precipitation delta"
units(delta_pr) <- ""
delta_pr
minmax(delta_pr)
panel(delta_pr, fun = function() lines(land, col = "#000000"),
      range = c(0, 5), fill_range = TRUE,
      col = hcl.colors(100, "YlGnBu", rev = TRUE))

# Temperature correction is a multi step process.
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
      range = c(-5, 5), fill_range = TRUE,
      col = hcl.colors(100, "Spectral", rev = TRUE))

# diurnal temperature range
## any negative or zero values will be changed to 0.05°C
## downscaled TraCE (0.5°)
trace_dtr <- coarse_trace_clim$tasmax - coarse_trace_clim$tasmin
sum(values(trace_dtr) <= 0, na.rm = TRUE)/(ncell(trace_dtr)*nlyr(trace_dtr)) * 100 # 0
trace_dtr <- ifel(trace_dtr <= 0, 1, trace_dtr)

chelsa_dtr <- coarse_chelsa_clim$tasmax - coarse_chelsa_clim$tasmin
sum(values(chelsa_dtr) <= 0, na.rm = TRUE)/(ncell(chelsa_dtr)*nlyr(chelsa_dtr)) * 100 # 0
chelsa_dtr <- ifel(chelsa_dtr <= 0, 1, chelsa_dtr)

delta_dtr <- chelsa_dtr / trace_dtr
delta_dtr[!is.finite(delta_dtr)] <- 1 # set any infinite to 1
# delta_dtr <- clamp(delta_dtr, 0.1, 5)
sum(values(delta_dtr) <= 0, na.rm = TRUE) # 0
varnames(delta_dtr) <- "dtr"
longnames(delta_dtr) <- "diurnal temperature range delta"
units(delta_dtr) <- ""
delta_dtr

# hist(delta_dtr, breaks = 20, freq = TRUE)
# global(delta_dtr, fun = function(x) quantile(x, probs = c(0.01, 0.05, 0.95, 0.99)))
# clamp_to_percentile <- function(rast, upper = 0.95) {
#     for (i in seq_len(nlyr(rast))) {
#         p95 <- quantile(values(rast[[i]]), probs = upper, na.rm = TRUE)
#         rast[[i]] <- clamp(rast[[i]], upper = p95, values = TRUE)
#     }
#     return(rast)
# }
# delta_dtr <- clamp_to_percentile(delta_dtr)
# delta_dtr

global(delta_dtr, fun = function(x) quantile(x, probs = c(0.01, 0.05, 0.95, 0.99)))

panel(delta_dtr, range = c(0, 5), fill_range = TRUE,
      col = hcl.colors(100, "Spectral", rev = TRUE),
      fun = function() lines(land))

deltas <- list(delta_pr, delta_tmean, delta_dtr)
names(deltas) <- c("pr", "tas", "dtr")

panel(deltas$pr, fun = function() lines(land),
      range = c(0, 5), fill_range = TRUE,
      breaks = seq(0, 5, by = 0.1),
      col = hcl.colors(50, "Spectral"))
panel(deltas$tas, fun = function() lines(land),
      range = c(-5, 5), fill_range = TRUE, col = hcl.colors(100, "Spectral"))
plot(deltas$dtr, fun = function() lines(land),
     range = c(0, 5), fill_range = TRUE, col = hcl.colors(100, "Spectral", rev = TRUE))

# Test the corrections on the TraCE data
panel(coarse_trace_clim$pr * deltas$pr)
tavg <- (0.5 * (coarse_trace_clim$tasmax + coarse_trace_clim$tasmin)) + deltas$tas
tavg
# panel(tavg)
tdtr <- (coarse_trace_clim$tasmax - coarse_trace_clim$tasmin)*deltas$dtr
tmax <- (tavg + 0.5*tdtr)
tmin <- (tavg - 0.5*tdtr)
tmax-tmin
panel(tmax)
panel(tmin)

# save the masked deltas to netcdf
source("01_code/00_functions/spatraster_to_netcdf.r")

deltas
time(deltas$pr, tstep = "months") <- 1:12
time(deltas$tas, tstep = "months") <- 1:12
time(deltas$dtr, tstep = "months") <- 1:12

write_spatraster_ncdf(
  deltas$pr,
  "02_data/02_processed/deltas/delta_halfdeg_pr_climatology_ncdf4.nc")
write_spatraster_ncdf(
  deltas$tas,
  "02_data/02_processed/deltas/delta_halfdeg_tas_climatology_ncdf4.nc")
write_spatraster_ncdf(
  deltas$dtr,
  "02_data/02_processed/deltas/delta_halfdeg_dtr_climatology_ncdf4.nc")
