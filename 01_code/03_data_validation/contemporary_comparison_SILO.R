library(terra)
library(gtools)
library(pbapply)
library(exactextractr)
library(sf)
library(data.table)
library(ggplot2)
library(qpdf)
library(plotrix)

# setGDALconfig("GDAL_PAM_ENABLED", "TRUE")
# terraOptions(memfrac = 0.85, memmax = 50)

land <- vect(rnaturalearthhires::countries10)
land <- crop(land, ext(106, 155, -50, 7))
land <- land[land$ADMIN == "Australia", ]
land <- aggregate(land)
plot(land)

# days in month
dmon <- c(31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31)
plot_avg <- FALSE

# # source the SILO data
# source("01_code/00_functions/silo_dl.R")
#
# year_vec <- 1900:1989
# # Download the data from SILO as netcdf files
# ## n.b. will overwrite any files already downloaded
# silo_dl(years_vec = year_vec,
#         variable = "monthly_rain",
#         dir = "/mnt/Data/SILO/PREC")
# silo_dl(years_vec = year_vec,
#         variable = "max_temp",
#         dir = "/mnt/Data/SILO/TASMAX")
# silo_dl(years_vec = year_vec,
#         variable = "min_temp",
#         dir = "/mnt/Data/SILO/TASMIN")

# read in our downscaled data
brown <- list.files(path = "/media/dafcluster4/storage/TraCE_1500_1990CE/1500_1990/out",
                    pattern = "biascorr.nc",
                    recursive = TRUE,
                    full.names = TRUE)
brown
brown <- pblapply(brown, function(x) {
  r <- rast(x, lyrs = 4801:5880, win = ext(land), snap = "out")
  time(r) <- seq(as.Date("1900-01-16"), by = "month", l = nlyr(r))
  r
})
brown <- sds(brown)
names(brown) <- c("pr", "tasmax", "tasmin")
time(brown) <- seq(as.Date("1900-01-16"), by = "month", l = nlyr(brown$pr))
brown

# load in SILO
# silo <- list.files("/mnt/Data/SILO",
#                    "remap",
#                    full.names = TRUE,
#                    recursive = TRUE)
# silo
# silo <- pblapply(silo, function(x) {
#   r <- rast(x, win = ext(land), snap = "out")
#   time(r) <- seq(as.Date("1900-01-16"), by = "month", l = nlyr(r))
#   r
# })
# names(silo) <- c("pr", "tasmax", "tasmin")
# silo$pr <- setValues(silo$pr, values(silo$pr)/(86400 * dmon))
# silo <- sds(silo)
# time(silo) <- seq(as.Date("1900-01-16"), by = "month", l = nlyr(silo$pr))
# silo
source("01_code/00_functions/agcd_proc.R")
silo <- pblapply(c("precip", "tmax", "tmin"), agcd_proc,
                 dir = "/mnt/Data/AusClim/data/raw/agcd",
                 template = brown$pr[[1]], years = 1910:1989,
                 proj_method = "average", type = ".nc$")
names(silo) <- c("pr", "tasmax", "tasmin")
silo$pr <- setValues(silo$pr, values(silo$pr)/(86400 * dmon))
units(silo$pr) <- units(brown$pr)[1]
time(silo$pr) <- time(silo$tasmax) <- time(silo$tasmin) <-
  seq(as.Date("1910-01-16"), by = "month", l = nlyr(silo$pr))
silo

# Load in CHELSA baseline data
source("01_code/00_functions/chelsa_proc.R")
chelsa_12 <- lapply(c("prec", "tmax", "tmin"),
  FUN = chelsa_proc,
  mask = NULL,
  ymin = 1980, ymax = 1989,
  tras_ext = ext(105.0, 161.25, -52.5, 11.25),
  load_exist = TRUE,
  dir = "/mnt/Data/CHELSA/v1.2",
  outdir = "02_data/02_processed/CHELSA",
  cores = 5L)
chelsa_12 <- pblapply(seq_along(chelsa_12), function(i) {
  remap <- if (i == 1) {"average"} else {"bilinear"}
  r <- project(rast(chelsa_12[[i]]), brown$pr, method = remap, use_gdal = TRUE, threads = TRUE)
  time(r) <- seq(as.Date("1980-01-16"), by = "month", l = nlyr(r))
  r
})
names(chelsa_12) <- c("pr", "tasmax", "tasmin")
chelsa_12

# Read in the CHELSA-TraCE21k data for 1900-1989
chelsa_lut <- data.table(ID = 1:221,
                         year_ID = seq(20, -200, by = -1),
                         start_year = seq(1900, by = -100, l = 221),
                         end_year = c(1990, seq(1899, by = -100, l = 220)),
                         kBP = seq(0, by = -0.1, l = 221))
chelsa_lut[start_year >= 1850, ]
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
  return(project(i, brown$pr[[1]], method = "bilinear", use_gdal = TRUE, threads = TRUE))
})
chelsa_trace
# convert tasmax and tasmin to deg_C
chelsa_trace$tasmax <- (chelsa_trace$tasmax*0.1)-273.15
chelsa_trace$tasmin <- (chelsa_trace$tasmin*0.1)-273.15
chelsa_trace$pr <- chelsa_trace$pr/(86400 * dmon)
units(chelsa_trace$tasmax) <- units(chelsa_trace$tasmin) <- "deg_C"
units(chelsa_trace$pr) <- units(brown$pr)[1]
time(chelsa_trace$pr) <- time(chelsa_trace$tasmax) <-
  time(chelsa_trace$tasmin) <- seq(as.Date("1950-01-16"), by = "month", l = 12)
chelsa_trace

# Load in Koppen climate zones
# koppen <- rast("02_data/01_inputs/koppen_sahul.tif")
# koppen <- mask(project(koppen, brown$pr, method = "mode"),
#                land, touches = TRUE)
# plot(koppen$major_desc, fun = function() lines(land))

koppen_bom <- rast("02_data/01_inputs/koppen_zones_raster.tif")
koppen_bom <- project(koppen_bom, brown$pr, method = "mode")
koppen_bom <- mask(koppen_bom, land, touches = TRUE)
has.colors(koppen_bom)
kd <- data.frame(id = 1:6,
                 Koppen = c("Temperate", "Grassland", "Desert",
                            "Subtropical", "Tropical", "Equatorial"))
levels(koppen_bom) <- kd
koppen_bom
plot(koppen_bom)

# Compute areal averages across zones, or across the entire Sahul area
get_summary_stats <- function(r, timevec, varname, koppen = NULL) {
  if (is.null(koppen)) {
    means <- global(r, "mean", na.rm = TRUE)[,1]
    sds <- global(r, "sd", na.rm = TRUE)[,1]
    return(data.table(time = timevec, mean = means, sd = sds, variable = varname))
  } else {
    zones <- unique(values(koppen))  # extract unique values from the raster
    zones <- zones[!is.na(zones)]     # remove NA if present
    koppen_summary <- pblapply(zones, function(zone) {
      zone_mask <- ifel(koppen == zone, koppen, NA)
      r_masked <- mask(r, zone_mask)
      means <- global(r_masked, "mean", na.rm = TRUE)[,1]
      sds <- global(r_masked, "sd", na.rm = TRUE)[,1]
      return(data.table(time = timevec, mean = means, sd = sds, variable = varname, zone = zone))
    })
    dt <- rbindlist(koppen_summary)
    category_df <- cats(koppen)[[1]]
    dt <- merge(dt, category_df, by.x = "zone", by.y = "id", all.x = TRUE)
    setcolorder(dt, c("time", "mean", "sd", "variable", "zone", "Koppen"))
    invisible(gc())
    return(dt)
  }
}
zseq <- time(brown$pr)
brown_summary <- rbindlist(lapply(seq_along(brown), function(i) {
  get_summary_stats(r = brown[[i]], timevec = zseq, varname = names(brown)[i],
                    koppen = koppen_bom)
}))
brown_summary[, Model := "Brown"]
brown_summary

zseq <- time(silo$pr)
silo_summary <- rbindlist(lapply(seq_along(silo), function(i) {
  get_summary_stats(r = silo[[i]], timevec = zseq, varname = names(silo)[i], koppen_bom)
}))
silo_summary[, Model := "BoM"]
silo_summary

zseq <- time(chelsa_12$pr)
chelsa_summary <- rbindlist(lapply(seq_along(chelsa_12), function(i) {
  get_summary_stats(r = chelsa_12[[i]], timevec = zseq, varname = names(chelsa_12)[i], koppen_bom)
}))
chelsa_summary[, Model := "CHELSA"]
chelsa_summary

zseq <- time(chelsa_trace$pr)
chelsaTrace_summary <- rbindlist(lapply(seq_along(chelsa_trace), function(i) {
  get_summary_stats(r = chelsa_trace[[i]], timevec = zseq, varname = names(chelsa_trace)[i], koppen_bom)
}))
chelsaTrace_summary[, Model := "Karger"]
chelsaTrace_summary

dt_summary <- rbindlist(list(brown_summary, silo_summary, chelsa_summary, chelsaTrace_summary))
dt_summary

saveRDS(dt_summary, "03_comparisons/koppen_comparisons_contemporary.RDS")

dt_summary[, Year := as.integer(format(dt_summary[["time"]], "%Y"))]
dt_summary
dt_avg <- copy(dt_summary)[, .(mean = mean(mean), sd = mean(sd)),
                           by = c("Year", "variable", "Koppen", "Model")]
karger_summaries <- rbindlist(list(
  copy(dt_avg)[Model == "Karger", ][, Year := 1900L],
  copy(dt_avg)[Model == "Karger", ][, Year := 1989L])
)
dt_avg <- rbindlist(list(dt_avg, karger_summaries))
dt_avg

set(dt_avg, i = which(dt_avg[["variable"]] == "pr"),
    j = "mean", value = (dt_avg[["mean"]][which(dt_avg[["variable"]] == "pr")] * 86400)*30)
set(dt_avg, i = which(dt_avg[["variable"]] == "pr"),
    j = "sd", value = (dt_avg[["sd"]][which(dt_avg[["variable"]] == "pr")] * 86400)*30)
dt_avg

dt_avg[Model == "Brown",
       `:=`(mean = frollmean(mean, n = 10),
            sd = frollmean(sd, n = 10)),
       by = .(variable, Koppen)]

p1 <- ggplot(dt_avg[Model != "BoM", ],
       aes(x = Year, y = mean, color = Model, fill = Model,
           group = interaction(Koppen, Model))) +
  #facet_wrap(~ Koppen, scales = "free_y") +
  ggh4x::facet_grid2(factor(variable, levels = c("pr", "tasmin", "tasmax")) ~ Koppen,
                     scales = "free_y", independent = "y") +
  geom_line(show.legend = FALSE) +
  geom_ribbon(aes(ymin = mean - sd, ymax = mean + sd), alpha = 0.2, color = NA) +
  geom_line(linewidth = 0.5, show.legend = FALSE) +
  scale_colour_manual(values = c("Brown" = "#1b9e77",
                                 "BoM" = "#d95f02",
                                 "Karger" = "#e7298a",
                                 "CHELSA" = "#7570b3")) +
  scale_fill_manual(values = c("Brown" = "#1b9e77",
                               "BoM" = "#d95f02",
                               "Karger" = "#e7298a",
                               "CHELSA" = "#7570b3"),
                    labels = c("BROWN" = "TraCE-Sahul",
                               "BoM" = "BoM",
                               "Karger" = "CHELSA\nTraCE-21ka",
                               "CHELSA" = "CHELSA\nv1.2"),
                    guide = guide_legend(title = "Model",
                                         nrow = 1,
                                         theme = theme(
                                           legend.title.position = "top",
                                           legend.title = element_text(hjust = 0.5),
                                           legend.text.position = "bottom",
                                           legend.key.height = unit(0.5, "cm"),
                                           legend.key.width = unit(1, "cm")
                                         ))) +
  cowplot::theme_cowplot() +
  theme(legend.position = "bottom",
        legend.justification = "center",
        legend.direction = "horizontal") +
  labs(title = "Regional Mean and Variability Over Time (Sahul)", x = "Year (CE)", y = "Value")
p1
# iterate through each dataset and extract monthly averages and SD for each zone
source("01_code/00_functions/koppen_summary.R")
koppen <- koppen_bom

step_summaries <- koppen_summary(list(as.list(brown), silo, chelsa_12, chelsa_trace))
names(step_summaries) <- c("brown", "agcd", "CHELSA", "CHELSA_trace")
step_summaries

saveRDS(step_summaries, "03_comparisons/scratch/step_summaries.RDS")

step_summaries <- readRDS("03_comparisons/scratch/step_summaries.RDS")

plot(x = step_summaries$brown[Koppen == "Temperate" & variable == "tasmax", ][["Year"]],
     y = step_summaries$brown[Koppen == "Temperate" & variable == "tasmax", ][["mean"]],
     type = "l", col = "#d95f02", ylim = c(17, 22))
lines(x = step_summaries$agcd[Koppen == "Temperate" & variable == "tasmax", ][["Year"]],
      y = step_summaries$agcd[Koppen == "Temperate" & variable == "tasmax", ][["mean"]],
      col = "#1b9e77")
lines(x = step_summaries$CHELSA[Koppen == "Temperate" & variable == "tasmax", ][["Year"]],
      y = step_summaries$CHELSA[Koppen == "Temperate" & variable == "tasmax", ][["mean"]],
      col = "#7570b3")

plot(x = step_summaries$brown[Koppen == "Temperate" & variable == "pr", ][["Year"]],
     y = step_summaries$brown[Koppen == "Temperate" & variable == "pr", ][["mean"]] * 86400 * 31,
     type = "l", col = "#d95f02", ylim = c(38, 75))
lines(x = step_summaries$agcd[Koppen == "Temperate" & variable == "pr", ][["Year"]],
      y = step_summaries$agcd[Koppen == "Temperate" & variable == "pr", ][["mean"]] * 86400 * 31,
      col = "#1b9e77")
lines(x = step_summaries$CHELSA[Koppen == "Temperate" & variable == "pr", ][["Year"]],
      y = step_summaries$CHELSA[Koppen == "Temperate" & variable == "pr", ][["mean"]] * 86400 * 31,
      col = "#7570b3")

step_summaries$brown <- copy(step_summaries$brown)[, MODEL := "BROWN"]
step_summaries$agcd <- copy(step_summaries$agcd)[, MODEL := "AGCD"]
step_summaries$CHELSA <- copy(step_summaries$CHELSA)[, MODEL := "CHELSA"]
step_summaries$CHELSA_trace <- copy(step_summaries$CHELSA_trace)[, MODEL := "CHELSA_Trace"]

step_summaries <- rbindlist(step_summaries)

step_summaries_roll <- copy(step_summaries)
summary(step_summaries_roll)
step_summaries_roll

vars <- c("mean", "SD")
step_summaries_roll[, paste0("roll_", vars) := frollmean(.SD, n = 10, align = "right",
                                                         hasNA = FALSE),
                    by = c("Koppen", "variable", "MODEL"),
                    .SDcols = vars]
step_summaries_roll

step_summaries_roll[, MODEL := factor(MODEL, levels = c("BROWN", "AGCD", "CHELSA", "CHELSA_Trace"))]

set(step_summaries_roll, i = which(step_summaries_roll[["MODEL"]] == "CHELSA_Trace"),
    j = "roll_mean", value = step_summaries_roll[MODEL == "CHELSA_Trace", ][["mean"]])
set(step_summaries_roll, i = which(step_summaries_roll[["MODEL"]] == "CHELSA_Trace"),
    j = "roll_SD", value = step_summaries_roll[MODEL == "CHELSA_Trace", ][["SD"]])

step_summaries_roll

facet_labels <- function(variable) {
  sapply(variable, function(v) {
    if (v == "pr") {
      "pr (mm/year)"
    } else {
      paste0(v, " (°C)")
    }
  })
}

# Define target years
years <- 1900:1989

# Get unique combinations of the grouping columns
unique_combos <- unique(copy(step_summaries_roll)[MODEL == "CHELSA_Trace", .(Koppen, variable, MODEL)])

# Create all combinations of those with the full year range
expanded <- CJ(Year = years, Koppen = unique_combos$Koppen,
               variable = unique_combos$variable, MODEL = unique_combos$MODEL, unique = TRUE)

# Merge the original data to the expanded data
# We'll keep only one value per group from the original and replicate it
merged <- merge(expanded, copy(step_summaries_roll)[MODEL == "CHELSA_Trace", ],
                by = c("Koppen", "variable", "MODEL"), all.x = TRUE)

# Fill in missing 'mean' and 'SD' using the first available value per group
merged[, `:=`(mean = mean[!is.na(mean)][1],
              SD = SD[!is.na(SD)][1]), by = .(Koppen, variable, MODEL)]


p2 <- ggplot(data = step_summaries_roll[MODEL %in% c("BROWN")],#, "AGCD"), ],
             aes(x = Year, y = roll_mean,
                 group = interaction(Koppen, MODEL),
                 colour = MODEL, fill = MODEL)) +
  ggh4x::facet_grid2(factor(variable, levels = c("pr", "tas", "tasmin", "tasmax")) ~ Koppen,
                     scales = "free_y", independent = "y",
                     labeller = labeller(.rows = facet_labels)) +
  geom_ribbon(data = merged,
              inherit.aes = FALSE,
              aes(x = Year.x, y = roll_mean,
                  ymin = roll_mean - roll_SD,
                  ymax = roll_mean + roll_SD,
                  group = interaction(Koppen, MODEL),
                  fill = MODEL),
              colour = NA,
              alpha = 0.25) +
  geom_ribbon(inherit.aes = TRUE,
              colour = NA,
              aes(ymin = roll_mean - roll_SD,
                  ymax = roll_mean + roll_SD),
              alpha = 0.25) +
  geom_line(data = merged,
            inherit.aes = FALSE,
            aes(x = Year.x, y = roll_mean,
                group = interaction(Koppen, MODEL),
                colour = MODEL),
            linewidth = 0.5, show.legend = FALSE) +
  geom_line(linewidth = 0.5, show.legend = FALSE) +
  scale_colour_manual(values = c("BROWN" = "#1b9e77", "AGCD" = "#d95f02", "CHELSA_Trace" = "#7570b3")) +
  scale_fill_manual(values = c("BROWN" = "#1b9e77", "AGCD" = "#d95f02", "CHELSA_Trace" = "#7570b3"),
                    labels = c("BROWN" = "Brown", "AGCD" = "BoM", "CHELSA_Trace" = "CHELSA\nTraCE-21ka"),
                    guide = guide_legend(title = "Model",
                                         nrow = 1,
                                         theme = theme(
                                           legend.title.position = "top",
                                           legend.title = element_text(hjust = 0.5),
                                           legend.text.position = "bottom",
                                           legend.key.height = unit(0.5, "cm"),
                                           legend.key.width = unit(1, "cm")
                                         ))) +
  cowplot::theme_cowplot() +
  theme(legend.position = "bottom",
        legend.justification = "center",
        legend.direction = "horizontal") +
  labs(x = "Year", y = "mean")
p2

pdf(file = "03_comparisons/zonal_means.pdf",
    width = 14, height = 8, bg = "white",
    pagecentre = TRUE)
print(p1)
dev.off()

# pdf(file = "03_comparisons/raster_means.pdf",
#     paper = "a4", bg = "white",
#     pagecentre = TRUE)
# {p6 <- plot(crop(mask(c(app(CHELSA_Trace21_1950$pr, sum),
#                         app(brown_1910_1989$pr, sum)),
#                       land), land),
#              nr = 2, range = c(150, 1500),
#             fill_range = TRUE,
#             col = hcl.colors(100, "YlGnBu", rev = TRUE),
#              main = c("CHELSA TraCE", "Brown"),
#              fun = function() lines(land),
#              plg = list(title = "rainfall (mm/year)", side = 4,
#                         at = seq(150, 1500, l = 10),
#                         font = 2, line = 2.5, cex = 0.8))
#
#   p7 <- plot(crop(mask(c(app(CHELSA_Trace21_1950$tas, mean),
#                          app(brown_1910_1989$tas, mean)), land), land),
#              nr = 2, range = c(0, 30),
#              fill_range = TRUE,
#              main = c("CHELSA TraCE", "Brown"),
#              fun = function() lines(land),
#              col = hcl.colors(100, "Batlow"),
#              plg = list(title = "tas (deg C)", side = 4,
#                         at = seq(0, 30, l = 11),
#                         font = 2, line = 2.5, cex = 0.8))
#
#   p8 <- plot(crop(mask(c(app(CHELSA_Trace21_1950$tasmin, mean),
#                          app(brown_1910_1989$tasmin, mean)), land), land),
#              nr = 2, range = c(0, 30),
#              fill_range = TRUE,
#              col = hcl.colors(100, "Batlow"),
#              main = c("CHELSA TraCE", "Brown"),
#              fun = function() lines(land),
#              plg = list(title = "tasmin (deg C)", side = 4,
#                         at = seq(0, 30, l = 11),
#                         font = 2, line = 2.5, cex = 0.8))
#
#   p9 <- plot(crop(mask(c(app(CHELSA_Trace21_1950$tasmax, mean),
#                         app(brown_1910_1989$tasmax, mean)), land), land),
#             nr = 2, range = c(0, 30),
#             fill_range = TRUE,
#             col = hcl.colors(100, "Batlow"),
#             main = c("CHELSA TraCE", "Brown"),
#             fun = function() lines(land),
#             plg = list(title = "tasmax (deg C)", side = 4,
#                        at = seq(0, 30, l = 11),
#                        font = 2, line = 2.5, cex = 0.8))
# }
# dev.off()
#
# qpdf::pdf_combine(input = c("03_comparisons/zonal_means.pdf",
#                             "03_comparisons/zonal_means_brown_karger.pdf",
#                             "03_comparisons/raster_means.pdf"),
#                   output = "03_comparisons/combined.pdf")

regions <- unique(dt_avg[["Koppen"]])

brown_means <- pblapply(seq_along(brown), function(i) {
  r <- tapp(brown[[i]], "months", mean)
  r
})

panel(brown_means$pr * (86400*dmon),
      main = month.abb,
      fun = function() lines(land),
      col = hcl.colors(100, "roma"),
      range = c(0, 200), fill_range = TRUE)

panel(silo_means$pr / brown_means$pr, range = c(0, 3),
      fill_range = TRUE)

panel(chelsa_means$pr / brown_means$pr, range = c(0, 3),
      fill_range = TRUE)

chelsa_means$pr/tapp(brown$pr[[which(time(brown$pr) >= as.Date("1980-01-16"))]],
     "months", mean)

silo_means <- pblapply(seq_along(silo), function(i) {
  r <- tapp(silo[[i]], "months", mean)
  r
})

chelsa_means <- pblapply(seq_along(chelsa_12), function(i) {
  r <- tapp(chelsa_12[[i]], "months", mean)
  r
})

names(brown_means) <- names(silo_means) <- names(chelsa_means) <- names(chelsa_trace)

# DELTA between CHELSA and Brown
## positive values mean Karger is higher
source("01_code/00_functions/raster_to_sds.R")
agcd <- split_raster_by_variable(rast("03_comparisons/agcd_1910_1989_monthly.tif"))
agcd
CHELSA_Trace21_1950 <- split_raster_by_variable(rast("03_comparisons/CHELSA_Trace21_1950_monthly.tif"))
brown_1910_1989 <- split_raster_by_variable(rast("03_comparisons/brown_1910_1989_monthly.tif"))

if (TRUE) {
  delta_pr <- crop(mask(app(CHELSA_Trace21_1950$pr, mean) / app(brown_1910_1989$pr, mean), land), land)
  delta_pr # > 1 == Karger wetter
  plot(delta_pr)

  delta_tasmax <- crop(mask(app(CHELSA_Trace21_1950$tasmax, mean) - app(brown_1910_1989$tasmax, mean), land), land)
  delta_tasmax
  hist(delta_tasmax)
  plot(delta_tasmax)

  delta_tasmin <- crop(mask(app(CHELSA_Trace21_1950$tasmin, mean) - app(brown_1910_1989$tasmin, mean), land), land)
  delta_tasmin
  hist(delta_tasmin)
  plot(delta_tasmin)

  delta_tas <- crop(mask(app(CHELSA_Trace21_1950$tas, mean) - app(brown_1910_1989$tas, mean), land), land)
  delta_tas
  hist(delta_tas)
  plot(delta_tas)
}
pdf(file = "03_comparisons/comparisons_delta.pdf",
    width = 10, height = 9, onefile = TRUE, bg = "white")
par(mfrow = c(2,2), mai = c(0.5,0.5,0.5,0.5), mar = c(0.5,0.5,0.5,0.5))
{plot(delta_pr, mar = c(5,0,0.5,0),
      buffer = TRUE,
      smooth = FALSE, box = TRUE, range = c(0.5, 2),
      fill_range = TRUE,
      plg = list(x = "bottom",
                 cex = 1, bty = "n",
                 at = seq(0.5, 2, by = 0.5),
                 size = c(0.75, 1),
                 tics = "out", title = "precipitation delta"),
      fun = function() lines(land, col = "#000000"))
  plot(delta_tas,
       range = c(-4, 4),
       fill_range = TRUE,
       buffer = TRUE,
       mar = c(5,0,0.5,0),
       smooth = FALSE, box = TRUE,
       plg = list(x = "bottom",
                  cex = 1, bty = "n",
                  size = c(0.75, 1),
                  at = seq(-4, 4),
                  tics = "out", title = "temperature delta"),
       fun = function() lines(land, col = "#000000"))
  plot(delta_tasmax,
       range = c(-4, 4),
       fill_range = TRUE,
       buffer = TRUE,
       mar = c(5,0,0.5,0),
       smooth = TRUE, box = TRUE,
       plg = list(x = "bottom",
                  cex = 1, bty = "n",
                  size = c(0.75, 1),
                  at = seq(-4, 4),
                  #labels = c(-3, "", -2, "", -1, "", 0, "", 1, "", 2, "", 3),
                  tics = "out", title = "max temperature delta"),
       fun = function() lines(land, col = "#000000"))
  plot(delta_tasmin,
       range = c(-4, 4),
       fill_range = TRUE,
       buffer = TRUE,
       mar = c(5,0,0.5,0),
       smooth = TRUE, box = TRUE,
       plg = list(x = "bottom",
                  cex = 1, bty = "n",
                  size = c(0.75, 1),
                  at = seq(-4, 4),
                  tics = "out", title = "min temperature delta"),
       fun = function() lines(land, col = "#000000"))
}
dev.off()

# common mask to mask all three datasets
comm <- c(silo$pr[[1]], brown_means$pr[[1]], chelsa_trace$pr[[1]],
          # agcd$tas[[1]], brown_1910_1989$tas[[1]], CHELSA_Trace21_1950$tas[[1]],
          silo$tasmin[[1]], brown_means$tasmin[[1]], chelsa_trace$tasmin[[1]],
          silo$tasmax[[1]], brown_means$tasmax[[1]], chelsa_trace$tasmax[[1]])
comm_sum <- app(comm, function(i) sum(!is.na(i)))
comm_sum <- ifel(comm_sum == 9, 1, NA)
comm_mask <- mask(comm_sum, land)
comm_mask; plot(comm_mask)

koppen <- mask(koppen, comm_mask)

source("01_code/00_functions/spatrast_to_taylor.R")

#### ZONAL TAYLOR ####
pdf(file = "03_comparisons/comparisons_taylor_koppen.pdf",
    width = 8, height = 8, onefile = TRUE, bg = "white")
par(mai = c(0.5,0.5,0.5,0.5), mar = c(0.5,0.5,0.5,0.5))
{{taylor_from_spatraster_zones(obs = chelsa_trace$tasmax,
                              mod = brown_means$tasmax,
                              zones = koppen,
                              add = FALSE,
                              zone_names = c("Temperate", "Grassland", "Desert",
                                             "Subtropical", "Tropical", "Equatorial"),
                              col_palette = c("#1f78b4", "#ffff99",
                                              "#b15828", "#b2df8a",
                                              "#34a02c", "#cab2d6"),
                              pch = 17, pcex = 1.5,
                              sig_digits = 3,
                              main = NULL)
  taylor_from_spatraster_zones(obs = chelsa_trace$tasmax,
                               mod = brown_means$tasmax,
                               zones = NULL,
                               add = TRUE,
                               sig_digits = 3,
                               pch = 17, pcex = 1.5,
                               main = NULL, col = "black")
  taylor_from_spatraster_zones(obs = chelsa_trace$tasmin,
                               mod = brown_means$tasmin,
                               zones = koppen,
                               add = TRUE,
                               sig_digits = 3,
                               zone_names = c("Temperate", "Grassland", "Desert",
                                              "Subtropical", "Tropical", "Equatorial"),
                               col_palette = c("#1f78b4", "#ffff99",
                                               "#b15828", "#b2df8a",
                                               "#34a02c", "#cab2d6"),
                               pch = 18, pcex = 2,
                               main = NULL)
  taylor_from_spatraster_zones(obs = chelsa_trace$tasmin,
                               mod = brown_means$tasmin,
                               zones = NULL,
                               add = TRUE,
                               sig_digits = 3,
                               pch = 18, pcex = 2,
                               main = NULL, col = "black")
  taylor_from_spatraster_zones(obs = chelsa_trace$pr,
                               mod = brown_means$pr,
                               zones = koppen,
                               add = TRUE,
                               sig_digits = 6,
                               zone_names = c("Temperate", "Grassland", "Desert",
                                              "Subtropical", "Tropical", "Equatorial"),
                               col_palette = c("#1f78b4", "#ffff99",
                                               "#b15828", "#b2df8a",
                                               "#34a02c", "#cab2d6"),
                               pch = 19, pcex = 1.5,
                               main = NULL)
  taylor_from_spatraster_zones(obs = chelsa_trace$pr,
                               mod = brown_means$pr,
                               zones = NULL,
                               sig_digits = 6,
                               add = TRUE,
                               pch = 19, pcex = 1.5, col = "black",
                               main = NULL)
  legend(x = 0.07, y = 1.85,
         legend = c("precipitation", "minimum temperature",
                    "maximum temperature"),
         col = "black",
         pch = c(19, 17, 18), box.lwd = 0,box.lty = 0,box.col = NA,
         pt.cex = c(1.5, 1.5, 2),
         ncol = 1)
}
# Save current par settings
old_par <- par(no.readonly = TRUE)
# Add inset using par(fig = ...) and par(new = TRUE)
par(fig = c(0.55,1.0, 0.55, 1.0), new = TRUE)
# Plot the map: could be zones, obs, etc.
plot(crop(koppen, land), axes = FALSE,
     buffer = TRUE,
     legend = TRUE, box = FALSE,
     plg = list(x = 154, y = -10,
                cex = 1,
                title = "Koppen zone"))
par(old_par)}
dev.off()


#### MONTHLY TAYLOR ####
chelsa_trace <- sds(chelsa_trace)
brown_means <- sds(brown_means)
silo_means <- sds(silo_means)
# Define color palette
colours <- c(
  Rainfall = "#0072B2",
  AirTemp = "#D55E00",
  MinTemp = "#009E73",
  MaxTemp = "#CC79A7")
pdf(file = "03_comparisons/comparisons_taylor.pdf",
    width = 8, height = 8, onefile = TRUE, bg = "white")
par(mai = c(0.5,0.5,0.5,0.5), mar = c(0.5,0.5,0.5,0.5))
{
  # taylor_from_sds_monthly(obs_sds = silo,
  #                        mod_sds = brown_means,
  #                        var_name = "tas",
  #                        col_palette = colours[2],
  #                        use_mask = comm_mask,
  #                        zones = NULL, add = FALSE,
  #                        sig_digits = 3, pch = 19,
  #                        main = "", ref.sd = TRUE,
  #                        sd.method = "population",
  #                        normalize = TRUE, mar = c(4,4,0,0))
  taylor_from_sds_monthly(obs_sds = silo_means,
                          mod_sds = brown_means,
                          var_name = "tasmin",
                          col_palette = colours[3],
                          use_mask = comm_mask,
                          zones = NULL, add = FALSE,
                          sig_digits = 3, pch = 19,
                          main = "", ref.sd = TRUE,
                          sd.method = "population",
                          normalize = TRUE, mar = c(4,4,0,0))
  taylor_from_sds_monthly(obs_sds = silo_means,
                          mod_sds = brown_means,
                          var_name = "tasmax",
                          col_palette = colours[4],
                          use_mask = comm_mask,
                          zones = NULL, add = TRUE,
                          sig_digits = 3, pch = 19,
                          main = "", ref.sd = TRUE,
                          sd.method = "population",
                          normalize = TRUE, mar = c(4,4,0,0))
  taylor_from_sds_monthly(obs_sds = silo_means,
                          mod_sds = brown_means,
                          var_name = "pr",
                          col_palette = colours[1],
                          use_mask = comm_mask,
                          zones = NULL, add = TRUE,
                          sig_digits = 3, pch = 19,
                          main = "", ref.sd = TRUE,
                          sd.method = "population",
                          normalize = TRUE, mar = c(4,4,0,0))

  # taylor_from_sds_monthly(obs_sds = chelsa_trace,
  #                         mod_sds = brown_means,
  #                         var_name = "tas",
  #                         col_palette = colours[2],
  #                         use_mask = comm_mask,
  #                         zones = NULL, add = TRUE,
  #                         sig_digits = 3, pch = 17,
  #                         main = "", ref.sd = TRUE,
  #                         sd.method = "population",
  #                         normalize = TRUE, mar = c(4,4,0,0))
  taylor_from_sds_monthly(obs_sds = chelsa_trace,
                          mod_sds = brown_means,
                          var_name = "tasmin",
                          col_palette = colours[3],
                          use_mask = comm_mask,
                          zones = NULL, add = TRUE,
                          sig_digits = 3, pch = 17,
                          main = "", ref.sd = TRUE,
                          sd.method = "population",
                          normalize = TRUE, mar = c(4,4,0,0))
  taylor_from_sds_monthly(obs_sds = chelsa_trace,
                          mod_sds = brown_means,
                          var_name = "tasmax",
                          col_palette = colours[4],
                          use_mask = comm_mask,
                          zones = NULL, add = TRUE,
                          sig_digits = 3, pch = 17,
                          main = "", ref.sd = TRUE,
                          sd.method = "population",
                          normalize = TRUE, mar = c(4,4,0,0))
  taylor_from_sds_monthly(obs_sds = chelsa_trace,
                          mod_sds = brown_means,
                          var_name = "pr",
                          col_palette = colours[1],
                          use_mask = comm_mask,
                          zones = NULL, add = TRUE,
                          sig_digits = 3, pch = 17,
                          main = "", ref.sd = TRUE,
                          sd.method = "population",
                          normalize = TRUE, mar = c(4,4,0,0))
  legend(x = 0.07, y = 1.5,
         legend = c("precipitation", #"mean temperature",
                    "minimum temperature", "maximum temperature"),
         col = colours,
         pch = 19, box.lwd = 0,box.lty = 0,box.col = NA,
         pt.cex = 1.5,
         ncol = 1)
  legend(x = 0.07, y = 1.25,
         legend = c("Aust. gridded climate data",
                    "CHELSA-TraCE21k"),
         col = "black",
         pch = c(19, 17), box.lwd = 0,box.lty = 0,box.col = NA,
         pt.cex = 1.5, ncol = 1)
  mtext("*each dot represents a single month averaged over 1910-1989",
        side = 3, adj = 0.9, outer = FALSE, line = -2, cex = 0.75)
}
dev.off()
