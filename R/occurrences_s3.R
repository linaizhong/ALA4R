#' Summarize, filter and subset occurrence data
#' 
#' Set of S3 methods to summarize, filter and get unique occurrence data retrieved using \code{occurrences}. 
#' This uses information based on selections of assertions (quality assurance issues ALA has identified), spatial and temporal data.
#' 
#' @author Atlas of Living Australia \email{support@@ala.org.au}
#' 
#' @param object list: an 'occurrence' object that has been downloaded using \code{occurrences}
#' @param x list: an 'occurrence' object that has been downloaded using \code{occurrences}
#' @param spatial numeric: specifies a rounding value in decimal degrees used to to create a unique subset of the data. Value of 0 means no rounding and use values as is. Values <0 mean ignore spatial unique parameter
#' @param temporal character: specifies the temporal unit for which to keep unique records; this can be by "year", "month", "yearmonth" or "full" date. NULL means ignore temporal unique parameter
#' @param na.rm logical: keep (FALSE) or remove (TRUE) missing spatial or temporal data
#' @param remove.fatal logical: remove flagged assertion issues that are considered "fatal"; see \code{check_assertions} 
#' @param exclude.spatial character vector: defining flagged spatial assertion issues to be removed. Values can include 'warnings','error','missing','none'; see \code{check_assertions}
#' @param exclude.temporal character vector: defining flagged temporal assertion issues to be removed. Values can include 'warnings','error','missing','none'; see \code{check_assertions}
#' @param exclude.taxonomic character vector: defining flagged taxonomic assertion issues to be removed. Values can include 'warnings','error','missing','none'; see \code{check_assertions}
#' @param max.spatial.uncertainty numeric: number defining the maximum spatial uncertainty (in meters) one is willing to accept. 
#' @param keep.missing.spatial.uncertainty logical: keep (FALSE) or remove (TRUE) information missing spatial uncertainty data.
#' @param incomparables logical/numeric: currently ignored, but needed for S3 method consistency
#' @param \dots not currently used
#'
#' @details
#' \code{unique} will give the min value for all columns that are not used in the aggregation.
#' 
#' @examples
#' #download some observations
#' x=occurrences(taxon="Amblyornis newtonianus",download_reason_id=10)
#' 
#' #summarize the occurrences
#' summary(x)
#' 
#' #keep spatially unique data at 0.01 degrees (latitude and longitude)
#' tt = unique(x,spatial=0.01)
#' summary(tt)
#'
#' #keep spatially unique data that is also unique year/month for the collection date
#' tt = unique(x,spatial=0,temporal='yearmonth')
#' summary(tt)
#'
#' #keep only information for which fatal or "error" assertions do not exist
#' tt = subset(x)
#' summary(tt)
#' 
#' @name occurrences_s3
NULL

#' @rdname occurrences_s3
#' @method summary occurrences
#' @S3method summary occurrences
"summary.occurrences" <- function(object, ...) {
	cat('number of names:',length(unique(object$data$Scientific.Name)),'\n')
	cat('number of taxonomically corrected names:',length(unique(object$data$Matched.Scientific.Name)),'\n')
	cat('number of observation records:',nrow(object$data),'\n')
	ass = check_assertions(object) #need to get existing assertions in occur dataset
	if (nrow(ass)>0) {
		cat('number of assertions listed:',nrow(ass),' -- ones with flagged issues are listed below\n')
		for (ii in 1:nrow(ass)) {
			rwi = length(which(as.logical(object$data[,ass$occur.colnames[ii]])==TRUE)) #count the number of records with issues
			if (rwi>0) cat('\t',ass$occur.colnames[ii],': ',rwi,' records ',ifelse(as.logical(ass$fatal[ii]),'-- considered fatal',''),sep='','\n')
		}
	} else { cat('no asserting issues\n') }
	invisible(object)
}

#' @rdname occurrences_s3
#' @method unique occurrences
#' @S3method unique occurrences
"unique.occurrences" <- function(x, incomparables=FALSE, spatial=0, temporal=NULL, na.rm=FALSE, ...) {
    assert_that(is.numeric(spatial)) #ensure unique.spatial is numeric
	if (!is.null(temporal)) {
		if (!temporal %in% c('year','month', 'yearmonth','full')) stop('temporal value must be NULL, "year", "month", "yearmonth" or "full"')
	}
	cois = list(Species...matched = x$data$Species...matched) #start defining the columns of interest to do the "unique" by
    if (spatial<0) {
        cat('ignoring spatial \n')
    } else {
		if (spatial>0) { #round the data to the spatial accuracy of interest
            x$data$Latitude...processed = round(x$data$Latitude...processed / spatial) * spatial
            x$data$Longitude...processed = round(x$data$Longitude...processed / spatial) * spatial
        }
		cois$Latitude...processed=x$data$Latitude...processed; cois$Longitude...processed=x$data$Longitude...processed #append the latitude and longitude
	}
	if (is.null(temporal)) {
		cat('ignoring temporal \n')
	} else {
		if (temporal=='full') {
			cois$Event.Date...parsed=x$data$Event.Date...parsed #add the full date to cois
		} else {
			if (length(grep('month',temporal))>0) cois$Month...parsed=x$data$Month...parsed
			if (length(grep('year',temporal))>0) cois$Year...parsed=x$data$Year...parsed
		}
	}
	x$data = aggregate(x$data,by=cois,min)[,-c(1:length(names(cois)))] #get 'unique' spatial/temporal data
	if (na.rm) {
		rois = which(is.na(x$data[,names(cois)]),arr.ind=TRUE)[,1]
		if ('Event.Date...parsed' %in% names(cois)) rois = c(rois,which(x$data$Event.Date...parsed==""))
		if (length(rois)>0) x$data = x$data[-(unique(rois)),] #remove the missing data rows
	}
	x
}

#' @rdname occurrences_s3
#' @method subset occurrences
#' @S3method subset occurrences
"subset.occurrences" = function(x, remove.fatal=TRUE, exclude.spatial='error', exclude.temporal='error', 
	exclude.taxonomic='error', max.spatial.uncertainty=NULL, keep.missing.spatial.uncertainty=TRUE, ...) 
{
	assert_that(is.character(exclude.spatial));assert_that(is.character(exclude.temporal));assert_that(is.character(exclude.taxonomic)) #check assertions are characters
	if(!all(c(exclude.spatial,exclude.temporal,exclude.temporal) %in% c('warnings','error','missing','none'))) 
		stop("exclude spatial, temporal and taxonomic must be a vector containing words of 'warnings','error','missing' or 'none'")
	assert_that(is.logical(remove.fatal)) #ensure fatal is logical
	assert_that(is.logical(keep.missing.spatial.uncertainty))
	assert_that(is.null(max.spatial.uncertainty) | is.numeric(max.spatial.uncertainty))
	
	ass = check_assertions(x) #need to get existing assertions in occur dataset
	if (nrow(ass)==0) warning('no assertions in occurrence data')
	
	roi = NULL #define an object outlining rows to remove
	for (ii in 1:nrow(ass)) {
		if (ass$fatal[ii]==TRUE) {
			if (remove.fatal) { #remove the fatal data
				roi = c(roi, which(x$data[,ass$occur.colnames[ii]] == TRUE)); next
			} 
		}
		if (ass$code[ii] < 10000) { #remove data with spatial issues
			if (length(exclude.spatial)>0) {
				if (ass$category[ii] %in% exclude.spatial) {
					roi = c(roi, which(x$data[,ass$occur.colnames[ii]] == TRUE)); next
				}
			}
		} else if (ass$code[ii] >= 10000 & ass$code[ii] < 20000) { #remove data with taxonomic issues
			if (length(exclude.taxonomic)>0 ) {
				if (ass$category[ii] %in% exclude.taxonomic) {
					roi = c(roi, which(x$data[,ass$occur.colnames[ii]] == TRUE)); next
				}
			}		
		} else if (ass$code[ii] >= 30000) { #remove data with temporal issues
			if (length(exclude.temporal)>0 ) {
				if (ass$category[ii] %in% exclude.temporal) {
					roi = c(roi, which(x$data[,ass$occur.colnames[ii]] == TRUE)); next
				}
			}		
		}
	}
	if(!is.null(max.spatial.uncertainty)) {
		if (keep.missing.spatial.uncertainty==FALSE) roi = c(roi,which(is.na(x$data$Coordinate.Uncertainty.in.Metres...parsed)))
		roi = c(roi,which(x$data$Coordinate.Uncertainty.in.Metres...parsed<=max.spatial.uncertainty))
	}

	roi = unique(roi) #remove duplicates
	if (length(roi)>0) x$data = x$data[-roi,] #remove the data

	x
}
