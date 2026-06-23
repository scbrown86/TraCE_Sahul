# library(devtools)
# install_github(c("SantanderMetGroup/loadeR.java",
#                  "SantanderMetGroup/climate4R.UDG",
#                  "SantanderMetGroup/loadeR",
#                  "SantanderMetGroup/transformeR",
#                  "SantanderMetGroup/visualizeR",
#                  "SantanderMetGroup/downscaleR"))

# Java options. Need to be run before any packages are loaded
## sets max RAM for Java to 128GB
options(java.parameters = "-Xmx128g"); gc()

#### LOAD LIBS AND FUNCTIONS ####
# Load libraries
library(loadeR)
library(downscaleR)
library(transformeR)
library(visualizeR)
library(loadeR.2nc)
library(parallel)

# load in the obs data
trace_sahul <- "/mnt/Data/TraCE-Sahul/pr/TraCE-Sahul_1500_1990_pr.nc"
obs_clim <- loadGridData(dataset = trace_sahul,
                              var = "pr",
                              # lonLim = c(138, 146),
                              # latLim= c(-18, -9),
                              years = 1960:1989)
obs_clim$Dates$start <- obs_clim$Dates$end <- as.POSIXct(seq(as.Date("1960-01-16"), as.Date("1989-12-16"), by = "month"),
                                                         tz = "", format = "%Y-%m-%d")
str(obs_clim)
temporalPlot("TraCE-Sahul" = obs_clim,
               cols = "black", lty = 1,
               xyplot.custom = list(main = "Monthly pr",
                                    xlab = "Date",
                                    ylab = "pr (mm/month)"))
spatialPlot(climatology(subsetGrid(obs_clim, years = 1989)), backdrop.theme = "coastline")

# CMIP6 data
cmip6_clim <- loadGridData("/mnt/Data/CMIP6/historical/pr/pr_ACCESS-ESM1-5_historical_r1i1p1f1_185001-201412.nc",
                           lonLim = c(138, 146), latLim = c(-18, -9),
                           var = "pr", years = 1960:1989)
cmip6_clim$Dates$start <- cmip6_clim$Dates$end <- obs_clim$Dates$start
str(cmip6_clim)

stopifnot(identical(dim(obs_clim$Data), dim(cmip6_clim$Data)))

cmip6_scen <- loadGridData("/mnt/Data/CMIP6/historical/pr/pr_ACCESS-ESM1-5_historical_r1i1p1f1_185001-201412.nc",
                           lonLim = c(138, 146), latLim = c(-18, -9),
                           var = "pr", years = 1990:2014)
cmip6_scen$Dates$start <- cmip6_scen$Dates$end <- as.POSIXct(
  seq(as.Date("1990-01-16"), as.Date("2014-12-16"), by = "month"),
  tz = "", format = "%Y-%m-%d")
str(cmip6_scen)

# Perform QDM correction
cmip6_qdmScen <- biasCorrection(
  ## Climatology period = 1940:1989
  y = obs_clim,
  x = cmip6_clim,
  ## Apply the correction to the full scenario period
  ## Histo = 1985:2014, SSP = 2015:2030; 2031:2040; 2041:2060; 2061:2080; 2081:2100
  newdata = cmip6_scen,
  precipitation = TRUE,
  parallel = TRUE,
  max.ncores = 3L,
  n.quantiles = 30,
  ncores = 3L,
  method = "qdm")
cmip6_qdmScen$Dates$end <- NULL ### remove end dates
cmip6_qdmScen$Dates$start <- seq(as.Date(as.Date(cmip6_qdmScen$Dates$start[1])),
                                         by = "month", l = dim(cmip6_qdmScen$Data)[1])
str(cmip6_qdmScen)

print(temporalPlot(
  "TraCE-Sahul" = obs_clim,
  "CMIP6 (bias)" = cmip6_scen,
  "CMIP6 (qdm)" = cmip6_qdmScen,
  cols = c("#bf616a", "#ebcb8b", "#a3be8c"),
  lty = c(1,1,2), lwd = c(2,1,2),
  xyplot.custom = list(xlab = "Date",
                       ylab = "precip (mm/month)",
                       xlim = c(as.Date("1960-01-01"),
                                as.Date("2015-01-01")))))

grid2nc(data = cmip6_qdmScen,
        NetCDFOutFile = "/mnt/Data/CMIP6/bias_corrected/pr_ACCESS-ESM1-5_ssp370_r1i1p1f1_199001-201412.nc",
        globalAttributes = list(
          "Author" = "Stuart C Brown",
          "Date" = Sys.Date(),
          "Method" = "QDM bias correction",
          "Notes" = "no smoothing window. Climatology period 1960-01:1989-12",
          "loadeR.2nc" = "version 0.1.2"
        ),
        verbose = TRUE,
        missval = -999,
        compression = NA,
        prec = "float")
