library(terra)

avg_vals <- function(x) {
    parts <- strsplit(basename(tools::file_path_sans_ext(x)), split = "_")[[1]]
    names(parts)[1:5] <- c("var", "model", "experiment", "forcing", "time_period")
    r <- rast(x)
    if (parts["experiment"] == "historical") {
        time(r) <- seq(as.Date("1900-01-16"), by = "month", l = nlyr(r))
    } else {
        time(r) <- seq(as.Date("2015-01-16"), by = "month", l = nlyr(r))
    }
    vals <- global(r, mean, na.rm = TRUE)

}