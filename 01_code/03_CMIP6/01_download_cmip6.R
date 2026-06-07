library(rcmip6)
library(data.table)

filter_replicas_smart <- function(dt) {
  node_preference <- c(
    "esgf-node.ornl.gov",
    "eagle.alcf.anl.gov",
    "aims3.llnl.gov",
    "esgf-data1.llnl.gov",
    "esgf-data2.llnl.gov",
    "esgf-data.dkrz.de",
    "esgf.ceda.ac.uk",
    "esgf-data04.diasjp.net")
  dtc <- copy(dt)[!is.na(datetime_start) & !is.na(datetime_end),
     if (any(!replica)) .SD[replica == FALSE] else .SD,
     by = .(source_id, experiment_id, variable_id)
  ][,
    node_rank := match(data_node, node_preference, nomatch = length(node_preference) + 1L)
  ][order(node_rank),
    .SD[1L],
    by = .(source_id, experiment_id, variable_id, instance_id)
  ][,
    node_rank := NULL][
      order(source_id, experiment_id, variable_id)
    ]
  return(dtc)
}

summarise_cmip6_availability <- function(dt) {
  var_label <- function(vars) {
    has_pr <- "pr" %in% vars
    has_tasmax <- "tasmax" %in% vars
    has_tasmin <- "tasmin" %in% vars
    has_tas <- has_tasmax & has_tasmin
    fcase(
      has_pr & has_tas, "PR+Tas",
      has_pr & has_tasmax, "PR+Tasmax",
      has_pr & has_tasmin, "PR+Tasmin",
      has_tas, "Tmin/Tmax",
      has_pr, "PR",
      has_tasmax, "Tasmax",
      has_tasmin, "Tasmin",
      default = NA_character_)
  }
  dt[,
     .(label = var_label(variable_id)),
     by = .(source_id, experiment_id)
  ] |>
    unique() |>
    dcast(source_id ~ experiment_id, value.var = "label")
}

results_simplify <- function(results) {
  cmip6_folder_template <- gsub("%\\(", "", cmip6_folder_template)
  cmip6_folder_template <- gsub("\\)s", "", cmip6_folder_template)
  columns <- colnames(results)
  vars <- c(strsplit(cmip6_folder_template, "/")[[1]], "variable_long_name",
            "datetime_start", "datetime_stop", "nominal_resolution")
  vars <- setdiff(vars, "root")
  simple <- results[, vars, with = FALSE]
  simple$full_info <- split(results[, -vars, with = FALSE],
                            seq_len(nrow(results)))
  class(simple) <- c("cmip_simple", class(simple))
  attr(simple, "column") <- columns
  simple
}

# URL from esgf metagrid search
json_url <- "https://esgf-node.ornl.gov/esgf-1-5-bridge?project=CMIP6&offset=0&limit=10000&type=Dataset&format=application%2Fsolr%2Bjson&facets=activity_id%2C+data_node%2C+source_id%2C+institution_id%2C+source_type%2C+experiment_id%2C+sub_experiment_id%2C+nominal_resolution%2C+variant_label%2C+grid_label%2C+table_id%2C+frequency%2C+realm%2C+variable_id%2C+cf_standard_name&latest=true&query=*&activity_id=ScenarioMIP%2CCMIP&experiment_id=historical%2Cssp245%2Cssp370%2Cssp126%2Cssp585&frequency=mon&source_id=ACCESS-ESM1-5%2CCMCC-ESM2%2CEC-Earth3%2CNorESM2-MM%2CMPI-ESM1-2-HR%2CMRI-ESM2-0&source_type=AOGCM&variable_id=tasmax%2Ctasmin%2Cpr&variant_label=r1i1p1f1"
cmip6_query <- cmip_url_to_list(json_url)

results <- cmip_search(query = cmip6_query)
saveRDS(results, "CMIP6_query_results.RDS")
results <- readRDS("CMIP6_query_results.RDS")
cmip_info(results)
results_clean <- filter_replicas_smart(results)
cmip_info(results_clean)
results_clean[, .N, by = data_node][order(-N)]
results_clean[1:10, ]

model_avail <- results_clean |>
  filter_replicas_smart() |>
  cmip_simplify() |>
  summarise_cmip6_availability()
model_avail

dl_config <- cmip_download_config(
  delay = 0.5,
  retry = 5,
  total_connections = 4L,
  host_connections = 2L,
  low_speed_limit = 100L,
  low_speed_time = 30L)

download_results <- cmip_download(
  results = results_clean,
  root = "/mnt/Data/CMIP6/",
  download_config = dl_config)

length(download_results)
download_results[[1]]

# download daily NorEMS2 data
# data will need to be aggregated to monthly in processing script
nor_url <- "https://esgf-node.ornl.gov/esgf-1-5-bridge?project=CMIP6&offset=0&limit=100&type=Dataset&format=application%2Fsolr%2Bjson&facets=activity_id%2C+data_node%2C+source_id%2C+institution_id%2C+source_type%2C+experiment_id%2C+sub_experiment_id%2C+nominal_resolution%2C+variant_label%2C+grid_label%2C+table_id%2C+frequency%2C+realm%2C+variable_id%2C+cf_standard_name&latest=true&query=*&experiment_id=ssp245%2Cssp585%2Cssp370%2Cssp126%2Chistorical&frequency=day&source_id=NorESM2-MM&variable_id=tasmin%2Ctasmax%2Cpr&variant_label=r1i1p1f1"
nor_query <- cmip_url_to_list(nor_url)

nor_results <- cmip_search(query = nor_query)
saveRDS(nor_results, "CMIP6_nor_query_results.RDS")
nor_results <- readRDS("CMIP6_nor_query_results.RDS")
cmip_info(nor_results)
nor_results_clean <- filter_replicas_smart(nor_results)
cmip_info(nor_results_clean)
nor_results_clean[, .N, by = data_node][order(-N)]
nor_results_clean[1:10, ]

nor_model_avail <- nor_results_clean |>
  filter_replicas_smart() |>
  cmip_simplify() |>
  summarise_cmip6_availability()
nor_model_avail

nor_download_results <- cmip_download(
  results = nor_results_clean,
  root = "/mnt/Data/CMIP6/",
  year_range = c(1850, 2100), #< restrict to 1850:2100 due to file size
  download_config = dl_config)

length(nor_download_results)
nor_download_results[[1]]
