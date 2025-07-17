library(terra)
land <- vect(rnaturalearthhires::countries10)
land <- crop(land, ext(105.0, 161.25, -52.5, 11.25))
land <- aggregate(land)

# ts
r <- rast("/media/dafcluster4/storage/TraCE_22k_1500CE/chunk_out/00001_00012/out/tas/CHELSA_tas_1_V.1.0.nc")
r-273.15
rbc <- rast("/media/dafcluster4/storage/TraCE_22k_1500CE/chunk_out/00001_00012/out/tas/CHELSA_tas_00001_00012_concat_biascorr.nc")[[1]]
rbc*1
plot(c(r-273.15, rbc), range = c(-5,35), fill_range = TRUE, main = c("raw ds TraCE", "bc TraCE"),
    fun = function() lines(land))

# dem
d <- rast("/mnt/Data/CHELSA_Trace21/Input/CHELSA_TraCE21k_dem_-200_V1.0.tif",
         win = c(105.0,161.25,-52.5,11.25))
d <- project(d, r, "average")
dm <- ifel(is.na(d), NA, 1)
d <- mask(d, dm)
plot(d, fun = function() lines(land), range = c(0, 2000), fill_range = FALSE)

# Karger CHELSA
kts <- (rast("/mnt/Data/CHELSA_Trace21/CHELSA_TraCE21k_tasmax_1_-200_V1.0.tif",
            win = c(105.0,161.25,-52.5,11.25)) +
       rast("/mnt/Data/CHELSA_Trace21/CHELSA_TraCE21k_tasmin_1_-200_V1.0.tif",
            win = c(105.0,161.25,-52.5,11.25))) * 0.5
kts <- project(kts, r, "average")
kts <- mask((kts/10)-273.15, dm)
kts
plot(kts, fun = function() lines(land))

plot(c(r-273.15, rbc, kts), nr = 1,
     range = c(-5,35), fill_range = TRUE, main = c("raw ds TraCE", "bc TraCE", "Karger TraCE"),
    fun = function() lines(land))

# deltas
d1 <- rast("02_data/02_processed/deltas/delta_fine_delta_tas_climatology_ncdf4.nc")[[1]]
d2 <- rast("02_data/02_processed/deltas/delta_fine_delta_tas_climatology.nc")[[1]]
d1 <- mask(d1, dm)
d2 <- mask(d2, dm)
plot(c(d1, d2), fun = function() lines(land))