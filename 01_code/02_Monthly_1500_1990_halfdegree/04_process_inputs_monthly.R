library(terra)
library(pbapply)
library(rnaturalearthhires)
library(qgisprocess)

land <- vect(rnaturalearthhires::countries10)
land <- crop(land, ext(105.0, 161.25, -52.5, 11.25))
land <- aggregate(land)
land

template <- rast("02_data/trace_to_sahul_half_degree_bilin.nc")
template

setwd("/home/dafcluster4/Documents/GitHub/TraCE_Sahul")

# load in the deltas
deltas <- list(
     "pr" = rast("/home/dafcluster4/Documents/GitHub/TraCE_Sahul/02_data/02_processed/deltas/delta_halfdeg_pr_climatology_ncdf4.nc")*1,
     "tas" = rast("/home/dafcluster4/Documents/GitHub/TraCE_Sahul/02_data/02_processed/deltas/delta_halfdeg_tas_climatology_ncdf4.nc")*1,
     "dtr" = rast("/home/dafcluster4/Documents/GitHub/TraCE_Sahul/02_data/02_processed/deltas/delta_halfdeg_dtr_climatology_ncdf4.nc")*1)
deltas <- lapply(deltas, function(i) project(i, template, "cubicspline"))
deltas

sapply(deltas, panel)

# create relative humidity data
huss <- rast("/media/dafcluster4/storage/TraCE_Monthly_halfDeg/RELHUM/trace.01-36.22000BP-1990CE.cam2.h0.RELHUM.0000101-2204012.Sahul.concat.1900_1989CE.nc",
             "RELHUM")
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
         unit = "percent", zname = "time", prec = "float")

# create precipitation data
pr <- rast("/media/dafcluster4/storage/TraCE_Monthly_halfDeg/PRECC/trace.01-36.22000BP-1990CE.cam2.h0.PRECC.0000101-2204012.Sahul.concat.1900_1989CE.nc",
           "PRECC") +
  rast("/media/dafcluster4/storage/TraCE_Monthly_halfDeg/PRECL/trace.01-36.22000BP-1990CE.cam2.h0.PRECL.0000101-2204012.Sahul.concat.1900_1989CE.nc",
       "PRECL")
time(pr) <- time(huss)
units(pr) <- "kg/m2/s"
varnames(pr) <- "rainfall"
names(pr) <- format(time(pr), "%b%Y")
crs(pr) <- "EPSG:4326"
pr <- pr * deltas$pr # bias correct
pr
panel(pr[[seq(1, 1080, l = 6)]]*86400, range = c(0, 12), fill_range = TRUE)
pr <- ifel(pr < 0, 0, pr)
writeCDF(pr, "02_data/02_processed/pr.nc",
         varname = "pr", longname = "precipitation",
         overwrite = TRUE,
         unit = "kg/m2/s", zname = "time", prec = "float")

# create ta_high
ta_high <- rast("/media/dafcluster4/storage/TraCE_Monthly_halfDeg/T/trace.01-36.22000BP-1990CE.cam2.h0.T.0000101-2204012.Sahul.concat.1900_1989CE.nc",
                "T")
## need TA @ [z=20]
ta_ind <- round(as.numeric(sapply(strsplit(names(ta_high), "=|_"), "[", 3)))
ta_ind <- which(ta_ind == 601)
ta_high <- ta_high[[ta_ind]]
time(ta_high) <- time(huss)
units(ta_high) <- "K"
varnames(ta_high) <- "Temperature"
names(ta_high) <- format(time(ta_high), "%b%Y")
crs(ta_high) <- "EPSG:4326"
depth(ta_high) <- NULL
ta_high
writeCDF(ta_high, "02_data/02_processed/ta_high.nc", varname = "T",
         longname = "T (TA_High)", overwrite = TRUE, unit = "K", zname = "time",
         prec = "float")

# create ta_low
ta_low <- rast("/media/dafcluster4/storage/TraCE_Monthly_halfDeg/T/trace.01-36.22000BP-1990CE.cam2.h0.T.0000101-2204012.Sahul.concat.1900_1989CE.nc",
               "T")
## need TA @ z=26
ta_ind <- round(as.numeric(sapply(strsplit(names(ta_low), "=|_"), "[", 3)))
ta_ind <- which(ta_ind == 993)
ta_low <- ta_low[[ta_ind]]
time(ta_low) <- time(huss)
units(ta_low) <- "K"
varnames(ta_low) <- "Temperature"
names(ta_low) <- format(time(ta_low), "%b%Y")
crs(ta_low) <- "EPSG:4326"
depth(ta_low) <- NULL
ta_low

# should all be positive
plot(ta_low[[1]] - ta_high[[1]], fun = function() lines(land, col = "#FFFFFF"))
writeCDF(ta_low, "02_data/02_processed/ta_low.nc",
         varname = "T", longname = "T (TA_low)",
         overwrite = TRUE,
         unit = "K", zname = "time", prec = "float")

# create tas
tsmx <- rast("/media/dafcluster4/storage/TraCE_Monthly_halfDeg/TSMX/trace.01-36.22000BP-1990CE.cam2.h0.TSMX.0000101-2204012.Sahul.concat.1900_1989CE.nc", "TSMX")
tsmn <- rast("/media/dafcluster4/storage/TraCE_Monthly_halfDeg/TSMN/trace.01-36.22000BP-1990CE.cam2.h0.TSMN.0000101-2204012.Sahul.concat.1900_1989CE.nc", "TSMN")
tas <- (0.5 * (tsmx + tsmn)) + deltas$tas
dtr <- (tsmx - tsmn) * deltas$dtr
time(tas) <- time(dtr) <- time(huss)
tas
dtr

# # per-cell climatological max dtr from 1980 onwards, used as floor
# dtr_med <- tapp(dtr[[which(time(dtr) >= as.Date("1980-01-16"))]], "month", median)
#
# # replicate dtr_med to match the full time dimension of dtr
# n_years <- nlyr(dtr) / 12
# dtr_floor <- rep(dtr_med, n_years)
# time(dtr_floor) <- time(dtr)
# dtr_floor
#
# nlyr(dtr) == nlyr(dtr_floor)
#
# # enforce floor in one vectorised pass
# dtr <- max(dtr, dtr_floor)
# dtr

# tas
units(tas) <- "K"
varnames(tas) <- "Temperature"
longnames(tas) <- "mean temperature at surface"
names(tas) <- format(time(tas), "%b%Y")
crs(tas) <- "EPSG:4326"
tas
writeCDF(tas, "02_data/02_processed/tas.nc", varname = "tas",
         longname = "Mean Temperature", overwrite = TRUE, unit = "K",
         zname = "time", prec = "float")

# new tasmax
tasmax <- tas + (0.5 * dtr)
time(tasmax) <- time(huss)
units(tasmax) <- "K"
varnames(tasmax) <- "Temperature"
longnames(tasmax) <- "max temperature at surface"
names(tasmax) <- format(time(tasmax), "%b%Y")
crs(tasmax) <- "EPSG:4326"
tasmax

# new tasmin
tasmin <- tas - (0.5 * dtr)
time(tasmin) <- time(huss)
units(tasmin) <- "K"
varnames(tasmin) <- "Temperature"
names(tasmin) <- format(time(tasmin), "%b%Y")
crs(tasmin) <- "EPSG:4326"
tasmin

# check for neg dtr and write
sum(tasmax < tasmin)
writeCDF(tasmax, "02_data/02_processed/tasmax.nc", varname = "tasmax",
         longname = "Maximum Temperature", overwrite = TRUE, unit = "K",
         zname = "time", prec = "float")
writeCDF(tasmin, "02_data/02_processed/tasmin.nc", varname = "tasmin",
         longname = "Minimum Temperature", overwrite = TRUE, unit = "K",
         zname = "time", prec = "float")

# create uwind
uwind <- rast("/media/dafcluster4/storage/TraCE_Monthly_halfDeg/U/trace.01-36.22000BP-1990CE.cam2.h0.U.0000101-2204012.Sahul.concat.1900_1989CE.nc",
              "U")
time(uwind) <- time(huss)
units(uwind) <- "m/s"
varnames(uwind) <- "Zonal wind"
names(uwind) <- format(time(uwind), "%b%Y")
crs(uwind) <- "EPSG:4326"
uwind
writeCDF(uwind, "02_data/02_processed/uwind.nc", varname = "U",
         longname = "Zonal wind", overwrite = TRUE, unit = "m/s",
         zname = "time", prec = "float")

# create vwind
vwind <- rast("/media/dafcluster4/storage/TraCE_Monthly_halfDeg/V/trace.01-36.22000BP-1990CE.cam2.h0.V.0000101-2204012.Sahul.concat.1900_1989CE.nc",
              "V")
time(vwind) <- time(huss)
units(vwind) <- "m/s"
varnames(vwind) <- "Meridional wind"
names(vwind) <- format(time(vwind), "%b%Y")
crs(vwind) <- "EPSG:4326"
vwind
writeCDF(vwind, "02_data/02_processed/vwind.nc", varname = "V",
         longname = "Meridional wind", overwrite = TRUE, unit = "m/s",
         zname = "time", prec = "float")

# create zg_high
zg_high <- rast("/media/dafcluster4/storage/TraCE_Monthly_halfDeg/Z3/trace.01-36.22000BP-1990CE.cam2.h0.Z3.0000101-2204012.Sahul.concat.1900_1989CE.nc",
                "Z3")
## need zg @ [z=20]
zg_high_ind <- round(as.numeric(sapply(strsplit(names(zg_high), "=|_"), "[", 3)))
zg_high_ind <- which(zg_high_ind == 601)
zg_high <- zg_high[[zg_high_ind]]
time(zg_high) <- time(huss)
units(zg_high) <- "m"
varnames(zg_high) <- "Geopotential Height (above sea level)"
names(zg_high) <- format(time(zg_high), "%b%Y")
crs(zg_high) <- "EPSG:4326"
depth(zg_high) <- NULL
zg_high
writeCDF(zg_high, "02_data/02_processed/zg_high.nc", varname = "z3",
         longname = "Geopotential Height", overwrite = TRUE, unit = "m",
         zname = "time", prec = "float")

# create zg_low
zg_low <- rast("/media/dafcluster4/storage/TraCE_Monthly_halfDeg/Z3/trace.01-36.22000BP-1990CE.cam2.h0.Z3.0000101-2204012.Sahul.concat.1900_1989CE.nc",
               "Z3")
## need zg @z=26
zg_low_ind <- round(as.numeric(sapply(strsplit(names(zg_low), "=|_"), "[", 3)))
zg_low_ind <- which(zg_low_ind == 993)
zg_low <- zg_low[[zg_low_ind]]
time(zg_low) <- time(huss)
units(zg_low) <- "m"
varnames(zg_low) <- "Geopotential Height (above sea level)"
names(zg_low) <- format(time(zg_low), "%b%Y")
crs(zg_low) <- "EPSG:4326"
depth(zg_low) <- NULL
zg_low
minmax(zg_low[[1:6]] - zg_high[[1:6]]) # should all be negative
writeCDF(zg_low, "02_data/02_processed/zg_low.nc", varname = "z3",
         longname = "Geopotential Height", overwrite = TRUE, unit = "m",
         zname = "time", prec = "float")

# quick lapse rate
# l = tl-th/zh-zl
(ta_low[[1:6]] - ta_high[[1:6]]) / (zg_high[[1:6]] - zg_low[[1:6]])
panel((ta_low[[1:6]] - ta_high[[1:6]]) / (zg_high[[1:6]] - zg_low[[1:6]]),
     fun = function() lines(land), range = c(0, 0.008), fill_range = TRUE)

# Create oro
oro <- rast("02_data/01_inputs/TraCE21_elevation_1450CE_1950CE_halfDeg.nc") * 1
oro

col_pal <- c("#08306B","#08519C","#2171B5","#4292C6","#6BAED6","#9ECAE1","#006400",
             "#228B22","#ADDEAD","#F4EBC1","#D9A066")
plot(oro,
     col = col_pal,
     breaks = c(-9000, -4000, -2000, -1000, -500, -100, 0, 100, 500, 1500,
                2000, 4000),
     fun = function() lines(land, col = "#000000", lwd = 1.5))
time(oro) <- as.Date("1950-06-16")
units(oro) <- "m"
varnames(oro) <- "Orographic elevation"
names(oro) <- format(time(oro), "%b%Y")
crs(oro) <- "EPSG:4326"
oro
writeCDF(oro, "02_data/02_processed/oro.nc", varname = "elevation",
         longname = "Orographic elevation", overwrite = TRUE, unit = "m",
         zname = "time", prec = "float")

# Create oro_high
land <- vect(rnaturalearthhires::countries10)

# oro_high <- rast("raw/Sahul_contemporary_elev.nc")
in_oro <- list.files("/mnt/Data/CHELSA_Trace21/Input",
                     full.names = TRUE, pattern = ".tif")
# match to timesteps for 1600 onwards (https://chelsa-climate.org/chelsa-trace21k/)
pattern <- "CHELSA_TraCE21k_dem_(16|17|18|19|20)_V1\\.0\\.tif$"
in_oro <- grep(pattern, in_oro, value = TRUE)
oro_high <- rast(lapply(in_oro, function(x) rast(x, win = ext(template))))
oro_high

oro_high_check <- oro_high
oro_high_check <- ifel(!is.na(oro_high_check), 1, 0)
oro_high_check <- app(oro_high_check, sum, na.rm = TRUE)
oro_high_check
length(unique(values(oro_high_check))) == 2 # all are 0/5
plot(oro_high_check) # 0/5 == no change in land/sea mask
oro_high <- oro_high[[5]]
plot(oro_high,
     col = col_pal,
     breaks = c(-6000, -4000, -2000, -1000, -500, -100, 0, 100, 500,
                1500, 2000, 4000),
     fun = function() lines(land, col = "#000000", lwd = 1.5))

# mean aggregation to ~5km grid
tmp_rst <- rast(
  res = 0.05, extent = ext(oro),
  crs = "EPSG:4326")
tmp_rst
oro_5 <- project(oro_high[[1]], tmp_rst,
                 method = "average",
                 use_gdal = TRUE)
oro_5 <- mask(oro_5, land, touches = TRUE)
plot(oro_5,
     col = col_pal,
     breaks = c(-6000, -4000, -2000, -1000, -500, -100, 0, 100, 500,
                1500, 2000, 4000),
     fun = function() lines(land, col = "#000000", lwd = 1.5))
oro_5 <- setValues(oro_5, round(values(oro_5), 3))
units(oro_5) <- "m"
varnames(oro_5) <- "Orographic elevation"
crs(oro_5) <- "EPSG:4326"
oro_5

writeCDF(oro_5,
         "02_data/02_processed/oro_high.nc",
         varname = "elevation", longname = "Orographic elevation",
         unit = "m", prec = "float", compression = 1,
         missval = NA, overwrite = TRUE)

# merc_template
template_raster <- rast(
  extent = ext(oro_5),
  crs = "EPSG:4326",
  resolution = res(oro_5),
  vals = 1L)
sahul_prj <- "EPSG:3395"
template_raster <- project(template_raster, sahul_prj,
                           method = "near",
                           res = 4000)
template_raster
plot(template_raster, fun = function() lines(project(land, template_raster)))
merc_template <- project(oro_5,
                         template_raster,
                         # threads = 12,
                         use_gdal = TRUE,
                         method = "average")
merc_template
plot(merc_template,
     col = col_pal,
     breaks = c(-6000, -4000, -2000, -1000, -500, -100, 0, 100, 500,
                1500, 2000, 4000),
     fun = function() lines(project(land, merc_template),
                            col = "#000000", lwd = 1.5))
writeCDF(merc_template,
         "02_data/02_processed/merc_template.nc",
         varname = "elevation", longname = "Orographic elevation",
         unit = "m", prec = "float", compression = 1,
         missval = NA, overwrite = TRUE)
