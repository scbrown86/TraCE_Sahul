chelsa_proc <- function(variable, dir, outdir, type = "\\.tif$",
                        mask = NULL, # wrap(land),
                        ymin = 1980, ymax = 1989,
                        tras_ext = ext(105, 160, -50, 7), # Sahul
                        cores = 10L, load_exist = TRUE,
                        ...) {
  require(pbapply)
  require(gtools)
  match.arg(arg = variable, choices = c("prec", "tmax", "tmin", "tmean"))
  v1 <- variable # keep old variable name
  from <- c("prec", "tmax", "tmin", "tmean")
  to <- c("pr", "tasmax", "tasmin", "tas")
  variable <- to[match(v1, from)]
  fil.list <- mixedsort(list.files(dir, pattern = type, full.names = TRUE))
  fil.list <- fil.list[grepl(pattern = v1, fil.list)]
  stopifnot("Not enough years of data for CHELSA data..." = length(fil.list) == ((ymax + 1) - ymin) * 12)
  # extract the years from fil.list
  years <- as.integer(unique(gsub(".*_(\\d{4})_.*", "\\1", fil.list)))
  years <- years[years >= ymin & years <= ymax]
  ann_CHELSA <- pbsapply(years, function(year, ...) {
    fil.list.annual <- fil.list[grepl(pattern = year, fil.list)]
    out_fil <- file.path(outdir, sprintf("CHELSA_%s_%s_V.1.2.tif", variable, year))
    # out_filn <- file.path(outdir, sprintf("CHELSA_%s_%s_V.1.2.nc", variable, year))
    if (file.exists(out_fil) & load_exist) {
      return(out_fil)
    }
    if (length(fil.list.annual) < 12) {
      stop("Less than 12 months of data for year: ", year)
    }
    chelsa <- rast(fil.list.annual)
    # crop CHELSA to extent of template raster and load into memory
    chelsa <- crop(chelsa, tras_ext)
    if (!is.null(mask)) {
      if (inherits(x = mask, "PackedSpatVector")) {
        mask <- terra::unwrap(mask)
      }
      chelsa <- terra::mask(chelsa, mask, touches = TRUE)
    }
    if (variable == "pr") {
      # stored as kg/m2 (i.e mm/month)
      # need to convert to kg/m2/s (x/conv_rate)
      # conv_rate = 24(hours)*3600(seconds in hour) = [86400] * num_days_in_month
      conv_rate <- (86400 * c(31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31))
      # pr files not reading fill value correctly. Remove here
      chelsa <- ifel(chelsa == 65535, NA, chelsa)
      # convert
      chelsa <- (chelsa / conv_rate)
      units(chelsa) <- "kg/m2/s"
      varnames(chelsa) <- variable
      time(chelsa) <- seq(as.Date(paste0(year, "-01-16")), by = "months", l = 12)
      names(chelsa) <- format(time(chelsa), "%b%Y")
    } else if (variable %in% c("tasmin", "tasmax", "tas")) {
      # stored as K/10. Convert to celcius
      chelsa <- setValues(chelsa, round((terra::values(chelsa) / 10) - 273.15, 2))
      units(chelsa) <- "degC"
      varnames(chelsa) <- variable
      time(chelsa) <- seq(as.Date(paste0(year, "-01-16")), by = "months", l = 12)
      names(chelsa) <- format(time(chelsa), "%b%Y")
    }
    if (variable == "pr") {
      writeRaster(chelsa, out_fil,
        gdal = c("COMPRESS=LZW", "TFW=NO", "PREDICTOR=3"),
        overwrite = TRUE
      )
      # writeCDF(chelsa, out_filn,
      #   varname = "pr", long_name = "rainfall",
      #   unit = "kg/m2/s", zname = "time", prec = "float"
      # )
    } else if (variable %in% c("tasmin", "tasmax", "tas")) {
      writeRaster(chelsa, out_fil,
        gdal = c("COMPRESS=LZW", "TFW=NO", "PREDICTOR=3"),
        overwrite = TRUE
      )
      # writeCDF(chelsa, out_filn,
      #   varname = variable, long_name = variable,
      #   unit = "deg_C", zname = "time", prec = "float"
      # )
    }
    return(out_fil)
  },
  cl = ifelse(!is.null(cores), cores, NULL)
  )
  return(ann_CHELSA)
}
