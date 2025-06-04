split_raster_by_variable <- function(r, vars  = c("pr", "tas", "tasmin", "tasmax")) {
  var_names <- names(r)
  var_layers <- lapply(vars, function(v) {
    matched <- grep(paste0("_", v, "$"), var_names, value = TRUE)
    r[[matched]]
  })
  sds_list <- sds(var_layers)
  names(sds_list) <- vars
  return(sds_list)
}

rescale_raster <- function(r, new_min, new_max) {
  old_min <- global(r, "min", na.rm = TRUE)[1,1]
  old_max <- global(r, "max", na.rm = TRUE)[1,1]
  (r - old_min) / (old_max - old_min) * (new_max - new_min) + new_min
}
