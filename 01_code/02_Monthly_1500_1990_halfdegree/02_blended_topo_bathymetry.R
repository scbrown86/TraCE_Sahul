library(terra)
library(data.table)
library(pbapply)

# Time steps
time_steps <- data.table("timeID" = seq(20, -200, by = -1),
                          "startyear" = seq(1900, -20100, by = -100),
                          "endyear" = c(1990, seq(1899, -20001, l = 220)),
                          "BP" = seq(0, by = 0.1, l = 221)*1000)
time_steps

# Load rasters
idx <- which(time_steps[["startyear"]] < 1500) # want pre-1500
fils <- gtools::mixedsort(list.files("/mnt/Data/CHELSA_Trace21/Input/halfdeg/",
                                    pattern = "dem_-?\\d+_V1\\.0\\.tif$",
                                    full.names = TRUE),
                         decreasing = TRUE)[idx]
fils
topo <- rast(lapply(fils, function(i) rast(i)))
topo
time(topo) <- as.integer(time_steps[idx, ][["BP"]])
topo
bathy <- rast("~/Documents/GEBCO_2014_2D_Sahul.nc") # single layer, contemporary
bathy <- resample(bathy, topo, "mean")
bathy
compareGeom(topo, bathy)

nrow(time_steps[idx, ])

# Sea level table from Karget et al tech info
## need to reverse order of rows
sea_level <- setorder(readRDS("02_data/Table5_Karger_Supp.RDS"),
                      -timeID)[-1, ]
sea_level[, timeID := time_steps[["timeID"]]]
sea_level

# subset both to timesteps in topo
time_steps <- copy(time_steps)[idx, ]
time_steps
sea_level <- copy(sea_level)[which(timeID %in% time_steps[["timeID"]]), ]
sea_level

stopifnot(nrow(time_steps) == nrow(sea_level))
stopifnot(nrow(time_steps) == nlyr(topo))

# iterate through, adjust sea level and blend
blended_topo_bath <- pblapply(seq_len(nrow(time_steps)), function(i) {
  tid <- time_steps[i, ][["timeID"]]
  sl_row <- copy(sea_level)[sea_level$timeID == tid, ]
  if (nrow(sl_row) == 0) {
    warning(paste("No sea level entry for timeID", tid, "- skipping"),
            immediate. = TRUE)
    return(NULL)
  }
  sl_offset <- sl_row[["sealevel"]]
  # Adjust bathymetry: subtract the (negative) sea level offset
  # This raises the seafloor relative to contemporary datum.
  # At LGM (sl = -122.2), bathy cells shallower than 122.2m become "land"
  bathy_adj <- bathy - sl_offset
  # Select the correct topography layer for this timestep
  # Assumes layers in topo are ordered to match time_steps rows
  topo_layer <- topo[[i]]
  # Blend: use topo where it defines land (topo > 0), bathy_adj elsewhere
  # Where topo > 0, that cell is land regardless of bathy
  blended <- ifel(topo_layer > 0, topo_layer, bathy_adj)
  time(blended) <- time_steps[i,][["BP"]]
  varnames(blended) <- "elevation"
  units(blended) <- "m"
  return(blended)
})
blended <- rast(blended_topo_bath)
depth(blended) <- NULL
blended <- setValues(blended, round(values(blended)))
plot(sum(blended > 0))
panel(blended[[floor(seq(1, nlyr(blended), l = 4))]] > 0)
blended

writeRaster(blended, "02_data/01_inputs/TraCE21_coarse_orog_bathy.tif",
            overwrite = TRUE,
            gdal = c("COMPRESS=LZW", "PREDICTOR=2"), datatype = "INT2S")
