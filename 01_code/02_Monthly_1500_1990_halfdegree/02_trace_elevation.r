library(terra)
# library(enmSdmX)

land <- vect(rnaturalearthhires::countries10)
land <- crop(land, ext(105.0, 161.25, -52.5, 11.25))
land <- aggregate(land)
plot(land)

template <- rast("02_data/trace_to_sahul_half_degree_bilin.nc")
template

# Keep bathy
elev <- rast("/media/dafcluster4/storage/Ice5g/ice5g_v1.2_00.0k_10min.nc", "orog")
elev <- crop(rotate(elev), ext(template), snap = "out")
elev
plot(elev, fun = function() lines(land))

elev_coarse <- project(elev, template, "average")
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