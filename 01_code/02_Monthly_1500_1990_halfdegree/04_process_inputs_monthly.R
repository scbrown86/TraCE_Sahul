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

base_loc <- "/media/dafcluster4/storage/TraCE_Monthly_halfDeg"

# load in the deltas
deltas <- list(
     "pr" = rast("02_data/02_processed/deltas/delta_halfdeg_pr_climatology_ncdf4.nc")*1,
     "tas" = rast("02_data/02_processed/deltas/delta_halfdeg_tas_climatology_ncdf4.nc")*1,
     "dtr" = rast("02_data/02_processed/deltas/delta_halfdeg_dtr_climatology_ncdf4.nc")*1)
deltas <- lapply(deltas, function(i) project(i, template, "bilinear"))
deltas

sapply(deltas, panel)

# create relative humidity data
huss <- rast(file.path(base_loc, "RELHUM/trace.01-36.22000BP-1990CE.cam2.h0.RELHUM.0000101-2204012.Sahul.concat.1500_1989CE.nc"),
             "RELHUM")
time(huss) <- rev(seq(as.Date("1989-12-16"), by = "-1 months", l = nlyr(huss)))
units(huss) <- "percent"
varnames(huss) <- "RELHUM (Relative humidity)"
names(huss) <- format(time(huss), "%b%Y")
crs(huss) <- "EPSG:4326"
setMinMax(huss)
range(minmax(huss))
huss
writeCDF(huss, "02_data/02_processed/huss.nc",
         varname = "relhum",
         longname = "RELHUM (Relative humidity)",
         overwrite = TRUE,
         unit = "percent", zname = "time", prec = "float")

# create precipitation data
pr <- rast(file.path(base_loc, "PRECC/trace.01-36.22000BP-1990CE.cam2.h0.PRECC.0000101-2204012.Sahul.concat.1500_1989CE.nc"),
           "PRECC") +
  rast(file.path(base_loc, "PRECL/trace.01-36.22000BP-1990CE.cam2.h0.PRECL.0000101-2204012.Sahul.concat.1500_1989CE.nc"),
       "PRECL")
time(pr) <- time(huss)
units(pr) <- "kg/m2/s"
varnames(pr) <- "rainfall"
names(pr) <- format(time(pr), "%b%Y")
crs(pr) <- "EPSG:4326"
pr <- pr * deltas$pr # bias correct
pr
range(minmax(pr))*86400
precip_min <- 0.1 / 86400  # 0.1 mm/day in kg m-2 s-1
pr <- ifel(pr < precip_min, precip_min, pr)
pr
panel(pr[[floor(seq(1, nlyr(pr), l = 6))]]*86400, range = c(0, 12), fill_range = TRUE)
writeCDF(pr, "02_data/02_processed/pr.nc",
         varname = "pr", longname = "precipitation",
         overwrite = TRUE,
         unit = "kg/m2/s", zname = "time", prec = "float")

# create ta_high
ta_high <- rast(file.path(base_loc, "T/trace.01-36.22000BP-1990CE.cam2.h0.T.0000101-2204012.Sahul.concat.1500_1989CE.nc"),
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
ta_low <- rast(file.path(base_loc, "T/trace.01-36.22000BP-1990CE.cam2.h0.T.0000101-2204012.Sahul.concat.1500_1989CE.nc"),
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
tsmx <- rast(file.path(base_loc, "TSMX/trace.01-36.22000BP-1990CE.cam2.h0.TSMX.0000101-2204012.Sahul.concat.1500_1989CE.nc"),
             "TSMX")
tsmn <- rast(file.path(base_loc, "TSMN/trace.01-36.22000BP-1990CE.cam2.h0.TSMN.0000101-2204012.Sahul.concat.1500_1989CE.nc"),
             "TSMN")
tas <- (0.5 * (tsmx + tsmn)) + deltas$tas
dtr <- (tsmx - tsmn) * deltas$dtr
time(tas) <- time(dtr) <- time(huss)
tas
dtr

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
uwind <- rast(file.path(base_loc, "U/trace.01-36.22000BP-1990CE.cam2.h0.U.0000101-2204012.Sahul.concat.1500_1989CE.nc"),
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
vwind <- rast(file.path(base_loc, "V/trace.01-36.22000BP-1990CE.cam2.h0.V.0000101-2204012.Sahul.concat.1500_1989CE.nc"),
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
zg_high <- rast(file.path(base_loc, "Z3/trace.01-36.22000BP-1990CE.cam2.h0.Z3.0000101-2204012.Sahul.concat.1500_1989CE.nc"),
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
zg_low <- rast(file.path(base_loc, "Z3/trace.01-36.22000BP-1990CE.cam2.h0.Z3.0000101-2204012.Sahul.concat.1500_1989CE.nc"),
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
     fun = function() lines(land), range = c(0.003, 0.005), fill_range = TRUE)

# Create oro
oro <- rast("02_data/01_inputs/TraCE21_elevation_22kaBP_1500CE_withBathy.tif")
oro <- oro[[nlyr(oro)]] # data from 1500
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
time(oro) <- as.Date("1500-01-16")
units(oro) <- "m"
varnames(oro) <- "Orographic elevation"
names(oro) <- format(time(oro), "%b%Y")
crs(oro) <- "EPSG:4326"
oro
plot(oro, col = col_pal,
     type = "interval",
     breaks = c(-9000, -2000, -1000, -500, -100, -1, 0,
                10, 25, 50, 100, 200, 500, 1000, 1500, 3000),
     fun = function() lines(land, col = "#000000", lwd = 1.5))
writeCDF(oro, "02_data/02_processed/oro.nc", varname = "elevation",
         longname = "Orographic elevation", overwrite = TRUE, unit = "m",
         zname = "time", prec = "float")

# Create oro_high
land <- vect(rnaturalearthhires::countries10)

# oro_high <- rast("raw/Sahul_contemporary_elev.nc")
in_oro <- list.files("/mnt/Data/CHELSA_Trace21/Input",
                     full.names = TRUE, pattern = ".tif")
# match to timesteps for 1600 onwards (https://chelsa-climate.org/chelsa-trace21k/)
pattern <- "CHELSA_TraCE21k_dem_(20)_V1\\.0\\.tif$"
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
blended_land <- ifel(oro_high > 0, oro_high, bathy)
plot(blended_land > 0)
blended <- ifel(bathy < 0, bathy, oro_high)
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
oro_mask <- project(blended_land > 0, tmp_rst,
                    method = "mode", use_gdal = TRUE)
oro_mask <- ifel(oro_mask == 0, NA_integer_, 1L)
plot(oro_mask, fun = function() lines(land))
writeRaster(oro_mask, "02_data/02_processed/oro_mask.tif",
            overwrite = TRUE)

oro_5 <- project(blended, tmp_rst,
                 method = "average", use_gdal = TRUE)

plot(oro_5,
     col = col_pal,
     type = "interval",
     breaks = c(-9000, -2000, -1000, -500, -100, -1, 0,
                10, 25, 50, 100, 200, 500, 1000, 1500, 3000),
     fun = function() lines(land, col = "#000000", lwd = 1.5))

oro_5 <- setValues(oro_5, round(values(oro_5), 0)) # round to nearest metre
units(oro_5) <- "m"
varnames(oro_5) <- "Orographic elevation"
crs(oro_5) <- "EPSG:4326"
oro_5 <- ifel(oro_5 < 0, 0, oro_5)
oro_5
plot(oro_5,
     col = col_pal,
     type = "interval",
     breaks = c(-9000, -2000, -1000, -500, -100, -1, 0,
                10, 25, 50, 100, 200, 500, 1000, 1500, 3000),
     fun = function() lines(land, col = "#000000", lwd = 1.5))

writeCDF(oro_5,
         "02_data/02_processed/oro_high.nc",
         varname = "elevation", longname = "Orographic elevation",
         unit = "m", prec = "float", compression = 1,
         missval = NA, overwrite = TRUE)

oro_5 <- rast("02_data/02_processed/oro_high.nc")
plot(oro_5,
     col = col_pal,
     type = "interval",
     breaks = c(-9000, -2000, -1000, -500, -100, -1, 0,
                10, 25, 50, 100, 200, 500, 1000, 1500, 3000),
     fun = function() lines(land, col = "#000000", lwd = 1.5))


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
                         use_gdal = TRUE,
                         method = "average")
merc_template
plot(merc_template,
     col = col_pal,
     type = "interval",
     breaks = c(-9000, -2000, -1000, -500, -100, -1, 0,
                10, 25, 50, 100, 200, 500, 1000, 1500, 3000),
     fun = function() lines(project(land, merc_template), col = "#000000", lwd = 1.5))
writeCDF(merc_template,
         "02_data/02_processed/merc_template.nc",
         varname = "elevation", longname = "Orographic elevation",
         unit = "m", prec = "float", compression = 1,
         missval = NA, overwrite = TRUE)
