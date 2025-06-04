library(terra)
setGDALconfig("GDAL_PAM_ENABLED", "FALSE") # don't write aux files!
terraOptions(memfrac = 0.85, memmax = 20)
library(gtools)
library(pbapply)
library(rnaturalearthhires)

land <- vect(rnaturalearthhires::countries10)
land <- crop(land, ext(105.0, 161.25, -52.5, 11.25))
land <- aggregate(land)
land
plot(land)

# load in the fine scale deltas
deltas_fine <- list.files("02_data/02_processed/deltas",
                          pattern = ".nc$", full.names = TRUE)
deltas_fine <- lapply(deltas_fine, rast)
names(deltas_fine) <- c("pr", "tas", "tasmax", "tasmin")
deltas_fine

# load in the brown downscaled data
brown <- list.files("02_data/03_CHELSA_paleo/out/",
                    recursive = TRUE, pattern = "1900_1990.nc$",
                    full.names = TRUE)
brown
brown <- pblapply(brown, function(i) {
  r <- rast(i)
  time(r) <- seq(as.Date("1900-01-16"), by = "month", l = nlyr(r))
  r_u <- units(r)[1]
  r_v <- varnames(r[[1]])
  l_v <- longnames(r[[1]])
  crs(r) <- "EPSG:4326"
  units(r) <- r_u
  if (r_u == "K") {
    r <- setValues(r, values(r) - 273.15)
    units(r) <- "deg_C"
  }
  varnames(r) <- r_v
  longnames(r) <- l_v
  time(r) <- seq(as.Date("1900-01-16"), by = "month", l = nlyr(r))
  names(r) <- format(time(r), "%b%Y")
  return(r)
})
names(brown) <- c("pr", "tas", "tasmax", "tasmin")
brown
par(mfrow = c(2,2))
sapply(brown, function(i) plot(i[[1]]))
par(mfrow = c(1,1))
nlyr(brown$pr) %% nlyr(deltas_fine$pr)

brown$pr <- brown$pr * deltas_fine$pr
brown$tas <- brown$tas + deltas_fine$tas
brown$tasmax <- brown$tasmax + deltas_fine$tasmax
brown$tasmin <- brown$tasmin + deltas_fine$tasmin
brown

units(brown$pr) <- "kg/m2/s"
units(brown$tas) <- units(brown$tasmax) <- units(brown$tasmin) <- "deg_C"

brown

par(mfrow = c(2,2))
sapply(brown, function(i) plot(i[[1]]))
par(mfrow = c(1,1))

# save to netCDF
sapply(seq_along(brown), function(i) {
  r <- brown[[i]]
  writeCDF(
    x = r,
    filename = sprintf("02_data/03_CHELSA_paleo/out/%s_downscaled_and_bc.nc", varnames(r[[1]])),
    varname = varnames(r[[1]]), longname = longnames(r[[1]]),
    unit = units(r[[1]]), zname = "time", prec = "float",
    overwrite = TRUE
  )
})
