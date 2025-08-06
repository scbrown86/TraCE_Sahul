write_spatraster_ncdf <- function(x,
                                  filename,
                                  global_atts = list(
                                      title      = "Created from terra SpatRaster",
                                      history    = paste("file written on", format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")),
                                      source     = "write_spatraster_ncdf()"
                                  ),
                                  compression = 4L,
                                  force_v4 = TRUE, ...) {
    require(terra)
    require(ncdf4)
    stopifnull <- function(obj, what) {
        if (is.null(obj)) stop(sprintf("Missing %s on at least one raster - cannot proceed.", what), call. = FALSE)
    }
    trim_is_blank <- function(x) all(trimws(as.character(x)) == "")
    infer_nc_prec <- function(x) {
        if (is.factor(x)) x <- as.integer(x)
        if (is.logical(x)) {
            return("byte")
        }
        if (is.integer(x)) {
            return("integer")
        }
        if (is.numeric(x)) {
            return(ifelse(is.double(x), "double", "float"))
        }
        stop("Non‑numeric data detected. Character rasters are not supported; ",
            "please convert them (e.g. to factors) before calling this function.",
            call. = FALSE
        )
    }
    # collect rasters into a list
    if (inherits(x, "SpatRaster")) {
        rasters <- list(x)
    } else if (inherits(x, "sds")) {
        rasters <- as.list(x)
    } else if (is.list(x) && all(vapply(x, inherits, logical(1), "SpatRaster"))) {
        rasters <- x
    } else {
        stop("`x` must be a SpatRaster, terra::sds, or list of SpatRaster objects.", call. = FALSE)
    }
    # give the list names if missing
    if (is.null(names(rasters))) names(rasters) <- paste0("var", seq_along(rasters))
    # compare geometry
    ref <- rasters[[1]]
    for (i in seq_along(rasters)) {
        if (!terra::compareGeom(ref, rasters[[i]], stopOnError = FALSE)) {
            stop(sprintf("Geometry of raster %s does not match the first raster - all inputs must share grid and CRS.", names(rasters)[i]), call. = FALSE)
        }
    }
    # extract lon/lat
    xs <- unique(values(terra::init(ref, "x")))
    ys <- unique(values(terra::init(ref, "y")))
    nx <- length(xs)
    ny <- length(ys)
    # define spatial dimensions
    lon_dim <- ncdf4::ncdim_def("longitude", "degrees_east", xs)
    lat_dim <- ncdf4::ncdim_def("latitude", "degrees_north", ys)
    # check if time exists
    has_time <- FALSE
    tvals <- terra::time(ref)
    if (is.na(tvals)[1]) {
        tvals <- NULL
    }
    if (!is.null(tvals) && length(tvals) > 0 && !trim_is_blank(tvals)) {
        has_time <- TRUE
        info <- terra::timeInfo(ref)
        tunits <- if (is.null(info$step) || trim_is_blank(info$step)) "unknown" else info$step
        long_t <- tunits
    } else {
        # auto-generate time from number of layers if needed
        nlayers <- terra::nlyr(ref)
        if (nlayers > 1) {
            has_time <- TRUE
            tvals <- seq(ISOdate(2000, 1, 1), by = "1 month", length.out = nlayers)
            tvals <- as.numeric(tvals - ISOdate(2000, 1, 1), units = "days") # relative to origin
            tunits <- "days since 2000-01-01"
            long_t <- "time (auto-generated)"
        } else {
            # single layer, no time
            tvals <- NULL
        }
    }
    if (has_time) {
        time_dim <- ncdf4::ncdim_def("time", tunits, tvals, unlim = TRUE, longname = long_t)
    }
    # variable definitions
    vdefs <- vector("list", length(rasters))
    for (i in seq_along(rasters)) {
        r <- rasters[[i]]
        nm <- terra::varnames(r)
        stopifnull(nm, "varnames()")
        un <- terra::units(r)
        stopifnull(un, "units()")
        ln <- terra::longnames(r)
        stopifnull(ln, "longnames()")
        sample_val <- values(r[[1]], na.rm = TRUE)[1]
        prec_i <- infer_nc_prec(sample_val)
        dims <- if (has_time) list(lon_dim, lat_dim, time_dim) else list(lon_dim, lat_dim)
        vdefs[[i]] <- ncdf4::ncvar_def(
            name = nm[1],
            units = un[1],
            prec = prec_i,
            dim = dims,
            longname = ln[1],
            compression = if (force_v4) compression else NA,
            missval = NA_real_,
            ...
        )
    }
    # create NetCDF file
    ncout <- NULL
    ncout <- ncdf4::nc_create(filename, vdefs, force_v4 = force_v4)
    on.exit(
        {
            if (!is.null(ncout) && inherits(ncout, "ncdf4")) {
                try(ncdf4::nc_close(ncout), silent = TRUE)
            }
        },
        add = TRUE
    )
    # global attributes
    for (att in names(global_atts)) {
        ncdf4::ncatt_put(ncout, 0, att, global_atts[[att]])
    }
    # optionally: store CRS
    # if (!is.na(terra::crs(ref, describe = FALSE))) {
    #   ncdf4::ncatt_put(ncout, 0, "crs", terra::crs(ref, describe = TRUE))
    # }
    # write values
    for (v in seq_along(rasters)) {
        r <- rasters[[v]]
        if (has_time) {
            for (layer in seq_len(terra::nlyr(r))) {
                ncdf4::ncvar_put(
                    nc = ncout,
                    varid = vdefs[[v]],
                    vals = values(r[[layer]]),
                    start = c(1, 1, layer),
                    count = c(-1, -1, 1)
                )
            }
        } else {
            ncdf4::ncvar_put(
                nc = ncout,
                varid = vdefs[[v]],
                vals = values(r[[1]])
            )
        }
    }
    # clean close
    ncdf4::nc_close(ncout)
    ncout <- NULL
    invisible(filename)
}


# # library(terra)
# # library(ncdf4)
#
# # test data
# {
#     set.seed(54)
#     prec <- rast(
#         res = 5, nlyrs = 12,
#         vals = rpois(ncell(rast(res = 5)) * 12, 75),
#         crs = "EPSG:4326"
#     )
#     tas <- rast(
#         res = 5, nlyrs = 12,
#         vals = rpois(ncell(rast(res = 5)) * 12, 15),
#         crs = "EPSG:4326"
#     )
#     time(prec, tstep = "months") <- time(tas, tstep = "months") <- 1:12
#     units(prec) <- "mm/month"
#     units(tas) <- "deg_C"
#     longnames(prec) <- "precipitation"
#     longnames(tas) <- "air temperature"
#     varnames(prec) <- "pr"
#     varnames(tas) <- "tas"
# }
#
# ## write single‑variable file
# write_spatraster_ncdf(x = prec, filename = "single_var.nc")
# ## write single‑variable file
# pr <- prec[[1]]
# time(pr) <- NULL
# write_spatraster_ncdf(x = pr, filename = "single_var_single_time.nc")
# ## write multi‑variable file
# write_spatraster_ncdf(list(prec = prec, tas = tas), "multi_var.nc",
#     global_atts = list(
#         Title = "Example multi‑var NetCDF",
#         Author = "Your Name"
#     ))
