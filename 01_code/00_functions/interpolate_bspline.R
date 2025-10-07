# used for multi-level bspline
safe_spline <- purrr::safely(qgisprocess::qgis_run_algorithm,
                             otherwise = NULL, quiet = TRUE)

# used for terra::project
safe_project <- purrr::safely(terra::project, otherwise = NULL, quiet = TRUE)

interpolate_bspline <- function(x, output_dir,
                                bspline_ext = ext(105.0, 161.25, -52.5, 11.25),
                                target_size = 0.5,
                                parallel_cores = 12,
                                start_date = as.Date("1985-01-16"),
                                outname_template = "CHELSA_coarse_%s_climatology.nc",
                                load_exist = TRUE,
                                algo = "bspline",
                                delta = FALSE) {
  require(terra); require(pbapply)
  stopifnot(inherits(x, "SpatRaster"))
  if (nlyr(x) %% 12 != 0) stop("The number of layers must be divisible by 12")
  if (!delta && is.null(units(x))) stop("Raster must have units set using `units(x)` if delta = FALSE.")
  var_name <- varnames(x)
  var_unit <- if (!delta) {
    unique(units(x))
  } else {
    NULL
  }
  match.arg(algo, choices = c("bspline", "bilinear", "average", "cubic", "cubicspline"), several.ok = FALSE)
  is_precip <- !delta && (var_unit == "kg/m2/s" || var_name %in% c("pr", "precip"))
  is_temp   <- !delta && (var_unit %in% c("degC", "deg_C") || var_name %in% c("tas", "tasmin", "tasmax"))
  if (!delta && !is_precip && !is_temp) {
    stop("Unsupported variable. Must be one of: 'pr', 'tas', 'tasmin', or 'tasmax'.")
  }
  month_days <- c(31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31)
  base_prefix <- switch(var_name,
                        "precip" = "pr",
                        "pr" = "pr",
                        "tas" = "tas",
                        "tasmin" = "tmn",
                        "tasmax" = "tmx",
                        "dtr" = "dtr",
                        var_name)
  out_prefix <- if (delta) {
    paste0("delta_", base_prefix)
  } else {
      base_prefix
  }
  nc_varname <- if (delta) {
    paste0("delta_", var_name)
  } else {
      switch(
      var_name, "precip" = "pr", "tas" = "tas", "tasmin" = "tasmin", "tasmax" = "tasmax", "dtr" = "dtr", var_name)
  }
  nc_longname <- if (delta) {
    paste("delta of", var_name)
  } else {
    switch(
    var_name,
    "pr" = "precipitation",
    "precip" = "precipitation",
    "tas" = "air temperature at surface",
    "tasmin" = "minimum temperature at surface",
    "tasmax" = "maximum temperature at surface",
    "dtr" = "diurnal temperature range",
    nc_varname
  )}
  nc_unit <- if (delta) {
    ""
    } else if (is_precip) {
      "kg/m2/s"
    } else {
      "deg_C"
    }
  nc_outfile <- file.path(output_dir, sprintf(outname_template, nc_varname))
  if (file.exists(nc_outfile) && load_exist) {
    message("Loading existing netcdf...")
    return(rast(nc_outfile))
  }
  out_files <- file.path(output_dir, sprintf("%s_bspline_%02d.tif", out_prefix, 1:nlyr(x)))
  if (all(sapply(out_files, file.exists)) && load_exist) {
    message("Loading b-spline tif files...")
    out_stack <- rast(lapply(out_files, rast))
  } else {
    message("Interpolating...")
    interpolated <- pblapply(seq_len(nlyr(x)), function(i, ...) {
      layer_assignment <- (((1:nlyr(x) - 1) %% length(month_days)) + 1)[i]
      out_file <- out_files[i]
      if (file.exists(out_file) && load_exist) {
        return(wrap(rast(out_file)))
      }
      tmp_r <- tempfile(pattern = sprintf("bspline_%s_%03d_", out_prefix, i), fileext = ".tif")
      ingrid <- unwrap(x)[[i]] * 1
      if (!delta && is_precip) {
        dmon <- month_days[layer_assignment]
        ingrid <- ingrid * 86400 # mm/day
        ingrid <- ifel(ingrid < 0, 0, ingrid)
      }
      if (algo == "bspline") {
        bspline <- safe_spline(
          "sagang:multilevelbsplinefromrasterpoints",
          GRID = ingrid,
          "TARGET_USER_XMIN TARGET_USER_XMAX TARGET_USER_YMIN TARGET_USER_YMAX" = bspline_ext,
          TARGET_USER_SIZE = target_size,
          TARGET_USER_FITS = 0,
          METHOD = 0,
          DATATYPE = 0,
          EPSILON = 0.000100,
          LEVEL_MAX = 14,
          TARGET_OUT_GRID = tmp_r)
        if (!is.null(bspline$error)) {
          return(NULL)
        }
        b <- qgis_as_terra(bspline$result)
        if (!delta && is_precip) {
          dmon <- month_days[layer_assignment]
          b <- ifel(b < 0, 0, b)
          b <- b / 86400 # kg m-2 s-1
        }
      } else {
        bspline <- safe_project(ingrid,
                                  rast(crs = "EPSG:4326",
                                       resolution = target_size,
                                       extent = bspline_ext,
                                       vals = 0L),
                                  method = algo,
                                  ...)
        if (!is.null(bspline$error)) {
          return(NULL)
        }
        b <- bspline$result
        if (!delta && is_precip) {
          dmon <- month_days[layer_assignment]
          b <- ifel(b < 0, 0, b)
          b <- b / 86400 # kg m-2 s-1
        }
      }
      writeRaster(b, filename = out_file,
                  overwrite = TRUE,
                  gdal = c("COMPRESS=LZW", "TFW=NO", "PREDICTOR=3"))
      return(terra::wrap(b))
    }, cl = parallel_cores)
    out_stack <- rast(lapply(interpolated, unwrap))
  }
  time(out_stack) <- seq(start_date, by = "month", length.out = nlyr(x))
  units(out_stack) <- nc_unit
  varnames(out_stack) <- nc_varname
  longnames(out_stack) <- nc_longname
  message("Writing b-spline files to netcdf...")
  writeCDF(out_stack,
           filename = nc_outfile,
           varname = nc_varname,
           longname = nc_longname,
           unit = nc_unit,
           zname = "time",
           prec = "float",
           overwrite = TRUE)
  return(out_stack)
}

