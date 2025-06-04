agcd_proc <- function(variable, dir, template, years,
                      proj_method = "average", type = "\\.nc$",  ...) {
  require(pbapply); require(gtools)
  match.arg(arg = variable, choices = c("precip", "tmax", "tmin"))
  fil.list <- mixedsort(list.files(dir, pattern = type, full.names = TRUE,
                                   recursive = TRUE))
  fil.list <- fil.list[grepl(pattern = variable, fil.list)]
  fil.years <- as.numeric(sapply(strsplit(basename(fil.list), "\\."), "[", 2))
  fil.list <- fil.list[which(fil.years %in% years)]
  # extract the years from fil.list
  ann_NCI <- pblapply(years, function(year, ...) {
    fil.list.annual <- fil.list[grepl(pattern = year, fil.list)]
    nci_ras <- rast(fil.list.annual)
    # convert from mm/month to kg/m2/s
    if (variable == "precip") {
      nci_ras <- nci_ras/(86400*c(31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31))
    }
    z <- time(nci_ras)
    # project to area
    nci_ras <- project(nci_ras, template, method = proj_method,
                       use_gdal = TRUE, threads = TRUE)
    return(nci_ras)
  })
  ann_NCI <- tighten(rast(ann_NCI))
  return(ann_NCI)
}
