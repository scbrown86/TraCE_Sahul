import numpy as np
import pandas as pd
import xarray as xr
import matplotlib.pyplot as plt
import xsdba

# --- Create toy gridded data ---
time_train = pd.date_range("1980-01-01", "1989-12-31", freq="MS")  # 10 yrs training
time_test  = pd.date_range("1990-01-01", "1999-12-31", freq="MS")  # 10 yrs test
lat = np.linspace(-10, 10, 4)   # 4 grid cells
lon = np.linspace(100, 120, 5)  # 5 grid cells

rng = np.random.default_rng(42)

# Observed training precip
obs = xr.DataArray(
    rng.gamma(shape=2, scale=2, size=(len(time_train), len(lat), len(lon))),
    coords={"time": time_train, "lat": lat, "lon": lon},
    dims=("time","lat","lon",),
    name="pr",
    attrs={"units": "mm/month"}
)
mean_obs = obs.groupby("time.year").sum("time").mean("year")
fig, axs = plt.subplots(1, 4, figsize=(16, 4), constrained_layout=True)
mean_obs.plot(ax=axs[0], cmap="YlGnBu"); axs[0].set_title("Observed (train)")
plt.show()

# Simulated training precip (biased low)
sim = xr.DataArray(
    rng.gamma(shape=1.5, scale=1.5, size=(len(time_train), len(lat), len(lon))),
    coords={"time": time_train, "lat": lat, "lon": lon},
    dims=("time","lat","lon",),
    name="pr",
    attrs={"units": "mm/month"}
)

# Simulated test data
test = xr.DataArray(
    rng.gamma(shape=1.5, scale=1.5, size=(len(time_test), len(lat), len(lon))),
    coords={"time": time_test, "lat": lat, "lon": lon},
    dims=("time","lat","lon",),
    name="pr",
    attrs={"units": "mm/month"}
)

# --- Fit QDM ---
qdm = xsdba.adjustment.QuantileDeltaMapping.train(obs, sim, nquantiles=20, kind="*", group="time")
qdm.fit(obs, sim)

# --- Apply to test period ---
test_corrected = qdm.adjust(test)

# --- Plot maps: mean annual precip ---
mean_obs = obs.groupby("time.year").sum("time").mean("year")
mean_sim = sim.groupby("time.year").sum("time").mean("year")
mean_test = test.groupby("time.year").sum("time").mean("year")
mean_corrected = test_corrected.groupby("time.year").sum("time").mean("year")

fig, axs = plt.subplots(1, 4, figsize=(16, 4), constrained_layout=True)
mean_obs.plot(ax=axs[0], cmap="YlGnBu"); axs[0].set_title("Observed (train)")
mean_sim.plot(ax=axs[1], cmap="YlGnBu"); axs[1].set_title("Simulated (train)")
mean_test.plot(ax=axs[2], cmap="YlGnBu"); axs[2].set_title("Test (sim)")
mean_corrected.plot(ax=axs[3], cmap="YlGnBu"); axs[3].set_title("Test (corrected)")

plt.show()

# --- Areal average time series ---
obs_area = obs.mean(["lat","lon"]).groupby("time.year").sum("time")
sim_area = sim.mean(["lat","lon"]).groupby("time.year").sum("time")
test_area = test.mean(["lat","lon"]).groupby("time.year").sum("time")
corrected_area = test_corrected.mean(["lat","lon"]).groupby("time.year").sum("time")

fig2, ax2 = plt.subplots(figsize=(8,5))
ax2.plot(obs_area["year"], obs_area, label="Observed (train)", lw=2)
ax2.plot(sim_area["year"], sim_area, label="Simulated (train)", lw=2)
ax2.plot(test_area["year"], test_area, label="Test (sim)", lw=2)
ax2.plot(corrected_area["year"], corrected_area, label="Test (corrected)", lw=2)
ax2.set_ylabel("Annual Areal Precip (a.u.)")
ax2.set_xlabel("Year")
ax2.legend()
ax2.grid(True)
plt.show()

