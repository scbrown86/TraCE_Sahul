library(terra)
library(data.table)
library(ggplot2)
library(sf)
library(pbapply)

# projection
wkt_proj <- 'PROJCS["Sahul_Lambert_Azimuthal",
  GEOGCS["GCS_WGS_1984",
  DATUM["D_WGS_1984",
  SPHEROID["WGS_1984",6378137.0,298.257223563]],
  PRIMEM["Greenwich",0.0],
  UNIT["Degree",0.0174532925199433]],
  PROJECTION["Lambert_Azimuthal_Equal_Area"],
  PARAMETER["False_Easting",0.0],
  PARAMETER["False_Northing",0.0],
  PARAMETER["Central_Meridian",135],
  PARAMETER["Latitude_Of_Origin",-20],
  UNIT["Meter",1.0]]'

format_year <- function(yr) {
  year <- yr + 1
  if (abs(year) >= 10000) {
    year <- format(year, big.mark = ",", scientific = FALSE)
  } else {
    year <- as.character(year)
  }
  sprintf("%s C.E", year)
}

# /mnt/Data/TraCE-Sahul/30yr_clims/pr/
pr <- c(rast("/mnt/Data/TraCE-Sahul/30yr_clims/pr/TraCE-Sahul_decadal_22k_1500CE_pr_30yrClim.nc"),
        rast("/mnt/Data/TraCE-Sahul/30yr_clims/pr/TraCE-Sahul_annual_1500_1990_pr_30yrClim.nc"))
time(pr) <- seq(to = 1989, by = 30, l = nlyr(pr))
units(pr) <- "mm/year"
crs(pr) <- "EPSG:4326"
pr

# proj template
prj_tmp <- project(pr[[1]], wkt_proj, res = 5000)
res(prj_tmp) <- c(5000, 5000)
prj_tmp

tasmax <- c(rast("/mnt/Data/TraCE-Sahul/30yr_clims/tasmax/TraCE-Sahul_decadal_22k_1500CE_tasmax_30yrClim.nc"),
            rast("/mnt/Data/TraCE-Sahul/30yr_clims/tasmax/TraCE-Sahul_annual_1500_1990_tasmax_30yrClim.nc"))
time(tasmax) <- time(pr)
units(tasmax) <- "°C"
crs(tasmax) <- "EPSG:4326"
tasmax

tasmin <- c(rast("/mnt/Data/TraCE-Sahul/30yr_clims/tasmin/TraCE-Sahul_decadal_22k_1500CE_tasmin_30yrClim.nc"),
            rast("/mnt/Data/TraCE-Sahul/30yr_clims/tasmin/TraCE-Sahul_annual_1500_1990_tasmin_30yrClim.nc"))
time(tasmin) <- time(pr)
units(tasmin) <- "°C"
crs(tasmin) <- "EPSG:4326"
tasmin

# precipitation (sequential) from https://dominicroye.github.io/color-for-geoscience/
precip_tropical_burst <- c("#FEFCF3", "#DBEFDA", "#B7E0C1", "#7CD1BA", "#00BFC3",
                           "#00A5CA", "#2485D0", "#4967D4", "#6F3BBA", "#970094")

theme_TraCESahul_map <- function() {
  list(coord_sf(
    label_axes = "-NE-",
    xlim = c(-3351929, 2160860),
    ylim = c(-2781227, 3195421), expand = FALSE),
      scale_x_continuous(breaks = seq(100,160,10)),
      scale_y_continuous(breaks = seq(-45,15,5)),
      theme_minimal(),
      theme(legend.position = "bottom",
            legend.justification = "centre",
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
            strip.text = element_text(size = 10, colour = "black", hjust = 0),
            strip.placement = "outside",
            axis.text = element_text(colour = "black", size = 10),
            axis.ticks = element_line(colour = "black", size = 0.5),
            axis.text.y.left = element_text(colour = "black", size = 10, angle = 90, hjust = 0.5),
            axis.text.y.right = element_text(colour = "black", size = 10, angle = 90, hjust = 0.5)),
      labs(x = NULL, y = NULL))
}

pbsapply(1:nlyr(pr), function(i) {
  m <- pr[[i]]
  m <- terra::project(m, prj_tmp, method = "bilinear")
  yr <- time(m)
  v <- sf::st_as_sf(as.polygons(ifel(!is.na(m), 1L, NA_integer_)))
  dt <- setDT(as.data.frame(m, xy = TRUE, na.rm = TRUE))
  colnames(dt)[3] <- "value"
  p <- ggplot() +
    geom_tile(data = dt, aes(x = x, y = y, fill = value)) +
    scale_fill_gradientn(colours = precip_tropical_burst,
                         limits = c(0, 3500),
                         breaks = seq(0, 3500, 500),
                         labels = c(seq(0, 3000, 500), ">3500"),
                         oob = scales::squish,
                         guide = guide_colourbar(
                           title = "Total annual precipitation (mm/year)",
                           title.position = "top",
                           title.theme = element_text(size = 10, colour = "black"),
                           title.hjust = 0.5,
                           label.position = "bottom",
                           label.theme = element_text(size = 10, colour = "black"),
                           label.hjust = 0.5,
                           barwidth = 20,
                           barheight = 0.8,
                           nbin = 256,
                           frame.colour = "black",
                           frame.linewidth = 0.5,
                           ticks = TRUE,
                           ticks.colour = "black",
                           draw.ulim = FALSE,
                           draw.llim = FALSE,
                           direction = "horizontal"
                         )) +
    geom_sf(data = v, inherit.aes = FALSE, fill = NA, colour = "#000000",
            linewidth = 0.25) +
    annotate("text", label = format_year(yr),
             x = -2995114, y = -2442253, hjust = 0, vjust = 0, size = 4,
             colour = "#000000")
  ragg::agg_png(filename = sprintf("~/Desktop/TraCE-Sahul_animations/pr/frame_%04d.png", i),
                width = 6, height = 7,
                units = "in", res = 350)
  print(p + theme_TraCESahul_map())
  dev.off()
  return(NULL)
}, cl = 48L)

# temp colour scale from https://dominicroye.github.io/color-for-geoscience/
temp_nws <- c("#F8FAFF", "#E8F2FC", "#D4E7F8", "#C0DAF2", "#A8CBEA", "#90BADC",
              "#7BAACE", "#6899BF", "#5788AE", "#1C2D6B", "#1F3878", "#234688", 
              "#3A618C", "#2D6B80", "#2E7070", "#4A7A5A", "#7A8840", "#AAAA30",
              "#C8A020", "#CC7818", "#C04830", "#AE2A50", "#921828", "#760E14",
              "#5C0A0A")


pbsapply(1:nlyr(tasmax), function(i) {
  m <- 0.5*(tasmax[[i]] + tasmin[[i]])
  m <- terra::project(m, prj_tmp, method = "bilinear")
  yr <- time(m)
  v <- sf::st_as_sf(as.polygons(ifel(!is.na(m), 1L, NA_integer_)))
  dt <- setDT(as.data.frame(m, xy = TRUE, na.rm = TRUE))
  colnames(dt)[3] <- "value"
  p <- ggplot() +
    geom_tile(data = dt, aes(x = x, y = y, fill = value)) +
    scale_fill_gradientn(colours = temp_nws,
                         limits = c(0, 30),
                         breaks = seq(0, 30, 2),
                         labels = c(seq(0, 28, 2), ">30"),
                         oob = scales::squish,
                         guide = guide_colourbar(
                           title = "Average annual temperature (°C)",
                           title.position = "top",
                           title.theme = element_text(size = 10, colour = "black"),
                           title.hjust = 0.5,
                           label.position = "bottom",
                           label.theme = element_text(size = 10, colour = "black"),
                           label.hjust = 0.5,
                           barwidth = 20,
                           barheight = 0.8,
                           nbin = 256,
                           frame.colour = "black",
                           frame.linewidth = 0.5,
                           ticks = TRUE,
                           ticks.colour = "black",
                           draw.ulim = FALSE,
                           draw.llim = FALSE,
                           direction = "horizontal"
                         )) +
    geom_sf(data = v, inherit.aes = FALSE, fill = NA, colour = "#000000",
            linewidth = 0.25) +
    annotate("text", label = format_year(yr),
             x = -2995114, y = -2442253, hjust = 0, vjust = 0, size = 4,
             colour = "#000000")
  ragg::agg_png(filename = sprintf("~/Desktop/TraCE-Sahul_animations/tas/frame_%04d.png", i),
                width = 6, height = 7,
                units = "in", res = 350)
  print(p + theme_TraCESahul_map())
  dev.off()
  return(NULL)
}, cl = 48L)


# Combine both datasets using FFMPEG
# ffmpeg \
# -framerate 6 -i pr/frame_%04d.png \
# -framerate 6 -i tas/frame_%04d.png \
# -filter_complex "[0:v][1:v]hstack=inputs=2,tpad=start_mode=clone:start_duration=5:stop_mode=clone:stop_duration=5[v]" \
# -map "[v]" \
# -c:v libx264 \
# -preset slow \
# -crf 16 \
# -pix_fmt yuv420p \
# TraCESahul_annual_climate.mp4

# Read in the CMIP6 data

format_year <- function(yr) {
  year <- yr# + 1
  if (abs(year) >= 10000) {
    year <- format(year, big.mark = ",", scientific = FALSE)
  } else {
    year <- as.character(year)
  }
  sprintf("%s C.E", year)
}


cmip6_pr <- sds(c(rast("/mnt/Data/CMIP6/CMIP6-Sahul/pr/TraCE-Sahul_historical_1990_2014_annualAvg.nc"),
                           rast("/mnt/Data/CMIP6/CMIP6-Sahul/pr/TraCE-Sahul_ssp126_2015_2100_annualAvg.nc")),
                c(rast("/mnt/Data/CMIP6/CMIP6-Sahul/pr/TraCE-Sahul_historical_1990_2014_annualAvg.nc"),
                           rast("/mnt/Data/CMIP6/CMIP6-Sahul/pr/TraCE-Sahul_ssp245_2015_2100_annualAvg.nc")),
                c(rast("/mnt/Data/CMIP6/CMIP6-Sahul/pr/TraCE-Sahul_historical_1990_2014_annualAvg.nc"),
                           rast("/mnt/Data/CMIP6/CMIP6-Sahul/pr/TraCE-Sahul_ssp370_2015_2100_annualAvg.nc")),
                c(rast("/mnt/Data/CMIP6/CMIP6-Sahul/pr/TraCE-Sahul_historical_1990_2014_annualAvg.nc"),
                           rast("/mnt/Data/CMIP6/CMIP6-Sahul/pr/TraCE-Sahul_ssp585_2015_2100_annualAvg.nc")))
names(cmip6_pr) <- c("ssp126", "ssp245", "ssp370", "ssp585")
time(cmip6_pr) <- seq(1990, by = 1, l = nlyr(cmip6_pr$ssp126))
cmip6_pr

pbsapply(1:nlyr(cmip6_pr$ssp126), function(i) {
  m <- c(cmip6_pr$ssp126[[i]], cmip6_pr$ssp245[[i]],
         cmip6_pr$ssp370[[i]], cmip6_pr$ssp585[[i]])
  m <- terra::project(m, prj_tmp, method = "bilinear")
  yr <- time(m)[1]
  v <- sf::st_as_sf(as.polygons(ifel(!is.na(m[[1]]), 1L, NA_integer_)))
  dt <- setDT(as.data.frame(m, xy = TRUE, na.rm = TRUE, wide = TRUE))
  colnames(dt)[-c(1:2)] <- names(cmip6_pr)
  dt <- data.table::melt(dt, id.vars = c("x", "y"))
  dt[, Scen := factor(c(ssp126 = "SSP1-2.6",
                        ssp245 = "SSP2-4.5",
                        ssp370 = "SSP3-7.0",
                        ssp585 = "SSP5-8.5")[variable],
                      levels = c("SSP1-2.6", "SSP2-4.5", "SSP3-7.0", "SSP5-8.5"))]
  label_df <- data.frame(
    Scen = "SSP3-7.0",
    x = -2995114,
    y = -2442253,
    label = format_year(yr))
  p <- ggplot() +
    geom_tile(data = dt, aes(x = x, y = y, fill = value)) +
    facet_wrap(~Scen, ncol = 2) +
    scale_fill_gradientn(colours = precip_tropical_burst,
                         limits = c(0, 3500),
                         breaks = seq(0, 3500, 500),
                         labels = c(seq(0, 3000, 500), ">3500"),
                         oob = scales::squish,
                         guide = guide_colourbar(
                           title = "Total annual precipitation (mm/year)",
                           title.position = "top",
                           title.theme = element_text(size = 10, colour = "black"),
                           title.hjust = 0.5,
                           label.position = "bottom",
                           label.theme = element_text(size = 10, colour = "black"),
                           label.hjust = 0.5,
                           barwidth = 20,
                           barheight = 0.8,
                           nbin = 256,
                           frame.colour = "black",
                           frame.linewidth = 0.5,
                           ticks = TRUE,
                           ticks.colour = "black",
                           draw.ulim = FALSE,
                           draw.llim = FALSE,
                           direction = "horizontal"
                         )) +
    geom_sf(data = v, inherit.aes = FALSE, fill = NA, colour = "#000000",
            linewidth = 0.25) +
    geom_text(
      data = label_df, aes(x = x, y = y, label = label),
      hjust = 0, vjust = 0, size = 4, colour = "#000000")
  ragg::agg_png(filename = sprintf("~/Desktop/TraCE-Sahul_animations/pr/frame_cmip6_%04d.png", i),
                width = 9, height = 10.5,
                units = "in", res = 350)
  print(p + theme_TraCESahul_map())
  dev.off()
  return(NULL)
}, cl = 48L)


cmip6_tasmax <- sds(c(rast("/mnt/Data/CMIP6/CMIP6-Sahul/tasmax/TraCE-Sahul_historical_1990_2014_annualAvg.nc"),
                  rast("/mnt/Data/CMIP6/CMIP6-Sahul/tasmax/TraCE-Sahul_ssp126_2015_2100_annualAvg.nc")),
                c(rast("/mnt/Data/CMIP6/CMIP6-Sahul/tasmax/TraCE-Sahul_historical_1990_2014_annualAvg.nc"),
                  rast("/mnt/Data/CMIP6/CMIP6-Sahul/tasmax/TraCE-Sahul_ssp245_2015_2100_annualAvg.nc")),
                c(rast("/mnt/Data/CMIP6/CMIP6-Sahul/tasmax/TraCE-Sahul_historical_1990_2014_annualAvg.nc"),
                  rast("/mnt/Data/CMIP6/CMIP6-Sahul/tasmax/TraCE-Sahul_ssp370_2015_2100_annualAvg.nc")),
                c(rast("/mnt/Data/CMIP6/CMIP6-Sahul/tasmax/TraCE-Sahul_historical_1990_2014_annualAvg.nc"),
                  rast("/mnt/Data/CMIP6/CMIP6-Sahul/tasmax/TraCE-Sahul_ssp585_2015_2100_annualAvg.nc")))
names(cmip6_tasmax) <- c("ssp126", "ssp245", "ssp370", "ssp585")
time(cmip6_tasmax) <- seq(1990, by = 1, l = nlyr(cmip6_tasmax$ssp126))
cmip6_tasmax

cmip6_tasmin <- sds(c(rast("/mnt/Data/CMIP6/CMIP6-Sahul/tasmin/TraCE-Sahul_historical_1990_2014_annualAvg.nc"),
                      rast("/mnt/Data/CMIP6/CMIP6-Sahul/tasmin/TraCE-Sahul_ssp126_2015_2100_annualAvg.nc")),
                    c(rast("/mnt/Data/CMIP6/CMIP6-Sahul/tasmin/TraCE-Sahul_historical_1990_2014_annualAvg.nc"),
                      rast("/mnt/Data/CMIP6/CMIP6-Sahul/tasmin/TraCE-Sahul_ssp245_2015_2100_annualAvg.nc")),
                    c(rast("/mnt/Data/CMIP6/CMIP6-Sahul/tasmin/TraCE-Sahul_historical_1990_2014_annualAvg.nc"),
                      rast("/mnt/Data/CMIP6/CMIP6-Sahul/tasmin/TraCE-Sahul_ssp370_2015_2100_annualAvg.nc")),
                    c(rast("/mnt/Data/CMIP6/CMIP6-Sahul/tasmin/TraCE-Sahul_historical_1990_2014_annualAvg.nc"),
                      rast("/mnt/Data/CMIP6/CMIP6-Sahul/tasmin/TraCE-Sahul_ssp585_2015_2100_annualAvg.nc")))
names(cmip6_tasmin) <- c("ssp126", "ssp245", "ssp370", "ssp585")
time(cmip6_tasmin) <- seq(1990, by = 1, l = nlyr(cmip6_tasmin$ssp126))
cmip6_tasmin

pbsapply(1:nlyr(cmip6_tasmax$ssp126), function(i) {
  m <- 0.5 * (c(cmip6_tasmax$ssp126[[i]], cmip6_tasmax$ssp245[[i]],
                cmip6_tasmax$ssp370[[i]], cmip6_tasmax$ssp585[[i]]) +
              c(cmip6_tasmin$ssp126[[i]], cmip6_tasmin$ssp245[[i]],
                cmip6_tasmin$ssp370[[i]], cmip6_tasmin$ssp585[[i]]))
  m <- terra::project(m, prj_tmp, method = "bilinear")
  yr <- time(m)[1]
  v <- sf::st_as_sf(as.polygons(ifel(!is.na(m[[1]]), 1L, NA_integer_)))
  dt <- setDT(as.data.frame(m, xy = TRUE, na.rm = TRUE, wide = TRUE))
  colnames(dt)[-c(1:2)] <- names(cmip6_pr)
  dt <- data.table::melt(dt, id.vars = c("x", "y"))
  dt[, Scen := factor(c(ssp126 = "SSP1-2.6",
                        ssp245 = "SSP2-4.5",
                        ssp370 = "SSP3-7.0",
                        ssp585 = "SSP5-8.5")[variable],
                      levels = c("SSP1-2.6", "SSP2-4.5", "SSP3-7.0", "SSP5-8.5"))]
  label_df <- data.frame(
    Scen = "SSP3-7.0",
    x = -2995114,
    y = -2442253,
    label = format_year(yr))
  p <- ggplot() +
    geom_tile(data = dt, aes(x = x, y = y, fill = value)) +
    facet_wrap(~Scen, ncol = 2) +
    scale_fill_gradientn(colours = temp_nws,
                         limits = c(0, 30),
                         breaks = seq(0, 30, 2),
                         labels = c(seq(0, 28, 2), ">30"),
                         oob = scales::squish,
                         guide = guide_colourbar(
                           title = "Average annual temperature (°C)",
                           title.position = "top",
                           title.theme = element_text(size = 10, colour = "black"),
                           title.hjust = 0.5,
                           label.position = "bottom",
                           label.theme = element_text(size = 10, colour = "black"),
                           label.hjust = 0.5,
                           barwidth = 20,
                           barheight = 0.8,
                           nbin = 256,
                           frame.colour = "black",
                           frame.linewidth = 0.5,
                           ticks = TRUE,
                           ticks.colour = "black",
                           draw.ulim = FALSE,
                           draw.llim = FALSE,
                           direction = "horizontal"
                         )) +
    geom_sf(data = v, inherit.aes = FALSE, fill = NA, colour = "#000000",
            linewidth = 0.25) +
    geom_text(
      data = label_df, aes(x = x, y = y, label = label),
      hjust = 0, vjust = 0, size = 4, colour = "#000000")
  ragg::agg_png(filename = sprintf("~/Desktop/TraCE-Sahul_animations/tas/frame_cmip6_%04d.png", i),
                width = 9, height = 10.5,
                units = "in", res = 350)
  print(p + theme_TraCESahul_map())
  dev.off()
  return(NULL)
}, cl = 48L)

# Combine both datasets using FFMPEG
# ffmpeg \
# -framerate 2 -i pr/frame_cmip6_%04d.png \
# -framerate 2 -i tas/frame_cmip6_%04d.png \
# -filter_complex "[0:v][1:v]hstack=inputs=2,pad=iw:ceil(ih/2)*2,tpad=start_mode=clone:start_duration=3:stop_mode=clone:stop_duration=3[v]" \
# -map "[v]" \
# -c:v libx264 \
# -preset slow \
# -crf 16 \
# -pix_fmt yuv420p \
# CMIP6Sahul_annual_climate.mp4