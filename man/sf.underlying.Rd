% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/EPFR.r
\name{sf.underlying}
\alias{sf.underlying}
\title{sf.underlying}
\usage{
sf.underlying(vbl.nm, univ, ret.nm, ret.prd, trail, sum.flows, grp, dly.vbl,
  nBins, fldr, vbl.lag, uRet = F, reverse.vbl = F, retHz = 1, classif)
}
\arguments{
\item{vbl.nm}{= variable}

\item{univ}{= membership (e.g. "EafeMem" or c("GemMem", 1))}

\item{ret.nm}{= return variable}

\item{ret.prd}{= the period for which you want returns}

\item{trail}{= number of trailing periods to compound/sum over}

\item{sum.flows}{= if T, flows get summed. Otherwise they get compounded.}

\item{grp}{= group within which binning is to be performed}

\item{dly.vbl}{= if T then a daily predictor is assumed else a monthly one}

\item{nBins}{= number of bins}

\item{fldr}{= data folder}

\item{vbl.lag}{= lags by <vbl.lag> weekdays or months depending on whether <dly.vbl> is true.}

\item{uRet}{= T/F depending on whether the equal-weight universe return is desired}

\item{reverse.vbl}{= T/F depending on whether you want the variable reversed}

\item{retHz}{= forward return horizon in months}

\item{classif}{= classif file}
}
\description{
Creates bin excess returns for a single period
}
\seealso{
Other sf: \code{\link{sf.bin.nms}}, \code{\link{sf.daily}},
  \code{\link{sf.detail}}, \code{\link{sf.single.bsim}},
  \code{\link{sf.subset}},
  \code{\link{sf.underlying.data}},
  \code{\link{sf.underlying.summ}}, \code{\link{sf}}
}
\keyword{sf.underlying}
