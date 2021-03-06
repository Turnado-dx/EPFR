% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/EPFR.r
\name{ftp.info}
\alias{ftp.info}
\title{ftp.info}
\usage{
ftp.info(x, y, n, w)
}
\arguments{
\item{x}{= M/W/D depending on whether flows are monthly/weekly/daily}

\item{y}{= T/F depending on whether you want to check Fund or Share-Class level data}

\item{n}{= one of sql.table/date.field/ftp.path}

\item{w}{= filter (e.g. Aggregate/Active/Passive/ETF/Mutual)}
}
\description{
parameter <n> associated with <x> flows at the <y> level with the <w> filter
}
\seealso{
Other ftp: \code{\link{ftp.all.dir}},
  \code{\link{ftp.all.files.underlying}},
  \code{\link{ftp.all.files}},
  \code{\link{ftp.credential}},
  \code{\link{ftp.delete.script.underlying}},
  \code{\link{ftp.delete.script}},
  \code{\link{ftp.dir.excise.crap}},
  \code{\link{ftp.dir.ftp.code}}, \code{\link{ftp.dir}},
  \code{\link{ftp.download.script}},
  \code{\link{ftp.file.size}}, \code{\link{ftp.get}},
  \code{\link{ftp.put}}, \code{\link{ftp.sql.factor}},
  \code{\link{ftp.sql.other}}, \code{\link{ftp.txt}},
  \code{\link{ftp.upload.script.underlying}},
  \code{\link{ftp.upload.script}}
}
\keyword{ftp.info}
