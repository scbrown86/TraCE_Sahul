#!/usr/bin/env Rscript

library(ncdf4)
library(data.table)

args <- commandArgs(trailingOnly = TRUE)
if(length(args) < 1){
  stop("You must supply a file path as the first argument")
}
fil <- args[1] # from arguments on command line

cat("Processing file:", fil, "\n")

# create the timesteps
time_steps <- readRDS("/home/dafcluster4/Documents/GitHub/TraCE_Sahul/02_data/downTrace_timesteps.RDS")
time_steps <- copy(time_steps)[Year <= 1499, ][, .(Month = 1:12, Year = ceiling(mean(Year))), by = dec]
time_steps[, `:=`(StartYear = Year - 5, EndYear = Year + 4)]
time_steps[, DecYear := Year + ((Month - 0.5)/12)]
time_steps[, file_step := rep(1:12, each = 2155)]
# time_steps

# open the file and extract number of steps
f <- nc_open(fil, write = TRUE)
nt <- f$dim$time$len

# grab the "step" from the filename
step <- as.integer(gsub(".nc", "", sapply(strsplit(basename(fil), "_"), tail, 1)))
time_index <- time_steps[file_step == step, ][["DecYear"]]
stopifnot(length(unique(time_index)) ==  length(time_index))
stopifnot(nt == length(time_index))

# Overwrite existing time variable
ncvar_put(f, "time", time_index)
ncatt_put(f, "time", "units", "decimal year CE")
ncatt_put(f, "time", "long_name", "decimal year (negative = BCE, positive = CE)")
nc_close(f)

# Add human-readable time labels
f <- nc_open(fil, write = TRUE)
time_dim <- f$dim$time
time_labels_var <- ncvar_def("time_labels",
                             units = "none",
                             dim = list(time_dim),
                             longname = "Human-readable time labels (YYYY/MM/DD)",
                             prec = "char")
# Add the new variable to the file
f <- ncvar_add(f, time_labels_var)
labels <- sprintf("%d/%02d/%s",
                  time_steps[file_step == step, ][["Year"]],
                  time_steps[file_step == step, ][["Month"]],
                  "16")
# Write the labels into the new variable
ncvar_put(f, time_labels_var, labels)
nc_close(f)
