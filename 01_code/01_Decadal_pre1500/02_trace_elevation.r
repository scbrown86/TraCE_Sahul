library(terra)
library(enmSdmX)

land <- vect(rnaturalearthhires::countries10)
land <- crop(land, ext(105.0, 161.25, -52.5, 11.25))
land <- aggregate(land)
plot(land)

template <- rast(extent = ext(-180, 180, -90, 90), res = 3.75, val = 1L)
template <- crop(template, ext(105, 161.25, -50, 10), snap = "out")
template

# Keep bathy
elev <- rast(lapply(list.files("/media/dafcluster4/storage/Ice5g/", 
                               full.names = TRUE, pattern = ".nc$"),
                    function(i) rast(i, "orog")))
elev <- crop(rotate(elev), ext(105.0, 161.25, -52.5, 11.25), snap = "out")
elev

# timesteps based on filenames
years <- as.numeric(sub(".*_([0-9]+\\.[0-9]+)k_.*", "\\1", 
                        list.files("/media/dafcluster4/storage/Ice5g/", 
                                   full.names = FALSE, pattern = ".nc$")))*1000
years*-1
time(elev) <- years

elev_interp <- enmSdmX::interpolateRasts(rasts = c(elev, elev[[39]]), 
                                         interpFrom = c(time(elev), 22000),
                                         interpTo = seq(0, 22000, 10), 
                                         type = "linear",
                                         verbose = TRUE)
time(elev_interp) <- seq(0, 22000, 10)
elev_interp #2201 layers
elev_interp <- setValues(elev_interp, round(values(elev_interp), 2))
elev_interp
idx <- which(rcarbon::BPtoBCAD(seq(0, 22000, 10)) < 1500)
elev_interp <- elev_interp[[idx]] #2155
# reverse order so 1490CE/460BP is last
elev_interp <- elev_interp[[rev(1:nlyr(elev_interp))]]
time(elev_interp) <- rcarbon::BPtoBCAD(time(elev_interp))
elev_interp

plot(elev_interp[[c(1, 500, 1000, 1500, 2000, 2500)]],
     range = c(-10, 1500), fill_range = TRUE,
     col = hcl.colors(100, "Batlow"),
     fun = function() lines(land))

landmask <- rast("/mnt/Data/TraCE21_Sahul/LANDFRAC/trace.01-36.22000BP.cam2.LANDFRAC.22000BP_decavg_400BCE.Sahul.preProc.nc", "LANDFRAC")
time(landmask) <- seq(from = 22000, length = 2204, by = -10)
landmask <- landmask[[which(seq(from = 22000, length = 2204, by = -10) >= 0)]]
idx <- which(rcarbon::BPtoBCAD(seq(22000, 0, -10)) < 1500)
landmask <- landmask[[idx]]
time(landmask) <- time(elev_interp)
landmask

head(cbind(time(elev_interp), time(landmask)))
par(mfrow = c(2, 2))
plot(elev_interp[[c(1, 2155)]], 
     range = c(0, 3000), fill_range = TRUE,
     col = hcl.colors(100, "Batlow"),
     fun = function() lines(land))
plot(landmask[[c(1, 2155)]], fun = function() lines(land))
par(mfrow = c(1, 1))

landmask <- ifel(landmask < 0.10, NA, 1) # less than 20% land, consider ocean
plot(landmask[[c(1, 2155)]], fun = function() lines(land))
landmask <- project(crop(landmask, ext(elev), snap = "out"), template, "near")
landmask

landmask_fine <- project(landmask, elev_interp, method = "near")
plot(landmask_fine[[c(1, 2155)]], fun = function() lines(land))

plot(merge(
  mask(project(mask(elev_interp[[2155]], landmask_fine[[2155]]), 
               landmask[[2155]], "average"), landmask[[2155]]),
  mask(project(mask(elev_interp[[2155]], landmask_fine[[2155]], 
                    inverse = TRUE), landmask[[2155]], "average"),
       landmask[[2155]],
       inverse = TRUE
  )), 
  fun = function() lines(land))

identical(time(elev_interp), time(landmask_fine))

elev_coarse <- merge(
  mask(project(mask(elev_interp, landmask_fine), landmask, "max"), landmask),
  mask(project(mask(elev_interp, landmask_fine, inverse = TRUE), 
               landmask, "average"),
       landmask,
       inverse = TRUE))
elev_coarse
elev_coarse <- setValues(elev_coarse, round(values(elev_coarse), 2))
plot(elev_coarse[[c(1, 2155)]],
     breaks = c(-Inf, 0, Inf),
     fill_range = TRUE,
     fun = function() {
       lines(as.polygons(landmask[[c(1, 2155)]]), lwd = 1.5)
       lines(land)
     })

# writeCDF
names(elev_coarse) <- rcarbon::BCADtoBP(time(elev_coarse))
depth(elev_coarse) <- NULL
writeCDF(elev_coarse, "/02_data/01_inputs/TraCE21_elevation_22kaBP_1490CE.nc", 
         varname = "elevation", longname = "elevation", 
         unit = "m", compression = 1, overwrite = TRUE)