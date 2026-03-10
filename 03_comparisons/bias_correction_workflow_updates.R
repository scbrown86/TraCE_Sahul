# ==============================================================================
# Bias Correction Workflow - Option 2
# Compute ratio at native resolution, smooth the ratio field via Gaussian kernel
#
# Inputs (user provided):
#   obs_rast   - SpatRaster, observed climatology (e.g. 1km res)
#   mod_rast   - SpatRaster, modelled climatology (e.g. 5km res)
#   land_mask  - SpatRaster, contemporary land mask (1 = land, NA = sea)
#
# Workflow:
#   1. Resample obs to match modelled grid (5km)
#   2. Compute log-ratio at 5km on contemporary land only
#   3. Project to equal-area CRS
#   4. Smooth/extrapolate log-ratio across full domain via Gaussian kernel
#   5. Reproject smoothed log-ratio back to WGS84
#   6. Apply exponentiated ratio to modelled field
# ==============================================================================

library(terra)
library(spatialEco)  # for Gaussian kernel smoothing via focal weights

# template raster at 0.05° res to make sure that
# anomalies etc. match the extent and res of our outputs
rast_template <- rast(res = 0.05, crs = "EPSG:4326", vals = 0L,
                      extent = ext(105, 161.25, -52.5, 11.25))

land <- vect(rnaturalearthhires::countries10)
land <- crop(land, rast_template)
land <- aggregate(land)

# ------------------------------------------------------------------------------
# 0. User inputs - load your own rasters here
# ------------------------------------------------------------------------------

obs_rast <- rast("02_data/02_processed/CHELSA/CHELSA_pr_climatology_coarse_remapcon.nc", win = ext(rast_template))
mod_rast <- rast("/media/dafcluster4/storage/TraCE_1500_1990CE/1500_1990/out/pr/TraCE_downscaled_1500_1990_concat.nc",
                  lyrs = 4801:5880, win = ext(rast_template))
time(mod_rast) <- seq(to = as.Date("1989-12-16"), by = "1 month", l = nlyr(mod_rast))
mod_clim <- tapp(mod_rast[[which(time(mod_rast) >= as.Date("1980-01-16"))]], "month", mean)

land_mask <- mod_rast[[1]]
land_mask <- ifel(is.na(land_mask), NA_integer_, 1L)  # 1 = land, NA = sea
plot(land_mask, fun = function () lines(land))

# ------------------------------------------------------------------------------
# 1. Constants
# ------------------------------------------------------------------------------

eps <- 0.0001 # kg m-2 month-1
eps <- eps / (86400*30) # kg m-2 s-1
sigma_km <- 100       # Gaussian kernel bandwidth in km - controls extrapolation reach
                     # increase if paleo land areas are far from contemporary coast

ea_crs <- 'PROJCS["Lambert_Azimuthal",
 GEOGCS["GCS_WGS_1984",
  DATUM["D_WGS_1984",
   SPHEROID["WGS_1984",6378137.0,298.257223563]],
  PRIMEM["Greenwich",0.0],
  UNIT["Degree",0.0174532925199433]],
 PROJECTION["Lambert_Azimuthal_Equal_Area"],
 PARAMETER["False_Easting",0.0],
 PARAMETER["False_Northing",0.0],
 PARAMETER["Central_Meridian",133],
 PARAMETER["Latitude_Of_Origin",-20.625],
 UNIT["Meter",1.0]]'   # equal-area CRS WKT string
ea_res <- 5000        # target cell size in metres (e.g. 5000 for 5km)
ea_ras <- project(rast_template, ea_crs)
res(ea_ras) <- ea_res
values(ea_ras) <- 1L
plot(ea_ras, fun = function() lines(project(land, ea_ras)))

# ------------------------------------------------------------------------------
# 2. Resample obs to modelled grid
#    Use bilinear for continuous precipitation fields
# ------------------------------------------------------------------------------

obs_5km <- resample(obs_rast, mod_rast,  method = "cubicspline")

# ------------------------------------------------------------------------------
# 3. Compute log-ratio on contemporary land only
#    Working in log space:
#      - maps multiplicative correction to additive scale
#      - symmetric around 0 (no correction = 0, not 1)
#      - avoids ratio explosion near zero better than raw ratio + eps alone
#      - well-behaved for spatial interpolation/smoothing
# ------------------------------------------------------------------------------

obs_land <- mask(obs_5km, land_mask)
mod_land <- mask(mod_clim, land_mask)

log_ratio <- log((obs_land + eps) / (mod_land + eps))
log_ratio
panel(log_ratio, fun = function() lines(land))
panel(exp(log_ratio), fun = function() lines(land),
     range = c(0, 4), fill_range = TRUE,
     main = month.abb,
     breaks = seq(0, 4, by = 0.1),
     col = hcl.colors(40, "Spectral"))
# ------------------------------------------------------------------------------
# 4. Project log-ratio to equal-area raster for spatially consistent smoothing
# ------------------------------------------------------------------------------

log_ratio_ea <- project(log_ratio, ea_ras, method = "cubicspline")
panel(log_ratio_ea, fun = function() lines(project(land, ea_ras)))

# ------------------------------------------------------------------------------
# 5. Build Gaussian kernel and smooth in equal-area space
#    res() now returns metres so sigma conversion is straightforward
#    na.policy = "only" allows corrections to extrapolate outward from
#    contemporary land into areas that are sea today but land in the
#    paleo simulation
# ------------------------------------------------------------------------------

kernel_mat <- focalMat(log_ratio_ea, d = sigma_km * 1000, type = "Gauss")

log_ratio_smooth_ea <- focal(
    log_ratio_ea,
    w = kernel_mat,
    fun = "mean",
    na.rm = TRUE,
    na.policy = "only")
panel(exp(log_ratio_smooth_ea), 
     fun = function() lines(project(land, ea_ras)),
     range = c(0, 4), fill_range = TRUE,
     main = month.abb,
     breaks = seq(0, 4, by = 0.1),
     col = hcl.colors(40, "Spectral"))

# Check for any remaining NAs (areas too isolated to receive correction signal)
# n_na <- global(is.na(log_ratio_smooth_ea), "sum")
# message("Cells with no correction coverage after smoothing: ", n_na$sum)

# Optional: fill any residual NAs with the global mean log-ratio as a fallback
# This should be rare if sigma_km is large enough relative to your domain
# global_mean_log_ratio <- global(log_ratio_ea, "mean", na.rm = TRUE)$mean
# log_ratio_smooth_ea <- cover(log_ratio_smooth_ea, log_ratio_ea * 0 + global_mean_log_ratio)


# ------------------------------------------------------------------------------
# 6. Reproject smoothed log-ratio back to WGS84 at original modelled resolution
# ------------------------------------------------------------------------------

log_ratio_smooth <- project(log_ratio_smooth_ea, mod_rast, method = "cubicspline")

# paleo mask
pal_mask <- rast("/media/dafcluster4/storage/TraCE_22k_1500CE/chunk_out/00001_00012/out/pr/CHELSA_pr_1_V.1.0.nc",
                 win = ext(rast_template))
pal_mask <- ifel(is.na(pal_mask), NA_integer_, 1L)

# masked ratio
log_ratio_smooth <- mask(log_ratio_smooth, pal_mask)


# ------------------------------------------------------------------------------
# 7. Convert log-ratio back to multiplicative ratio
# ------------------------------------------------------------------------------

ratio_smooth <- exp(log_ratio_smooth)
ratio_smooth
panel(ratio_smooth, fun = function() lines(land),
     range = c(0, 4), fill_range = TRUE,
     main = month.abb,
     breaks = seq(0, 4, by = 0.1),
     col = hcl.colors(40, "Spectral"))

# What about the original ratio correction
ratio_correction <- rast("02_data/02_processed/deltas/delta_fine_delta_pr_climatology_ncdf4.nc")*1
ratio_correction
panel(ratio_correction, fun = function() lines(land),
     range = c(0, 2), fill_range = TRUE,
     main = month.abb,
     breaks = seq(0, 2, by = 0.1),
     col = hcl.colors(20, "Spectral"))

# ------------------------------------------------------------------------------
# 8. Apply bias correction to modelled field
# ------------------------------------------------------------------------------

mod_corrected <- mod_rast * ratio_smooth


# ------------------------------------------------------------------------------
# 9. Sanity checks
# ------------------------------------------------------------------------------

# Ratio should be centred near 1.0 over contemporary land
ratio_land <- mask(ratio_smooth, land_mask)
message("Ratio summary over contemporary land:")
print(global(ratio_land, c("min", "mean", "max"), na.rm = TRUE))

# Check for unreasonable corrections (ratio > 10 or < 0.1 may warrant inspection)
extreme_high <- global(ratio_smooth > 10, "sum", na.rm = TRUE)$sum
extreme_low  <- global(ratio_smooth < 0.1, "sum", na.rm = TRUE)$sum
message("Cells with ratio > 10: ", extreme_high)
message("Cells with ratio < 0.1: ", extreme_low)


# ------------------------------------------------------------------------------
# 10. Write outputs
# ------------------------------------------------------------------------------

# writeRaster(log_ratio_smooth, "log_ratio_smooth_5km.tif", overwrite = TRUE)
# writeRaster(ratio_smooth,     "ratio_smooth_5km.tif",     overwrite = TRUE)
# writeRaster(mod_corrected,    "mod_corrected_5km.tif",    overwrite = TRUE)
