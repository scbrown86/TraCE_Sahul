library(data.table)
time_steps <- readRDS("/home/dafcluster4/Documents/GitHub/TraCE_Sahul/02_data/downTrace_timesteps.RDS")
time_steps <- copy(time_steps)[Year <= 1499, ][, .(Month = 1:12, Year = ceiling(mean(Year))), by = dec]
time_steps[, `:=`(StartYear = Year - 5, EndYear = Year + 4)]
time_steps[, DecYear := Year + ((Month - 0.5)/12)]
time_steps[, file_step := c(rep(1:5, each = 4812), rep(6, times = 1800))]
time_steps[, layerID := 1:nrow(time_steps)]
setcolorder(time_steps, "layerID")
fwrite(time_steps, "02_data/downTrace_timesteps_paleoDecades.csv")