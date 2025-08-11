library(terra)
library(exactextractr)
library(data.table)
library(ggplot2)
library(pbapply)

land <- vect(rnaturalearthhires::countries10)
land <- crop(land, ext(106, 155, -50, 11))
aus <- aggregate(land[land$NAME == "Australia", ])
land <- aggregate(land)
plot(land)
lines(aus, col = "red")

land_buffer <- buffer(land, width = 100*1000)

# Time steps
## annual aggregations
time_annual <- 1500:1989

## centennial aggregations
nc <- ncdf4::nc_open("/mnt/Data/TraCE21_Sahul/PRECC/trace.01-36.22000BP-1990CE.cam2.h0.PRECC.0000101-2204012.Sahul.concat.nc")
years <- ncdf4::ncvar_get(nc, "year")
head(years, 20)
tail(years, 20)
months <- ncdf4::ncvar_get(nc, "month")
head(months, 100)
tail(months, 100)
ncdf4::nc_close(nc)
time_steps <- data.table(ID = 1:length(years),
                         Years = years,
                         Months = months)
# sequence of decades
time_steps[, dec := rep(1:(length(years) / 120), each = 120)]
time_steps[, century := ceiling(dec / 10)]
# time_steps[, cent := rep(1:(length(years) / 1200), each = 1200)]
time_steps <- copy(time_steps)[Years <= 1499, ][, .(Months = 1:12, Years = ceiling(mean(Years))), by = century]

time_centennial <- unique(time_steps[["Years"]]) # central year of centennial step
time_centennial <- c(time_centennial[1:215] - 50, time_centennial[216]-25)
rm(years, months, nc); gc()
time_centennial
# read in our downscaled temporal aggregated data
brown <- pblapply(list.files(path = "/media/dafcluster4/storage/TraCE_22k_1990CE_CoarseSummary",
                    pattern = "noSpat.nc",
                    recursive = TRUE,
                    full.names = TRUE), function(x) rast(x)*1)
brown

brown <- sds(
  c(brown[[2]]/c(rep(10, 215), 5), brown[[1]]),
  c(brown[[4]], brown[[3]]),
  c(brown[[6]], brown[[5]]),
  c(brown[[8]], brown[[7]]))
time(brown, tstep = "years") <- c(time_centennial, time_annual)
brown

plot(brown$pr[[c(1, 216, 217, 706)]], nc = 2,
     fun = function() lines(land), range = c(0, 3500),
     fill_range = TRUE, col = hcl.colors(100, "Roma"))

plot(brown$tas[[c(1, 216, 217, 706)]], nc = 2,
     fun = function() lines(land), range = c(5, 30),
     fill_range = TRUE, col = hcl.colors(100, "Temps"))

# Load in the aggregated Karger CHELSA TraCE data
karger <- lapply(list.files(path = "/mnt/Data/CHELSA_Trace21/Sahul",
                            pattern = "noSpat.nc",
                            full.names = TRUE)[1], function(x) rast(x)*1)
names(karger) <- c("pr", "tasmax", "tasmin")
plot(karger$pr[[c(1, 216, 217, 221)]], nc = 2,
     fun = function() lines(land), range = c(0, 3500),
     fill_range = TRUE, col = hcl.colors(100, "Roma"))
# Mask the karger data by the nearest brown layer
m <- match(seq(-20050, to = 1950, by = 100), time(brown$pr))
length(m) == nlyr(karger$pr)
karger$pr <- mask(karger$pr, brown$pr[[m]])
karger$tasmax <- mask(karger$tasmax, brown$tasmax[[m]])
karger$tasmin <- mask(karger$tasmin, brown$tasmin[[m]])
karger$tas <- 0.5 * (karger$tasmin + karger$tasmax)
karger <- sds(karger$pr, karger$tas, karger$tasmax, karger$tasmin)
names(karger) <- c("pr", "tas", "tasmax", "tasmin")
time(karger, tstep = "years") <- seq(-20050, to = 1950, by = 100)
karger

plot(karger$pr[[c(1, 216, 217, 221)]], nc = 2,
     fun = function() lines(land), range = c(0, 3000),
     fill_range = TRUE, col = hcl.colors(100, "Roma"))

plot(karger$tas[[c(1, 216, 217, 221)]], nc = 2,
     fun = function() lines(land), range = c(5, 30),
     fill_range = TRUE, col = hcl.colors(100, "Temps"))

plot(karger$pr[[c(1, 216, 217, 221)]]/brown$pr[[c(1, 216, 217, 667)]],
     nc = 2, fun = function() lines(land), range = c(0, 3),
     fill_range = TRUE, col = hcl.colors(100, "Roma"))

# Load in Koppen climate zones
koppen <- rast("02_data/01_inputs/koppen_sahul.tif")
koppen
koppen <- project(koppen, brown$pr[[1]], method = "mode")
plot(koppen, fun = function() lines(land))

# # Make plots of conditons at various time-points
# time_array <- rcarbon::BCADtoBP(time(karger$pr)[1:201])/1000
# time_poi <- c(22, 16.8, 14.7, 14.3, 12.2, 8.4)
# time_array
# sapply(time_poi, function(i) {
#   x <- which.min(abs(time_array - i))
#   plot(c(karger$pr[[x]], brown$pr[[x]]),
#        range = c(0, 3500),
#        fill_range = TRUE, col = hcl.colors(100, "Roma"),
#        main = i, fun = function() lines(land))
#   plot(karger$pr[[x]]/brown$pr[[x]],
#        range = c(0, 3),
#        fill_range = TRUE, col = hcl.colors(100, "Spectral"),
#        main = paste0("Delta pr ", i), fun = function() lines(land))
# })
#
# sapply(time_poi, function(i) {
#   x <- which.min(abs(time_array - i))
#   plot(c(karger$tas[[x]], brown$tas[[x]]),
#        main = i, fun = function() lines(land))
# })
#
# plot(c(karger$pr[[53]], brown$pr[[53]]),
#      range = c(100, 3000), fill_range = TRUE,
#      main = time_poi[2], fun = function() lines(land))

# Areal averages over the whole Sahul region
# Compute areal averages across zones, or across the entire Sahul area
get_summary_stats <- function(r, timevec, varname, koppen = NULL) {
  if (is.null(koppen)) {
    means <- global(r, "mean", na.rm = TRUE)[,1]
    sds   <- global(r, "sd", na.rm = TRUE)[,1]
    return(data.table(time = timevec, mean = means, sd = sds, variable = varname))
  } else {
    zones <- unique(values(koppen))  # extract unique values from the raster
    zones <- zones[!is.na(zones)]     # remove NA if present
    koppen_summary <- pblapply(zones, function(zone) {
      zone_mask <- ifel(koppen == zone, koppen, NA)
      r_masked  <- mask(r, zone_mask)
      means <- global(r_masked, "mean", na.rm = TRUE)[,1]
      sds   <- global(r_masked, "sd", na.rm = TRUE)[,1]
      return(data.table(time = timevec, mean = means, sd = sds, variable = varname, zone = zone))
    })
    dt <- rbindlist(koppen_summary)
    category_df <- cats(koppen)[[1]]
    dt <- merge(dt, category_df, by.x = "zone", by.y = "ID", all.x = TRUE)
    dt[, description := NULL]
    setcolorder(dt, c("time", "mean", "sd", "variable", "zone", "code"))
    return(dt)
  }
}

brown_summary <- rbindlist(lapply(1:4, function(i) {
  get_summary_stats(brown[[i]], time(brown$pr), names(brown)[i], koppen)
  }))
brown_summary[, Model := "Brown"]
karger_summary <- rbindlist(lapply(1:4, function(i) get_summary_stats(karger[[i]], time(karger$pr), names(karger)[i])))
karger_summary[, Model := "Karger"]
dt_summary <- rbindlist(list(brown_summary, karger_summary))
dt_summary

ggplot(dt_summary, aes(x = time, y = mean, color = Model, fill = Model)) +
  facet_wrap(~ variable, scales = "free_y") +
  geom_line() +
  geom_ribbon(aes(ymin = mean - sd, ymax = mean + sd), alpha = 0.2, color = NA) +

  labs(title = "Regional Mean and Variability Over Time (Sahul)", x = "Year (CE)", y = "Value") +
  scale_x_continuous(labels = function(x) 1950 - x) +
  theme_minimal()
