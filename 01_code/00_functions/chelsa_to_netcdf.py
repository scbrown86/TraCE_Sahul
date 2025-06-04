def chelsa_to_netcdf(input_dir, output_path, variable, xmin, xmax, ymin, ymax):
    """
    Reads CHELSA tif files, crops them, stacks into a time series and writes to NetCDF.

    Args:
        input_dir (str): Directory containing CHELSA .tif files.
        output_path (str): Output NetCDF file path.
        variable (str): One of 'prec', 'tmax', 'tmin', 'tmean'.
        xmin, xmax, ymin, ymax (float): Bounding box for cropping.
    """
    pattern = re.compile(
        rf"CHELSA_{variable}_(\d{{4}})_(\d{{2}})_V1\.2\.1\.tif$"
    )

    # Collect and sort matching files
    file_info = []
    for f in os.listdir(input_dir):
        match = pattern.match(f)
        if match:
            year, month = int(match.group(1)), int(match.group(2))
            if 1980 <= year <= 1989:
                file_info.append((year, month, os.path.join(input_dir, f)))

    file_info.sort()

    if len(file_info) != 120:
        raise ValueError(f"Expected 120 monthly files for 1980–1989, found {len(file_info)}.")

    # Prepare the crop window
    sample_ds = gdal.Open(file_info[0][2], gdalconst.GA_ReadOnly)
    gt = sample_ds.GetGeoTransform()
    inv_gt = gdal.InvGeoTransform(gt)

    off_ul = gdal.ApplyGeoTransform(inv_gt, xmin, ymax)
    off_lr = gdal.ApplyGeoTransform(inv_gt, xmax, ymin)

    xoff = int(min(off_ul[0], off_lr[0]))
    yoff = int(min(off_ul[1], off_lr[1]))
    xsize = int(abs(off_lr[0] - off_ul[0]))
    ysize = int(abs(off_lr[1] - off_ul[1]))

    driver = gdal.GetDriverByName('NetCDF')
    out_ds = driver.Create(output_path, xsize, ysize, 120, gdal.GDT_Float32)
    out_ds.SetGeoTransform((xmin, gt[1], 0, ymax, 0, gt[5]))
    out_ds.SetProjection(sample_ds.GetProjection())

    # Progress bar added here
    for i, (year, month, path) in enumerate(tqdm(file_info, desc="Processing CHELSA layers")):
        in_ds = gdal.Open(path, gdalconst.GA_ReadOnly)
        band = in_ds.GetRasterBand(1)
        data = band.ReadAsArray(xoff, yoff, xsize, ysize)
        out_ds.GetRasterBand(i + 1).WriteArray(data)
        out_ds.GetRasterBand(i + 1).SetDescription(f"{year}-{month:02d}")

    out_ds.FlushCache()
    print(f"Saved NetCDF to: {output_path}")