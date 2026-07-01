library(terra)
library(raster)
library(ncdf4)
library(openair)
library(ggplot2)
library(ggh4x)
library(data.table)
library(pbapply)
library(patchwork)

model_lvl <- c("ensmean", "ACCESS-ESM1-5", "CMCC-ESM2", "EC-Earth3", 
               "MPI-ESM1-2-HR", "MRI-ESM2-0", "NorESM2-MM")

model_cols <- RColorBrewer::brewer.pal(n = 6, name = "Dark2")

# function to extract file name
get_model_name <- function(filepath) {
  base <- tools::file_path_sans_ext(basename(filepath))
  if (grepl("^TraCE-Sahul", base)) {
    return("TraCE-Sahul")
  }
  parts <- strsplit(base, "_")[[1]]
  return(parts[2])
}

get_source_tag <- function(filepath) {
  if (grepl("CMIP6_bias_corrected", filepath)) {
    return("bias_corrected")
  } else if (grepl("CMIP6_historical", filepath)) {
    return("raw")
  } else if (grepl("ensemble", filepath)) {
    return("ensmean")
  } else if (grepl("TraCE-Sahul", filepath)) {
    return("TraCE-Sahul")
  } else {
    return(NA_character_)
  }
}

# make SDS
build_climatology_sds <- function(root, variables, types) {
  out <- list()
  for (var in variables) {
    for (type in types) {
      pattern <- paste0("_", type, "\\.nc$")
      files <- list.files(file.path(root, var),
                          pattern = pattern,
                          recursive = TRUE,
                          full.names = TRUE)
      files <- files[grepl(x = files, pattern = "CMIP6_bias_corrected|CMIP6_historical|ensmean|TraCE")]
      if (length(files) == 0) {
        warning(paste0("No files found for ", var, " ", type))
        next()
      }
      model_names <- vapply(files, get_model_name, character(1))
      source_tags <- vapply(files, get_source_tag, character(1))
      full_names <- ifelse(source_tags %in% c("ensmean", "TraCE-Sahul"),
                           source_tags,
                           paste0(model_names, "_", source_tags))
      ord <- order(full_names)
      files <- files[ord]
      full_names <- full_names[ord]
      fils <- pblapply(files, function(x) {
        r <- raster::brick(x)*1
        r <- terra::rast(r)
        terra::crs(r) <- "EPSG:4326"
        return(r)
      })
      sds_obj <- terra::sds(fils)
      names(sds_obj) <- full_names
      out[[paste0(var, "_", type)]] <- sds_obj
    }
  }
  return(out)
}

# sds to data.table
sds_to_datatable <- function(i) {
  dt <- pblapply(seq_along(i), function(j) {
    r <- i[j]
    if (terra::nlyr(r) == 4) {
      names(r) <- c("DJF", "MAM", "JJA", "SON")
    } else {
      names(r) <- month.abb
    }
    DT <- data.table::setDT(as.data.frame(r, xy = TRUE, wide = FALSE))
    DT[, Model := names(i)[j]]
    return(DT)
  })
}

prep_obs_mod <- function(x) {
  dt <- rbindlist(x)
  obs <- dt[Model == "TraCE-Sahul",
            .(x, y, layer, obs = values)]
  mod <- dt[Model != "TraCE-Sahul",
            .(x, y, layer,
              model = sub("_raw$|_bias_corrected$", "", Model),
              source = fcase(Model == "ensmean", "bias_corrected",
                             grepl("_raw$", Model), "raw",
                             grepl("_bias_corrected$", Model), "bias_corrected"),
              values)]
  mod <- dcast(mod, x + y + layer + model ~ source, value.var = "values")
  setnames(mod, c("raw", "bias_corrected"), c("mod_raw", "mod_biascorr"))
  mod[obs, on = .(x, y, layer), .(x, y, layer, obs = i.obs, mod_raw, mod_biascorr, model)]
}

add_panel_labels <- function(plot, labels, x = 0.03, y = Inf, hjust = 1, vjust = -1) {
  layers <- lapply(seq_along(labels), function(i) {
    at_panel(annotate("text", x = x, y = y,
                      label = paste0("bold(", labels[i], ")"), parse = TRUE,
                      hjust = hjust, vjust = vjust),
             PANEL == i)
  })
  Reduce(`+`, layers, plot)
}

# make an SDS for each climatology type
climatologies <- build_climatology_sds(
  root = "/home/dafcluster4/Desktop/validation_datasets_traceSahul_CMIP6",
  variables = c("pr", "tasmax", "tasmin"),
  types = c("yseasmean", "ymonmean"))
climatologies

# precip data.frame
precips <- sds_to_datatable(climatologies$pr_yseasmean)
precips <- prep_obs_mod(precips)
precips
precips[, `:=`(layer = factor(layer, levels = c("DJF", "MAM", "JJA", "SON")),
               model = factor(model, levels = model_lvl))]
precips

td_precip_s <- TaylorDiagram(precips,
                    obs = "obs",
                    mod = c("mod_biascorr", "mod_raw"),
                    group = "model",
                    type = "layer",
                    col = "Dark2",
                    text.obs = "",
                    annotate = "",
                    key.position = "bottom",
                    key.title = "Model",
                    key.columns = 7,
                    nrow = 1, ncol = 4,
                    normalise = TRUE,
                    plot = FALSE)
td_precip_s$plot
col_scale <- td_precip_s$plot$scales$get_scales("colour")
col_scale$breaks <- setdiff(col_scale$breaks, "")
shape_scale <- td_precip_s$plot$scales$get_scales("shape")
shape_scale$breaks <- setdiff(shape_scale$breaks, "")
# ragg::agg_png("/home/dafcluster4/Documents/GitHub/TraCE_Sahul/01_code/03_CMIP6/seasonal_taylor_precip.png",
#               height = 8, width = 12, units = "in",
#               res = 320, background = "white")
print(add_panel_labels(td_precip_s$plot, LETTERS[1:4]) +
        theme(legend.title.position = "top",
              strip.clip = "off",
              strip.placement = "inside",
              strip.background = element_blank(),
              strip.text = element_blank()))
# dev.off()
rm(col_scale, shape_scale); gc()

precipy <- sds_to_datatable(climatologies$pr_ymonmean)
precipy <- prep_obs_mod(precipy)
precipy[, `:=`(layer = factor(layer, levels = month.abb),
               model = factor(model, levels = model_lvl))]
precipy

td <- TaylorDiagram(precipy,
                    obs = "obs",
                    mod = c("mod_biascorr", "mod_raw"),
                    group = "model",
                    type = "layer",
                    col = "Dark2",
                    text.obs = "",
                    annotate = "",
                    key.position = "bottom",
                    key.title = "Model",
                    key.columns = 7,
                    nrow = 3, ncol = 4,
                    normalise = TRUE,
                    plot = FALSE)
ggplot_build(td$plot)$layout$layout
col_scale <- td$plot$scales$get_scales("colour")
col_scale$breaks <- setdiff(col_scale$breaks, "")
shape_scale <- td$plot$scales$get_scales("shape")
shape_scale$breaks <- setdiff(shape_scale$breaks, "")
ragg::agg_png("/home/dafcluster4/Documents/GitHub/TraCE_Sahul/01_code/03_CMIP6/monthly_taylor_precip.png",
              height = 12, width = 14, units = "in",
              res = 320, background = "white")
print(add_panel_labels(td$plot, LETTERS[1:12]) +
        theme(legend.title.position = "top",
              strip.clip = "off",
              strip.placement = "inside",
              strip.background = element_blank(),
              strip.text = element_blank()))
dev.off()
pdf("/home/dafcluster4/Documents/GitHub/TraCE_Sahul/01_code/03_CMIP6/monthly_taylor_precip.pdf",
              height = 12, width = 14, bg = "white")
print(add_panel_labels(td$plot, LETTERS[1:12]) +
        theme(legend.title.position = "top",
              strip.clip = "off",
              strip.placement = "inside",
              strip.background = element_blank(),
              strip.text = element_blank()))
dev.off()
rm(col_scale, shape_scale); gc()

# tasmax
tasmaxs <- sds_to_datatable(climatologies$tasmax_yseasmean)
tasmaxs <- prep_obs_mod(tasmaxs)
tasmaxs
tasmaxs[, `:=`(layer = factor(layer, levels = c("DJF", "MAM", "JJA", "SON")),
               model = factor(model, levels = model_lvl))]
td_tasmax_s <- TaylorDiagram(tasmaxs,
                    obs = "obs",
                    mod = c("mod_biascorr", "mod_raw"),
                    group = "model",
                    type = "layer",
                    col = "Dark2",
                    text.obs = "",
                    annotate = "",
                    key.position = "bottom",
                    key.title = "Model",
                    key.columns = 7,
                    nrow = 1, ncol = 4,
                    normalise = TRUE,
                    plot = FALSE)
ggplot_build(td_tasmax_s$plot)$layout$layout
col_scale <- td_tasmax_s$plot$scales$get_scales("colour")
col_scale$breaks <- setdiff(col_scale$breaks, "")
shape_scale <- td_tasmax_s$plot$scales$get_scales("shape")
shape_scale$breaks <- setdiff(shape_scale$breaks, "")
# ragg::agg_png("/home/dafcluster4/Documents/GitHub/TraCE_Sahul/01_code/03_CMIP6/seasonal_taylor_tasmax.png",
#               height = 8, width = 12, units = "in",
#               res = 320, background = "white")
print(add_panel_labels(td_tasmax_s$plot, LETTERS[5:8]) +
        theme(legend.title.position = "top",
              strip.clip = "off",
              strip.placement = "inside",
              strip.background = element_blank(),
              strip.text = element_blank()))
# dev.off()
rm(col_scale, shape_scale); gc()

tasmaxy <- sds_to_datatable(climatologies$tasmax_ymonmean)
tasmaxy <- prep_obs_mod(tasmaxy)
tasmaxy[, `:=`(layer = factor(layer, levels = month.abb),
               model = factor(model, levels = model_lvl))]
tasmaxy

td <- TaylorDiagram(tasmaxy,
                    obs = "obs",
                    mod = c("mod_biascorr", "mod_raw"),
                    group = "model",
                    type = "layer",
                    col = "Dark2",
                    text.obs = "",
                    annotate = "",
                    key.position = "bottom",
                    key.title = "Model",
                    key.columns = 7,
                    nrow = 3, ncol = 4,
                    normalise = TRUE,
                    plot = FALSE)
ggplot_build(td$plot)$layout$layout
col_scale <- td$plot$scales$get_scales("colour")
col_scale$breaks <- setdiff(col_scale$breaks, "")
shape_scale <- td$plot$scales$get_scales("shape")
shape_scale$breaks <- setdiff(shape_scale$breaks, "")
ragg::agg_png("/home/dafcluster4/Documents/GitHub/TraCE_Sahul/01_code/03_CMIP6/monthly_taylor_tasmax.png",
              height = 12, width = 14, units = "in",
              res = 320, background = "white")
print(add_panel_labels(td$plot, LETTERS[1:12]) +
        theme(legend.title.position = "top",
              strip.clip = "off",
              strip.placement = "inside",
              strip.background = element_blank(),
              strip.text = element_blank()))
dev.off()
pdf("/home/dafcluster4/Documents/GitHub/TraCE_Sahul/01_code/03_CMIP6/monthly_taylor_tasmax.pdf",
              height = 12, width = 14, bg = "white")
print(add_panel_labels(td$plot, LETTERS[1:12]) +
        theme(legend.title.position = "top",
              strip.clip = "off",
              strip.placement = "inside",
              strip.background = element_blank(),
              strip.text = element_blank()))
dev.off()
rm(col_scale, shape_scale); gc()

# tasmin
tasmins <- sds_to_datatable(climatologies$tasmin_yseasmean)
tasmins <- prep_obs_mod(tasmins)
tasmins
tasmins[, `:=`(layer = factor(layer, levels = c("DJF", "MAM", "JJA", "SON")),
               model = factor(model, levels = model_lvl))]
td_tasmin_s <- TaylorDiagram(tasmins,
                    obs = "obs",
                    mod = c("mod_biascorr", "mod_raw"),
                    group = "model",
                    type = "layer",
                    col = "Dark2",
                    text.obs = "",
                    annotate = "",
                    key.position = "bottom",
                    key.title = "Model",
                    key.columns = 7,
                    nrow = 1, ncol = 4,
                    normalise = TRUE,
                    plot = FALSE)
ggplot_build(td_tasmin_s$plot)$layout$layout
col_scale <- td_tasmin_s$plot$scales$get_scales("colour")
col_scale$breaks <- setdiff(col_scale$breaks, "")
shape_scale <- td_tasmin_s$plot$scales$get_scales("shape")
shape_scale$breaks <- setdiff(shape_scale$breaks, "")
# ragg::agg_png("/home/dafcluster4/Documents/GitHub/TraCE_Sahul/01_code/03_CMIP6/seasonal_taylor_tasmin.png",
#               height = 8, width = 12, units = "in",
#               res = 320, background = "white")
print(add_panel_labels(td_tasmin_s$plot, LETTERS[9:12]) +
        theme(legend.title.position = "top",
              strip.clip = "off",
              strip.placement = "inside",
              strip.background = element_blank(),
              strip.text = element_blank()))
# dev.off()
rm(col_scale, shape_scale); gc()

tasminy <- sds_to_datatable(climatologies$tasmin_ymonmean)
tasminy <- prep_obs_mod(tasminy)
tasminy[, `:=`(layer = factor(layer, levels = month.abb),
               model = factor(model, levels = model_lvl))]
tasminy

td <- TaylorDiagram(tasminy,
                    obs = "obs",
                    mod = c("mod_biascorr", "mod_raw"),
                    group = "model",
                    type = "layer",
                    col = "Dark2",
                    text.obs = "",
                    annotate = "",
                    key.position = "bottom",
                    key.title = "Model",
                    key.columns = 7,
                    nrow = 3, ncol = 4,
                    normalise = TRUE,
                    plot = FALSE)
ggplot_build(td$plot)$layout$layout
col_scale <- td$plot$scales$get_scales("colour")
col_scale$breaks <- setdiff(col_scale$breaks, "")
shape_scale <- td$plot$scales$get_scales("shape")
shape_scale$breaks <- setdiff(shape_scale$breaks, "")
ragg::agg_png("/home/dafcluster4/Documents/GitHub/TraCE_Sahul/01_code/03_CMIP6/monthly_taylor_tasmin.png",
              height = 12, width = 14, units = "in",
              res = 320, background = "white")
print(add_panel_labels(td$plot, LETTERS[1:12]) +
        theme(legend.title.position = "top",
              strip.clip = "off",
              strip.placement = "inside",
              strip.background = element_blank(),
              strip.text = element_blank()))
dev.off()
pdf("/home/dafcluster4/Documents/GitHub/TraCE_Sahul/01_code/03_CMIP6/monthly_taylor_tasmin.pdf",
              height = 12, width = 14, bg = "white")
print(add_panel_labels(td$plot, LETTERS[1:12]) +
        theme(legend.title.position = "top",
              strip.clip = "off",
              strip.placement = "inside",
              strip.background = element_blank(),
              strip.text = element_blank()))
dev.off()
rm(col_scale, shape_scale); gc()

# Combine the seasonal plots
first_row <- add_panel_labels(td_tasmax_s$plot, LETTERS[1:4]) +
  theme(legend.title.position = "top",
        strip.clip = "off",
        strip.placement = "inside",
        strip.background = element_blank(),
        strip.text = element_blank())
second_row <- add_panel_labels(td_tasmin_s$plot, LETTERS[5:8]) +
  theme(legend.title.position = "top",
        strip.clip = "off",
        strip.placement = "inside",
        strip.background = element_blank(),
        strip.text = element_blank())
third_row <- add_panel_labels(td_precip_s$plot, LETTERS[9:12]) +
  theme(legend.title.position = "top",
        strip.clip = "off",
        strip.placement = "inside",
        strip.background = element_blank(),
        strip.text = element_blank())
combine_seasonal <- wrap_plots(first_row +
                                 theme(legend.position = "none"),
                               second_row +
                                 theme(legend.position = "none"),
                               third_row,
                               ncol = 1,
                               axis_titles = "collect")
ragg::agg_png("/home/dafcluster4/Documents/GitHub/TraCE_Sahul/01_code/03_CMIP6/seasonal_taylor_combined.png",
              height = 14, width = 14, units = "in",
              res = 320, background = "white")
combine_seasonal
dev.off()

pdf("/home/dafcluster4/Documents/GitHub/TraCE_Sahul/01_code/03_CMIP6/seasonal_taylor_combined.pdf",
              height = 14, width = 14, bg = "white")
combine_seasonal
dev.off()
