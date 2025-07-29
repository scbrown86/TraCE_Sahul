library(terra)
library(pbapply)
library(rnaturalearthhires)
library(qgisprocess)
library(data.table)
library(enmSdmX)
land <- vect(rnaturalearthhires::countries10)
land <- crop(land, ext(105.0, 161.25, -52.5, 11.25))
land <- aggregate(land)
land

template <- rast(extent = ext(-180, 180, -90, 90), res = 3.75, val = 1L)
template <- crop(template, ext(105, 161.25, -50, 10), snap = "out")
template

# setwd("/home/dafcluster4/Documents/GitHub/TraCE_Sahul")

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

# timesteps
nc <- ncdf4::nc_open("/mnt/Data/TraCE21_Sahul/PRECC/trace.01-36.22000BP-1990CE.cam2.h0.PRECC.0000101-2204012.Sahul.concat.nc")
years <- ncdf4::ncvar_get(nc, "year")
head(years, 20)
tail(years, 20)

months <- ncdf4::ncvar_get(nc, "month")
head(months, 100)
tail(months, 100)

ncdf4::nc_close(nc)

time_steps <- data.table(ID = 1:length(years),
                         Years = years, 
                         Months = months)

# sequence of decades
time_steps[, dec := rep(1:(length(years) / 120), each = 120)]
time_steps

time_steps <- copy(time_steps)[Years <= 1499, ][, .(Months = 1:12, Years = ceiling(mean(Years))), by = dec]
time_steps[, dec_year := Years + (Months - 1 + 15.5 / 30.4375) / 12]
time_steps

# create relative humidity data
huss <- rast("/media/dafcluster4/storage/TraCE_Decadal/RELHUM/trace.01-35.22000BP-1500CE.cam2.h0.RELHUM.0000101-258600.Sahul.decavg.concat.nc", "RELHUM")
time(huss) <- time_steps[["dec_year"]]
units(huss) <- "percent"
varnames(huss) <- "RELHUM (Relative humidity)"
names(huss) <- as.character(paste(time_steps[["Years"]], time_steps[["Months"]], sep = "."))
crs(huss) <- "EPSG:4326"
huss
# plot(huss[[1:6]])
writeCDF(huss, "02_data/02_processed/huss.nc",
     varname = "relhum",
     longname = "RELHUM (Relative humidity)",
     overwrite = TRUE,
     unit = "percent", zname = "time", prec = "float")

# create precipitation data
pr <- rast("/media/dafcluster4/storage/TraCE_Decadal/PRECC/trace.01-35.22000BP-1500CE.cam2.h0.PRECC.0000101-258600.Sahul.decavg.concat.nc", "PRECC") +
     rast("/media/dafcluster4/storage/TraCE_Decadal/PRECL/trace.01-35.22000BP-1500CE.cam2.h0.PRECL.0000101-258600.Sahul.decavg.concat.nc", "PRECL")
time(pr) <- time(huss)
units(pr) <- "kg/m2/s"
varnames(pr) <- "rainfall"
names(pr) <- as.character(paste(time_steps[["Years"]], time_steps[["Months"]], sep = "."))
crs(pr) <- "EPSG:4326"
pr
# par(mfrow = c(1, 2))
# plot(pr[[1]], fun = function() lines(land, col = "#FFFFFF"), main = "Jan 1600")
# plot(app(pr[[1:12]] * 86400 * c(31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31), sum), fun = function() lines(land, col = "#FFFFFF"), main = "1600 total")
# par(mfrow = c(1, 1))
writeCDF(pr, "02_data/02_processed/pr.nc",
     varname = "pr", longname = "precipitation",
     overwrite = TRUE,
     unit = "kg/m2/s", zname = "time", prec = "float")

# create ta_high
ta_high <- rast("/media/dafcluster4/storage/TraCE_Decadal/T/trace.01-35.22000BP-1500CE.cam2.h0.T.0000101-258600.Sahul.decavg.concat.nc", "T")
## need TA @ [z=20]
ta_ind <- round(as.numeric(sapply(strsplit(names(ta_high), "=|_"), "[", 3)))
ta_ind <- which(ta_ind == 601)
ta_high <- ta_high[[ta_ind]]
time(ta_high) <- time(huss)
units(ta_high) <- "K"
varnames(ta_high) <- "Temperature"
names(ta_high) <- names(huss)
crs(ta_high) <- "EPSG:4326"
depth(ta_high) <- NULL
ta_high
# plot(ta_high[[1]], fun = function() lines(land, col = "#FFFFFF"))
# plot(ta_high[[1]]-273.15)
writeCDF(ta_high, "02_data/02_processed/ta_high.nc", varname = "T", longname = "T (TA_High)", overwrite = TRUE, unit = "K", zname = "time", prec = "float")

# create ta_low
ta_low <- rast("/media/dafcluster4/storage/TraCE_Decadal/T/trace.01-35.22000BP-1500CE.cam2.h0.T.0000101-258600.Sahul.decavg.concat.nc", "T")
## need TA @ z=26
ta_ind <- round(as.numeric(sapply(strsplit(names(ta_low), "=|_"), "[", 3)))
ta_ind <- which(ta_ind == 993)
ta_low <- ta_low[[ta_ind]]
time(ta_low) <- time(huss)
units(ta_low) <- "K"
varnames(ta_low) <- "Temperature"
names(ta_low) <- names(huss)
crs(ta_low) <- "EPSG:4326"
depth(ta_low) <- NULL
ta_low

# should all be positive
plot(ta_low[[1]] - ta_high[[1]], fun = function() lines(land, col = "#FFFFFF"))


writeCDF(ta_low, "02_data/02_processed/ta_low.nc",
     varname = "T", longname = "T (TA_low)",
     overwrite = TRUE,
     unit = "K", zname = "time", prec = "float")

# create tasmax
tasmax <- rast("/media/dafcluster4/storage/TraCE_Decadal/TSMX/trace.01-35.22000BP-1500CE.cam2.h0.TSMX.0000101-258600.Sahul.decavg.concat.nc", "TSMX")
time(tasmax) <- time(huss)
units(tasmax) <- "K"
varnames(tasmax) <- "Temperature"
crs(tasmax) <- "EPSG:4326"
names(tasmax) <- names(huss)
tasmax
# plot(tasmax[[1080]], fun = function() lines(land, col = "#FFFFFF"))
# plot(tasmax[[1080]]-273.15, fun = function() lines(land, col = "#FFFFFF"))
writeCDF(tasmax, "02_data/02_processed/tasmax.nc", varname = "tasmax", longname = "Maximum Temperature", overwrite = TRUE, unit = "K", zname = "time", prec = "float")

# create tasmin
tasmin <- rast("/media/dafcluster4/storage/TraCE_Decadal/TSMN/trace.01-35.22000BP-1500CE.cam2.h0.TSMN.0000101-258600.Sahul.decavg.concat.nc", "TSMN")
time(tasmin) <- time(huss)
units(tasmin) <- "K"
varnames(tasmin) <- "Temperature"
names(tasmin) <- names(huss)
crs(tasmin) <- "EPSG:4326"
tasmin
# plot(tasmin[[1080]])
# plot(tasmin[[1080]]-273.15)
writeCDF(tasmin, "02_data/02_processed/tasmin.nc", varname = "tasmin", longname = "Minimum Temperature", overwrite = TRUE, unit = "K", zname = "time", prec = "float")
# mask(tasmax[[1:6]] - tasmin[[1:6]], land)
# mask(tasmax[[1:6]] - tasmin[[1:6]], land, inverse = TRUE)
# plot(mask(tasmax[[1:6]] - tasmin[[1:6]], land), fun = function() lines(land), range = c(0, 50))

# create tas
tas <- rast("/media/dafcluster4/storage/TraCE_Decadal/TS/trace.01-35.22000BP-1500CE.cam2.h0.TS.0000101-258600.Sahul.decavg.concat.nc", "TS")
time(tas) <- time(huss)
units(tas) <- "K"
varnames(tas) <- "Temperature"
names(tas) <- names(huss)
crs(tas) <- "EPSG:4326"
tas
# plot(tas[[1080]])
# plot(tas[[1080]]-273.15)
tasmax[[1:6]] - tas[[1:6]]
tasmin[[1:6]] - tas[[1:6]]
writeCDF(tas, "02_data/02_processed/tas.nc", varname = "tas", longname = "Mean Temperature", overwrite = TRUE, unit = "K", zname = "time", prec = "float")

# create uwind
uwind <- rast("/media/dafcluster4/storage/TraCE_Decadal/U/trace.01-35.22000BP-1500CE.cam2.h0.U.0000101-258600.Sahul.decavg.concat.nc", "U")
## need U @ sea-level (993 hPa [z=26])
# uwind_ind <- round(as.numeric(sapply(strsplit(names(uwind), "=|_"), "[", 3)))
# uwind_ind <- which(uwind_ind == 993)
# uwind <- uwind[[uwind_ind]]
time(uwind) <- time(huss)
units(uwind) <- "m/s"
varnames(uwind) <- "Zonal wind"
names(uwind) <- names(huss)
depth(uwind) <- NULL
crs(uwind) <- "EPSG:4326"
uwind
writeCDF(uwind, "02_data/02_processed/uwind.nc", varname = "U", longname = "Zonal wind", overwrite = TRUE, unit = "m/s", zname = "time", prec = "float")

# create vwind
vwind <- rast("/media/dafcluster4/storage/TraCE_Decadal/V/trace.01-35.22000BP-1500CE.cam2.h0.V.0000101-258600.Sahul.decavg.concat.nc", "V")
## need V @ sea-level (993 hPa [z=26])
# vwind_ind <- round(as.numeric(sapply(strsplit(names(vwind), "=|_"), "[", 3)))
# vwind_ind <- which(vwind_ind == 993)
# vwind <- vwind[[vwind_ind]]
time(vwind) <- time(huss)
units(vwind) <- "m/s"
varnames(vwind) <- "Meridional wind"
names(vwind) <- names(huss)
depth(vwind) <- NULL
crs(vwind) <- "EPSG:4326"
vwind
writeCDF(vwind, "02_data/02_processed/vwind.nc", varname = "V", longname = "Meridional wind", overwrite = TRUE, unit = "m/s", zname = "time", prec = "float")

# create zg_high
zg_high <- rast("/media/dafcluster4/storage/TraCE_Decadal/Z3/trace.01-35.22000BP-1500CE.cam2.h0.Z3.0000101-258600.Sahul.decavg.concat.nc", "Z3")
## need zg @ [z=20]
zg_high_ind <- round(as.numeric(sapply(strsplit(names(zg_high), "=|_"), "[", 3)))
zg_high_ind <- which(zg_high_ind == 601)
zg_high <- zg_high[[zg_high_ind]]
time(zg_high) <- time(huss)
units(zg_high) <- "m"
varnames(zg_high) <- "Geopotential Height (above sea level)"
names(zg_high) <- names(huss)
crs(zg_high) <- "EPSG:4326"
depth(zg_high) <- NULL
zg_high
writeCDF(zg_high, "02_data/02_processed/zg_high.nc", varname = "z3", longname = "Geopotential Height", overwrite = TRUE, unit = "m", zname = "time", prec = "float")

# create zg_low
zg_low <- rast("/media/dafcluster4/storage/TraCE_Decadal/Z3/trace.01-35.22000BP-1500CE.cam2.h0.Z3.0000101-258600.Sahul.decavg.concat.nc", "Z3")
## need zg @z=26
zg_low_ind <- round(as.numeric(sapply(strsplit(names(zg_low), "=|_"), "[", 3)))
zg_low_ind <- which(zg_low_ind == 993)
zg_low <- zg_low[[zg_low_ind]]
time(zg_low) <- time(huss)
units(zg_low) <- "m"
varnames(zg_low) <- "Geopotential Height (above sea level)"
names(zg_low) <- names(huss)
crs(zg_low) <- "EPSG:4326"
depth(zg_low) <- NULL
zg_low
# plot(zg_low[[1:6]])
zg_low[[1:6]] - zg_high[[1:6]] # should all be negative
writeCDF(zg_low, "02_data/02_processed/zg_low.nc", varname = "z3", longname = "Geopotential Height", overwrite = TRUE, unit = "m", zname = "time", prec = "float")

# quick lapse rate
# l = tl-th/zh-zl
(ta_low[[1:6]] - ta_high[[1:6]]) / (zg_high[[1:6]] - zg_low[[1:6]])
plot((ta_low[[1:6]] - ta_high[[1:6]]) / (zg_high[[1:6]] - zg_low[[1:6]]), fun = function() lines(land), range = c(0, 0.006), fill_range = TRUE)

# Create oro
oro <- rast("02_data/01_inputs/TraCE21_elevation_22kaBP_1490CE.nc") * 1
names(oro) <- unique(time_steps[["Years"]])
time(oro) <- unique(time_steps[["Years"]])
units(oro) <- "m"
varnames(oro) <- "Orographic elevation"
crs(oro) <- "EPSG:4326"
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
     "#D9A066")

plot(oro[[c(1, 2155)]],
     col = col_pal,
     breaks = c(-6000, -4000, -2000, -1000, -500, -100, 0, 100, 500, 1500, 2000, 4000),
     fun = function() lines(land, col = "#000000", lwd = 1.5))

writeCDF(oro, "02_data/02_processed/oro.nc", varname = "elevation", longname = "Orographic elevation", overwrite = TRUE, unit = "m", zname = "time", prec = "float")

# Create oro_high
land <- vect(rnaturalearthhires::countries10)

# oro_high <- rast("raw/Sahul_contemporary_elev.nc")
in_oro <- gtools::mixedsort(list.files("/mnt/Data/CHELSA_Trace21/Input",
     full.names = TRUE, pattern = ".tif$"))
in_oro <- in_oro[grepl("dem", in_oro)]
in_oro <- in_oro[1:216]
# match to timesteps for 1600 onwards (https://chelsa-climate.org/chelsa-trace21k/)
# pattern <- "CHELSA_TraCE21k_dem_(17|18|19|20)_V1\\.0\\.tif$"
# pattern <- "CHELSA_TraCE21k_dem_-(1[0-9]{2}|200|[2-9][0-9]|[1-9])_V1\\.0\\.tif$|CHELSA_TraCE21k_dem_-0?_V1\\.0\\.tif$|CHELSA_TraCE21k_dem_([0-9]|1[0-5])_V1\\.0\\.tif$"
# in_oro <- grep(pattern, in_oro, value = TRUE)
in_oro
oro_z <- seq(-20001, 1499, 100)
oro_z_kaBP <- seq(22, 0.5, -0.1)*1000
length(in_oro) == length(oro_z)

# read in the high res oro data, project to 5km
tmp_rst <- rast(
     res = 0.05, extent = ext(oro),
     crs = "EPSG:4326")
tmp_rst

oro_high <- rast(pblapply(seq_along(in_oro), function(i) {
     r <- rast(in_oro[i], win = ext(oro), snap = "out")
     r <- project(r, tmp_rst, method = "average", use_gdal = TRUE)
     r <- setValues(r, round(values(r), 3))
     time(r) <- oro_z[i]
     names(r) <- oro_z[i]
     units(r) <- "m"
     varnames(r) <- "Orographic elevation"
     crs(r) <- "EPSG:4326"
     r 
}))
time(oro_high) <- rcarbon::BPtoBCAD(oro_z_kaBP)
oro_high <- c(oro_high, oro_high[[216]])
time(oro_high) <- c(rcarbon::BPtoBCAD(oro_z_kaBP), 1500)
oro_high

# need to interpolate to decadal timesteps
oro_high_22k <- enmSdmX::interpolateRasts(rasts = oro_high,
                                         interpFrom = time(oro_high),
                                         interpTo = seq(-20050, 1490, by = 10), 
                                         type = "linear",
                                         useRasts = FALSE,
                                         verbose = TRUE)
time(oro_high_22k) <- seq(-20050, 1495, by = 10)
names(oro_high_22k) <- time(oro_high_22k)
oro_high_22k

nlyr(oro) == nlyr(oro_high_22k)

plot(oro_high_22k[[c(1, 2155)]],
     col = col_pal,
     breaks = c(-6000, -4000, -2000, -1000, -500, -100, 0, 100, 500, 1500, 2000, 4000),
     fun = function() lines(land, col = "#000000", lwd = 1.5))

# save in steps of 100 years
out_steps <- pbsapply(seq(1, nlyr(oro_high_22k), by = 100), function(i) {
     j <- i + 99
     if (j > 2155) j <- 2155
     fout <- sprintf("02_data/02_processed/scratch/oro_high_22k_%04d_%04d.nc", i, j)
     r <- subset(oro_high_22k, subset = i:j)
     r <- setValues(r, round(values(r), 1))
     writeCDF(r, fout,
              varname = "elevation", longname = "Orographic elevation",
              unit = "m", prec = "float", compression = 1,
              zname = "time",
              missval = NA, overwrite = TRUE)
     return(fout)
})

# use cdo to concat the files. Output file here needs to be moved to 02_data/02_processed/oro_high.nc
'conda activate nco_stable; cd "02_data/02_processed/scratch/"; mapfile -t nc_files < <(ls -v1 *.nc 2>/dev/null); printf '%s\n' "${nc_files[@]}" >"input_order.txt"; cdo -f nc4 -P 50 -O -pack -cat "${nc_files[@]}" oro_high_22k.nc'

# this fails due to files size and having to hold two copies in memory
# writeCDF(oro_high_22k,
#      "02_data/02_processed/oro_high.nc",
#      varname = "elevation", longname = "Orographic elevation",
#      unit = "m", prec = "float", compression = 1,
#      zname = "time",
#      missval = NA, overwrite = TRUE)

# merc_template
template_raster <- rast(
     extent = ext(oro_high_22k),
     crs = "EPSG:4326",
     resolution = res(oro_high_22k),
     vals = 1L)
sahul_prj <- "EPSG:3395"

template_raster <- project(template_raster, sahul_prj,
     method = "near",
     res = 4000)
template_raster
plot(template_raster, fun = function() lines(project(land, template_raster)))

# merc template only ever grabs the first step in Dirks original code, so we can just use 22k
merc_template <- project(oro_high_22k[[1]],
     template_raster,
     # threads = 12,
     use_gdal = TRUE,
     method = "average")
merc_template
plot(merc_template,
     col = col_pal,
     breaks = c(-6000, -4000, -2000, -1000, -500, -100, 0, 100, 500, 1500, 2000, 4000),
     fun = function() lines(project(land, merc_template), col = "#000000", lwd = 1.5))

writeCDF(merc_template,
     "02_data/02_processed/merc_template.nc",
     varname = "elevation", longname = "Orographic elevation",
     unit = "m", prec = "float", compression = 1,
     missval = NA, overwrite = TRUE)

# set up the CHELSA paleo folders
sapply(
     paste0(
          "/media/dafcluster4/storage/TraCE_22k_1500CE/",
          c("orog", "static", "clim", "out/tas", "out/tasmax", "out/tasmin", "out/pr")),
     dir.create,
     recursive = TRUE)
