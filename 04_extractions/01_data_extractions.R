library(terra)
library(data.table)
library(pbapply)

# days in month
dmon <- c(31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31)

land <- vect(rnaturalearthhires::countries10)
land <- crop(land, ext(143, 149, -44, -39))
land <- land[land$ADMIN == "Australia", ]
land <- aggregate(land)

# Read in the precip, tasmax, and tasmin data for Tasmania for 1500 onwards
downTrace <- pblapply(list.files("/media/dafcluster4/storage/TraCE_1500_1990CE/1500_1990/out",
                                 recursive = TRUE, pattern = "biascorr.nc",
                                 full.names = TRUE),
                      function(i) {
                        r <- rast(i, win = ext(143, 149, -44, -39), snap = "out")
                        time(r) <- seq(as.Date("1500-01-16"), by = "month", length = nlyr(r))
                        r
                      })
names(downTrace) <- c("pr", "tasmax", "tasmin")
downTrace