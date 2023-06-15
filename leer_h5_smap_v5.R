
library(dplyr)

# a. Buscar archivos descargados y generar data frame tal como lo devuelve
#    smapr::download_smap
archivos.descargados <- list.files(path = here::here("archivos_h5/smap_v5"), 
                                   pattern = "*.h5$", full.names = FALSE) %>%
  stringr::str_match(string = ., pattern = "^(.+?_(\\d{4})(\\d{2})(\\d{2})_.+?)\\.h5$") %>%
  as.data.frame() %>%
  dplyr::rename(name = V2) %>%
  dplyr::mutate(fecha = as.Date(sprintf("%s-%s-%s", V3, V4, V5)),
                date = sprintf("%s.%s.%s", V3, V4, V5),
                dir = sprintf("%s.%03d/%s/", "SPL3SMP_E", 5, date),
                local_dir = here::here("archivos_h5/smap_v5")) %>%
  dplyr::select(fecha, name, date, dir, local_dir) %>%
  dplyr::arrange(fecha)

# Para instalar smapr seguir estos pasos:
# 1- install.packages('BiocManager')
# 2- BiocManager::install('rhdf5')
# 3- install.packages('smapr')

# PROJ.4 string para "EPSG:4326" (ver: https://epsg.io/4326)
crs_proj4_para_epsg_4326 <- "+proj=longlat +datum=WGS84 +no_defs +type=crs"  

# i. Obtener capas de datos
raster.datos   <- smapr::extract_smap(data = archivos.descargados, in_memory = TRUE,
                                      name = "/Soil_Moisture_Retrieval_Data_AM/soil_moisture") %>%
  raster::stackApply(indices = rep(1, nrow(archivos.descargados)), fun = mean, na.rm = TRUE) %>%
  raster::projectRaster(crs = crs_proj4_para_epsg_4326) 
raster::plot(raster.datos)
# i. Obtener capas de calidad
raster.calidad <- smapr::extract_smap(data = archivos.descargados, in_memory = TRUE,
                                      name = "/Soil_Moisture_Retrieval_Data_AM/retrieval_qual_flag") %>%
  raster::stackApply(indices = rep(1, nrow(archivos.descargados)), fun = mean, na.rm = TRUE) %>%
  raster::projectRaster(crs = crs_proj4_para_epsg_4326) 
raster::plot(raster.calidad)

