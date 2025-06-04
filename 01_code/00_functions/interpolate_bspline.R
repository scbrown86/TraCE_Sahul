# interpolate_bspline <- function(x, output_dir,
#                                 bspline_ext = ext(105.0, 161.25, -52.5, 11.25),
#                                 target_size = 0.5,
#                                 parallel_cores = 12,
#                                 start_date = as.Date("1985-01-16"),
#                                 outname_template = "CHELSA_coarse_%s_climatology.nc",
#                                 load_exist = TRUE) {
#   require(terra); require(pbapply)
#   stopifnot(inherits(x, "SpatRaster"))
#   if (nlyr(x) != 12) stop("The raster must have 12 monthly layers.")
#   if (is.null(units(x))) stop("Raster must have units set using `units(x)`.")
#   var_unit <- unique(units(x))
#   var_name <- varnames(x)
#   is_precip <- var_unit == "kg/m2/s" || var_name == "pr" || var_name == "precip"
#   is_temp <- var_unit == "deg_C" || var_unit == "degC" || var_name %in% c("tas", "tasmin", "tasmax")
#   if (!is_precip && !is_temp) {
#     stop("Unsupported variable. Must be one of: 'pr', 'tas', 'tasmin', or 'tasmax'.")
#   }
#   month_days <- c(31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31)
#   out_prefix <- switch(var_name, "pr" = "pr",
#                        "precip" = "pr",
#                        "tas" = "tas", "tasmin" = "tmn",
#                        "tasmax" = "tmx", var_name)
#   nc_varname <- switch(var_name, "precip" = "pr", "tas" = "tas",
#                        "tasmin" = "tasmin", "tasmax" = "tasmax", var_name)
#   nc_longname <- switch(var_name,
#                         "pr" = "precipitation",
#                         "precip" = "precipitation",
#                         "tas" = "air temperature at surface",
#                         "tasmin" = "minimum temperature at surface",
#                         "tasmax" = "maximum temperature at surface", nc_varname)
#   nc_unit <- if (is_precip) "kg/m2/s" else "deg_C"
#   nc_outfile <- file.path(output_dir, sprintf(outname_template, nc_varname))
#   if (file.exists(nc_outfile) && load_exist) {
#     return(rast(nc_outfile))
#   }
#   out_files <- file.path(output_dir, sprintf("%s_bspline_%02d.tif", out_prefix, 1:12))
#   if(all(sapply(out_files, file.exists)) && load_exist) {
#     message("Loading b-spline files...")
#     out_stack <- rast(lapply(out_files, rast))
#   } else {
#     message("Interpolating b-splines...")
#     interpolated <- pblapply(seq_len(12), function(i) {
#       out_file <- out_files[i]
#       if (file.exists(out_file)) {
#         return(wrap(rast(out_file)))
#       }
#       tmp_r <- tempfile(pattern = sprintf("bspline_%s_%02d_", out_prefix, i), fileext = ".tif")
#       ingrid <- unwrap(x)[[i]] * 1
#       if (is_precip) {
#         dmon <- month_days[i]
#         ingrid <- ingrid * (86400 * dmon)
#         ingrid <- ifel(ingrid < 5, 5, ingrid)
#       }
#       bspline <- safe_spline(
#         "sagang:multilevelbsplinefromgridpoints",
#         GRID = ingrid,
#         "TARGET_USER_XMIN TARGET_USER_XMAX TARGET_USER_YMIN TARGET_USER_YMAX" = bspline_ext,
#         TARGET_USER_SIZE = target_size,
#         TARGET_USER_FITS = 1,
#         METHOD = 0,
#         DATATYPE = 0,
#         EPSILON = 0.000100,
#         LEVEL_MAX = 14,
#         TARGET_OUT_GRID = tmp_r)
#       if (!is.null(bspline$error)) return(NULL)
#       b <- qgis_as_terra(bspline$result)
#       if (is_precip) {
#         dmon <- month_days[i]
#         b <- ifel(b < 1, 1, b)
#         b <- b / (86400 * dmon)
#       }
#       writeRaster(b, filename = out_file,
#                   gdal = c("COMPRESS=LZW", "TFW=NO", "PREDICTOR=3"))
#       return(terra::wrap(b))
#     }, cl = parallel_cores)
#     out_stack <- rast(lapply(interpolated, unwrap))
#   }
#   time(out_stack) <- seq(start_date, by = "month", length.out = 12)
#   units(out_stack) <- nc_unit
#   varnames(out_stack) <- nc_varname
#   longnames(out_stack) <- nc_longname
#   # Write to NetCDF
#   message("Writing b-spline files to netcdf...")
#   writeCDF(out_stack,
#            filename = nc_outfile,
#            varname = nc_varname,
#            longname = nc_longname,
#            unit = nc_unit,
#            zname = "time",
#            prec = "float",
#            overwrite = TRUE)
#   return(out_stack)
# }

interpolate_bspline <- function(x, output_dir,
                                bspline_ext = ext(105.0, 161.25, -52.5, 11.25),
                                target_size = 0.5,
                                parallel_cores = 12,
                                start_date = as.Date("1985-01-16"),
                                outname_template = "CHELSA_coarse_%s_climatology.nc",
                                load_exist = TRUE,
                                delta = FALSE) {
  require(terra); require(pbapply)
  stopifnot(inherits(x, "SpatRaster"))
  if (nlyr(x) != 12) stop("The raster must have 12 monthly layers.")
  if (!delta && is.null(units(x))) stop("Raster must have units set using `units(x)` if delta = FALSE.")
  var_name <- varnames(x)
  var_unit <- if (!delta) unique(units(x)) else NULL
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
                        var_name)
  out_prefix <- if (delta) paste0("delta_", base_prefix) else base_prefix
  nc_varname <- if (delta) paste0("delta_", var_name) else switch(
    var_name, "precip" = "pr", "tas" = "tas", "tasmin" = "tasmin", "tasmax" = "tasmax", var_name
  )
  nc_longname <- if (delta) paste("delta of", var_name) else switch(
    var_name,
    "pr" = "precipitation",
    "precip" = "precipitation",
    "tas" = "air temperature at surface",
    "tasmin" = "minimum temperature at surface",
    "tasmax" = "maximum temperature at surface",
    nc_varname
  )
  nc_unit <- if (delta) "" else if (is_precip) "kg/m2/s" else "deg_C"
  nc_outfile <- file.path(output_dir, sprintf(outname_template, nc_varname))
  if (file.exists(nc_outfile) && load_exist) {
    return(rast(nc_outfile))
  }
  out_files <- file.path(output_dir, sprintf("%s_bspline_%02d.tif", out_prefix, 1:12))
  if (all(sapply(out_files, file.exists)) && load_exist) {
    message("Loading b-spline files...")
    out_stack <- rast(lapply(out_files, rast))
  } else {
    message("Interpolating b-splines...")
    interpolated <- pblapply(seq_len(12), function(i) {
      out_file <- out_files[i]
      if (file.exists(out_file)) {
        return(wrap(rast(out_file)))
      }
      tmp_r <- tempfile(pattern = sprintf("bspline_%s_%02d_", out_prefix, i), fileext = ".tif")
      ingrid <- unwrap(x)[[i]] * 1
      if (!delta && is_precip) {
        dmon <- month_days[i]
        ingrid <- ingrid * (86400 * dmon)
        ingrid <- ifel(ingrid < 5, 5, ingrid)
      }
      bspline <- safe_spline(
        "sagang:multilevelbsplinefromgridpoints",
        GRID = ingrid,
        "TARGET_USER_XMIN TARGET_USER_XMAX TARGET_USER_YMIN TARGET_USER_YMAX" = bspline_ext,
        TARGET_USER_SIZE = target_size,
        TARGET_USER_FITS = 1,
        METHOD = 0,
        DATATYPE = 0,
        EPSILON = 0.000100,
        LEVEL_MAX = 14,
        TARGET_OUT_GRID = tmp_r)
      if (!is.null(bspline$error)) return(NULL)
      b <- qgis_as_terra(bspline$result)
      if (!delta && is_precip) {
        dmon <- month_days[i]
        b <- ifel(b < 1, 1, b)
        b <- b / (86400 * dmon)
      }
      writeRaster(b, filename = out_file,
                  gdal = c("COMPRESS=LZW", "TFW=NO", "PREDICTOR=3"))
      return(terra::wrap(b))
    }, cl = parallel_cores)

    out_stack <- rast(lapply(interpolated, unwrap))
  }
  time(out_stack) <- seq(start_date, by = "month", length.out = 12)
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

