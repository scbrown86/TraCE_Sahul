library(terra)
library(exactextractr)
library(data.table)
library(ggplot2)
library(pbapply)

land <- vect(rnaturalearthhires::countries10)
land <- crop(land, ext(106, 155, -50, 7))
land <- land[land$ADMIN == "Australia", ]
land <- aggregate(land)
plot(land)

land_buffer <- buffer(land, width = 100*1000)

# read in our downscaled data
brown <- list.files(path = "/media/dafcluster4/storage/TraCE_22k_1500CE/out",
                    pattern = "biascorr.nc",
                    recursive = TRUE,
                    full.names = TRUE)
brown

# indexes for layers (decades)
idx <- rep(1:2155, each = 12)

# empty lists for storing results
pr_agg <- tas_agg <- tasmax_agg <- tasmin_agg <- vector("list", length = length(unique(idx)))

brown_agg <- pbsapply(unique(idx), function(i) {
  pr <- app(rast(brown[1], lyrs = which(idx == i), win = ext(land_buffer), snap = "out"), sum)
  units(pr) <- "mm/month"
  tas <- app(rast(brown[2], lyrs = which(idx == i), win = ext(land_buffer), snap = "out"), mean)
  tasmax <- app(rast(brown[3], lyrs = which(idx == i), win = ext(land_buffer), snap = "out"), mean)
  tasmin <- app(rast(brown[4], lyrs = which(idx == i), win = ext(land_buffer), snap = "out"), mean)
  units(tas) <- units(tasmax) <- units(tasmin) <- "deg_C"
  names(pr) <- names(tas) <- names(tasmax) <- names(tasmin) <- paste0("C_", i)
  pr_agg[[i]] <- pr; tas_agg[[i]] <- tas
  tasmax_agg[[i]] <- tasmax; tasmin_agg[[i]] <- tasmin
  return(i)
})

# Load in Koppen climate zones
koppen <- rast("02_data/01_inputs/koppen_zones_raster.tif")
koppen <- project(koppen, brown$pr, method = "near")
koppen <- mask(koppen, project(land, koppen), touches = TRUE)
has.colors(koppen)
kd <- data.frame(id = 1:6,
                 Koppen = c("Temperate", "Grassland", "Desert",
                            "Subtropical", "Tropical", "Equatorial"))
levels(koppen) <- kd
koppen
plot(koppen)

# Read in the CHELSA-TraCE21k data for 22k to 1500CE
chelsa_lut <- data.table(ID = 1:221,
                         year_ID = seq(20, -200, by = -1),
                         start_year = seq(1900, by = -100, l = 221),
                         end_year = c(1990, seq(1899, by = -100, l = 220)),
                         kBP = seq(0, by = -0.1, l = 221))
chelsa_lut[start_year <= 1500, ]
# List all .tif files in the folder
chelsa_fil <- mixedsort(list.files("/mnt/Data/CHELSA_Trace21/",
                                   pattern = ".tif$",
                                   full.names = TRUE))
head(chelsa_fil)
pattern <- "CHELSA_TraCE21k_[a-z]+_([1-9]|1[0-2])_20_V1\\.0\\.tif"
chelsa_fil <- chelsa_fil[grepl(pattern, chelsa_fil)]
chelsa_fil

chelsa_trace <- list(pr = rast(chelsa_fil[1:12], win = ext(land)),
                     tasmax = rast(chelsa_fil[13:24], win = ext(land)),
                     tasmin = rast(chelsa_fil[25:36], win = ext(land)))
chelsa_trace <- pblapply(chelsa_trace, function(i) {
  return(project(i, brown$pr[[1]], method = "average", use_gdal = TRUE, threads = TRUE))
})

# convert tasmax and tasmin to deg_C
chelsa_trace$tasmax <- (chelsa_trace$tasmax*0.1)-273.15
chelsa_trace$tasmin <- (chelsa_trace$tasmin*0.1)-273.15
units(chelsa_trace$tasmax) <- units(chelsa_trace$tasmin) <- "deg_C"
chelsa_trace$tas <- (chelsa_trace$tasmax + chelsa_trace$tasmin) * 0.5
units(chelsa_trace$tas) <- "deg_C"
time(chelsa_trace$pr) <- time(chelsa_trace$tasmax) <-
  time(chelsa_trace$tasmin) <- time(chelsa_trace$tas) <-
  seq(as.Date("1950-01-16"), by = "month", l = 12)
chelsa_trace

