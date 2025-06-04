library(terra)

land <- vect(rnaturalearthhires::countries10)
land <- crop(land, ext(105.0, 161.25, -52.5, 11.25))
land <- aggregate(land)

template <- rast(extent = ext(-180, 180, -90, 90), res = 3.75, val = 1L)
template <- crop(template, ext(105, 161.25, -50, 10), snap = "out")
template

# Keep bathy
elev <- rast("/home/dafcluster4/Desktop/TraCE_Data/ice5g_v1.1_00.0k_1deg.nc", "orog")
# elev <- rast("/mnt/Data/CHELSA_Trace21/Input/CHELSA_TraCE21k_dem_20_V1.0.tif")
elev <- crop(rotate(elev), ext(105.0, 161.25, -52.5, 11.25), snap = "out")
elev
# elev <- ifel(elev < 0, NA, elev)
plot(elev)

landmask <- rast("/home/dafcluster4/Desktop/TraCE_Data/raw/monthly/TraCE-21K.monthly.landmask.1700.1989.nc", "landsea")[[3480]]
landmask
landmask <- project(crop(rotate(landmask), ext(elev), snap = "out"), template, "near")
landmask <- ifel(is.na(landmask), 1, NA) # invert
landmask

# land_cells <- landmask
# values(land_cells) <- 1:ncell(land_cells)
# plot(landmask, fun = function() lines(land))
# text(land_cells)

# landmask[95] <- NA
# landmask[c(42, 74,75,92,93,59,232,208)] <- 1

# plot(landmask, fun = function() lines(land))
# text(land_cells)

landmask_fine <- project(landmask, elev, method = "near")
plot(landmask_fine)

# elev_fill <- mask(elev, landmask_fine)
# plot(elev_fill, fun = function() lines(as.polygons(landmask_fine)))
# elev_fill <- focal(elev, w = 5, fun = "median", na.rm = TRUE, na.policy = "only")
# elev_fill <- mask(elev_fill, landmask_fine)
# par(mfrow = c(1, 2))
# plot(elev, fun = function() lines(as.polygons(landmask_fine)))
# plot(elev_fill, fun = function() lines(as.polygons(landmask_fine)))

plot(merge(
  mask(project(mask(elev, landmask_fine), landmask, "max"), landmask),
  mask(project(mask(elev, landmask_fine, inverse = TRUE), landmask, "average"),
    landmask,
    inverse = TRUE
  )
))

# elev_coarse <- project(elev, landmask, method = "average", mask = FALSE)
# elev_coarse
elev_coarse <- merge(
  mask(project(mask(elev, landmask_fine), landmask, "max"), landmask),
  mask(project(mask(elev, landmask_fine, inverse = TRUE), landmask, "average"),
    landmask,
    inverse = TRUE
  )
)
elev_coarse
plot(elev_coarse, fun = function() {
  lines(as.polygons(landmask), lwd = 1.5)
  lines(land)
})
# # make elev_coarse at 0.5
# elev_coarse_fine <- project(elev_coarse, disagg(landmask_fine,2, "near"), method = "near")
# elev_coarse_fine <- crop(elev_coarse_fine, c(105,160,-50,7))
# elev_coarse_fine
# plot(elev_coarse_fine, fun = function() lines(as.polygons(disagg(landmask_fine,2, "near"))))

# writeCDF
writeCDF(elev_coarse, "./02_data/01_inputs/TraCE21_elevation.nc", varname = "elevation", longname = "elevation", unit = "m", compression = 1, overwrite = TRUE)
