#!/usr/bin/env python3
"""
QDM correction with Dask (50-year chunks), subset test data to 1950-01 -> 1989-12.
Designed for local workstation: 128 cores, 250 GB RAM.

Dependencies:
    numpy, pandas, xarray, dask, dask.distributed, rioxarray, xsdba, xclim, xarray-sdba (xsdba)
"""

import os
import numpy as np
import xarray as xr
import rioxarray
from dask.distributed import Client, LocalCluster, progress
from dask.diagnostics import ProgressBar
import dask
import xsdba

# Optional: switch scheduler
dask.config.set(scheduler="processes")  # or "threads" (default)

# -----------------------------
# User-editable settings
# -----------------------------
OBS_PATH = "/02_data/02_processed/CHELSA/CHELSA_0p05_pr_climatology.nc"
SIM_PATH = "02_data/02_processed/TRACE/TraCE_0p05_pr_climatology.nc"
TEST_PATH = "storage/TraCE_1500_1990CE/1500_1990/out/pr/TraCE_downscaled_1500_1990_concat.nc"

OUTPUT_QDM_TRAINED = "python_test/qdm_trained_pr_Sahul.nc"
OUTPUT_ADJUSTED = "storage/TraCE_1500_1990CE/1500_1990/out/pr/TraCE_22ka_downscaled_pr_1950_1989_qdm.nc"

# chunking: 50 years -> 50 * 12 months
YEARS_PER_CHUNK = 50
MONTHS_PER_CHUNK = YEARS_PER_CHUNK * 12  # = 600

# Dask local cluster config tuned to 128 cores / 250 GB
N_WORKERS = 64                 # 64 workers × 2 threads = 128 threads
THREADS_PER_WORKER = 2
MEMORY_LIMIT_PER_WORKER = "3.5GB"  # ~64 * 3.5 = 224 GB total (tune if needed)

# subset test data to this period (user requested)
TEST_SUBSET_START = "1950-01-01"
TEST_SUBSET_END = "1989-12-31"

# # -----------------------------
# # Start Dask LocalCluster & Client
# # -----------------------------
# print("Starting Dask LocalCluster...")
# cluster = LocalCluster(
#     n_workers=N_WORKERS,
#     threads_per_worker=THREADS_PER_WORKER,
#     memory_limit=MEMORY_LIMIT_PER_WORKER,
#     processes=True,
#     silence_logs=logging.WARNING if 'logging' in globals() else 'error',
# )
# client = Client(cluster)
# print("Dask client started:")
# print(client)
# print(f"Dask dashboard available at: {client.dashboard_link}")

# Helpful: limit xarray's default chunking behavior (optional)
xr.set_options(keep_attrs=True)

# -----------------------------
# Open small climatologies (obs, sim) with Dask
# -----------------------------
print("Opening climatology files (lazy, with dask chunks)...")
obs = xr.open_dataset(OBS_PATH, decode_times=False, chunks={"time": -1})["pr"]
sim = xr.open_dataset(SIM_PATH, decode_times=False, chunks={"time": -1})["pr"]

# Ensure time coordinates are months Jan-Dec (climatologies)
months_clim = xr.date_range(
    start="1985-01-01", end="1985-12-31", freq="ME", calendar="noleap", use_cftime=True
)
obs = obs.assign_coords(time=months_clim)
sim = sim.assign_coords(time=months_clim)

# Normalize name of lat/lon if needed
if "longitude" in obs.coords: obs = obs.rename({"longitude": "lon"})
if "latitude" in obs.coords: obs = obs.rename({"latitude": "lat"})
if "longitude" in sim.coords: sim = sim.rename({"longitude": "lon"})
if "latitude" in sim.coords: sim = sim.rename({"latitude": "lat"})

print("obs:", obs)
print("sim:", sim)

# -----------------------------
# Open large simulated dataset with Dask and subset to 1950-1989
# -----------------------------
print("Opening large test dataset (lazy) and subsetting to 1950-01 -> 1989-12 ...")
downTrace = xr.open_dataset(TEST_PATH, decode_times=False, chunks={"time": MONTHS_PER_CHUNK})["pr"]

# assign full time coords then subset
months_full = xr.date_range(
    start="1500-01-01", end="1989-12-31", freq="ME", calendar="noleap", use_cftime=True
)
downTrace = downTrace.assign_coords(time=months_full)

# subset to requested window
downTrace = downTrace.sel(time=slice(TEST_SUBSET_START, TEST_SUBSET_END))
print("downTrace (subset):", downTrace)
print("downTrace size (months):", downTrace.sizes.get("time"))

# -----------------------------
# Assign CRS (rioxarray) - ensure arrays can be reprojected if needed
# -----------------------------
print("Writing CRS (EPSG:4326) to DataArrays (lazy metadata only)...")
obs = obs.rio.write_crs("EPSG:4326")
sim = sim.rio.write_crs("EPSG:4326")
downTrace = downTrace.rio.write_crs("EPSG:4326")

# -----------------------------
# Reproject obs/sim to grid of downTrace
# -----------------------------
# rioxarray needs x/y names for reproject; create x/y copies for the operation
print("Preparing names for reprojection (rioxarray expects x/y)...")
obs_xy = obs.rename({"lat": "y", "lon": "x"})
sim_xy = sim.rename({"lat": "y", "lon": "x"})
downTrace_xy = downTrace.rename({"lat": "y", "lon": "x"})

print("Reprojecting obs and sim to match downTrace grid (this may do some compute)...")
# reproject_match returns a lazily reprojected DataArray (but may trigger some work)
obs_xy = obs_xy.rio.reproject_match(downTrace_xy)
sim_xy = sim_xy.rio.reproject_match(downTrace_xy)

# Rename back to lat/lon
obs = obs_xy.rename({"y": "lat", "x": "lon"})
sim = sim_xy.rename({"y": "lat", "x": "lon"})
downTrace = downTrace_xy.rename({"y": "lat", "x": "lon"})

# -----------------------------
# Rechunk datasets to 50-year time chunks and reasonable spatial chunks
# -----------------------------
print("Calculating dynamic lat/lon chunk sizes...")
# suggested splits: approx 5 splits along each spatial axis (tunable)
n_spatial_splits = 5
lat_len = downTrace.sizes["lat"]
lon_len = downTrace.sizes["lon"]
lat_chunk = max(1, lat_len // n_spatial_splits)
lon_chunk = max(1, lon_len // n_spatial_splits)

print(f"Using chunk sizes -> time: {MONTHS_PER_CHUNK}, lat: {lat_chunk}, lon: {lon_chunk}")

obs = obs.chunk({"time": -1, "lat": lat_chunk, "lon": lon_chunk})
sim = sim.chunk({"time": -1, "lat": lat_chunk, "lon": lon_chunk})
downTrace = downTrace.chunk({"time": MONTHS_PER_CHUNK, "lat": lat_chunk, "lon": lon_chunk})

# Print chunk info for sanity
print("Chunks (obs):", obs.chunks)
print("Chunks (sim):", sim.chunks)
print("Chunks (downTrace):", downTrace.chunks)

# -----------------------------
# Utility: bbox printer (no heavy compute)
# -----------------------------
def print_bbox(da, name="DataArray"):
    # we call .values on coords only (small)
    lat_vals = xr.DataArray(da["lat"]).values
    lon_vals = xr.DataArray(da["lon"]).values
    lat_min, lat_max = float(np.nanmin(lat_vals)), float(np.nanmax(lat_vals))
    lon_min, lon_max = float(np.nanmin(lon_vals)), float(np.nanmax(lon_vals))
    print(f"{name} bounding box:")
    print(f"  lat: {lat_min} → {lat_max}")
    print(f"  lon: {lon_min} → {lon_max}")
    print()

print_bbox(obs, "obs")
print_bbox(sim, "sim")
print_bbox(downTrace, "downTrace (subset)")

# -----------------------------
# Train QDM (xsdba) using climatologies
# -----------------------------
print("Training QDM (this will build a dask graph but is typically lightweight for climatologies)...")
qdm = xsdba.adjustment.QuantileDeltaMapping.train(obs, sim, nquantiles=101, kind="*", group="time.month")

print("QDM trained; dataset summary:")
print(qdm.ds)

# Save trained QDM to NetCDF (small compute)
print(f"Saving trained QDM to {OUTPUT_QDM_TRAINED} ...")
with ProgressBar():
    # Use compute=True so small compute happens now and file is written
    qdm.ds.to_netcdf(OUTPUT_QDM_TRAINED, compute=True)
print("QDM saved.")

# -----------------------------
# Apply QDM to test (use the whole subset 1950-1989)
# -----------------------------
print("Selecting the test window (1950-01 to 1989-12) and chunking appropriately...")
test_window = downTrace.sel(time=slice(TEST_SUBSET_START, TEST_SUBSET_END))
test_window = test_window.chunk({"time": MONTHS_PER_CHUNK, "lat": lat_chunk, "lon": lon_chunk})

print("Applying QDM.adjust(...) to test window (lazy) ...")
adjTest = qdm.adjust(test_window, extrapolation="constant", interp="linear")
adjTest = adjTest.transpose("time", "lat", "lon")  # good order for many operations

# Optionally: add encoding to control compression and chunking in final file
encoding = {}
if isinstance(adjTest, xr.DataArray):
    # as DataArray -> convert to Dataset wrapper for to_netcdf encoding convenience
    ds_to_save = adjTest.to_dataset(name="pr")
else:
    ds_to_save = adjTest.ds if hasattr(adjTest, "ds") else adjTest

# Set zlib compression and preserve original attributes
for v in ds_to_save.data_vars:
    encoding[v] = {"zlib": True, "complevel": 4, "shuffle": True}
    # set chunking on file to match dask chunk (netCDF4/h5netcdf will use them)
    encoding[v]["chunksizes"] = (min(ds_to_save.sizes.get("time", MONTHS_PER_CHUNK), MONTHS_PER_CHUNK),
                                 min(ds_to_save.sizes.get("lat", lat_chunk), lat_chunk),
                                 min(ds_to_save.sizes.get("lon", lon_chunk), lon_chunk))

# -----------------------------
# Persist adjusted result to avoid recomputing repeatedly during write
# -----------------------------
print("Persisting adjusted data in cluster memory (this will transfer computed chunks into workers' memory).")
# Only persist if you have ample memory; monitor the cluster dashboard!
adj_persisted = ds_to_save.persist()
print("Persist triggered. Use dashboard to monitor memory and task progress.")

# Wait for persist to complete (show progress)
print("Waiting for persist to finish...")
with ProgressBar():
    dask.distributed.wait(adj_persisted)

print("Persist complete. Beginning robust NetCDF write (parallelised via dask).")
# Write to NetCDF (non-blocking creation) and then compute via dask
# compute=False -> returns a dask.delayed or similar; we then ask the scheduler to compute
to_netcdf_obj = adj_persisted.to_netcdf(OUTPUT_ADJUSTED, mode="w", compute=False, encoding=encoding)

# Submit the single write job to the cluster and watch progress
future = client.compute(to_netcdf_obj)
print("Write submitted to Dask. Monitoring with progress...")
progress(future)  # prints progress in terminal

# Wait for completion
future.result()
print(f"Finished writing adjusted netCDF to: {OUTPUT_ADJUSTED}")

# -----------------------------
# Cleanup
# -----------------------------
print("Closing Dask client and cluster...")
client.close()
cluster.close()
print("Done.")
