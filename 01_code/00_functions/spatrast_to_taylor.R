taylor_from_spatraster <- function(obs, mod, add = FALSE, ...) {
  require(terra)
  require(plotrix)
  obs_vals <- values(obs)
  mod_vals <- values(mod)
  # Remove rows with NA in either obs or mod
  valid_idx <- complete.cases(obs_vals, mod_vals)
  obs_clean <- obs_vals[valid_idx]
  mod_clean <- mod_vals[valid_idx]
  df <- data.frame(obs = obs_clean, mod = mod_clean)
  taylor.diagram(ref = df$obs, model = df$mod, add = add, ...)
  invisible(df)
}

taylor_from_spatraster_zones <- function(obs, mod, zones = NULL, add = FALSE,
                                         zone_names = NULL, col_palette = NULL,
                                         doagg  = NULL, sig_digits = NULL,
                                         ...) {
  # Check input types
  if (!inherits(obs, "SpatRaster") || !inherits(mod, "SpatRaster")) {
    stop("Both 'obs' and 'mod' must be SpatRaster objects.")
  }
  if (!is.null(zones) && !inherits(zones, "SpatRaster")) {
    stop("'zones' must be a SpatRaster object or NULL.")
  }
  if (!is.null(zones) && !compareGeom(obs, zones, stopOnError = FALSE)) {
    stop("The 'zones' raster must match the geometry of 'obs' and 'mod'.")
  }
  if (!is.null(sig_digits) &&
      (!is.numeric(sig_digits) || length(sig_digits) != 1L || sig_digits < 1))
    stop("'sig_digits' must be a single positive integer or NULL.")
  ## helper for optional rounding -----------------
  round_sig <- function(x) {
    if (is.null(sig_digits)) x else signif(x, sig_digits)
  }
  # No zones? Plot the global Taylor diagram
  if (is.null(zones)) {
    obs_vals <- values(obs, mat = FALSE)
    mod_vals <- values(mod, mat = FALSE)
    valid_idx <- complete.cases(obs_vals, mod_vals)
    df <- data.frame(obs = round_sig(obs_vals[valid_idx]),
                     mod = round_sig(mod_vals[valid_idx]))
    taylor_diagram(df$obs, df$mod, add = add, pos.cor = TRUE, col = "black",
                   ref.sd = TRUE,
                   sd.arcs = TRUE,
                   normalize = TRUE,
                   sd.method = "sample",
                   show.gamma = FALSE, ...)
    return(invisible(df))
  }
  # Handle zones
  zone_values <- sort(unique(na.omit(values(zones))))
  n_zones <- length(zone_values)
  # Use zone_names or default to zone values
  if (is.null(zone_names)) {
    zone_labels <- as.character(zone_values)
  } else {
    if (length(zone_names) != n_zones) {
      stop("Length of 'zone_names' must match the number of unique zones.")
    }
    zone_labels <- zone_names
  }
  # Store zone-wise data if needed
  results <- list()
  for (i in seq_along(zone_values)) {
    zone_val <- zone_values[i]
    zone_mask <- ifel(zones == zone_val, 1, NA)
    obs_masked <- mask(obs, zone_mask)
    mod_masked <- mask(mod, zone_mask)

    if (!is.null(doagg)) {
      obs_masked <- terra::aggregate(obs_masked, fact = doagg, na.rm = TRUE)
      mod_masked <- terra::aggregate(mod_masked, fact = doagg, na.rm = TRUE)
    }

    obs_vals <- values(obs_masked, mat = FALSE)
    mod_vals <- values(mod_masked, mat = FALSE)

    valid_idx <- complete.cases(obs_vals, mod_vals)
    obs_clean <- round_sig(obs_vals[valid_idx])
    mod_clean <- round_sig(mod_vals[valid_idx])

    if (length(obs_clean) < 2 || length(mod_clean) < 2) {
      warning(paste("Zone", zone_val, "has insufficient valid data and was skipped."))
      next
    }
    # Save data
    df_zone <- data.frame(obs = obs_clean, mod = mod_clean)
    results[[zone_labels[i]]] <- df_zone
    # Plot
    taylor_diagram(df_zone$obs, df_zone$mod,
                   add = add || (i > 1), # only the first zone can initiate the plot
                   col = col_palette[i],
                   pos.cor = TRUE,
                   ref.sd = TRUE,
                   sd.arcs = TRUE,
                   normalize = TRUE,
                   sd.method = "sample",
                   show.gamma = FALSE,
                   ...)
  }
  # Return list of zone-wise data frames invisibly
  invisible(results)
}

taylor_from_sds_monthly <- function(obs_sds, mod_sds, var_name, zones = NULL,
                                    use_mask = NULL,
                                    add = FALSE, col_palette = NULL,
                                    sig_digits = NULL, zone_names = NULL,
                                    doagg = NULL, ...) {
  # ----- Checks -----
  if (!inherits(obs_sds, "SpatRasterDataset") || !inherits(mod_sds, "SpatRasterDataset")) {
    stop("Both 'obs_sds' and 'mod_sds' must be terra::sds objects.")
  }
  if (!(var_name %in% names(obs_sds)) || !(var_name %in% names(mod_sds))) {
    stop("The specified 'var_name' must be present in both SDS objects.")
  }
  if (is.null(col_palette)) {
    col_palette <- grDevices::rainbow(12)
  }
  get_color <- function(i) {
    if (is.null(col_palette)) return("black")
    if (length(col_palette) > 1) return(col_palette[i])
    return(col_palette)
  }

  round_sig <- function(x) {
    if (is.null(sig_digits)) x else signif(x, sig_digits)
  }

  # Extract var from each sds and mask if needed
  obs_stack <- obs_sds[[var_name]]
  mod_stack <- mod_sds[[var_name]]
    if (!is.null(use_mask)) {
    obs_stack <- mask(obs_stack, use_mask)
    mod_stack <- mask(mod_stack, use_mask)
  }
  # obs_stack and mod_stack should each be SpatRaster with 12 layers
  if (terra::nlyr(obs_stack) != 12 || terra::nlyr(mod_stack) != 12) {
    stop("Expected 12 layers per stack for 12 months. Check input SDS structure.")
  }
  month_labels <- month.abb
  plot_index <- 1  # to control `add` to existing plot

  for (i in 1:12) {
    obs_layer <- obs_stack[[i]]
    mod_layer <- mod_stack[[i]]

    if (!is.null(zones)) {
      # Zonal version
      zone_vals  <- sort(unique(na.omit(values(zones))))
      n_zones    <- length(zone_vals)
      for (z in seq_along(zone_vals)) {
        zval  <- zone_vals[z]
        zmask <- ifel(zones == zval, 1, NA)
        obs_masked <- mask(obs_layer, zmask)
        mod_masked <- mask(mod_layer, zmask)
        if (!is.null(doagg)) {
          obs_masked <- terra::aggregate(obs_masked, fact = doagg, na.rm = TRUE)
          mod_masked <- terra::aggregate(mod_masked, fact = doagg, na.rm = TRUE)
        }
        obs_vals <- values(obs_masked, mat = FALSE)
        mod_vals <- values(mod_masked, mat = FALSE)
        valid    <- complete.cases(obs_vals, mod_vals)
        obs_clean <- round_sig(obs_vals[valid])
        mod_clean <- round_sig(mod_vals[valid])
        if (length(obs_clean) < 2L) {
          warning(sprintf("Month %s / Zone %s skipped: insufficient data.", month_labels[i], zval))
          next
        }
        taylor.diagram(obs_clean, mod_clean,
                       add = add || (plot_index > 1L),
                       col = get_color(i),
                       ...)
        plot_index <- plot_index + 1
      }
    } else {
      # Global version
      obs_vals <- values(obs_layer, mat = FALSE)
      mod_vals <- values(mod_layer, mat = FALSE)
      valid    <- complete.cases(obs_vals, mod_vals)
      obs_clean <- round_sig(obs_vals[valid])
      mod_clean <- round_sig(mod_vals[valid])
      if (length(obs_clean) < 2L) {
        warning(sprintf("Month %s skipped: insufficient valid data.", month_labels[i]))
        next
      }
      taylor.diagram(obs_clean, mod_clean,
                     add  = add || (plot_index > 1L),
                     col = get_color(i),
                     ...)
      plot_index <- plot_index + 1
    }
  }
  invisible(NULL)
}


taylor_diagram <- function (ref, model, add = FALSE, col = "red", pch = 19, pos.cor = TRUE,
                            xlab = "Standard deviation", ylab = "", main = "Taylor Diagram",
                            show.gamma = TRUE, ngamma = 3, gamma.col = 8, sd.arcs = 0,
                            ref.sd = FALSE, sd.method = "sample",
                            grad.corr.lines = c(0.2,0.4, 0.6, 0.8, 0.9),
                            pcex = 1, cex.axis = 1, normalize = FALSE,
                            mar = c(4, 3, 4, 3), ...) {
  grad.corr.full <- c(0, 0.2, 0.4, 0.6, 0.8, 0.9, 0.95, 0.99,1)
  R <- cor(ref, model, use = "pairwise", method = "pearson")
  if (is.list(ref))
    ref <- unlist(ref)
  if (is.list(model))
    ref <- unlist(model)
  SD <- function(x, subn) {
    meanx <- mean(x, na.rm = TRUE)
    devx <- x - meanx
    ssd <- sqrt(sum(devx * devx, na.rm = TRUE)/(length(x[!is.na(x)]) - subn))
    return(ssd)
  }
  subn <- sd.method != "sample"
  sd.r <- SD(ref, subn)
  sd.f <- SD(model, subn)
  if (normalize) {
    sd.f <- sd.f/sd.r
    sd.r <- 1
  }
  maxsd <- 1.5 * max(sd.f, sd.r)
  oldpar <- par("mar", "xpd", "xaxs", "yaxs")
  if (!add) {
    par(mar = mar)
    if (pos.cor) {
      if (nchar(ylab) == 0)
        ylab = "Standard deviation"
      plot(0, xlim = c(0, maxsd * 1.1),
           ylim = c(0, maxsd * 1.1), xaxs = "i", yaxs = "i", axes = FALSE,
           main = main, xlab = "", ylab = ylab, type = "n",
           cex = cex.axis, ...)
      mtext(xlab, side = 1, line = 2.3)
      if (grad.corr.lines[1]) {
        for (gcl in grad.corr.lines) lines(c(0, maxsd * gcl),
                                           c(0, maxsd * sqrt(1 - gcl^2)),
                                           lty = 3)
      }
      segments(c(0, 0), c(0, 0), c(0, maxsd), c(maxsd, 0))
      axis.ticks <- pretty(c(0, maxsd))
      axis.ticks <- axis.ticks[axis.ticks <= maxsd]
      axis(1, at = axis.ticks, cex.axis = cex.axis)
      axis(2, at = axis.ticks, cex.axis = cex.axis)
      if (sd.arcs[1]) {
        if (length(sd.arcs) == 1)
          sd.arcs <- axis.ticks
        for (sdarc in sd.arcs) {
          xcurve <- cos(seq(0, pi/2, by = 0.03)) * sdarc
          ycurve <- sin(seq(0, pi/2, by = 0.03)) * sdarc
          lines(xcurve, ycurve, col = "blue", lty = 3)
        }
      }
      if (show.gamma[1]) {
        if (length(show.gamma) > 1)
          gamma <- show.gamma
        else gamma <- pretty(c(0, maxsd), n = ngamma)[-1]
        if (gamma[length(gamma)] > maxsd)
          gamma <- gamma[-length(gamma)]
        labelpos <- seq(45, 70, length.out = length(gamma))
        for (gindex in 1:length(gamma)) {
          xcurve <- cos(seq(0, pi, by = 0.03)) * gamma[gindex] +
            sd.r
          endcurve <- which(xcurve < 0)
          endcurve <- ifelse(length(endcurve), min(endcurve) -
                               1, 105)
          ycurve <- sin(seq(0, pi, by = 0.03)) * gamma[gindex]
          maxcurve <- xcurve * xcurve + ycurve * ycurve
          startcurve <- which(maxcurve > maxsd * maxsd)
          startcurve <- ifelse(length(startcurve), max(startcurve) + 1, 0)
          lines(xcurve[startcurve:endcurve], ycurve[startcurve:endcurve],
                col = gamma.col)
          if (xcurve[labelpos[gindex]] > 0)
            boxed.labels(xcurve[labelpos[gindex]], ycurve[labelpos[gindex]],
                         gamma[gindex], border = FALSE)
        }
      }
      xcurve <- cos(seq(0, pi/2, by = 0.01)) * maxsd
      ycurve <- sin(seq(0, pi/2, by = 0.01)) * maxsd
      lines(xcurve, ycurve)
      bigtickangles <- acos(seq(0.1, 0.9, by = 0.1))
      medtickangles <- acos(seq(0.05, 0.95, by = 0.1))
      smltickangles <- acos(seq(0.91, 0.99, by = 0.01))
      segments(cos(bigtickangles) * maxsd, sin(bigtickangles) *
                 maxsd, cos(bigtickangles) * 0.97 * maxsd, sin(bigtickangles) *
                 0.97 * maxsd)
      par(xpd = TRUE)
      if (ref.sd) {
        xcurve <- cos(seq(0, pi/2, by = 0.01)) * sd.r
        ycurve <- sin(seq(0, pi/2, by = 0.01)) * sd.r
        lines(xcurve, ycurve)
      }
      points(sd.r, 0, cex = pcex)
      text(cos(c(bigtickangles, acos(c(0.95, 0.99)))) *
             1.05 * maxsd,
           sin(c(bigtickangles, acos(c(0.95, 0.99)))) * 1.05 * maxsd,
           c(seq(0.1, 0.9, by = 0.1), 0.95, 0.99), cex = cex.axis)
      segments(cos(medtickangles) * maxsd, sin(medtickangles) *
                 maxsd, cos(medtickangles) * 0.98 * maxsd, sin(medtickangles) *
                 0.98 * maxsd)
      segments(cos(smltickangles) * maxsd, sin(smltickangles) *
                 maxsd, cos(smltickangles) * 0.99 * maxsd, sin(smltickangles) *
                 0.99 * maxsd)
    } else {
      x <- ref
      y <- model
      R <- cor(x, y, use = "pairwise.complete.obs", method = "pearson")
      E <- mean(x, na.rm = TRUE) - mean(y, na.rm = TRUE)
      xprime <- x - mean(x, na.rm = TRUE)
      yprime <- y - mean(y, na.rm = TRUE)
      sumofsquares <- (xprime - yprime)^2
      Eprime <- sqrt(sum(sumofsquares)/length(complete.cases(x)))
      E2 <- E^2 + Eprime^2
      if (add == FALSE) {
        maxray <- 1.5 * max(sd.f, sd.r)
        plot(c(-maxray, maxray), c(0, maxray), type = "n",
             asp = 1, bty = "n", xaxt = "n", yaxt = "n",
             xlim = c(-1.1 * maxray, 1.1 * maxray), xlab = xlab,
             ylab = ylab, main = main, cex = cex.axis)
        discrete <- seq(180, 0, by = -1)
        listepoints <- NULL
        for (i in discrete) {
          listepoints <- cbind(listepoints, maxray *
                                 cos(i * pi/180), maxray * sin(i * pi/180))
        }
        listepoints <- matrix(listepoints, 2, length(listepoints)/2)
        listepoints <- t(listepoints)
        lines(listepoints[, 1], listepoints[, 2])
        lines(c(-maxray, maxray), c(0, 0))
        lines(c(0, 0), c(0, maxray))
        for (i in grad.corr.lines) {
          lines(c(0, maxray * i), c(0, maxray * sqrt(1 - i^2)), lty = 3)
          lines(c(0, -maxray * i), c(0, maxray * sqrt(1 - i^2)), lty = 3)
        }
        for (i in grad.corr.full) {
          text(1.05 * maxray * i, 1.05 * maxray * sqrt(1 - i^2), i,
               cex = cex.axis, adj = cos(i)/2)
          text(-1.05 * maxray * i, 1.05 * maxray * sqrt(1 - i^2), -i,
               cex = cex.axis, adj = 1 - cos(i)/2)
        }
        seq.sd <- seq.int(0, 2 * maxray, by = (maxray/10))[-1]
        for (i in seq.sd) {
          xcircle <- sd.r + (cos(discrete * pi/180) * i)
          ycircle <- sin(discrete * pi/180) * i
          for (j in 1:length(xcircle)) {
            if ((xcircle[j]^2 + ycircle[j]^2) < (maxray^2)) {
              points(xcircle[j], ycircle[j], col = "darkgreen",
                     pch = ".")
              if (j == 10)
                text(xcircle[j], ycircle[j], signif(i, 2),
                     cex = cex.axis, col = "darkgreen",
                     srt = 90)
            }
          }
        }
        seq.sd <- seq.int(0, maxray, length.out = 5)
        for (i in seq.sd) {
          xcircle <- cos(discrete * pi/180) * i
          ycircle <- sin(discrete * pi/180) * i
          if (i)
            lines(xcircle, ycircle, lty = 3, col = "blue")
          text(min(xcircle), -0.06 * maxray,
               signif(i,  2), cex = cex.axis, col = "blue")
          text(max(xcircle), -0.06 * maxray, signif(i, 2),
               cex = cex.axis, col = "blue")
        }
        text(0, -0.14 * maxray, "Standard Deviation",
             cex = cex.axis, col = "blue")
        text(0, -0.22 * maxray, "Centered RMS Difference",
             cex = cex.axis, col = "darkgreen")
        points(sd.r, 0, pch = 22, bg = "darkgreen",
               cex = pcex)
        text(0, 1.2 * maxray, "Correlation Coefficient",
             cex = cex.axis)
      }
      S <- (2 * (1 + R))/(sd.f + (1/sd.f))^2
    }
  }
  points(sd.f * R, sd.f * sin(acos(R)), pch = pch, col = col,
         cex = pcex)
  invisible(oldpar)
}

# sig_digits <- function(x) {
#   x <- signif(x, 11)
#   x_str <- format(x, scientific = TRUE)
#   parts <- unlist(strsplit(x_str, "e"))
#   digits <- gsub("\\.", "", parts[1])
#   digits <- gsub("^0+", "", digits)
#   nchar(digits)
# }
