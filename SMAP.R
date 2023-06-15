require(R6)

SMAP <- R6::R6Class("SMAP",
  private = list(
    base.dir = NULL,
    
    listFiles = function(pattern) {
      return (sort(list.files(path = private$base.dir, 
                              pattern = pattern, 
                              full.names = TRUE)))
    },
    
    filterFiles = function(pattern, from = NULL, to = NULL) {
      files <- private$listFiles(pattern = pattern)
      if (! is.null(from) || ! is.null(to)) {
        filtered.files <- c()
        for (file in files) {
          nc         <- ncdf4::nc_open(files[1])
          start.date <- as.Date(ncdf4::ncatt_get(nc = nc, varid = 0, attname = "Start Date")$value)
          end.date   <- as.Date(ncdf4::ncatt_get(nc = nc, varid = 0, attname = "End Date")$value)
          ncdf4::nc_close(nc)
          is.within  <- TRUE
          if (is.within && ! is.null(from)) {
            is.within <- (start.date >= from)
          }
          if (is.within && ! is.null(to)) {
            is.within <- (start.date <= to)
          }
          if (is.within) {
            filtered.files <- c(filtered.files, file)
          }
        }
      }
      
      return (files)
    },
    
    getDateRange = function(pattern) {
      # Listar archivos
      files <- private$listFiles(pattern = pattern)
      
      if (length(files > 0)) {
        # Calculo de fechas de inicio y fin
        nc.first       <- ncdf4::nc_open(files[1])
        start.date     <- as.Date(ncdf4::ncatt_get(nc = nc.first, varid = 0, attname = "Start Date")$value)
        ncdf4::nc_close(nc.first)
        nc.last        <- ncdf4::nc_open(files[length(files)])
        end.date       <- as.Date(ncdf4::ncatt_get(nc = nc.last, varid = 0, attname = "End Date")$value)
        ncdf4::nc_close(nc.last)
        
        return (c(start.date, end.date))
      } else {
        return (c(NA, NA))
      }
    },
    
    createStack = function(product.name, files, from, to, zone = NULL) {
      # a. Obtener fecha de referencia y crs
      nc        <- ncdf4::nc_open(files[1])
      ref.date  <- as.Date(ncdf4::ncatt_get(nc = nc, varid = 0, attname = "Reference Date")$value)
      shape.crs <- ncdf4::ncatt_get(nc = nc, varid = 0, attname = "CRS")$value
      ncdf4::nc_close(nc)
      
      # b. Generar bricks y stack unico a partir de bricks
      brick.list <- lapply(
        X = files,
        FUN = raster::brick,
        varname = product.name
      )
      raster.stack <- raster::stack(brick.list)
      
      # c. Obtener fechas de bricks
      relative.dates <- unlist(lapply(
        X = brick.list,
        FUN = raster::getZ
      ))
      absolute.dates <- as.Date(relative.dates, origin = ref.date)
      
      # d. Hacer subset de acuerdo a las fechas ingresadas. Setear eje temporal absoluto
      selected.positions <- which((absolute.dates >= from) & (absolute.dates <= to))  
      absolute.dates     <- absolute.dates[selected.positions]
      raster.stack       <- raster::subset(x = raster.stack, subset = selected.positions)
      raster.stack       <- raster::setZ(raster.stack, absolute.dates, "time")
      
      # e. Asignar CRS
      raster::crs(raster.stack) <- shape.crs
      
      # f. Si hay que delimitar el raster a una zona, hacer crop y mask.
      #    Chequear coordenadas de la zona
      if (! is.null(zone)) {
        transformed.zone <- zone
        if (rgdal::CRSargs(raster::crs(zone)) != rgdal::CRSargs(raster::crs(raster.stack))) {
          # Transformar zona a sistema de coordenadas compatible
          transformed.zone <- sp::spTransform(zone, raster::crs(raster.stack))
        }
        
        # Hacer crop y mask
        raster.stack <- raster::crop(raster.stack, raster::extent(transformed.zone))
        raster.stack <- raster::mask(raster.stack, transformed.zone)
      }
      
      # g. Agregar fechas
      raster.stack <- raster::setZ(raster.stack, absolute.dates, "time")
      
      return (raster.stack)
    }
  ),
  public = list(
    initialize = function(base.dir = NULL) {
			if (is.null(base.dir)) {
			  stop("Carpeta de búsqueda indefinida");
			} else if (! dir.exists(base.dir)) {
			  stop("Carpeta de búsqueda inexistente");
			}
			
		  private$base.dir <- base.dir
		},

		getBaseDir = function() {
			return (private$base.dir)
		},
		setBaseDir = function(base.dir) {
		  private$base.dir <- base.dir
		},
		
		getProductNames = function() {
		  # Listar archivos
		  files <- private$listFiles(pattern = "^\\d{4}_SMAP\\.nc$")
		  
		  if (length(files > 0)) {
		    # Calculo de fechas de inicio y fin
		    nc.first      <- ncdf4::nc_open(files[1])
		    product.names <- names(nc.first$var)
		    ncdf4::nc_close(nc.first)
		    return (product.names)
		  } else {
		    return (c())
		  }
		},
		
		getProductsDateRange = function() {
		  return (private$getDateRange(pattern = "^\\d{4}_SMAP\\.nc$"))
		},
		
    getProduct = function(product.name, from = NULL, to = NULL, zone = NULL) {
      # Chequear que exista el indice
      if (! product.name %in% self$getProductNames()) {
        return (NULL)
      }
      
      # Buscar los archivos asociados al rango de fechas
      files <- private$filterFiles(pattern = "^\\d{4}_SMAP\\.nc$", from = from, to = to)
      if (length(files) > 0) {
        date.range <- self$getProductsDateRange()
        if (is.null(from) || (from < date.range[1])) {
          from <- date.range[1]
        }
        if (is.null(to) || (to > date.range[2])) {
          to <- date.range[2]
        }
        
        return (private$createStack(product.name = product.name, files = files, from = from, to = to, zone = zone))
      } else {
        return (NULL)
      }
    }
	)
)