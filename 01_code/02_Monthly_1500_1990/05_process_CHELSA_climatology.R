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

plot(app(coarse_chelsa_clim$pr, sum)*86400*12, range = c(0, 3000), fill_range = TRUE, fun = function() lines(land), col = hcl.colors(100, "YlGnBu", rev = TRUE))
plot(coarse_chelsa_clim$tas, range = c(5, 30), fill_range = TRUE, fun = function() lines(land), col = hcl.colors(100, "Spectral", rev = TRUE))
plot(coarse_chelsa_clim$tasmax - coarse_chelsa_clim$tas, range = c(1, 5), fill_range = TRUE, fun = function() lines(land), col = hcl.colors(100, "Spectral", rev = TRUE))


#### TRACE ####
# load in the raw trace data
brown <- list(rast("/media/dafcluster4/storage/TraCE_Monthly/PRECC/trace.01-36.22000BP-1990CE.cam2.h0.PRECC.0000101-2204012.Sahul.concat.1500_1989CE.nc",
                   lyrs = 5761:5880) +
                rast("/media/dafcluster4/storage/TraCE_Monthly/PRECL/trace.01-36.22000BP-1990CE.cam2.h0.PRECL.0000101-2204012.Sahul.concat.1500_1989CE.nc",
                     lyrs = 5761:5880),
              rast("/media/dafcluster4/storage/TraCE_1500_1990CE/1500_1990/out/tas/TraCE_downscaled_1980_1990_monthly_climatology.nc"),
              rast("/media/dafcluster4/storage/TraCE_1500_1990CE/1500_1990/out/tasmax/TraCE_downscaled_1980_1990_monthly_climatology.nc"),
              rast("/media/dafcluster4/storage/TraCE_1500_1990CE/1500_1990/out/tasmin/TraCE_downscaled_1980_1990_monthly_climatology.nc"))
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
varnames(brown[[2]]) <- "tas"
varnames(brown[[3]]) <- "tasmax"
varnames(brown[[4]]) <- "tasmin"
units(brown[[1]]) <- "kg/m2/s"
units(brown[[2]]) <- units(brown[[3]]) <- units(brown[[4]]) <-"deg_C"
names(brown) <- c("pr", "tas", "tasmax", "tasmin")
brown
minmax(brown$tasmax - brown$tas)

brown_climatologies <- c(
  "02_data/02_processed/TRACE/TraCE_coarse_pr_climatology.nc",
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

plot(coarse_trace_clim$tasmax - coarse_trace_clim$tas)
minmax(coarse_trace_clim$tasmax - coarse_trace_clim$tas)
round(minmax(coarse_trace_clim$tasmin - coarse_trace_clim$tas), 2)


#### DELTAS ####
# create delta between the CHELSA and downscaled TraCE climatology
rbind(
  minmax(coarse_chelsa_clim$pr * (c(31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31) * 86400)),
  minmax(coarse_trace_clim$pr * (c(31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31) * 86400)))

delta_pr <-( coarse_chelsa_clim$pr + 1e-4) / (coarse_trace_clim$pr + 1e-4)
delta_pr
plot(delta_pr, fun = function() lines(land, col = "#000000"),
     range = c(0, 2), fill_range = TRUE,
     breaks = seq(0, 2, by = 0.1),
     col = hcl.colors(20, "Spectral"))
# temperature delta
delta_tas <- coarse_chelsa_clim$tas - coarse_trace_clim$tas
delta_tas
plot(delta_tas, fun = function() lines(land, col = "#FFFFFF"),
     range = c(-5, 5), fill_range = TRUE, col = hcl.colors(100, "Spectral"))

delta_tasmin <- coarse_chelsa_clim$tasmin - coarse_trace_clim$tasmin
delta_tasmin
plot(delta_tasmin, fun = function() lines(land, col = "#FFFFFF"),
     range = c(-5, 5), fill_range = TRUE, col = hcl.colors(100, "Spectral"))

delta_tasmax <- coarse_chelsa_clim$tasmax - coarse_trace_clim$tasmax
delta_tasmax
plot(delta_tasmax, fun = function() lines(land, col = "#FFFFFF"),
     range = c(-5, 5), fill_range = TRUE, col = hcl.colors(100, "Spectral"))

# convert the delta back to 0.05 degrees using b-splines
if (!dir.exists("02_data/02_processed/deltas")) {
  dir.create("02_data/02_processed/deltas", recursive = TRUE)
}
deltas <- list(delta_pr, delta_tas, delta_tasmax, delta_tasmin)
deltas_fine <- lapply(deltas, interpolate_bspline,
  output_dir = "02_data/02_processed/deltas",
  bspline_ext = ext(105.0, 161.25, -52.5, 11.25),
  target_size = 0.05,
  parallel_cores = 12,
  start_date = as.Date("1985-01-16"),
  outname_template = "delta_fine_%s_climatology.nc",
  load_exist = TRUE,
  delta = TRUE)
names(deltas_fine) <- c("pr", "tas", "tasmax", "tasmin")
deltas_fine
deltas_fine$pr*1
plot(deltas_fine$pr)
plot(deltas_fine$tas)
plot(deltas_fine$tasmax)
plot(deltas_fine$tasmin)

# load in data for the first and last time step and check the effect of delta
downscaled_22k <- list.files("/media/dafcluster4/storage/TraCE_22k_1500CE/chunk_out/00001_00012/out",
                             recursive = TRUE, full.names = TRUE)
downscaled_22k <- split(downscaled_22k, sapply(downscaled_22k, function(x) sub(".*CHELSA_([a-z]+)_.*", "\\1", basename(x)))) |> 
                    lapply(rast)
mask_22ka <- downscaled_22k$pr[[1]]
mask_22ka <- ifel(is.na(mask_22ka), NA, 1)
plot((downscaled_22k$pr * 86400 * c(31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31)) * deltas_fine$pr)
plot((downscaled_22k$tas-273.15) + deltas_fine$tas)
minmax((downscaled_22k$tasmax + deltas_fine$tasmax) - (downscaled_22k$tas + deltas_fine$tas))
minmax((downscaled_22k$tasmin + deltas_fine$tasmin) - (downscaled_22k$tas + deltas_fine$tas))
minmax((downscaled_22k$tasmax[[1]] + deltas_fine$tasmax[[1]]) - (downscaled_22k$tasmin[[1]] + deltas_fine$tasmin[[1]]))

# some areas where max is < min
brown_22k <- ((downscaled_22k$tasmax - 273.15) + deltas_fine$tasmax) - ((downscaled_22k$tasmin - 273.15) + deltas_fine$tasmin)
plot(brown_22k, main = paste(month.abb, " max - min temp"),
     range = c(-8, 8), fill_range = TRUE, col = hcl.colors(20, "Spectral"), 
     fun = function() lines(land))

# Karger et al have the same issue! Max is lower than the min after bias correction
karger_22k <- ((rast(sprintf("/mnt/Data/CHELSA_Trace21/CHELSA_TraCE21k_tasmax_%s_-200_V1.0.tif", 1:12), 
                     win = ext(downscaled_22k$tasmax))*0.1)- 273.15) -
      ((rast(sprintf("/mnt/Data/CHELSA_Trace21/CHELSA_TraCE21k_tasmin_%s_-200_V1.0.tif", 1:12), 
           win = ext(downscaled_22k$tasmax))*0.1)- 273.15)
karger_22k <- mask(karger_22k, disagg(mask_22ka, 6, "near"))
karger_22k
plot(karger_22k, main = paste(month.abb, " max - min temp"),
     range = c(-8, 8), fill_range = TRUE, col = hcl.colors(20, "Spectral"), 
     fun = function() lines(land))

# load in data for the first and last time step and check the effect of delta
downscaled_1950 <- list.files("/media/dafcluster4/storage/TraCE_1500_1990CE/1500_1990/chunk_out/04801_05880/out/",
                             recursive = TRUE, full.names = TRUE)
downscaled_1950 <- split(downscaled_1950, sapply(downscaled_1950, function(x) sub(".*CHELSA_([a-z]+)_.*", "\\1", basename(x)))) |> 
                    pblapply(function(x) app(rast(x), mean))
mask_1950 <- downscaled_1950$pr[[1]]
mask_1950 <- ifel(is.na(mask_1950), NA, 1)
plot(downscaled_1950$pr * 86400 * c(31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31))
plot((downscaled_1950$pr * 86400 * c(31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31)) * deltas_fine$pr)
plot((downscaled_1950$tas-273.15) + deltas_fine$tas)
minmax((downscaled_22k$tasmax + deltas_fine$tasmax) - (downscaled_22k$tas + deltas_fine$tas))
minmax((downscaled_22k$tasmin + deltas_fine$tasmin) - (downscaled_22k$tas + deltas_fine$tas))
minmax((downscaled_22k$tasmax[[1]] + deltas_fine$tasmax[[1]]) - (downscaled_22k$tasmin[[1]] + deltas_fine$tasmin[[1]]))

# some areas where max is < min
brown_contemp <- ((downscaled_22k$tasmax[[1]] - 273.15) + deltas_fine$tasmax[[1]]) - ((downscaled_22k$tasmin[[1]] - 273.15) + deltas_fine$tasmin[[1]])
plot(brown_22k, main = "brown maximum temp - minimum temp",
     range = c(-5, 5), fill_range = TRUE, col = hcl.colors(10, "Spectral"), 
     fun = function() lines(land))

# Karger et al have the same issue! Max is lower than the min after bias correction
karger_22k <- ((rast("/mnt/Data/CHELSA_Trace21/CHELSA_TraCE21k_tasmax_1_-200_V1.0.tif", 
      win = ext(downscaled_22k$tasmax))*0.1)- 273.15) -
      ((rast("/mnt/Data/CHELSA_Trace21/CHELSA_TraCE21k_tasmin_1_-200_V1.0.tif", 
           win = ext(downscaled_22k$tasmax))*0.1)- 273.15)
karger_22k <- mask(karger_22k, disagg(mask_22ka, 6, "near"))
karger_22k
plot(karger_22k, main = "karger maximum temp - karger minimum temp",
     range = c(-5, 5), fill_range = TRUE, col = hcl.colors(10, "Spectral"), 
     fun = function() lines(land))

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
