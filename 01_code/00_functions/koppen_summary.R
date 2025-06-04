koppen_summary <- function(grids) {
  require(data.table); require(pbapply); require(exactextractr)
  ext <- pblapply(seq_along(grids), function(i) {
    vars <- grids[[i]]
    var_extract <- lapply(seq_along(vars), function(j,...) {
      vj <- vars[[j]]
      vj <- tapp(vj, "years", "mean")
      crs(vj) <- "EPSG:4326"
      zt <- time(vj)
      # convert to degC if appropriate
      vj_units <- tryCatch(terra::units(vj)[1], error = function(e) NULL)
      vj_units <- if (!is.null(vj_units) && trimws(vj_units) != "") trimws(vj_units) else NULL
      if (!is.null(vj_units)) {
        if (tolower(vj_units) %in% c("k", "kelvin")) {
          vj <- setValues(vj, values(vj) - 273.15)
          terra::units(vj) <- "deg_C"
        }
      } else {
        # If no units attribute, check global max
        ## precip not an issue as kg/m2/s
        vmax <- unlist(terra::global(vj, "max", na.rm = TRUE)[1])[1]
        if (isTRUE(vmax > 100)) { # arbitrarily high value
          vj <- setValues(vj, values(vj) - 273.15)
          terra::units(vj) <- "deg_C"
        }
      }
      koppen <- project(koppen, vj, "near")
      zt <- data.table(timestep = 1:length(zt), yd = zt)
      rzm <- setDT(zonal(vj, z = koppen, fun = mean, wide = TRUE, na.rm = TRUE))
      rzm <- melt(rzm, id.vars = "Koppen", variable.name = "Year", value.name = "mean")
      rzs <- setDT(zonal(vj, z = koppen, fun = function(x,...) sqrt(var(x,...)), wide = TRUE, na.rm = TRUE))
      rzs <- melt(rzs, id.vars = "Koppen", variable.name = "Year", value.name = "SD")
      rz <- do.call(merge, list(rzm, rzs))
      if (varnames(vars[[j]])[1] == "") {
        rz[, variable := names(vars[j])]
      } else {
        rz[, variable := varnames(vars[[j]])[1]]
      }
      rz[, Year := as.integer(sapply(strsplit(x = as.character(Year), "_"), tail, 1))]
      fout <- file.path(sprintf("scratch/var_extract_%s_%s.RDS", i, j))
      saveRDS(rz, fout)
      return(rz)
    })
    var_extract <- rbindlist(var_extract)
    return(var_extract)
  })
  return(ext)
}

require(exactextractr)
