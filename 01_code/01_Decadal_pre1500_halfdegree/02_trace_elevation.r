library(terra)
library(data.table)
library(enmSdmX)

land <- vect(rnaturalearthhires::countries10)
land <- crop(land, ext(105.0, 161.25, -52.5, 11.25))
land <- aggregate(land)
plot(land)

template <- rast("02_data/trace_to_sahul_half_degree_bilin.nc")
template

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


