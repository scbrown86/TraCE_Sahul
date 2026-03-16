library(terra)
library(pbapply)
library(rnaturalearthhires)
library(qgisprocess)
library(data.table)

land <- vect(rnaturalearthhires::countries10)
land <- crop(land, ext(105.0, 161.25, -52.5, 11.25))
land <- aggregate(land)
land

template <- rast("02_data/trace_to_sahul_half_degree_bilin.nc")
template

setwd("/mnt/Data/TraCE21_SahulHalfDeg/")

# load in the deltas
deltas <- list(
  "pr" = rast("/home/dafcluster4/Documents/GitHub/TraCE_Sahul/02_data/02_processed/deltas/delta_halfdeg_pr_climatology_ncdf4.nc")*1,
  "tas" = rast("/home/dafcluster4/Documents/GitHub/TraCE_Sahul/02_data/02_processed/deltas/delta_halfdeg_tas_climatology_ncdf4.nc")*1,
  "dtr" = rast("/home/dafcluster4/Documents/GitHub/TraCE_Sahul/02_data/02_processed/deltas/delta_halfdeg_dtr_climatology_ncdf4.nc")*1)
deltas <- lapply(deltas, function(i) project(i, template, "cubicspline"))
deltas

sapply(deltas, panel)

# need to create the following input files
# INPUT DATA - CLIMATE DATA
# files to be stored in a subdirectory /clim
#
# huss.nc: a netCDF file containing relative humidity at the surface of n timesteps
# pr.nc: a netCDF file containing precipitation rate at the surface of n timesteps
# ta_high.nc: a netCDF file containing air temperatures at the higher pressure level used for the
# lapse rate calculation (e.g. 600.5 hPa [z=20]) of n timesteps
# ta_low.nc: a netCDF file containing air temperatures at the lower pressure level used for the
# lapse rate calculation (e.g. 992.5 hPa [z=26]) of n timesteps
# tasmax.nc: a netCDF file containing daily maximum near-surface air temperature of n timesteps
# tasmin.nc: a netCDF file containing daily minimum near-surface air temperature of n timesteps
# tas.nc: a netCDF file containing daily mean near-surface air temperature of n timesteps
# uwind.nc: a netCDF file containing the zonal wind component (u) of n timesteps
# vwind.nc: a netCDF file containing the meridional wind component (v) of n timesteps
# zg_high.nc: a netCDF file containing geopotential height (in meters) at the
# higher pressure level used for the lapse rate calculation (e.g. 600.5 hPa [z=20]) of n timesteps
# zg_low.nc: a netCDF file containing geopotential height (in meters) at the
# lower pressure level used for the lapse rate calculation (e.g. 992.5 hPa [z=26]) of n timesteps
#
# INPUT DATA - OROGRAPHIC DATA
# files to be stored in a subdirectory /orog
#
# oro.nc: a netCDF file containing the orography at the coarse (GCM) resolution
# of n timesteps (modified to work with a single timestep)
# oro_high.nc: a netCDF file containing the orography at the high (target)
# resolution of n timesteps (modified to work with a single timestep)
#
#
# INPUT DATA - STATIC DATA
# files to be stored in a subdirectory /static
#
# merc_template.nc: a netCDF file containing the orography at high (target)
# resolution in World Mercator projection
#
# EPSG:3395
# Proj4 string = '+proj=merc +lon_0=0 +k=1 +x_0=0 +y_0=0 +ellps=WGS84 +datum=WGS84 +units=m +no_defs'

# timesteps
n <- nlyr(rast("PRECC/trace.01-35.22000BP-1500CE.cam2.h0.PRECC.0000101-258600.Sahul.decavg.concat.nc"))
n_decades <- n / 12  # 2155
steps <- seq(1, by = 120, length.out = n_decades)
ends <- steps + 119
mids_months <- (steps + ends) / 2
mids_years <- mids_months / 12
time_bp <- 22000 - mids_years

time_steps <- data.table(
  layer = 1:n,
  dec = rep(1:n_decades, each = 12),
  Months = rep(1:12, times = n_decades),
  YearsBP = rep(ceiling(time_bp), each = 12))
time_steps[, YearsCE := rcarbon::BPtoBCAD(YearsBP)]
time_steps[, dec_year := YearsCE + (Months - 1 + 15.5 / 30.4375) / 12]
time_steps

# subset for layers for testing
idx <- time_steps[YearsBP >= 21975, ][["layer"]]

# create relative humidity data
huss <- rast("RELHUM/trace.01-35.22000BP-1500CE.cam2.h0.RELHUM.0000101-258600.Sahul.decavg.concat.nc",
             "RELHUM", lyrs = idx)
time(huss) <- time_steps[idx, ][["dec_year"]]
units(huss) <- "percent"
varnames(huss) <- "RELHUM (Relative humidity)"
names(huss) <- as.character(paste(time_steps[idx, ][["YearsBP"]], time_steps[idx, ][["Months"]],
                                  sep = "."))
crs(huss) <- "EPSG:4326"
huss
range(minmax(huss))
# plot(huss[[1:6]])
writeCDF(huss, "/home/dafcluster4/Desktop/CHELSA_LGM/huss.nc", #"02_data/02_processed/huss.nc",
         varname = "relhum",
         longname = "RELHUM (Relative humidity)",
         overwrite = TRUE,
         unit = "percent", zname = "time", prec = "float")

# create precipitation data
pr <- rast("PRECC/trace.01-35.22000BP-1500CE.cam2.h0.PRECC.0000101-258600.Sahul.decavg.concat.nc",
           "PRECC", lyrs = idx) +
  rast("PRECL/trace.01-35.22000BP-1500CE.cam2.h0.PRECL.0000101-258600.Sahul.decavg.concat.nc",
       "PRECL", lyrs = idx)
time(pr) <- time(huss)
units(pr) <- "kg/m2/s"
varnames(pr) <- "rainfall"
names(pr) <- names(huss)
crs(pr) <- "EPSG:4326"
pr
pr <- pr * deltas$pr # bias correct
pr
panel(pr[[floor(seq(1, 36, l = 6))]]*86400, range = c(0, 12), fill_range = TRUE)
pr <- ifel(pr < 0, 0, pr)
writeCDF(pr, "/home/dafcluster4/Desktop/CHELSA_LGM/pr.nc",#"02_data/02_processed/pr.nc",
         varname = "pr", longname = "precipitation",
         overwrite = TRUE,
         unit = "kg/m2/s", zname = "time", prec = "float")

# create ta_high
ta_high <- rast("T/trace.01-35.22000BP-1500CE.cam2.h0.T.0000101-258600.Sahul.decavg.concat.nc",
                "T")
## need TA @ [z=20]
ta_ind <- round(as.numeric(sapply(strsplit(names(ta_high), "=|_"), "[", 3)))
ta_ind <- which(ta_ind == 601)
ta_high <- ta_high[[ta_ind]]
ta_high <- ta_high[[idx]]
ta_high
time(ta_high) <- time(huss)
units(ta_high) <- "K"
varnames(ta_high) <- "Temperature"
names(ta_high) <- names(huss)
crs(ta_high) <- "EPSG:4326"
depth(ta_high) <- NULL
ta_high
# plot(ta_high[[1]], fun = function() lines(land, col = "#FFFFFF"))
# plot(ta_high[[1]]-273.15)
writeCDF(ta_high, "/home/dafcluster4/Desktop/CHELSA_LGM/ta_high.nc", #02_data/02_processed/ta_high.nc", varname = "T",
         longname = "T (TA_High)", overwrite = TRUE, unit = "K",
         zname = "time", prec = "float")

# create ta_low
ta_low <- rast("T/trace.01-35.22000BP-1500CE.cam2.h0.T.0000101-258600.Sahul.decavg.concat.nc",
               "T")
## need TA @ z=26
ta_ind <- round(as.numeric(sapply(strsplit(names(ta_low), "=|_"), "[", 3)))
ta_ind <- which(ta_ind == 993)
ta_low <- ta_low[[ta_ind]]
ta_low <- ta_low[[idx]]
time(ta_low) <- time(huss)
units(ta_low) <- "K"
varnames(ta_low) <- "Temperature"
names(ta_low) <- names(huss)
crs(ta_low) <- "EPSG:4326"
depth(ta_low) <- NULL
ta_low

# should all be positive
plot(ta_low[[1]] - ta_high[[1]], fun = function() lines(land, col = "#FFFFFF"))

writeCDF(ta_low, "/home/dafcluster4/Desktop/CHELSA_LGM/ta_low.nc", #02_data/02_processed/ta_low.nc",
         varname = "T", longname = "T (TA_low)",
         overwrite = TRUE,
         unit = "K", zname = "time", prec = "float")

# create tas
# create tas
tsmx <- rast("TSMX/trace.01-35.22000BP-1500CE.cam2.h0.TSMX.0000101-258600.Sahul.decavg.concat.nc", "TSMX",
             lyrs = idx)
tsmn <- rast("TSMN/trace.01-35.22000BP-1500CE.cam2.h0.TSMN.0000101-258600.Sahul.decavg.concat.nc", "TSMN",
             lyrs = idx)
tas <- (0.5 * (tsmx + tsmn)) + deltas$tas
dtr <- (tsmx - tsmn) * deltas$dtr
time(tas) <- time(dtr) <- time(huss)
tas
dtr

# tas
units(tas) <- "K"
varnames(tas) <- "Temperature"
longnames(tas) <- "mean temperature at surface"
names(tas) <- names(huss)
crs(tas) <- "EPSG:4326"
tas
writeCDF(tas, "/home/dafcluster4/Desktop/CHELSA_LGM/tas.nc", #"02_data/02_processed/tas.nc",
         varname = "tas",
         longname = "Mean Temperature", overwrite = TRUE, unit = "K",
         zname = "time", prec = "float")

# new tasmax
tasmax <- tas + (0.5 * dtr)
time(tasmax) <- time(huss)
units(tasmax) <- "K"
varnames(tasmax) <- "Temperature"
longnames(tasmax) <- "max temperature at surface"
names(tasmax) <- names(tas)
crs(tasmax) <- "EPSG:4326"
tasmax

# new tasmin
tasmin <- tas - (0.5 * dtr)
time(tasmin) <- time(huss)
units(tasmin) <- "K"
varnames(tasmin) <- "Temperature"
names(tasmin) <- names(tas)
crs(tasmin) <- "EPSG:4326"
tasmin

# check for neg dtr and write
sum(tasmax < tasmin)
writeCDF(tasmax, "/home/dafcluster4/Desktop/CHELSA_LGM/tasmax.nc", #"02_data/02_processed/tasmax.nc",
         varname = "tasmax",
         longname = "Maximum Temperature", overwrite = TRUE, unit = "K",
         zname = "time", prec = "float")
writeCDF(tasmin, "/home/dafcluster4/Desktop/CHELSA_LGM/tasmin.nc",#"02_data/02_processed/tasmin.nc",
         varname = "tasmin",
         longname = "Minimum Temperature", overwrite = TRUE, unit = "K",
         zname = "time", prec = "float")

# create uwind
uwind <- rast("U/trace.01-35.22000BP-1500CE.cam2.h0.U.0000101-258600.Sahul.decavg.concat.nc",
              "U", lyrs = idx)
time(uwind) <- time(huss)
units(uwind) <- "m/s"
varnames(uwind) <- "Zonal wind"
names(uwind) <- names(huss)
depth(uwind) <- NULL
crs(uwind) <- "EPSG:4326"
uwind
writeCDF(uwind, "/home/dafcluster4/Desktop/CHELSA_LGM/uwind.nc", #"02_data/02_processed/uwind.nc",
         varname = "U",
         longname = "Zonal wind", overwrite = TRUE, unit = "m/s",
         zname = "time", prec = "float")

# create vwind
vwind <- rast("V/trace.01-35.22000BP-1500CE.cam2.h0.V.0000101-258600.Sahul.decavg.concat.nc",
              "V", lyrs = idx)
time(vwind) <- time(huss)
units(vwind) <- "m/s"
varnames(vwind) <- "Meridional wind"
names(vwind) <- names(huss)
depth(vwind) <- NULL
crs(vwind) <- "EPSG:4326"
vwind
writeCDF(vwind, "/home/dafcluster4/Desktop/CHELSA_LGM/vwind.nc",
         #"02_data/02_processed/vwind.nc",
         varname = "V",
         longname = "Meridional wind", overwrite = TRUE, unit = "m/s",
         zname = "time", prec = "float")

# create zg_high
zg_high <- rast("Z3/trace.01-35.22000BP-1500CE.cam2.h0.Z3.0000101-258600.Sahul.decavg.concat.nc",
                "Z3")
## need zg @ [z=20]
zg_high_ind <- round(as.numeric(sapply(strsplit(names(zg_high), "=|_"), "[", 3)))
zg_high_ind <- which(zg_high_ind == 601)
zg_high <- zg_high[[zg_high_ind]]
zg_high <- zg_high[[idx]]
time(zg_high) <- time(huss)
units(zg_high) <- "m"
varnames(zg_high) <- "Geopotential Height (above sea level)"
names(zg_high) <- names(huss)
crs(zg_high) <- "EPSG:4326"
depth(zg_high) <- NULL
zg_high
writeCDF(zg_high, "/home/dafcluster4/Desktop/CHELSA_LGM/zg_high.nc", #"02_data/02_processed/zg_high.nc",
         varname = "z3",
         longname = "Geopotential Height", overwrite = TRUE, unit = "m",
         zname = "time", prec = "float")

# create zg_low
zg_low <- rast("Z3/trace.01-35.22000BP-1500CE.cam2.h0.Z3.0000101-258600.Sahul.decavg.concat.nc",
               "Z3")
## need zg @z=26
zg_low_ind <- round(as.numeric(sapply(strsplit(names(zg_low), "=|_"), "[", 3)))
zg_low_ind <- which(zg_low_ind == 993)
zg_low <- zg_low[[zg_low_ind]]
zg_low <- zg_low[[idx]]
time(zg_low) <- time(huss)
units(zg_low) <- "m"
varnames(zg_low) <- "Geopotential Height (above sea level)"
names(zg_low) <- names(huss)
crs(zg_low) <- "EPSG:4326"
depth(zg_low) <- NULL
zg_low
writeCDF(zg_low, "/home/dafcluster4/Desktop/CHELSA_LGM/zg_low.nc",#"02_data/02_processed/zg_low.nc",
         varname = "z3",
         longname = "Geopotential Height", overwrite = TRUE, unit = "m",
         zname = "time", prec = "float")

# quick lapse rate
# l = tl-th/zh-zl
(ta_low[[1:6]] - ta_high[[1:6]]) / (zg_high[[1:6]] - zg_low[[1:6]])
panel((ta_low[[1:6]] - ta_high[[1:6]]) / (zg_high[[1:6]] - zg_low[[1:6]]),
     fun = function() lines(land), range = c(0, 0.006), fill_range = TRUE)

# Create oro
oro <- rast("/home/dafcluster4/Documents/GitHub/TraCE_Sahul/02_data/01_inputs/TraCE21_elevation_22kaBP_1500CE_withBathy.tif")
oro <- oro[[1]] # data for LGM
oro

col_pal <- c(
  "#08306B", "#2171B5", "#4292C6", "#6BAED6", "#9ECAE1",
  "#006400", "#228B22", "#56A83A", "#8CC56A", "#ADDE9E",
  "#F4EBC1", "#E8D5A3", "#D9A066", "#C47A3A", "#A0522D")
plot(oro, col = col_pal,
     type = "interval",
     breaks = c(-9000, -2000, -1000, -500, -100, -1, 0,
                10, 25, 50, 100, 200, 500, 1000, 1500, 3000),
     fun = function() lines(land, col = "#000000", lwd = 1.5))
oro <- ifel(oro < 0, 0, oro)
time(oro) <- as.integer(format(time(oro), "%Y"))
units(oro) <- "m"
varnames(oro) <- "Orographic elevation"
names(oro) <- paste0(time(oro), "BP")
crs(oro) <- "EPSG:4326"
oro
writeCDF(oro, "/home/dafcluster4/Desktop/CHELSA_LGM/oro.nc", #02_data/02_processed/oro.nc",
         varname = "elevation",
         longname = "Orographic elevation", overwrite = TRUE, unit = "m",
         zname = "time", prec = "float")

# Create oro_high
land <- vect(rnaturalearthhires::countries10)

# oro_high <- rast("raw/Sahul_contemporary_elev.nc")
in_oro <- list.files("/mnt/Data/CHELSA_Trace21/Input",
                     full.names = TRUE, pattern = ".tif")
# match to timesteps for 21k BP
pattern <- "CHELSA_TraCE21k_dem_(-200)_V1\\.0\\.tif$"
in_oro <- grep(pattern, in_oro, value = TRUE)
oro_high <- rast(in_oro, win = ext(template))
oro_high

plot(oro_high, col = col_pal,
     type = "interval",
     breaks = c(-9000, -2000, -1000, -500, -100, -1, 0,
                10, 25, 50, 100, 200, 500, 1000, 1500, 3000),
     fun = function() lines(land, col = "#000000", lwd = 1.5))

# GEBCO 2014
bathy <- rast("~/Documents/GEBCO_2014_2D_Sahul.nc", win = ext(template)) # single layer, contemporary
bathy

plot(bathy, col = col_pal,
     type = "interval",
     breaks = c(-9000, -2000, -1000, -500, -100, -1, 0,
                10, 25, 50, 100, 200, 500, 1000, 1500, 3000),
     fun = function() lines(land, col = "#000000", lwd = 1.5))

# blend
blended <- ifel(oro_high < 0, bathy, oro_high)
blended
minmax(blended)
plot(blended, col = col_pal,
     type = "interval",
     breaks = c(-9000, -2000, -1000, -500, -100, -1, 0,
                10, 25, 50, 100, 200, 500, 1000, 1500, 3000),
     fun = function() lines(land, col = "#000000", lwd = 1.5))

# mean aggregation to ~5km grid
tmp_rst <- rast(
  res = 0.05, extent = ext(template),
  crs = "EPSG:4326")
tmp_rst
oro_5 <- project(blended, tmp_rst,
                 method = "average", use_gdal = TRUE)
plot(oro_5,
     col = col_pal,
     type = "interval",
     breaks = c(-9000, -2000, -1000, -500, -100, -1, 0,
                10, 25, 50, 100, 200, 500, 1000, 1500, 3000),
     fun = function() lines(land, col = "#000000", lwd = 1.5))

oro_5 <- setValues(oro_5, round(values(oro_5), 0)) # round to nearest metre
oro_5 <- ifel(oro_5 < 0, 0, oro_5)
units(oro_5) <- "m"
varnames(oro_5) <- "Orographic elevation"
crs(oro_5) <- "EPSG:4326"
oro_5

writeCDF(oro_5,
         "/home/dafcluster4/Desktop/CHELSA_LGM/oro_high.nc", #02_data/02_processed/oro_high.nc",
         varname = "elevation", longname = "Orographic elevation",
         unit = "m", prec = "float", compression = 1,
         missval = NA, overwrite = TRUE)

# merc_template
template_raster <- rast(
  extent = ext(blended),
  crs = "EPSG:4326",
  resolution = res(blended),
  vals = 1L)
sahul_prj <- "EPSG:3395"

template_raster <- project(template_raster, sahul_prj,
                           method = "near",
                           res = 4000)
template_raster
plot(template_raster, fun = function() lines(project(land, template_raster)))

# merc template only ever grabs the first step in Karger et al original code,
# so we can just use 22k
merc_template <- project(blended,
                         template_raster,
                         use_gdal = TRUE,
                         method = "average")
merc_template
plot(merc_template,
     col = col_pal,
     type = "interval",
     breaks = c(-9000, -2000, -1000, -500, -100, -1, 0,
                10, 25, 50, 100, 200, 500, 1000, 1500, 3000),
     fun = function() lines(project(land, template_raster),
                            col = "#000000", lwd = 1.5))

writeCDF(merc_template,
         "/home/dafcluster4/Desktop/CHELSA_LGM/merc_template.nc",#"02_data/02_processed/merc_template.nc",
         varname = "elevation", longname = "Orographic elevation",
         unit = "m", prec = "float", compression = 1,
         missval = NA, overwrite = TRUE)

# set up the CHELSA paleo folders
sapply(
  paste0(
    "/media/dafcluster4/storage/TraCE_22k_1500CE/",
    c("orog", "static", "clim", "out/tas", "out/tasmax", "out/tasmin",
      "out/pr")),
  dir.create,
  recursive = TRUE)
