library(terra)
# library(enmSdmX)

land <- vect(rnaturalearthhires::countries10)
land <- crop(land, ext(105.0, 161.25, -52.5, 11.25))
land <- aggregate(land)
plot(land)

template <- rast("02_data/trace_to_sahul_half_degree_bilin.nc")
template

# Timesteps from Karget et al
time_steps <- data.table("timeID" = seq(20, -200, by = -1),
                         "startyear" = seq(1900, -20100, by = -100),
                         "endyear" = c(1990, seq(1899, -20001, l = 220)),
                         "k BP" = seq(0, by = 0.1, l = 221))
time_steps

# read in elev for 1500 C.E (held constant after this)
elev <- rast(lapply(gtools::mixedsort(list.files("/mnt/Data/CHELSA_Trace21/Input/",
                                            pattern = "dem_-?\\d+_V1\\.0\\.tif$",
                                            full.names = TRUE),
                                 decreasing = TRUE)[which(time_steps[["startyear"]] == 1500)],
               function(i) rast(i, win = ext(template), snap = "out")))
time(elev) <- time_steps[startyear == 1500, ][["k BP"]]*1000
elev

# resample to 0.5°
elev_coarse <- resample(elev, template, "mean", threads = TRUE)
elev_coarse

# elev_coarse <- setValues(elev_coarse, round(values(elev_coarse), 1))
plot(elev_coarse,
     breaks = c(-Inf, 0, Inf),
     fill_range = TRUE,
     fun = function() lines(land))

plot(elev_coarse,
     range = c(-4000, 4000),
     fill_range = TRUE,
     col = hcl.colors(100, "Batlow"),
     fun = function() lines(land))

# writeCDF
names(elev_coarse) <- 1950
depth(elev_coarse) <- NULL
writeCDF(elev_coarse, "02_data/01_inputs/TraCE21_elevation_1450CE_1950CE_halfDeg.nc",
         varname = "elevation", longname = "elevation", unit = "m", 
         compression = 1, overwrite = TRUE)