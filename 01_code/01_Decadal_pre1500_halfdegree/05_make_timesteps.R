library(data.table)
library(terra)

# Create the paleo timesteps
base_dir <- "/mnt/Data/TraCE21_SahulHalfDeg/"
n <- nlyr(rast(file.path(base_dir, "PRECC/trace.01-35.22000BP-1500CE.cam2.h0.PRECC.0000101-258600.Sahul.decavg.concat.nc")))
n_decades <- n / 12  # 2155
steps <- seq(1, by = 120, length.out = n_decades)
ends <- steps + 119
mids_months <- (steps + ends) / 2
mids_years <- mids_months / 12
time_bp <- 22000 - mids_years
time_steps <- data.table(
  layerID = 1:n,
  dec = rep(1:n_decades, each = 12),
  Month = rep(1:12, times = n_decades),
  YearsBP = rep(ceiling(time_bp), each = 12),
  file_step = c(rep(1:5, each = 4812), rep(6, times = 1800)))
time_steps
time_steps[, YearsCE := 1950 - YearsBP]
time_steps[, dec_year := YearsCE + (Month - 1 + 15.5 / 30.4375) / 12]
time_steps[YearsCE <= 1450, ]
time_steps[, `:=`(StartYearCE = YearsCE - 5,
                  EndYearCE = YearsCE + 4,
                  StartYearBP = YearsBP + 5,
                  EndYearBP = YearsBP - 4)]
time_steps[YearsCE %in% c(-6:6), ] # what happens about year 0?
time_steps

# Post 1500 timesteps
monthly_years <- rep(1500:1989, each = 12)
monthly_months <- rep(1:12, times = 490)
monthly_rows <- data.table(
  layerID = (n + 1):(n + 490 * 12),
  dec = NA_integer_,
  Month = monthly_months,
  YearsBP = 1950L - monthly_years,
  YearsCE = monthly_years,
  file_step = NA_integer_)
monthly_rows[, dec_year := YearsCE + (Month - 1 + 15.5 / 30.4375) / 12]
monthly_rows[, `:=`(StartYearCE = YearsCE,
                    EndYearCE = YearsCE,
                    StartYearBP = YearsBP,
                    EndYearBP = YearsBP)]
monthly_rows

# combine
time_steps <- rbind(time_steps, monthly_rows)
time_steps
time_steps[1:25860, ]
time_steps[25861:nrow(time_steps), ]


# save
fwrite(time_steps, "02_data/downTrace_timesteps_paleoDecades.csv")
saveRDS(time_steps, "02_data/downTrace_timesteps.RDS")

