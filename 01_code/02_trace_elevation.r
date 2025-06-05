library(terra)

land <- vect(rnaturalearthhires::countries10)
land <- crop(land, ext(105.0, 161.25, -52.5, 11.25))
land <- aggregate(land)

template <- rast(extent = ext(-180, 180, -90, 90), res = 3.75, val = 1L)
template <- crop(template, ext(105, 161.25, -50, 10), snap = "out")
template

# Keep bathy
elev <- rast("/home/dafcluster4/Desktop/TraCE_Data/ice5g_v1.1_00.0k_1deg.nc", "orog")
elev <- crop(rotate(elev), ext(105.0, 161.25, -52.5, 11.25), snap = "out")
elev
plot(elev)

landmask <- rast("/home/dafcluster4/Desktop/TraCE_Data/raw/monthly/TraCE-21K.monthly.landmask.1700.1989.nc", "landsea")[[3480]]
landmask
landmask <- project(crop(rotate(landmask), ext(elev), snap = "out"), template, "near")
landmask <- ifel(is.na(landmask), 1, NA) # invert
landmask

landmask_fine <- project(landmask, elev, method = "near")
plot(landmask_fine)

plot(merge(
  mask(project(mask(elev, landmask_fine), landmask, "average"), landmask),
  mask(project(mask(elev, landmask_fine, inverse = TRUE), landmask, "average"),
    landmask,
    inverse = TRUE
  )
))

elev_coarse <- merge(
  mask(project(mask(elev, landmask_fine), landmask, "max"), landmask),
  mask(project(mask(elev, landmask_fine, inverse = TRUE), landmask, "average"),
    landmask,
    inverse = TRUE
  )
)
elev_coarse
plot(elev_coarse,
  breaks = c(-Inf, 0, Inf),
  fill_range = TRUE,
  fun = function() {
    lines(as.polygons(landmask), lwd = 1.5)
    lines(land)
  }
)

# writeCDF
writeCDF(elev_coarse, "./02_data/01_inputs/TraCE21_elevation.nc", varname = "elevation", longname = "elevation", unit = "m", compression = 1, overwrite = TRUE)
