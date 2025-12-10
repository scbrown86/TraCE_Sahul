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
