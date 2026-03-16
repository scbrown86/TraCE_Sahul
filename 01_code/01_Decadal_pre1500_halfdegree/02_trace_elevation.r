library(terra)
library(data.table)
library(enmSdmX)
library(pbapply)
library(ncdf4)

land <- vect(rnaturalearthhires::countries10)
land <- crop(land, ext(105.0, 161.25, -52.5, 11.25))
land <- aggregate(land)
plot(land)

template <- rast("02_data/trace_to_sahul_half_degree_bilin.nc")
template

template_05 <- disagg(template, 10)
template_05

# Elev from Karget et al
time_steps <- data.table("timeID" = seq(20, -200, by = -1),
                         "startyear" = seq(1900, -20100, by = -100),
                         "endyear" = c(1990, seq(1899, -20001, l = 220)),
                         "BP" = seq(0, by = 0.1, l = 221)*1000)
time_steps

# read in elev from 1500 C.E backwards to 21 ka BP
# already resampled to 0.5° with GDAL
elev <- rast("02_data/01_inputs/TraCE21_coarse_orog_bathy.tif")
elev <- c(elev[[1]], elev)
time(elev) <- c(450, as.integer(time_steps[startyear < 1500, ][["BP"]]))
elev

# 5 ocean + 10 land = 15 colours for 15 intervals
col_pal <- c(
  "#08306B", "#2171B5", "#4292C6", "#6BAED6", "#9ECAE1",
  "#006400", "#228B22", "#56A83A", "#8CC56A", "#ADDE9E",
  "#F4EBC1", "#E8D5A3", "#D9A066", "#C47A3A", "#A0522D")

panel(elev[[floor(seq(1, nlyr(elev), l = 4))]],
      col = col_pal,
      type = "interval",
      breaks = c(-9000, -2000, -1000, -500, -100, -1, 0,
                 10, 25, 50, 100, 200, 500, 1000, 1500, 3000),
      fun = function() lines(land, col = "#000000", lwd = 1.5))

elev_interp <- enmSdmX::interpolateRasts(rasts = elev,
                                         interpFrom = time(elev),
                                         interpTo = seq(min(time(elev)),
                                                        max(time(elev)),
                                                        by = 10),
                                         type = "linear",
                                         verbose = TRUE)
time(elev_interp) <- seq(min(time(elev)), max(time(elev)), by = 10)
names(elev_interp) <- paste0(time(elev_interp), "BP")
units(elev_interp) <- "m"
varnames(elev_interp) <- "elevation"
depth(elev_interp) <- rcarbon::BPtoBCAD(time(elev_interp))
depthName(elev_interp) <- "yearsCE"
depthUnit(elev_interp) <- "years"
elev_interp <- setValues(elev_interp, round(values(elev_interp)))
elev_interp <- elev_interp[[rev(1:nlyr(elev_interp))]]
time(elev_interp) <- rev(time(elev_interp))
elev_interp # 2156 layers from 22 ka to 1500CE

panel(elev_interp[[floor(seq(1, nlyr(elev_interp), l = 6))]],
      col = col_pal,
      type = "interval",
      breaks = c(-9000, -2000, -1000, -500, -100, -1, 0,
                 10, 25, 50, 100, 200, 500, 1000, 1500, 3000),
      fun = function() lines(land, col = "#000000", lwd = 1.5))


writeRaster(elev_interp, "02_data/01_inputs/TraCE21_elevation_22kaBP_1500CE_withBathy.tif",
            overwrite = TRUE,
            gdal = c("COMPRESS=LZW", "PREDICTOR=2"), datatype = "INT2S")
depth(elev_interp) <- NULL
elev_interp

writeCDF(elev_interp, "02_data/01_inputs/TraCE21_elevation_22kaBP_1500CE_withBathy.nc",
         varname = "elevation", longname = "elevation",
         prec = "short",
         unit = "m", compression = 1, overwrite = TRUE)

# High res DEM to be interpolated
idx <- which(time_steps[["startyear"]] < 1500) # want pre-1500
fils <- gtools::mixedsort(list.files("/mnt/Data/CHELSA_Trace21/Input",
                                     pattern = "dem_-?\\d+_V1\\.0\\.tif$",
                                     recursive = FALSE,
                                     full.names = TRUE),
                          decreasing = TRUE)[idx]
fils
topo <- rast(lapply(fils, function(i) rast(i, win = ext(template), snap = "out")))
topo
time(topo) <- as.integer(time_steps[idx, ][["BP"]])
topo
topo
bathy <- rast("~/Documents/GEBCO_2014_2D_Sahul.nc") # single layer, contemporary
bathy <- project(bathy, topo, "bilinear")
compareGeom(topo, bathy)

nrow(time_steps[idx, ])

# Sea level table from Karget et al tech info
## need to reverse order of rows
sea_level <- setorder(readRDS("02_data/Table5_Karger_Supp.RDS"),
                      -timeID)[-1, ]
sea_level[, timeID := time_steps[["timeID"]]]
sea_level

# subset both to timesteps in topo
time_steps <- copy(time_steps)[idx, ]
time_steps
sea_level <- copy(sea_level)[which(timeID %in% time_steps[["timeID"]]), ]
sea_level

stopifnot(nrow(time_steps) == nrow(sea_level))
stopifnot(nrow(time_steps) == nlyr(topo))

# iterate through, adjust sea level and blend
blended_topo_bath <- pblapply(seq_len(nrow(time_steps)), function(i) {
  tid <- time_steps[i, ][["timeID"]]
  sl_row <- copy(sea_level)[sea_level$timeID == tid, ]
  if (nrow(sl_row) == 0) {
    warning(paste("No sea level entry for timeID", tid, "- skipping"),
            immediate. = TRUE)
    return(NULL)
  }
  sl_offset <- sl_row[["sealevel"]]
  # Adjust bathymetry: subtract the (negative) sea level offset
  # This raises the seafloor relative to contemporary datum.
  # At LGM (sl = -122.2), bathy cells shallower than 122.2m become "land"
  bathy_adj <- bathy - sl_offset
  # Select the correct topography layer for this timestep
  # Assumes layers in topo are ordered to match time_steps rows
  topo_layer <- topo[[i]]
  # Blend: use topo where it defines land (topo > 0), bathy_adj elsewhere
  # Where topo > 0, that cell is land regardless of bathy
  blended <- ifel(topo_layer > 0, topo_layer, bathy_adj)
  blended <- resample(blended, template_05, "average")
  # Set blended elevations to zero if less than zero
  blended <- ifel(blended < 0, 0, blended)
  blended <- setValues(blended, round(values(blended)))
  time(blended) <- time_steps[i, ][["BP"]]
  varnames(blended) <- "elevation"
  units(blended) <- "m"
  return(blended)
})
panel(c(blended_topo_bath[[216]],blended_topo_bath[[1]]),
      col = col_pal,
      type = "interval",
      breaks = c(-9000, -2000, -1000, -500, -100, -1, 0,
                 10, 25, 50, 100, 200, 500, 1000, 1500, 3000),
      fun = function() lines(land, col = "#000000", lwd = 1.5))
plot(c(blended_topo_bath[[216]],blended_topo_bath[[1]]) > 0,
      fun = function() lines(land, col = "#000000", lwd = 1.5))

blended <- rast(blended_topo_bath)
depth(blended) <- NULL
blended <- setValues(blended, round(values(blended)))
plot(sum(blended > 0))
panel(blended[[floor(seq(1, nlyr(blended), l = 6))]] > 0)

blended <- blended[[rev(1:nlyr(blended))]]
time(blended) <- rev(time(blended))
blended
panel(blended[[c(1, 216)]],
      col = col_pal,
      type = "interval",
      breaks = c(-9000, -2000, -1000, -500, -100, -1, 0,
                 10, 25, 50, 100, 200, 500, 1000, 1500, 3000),
      fun = function() lines(land, col = "#000000", lwd = 1.5))

# output elevation filename
filename <- "02_data/01_inputs/TraCE21_fine_elevation_22kaBP_1500CE_withBathy.nc"

# Longitude and Latitude data
xvals <- unique(values(init(blended, "x")))
yvals <- unique(values(init(blended, "y")))
nx <- length(xvals)
ny <- length(yvals)
lon <- ncdim_def("longitude", "degrees_east", xvals)
lat <- ncdim_def("latitude", "degrees_north", yvals)

# Missing value to use
mv <- -1

# Time component
time_vals <- seq(0, by = 365, length.out = nlyr(blended)) # 1 year step in days
time <- ncdim_def(name = "time",
                  units = "days since 1900-01-01",
                  vals = time_vals,
                  calendar = "365_day", ##<
                  unlim = TRUE,
                  longname = "time")

# Define the elevation variable
var_orog <- ncvar_def(name = "elevation",
                      units = "m",
                      dim = list(lon, lat, time),
                      longname = "Elevation",
                      missval = mv,
                      prec = "integer",
                      shuffle = TRUE,
                      chunksizes = c(113, 113, 1),
                      compression = 3)

# Add the variables to the file
ncout <- nc_create(filename, vars = var_orog, force_v4 = TRUE)
print(paste("The file has", ncout$nvars,"variables"))
print(paste("The file has", ncout$ndim,"dimensions"))

# add some global attributes
ncatt_put(ncout, 0, "Author", "Stuart C Brown")
ncatt_put(ncout, 0, "Affiliation", "Adelaide University")
ncatt_put(ncout, 0, "Sources", "Karger at al DEM's and GEBCO2014")
ncatt_put(ncout, 0, "Created on", date())
ncatt_put(ncout, 0, "Timesteps (BP)", as.character(as.vector(time(blended))))
ncatt_put(ncout, 0, "Timesteps (CE)", as.character(as.vector(rcarbon::BPtoBCAD(time(blended)))))
# Place the values in the file
for (i in 1:nlyr(blended)) {
  ncvar_put(nc = ncout,
            varid = var_orog,
            vals = values(blended[[i]]),
            start = c(1, 1, i),
            count = c(-1, -1, 1))
}
# Close the netcdf file when finished adding variables
nc_close(ncout)

orog_fine <- rast(filename, drivers = "NETCDF")
orog_fine

panel(orog_fine[[floor(seq(1, 216, l = 6))]],
      col = col_pal,
      type = "interval",
      breaks = c(-9000, -2000, -1000, -500, -100, -1, 0,
                 10, 25, 50, 100, 200, 500, 1000, 1500, 3000),
      fun = function() lines(land, col = "#000000", lwd = 1.5))

time(orog_fine)

# time interpolate with CDO
# file=02_data/01_inputs/TraCE21_fine_elevation_22kaBP_1500CE_withBathy.nc
# outfile=02_data/01_inputs/TraCE21_fine_elevation_22kaBP_1500CE_withBathy_inttime.nc
# cdo -P 100 -L -b I16 -f nc4 -z zip_3 -k grid intntime,10 $file $outfile

# check
timeinterp <- "02_data/01_inputs/TraCE21_fine_elevation_22kaBP_1500CE_withBathy_inttime.nc"
inter_orog <- rast(timeinterp)
inter_orog
panel(inter_orog[[floor(seq(1, nlyr(inter_orog), l = 6))]],
      col = col_pal,
      type = "interval",
      breaks = c(-9000, -2000, -1000, -500, -100, -1, 0,
                 10, 25, 50, 100, 200, 500, 1000, 1500, 3000),
      fun = function() lines(land, col = "#000000", lwd = 1.5))
