library(terra)
library(pbapply)
library(rnaturalearthhires)
library(qgisprocess)

land <- vect(rnaturalearthhires::countries10)
land <- crop(land, ext(105.0, 161.25, -52.5, 11.25))
land <- aggregate(land)
land

template <- rast(extent = ext(-180, 180, -90, 90), res = 3.75, val = 1L)
template <- crop(template, ext(105, 161.25, -50, 10), snap = "out")
template

setwd("/home/dafcluster4/Documents/GitHub/temperature_test/")
# source("write_cdf_function.R")
# assignInNamespace(".write_cdf", write_cdf, ns = "terra")
# setwd("C:/Users/Stu/Desktop/Trace_CHELSA_Inputs")

# need to create the following input files
# INPUT DATA - CLIMATE DATA
# files to be stored in a subdirectory /clim
#
# huss.nc : a netCDF file containing relative humidity at the surface of n timesteps
# pr.nc : a netCDF file containing precipitation rate at the surface of n timesteps
# ta_high.nc : a netCDF file containing air temperatures at the higher pressure level used for the
# lapse rate calculation (e.g. 600.5 hPa [z=20]) of n timesteps
# ta_low.nc : a netCDF file containing air temperatures at the lower pressure level used for the
# lapse rate calculation (e.g. 992.5 hPa [z=26]) of n timesteps
# tasmax.nc : a netCDF file containing daily maximum near-surface air temperature of n timesteps
# tasmin.nc : a netCDF file containing daily minimum near-surface air temperature of n timesteps
# tas.nc : a netCDF file containing daily mean near-surface air temperature of n timesteps
# uwind.nc : a netCDF file containing the zonal wind component (u) of n timesteps
# vwind.nc : a netCDF file containing the meridional wind component (v) of n timesteps
# zg_high.nc : a netCDF file containing geopotential height (in meters) at the higher pressure level used for the
# lapse rate calculation (e.g. 600.5 hPa [z=20]) of n timesteps
# zg_low.nc : a netCDF file containing geopotential height (in meters) at the lower pressure level used for the
# lapse rate calculation (e.g. 992.5 hPa [z=26]) of n timesteps
#
# INPUT DATA - OROGRAPHIC DATA
# files to be stored in a subdirectory /orog
#
# oro.nc : a netCDF file containing the orography at the coarse (GCM) resolution of n timesteps (modified to work with a single timestep)
# oro_high.nc : a netCDF file containing the orography at the high (target) resolution of n timesteps (modified to work with a single timestep)
#
#
# INPUT DATA - STATIC DATA
# files to be stored in a subdirectory /static
#
# merc_template.nc : a netCDF file containing the orography at high (target) resolution in World Mercator projection
#
# EPSG:3395
# Proj4 string = '+proj=merc +lon_0=0 +k=1 +x_0=0 +y_0=0 +ellps=WGS84 +datum=WGS84 +units=m +no_defs'

# create relative humidity data
huss <- rast("02_data/01_inputs/trace.36.400BP-1990CE.cam2.h0.RELHUM.2160101-2204012.Sahul.1900_1989CE.nc", "RELHUM")
time(huss) <- rev(seq(as.Date("1989-12-16"), by = "-1 months", l = nlyr(huss)))
units(huss) <- "percent"
varnames(huss) <- "RELHUM (Relative humidity)"
names(huss) <- format(time(huss), "%b%Y")
crs(huss) <- "EPSG:4326"
huss
# plot(huss[[1:6]])
writeCDF(huss, "02_data/02_processed/huss.nc",
     varname = "relhum",
     longname = "RELHUM (Relative humidity)",
     overwrite = TRUE,
     unit = "percent", zname = "time", prec = "float"
)

# create precipitation data
pr <- rast("02_data/01_inputs/trace.36.400BP-1990CE.cam2.h0.PRECC.2160101-2204012.Sahul.1900_1989CE.nc", "PRECC") +
     rast("02_data/01_inputs/trace.36.400BP-1990CE.cam2.h0.PRECL.2160101-2204012.Sahul.1900_1989CE.nc", "PRECL")
time(pr) <- time(huss)
units(pr) <- "kg/m2/s"
varnames(pr) <- "rainfall"
names(pr) <- format(time(pr), "%b%Y")
crs(pr) <- "EPSG:4326"
pr
par(mfrow = c(1, 2))
plot(pr[[1]], fun = function() lines(land, col = "#FFFFFF"), main = "Jan 1900")
plot(app(pr[[1:12]] * 86400 * c(31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31), sum), fun = function() lines(land, col = "#FFFFFF"), main = "1900 total")
par(mfrow = c(1, 1))
writeCDF(pr, "02_data/02_processed/pr.nc",
     varname = "rain", longname = "rainfall",
     overwrite = TRUE,
     unit = "kg/m2/s", zname = "time", prec = "float"
)

# create ta_high
ta_high <- rast("02_data/01_inputs/trace.36.400BP-1990CE.cam2.h0.T.2160101-2204012.Sahul.1900_1989CE.nc", "T")
## need TA @ [z=20]
ta_ind <- round(as.numeric(sapply(strsplit(names(ta_high), "=|_"), "[", 3)))
ta_ind <- which(ta_ind == 601)
ta_high <- ta_high[[ta_ind]]
time(ta_high) <- time(huss)
units(ta_high) <- "K"
varnames(ta_high) <- "Temperature"
names(ta_high) <- format(time(ta_high), "%b%Y")
crs(ta_high) <- "EPSG:4326"
ta_high
# plot(ta_high[[1]], fun = function() lines(land, col = "#FFFFFF"))
# plot(ta_high[[1]]-273.15)
writeCDF(ta_high, "02_data/02_processed/ta_high.nc", varname = "T", longname = "T (TA_High)", overwrite = TRUE, unit = "K", zname = "time", prec = "float")

# create ta_low
ta_low <- rast("02_data/01_inputs/trace.36.400BP-1990CE.cam2.h0.T.2160101-2204012.Sahul.1900_1989CE.nc", "T")
## need TA @ z=26
ta_ind <- round(as.numeric(sapply(strsplit(names(ta_low), "=|_"), "[", 3)))
ta_ind <- which(ta_ind == 993)
ta_low <- ta_low[[ta_ind]]
time(ta_low) <- time(huss)
units(ta_low) <- "K"
varnames(ta_low) <- "Temperature"
names(ta_low) <- format(time(ta_low), "%b%Y")
crs(ta_low) <- "EPSG:4326"
ta_low

# should all be positive
plot(ta_low[[1]] - ta_high[[1]], fun = function() lines(land, col = "#FFFFFF"))


writeCDF(ta_low, "02_data/02_processed/ta_low.nc",
     varname = "T", longname = "T (TA_low)",
     overwrite = TRUE,
     unit = "K", zname = "time", prec = "float"
)

# create tasmax
tasmax <- rast("02_data/01_inputs/trace.36.400BP-1990CE.cam2.h0.TSMX.2160101-2204012.Sahul.1900_1989CE.nc", "TSMX")
time(tasmax) <- time(huss)
units(tasmax) <- "K"
varnames(tasmax) <- "Temperature"
names(tasmax) <- format(time(tasmax), "%b%Y")
crs(tasmax) <- "EPSG:4326"
tasmax
# plot(tasmax[[1080]], fun = function() lines(land, col = "#FFFFFF"))
# plot(tasmax[[1080]]-273.15, fun = function() lines(land, col = "#FFFFFF"))
writeCDF(tasmax, "02_data/02_processed/tasmax.nc", varname = "tasmax", longname = "Maximum Temperature", overwrite = TRUE, unit = "K", zname = "time", prec = "float")

# create tasmin
tasmin <- rast("02_data/01_inputs/trace.36.400BP-1990CE.cam2.h0.TSMN.2160101-2204012.Sahul.1900_1989CE.nc", "TSMN")
time(tasmin) <- time(huss)
units(tasmin) <- "K"
varnames(tasmin) <- "Temperature"
names(tasmin) <- format(time(tasmin), "%b%Y")
crs(tasmin) <- "EPSG:4326"
tasmin
# plot(tasmin[[1080]])
# plot(tasmin[[1080]]-273.15)
writeCDF(tasmin, "02_data/02_processed/tasmin.nc", varname = "tasmin", longname = "Minimum Temperature", overwrite = TRUE, unit = "K", zname = "time", prec = "float")
mask(tasmax[[1:6]] - tasmin[[1:6]], land)
mask(tasmax[[1:6]] - tasmin[[1:6]], land, inverse = TRUE)
plot(mask(tasmax[[1:6]] - tasmin[[1:6]], land), fun = function() lines(land), range = c(0, 50))

# create tas
tas <- rast("02_data/01_inputs/trace.36.400BP-1990CE.cam2.h0.TS.2160101-2204012.Sahul.1900_1989CE.nc", "TS")
time(tas) <- time(huss)
units(tas) <- "K"
varnames(tas) <- "Temperature"
names(tas) <- format(time(tas), "%b%Y")
crs(tas) <- "EPSG:4326"
tas
# plot(tas[[1080]])
# plot(tas[[1080]]-273.15)
tasmax[[1:6]] - tas[[1:6]]
tasmin[[1:6]] - tas[[1:6]]
writeCDF(tas, "02_data/02_processed/tas.nc", varname = "tas", longname = "Mean Temperature", overwrite = TRUE, unit = "K", zname = "time", prec = "float")

# create uwind
uwind <- rast("02_data/01_inputs/trace.36.400BP-1990CE.cam2.h0.U.2160101-2204012.Sahul.1900_1989CE.nc", "U")
## need U @ sea-level (993 hPa [z=26])
uwind_ind <- round(as.numeric(sapply(strsplit(names(uwind), "=|_"), "[", 3)))
uwind_ind <- which(uwind_ind == 993)
uwind <- uwind[[uwind_ind]]
time(uwind) <- time(huss)
units(uwind) <- "m/s"
varnames(uwind) <- "Zonal wind"
names(uwind) <- format(time(uwind), "%b%Y")
crs(uwind) <- "EPSG:4326"
uwind
writeCDF(uwind, "02_data/02_processed/uwind.nc", varname = "U", longname = "Zonal wind", overwrite = TRUE, unit = "m/s", zname = "time", prec = "float")

# create vwind
vwind <- rast("02_data/01_inputs/trace.36.400BP-1990CE.cam2.h0.V.2160101-2204012.Sahul.1900_1989CE.nc", "V")
## need V @ sea-level (993 hPa [z=26])
vwind_ind <- round(as.numeric(sapply(strsplit(names(vwind), "=|_"), "[", 3)))
vwind_ind <- which(vwind_ind == 993)
vwind <- vwind[[vwind_ind]]
time(vwind) <- time(huss)
units(vwind) <- "m/s"
varnames(vwind) <- "Meridional wind"
names(vwind) <- format(time(vwind), "%b%Y")
crs(vwind) <- "EPSG:4326"
vwind
writeCDF(vwind, "02_data/02_processed/vwind.nc", varname = "V", longname = "Meridional wind", overwrite = TRUE, unit = "m/s", zname = "time", prec = "float")

# create zg_high
zg_high <- rast("02_data/01_inputs/trace.36.400BP-1990CE.cam2.h0.Z3.2160101-2204012.Sahul.1900_1989CE.nc", "Z3")
## need zg @ [z=20]
zg_high_ind <- round(as.numeric(sapply(strsplit(names(zg_high), "=|_"), "[", 3)))
zg_high_ind <- which(zg_high_ind == 601)
zg_high <- zg_high[[zg_high_ind]]
time(zg_high) <- time(huss)
units(zg_high) <- "m"
varnames(zg_high) <- "Geopotential Height (above sea level)"
names(zg_high) <- format(time(zg_high), "%b%Y")
crs(zg_high) <- "EPSG:4326"
zg_high
writeCDF(zg_high, "02_data/02_processed/zg_high.nc", varname = "z3", longname = "Geopotential Height", overwrite = TRUE, unit = "m", zname = "time", prec = "float")

# create zg_low
zg_low <- rast("02_data/01_inputs/trace.36.400BP-1990CE.cam2.h0.Z3.2160101-2204012.Sahul.1900_1989CE.nc", "Z3")
## need zg @z=26
zg_low_ind <- round(as.numeric(sapply(strsplit(names(zg_low), "=|_"), "[", 3)))
zg_low_ind <- which(zg_low_ind == 993)
zg_low <- zg_low[[zg_low_ind]]
time(zg_low) <- time(huss)
units(zg_low) <- "m"
varnames(zg_low) <- "Geopotential Height (above sea level)"
names(zg_low) <- format(time(zg_low), "%b%Y")
crs(zg_low) <- "EPSG:4326"
zg_low
plot(zg_low[[1:6]])
zg_low[[1:6]] - zg_high[[1:6]] # should all be negative
writeCDF(zg_low, "02_data/02_processed/zg_low.nc", varname = "z3", longname = "Geopotential Height", overwrite = TRUE, unit = "m", zname = "time", prec = "float")

# quick lapse rate
# l = tl-th/zh-zl
(ta_low[[1:6]] - ta_high[[1:6]]) / (zg_high[[1:6]] - zg_low[[1:6]])
plot((ta_low[[1:6]] - ta_high[[1:6]]) / (zg_high[[1:6]] - zg_low[[1:6]]), fun = function() lines(land), range = c(0, 0.008))

# Create oro
oro <- rast("02_data/01_inputs/TraCE21_elevation.nc") * 1
oro

col_pal <- c(
     "#08306B",
     "#08519C",
     "#2171B5",
     "#4292C6",
     "#6BAED6",
     "#9ECAE1",
     "#006400",
     "#228B22",
     "#ADDEAD",
     "#F4EBC1",
     "#D9A066"
)


plot(oro,
     col = col_pal,
     breaks = c(-6000, -4000, -2000, -1000, -500, -100, 0, 100, 500, 1500, 2000, 4000),
     fun = function() lines(land, col = "#000000", lwd = 1.5)
)
time(oro) <- as.Date("1950-06-16")
units(oro) <- "m"
varnames(oro) <- "Orographic elevation"
names(oro) <- format(time(oro), "%b%Y")
crs(oro) <- "EPSG:4326"
oro
writeCDF(oro, "02_data/02_processed/oro.nc", varname = "elevation", longname = "Orographic elevation", overwrite = TRUE, unit = "m", zname = "time", prec = "float")

# Create oro_high
land <- vect(rnaturalearthhires::countries10)

# oro_high <- rast("raw/Sahul_contemporary_elev.nc")
oro_high <- rast("/mnt/Data/CHELSA_Trace21/Input/CHELSA_TraCE21k_dem_20_V1.0.tif")
oro_high <- crop(oro_high, ext(oro), snap = "out")
oro_high
# oro_high <- ifel(oro_high < 0, 0, oro_high)
plot(oro_high,
     col = col_pal,
     breaks = c(-6000, -4000, -2000, -1000, -500, -100, 0, 100, 500, 1500, 2000, 4000),
     fun = function() lines(land, col = "#000000", lwd = 1.5)
)

# mean aggregation to ~5km grid
tmp_rst <- rast(
     res = 0.05, extent = ext(oro),
     crs = "EPSG:4326"
)
tmp_rst
oro_4 <- project(oro_high, tmp_rst,
     method = "average",
     use_gdal = TRUE
)
oro_4 <- mask(oro_4, land, touches = TRUE)
plot(oro_4,
     col = col_pal,
     breaks = c(-6000, -4000, -2000, -1000, -500, -100, 0, 100, 500, 1500, 2000, 4000),
     fun = function() lines(land, col = "#000000", lwd = 1.5)
)
oro_4 <- setValues(oro_4, round(values(oro_4), 1))
units(oro_4) <- "m"
varnames(oro_4) <- "Orographic elevation"
crs(oro_4) <- "EPSG:4326"
oro_4

writeCDF(oro_4,
     "02_data/02_processed/oro_high.nc",
     varname = "elevation", longname = "Orographic elevation",
     unit = "m", prec = "float", compression = 1,
     missval = NA, overwrite = TRUE
)

# merc_template
template_raster <- rast(
     extent = ext(oro_4),
     crs = "EPSG:4326",
     resolution = res(oro_4),
     vals = 1L
)
sahul_prj <- "EPSG:3395"

# sahul_prj <- 'PROJCS["Lambert_Azimuthal_Sahul",
#  GEOGCS["GCS_WGS_1984",
#   DATUM["D_WGS_1984",
#    SPHEROID["WGS_1984",6378137.0,298.257223563]],
#   PRIMEM["Greenwich",0.0],
#   UNIT["Degree",0.0174532925199433]],
#  PROJECTION["Lambert_Azimuthal_Equal_Area"],
#  PARAMETER["False_Easting",0.0],
#  PARAMETER["False_Northing",0.0],
#  PARAMETER["Central_Meridian",133],
#  PARAMETER["Latitude_Of_Origin",-21.5],
#  UNIT["Meter",1.0]]'

template_raster <- project(template_raster, sahul_prj,
     method = "near",
     res = 4000
)
template_raster
plot(template_raster, fun = function() lines(project(land, template_raster)))

merc_template <- project(oro_4,
     template_raster,
     # threads = 12,
     use_gdal = TRUE,
     method = "average"
)
merc_template
merc_template <- setValues(merc_template, round(values(merc_template), 1))
plot(merc_template,
     col = col_pal,
     breaks = c(-6000, -4000, -2000, -1000, -500, -100, 0, 100, 500, 1500, 2000, 4000),
     fun = function() lines(project(land, merc_template), col = "#000000", lwd = 1.5)
)

writeCDF(merc_template,
     "02_data/02_processed/merc_template.nc",
     varname = "elevation", longname = "Orographic elevation",
     unit = "m", prec = "float", compression = 1,
     missval = NA, overwrite = TRUE
)
