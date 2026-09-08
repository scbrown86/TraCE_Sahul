#  /media/dafcluster4/storage/TraCE_22k_1500CE/chunk_out/00001_00012/out/pr/CHELSA_pr_1_V.1.0_chunk0001.nc
library(terra)
library(pbapply)
library(future)
library(future.apply)

plan(multicore, workers = 64)

range <- seq(1, 25849, by = 12)
range_f <- sapply(range, function(v) {
    paste0(sprintf("%05d", v), "_", sprintf("%05d", v + 11))
})
vars <- c("pr", "tasmax", "tasmin")
results <- pbsapply(range_f, function(f) {
    d <- which(f == range_f)
    d <- sprintf("%04d", as.integer(d))
    needs_masking <- sapply(vars, function(v) {
        file <- file.path(sprintf(
            "/media/dafcluster4/storage/TraCE_22k_1500CE/chunk_out/%s/out/%s/CHELSA_%s_1_V.1.0_chunk%s.nc",
            f, v, v, d
        ))
        stopifnot(file.exists(file))
        r <- terra::rast(file, win = ext(113.225, 113.275, -16.025, -15.975))
        sna <- sum(is.na(as.vector(values(r))))
        if (sna < 1) {
            return(file)
        }
    })
    Filter(Negate(is.null), needs_masking)
}, simplify = FALSE, cl = "future")
results <- Filter(function(x) length(x) > 0, results)
results
saveRDS(results, "~/Desktop/need_masking_rasters.RDS")
results
