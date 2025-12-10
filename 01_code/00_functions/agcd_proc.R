agcd_proc <- function(variable, dir, template, years,
                      proj_method = "average", type = "\\.nc$",  ...) {
  require(pbapply); require(gtools)
  match.arg(arg = variable, choices = c("precip", "tmax", "tmin"))
  fil.list <- mixedsort(list.files(dir, pattern = type, full.names = TRUE,
                                   recursive = TRUE))
  fil.list <- fil.list[grepl(pattern = variable, fil.list)]
  fil.years <- as.numeric(sapply(strsplit(basename(fil.list), "\\."), "[", 2))
  fil.list <- fil.list[which(fil.years %in% years)]
  ann_NCI <- pblapply(years, function(year, ...) {
    fil.list.annual <- fil.list[grepl(pattern = year, fil.list)]
    nci_ras <- rast(fil.list.annual, win = ext(template), snap = "out")
    z <- time(nci_ras)
    nci_ras <- project(nci_ras, template, method = proj_method,
                       use_gdal = TRUE, threads = TRUE)
    return(nci_ras)
  })
  ann_NCI <- tighten(rast(ann_NCI))
  return(ann_NCI)
}
