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

setwd("/home/dafcluster4/Documents/GitHub/TraCE_Sahul")

# create relative humidity data
huss <- rast("/media/dafcluster4/storage/TraCE_Monthly/RELHUM/trace.01-36.22000BP-1990CE.cam2.h0.RELHUM.0000101-2204012.Sahul.concat.1500_1989CE.nc",
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
pr <- rast("/media/dafcluster4/storage/TraCE_Monthly/PRECC/trace.01-36.22000BP-1990CE.cam2.h0.PRECC.0000101-2204012.Sahul.concat.1500_1989CE.nc",
           "PRECC") +
  rast("/media/dafcluster4/storage/TraCE_Monthly/PRECL/trace.01-36.22000BP-1990CE.cam2.h0.PRECL.0000101-2204012.Sahul.concat.1500_1989CE.nc",
       "PRECL")
time(pr) <- time(huss)
units(pr) <- "kg/m2/s"
varnames(pr) <- "rainfall"
names(pr) <- format(time(pr), "%b%Y")
crs(pr) <- "EPSG:4326"
pr
writeCDF(pr, "02_data/02_processed/pr.nc",
         varname = "pr", longname = "precipitation",
         overwrite = TRUE,
         unit = "kg/m2/s", zname = "time", prec = "float")

# create ta_high
ta_high <- rast("/media/dafcluster4/storage/TraCE_Monthly/T/trace.01-36.22000BP-1990CE.cam2.h0.T.0000101-2204012.Sahul.concat.1500_1989CE.nc",
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
ta_low <- rast("/media/dafcluster4/storage/TraCE_Monthly/T/trace.01-36.22000BP-1990CE.cam2.h0.T.0000101-2204012.Sahul.concat.1500_1989CE.nc",
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

# create tasmax
tasmax <- rast("/media/dafcluster4/storage/TraCE_Monthly/TSMX/trace.01-36.22000BP-1990CE.cam2.h0.TSMX.0000101-2204012.Sahul.concat.1500_1989CE.nc",
               "TSMX")
time(tasmax) <- time(huss)
units(tasmax) <- "K"
varnames(tasmax) <- "Temperature"
names(tasmax) <- format(time(tasmax), "%b%Y")
crs(tasmax) <- "EPSG:4326"
tasmax
writeCDF(tasmax, "02_data/02_processed/tasmax.nc", varname = "tasmax", 
         longname = "Maximum Temperature", overwrite = TRUE, unit = "K", 
         zname = "time", prec = "float")

# create tasmin
tasmin <- rast("/media/dafcluster4/storage/TraCE_Monthly/TSMN/trace.01-36.22000BP-1990CE.cam2.h0.TSMN.0000101-2204012.Sahul.concat.1500_1989CE.nc",
               "TSMN")
time(tasmin) <- time(huss)
units(tasmin) <- "K"
varnames(tasmin) <- "Temperature"
names(tasmin) <- format(time(tasmin), "%b%Y")
crs(tasmin) <- "EPSG:4326"
tasmin
writeCDF(tasmin, "02_data/02_processed/tasmin.nc", varname = "tasmin", 
         longname = "Minimum Temperature", overwrite = TRUE, unit = "K", 
         zname = "time", prec = "float")

# create tas
tas <- rast("/media/dafcluster4/storage/TraCE_Monthly/TS/trace.01-36.22000BP-1990CE.cam2.h0.TS.0000101-2204012.Sahul.concat.1500_1989CE.nc",
            "TS")
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
writeCDF(tas, "02_data/02_processed/tas.nc", varname = "tas", 
         longname = "Mean Temperature", overwrite = TRUE, unit = "K", 
         zname = "time", prec = "float")

# create uwind
uwind <- rast("/media/dafcluster4/storage/TraCE_Monthly/U/trace.01-36.22000BP-1990CE.cam2.h0.U.0000101-2204012.Sahul.concat.1500_1989CE.nc",
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
vwind <- rast("/media/dafcluster4/storage/TraCE_Monthly/V/trace.01-36.22000BP-1990CE.cam2.h0.V.0000101-2204012.Sahul.concat.1500_1989CE.nc",
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
zg_high <- rast("/media/dafcluster4/storage/TraCE_Monthly/Z3/trace.01-36.22000BP-1990CE.cam2.h0.Z3.0000101-2204012.Sahul.concat.1500_1989CE.nc",
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
zg_low <- rast("/media/dafcluster4/storage/TraCE_Monthly/Z3/trace.01-36.22000BP-1990CE.cam2.h0.Z3.0000101-2204012.Sahul.concat.1500_1989CE.nc",
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
zg_low[[1:6]] - zg_high[[1:6]] # should all be negative
writeCDF(zg_low, "02_data/02_processed/zg_low.nc", varname = "z3", 
         longname = "Geopotential Height", overwrite = TRUE, unit = "m", 
         zname = "time", prec = "float")

# quick lapse rate
# l = tl-th/zh-zl
(ta_low[[1:6]] - ta_high[[1:6]]) / (zg_high[[1:6]] - zg_low[[1:6]])
plot((ta_low[[1:6]] - ta_high[[1:6]]) / (zg_high[[1:6]] - zg_low[[1:6]]), 
     fun = function() lines(land), range = c(0, 0.008), fill_range = TRUE)

# Create oro
oro <- rast("02_data/01_inputs/TraCE21_elevation.nc") * 1
oro

col_pal <- c("#08306B","#08519C","#2171B5","#4292C6","#6BAED6","#9ECAE1","#006400",
             "#228B22","#ADDEAD","#F4EBC1","#D9A066")
plot(oro,
     col = col_pal,
     breaks = c(-6000, -4000, -2000, -1000, -500, -100, 0, 100, 500, 1500, 
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
oro_4 <- project(oro_high[[1]], tmp_rst,
                 method = "average",
                 use_gdal = TRUE)
oro_4 <- mask(oro_4, land, touches = TRUE)
plot(oro_4,
     col = col_pal,
     breaks = c(-6000, -4000, -2000, -1000, -500, -100, 0, 100, 500, 
                1500, 2000, 4000),
     fun = function() lines(land, col = "#000000", lwd = 1.5))
oro_4 <- setValues(oro_4, round(values(oro_4), 3))
units(oro_4) <- "m"
varnames(oro_4) <- "Orographic elevation"
crs(oro_4) <- "EPSG:4326"
oro_4

writeCDF(oro_4,
         "02_data/02_processed/oro_high.nc",
         varname = "elevation", longname = "Orographic elevation",
         unit = "m", prec = "float", compression = 1,
         missval = NA, overwrite = TRUE)

# merc_template
template_raster <- rast(
  extent = ext(oro_4),
  crs = "EPSG:4326",
  resolution = res(oro_4),
  vals = 1L)
sahul_prj <- "EPSG:3395"
template_raster <- project(template_raster, sahul_prj,
                           method = "near",
                           res = 4000)
template_raster
plot(template_raster, fun = function() lines(project(land, template_raster)))
merc_template <- project(oro_4,
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