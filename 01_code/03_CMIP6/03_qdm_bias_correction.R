# Java options. Need to be run before any packages are loaded
## sets max RAM for Java to 128GB
options(java.parameters = "-Xmx128g"); gc()

# Define ANSI color codes
red_text <- "\033[31m"
green_text <- "\033[32m"
blue_text <- "\033[34m"
reset_text <- "\033[0m"

# Load libraries
library(loadeR)
library(downscaleR)
library(transformeR)
library(visualizeR)
library(loadeR.2nc)
library(parallel)

# Model setup
models <- c("ACCESS-ESM1-5", "CMCC-ESM2", "EC-Earth3", "MPI-ESM1-2-HR", "MRI-ESM2-0", "NorESM2-MM")
variables <- c("pr", "tasmax", "tasmin")
experiments <- c("ssp126", "ssp245", "ssp370", "ssp585")

clim_years <- 1960:1989
hist_years <- 1990:2014
ssp_chunks <- list(
  c(2015, 2030),
  c(2031, 2040),
  c(2041, 2060),
  c(2061, 2080),
  c(2081, 2100))

# Cape York for testing
lon_lim <- c(138, 146)
lat_lim <- c(-18, -9)

# Paths
input_root <- "/mnt/Data/CMIP6"
out_root <- "/mnt/Data/CMIP6/bias_corrected"
dir.create(out_root, recursive = TRUE, showWarnings = TRUE)

obs_paths <- list(
  pr = "/mnt/Data/TraCE-Sahul/pr/TraCE-Sahul_1500_1990_pr.nc",
  tasmax = "/mnt/Data/TraCE-Sahul/tasmax/TraCE-Sahul_1500_1990_tasmax.nc",
  tasmin = "/mnt/Data/TraCE-Sahul/tasmin/TraCE-Sahul_1500_1990_tasmin.nc")

# Functions
find_input_file <- function(var, model, experiment, input_root) {
  if (experiment == "historical") {
    timerange <- "185001-201412"
  } else {
    timerange <- "201501-210012"
  }
  path <- file.path(input_root, experiment, var, paste0(var, "_", model, "_", experiment, "_r1i1p1f1_", timerange, ".nc"))
  if (!file.exists(path)) {
    return(NA_character_)
  }
  return(path)
}

set_monthly_dates <- function(grid, start_year, n_months) {
  grid$Dates$start <- grid$Dates$end <- as.POSIXct(
    seq(as.Date(paste0(start_year, "-01-16")), by = "month", l = n_months),
    tz = "", format = "%Y-%m-%d")
  return(grid)
}

# Loop through models, variables, and experiments
for (model in models) {
  cat(green_text, paste0("Model: ", model), reset_text, "\n")
  for (var in variables) {
    cat(green_text, paste0("\tVariable: ", var), reset_text, "\n")
    is_precip <- var == "pr"
    # load obs climatology (fixed across all models/experiments)
    cat(blue_text, paste0("\tLoading historical TraCE-Sahul climatology: ", clim_years[1], ":", clim_years[length(clim_years)]), reset_text, "\n")
    obs_clim <- loadGridData(
      dataset = obs_paths[[var]],
      var = var,
      lonLim = lon_lim,
      latLim = lat_lim,
      years = clim_years)
    obs_clim <- set_monthly_dates(obs_clim, clim_years[1], length(clim_years) * 12L)
    # find historical file for this model/variable
    hist_file <- find_input_file(var, model, "historical", input_root)
    if (is.na(hist_file)) {
      cat(red_text, paste0("\tNo historical file found for ", model, " ", var, ", skipping model/variable"), reset_text, "\n")
      next
    }
    # load CMIP6 climatology from historical file
    cat(blue_text, paste0("\tLoading historical CMIP6 climatology: ", clim_years[1], ":", clim_years[length(clim_years)]), reset_text, "\n")
    cmip6_clim <- loadGridData(
      dataset = hist_file,
      var = var,
      lonLim = lon_lim,
      latLim = lat_lim,
      years = clim_years)
    cmip6_clim <- set_monthly_dates(cmip6_clim, clim_years[1], length(clim_years) * 12L)
    stopifnot(identical(dim(obs_clim$Data), dim(cmip6_clim$Data)))
    # correct historical period (1990:2014)
    cat(blue_text, paste0("\tProcessing historical: ", hist_years[1], ":", hist_years[length(hist_years)]), reset_text, "\n")
    cmip6_scen <- loadGridData(
      dataset = hist_file,
      var = var,
      lonLim = lon_lim,
      latLim = lat_lim,
      years = hist_years)
    cmip6_scen <- set_monthly_dates(cmip6_scen, hist_years[1], length(hist_years) * 12L)
    tStart <- Sys.time()
    cat(blue_text, paste0("\tStarting QDM bias correction. Start time: ", format(tStart, "%Y-%m-%d %H:%M")), reset_text, "\n")
    cmip6_qdmScen <- tryCatch({
      biasCorrection(
        y = obs_clim,
        x = cmip6_clim,
        newdata = cmip6_scen,
        precipitation = is_precip,
        parallel = TRUE,
        max.ncores = 10L,
        ncores = 10L,
        method = "qdm")
    }, error = function(e) {
      cat(red_text, paste0("\tQDM failed for ", model, " ", var, " historical: ", conditionMessage(e)), reset_text, "\n")
      return(NULL)
    })
    tEnd <- Sys.time()
    cat(blue_text, paste0("\tFinished QDM bias correction. Start time: ", format(tEnd, "%Y-%m-%d %H:%M")), reset_text, "\n")
    cat(blue_text, paste0("\tElapsed time: ", round(difftime(tEnd, tStart, units = "hours"), 2), " hours."), reset_text, "\n")
    if (!is.null(cmip6_qdmScen)) {
      # if historical is corrected then write out to netcdf
      cmip6_qdmScen$Dates$end <- NULL
      cmip6_qdmScen$Dates$start <- seq(as.Date(cmip6_qdmScen$Dates$start[1]), by = "month", l = dim(cmip6_qdmScen$Data)[1])
      tstart <- format(as.Date(cmip6_qdmScen$Dates$start[1]), "%Y%m")
      tend <- format(as.Date(cmip6_qdmScen$Dates$start[length(cmip6_qdmScen$Dates$start)]), "%Y%m")
      out_name <- paste0(var, "_", model, "_historical_r1i1p1f1_", tstart, "-", tend, ".nc")
      outF <- file.path(out_root, out_name)
      cat(green_text, paste0("\tWriting outfile: ", outF), reset_text, "\n")
      grid2nc(
        data = cmip6_qdmScen,
        NetCDFOutFile = outF,
        globalAttributes = list(
          "Author" = "Stu",
          "Date" = as.character(Sys.Date()),
          "Method" = "QDM bias correction",
          "Notes" = paste0("Climatology period ", clim_years[1], "-01:", clim_years[length(clim_years)], "-12"),
          "loadeR.2nc" = "version 1.8.6.9"),
        verbose = FALSE,
        missval = -999,
        compression = NA,
        prec = "float")
      cat(green_text, paste0("\tWritten: ", outF), reset_text, "\n")
    }
    # correct each SSP experiment and temporal chunk
    for (experiment in experiments) {
      ssp_file <- find_input_file(var, model, experiment, input_root)
      if (is.na(ssp_file)) {
        cat(red_text, paste0("\tNo file found for ", model, " ", var, " ", experiment, ", skipping"), reset_text, "\n")
        next
      }
      for (chunk in ssp_chunks) {
        chunk_years <- unlist(chunk)[1]:unlist(chunk)[2]
        cat(blue_text, paste0("\tProcessing ", experiment, ": ", unlist(chunk)[1], ":", unlist(chunk)[2]), reset_text, "\n")
        cmip6_scen <- tryCatch({
          loadGridData(
            dataset = ssp_file,
            var = var,
            lonLim = lon_lim,
            latLim = lat_lim,
            years = chunk_years)},
          error = function(e) {
          cat(red_text, paste0("\tFailed to load ", experiment, " chunk ", chunk[1], "-", unlist(chunk)[2], ": ", conditionMessage(e)), reset_text, "\n")
          return(NULL)
        })
        if (is.null(cmip6_scen)) {
          next
        }
        cmip6_scen <- set_monthly_dates(cmip6_scen, chunk_years[1], length(chunk_years) * 12L)
        tStart <- Sys.time()
        cat(blue_text, paste0("\tStarting QDM bias correction. Start time: ", format(tStart, "%Y-%m-%d %H:%M")), reset_text, "\n")
        cmip6_qdmScen <- tryCatch({
          biasCorrection(
            y = obs_clim,
            x = cmip6_clim,
            newdata = cmip6_scen,
            precipitation = is_precip,
            parallel = TRUE,
            max.ncores = 10L,
            ncores = 10L,
            method = "qdm")
        }, error = function(e) {
          cat(red_text, paste0("\tQDM failed for ", model, " ", var, " ", experiment, " ", chunk[1], "-", chunk[2], ": ", conditionMessage(e)), reset_text, "\n")
          return(NULL)
        })
        tEnd <- Sys.time()
        cat(blue_text, paste0("\tFinished QDM bias correction. Start time: ", format(tEnd, "%Y-%m-%d %H:%M")), reset_text, "\n")
        cat(blue_text, paste0("\tElapsed time: ", round(difftime(tEnd, tStart, units = "hours"), 2), " hours."), reset_text, "\n")
        if (is.null(cmip6_qdmScen)) {
          cat(red_text, paste0("\tFailed QDM bias correction: ", model, ", ", var, ", ", experiment, ", ", paste(unlist(chunk), collapse = ":")), reset_text, "\n")
          next
        }
        cmip6_qdmScen$Dates$end <- NULL
        cmip6_qdmScen$Dates$start <- seq(as.Date(cmip6_qdmScen$Dates$start[1]), by = "month", l = dim(cmip6_qdmScen$Data)[1])
        tstart <- format(as.Date(cmip6_qdmScen$Dates$start[1]), "%Y%m")
        tend <- format(as.Date(cmip6_qdmScen$Dates$start[length(cmip6_qdmScen$Dates$start)]), "%Y%m")
        out_name <- paste0(var, "_", model, "_", experiment, "_r1i1p1f1_", tstart, "-", tend, ".nc")
        outF <- file.path(out_root, out_name)
        cat(green_text, paste0("\tWriting outfile: ", outF), reset_text, "\n")
        grid2nc(
          data = cmip6_qdmScen,
          NetCDFOutFile = outF,
          globalAttributes = list(
            "Author" = "Stu",
            "Date" = as.character(Sys.Date()),
            "Method" = "QDM bias correction",
            "Notes" = paste0("Climatology period ", clim_years[1], "-01:", clim_years[length(clim_years)], "-12"),
            "loadeR.2nc" = "version 1.8.6.9"),
          verbose = FALSE,
          missval = -999,
          compression = NA,
          prec = "float")
        cat(green_text, paste0("\tWritten: ", outF), reset_text, "\n")
      }
    }
  }
}

message("All done.")
