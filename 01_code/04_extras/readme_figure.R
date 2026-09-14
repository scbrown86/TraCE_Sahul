library(terra)
library(ggplot2)
library(sf)
library(ggnewscale)
library(data.table)
library(patchwork)

# TraCESahul
traceSahul_pr <- rast("/mnt/Data/TraCE-Sahul/30yr_clims/pr/TraCE-Sahul_annual_1500_1990_pr_30yrClim.nc",
                      lyrs = 16)
traceSahul_tas <- 0.5*(rast("/mnt/Data/TraCE-Sahul/30yr_clims/tasmax/TraCE-Sahul_annual_1500_1990_tasmax_30yrClim.nc",
                       lyrs = 16) + 
  rast("/mnt/Data/TraCE-Sahul/30yr_clims/tasmin/TraCE-Sahul_annual_1500_1990_tasmin_30yrClim.nc",
       lyrs = 16))
time(traceSahul_pr) <- time(traceSahul_tas) <- 1989
crs(traceSahul_pr) <- crs(traceSahul_tas) <- "EPSG:4326"
names(traceSahul_pr) <- names(traceSahul_tas) <- "TraCE-Sahul"
traceSahul_pr; traceSahul_tas
plot(traceSahul_pr)
plot(traceSahul_tas)

m1 <- traceSahul_tas[[1]]
m1 <- ifel(!is.na(m1), 1L, NA_integer_)
m1 <- as.polygons(m1)

# CMIP6 data
cmip6_pr <- app(rast("/mnt/Data/CMIP6/CMIP6-Sahul/pr/TraCE-Sahul_ssp585_2015_2100_annualAvg.nc", lyrs = 57:86), mean)
cmip6_pr
cmip6_tas <- 0.5 * (app(rast("/mnt/Data/CMIP6/CMIP6-Sahul/tasmax/TraCE-Sahul_ssp585_2015_2100_annualAvg.nc", lyrs = 57:86), mean) + 
                        app(rast("/mnt/Data/CMIP6/CMIP6-Sahul/tasmin/TraCE-Sahul_ssp585_2015_2100_annualAvg.nc", lyrs = 57:86), mean))
cmip6_tas
crs(cmip6_pr) <- crs(cmip6_tas) <- "EPSG:4326"
names(cmip6_pr) <- names(cmip6_tas) <- "zzCMIP6"

# Raw trace data
trace21_pr <- app(tapp(rast("/media/dafcluster4/storage/TraCE_Decadal/PRECC/trace.01-35.22000BP-1500CE.cam2.h0.PRECC.0000101-258600.Sahul.decavg.concat.nc",
                   lyrs = 25501:25860)*2629800, rep(1:30, each = 12), sum), mean) + 
  app(tapp(rast("/media/dafcluster4/storage/TraCE_Decadal/PRECL/trace.01-35.22000BP-1500CE.cam2.h0.PRECL.0000101-258600.Sahul.decavg.concat.nc",
                lyrs = 25501:25860)*2629800, rep(1:30, each = 12), sum), mean)
trace21_pr <- mask(trace21_pr, m1, touches = TRUE)
trace21_pr <- resample(trace21_pr, traceSahul_pr, "near")
trace21_pr

trace21_tas <- 0.5 * (app(rast("/media/dafcluster4/storage/TraCE_Decadal/TSMX/trace.01-35.22000BP-1500CE.cam2.h0.TSMX.0000101-258600.Sahul.decavg.concat.nc",
                        lyrs = 25500:25860)-273.15, mean) + 
  app(rast("/media/dafcluster4/storage/TraCE_Decadal/TSMN/trace.01-35.22000BP-1500CE.cam2.h0.TSMN.0000101-258600.Sahul.decavg.concat.nc",
           lyrs = 25500:25860)-273.15, mean))
trace21_tas <- mask(trace21_tas, m1, touches = TRUE)
trace21_tas <- resample(trace21_tas, traceSahul_pr, "near")
trace21_tas
crs(trace21_pr) <- crs(trace21_tas) <- "EPSG:4326"
names(trace21_pr) <- names(trace21_tas) <- "TraCE-21ka"

temp <- setDT(as.data.frame(c(traceSahul_tas, trace21_tas, cmip6_tas), xy = TRUE, wide = FALSE))
temp

prec <- setDT(as.data.frame(c(traceSahul_pr, trace21_pr, cmip6_pr), xy = TRUE, wide = FALSE))
prec

temp[, variable := "Temperature"]
prec[, variable := "Precipitation"]

dat <- rbind(temp, prec)
dat <- dat[which(!is.na(dat[["values"]])), ]
m1 <- st_as_sf(m1)

precip_tropical_burst <- c("#FEFCF3", "#DBEFDA", "#B7E0C1", "#7CD1BA", "#00BFC3",
                           "#00A5CA", "#2485D0", "#4967D4", "#6F3BBA", "#970094")

temp_nws <- c("#F8FAFF", "#E8F2FC", "#D4E7F8", "#C0DAF2", "#A8CBEA", "#90BADC",
              "#7BAACE", "#6899BF", "#5788AE", "#1C2D6B", "#1F3878", "#234688", 
              "#3A618C", "#2D6B80", "#2E7070", "#4A7A5A", "#7A8840", "#AAAA30",
              "#C8A020", "#CC7818", "#C04830", "#AE2A50", "#921828", "#760E14",
              "#5C0A0A")

theme_TraCESahul_map <- function() {
  list(coord_sf(
    label_axes = "-NE-",
    #xlim = c(-3351929, 2160860),
    #ylim = c(-2781227, 3195421), 
    expand = FALSE),
    scale_x_continuous(breaks = seq(100,160,10)),
    scale_y_continuous(breaks = seq(-45,15,5)),
    theme_minimal(),
    theme(legend.position = "right",
          # legend.justification = "centre",
          legend.spacing.y = unit(0.5, "lines"),
          legend.spacing.x = unit(0, "mm"),
          legend.box.margin = margin(0, 0, 0, 0, unit = "lines"), 
          legend.margin = margin(-0.2,0,0,0, unit = "lines"),
          legend.title = element_text(colour = "black", size = 10, hjust = 0.5),
          legend.text = element_text(colour = "black", size = 10, hjust = 0.5),
          panel.background = element_rect(colour = "black", fill = NA),
          panel.spacing.x = unit(1, "lines"),
          panel.spacing.y = unit(0.33, "lines"),
          panel.grid = element_line(colour = "grey90", linetype = 2, size = 0.25),
          panel.ontop = TRUE,
          strip.text = element_blank(),
          strip.placement = "outside",
          axis.text = element_text(colour = "black", size = 10),
          axis.ticks = element_line(colour = "black", size = 0.5),
          axis.text.y.left = element_text(colour = "black", size = 10, angle = 90, hjust = 0.5),
          axis.text.y.right = element_text(colour = "black", size = 10, angle = 90, hjust = 0.5)),
    labs(x = NULL, y = NULL))
}

idx <- sample(1:nrow(temp), size = 1000, replace = FALSE)

temp_fig <- ggplot() +
  geom_raster(
    data = temp,
    aes(x = x, y = y, fill = values)) +
  facet_wrap(~layer, ncol = 3) +
  scale_fill_gradientn(colours = temp_nws,
                       limits = c(0, 30),
                       breaks = seq(0, 30, 2),
                       labels = c(seq(0, 28, 2), ">30"),
                       na.value = NA,
                       oob = scales::squish,
                       guide = guide_colourbar(
                         title = "Average annual temperature (°C)",
                         title.position = "right",
                         title.theme = element_text(size = 10, colour = "black",
                                                    angle = 90),
                         title.hjust = 0.5,
                         label.position = "right",
                         label.theme = element_text(size = 10, colour = "black"),
                         label.hjust = 0.5,
                         barwidth = 0.5,
                         barheight = 18,
                         nbin = 256,
                         frame.colour = "black",
                         frame.linewidth = 0.5,
                         ticks = TRUE,
                         ticks.colour = "black",
                         draw.ulim = FALSE,
                         draw.llim = FALSE,
                         direction = "vertical",
                         order = 2)) +
  geom_sf(data = m1, inherit.aes = FALSE, fill = NA, colour = "#000000",
          linewidth = 0.25) +
  theme_TraCESahul_map()
temp_fig

pr_fig <- ggplot() +
  geom_raster(
    data = prec,
    aes(x = x, y = y, fill = values/365)) +
  facet_wrap(~layer, ncol = 3) +
  scale_fill_gradientn(colours = precip_tropical_burst,
                       limits = c(0, 10),
                       transform = "log1p",
                       breaks = seq(0, 10, 1),
                       labels = c(seq(0, 9, 1), ">10"),
                       oob = scales::squish,
                       na.value = NA,
                       guide = guide_colourbar(
                         title = expression(
                           "Total annual precipitation (" *
                             italic(log) *
                             "(mm day"^-1 * ")"
                         ),
                         title.position = "right",
                         title.theme = element_text(size = 10, colour = "black",
                                                    angle = 90),
                         title.hjust = 0.5,
                         label.position = "right",
                         label.theme = element_text(size = 10, colour = "black"),
                         label.hjust = 0.5,
                         barwidth = 0.5,
                         barheight = 18,
                         nbin = 256,
                         frame.colour = "black",
                         frame.linewidth = 0.5,
                         ticks = TRUE,
                         ticks.colour = "black",
                         draw.ulim = FALSE,
                         draw.llim = FALSE,
                         direction = "vertical",
                         order = 1)) +
  geom_sf(data = m1, inherit.aes = FALSE, fill = NA, colour = "#000000",
          linewidth = 0.25) +
  theme_TraCESahul_map()
pr_fig

combined <- temp_fig / pr_fig
ragg::agg_png(filename = sprintf("~/Desktop/TraCE-Sahul_animations/combined_figure.png"),
              width = 12, height = 8.5,
              units = "in", res = 350)
print(combined)
dev.off()
