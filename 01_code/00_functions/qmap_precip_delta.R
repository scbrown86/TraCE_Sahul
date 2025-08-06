qmap_pr_delta <- function(chelsa_coarse_clim,
                          trace_coarse_clim,
                          high_res_template,
                          smooth = FALSE,
                          qm_method = "SSPLIN",
                          qm_qstep = 1e-4,
                          delta_method = "multiplicative",
                          resample_delta = "average",
                          eps = 1e-4,
                          do_plot = FALSE) {
  # Check input types
  if (!inherits(chelsa_coarse_clim, "SpatRaster") || !inherits(trace_coarse_clim, "SpatRaster")) {
    stop("Both 'chelsa_coarse_clim' and 'trace_coarse_clim' must be SpatRaster objects.")
  }
  if (!inherits(high_res_template, "SpatRaster")) {
    stop("'high_res_template' must be a SpatRaster object or NULL.")
  }
  if (delta_method != "multiplicative") {
    stop("Only 'multiplicative' is currently supported for 'delta_method'")
  }
  if (!identical(time(chelsa_coarse_clim), time(trace_coarse_clim))) {
    stop("Both 'chelsa_coarse_clim' and 'trace_coarse_clim' must have the same time index")
  }
  match.arg(arg = resample_delta, choices = c("bilinear", "average", "cubic", "cubicspline", "median"))
  require(terra); require(qmap); require(pbapply)

  # focal 3x3 if wanted?
  if (smooth) {
    warning("'trace_coarse_clim' smoothed with a 3x3 focal mean", call. = FALSE, immediate. = TRUE)
    trace_coarse_clim <- focal(trace_coarse_clim, w = matrix(1, 3, 3),
                               fun = mean, na.rm = TRUE)
  }

  # resample chelsa_coarse_clim to match TraCE clim
  obs_coarse <- resample(chelsa_coarse_clim, trace_coarse_clim, method = "average")

  # extract values to vectors
  obs_coarse_vals <- as.vector(values(obs_coarse))
  mod_coarse_vals <- as.vector(values(trace_coarse_clim))

  # Convert to data.frame
  df <- data.frame(CHELSA = obs_coarse_vals,
                   downscaled = mod_coarse_vals)
  df <- df[complete.cases(df), ] # remove missing rows
  if (nrow(df) == 0) {
    stop("No valid pixel values found across the entire stack.")
  }
  # Fit QMAP with chosen method & quantile step
  fit_qm <- qmap::fitQmap(
    obs = df$CHELSA,
    mod = df$downscaled,
    method = qm_method,
    qstep = qm_qstep)

  # Function for applying QMAP to each pixel's time series
  fun_qmap_stack <- function(x,...) {
    return(doQmap(x, fit_qm))
  }

  # apply the fitted q-map to the entire stack
  trace_qm <- terra::app(trace_coarse_clim, fun = fun_qmap_stack)

  # Generate a delta for each month from the qmapped stack
  delta_list <- pblapply(1:nlyr(trace_coarse_clim), function(i,...) {
    obs_coarse_i  <- obs_coarse[[i]]
    mod_coarse_i  <- trace_coarse_clim[[i]]
    mod_coarse_qm_i <- app(mod_coarse_i, fun = fun_qmap_stack)
    delta_i <- (obs_coarse_i + eps) / (mod_coarse_qm_i + eps)
    delta_high_i   <- resample(delta_i, high_res_template, method = resample_delta)
    return(delta_high_i)
  })
  # convert to SpatRaster stack
  delta_stack <- rast(delta_list)
  time(delta_stack) <- time(trace_coarse_clim)
  units(delta_stack) <- ""
  varnames(delta_stack) <- "precipitation delta (multiplicative)"
  if (do_plot) {
    plot(delta_stack, range = c(0, 2.5), fill_range = TRUE,
         col = hcl.colors(100, "Batlow", rev = TRUE))
    plot((resample(trace_coarse_clim, high_res_template, method = resample_delta) *
           delta_stack)*86400*c(31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31),
         range = c(0, 500), fill_range = TRUE,
         col = hcl.colors(100, "YlGnBu", rev = TRUE)
         )
    plot(app((resample(trace_coarse_clim, high_res_template, method = resample_delta) *
            delta_stack)*86400*c(31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31), sum),
         range = c(100, 4500), fill_range = TRUE,
         col = hcl.colors(100, "YlGnBu", rev = TRUE))
  }
  return(delta_stack)
}
