
library(dplyr)

# Cargar clase SMAP
source(here::here("SMAP.R"))

# Instanciar clase SMAP
smap <- SMAP$new(base.dir = here::here('archivos_netcdf/smap_v4'))

# Extraer datos del NetCDF
capas <- smap$getProduct(
  product.name = "soil_moisture_am",  from = as.Date("2021-01-01"), to = as.Date("2021-01-01"))
raster::plot(capas)  # graficar raster

# PROJ.4 string para "EPSG:4326" (ver: https://epsg.io/4326)
crs_proj4_para_epsg_4326 <- "+proj=longlat +datum=WGS84 +no_defs +type=crs"

# Reprojectar raster
rasters <- capas %>%
  raster::projectRaster(crs = crs_proj4_para_epsg_4326)
raster::plot(rasters)  # graficar raster

