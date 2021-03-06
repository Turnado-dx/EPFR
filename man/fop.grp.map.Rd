% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/EPFR.r
\name{fop.grp.map}
\alias{fop.grp.map}
\title{fop.grp.map}
\usage{
fop.grp.map(fcn, x, y, n, w)
}
\arguments{
\item{fcn}{= a function that maps yyyymmdd dates to groups of interest (e.g. day of the week)}

\item{x}{= a matrix/data frame of predictors}

\item{y}{= the number of days the predictors are lagged}

\item{n}{= the number of days needed for the predictors to be known}

\item{w}{= if F <fcn> is applied to formation dates. Otherwise it is applied to the first day in forward the return window.}
}
\description{
maps dates to date groups
}
\seealso{
Other fop: \code{\link{fop.Bin.underlying}},
  \code{\link{fop.Bin}}, \code{\link{fop.IC.summ}},
  \code{\link{fop.IC}}, \code{\link{fop.correl}},
  \code{\link{fop.rank.xRet}}, \code{\link{fop.wrapper}},
  \code{\link{fop}}
}
\keyword{fop.grp.map}
