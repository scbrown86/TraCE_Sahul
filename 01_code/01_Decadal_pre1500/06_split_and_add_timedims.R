#!/usr/bin/env Rscript

##################################################################################
##                          DO NOT RUN THIS SCRIPT                              ##
##  IT IS RUN FROM 01_code/01_Decadal_pre1500/05_bias_correction_dtr_method.sh  ##
##################################################################################

library(ncdf4)
library(data.table)

args <- commandArgs(trailingOnly = TRUE)
if(length(args) < 1){
  stop("You must supply a file path as the first argument")
}
fil <- args[1] # from arguments on command line

# cat("Processing file:", fil, "\n")

# read the timesteps
time_steps <- fread("/home/dafcluster4/Documents/GitHub/TraCE_Sahul/02_data/downTrace_timesteps_paleoDecades.csv")
# time_steps

# open the file and extract number of steps
f <- nc_open(fil, write = TRUE)
nt <- f$dim$time$len

if (nt == 25860) { # if full file, then replace with full time index
  time_index <- time_steps[["DecYear"]]
  stopifnot(length(unique(time_index)) ==  length(time_index))
  stopifnot(nt == length(time_index))
  # Overwrite existing time variable
  ncvar_put(f, "time", time_index)
  ncatt_put(f, "time", "units", "decimal year CE")
  ncatt_put(f, "time", "long_name", "decimal year (negative = BCE, positive = CE)")
  nc_close(f)
} else { # else use the dates for the step only
  # grab the "step" from the filename
  step <- as.integer(gsub(".nc", "", sapply(strsplit(basename(fil), "_"), tail, 1)))
  time_index <- time_steps[file_step == step, ][["DecYear"]]
  stopifnot(length(unique(time_index)) ==  length(time_index))
  stopifnot(nt == length(time_index))
  ncvar_put(f, "time", time_index)
  ncatt_put(f, "time", "units", "decimal year CE")
  ncatt_put(f, "time", "long_name", "decimal year (negative = BCE, positive = CE)")
  nc_close(f)
}