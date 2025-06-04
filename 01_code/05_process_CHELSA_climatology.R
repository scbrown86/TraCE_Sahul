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
#### CHELSA ####

# load in CHELSA V1.2 data at original res
# calculate averages between 1980 and 1989
processed_chelsa <- lapply(c("prec", "tmin", "tmax", "tmean"), function(v, ...) {
    chelsa_proc(
        variable = v,
        mask = NULL,
        ymin = 1980, ymax = 1989,
        tras_ext = ext(105.0, 161.25, -52.5, 11.25),
        load_exist = TRUE,
        dir = "/mnt/Data/CHELSA/v1.2",
        outdir = "02_data/02_processed/CHELSA",
        cores = 5L
    )
})
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

idx <- format(time(pr_avg), "%b")

chelsa_climatologies <- c(
  "02_data/02_processed/CHELSA/CHELSA_pr_climatology.nc",
  "02_data/02_processed/CHELSA/CHELSA_tasmin_climatology.nc",
  "02_data/02_processed/CHELSA/CHELSA_tasmax_climatology.nc",
  "02_data/02_processed/CHELSA/CHELSA_tas_climatology.nc"
)

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
           overwrite = TRUE
  )
  writeCDF(tmn_avg, "02_data/02_processed/CHELSA/CHELSA_tasmin_climatology.nc",
           varname = "tasmin",
           longname = "minimum near surface air temperature",
           # compression = 6L,
           unit = "deg_C", zname = "time", prec = "float",
           overwrite = TRUE
  )
  writeCDF(tmx_avg, "02_data/02_processed/CHELSA/CHELSA_tasmax_climatology.nc",
           varname = "tasmax",
           longname = "maximum near surface air temperature",
           # compression = 6L,
           unit = "deg_C", zname = "time", prec = "float",
           overwrite = TRUE
  )
  writeCDF(tas_avg, "02_data/02_processed/CHELSA/CHELSA_tas_climatology.nc",
           varname = "tas",
           longname = "mean near surface air temperature",
           # compression = 6L,
           unit = "deg_C", zname = "time", prec = "float",
           overwrite = TRUE
  )
}

# convert the CHELSA climatology data to 0.5 degree using b-splines
source("01_code/00_functions/interpolate_bspline.R")
fine_clim <- list(pr_avg, tas_avg, tmn_avg, tmx_avg)
varnames(fine_clim[[1]]) <- "pr"
varnames(fine_clim[[2]]) <- "tas"
varnames(fine_clim[[3]]) <- "tasmin"
varnames(fine_clim[[4]]) <- "tasmax"
fine_clim
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

#### TRACE ####
# load in the downscaled Brown data
brown <- list.files("02_data/03_CHELSA_paleo/out/",
                    recursive = TRUE, pattern = "1900_1990.nc$",
                    full.names = TRUE)
brown <- pblapply(brown, function(i) {
  r <- rast(i)
  time(r) <- seq(as.Date("1900-01-16"), by = "month", l = nlyr(r))
  r_u <- units(r)[1]
  r_v <- varnames(r[[1]])
  l_v <- longnames(r[[1]])
  r <- r[[which(time(r) >= "1980-01-01")]] # 1980 onwards only
  r <- tapp(r, "months", "mean")
  units(r) <- r_u
  r <- project(r, rast(res = 0.05, extent = ext(105, 161.25, -52.5, 11.25),
                       crs = "EPSG:4326"),
               method = "average")
  if (r_u == "K") {
    r <- setValues(r, values(r)-273.15)
    units(r) <- "deg_C"
  }
  varnames(r) <- r_v
  longnames(r) <- l_v
  time(r) <- seq(as.Date("1985-01-16"), by = "month", l = 12)
  names(r) <- month.abb
  return(r)
})
names(brown) <- c("pr", "tas", "tasmax", "tasmin")
brown

# convert downscaled TraCE climatology to 0.5 degrees
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

#### DELTAS ####
# create delta between the CHELSA and downscaled TraCE climatology
minmax(coarse_chelsa_clim$pr*(c(31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31)*86400))
minmax(coarse_trace_clim$pr*(c(31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31)*86400))

delta_pr <- (coarse_chelsa_clim$pr*(c(31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31)*86400)+1)/
  (coarse_trace_clim$pr*(c(31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31)*86400)+1)
delta_pr
plot(delta_pr, fun = function() lines(land, col = "#FFFFFF"))

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

# test adding the delta to brown downscaled
brown_corrected <- brown
names(brown_corrected) <- names(coarse_trace_clim)
brown_corrected
brown_corrected$pr <- brown_corrected$pr * deltas_fine$pr
brown_corrected$tas <- brown_corrected$tas + deltas_fine$tas
brown_corrected$tasmin <- brown_corrected$tasmin + deltas_fine$tasmin
brown_corrected$tasmax <- brown_corrected$tasmax + deltas_fine$tasmax
brown_corrected

plot(brown$pr, fun = function() lines(land, col = "#000000"))
plot(brown_corrected$pr, fun = function() lines(land, col = "#000000"))

plot(brown$tas, fun = function() lines(land, col = "#000000"))
plot(brown_corrected$tas, fun = function() lines(land, col = "#000000"))

plot(brown$tasmin, fun = function() lines(land, col = "#000000"))
plot(brown_corrected$tasmin, fun = function() lines(land, col = "#000000"))

plot(brown$tasmax, fun = function() lines(land, col = "#000000"))
plot(brown_corrected$tasmax, fun = function() lines(land, col = "#000000"))
