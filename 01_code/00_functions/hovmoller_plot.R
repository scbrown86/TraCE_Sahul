# Make a Hovmöller (latitude–time) plot from a SpatRaster
hovmoller_plot <- function(ras, zones = NULL, fun = mean, value_name = "value",
                           palette_fun = viridis::turbo, n_colours = 100,
                           fill_limits = c(25, 28),
                           fill_breaks = seq(25, 28, 1),
                           fill_title = "Zonal value", 
                           x_label = "Year", y_label = "Latitude",
                           theme_fun = theme_bw()) {
  stopifnot(inherits(ras, "SpatRaster"))
  if (is.null(zones)) zones <- terra::init(ras, "y")
  zonal_means <- data.table::setDT(terra::zonal(ras, zones, fun, na.rm = TRUE))
  data.table::setnames(zonal_means, 1L, "lat")
  zonal_means <- data.table::melt(zonal_means, id.vars = "lat", 
                                  variable.name = "time", 
                                  value.name = value_name)
  if (value_name != "value") {
    data.table::setnames(zonal_means, value_name, "value")
  }
  # make the plot
  ggplot(zonal_means) +
    geom_raster(aes(x = time, y = lat, fill = value)) +
    scale_fill_gradientn(
      colours = palette_fun(n_colours), limits = fill_limits, 
      breaks = fill_breaks, labels = fill_breaks, oob = scales::squish,
      guide = guide_colourbar(
        title = fill_title, title.position = "top",
        title.theme = element_text(size = 8, colour = "black"), 
        title.hjust = 0.5, label.position = "bottom", 
        label.theme = element_text(size = 8, colour = "black"),
        label.hjust = 0.5, barwidth = unit(15, "lines"), 
        barheight = unit(0.5, "lines"), nbin = n_colours, 
        frame.colour = "black", frame.linewidth = 0.5,
        ticks = TRUE, ticks.colour = "black", ticks.linewidth = 0.5,
        draw.ulim = TRUE, draw.llim = TRUE, direction = "horizontal")) +
    scale_x_discrete(expand = c(0, 0)) +
    scale_y_continuous(expand = c(0, 0), breaks = scales::pretty_breaks(n = 6),
                       oob = scales::squish, limits = range(zonal_means$lat)) +
    labs(x = x_label, y = y_label) +
    theme_fun +
    theme(
      legend.position = "bottom", legend.margin = margin(-5, 0, 0, 0),
      legend.background = element_blank(), legend.justification = "center",
      axis.text.y = element_text(size = 8, colour = "black", angle = 90, hjust = 0.5),
      axis.text.x = element_text(size = 8, colour = "black", hjust = 0.5),
      axis.ticks = element_line(colour = "black", size = 0.5),
      panel.border = element_rect(size = 0.5, fill = NA, colour = "black"),
      strip.background = element_blank(),
      strip.text = element_text(size = 12, face = "bold", colour = "black", hjust = 0)
    )
}
