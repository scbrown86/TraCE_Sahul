downscale_bias_correct <- function(x, delta_sds, convert_to_annual = FALSE,
                                   cores = 12L, ...) {
  stopifnot(!is.null(terra::names(delta_sds)))
  ras <- rast(x)
  stopifnot("Incorrect number of layers. Not divisible by 12." = nlyr(ras) %% 12 == 0)
  var <- varnames(ras)
  if (var %in% c("rain", "rainfall", "precip", "precipitation")) {
    var <- "pr"
  }
  sd_delta <- delta_sds[[var]]
  nlay <- nlyr(ras)
  if (is_monthly(time(ras)) & convert_to_annual) {
    idx <- format(time(ras), "%Y")
    ras <- tapp(ras, idx, mean)
    time(ras, tstep = "years") <- as.integer(unique(idx))
    nlay <- nlyr(ras)
  }
  ras <- wrap(ras)
  sd_delta <- wrap(sd_delta)
  var_bil <- pblapply(seq_len(nlay), function(i, v = var, delta = sd_delta, ...) {
    if (file.exists(sprintf("scratch/%s_biascorr_%04d.tif", v, i))) {
      return(terra::wrap(terra::rast(sprintf("scratch/%s_biascorr_%04d.tif", v, i))))
    }
    tmp_r <- tempfile(pattern = sprintf("biascorr_%s_%04d_", v, i),
                      fileext = ".tif",
                      tmpdir = "scratch/tmp")
    ingrid <- unwrap(ras)[[i]] * 1
    month <- format(as.Date(time(ingrid)), "%b")
    delta_idx <- unwrap(sd_delta)
    names(delta_idx) <- month.abb
    didx <- which(names(delta_idx) == month)
    if (v == "pr") {
      dmon <- c(31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31)[didx]
      ingrid <- ingrid*(86400*dmon)
      ingrid <- ifel(ingrid < 5, 5, ingrid)
    }
    delta_idx <- delta_idx[[didx]] * 1
    first <- TRUE
    bspline <- safe_spline(
      "sagang:multilevelbsplinefromgridpoints",
      GRID = ingrid,
      "TARGET_USER_XMIN TARGET_USER_XMAX TARGET_USER_YMIN TARGET_USER_YMAX" = ext(105, 160, -50, 7),
      TARGET_USER_SIZE = 0.5,
      TARGET_USER_FITS = 1,
      METHOD = 0,
      DATATYPE = 0,
      EPSILON = 0.000100,
      LEVEL_MAX = 14,
      TARGET_OUT_GRID = tmp_r)
    if (!is.null(bspline$error) & first) {
      first <- FALSE
      bspline <- safe_spline(
        "sagang:multilevelbsplinefromgridpoints",
        GRID = ingrid,
        "TARGET_USER_XMIN TARGET_USER_XMAX TARGET_USER_YMIN TARGET_USER_YMAX" = ext(105, 160, -50, 7),
        TARGET_USER_SIZE = 0.5,
        TARGET_USER_FITS = 1,
        METHOD = 0,
        DATATYPE = 0,
        EPSILON = 0.000100,
        LEVEL_MAX = 14,
        TARGET_OUT_GRID = tmp_r)
    }
    if (is.null(bspline$error)) {
      b <- qgis_as_terra(bspline$result)*1
      if (var == "pr") {
        b <- ifel(b < 1, 1, b)
        b <- b/(86400*dmon)
        b <- b * delta_idx
      } else if (var %in% c("tasmin", "tasmax", "tas")) {
        b <- b + delta_idx
      }
      time(b) <- time(ingrid)
      varnames(b) <- var
      units(b) <- units(ingrid)
      names(b) <- format(time(b), "%b%Y")
      writeRaster(b,
                  filename = sprintf("scratch/%s_biascorr_%04d.tif", v, i),
                  gdal = c("COMPRESS=LZW", "TFW=NO", "PREDICTOR=3"))
      b <- wrap(b)
      file.remove(tmp_r)
      return(b)
    } else {
      file.remove(tmp_r)
      return(NULL)
    }
  }, cl = cores)
  if (sum(sapply(var_bil, inherits, "PackedSpatRaster")) == nlay) {
    var_bil <- rast(lapply(var_bil, function(f) unwrap(f)))
    ras <- unwrap(ras)
    time(var_bil) <- time(ras)
    units(var_bil) <- units(ras)
    varnames(var_bil) <- var
    return(var_bil)
  } else {
    return(sprintf("Not all timesteps were created. Run again for var: %s", var))
  }
}

# check dates
is_monthly <- function(date_vector) {
  dates <- as.Date(date_vector, format = "%Y-%m-%d")
  year_months <- unique(format(dates, "%Y-%m"))
  if (length(year_months) < 2) {
    return(TRUE)
  }
  ym_dates <- as.Date(paste0(year_months, "-01"))
  return(all(round(diff(ym_dates, units = "weeks")) == as.difftime(4, units = "weeks")))
}
