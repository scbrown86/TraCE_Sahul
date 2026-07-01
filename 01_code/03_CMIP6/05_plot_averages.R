library(data.table)
library(ggplot2)
library(pbapply)
library(ragg)

ssp_cols <- c("TraCE-Sahul" = "#7B3294",
              "Historical" = "#4A4A4A",
              "SSP1-2.6" = "#173C66",
              "SSP2-4.5" = "#F79420",
              "SSP3-7.0" = "#E71D25",
              "SSP5-8.5" = "#951B1E")
ens_stats <- c("ensmean", "enspctl10", "enspctl90")
exp_labels <- c("TraCE-Sahul" = "TraCE-Sahul",
                "historical" = "Historical",
                "ssp126" = "SSP1-2.6",
                "ssp245" = "SSP2-4.5",
                "ssp370" = "SSP3-7.0",
                "ssp585" = "SSP5-8.5")

# function to read in the CDO averages
avg_vals <- function(x) {
  parts <- strsplit(basename(tools::file_path_sans_ext(x)), split = "_")[[1]]
  if (length(parts) == 5) {
    names(parts)[1:5] <- c("var", "model", "experiment", "forcing", "time_period")
  } else {
    names(parts)[1:4] <- c("var", "model", "experiment", "time_period")
  }    
  vals <- data.table::fread(x, header = FALSE, skip = 1L)
  colnames(vals) <- c("Date", "Value")
  vals[, `:=`(Year = format(vals[["Date"]], "%Y"),
              Month = format(vals[["Date"]], "%b"),
              Variable = parts["var"],
              Model = parts["model"],
              Experiment = parts["experiment"])]
  return(vals)
}

# summarise function
make_summary_datasets <- function(dt,
                                  historical_period = c(1900L, 1989L),
                                  ssp_centres = c(2030L, 2050L, 2070L, 2090L),
                                  window = 20L) {
  dt <- copy(dt)
  dt[, Year := as.integer(Year)]
  dt[, Month := factor(Month, levels = month.abb)]
  # summary function
  summarise_dt <- function(x, groups) {
    x[, .(Mean = round(mean(Value), 2),
          Q10 = round(quantile(Value, 0.10, type = 8), 2),
          Q90 = round(quantile(Value, 0.90, type = 8), 2),
          Min = round(min(Value), 2),
          Max = round(max(Value), 2)),
      by = groups]
  }
  # Annual summaries
  annual <- summarise_dt(dt, groups = c("Variable", "Model", "Experiment", "Year"))
  # Unified window specs for monthly climatologies
  half_window <- window / 2L
  win_specs <- c(
    list(list(
      nm = sprintf("historical_%d_%d", historical_period[1], historical_period[2]),
      is_hist = TRUE,
      start = historical_period[1],
      end = historical_period[2])),
    lapply(ssp_centres, function(ctr) {
      list(nm = sprintf("ssp_%d", ctr),
           is_hist = FALSE,
           start = ctr - half_window,
           end = ctr + half_window - 1L)
    }))
  # Monthly climatologies
  monthly <- lapply(win_specs, function(w) {
    sub <- if (w$is_hist) {
      dt[Experiment %in% c("historical", "TraCE") & Year >= w$start & Year <= w$end]
    } else {
      dt[Experiment %notin% c("historical", "TraCE") & Year >= w$start & Year <= w$end]
    }
    summarise_dt(sub, groups = c("Variable", "Model", "Experiment", "Month"))
  })
  names(monthly) <- sapply(win_specs, `[[`, "nm")
  list(annual = annual, monthly = monthly)
}

cmip6_bias_corr <- list.files("/mnt/Data/CMIP6/bias_corrected/", pattern = ".txt$", recursive = TRUE, full.names = TRUE)
cmip6_bias_corr_avgs <- pblapply(cmip6_bias_corr, avg_vals)
cmip6_bias_corr_avgs[1:4]
cmip6_bias_corr_avgs <- rbindlist(cmip6_bias_corr_avgs)
cmip6_bias_corr_avgs

cmip6_summaries <- make_summary_datasets(cmip6_bias_corr_avgs)
cmip6_summaries

ssp_exps <- cmip6_summaries$annual[Experiment != "historical", unique(Experiment)]
hist_end <- cmip6_summaries$annual[
  Experiment == "historical",
  .SD[which.max(Year)],
  by = .(Variable, Model)]
bridge <- rbindlist(lapply(ssp_exps, function(e) {
  copy(hist_end)[, Experiment := e]
}))
cmip6_summaries$annual <- rbindlist(list(cmip6_summaries$annual, bridge),
                                    use.names = TRUE)
setorder(cmip6_summaries$annual, Variable, Model, Experiment, Year)
cmip6_summaries$annual[, exp_label := exp_labels[Experiment]]
invisible(lapply(cmip6_summaries$monthly,
                 function(dt) dt[, exp_label := exp_labels[Experiment]]))
cmip6_summaries$monthly

dt_members <- copy(cmip6_summaries$annual)[!Model %in% ens_stats]
dt_ens <- copy(cmip6_summaries$annual)[Model %in% ens_stats]

# Read in the TraCE-Sahul data for the 
trace_data <- rbindlist(
  list(fread("/mnt/Data/TraCE-Sahul/pr/TraCE-Sahul_1500_1990_pr.txt", header = FALSE, skip = 1L,
             col.names = c("Date", "Value"))[, `:=`(Year = rep(1500:1989, each = 12),
                                                    Month = rep(month.abb, times = 490),
                                                    Variable = "pr",
                                                    Model = "TraCE-Sahul",
                                                    Experiment = "TraCE")],
       fread("/mnt/Data/TraCE-Sahul/tasmax/TraCE-Sahul_1500_1990_tasmax.txt", header = FALSE, skip = 1L,
             col.names = c("Date", "Value"))[, `:=`(Year = rep(1500:1989, each = 12),
                                                    Month = rep(month.abb, times = 490),
                                                    Variable = "tasmax",
                                                    Model = "TraCE-Sahul",
                                                    Experiment = "TraCE")],
       fread("/mnt/Data/TraCE-Sahul/tasmin/TraCE-Sahul_1500_1990_tasmin.txt", header = FALSE, skip = 1L,
             col.names = c("Date", "Value"))[, `:=`(Year = rep(1500:1989, each = 12),
                                                    Month = rep(month.abb, times = 490),
                                                    Variable = "tasmin",
                                                    Model = "TraCE-Sahul",
                                                    Experiment = "TraCE")]))
trace_data
trace_data_summaries <- make_summary_datasets(trace_data)
trace_data_summaries

p <- ggplot() +
  geom_line(data = cmip6_summaries$annual[Model %notin% ens_stats, ],
            aes(x = Year, y = Mean,
                colour = exp_label,
                group = interaction(Model, Experiment)),
            linewidth = 0.25, alpha = 0.2) +
  geom_line(data = trace_data_summaries$annual,
            alpha = 0.5,
            aes(x = Year, y = Mean, colour = "TraCE-Sahul"),
            linewidth = 0.9) +
  geom_line(data = cmip6_summaries$annual[Model == "ensmean", ],
            alpha = 0.5,
            aes(x = Year, y = Mean, colour = exp_label,
                group = interaction(Model, Experiment)),
            linewidth = 0.9) +
  scale_colour_manual(name = NULL, values = ssp_cols,
                      breaks = c("TraCE-Sahul", "Historical", "SSP1-2.6", 
                                 "SSP2-4.5", "SSP3-7.0", "SSP5-8.5")) +
  facet_wrap(~Variable,
             scales = "free_y",
             ncol = 1,
             labeller = as_labeller(c(pr = "Precipitation (mm/month)", 
                                      tasmax = "Max. temperature (°C)", 
                                      tasmin = "Min. temperature (°C)")),
             strip.position = "left") +
  scale_x_continuous(breaks = seq(1900, 2100, by = 10),
                     expand = 0.01) +
  coord_cartesian(xlim = c(1900, 2100)) +
  labs(x = NULL, y = NULL) +
  theme_bw(base_size = 11) +
  theme(strip.placement = "outside",
        strip.background = element_blank(),
        strip.text = element_text(size = 10),
        legend.position = "bottom",
        legend.key.width = unit(1.5, "cm"),
        panel.grid.minor = element_blank())
p

# Monthly plots
cmip6_monthly_all <- rbindlist(cmip6_summaries$monthly, idcol = "Period")
trace_monthly <- copy(trace_data_summaries$monthly$historical_1900_1989)
trace_monthly[, Period := "trace_1900_1989"]
monthly_all <- rbindlist(list(cmip6_monthly_all, trace_monthly),
                         use.names = TRUE,
                         fill = TRUE)
monthly_all[Period == "trace_1900_1989", exp_label := "TraCE-Sahul"]
period_labels <- c(
  "trace_1900_1989" = "Historical (1900-1989)",
  "historical_1900_1989" = "Historical (1900-1989)",
  "ssp_2030" = "2020-2039",
  "ssp_2050" = "2040-2059",
  "ssp_2070" = "2060-2079",
  "ssp_2090" = "2080-2099")
monthly_all[, period_label := period_labels[Period]]
period_lty <- c(
  "Historical (1900-1989)" = "solid",
  "2020-2039" = "dotted",
  "2040-2059" = "dashed",
  "2060-2079" = "longdash",
  "2080-2099" = "twodash")
dt_monthly_plot <- monthly_all[Model %in% c("ensmean", "TraCE-Sahul")]
ens_stats <- c("ensmean", "enspctl10", "enspctl90")
dt_ribbon <- monthly_all[Model %notin% ens_stats,
                         .(Q10 = mean(Q10), Q90 = mean(Q90)),
                         by = .(Variable, Experiment, Period, Month, exp_label, period_label)]

period_label_levels <- c(
  "Historical (1900-1989)",
  "2020-2039",
  "2040-2059",
  "2060-2079",
  "2080-2099")
dt_monthly_plot[, period_label := factor(period_label, levels = period_label_levels)]
dt_ribbon[, period_label := factor(period_label, levels = period_label_levels)]

p_monthly <- ggplot(dt_monthly_plot,
                    aes(x = Month, y = Mean,
                        colour = exp_label,
                        group = interaction(Experiment, period_label))) +
  facet_grid(Variable ~ period_label,
             scales = "free_y", switch = "y",
             labeller = labeller(.rows = c(pr = "Precipitation (mm/month)",
                                           tasmax = "Max. temperature (°C)",
                                           tasmin = "Min. temperature (°C)"))) +
  geom_ribbon(data = dt_ribbon,
              inherit.aes = FALSE,
              aes(x = Month, ymin = Q10, ymax = Q90,
                  fill = exp_label,
                  group = interaction(Experiment, period_label)),
              colour = NA, alpha = 0.10, show.legend = FALSE) +
  geom_line(linewidth = 0.8, alpha = 0.5) +
  scale_colour_manual(name = NULL,
                      values = ssp_cols,
                      breaks = c("TraCE-Sahul", "Historical", "SSP1-2.6",
                                 "SSP2-4.5", "SSP3-7.0", "SSP5-8.5")) +
  scale_fill_manual(name = NULL, values = ssp_cols) +
  labs(x = NULL, y = NULL) +
  theme_bw(base_size = 11) +
  theme(strip.placement = "outside",
        strip.background = element_blank(),
        strip.text = element_text(size = 10),
        axis.text.x = element_text(angle = 90, vjust = 0.5),
        legend.position = "bottom",
        legend.key.width = unit(1.5, "cm"),
        panel.grid.minor = element_blank())
p_monthly

# Save figures
ragg::agg_png("/home/dafcluster4/Documents/GitHub/TraCE_Sahul/01_code/03_CMIP6/annual_timeseries_cmip6.png",
              height = 8, width = 12, units = "in",
              res = 320, background = "white")
p
dev.off()

ragg::agg_png("/home/dafcluster4/Documents/GitHub/TraCE_Sahul/01_code/03_CMIP6/monthly_timeseries_cmip6.png",
              height = 8, width = 14, units = "in",
              res = 320, background = "white")
p_monthly
dev.off()

pdf("/home/dafcluster4/Documents/GitHub/TraCE_Sahul/01_code/03_CMIP6/annual_timeseries_cmip6.pdf",
    bg = "white", height = 8, width = 12)
p
dev.off()

pdf("/home/dafcluster4/Documents/GitHub/TraCE_Sahul/01_code/03_CMIP6/monthly_timeseries_cmip6.pdf",
    height = 8, width = 14, bg = "white")
p_monthly
dev.off()
