library(terra)
library(pbapply)
library(future)
library(MBC)

bias_correct_qdm <- function(obs_clim, mod_clim, mod_full, ratio = TRUE, 
                             nproc = 6L) {
  # obs_clim: SpatRaster, obs monthly data for climatological period (e.g. 1970-1989)
  # mod_clim: SpatRaster, model monthly data for same climatological period
  # mod_full: SpatRaster, model monthly data to be corrected (e.g. 1990-2100)
  # ratio: FALSE for temperature, TRUE for precipitation
  stopifnot(terra::nlyr(obs_clim) %% 12 == 0)
  stopifnot(terra::nlyr(mod_clim) %% 12 == 0)
  stopifnot(terra::nlyr(mod_full) %% 12 == 0)
  stopifnot(terra::nlyr(obs_clim) == terra::nlyr(mod_clim))
  stopifnot(terra::compareGeom(obs_clim, mod_clim, mod_full))
  n_years_clim <- terra::nlyr(obs_clim) / 12
  n_years_mod <- terra::nlyr(mod_clim) / 12
  message("Extracting raster data to matrices...")
  # extract to matrices: rows = cells, cols = layers
  valid_cells <- terra::cells(obs_clim[[1]])
  n_valid <- length(valid_cells)
  obs_valid <- terra::as.matrix(obs_clim[valid_cells])
  mod_valid <- terra::as.matrix(mod_clim[valid_cells])
  mod_full_valid <- terra::as.matrix(mod_full[valid_cells])
  message("Applying QDM to ", n_valid, " non-NA cells")
  month_idx_clim <- rep(1:12, times = n_years_clim)
  month_idx_mod <- rep(1:12, times = n_years_mod)
  # output matrix for valid cells only
  corrected_valid <- matrix(NA_real_, nrow = n_valid, ncol = terra::nlyr(mod_full))
  # process each month in parallel
  plan(multicore, workers = nproc)
  for (m in 1:12) {
    message("  Processing month ", m)
    clim_idx <- which(month_idx_clim == m)
    full_idx <- which(month_idx_mod == m)
    corrected_valid[, full_idx] <- t(pbapply::pbvapply(
      seq_len(n_valid),
      function(i) {
        MBC::QDM(
          o.c = obs_valid[i, clim_idx],
          m.c = mod_valid[i, clim_idx],
          m.p = mod_full_valid[i, full_idx],
          ratio = ratio)$mhat.p
      },
      FUN.VALUE = numeric(length(full_idx)),
      cl = "future"))
  }
  plan(sequential)
  # rebuild full matrix with NA for ocean cells
  out <- terra::rast(mod_full)
  out[valid_cells] <- corrected_valid
  return(out)
}

r <- rast("/mnt/Data/TraCE-Sahul/pr/TraCE-Sahul_1500_1990_pr.nc",
          md = TRUE, drivers = "NETCDF")
time(r) <- seq(as.Date("1500-01-16"), by = "month", l = nlyr(r))
r

(obs_clim <- r[[which(time(r) >= "1970-01-16")]]*1)
(mod_clim <- r[[which(time(r) >= "1950-01-16" & time(r) < as.Date("1970-01-16"))]]*1)
(mod_full <- r[[which(time(r) >= as.Date("1850-01-16") & time(r) < as.Date("1950-01-16"))]]*1)

mod_bc <- bias_correct_qdm(obs_clim, mod_clim, mod_full)