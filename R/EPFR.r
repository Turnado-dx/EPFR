
#' mat.read
#' 
#' reads the file into data frame
#' @param x = a path to a text file
#' @param y = the separator
#' @param n = the column containing the row names (or NULL if none)
#' @param w = T/F variable depending on whether <x> has a header
#' @keywords mat.read
#' @export
#' @family mat
#' @import utils

mat.read <- function (x = "C:\\temp\\write.csv", y = ",", n = 1, w = T) 
{
    if (missing(y)) 
        y <- c("\t", ",")
    if (is.null(n)) 
        adj <- 0:1
    else adj <- rep(0, 2)
    if (!file.exists(x)) 
        stop("File ", x, " doesn't exist!\n")
    h <- length(y)
    z <- read.table(x, w, y[h], row.names = n, quote = "", as.is = T, 
        na.strings = txt.na(), comment.char = "", check.names = F)
    while (min(dim(z) - adj) == 0 & h > 1) {
        h <- h - 1
        z <- read.table(x, w, y[h], row.names = n, quote = "", 
            as.is = T, na.strings = txt.na(), comment.char = "", 
            check.names = F)
    }
    z
}

#' ret.outliers
#' 
#' Sets big ones to NA (a way to control for splits)
#' @param x = a vector of returns
#' @param y = outlier threshold
#' @keywords ret.outliers
#' @export
#' @family ret
#' @import stats

ret.outliers <- function (x, y = 1.5) 
{
    mdn <- median(x, na.rm = T)
    y <- c(1/y, y) * (100 + mdn) - 100
    z <- !is.na(x) & x > y[1] & x < y[2]
    z <- ifelse(z, x, NA)
    z
}

#' mk.1mPerfTrend
#' 
#' Returns a variable with the same row space as <n>
#' @param x = a single YYYYMM
#' @param y = variable to build
#' @param n = list object containing the following items: a) classif - classif file b) conn - a connection, the output of odbcDriverConnect c) uiconn - a connection to EPFRUI, the output of odbcDriverConnect d) DB - any of StockFlows/China/Japan/CSI300/Energy
#' @keywords mk.1mPerfTrend
#' @export
#' @family mk
#' @import RODBC

mk.1mPerfTrend <- function (x, y, n) 
{
    vbls <- paste0("Perf", txt.expand(c("", "ActWt"), c("Trend", 
        "Diff", "Diff2"), ""))
    if (length(y) != 1) 
        stop("Bad Argument Count")
    if (!is.element(y, vbls)) 
        stop("<y> must be one of", paste(vbls, collapse = "\\"))
    x <- yyyymm.lag(x, 1)
    ui <- "HFundId, FundRet = sum(PortfolioChange)/sum(AssetsStart)"
    ui <- sql.tbl(ui, "MonthlyData", "MonthEnding = @newDt", 
        "HFundId", "sum(AssetsStart) > 0")
    ui <- sql.tbl("t1.HFundId, GeographicFocus, FundRet", c(sql.label(ui, 
        "t1"), "inner join", "FundHistory t2", "\ton t2.HFundId = t1.HFundId"))
    ui <- paste(c(sql.declare("@newDt", "datetime", yyyymm.to.day(x)), 
        sql.unbracket(ui)), collapse = "\n")
    ui <- sqlQuery(n$uiconn, ui, stringsAsFactors = F)
    ui[, "FundRet"] <- ui[, "FundRet"] - map.rname(pivot.1d(mean, 
        ui[, "GeographicFocus"], ui[, "FundRet"]), ui[, "GeographicFocus"])
    if (any(duplicated(ui[, "HFundId"]))) 
        stop("Problem")
    ui <- vec.named(ui[, "FundRet"], ui[, "HFundId"])
    if (is.element(y, paste0("Perf", c("Trend", "Diff", "Diff2")))) {
        sf <- c("SecurityId", "his.FundId", "WtCol = n1.HoldingValue/AssetsEnd - o1.HoldingValue/AssetsStart")
        w <- sql.1mAllocMo.underlying.pre("All", yyyymm.to.day(x), 
            yyyymm.to.day(yyyymm.lag(x)))
        h <- c(sql.1mAllocMo.underlying.from("All"), "inner join", 
            "SecurityHistory id on id.HSecurityId = n1.HSecurityId")
        sf <- c(paste(w, collapse = "\n"), paste(sql.unbracket(sql.tbl(sf, 
            h, sql.in("n1.HSecurityId", sql.RDSuniv(n$DB)))), 
            collapse = "\n"))
    }
    else {
        sf <- c(sql.label(sql.MonthlyAssetsEnd("@newDt", ""), 
            "t"), "inner join", "FundHistory his", "\ton his.HFundId = t.HFundId")
        sf <- c(sf, "inner join", sql.label(sql.MonthlyAlloc("@newDt", 
            ""), "n1"), "\ton n1.HFundId = t.HFundId", "inner join")
        sf <- c(sf, "SecurityHistory id", "\ton id.HSecurityId = n1.HSecurityId")
        sf <- sql.tbl("SecurityId, t.HFundId, GeographicFocusId, WtCol = HoldingValue/AssetsEnd", 
            sf, sql.in("n1.HSecurityId", sql.RDSuniv(n$DB)))
        sf <- paste(c(sql.declare("@newDt", "datetime", yyyymm.to.day(x)), 
            sql.unbracket(sf)), collapse = "\n")
    }
    sf <- sqlQuery(n$conn, sf, stringsAsFactors = F)
    sf <- sf[is.element(sf[, "HFundId"], names(ui)), ]
    if (is.element(y, paste0("PerfActWt", c("Trend", "Diff", 
        "Diff2")))) {
        vec <- paste(sf[, "SecurityId"], sf[, "GeographicFocusId"])
        vec <- pivot.1d(mean, vec, sf[, "WtCol"])
        vec <- as.numeric(map.rname(vec, paste(sf[, "SecurityId"], 
            sf[, "GeographicFocusId"])))
        sf[, "WtCol"] <- sf[, "WtCol"] - vec
    }
    z <- as.numeric(ui[as.character(sf[, "HFundId"])])
    if (is.element(y, c("PerfDiff2", "PerfActWtDiff2"))) 
        z <- sign(z)
    if (is.element(y, c("PerfDiff", "PerfActWtDiff"))) 
        z <- z * sign(sf[, "WtCol"])
    else z <- z * sf[, "WtCol"]
    num <- pivot.1d(sum, sf[, "SecurityId"], z)
    den <- pivot.1d(sum, sf[, "SecurityId"], abs(z))
    z <- map.rname(den, dimnames(n$classif)[[1]])
    z <- nonneg(z)
    z <- map.rname(num, dimnames(n$classif)[[1]])/z
    z <- as.numeric(z)
    z
}

#' email
#' 
#' emails <x>
#' @param x = the email address of the recipient
#' @param y = subject of the email
#' @param n = text of the email
#' @param w = a vector of paths to attachement
#' @param h = T/F depending on whether you want to use html
#' @keywords email
#' @export
#' @import RDCOMClient

email <- function (x, y, n, w = "", h = F) 
{
    z <- COMCreate("Outlook.Application")
    z <- z$CreateItem(0)
    z[["To"]] <- x
    z[["subject"]] <- y
    if (h) {
        z[["HTMLBody"]] <- n
    }
    else {
        z[["body"]] <- n
    }
    for (j in w) if (file.exists(j)) 
        z[["Attachments"]]$Add(j)
    z$Send()
    invisible()
}

#' array.unlist
#' 
#' unlists the contents of an array
#' @param x = any numerical array
#' @param y = a vector of names for the columns of the output corresponding to the dimensions of <x>
#' @keywords array.unlist
#' @export

array.unlist <- function (x, y) 
{
    n <- length(dim(x))
    if (missing(y)) 
        y <- col.ex.int(0:n + 1)
    if (length(y) != n + 1) 
        stop("Problem")
    z <- expand.grid(dimnames(x), stringsAsFactors = F)
    names(z) <- y[1:n]
    z[, y[n + 1]] <- as.vector(x)
    z
}

#' ascending
#' 
#' T/F depending on whether <x> is ascending
#' @param x = a vector
#' @keywords ascending
#' @export

ascending <- function (x) 
{
    if (any(is.na(x))) 
        stop("Problem")
    z <- x[order(x)]
    z <- all(z == x)
    z
}

#' avail
#' 
#' For each row, returns leftmost entry with data
#' @param x = a matrix/data-frame
#' @keywords avail
#' @export

avail <- function (x) 
{
    fcn <- function(x, y) ifelse(is.na(x), y, x)
    z <- Reduce(fcn, mat.ex.matrix(x))
    z
}

#' avg.model
#' 
#' constant-only (zero-variable) regression model
#' @param x = vector of results
#' @keywords avg.model
#' @export
#' @family avg

avg.model <- function (x) 
{
    x <- x[!is.na(x)]
    z <- vec.named(mean(x), "Estimate")
    z["Std. Error"] <- sd(x)/sqrt(length(x))
    z["t value"] <- z["Estimate"]/nonneg(z["Std. Error"])
    z
}

#' avg.winsorized
#' 
#' mean is computed over the quantiles 2 through <y> - 1
#' @param x = a numeric vector
#' @param y = number of quantiles
#' @keywords avg.winsorized
#' @export
#' @family avg

avg.winsorized <- function (x, y = 100) 
{
    x <- x[!is.na(x)]
    w <- qtl(x, y)
    w <- is.element(w, 3:y - 1)
    z <- x[w]
    z <- mean(z)
    z
}

#' avg.wtd
#' 
#' returns the weighted mean of <x> given weights <n>
#' @param x = a numeric vector
#' @param y = a numeric vector of weights
#' @keywords avg.wtd
#' @export
#' @family avg

avg.wtd <- function (x, y) 
{
    fcn <- function(x, y) sum(x * y)/nonneg(sum(y))
    z <- fcn.num.nonNA(fcn, x, y, F)
    z
}

#' base.ex.int
#' 
#' Expresses <x> in base <y>
#' @param x = a non-negative integer
#' @param y = a positive integer
#' @keywords base.ex.int
#' @export
#' @family base

base.ex.int <- function (x, y = 26) 
{
    if (x == 0) 
        z <- 0
    else z <- NULL
    while (x > 0) {
        z <- c(x%%y, z)
        x <- (x - x%%y)/y
    }
    z
}

#' base.to.int
#' 
#' Evaluates the base <y> number <x>
#' @param x = a vector of positive integers
#' @param y = a positive integer
#' @keywords base.to.int
#' @export
#' @family base

base.to.int <- function (x, y = 26) 
{
    m <- length(x)
    z <- x * y^(m:1 - 1)
    z <- sum(z)
    z
}

#' bbk
#' 
#' standard model output
#' @param x = predictor indexed by yyyymmdd or yyyymm
#' @param y = total return index indexed by the same date format as <x>
#' @param floW = number of <prd.size>'s over which the predictor should be compounded/summed
#' @param retW = return window in days or months depending on whether <x> is YYYYMMDD or YYYYMM
#' @param nBin = number of bins to divide the variable into
#' @param doW = day of the week you will trade on (5 = Fri)
#' @param sum.flows = T/F depending on whether <x> should be summed or compounded
#' @param lag = predictor lag in days or months depending on whether <x> is YYYYMMDD or YYYYMM
#' @param delay = delay in knowing data in days or months depending on whether <x> is YYYYMMDD or YYYYMM
#' @param idx = the index within which you are trading
#' @param prd.size = size of each period in days or months depending on whether <x> is YYYYMMDD or YYYYMM
#' @param sprds = T/F depending on whether spread changes, rather than returns, are needed
#' @keywords bbk
#' @export
#' @family bbk

bbk <- function (x, y, floW = 20, retW = 5, nBin = 5, doW = 4, sum.flows = F, 
    lag = 0, delay = 2, idx = NULL, prd.size = 1, sprds = F) 
{
    x <- bbk.data(x, y, floW, sum.flows, lag, delay, doW, retW, 
        idx, prd.size, sprds)
    z <- bbk.bin.xRet(x$x, x$fwdRet, nBin, T, T)
    z <- lapply(z, mat.reverse)
    quantum <- ifelse(is.null(doW), 1, 5)
    z <- c(z, bbk.summ(z$rets, z$bins, retW, quantum))
    z
}

#' bbk.bin.rets.prd.summ
#' 
#' Summarizes bin excess returns by sub-periods of interest (as defined by <y>)
#' @param fcn = function you use to summarize results
#' @param x = a matrix/df with rows indexed by time and columns indexed by bins
#' @param y = a vector corresponding to the rows of <x> that maps each row to a sub-period of interest (e.g. calendar year)
#' @param n = number of rows of <x> needed to cover an entire calendar year
#' @keywords bbk.bin.rets.prd.summ
#' @export
#' @family bbk

bbk.bin.rets.prd.summ <- function (fcn, x, y, n) 
{
    w <- !is.na(y)
    y <- y[w]
    x <- x[w, ]
    x <- mat.ex.matrix(x)
    fcn.loc <- function(x) fcn(x, n, T)
    z <- split(x, y)
    z <- sapply(z, fcn.loc, simplify = "array")
    z
}

#' bbk.bin.rets.summ
#' 
#' Summarizes bin excess returns arithmetically
#' @param x = a matrix/df with rows indexed by time and columns indexed by bins
#' @param y = number of rows of <x> needed to cover an entire calendar year
#' @param n = T/F depending on if you want to count number of periods
#' @keywords bbk.bin.rets.summ
#' @export
#' @family bbk

bbk.bin.rets.summ <- function (x, y, n = F) 
{
    z <- c("AnnMn", "AnnSd", "Sharpe", "HitRate", "Beta", "Alpha", 
        "DrawDn", "DDnBeg", "DDnN")
    if (n) 
        z <- c(z, "nPrds")
    z <- matrix(NA, length(z), dim(x)[2], F, list(z, dimnames(x)[[2]]))
    if (n) 
        z["nPrds", ] <- sum(!is.na(x[, 1]))
    z["AnnMn", ] <- apply(x, 2, mean, na.rm = T) * y
    z["AnnSd", ] <- apply(x, 2, sd, na.rm = T) * sqrt(y)
    z["Sharpe", ] <- 100 * z["AnnMn", ]/z["AnnSd", ]
    z["HitRate", ] <- apply(sign(x), 2, mean, na.rm = T) * 50
    w <- dimnames(x)[[2]] == "uRet"
    if (any(w)) {
        z[c("Alpha", "Beta"), "uRet"] <- 0:1
        h <- !is.na(x[, "uRet"])
        m <- sum(h)
        if (m > 1) {
            vec <- c(rep(1, m), x[h, "uRet"])
            vec <- matrix(vec, m, 2, F, list(1:m, c("Alpha", 
                "Beta")))
            vec <- run.cs.reg(t(x[h, !w]), vec)
            vec[, "Alpha"] <- vec[, "Alpha"] * y
            z[dimnames(vec)[[2]], dimnames(vec)[[1]]] <- t(vec)
        }
    }
    if (dim(x)[1] > 1) {
        x <- x[order(dimnames(x)[[1]]), ]
        w <- fcn.mat.vec(bbk.drawdown, x, , T)
        z["DDnN", ] <- colSums(w)
        z["DrawDn", ] <- colSums(w * zav(x))
        y <- fcn.mat.num(which.max, w, , T)
        y <- dimnames(x)[[1]][y]
        if (any(substring(y, 5, 5) == "Q")) 
            y <- yyyymm.ex.qtr(y)
        z["DDnBeg", ] <- as.numeric(y)
    }
    z
}

#' bbk.bin.xRet
#' 
#' Returns equal weight bin returns through time
#' @param x = a matrix/df of predictors, the rows of which are indexed by time
#' @param y = a matrix/df of the same dimensions as <x> containing associated forward returns
#' @param n = number of desired bins
#' @param w = T/F depending on whether universe return is desired
#' @param h = T/F depending on whether full detail or bin returns are needed
#' @keywords bbk.bin.xRet
#' @export
#' @family bbk

bbk.bin.xRet <- function (x, y, n = 5, w = F, h = F) 
{
    if (h) 
        rslt <- list(raw.fwd.rets = y, raw = x)
    x <- bbk.holidays(x, y)
    x <- qtl.eq(x, n)
    if (h) 
        rslt[["bins"]] <- x
    uRetVec <- rowMeans(y, na.rm = T)
    y <- mat.ex.matrix(y) - uRetVec
    z <- array.unlist(x, c("date", "security", "bin"))
    z$ret <- unlist(y)
    z <- pivot(mean, z$ret, z$date, z$bin)
    z <- map.rname(z, dimnames(x)[[1]])
    dimnames(z)[[2]] <- paste0("Q", dimnames(z)[[2]])
    z <- mat.ex.matrix(z)
    z$TxB <- z[, 1] - z[, dim(z)[2]]
    if (w) 
        z$uRet <- uRetVec
    if (h) {
        rslt[["rets"]] <- z
        z <- rslt
    }
    z
}

#' bbk.data
#' 
#' fetches data required to compute standard model output
#' @param x = predictor indexed by yyyymmdd or yyyymm
#' @param y = total return index indexed by the same date format as <x>
#' @param floW = number of <prd.size>'s over which the predictor should be compounded/summed
#' @param sum.flows = T/F depending on whether <x> should be summed or compounded
#' @param lag = predictor lag in days or months depending on whether <x> is YYYYMMDD or YYYYMM
#' @param delay = delay in knowing data in days or months depending on whether <x> is YYYYMMDD or YYYYMM
#' @param doW = day of the week you will trade on (5 = Fri)
#' @param retW = return window in days or months depending on whether <x> is YYYYMMDD or YYYYMM
#' @param idx = the index within which you are trading
#' @param prd.size = size of each period in days or months depending on whether <x> is YYYYMMDD or YYYYMM
#' @param sprds = T/F depending on whether spread changes, rather than returns, are needed
#' @keywords bbk.data
#' @export
#' @family bbk

bbk.data <- function (x, y, floW, sum.flows, lag, delay, doW, retW, idx, 
    prd.size, sprds) 
{
    x <- x[!is.na(avail(x)), ]
    if (!ascending(dimnames(x)[[1]])) 
        stop("Flows are crap")
    if (any(yyyymm.lag(dimnames(x)[[1]][dim(x)[1]], dim(x)[1]:1 - 
        1, F) != dimnames(x)[[1]])) 
        stop("Missing flow dates")
    if (!ascending(dimnames(y)[[1]])) 
        stop("Returns are crap")
    if (any(yyyymm.lag(dimnames(y)[[1]][dim(y)[1]], dim(y)[1]:1 - 
        1) != dimnames(y)[[1]])) 
        stop("Missing return dates")
    x <- compound.flows(x, floW, prd.size, sum.flows)
    x <- mat.lag(x, lag + delay, F, F, F)
    if (!is.null(doW)) 
        x <- mat.daily.to.weekly(x, doW)
    y <- bbk.fwdRet(x, y, retW, 0, 0, !sprds)
    if (!is.null(idx)) 
        y <- Ctry.msci.index.changes(y, idx)
    z <- list(x = x, fwdRet = y)
    z
}

#' bbk.drawdown
#' 
#' returns a logical vector identifying the contiguous periods corresponding to max drawdown
#' @param x = a numeric vector
#' @keywords bbk.drawdown
#' @export
#' @family bbk

bbk.drawdown <- function (x) 
{
    n <- length(x)
    x <- zav(x)
    if (n == 1) {
        z <- 1
    }
    else {
        z <- vec.to.lags(x, n, F)
        for (i in 2:n) z[, i] <- z[, i] + z[, i - 1]
        prd.num <- order(apply(z, 2, min, na.rm = T))[1]
        prd.beg <- order(z[, prd.num])[1]
        z <- seq(prd.beg, length.out = prd.num)
        z <- is.element(1:n, z)
    }
    z
}

#' bbk.fanChart
#' 
#' quintile fan charts
#' @param x = "rets" part of the output of function bbk
#' @keywords bbk.fanChart
#' @export
#' @family bbk

bbk.fanChart <- function (x) 
{
    x <- mat.reverse(x[!is.na(x[, 1]), paste0("Q", 1:5)])
    for (j in 2:dim(x)[1]) x[j, ] <- apply(x[j - 1:0, ], 2, compound)
    z <- mat.reverse(x)/100
    z
}

#' bbk.fwdRet
#' 
#' returns a matrix/data frame of the same dimensions as <x>
#' @param x = a matrix/data frame of predictors
#' @param y = a matrix/data frame of total return indices
#' @param n = the number of days in the return window
#' @param w = the number of days the predictors are lagged
#' @param h = the number of days needed for the predictors to be known
#' @param u = T/F depending on whether returns or spread changes are needed
#' @keywords bbk.fwdRet
#' @export
#' @family bbk

bbk.fwdRet <- function (x, y, n, w, h, u) 
{
    if (dim(x)[2] != dim(y)[2]) 
        stop("Problem 1")
    if (any(dimnames(x)[[2]] != dimnames(y)[[2]])) 
        stop("Problem 2")
    y <- ret.ex.idx(y, n, F, T, u)
    y <- mat.lag(y, -h - w, F, F)
    z <- map.rname(y, dimnames(x)[[1]])
    z <- excise.zeroes(z)
    z
}

#' bbk.histogram
#' 
#' return distribution
#' @param x = "rets" part of the output of function bbk
#' @keywords bbk.histogram
#' @export
#' @family bbk

bbk.histogram <- function (x) 
{
    z <- vec.count(0.01 * round(x$TxB/0.5) * 0.5)
    z <- matrix(z, length(z), 3, F, list(names(z), c("Obs", "Plus", 
        "Minus")))
    z[, "Plus"] <- ifelse(as.numeric(dimnames(z)[[1]]) < 0, NA, 
        z[, "Plus"]/sum(z[, "Plus"]))
    z[, "Minus"] <- ifelse(as.numeric(dimnames(z)[[1]]) < 0, 
        z[, "Minus"]/sum(z[, "Minus"]), NA)
    z
}

#' bbk.holidays
#' 
#' Sets <x> to NA whenever <y> is NA
#' @param x = a matrix/df of predictors, the rows of which are indexed by time
#' @param y = a matrix/df of the same dimensions as <x> containing associated forward returns
#' @keywords bbk.holidays
#' @export
#' @family bbk

bbk.holidays <- function (x, y) 
{
    fcn <- function(x, y) ifelse(is.na(y), NA, x)
    z <- fcn.mat.vec(fcn, x, y, T)
    z
}

#' bbk.summ
#' 
#' summarizes by year and overall
#' @param x = bin returns
#' @param y = bin memberships
#' @param n = return window in days or months depending on whether <x> is YYYYMMDD or YYYYMM
#' @param w = quantum size (<n> is made up of non-overlapping windows of size <w>)
#' @keywords bbk.summ
#' @export
#' @family bbk

bbk.summ <- function (x, y, n, w) 
{
    if (n%%w != 0) 
        stop("Quantum size is wrong!")
    prdsPerYr <- yyyy.periods.count(dimnames(x)[[1]])
    fcn <- function(x) bbk.bin.rets.summ(x, prdsPerYr/n)
    z <- mat.ex.matrix(summ.multi(fcn, x, n/w))
    fcn <- function(x) bbk.turnover(x) * prdsPerYr/n
    y <- summ.multi(fcn, mat.ex.matrix(y), n/w)
    z <- map.rname(z, c(dimnames(z)[[1]], "AnnTo"))
    z["AnnTo", ] <- map.rname(y, dimnames(z)[[2]])
    z <- list(summ = z)
    if (n == w) {
        z.ann <- yyyy.ex.period(dimnames(x)[[1]], n)
        z.ann <- bbk.bin.rets.prd.summ(bbk.bin.rets.summ, x, 
            z.ann, prdsPerYr/n)
        z.ann <- rbind(z.ann["AnnMn", , ], z.ann["nPrds", "uRet", 
            ])
        z.ann <- t(z.ann)
        dimnames(z.ann)[[2]][dim(z.ann)[2]] <- "nPrds"
        z[["annSumm"]] <- z.ann
    }
    z
}

#' bbk.turnover
#' 
#' returns average name turnover per bin
#' @param x = a matrix/df of positive integers
#' @keywords bbk.turnover
#' @export
#' @family bbk

bbk.turnover <- function (x) 
{
    z <- vec.unique(x)
    x <- zav(x)
    new <- x[-1, ]
    old <- x[-dim(x)[1], ]
    z <- vec.named(rep(NA, length(z)), z)
    for (i in names(z)) z[i] <- mean(nameTo(old == i, new == 
        i), na.rm = T)
    names(z) <- paste0("Q", names(z))
    z["TxB"] <- z["Q1"] + z["Q5"]
    z["uRet"] <- 0
    z
}

#' best.linear.strategy.blend
#' 
#' Returns optimal weights to put on <x> and <y>
#' @param x = a return stream from a strategy
#' @param y = an isomekic return stream from a strategy
#' @keywords best.linear.strategy.blend
#' @export

best.linear.strategy.blend <- function (x, y) 
{
    w <- !is.na(x) & !is.na(y)
    x <- x[w]
    y <- y[w]
    mx <- mean(x)
    my <- mean(y)
    sx <- sd(x)
    sy <- sd(y)
    gm <- correl(x, y)
    V <- c(sx^2, rep(sx * sy * gm, 2), sy^2)
    V <- matrix(V, 2, 2)
    V <- solve(V)
    z <- V %*% c(mx, my)
    z <- renorm(z[, 1])
    z
}

#' binomial.trial
#' 
#' returns the likelihood of getting <n> or more/fewer heads depending on whether <w> is T/F
#' @param x = probability of success in a 1/0 Bernoulli trial
#' @param y = number of coin flips
#' @param n = number of heads
#' @param w = T/F variable depending on which tail you want
#' @keywords binomial.trial
#' @export

binomial.trial <- function (x, y, n, w) 
{
    if (w) 
        pbinom(y - n, y, 1 - x)
    else pbinom(n, y, x)
}

#' britten.jones
#' 
#' transforms the design matrix as set out in Britten-Jones, M., Neuberger  , A., & Nolte, I. (2011). Improved inference in regression with overlapping  observations. Journal of Business Finance & Accounting, 38(5-6), 657-683.
#' @param x = design matrix of a regression with 1st column assumed to be dependent
#' @param y = constitutent lagged returns that go into the first period
#' @keywords britten.jones
#' @export
#' @family britten

britten.jones <- function (x, y) 
{
    m <- length(y)
    n <- dim(x)[1]
    orig.nms <- dimnames(x)[[2]]
    for (i in 1:n) y <- c(y, x[i, 1] - sum(y[i - 1 + 1:m]))
    x <- as.matrix(x[, -1])
    z <- matrix(0, n + m, dim(x)[2], F, list(seq(1, m + n), dimnames(x)[[2]]))
    for (i in 0:m) z[1:n + i, ] <- z[1:n + i, ] + x
    if (det(crossprod(z)) > 0) {
        z <- z %*% solve(crossprod(z)) %*% crossprod(x)
        z <- data.frame(y, z)
        names(z) <- orig.nms
    }
    else z <- NULL
    z
}

#' britten.jones.data
#' 
#' returns data needed for a Britten-Jones analysis
#' @param x = a data frame of predictors
#' @param y = total return index of the same size as <x>
#' @param n = number of periods of forward returns used
#' @param w = the index within which you are trading
#' @keywords britten.jones.data
#' @export
#' @family britten

britten.jones.data <- function (x, y, n, w = NULL) 
{
    if (any(dim(x) != dim(y))) 
        stop("x/y are mismatched!")
    prd.ret <- 100 * mat.lag(y, -1, T, T)/nonneg(y) - 100
    prd.ret <- list(prd1 = prd.ret)
    if (n > 1) 
        for (i in 2:n) prd.ret[[paste0("prd", i)]] <- mat.lag(prd.ret[["prd1"]], 
            1 - i, T, T)
    y <- ret.ex.idx(y, n, T, T, T)
    vec <- as.numeric(unlist(y))
    w1 <- !is.na(vec) & abs(vec) < 1e-06
    if (any(w1)) {
        for (i in names(prd.ret)) {
            w2 <- as.numeric(unlist(prd.ret[[i]]))
            w2 <- is.na(w2) | abs(w2) < 1e-06
            w1 <- w1 & w2
        }
    }
    if (any(w1)) {
        vec <- ifelse(w1, NA, vec)
        y <- matrix(vec, dim(y)[1], dim(y)[2], F, dimnames(y))
    }
    if (!is.null(w)) 
        y <- Ctry.msci.index.changes(y, w)
    x <- bbk.bin.xRet(x, y, 5, F, T)
    y <- ret.to.log(y)
    prd.ret <- lapply(prd.ret, ret.to.log)
    w1 <- !is.na(unlist(y))
    for (i in names(prd.ret)) {
        vec <- as.numeric(unlist(prd.ret[[i]]))
        vec <- ifelse(w1, vec, NA)
        prd.ret[[i]] <- matrix(vec, dim(y)[1], dim(y)[2], F, 
            dimnames(y))
    }
    fcn <- function(x) x - rowMeans(x, na.rm = T)
    y <- fcn(y)
    prd.ret <- lapply(prd.ret, fcn)
    z <- NULL
    for (i in dimnames(x$bins)[[2]]) {
        if (sum(!is.na(x$bins[, i]) & !duplicated(x$bins[, i])) > 
            1) {
            df <- as.numeric(x$bins[, i])
            w1 <- !is.na(df)
            n.beg <- find.data(w1, T)
            n.end <- find.data(w1, F)
            if (n > 1 & n.end - n.beg + 1 > sum(w1)) {
                vec <- find.gaps(w1)
                if (any(vec < n - 1)) {
                  vec <- vec[vec < n - 1]
                  for (j in names(vec)) df[as.numeric(j) + 1:as.numeric(vec[j]) - 
                    1] <- 3
                }
            }
            df <- mat.ex.vec(df)
            w1 <- rowSums(df) == 1
            if (all(is.element(c("Q1", "Q5"), names(df)))) {
                df$TxB <- (df$Q1 - df$Q5)/2
            }
            else if (any(names(df) == "Q1")) {
                df$TxB <- df$Q1/2
            }
            else if (any(names(df) == "Q5")) {
                df$TxB <- -df$Q5/2
            }
            df <- df[, !is.element(names(df), c("Q1", "Q5"))]
            df$ActRet <- y[, i]
            df <- mat.last.to.first(df)
            w1 <- !is.na(prd.ret[["prd1"]][, i]) & w1
            n.beg <- find.data(w1, T)
            n.end <- find.data(w1, F)
            if (n == 1 | n.end - n.beg + 1 == sum(w1)) {
                z <- britten.jones.data.stack(z, df[n.beg:n.end, 
                  ], n, prd.ret, n.beg, i)
            }
            else {
                vec <- find.gaps(w1)
                if (any(vec < n - 1)) 
                  stop("Small return gap detected: i = ", i, 
                    ", retHz =", n, "...\n")
                if (any(vec >= n - 1)) {
                  vec <- vec[vec >= n - 1]
                  n.beg <- c(n.beg, as.numeric(names(vec)) + 
                    as.numeric(vec))
                  n.end <- c(as.numeric(names(vec)) - 1, n.end)
                  for (j in 1:length(n.beg)) z <- britten.jones.data.stack(z, 
                    df[n.beg[j]:n.end[j], ], n, prd.ret, n.beg[j], 
                    i)
                }
            }
        }
    }
    z
}

#' britten.jones.data.stack
#' 
#' applies the Britten-Jones transformation to a subset and then stacks
#' @param rslt =
#' @param df =
#' @param retHz =
#' @param prd.ret =
#' @param n.beg =
#' @param entity =
#' @keywords britten.jones.data.stack
#' @export
#' @family britten

britten.jones.data.stack <- function (rslt, df, retHz, prd.ret, n.beg, entity) 
{
    w <- colSums(df[, -1] == 0) == dim(df)[1]
    if (any(w)) {
        w <- !is.element(dimnames(df)[[2]], dimnames(df)[[2]][-1][w])
        df <- df[, w]
    }
    if (retHz > 1) {
        vec <- NULL
        for (j in names(prd.ret)[-retHz]) vec <- c(vec, prd.ret[[j]][n.beg, 
            entity])
        n <- dim(df)[1]
        df <- britten.jones(df, vec)
        if (is.null(df)) 
            cat("Discarding", n, "observations for", entity, 
                "due to Britten-Jones singularity ...\n")
    }
    if (!is.null(df)) 
        df <- mat.ex.matrix(zav(t(map.rname(t(df), c("ActRet", 
            paste0("Q", 2:4), "TxB")))))
    if (!is.null(df)) {
        if (is.null(z)) {
            dimnames(df)[[1]] <- 1:dim(df)[1]
            z <- df
        }
        else {
            dimnames(df)[[1]] <- 1:dim(df)[1] + dim(z)[1]
            z <- rbind(z, df)
        }
    }
    z
}

#' char.ex.int
#' 
#' the characters whose ascii values correspond to <x>
#' @param x = a string of integers
#' @keywords char.ex.int
#' @export
#' @family char

char.ex.int <- function (x) 
{
    z <- rawToChar(as.raw(x))
    z <- strsplit(z, "")[[1]]
    z
}

#' char.lag
#' 
#' lags <x> by <y>
#' @param x = a vector of characters
#' @param y = a number
#' @keywords char.lag
#' @export
#' @family char

char.lag <- function (x, y) 
{
    obj.lag(x, y, char.to.int, char.ex.int)
}

#' char.seq
#' 
#' returns a sequence of ASCII characters between (and including) x and y
#' @param x = a SINGLE character
#' @param y = a SINGLE character
#' @param n = quantum size
#' @keywords char.seq
#' @export
#' @family char

char.seq <- function (x, y, n = 1) 
{
    obj.seq(x, y, char.to.int, char.ex.int, n)
}

#' char.to.int
#' 
#' ascii values
#' @param x = a string of single characters
#' @keywords char.to.int
#' @export
#' @family char

char.to.int <- function (x) 
{
    z <- paste(x, collapse = "")
    z <- strtoi(charToRaw(z), 16L)
    z
}

#' char.to.num
#' 
#' coerces to numeric much more brutally than does as.numeric
#' @param x = a vector of strings
#' @keywords char.to.num
#' @export
#' @family char

char.to.num <- function (x) 
{
    z <- txt.replace(x, "\"", "")
    z <- txt.replace(z, ",", "")
    z <- as.numeric(z)
    z
}

#' col.ex.int
#' 
#' Returns the relevant excel column (1 = "A", 2 = "B", etc.)
#' @param x = a vector of positive integers
#' @keywords col.ex.int
#' @export
#' @family col

col.ex.int <- function (x) 
{
    fcn <- function(x) vec.last.element.increment(base.ex.int(x))
    z <- lapply(vec.to.list(x - 1), fcn)
    fcn <- function(x) char.ex.int(x + 64)
    z <- lapply(z, fcn)
    fcn <- function(x) paste(x, collapse = "")
    z <- as.character(sapply(z, fcn))
    z
}

#' col.offset
#' 
#' Offsets <x> by <y> columns
#' @param x = string representation of an excel column
#' @param y = an integer representing the desired column offset
#' @keywords col.offset
#' @export
#' @family col

col.offset <- function (x, y) 
{
    obj.lag(x, -y, col.to.int, col.ex.int)
}

#' col.to.int
#' 
#' Returns the relevant associated integer (1 = "A", 2 = "B", etc.)
#' @param x = a vector of string representations of excel columns
#' @keywords col.to.int
#' @export
#' @family col

col.to.int <- function (x) 
{
    z <- lapply(vec.to.list(x), txt.to.char)
    fcn <- function(x) char.to.int(x) - char.to.int("A") + 1
    z <- lapply(z, fcn)
    z <- as.numeric(sapply(z, base.to.int))
    z
}

#' combinations
#' 
#' returns all possible combinations of <y> values of <x>
#' @param x = a vector
#' @param y = an integer between 1 and <length(x)>
#' @keywords combinations
#' @export
#' @family combinations

combinations <- function (x, y) 
{
    w <- rep(F, length(x))
    if (y > 0) 
        w[1:y] <- T
    if (all(w)) {
        z <- paste(x, collapse = " ")
    }
    else if (all(!w)) {
        z <- ""
    }
    else {
        z <- NULL
        while (any(w)) {
            z <- c(z, paste(x[w], collapse = " "))
            w <- combinations.next(w)
        }
    }
    z
}

#' combinations.ex.int
#' 
#' inverse of combinations.to.int; returns a logical vector of length <n>, <y> of which elements are T
#' @param x = a positive integer
#' @param y = a positive integer
#' @param n = a positive integer
#' @keywords combinations.ex.int
#' @export
#' @family combinations

combinations.ex.int <- function (x, y, n) 
{
    z <- x <= choose(n - 1, y - 1)
    if (n > 1 & z) {
        z <- c(z, combinations.ex.int(x, y - 1, n - 1))
    }
    else if (n > 1 & !z) {
        z <- c(z, combinations.ex.int(x - choose(n - 1, y - 1), 
            y, n - 1))
    }
    z
}

#' combinations.next
#' 
#' returns the next combination in dictionary order
#' @param x = a logical vector
#' @keywords combinations.next
#' @export
#' @family combinations

combinations.next <- function (x) 
{
    m <- length(x)
    n <- find.data(!x, F)
    if (any(x[1:n])) {
        n <- find.data(x[1:n], F)
        nT <- sum(x) - sum(x[1:n])
        x[n:m] <- F
        x[n + 1 + 0:nT] <- T
        z <- x
    }
    else {
        z <- rep(F, m)
    }
    z
}

#' combinations.to.int
#' 
#' maps each particular way to choose <sum(x)> things amongst <length(x)> things to the number line
#' @param x = a logical vector
#' @keywords combinations.to.int
#' @export
#' @family combinations

combinations.to.int <- function (x) 
{
    n <- length(x)
    m <- sum(x)
    if (m == 0 | n == 1) {
        z <- 1
    }
    else if (x[1]) {
        z <- combinations.to.int(x[-1])
    }
    else {
        z <- choose(n - 1, m - 1) + combinations.to.int(x[-1])
    }
    z
}

#' compound
#' 
#' Outputs the compounded return
#' @param x = a vector of percentage returns
#' @keywords compound
#' @export
#' @family compound

compound <- function (x) 
{
    z <- !is.na(x)
    if (any(z)) 
        z <- 100 * product(1 + x[z]/100) - 100
    else z <- NA
    z
}

#' compound.flows
#' 
#' compounded flows over <n> trailing periods indexed by last day in the flow window
#' @param x = a matrix/data-frame of percentage flows
#' @param y = flow window in terms of the number of trailing periods to compound
#' @param n = size of each period in terms of days if the rows of <x> are yyyymmdd or months otherwise
#' @param w = if T, flows get summed. Otherwise they get compounded.
#' @keywords compound.flows
#' @export
#' @family compound

compound.flows <- function (x, y, n, w = F) 
{
    if (w) 
        fcn <- sum
    else fcn <- compound
    fcn2 <- function(x) if (is.na(x[1])) 
        NA
    else fcn(zav(x))
    z <- compound.flows.underlying(fcn2, x, y, F, n)
    z[compound.flows.initial(x, (y - 1) * n), ] <- NA
    z
}

#' compound.flows.initial
#' 
#' T/F depending on whether output for a row is to be set to NA
#' @param x = a matrix/data-frame of percentage flows
#' @param y = an integer representing the size of the window needed
#' @keywords compound.flows.initial
#' @export
#' @family compound

compound.flows.initial <- function (x, y) 
{
    z <- mat.to.first.data.row(x)
    z <- dimnames(x)[[1]][z]
    z <- yyyymm.lag(z, -y)
    z <- dimnames(x)[[1]] < z
    z
}

#' compound.flows.underlying
#' 
#' compounded flows over <y> trailing periods indexed by last day in the flow window
#' @param fcn = function used to compound flows
#' @param x = a matrix/data-frame of percentage flows
#' @param y = flow window in terms of the number of trailing periods to compound
#' @param n = if T simple positional lagging is used. If F, yyyymm.lag is invoked
#' @param w = size of each period in terms of days if the rows of <x> are yyyymmdd or months otherwise
#' @keywords compound.flows.underlying
#' @export
#' @family compound

compound.flows.underlying <- function (fcn, x, y, n, w) 
{
    if (y > 1) {
        z <- mat.to.lags(x, y, n, w)
        z <- apply(z, 1:2, fcn)
    }
    else {
        z <- x
    }
    z
}

#' compound.sf
#' 
#' compounds flows
#' @param x = a matrix/data-frame of percentage flows
#' @param y = if T, flows get summed. Otherwise they get compounded.
#' @keywords compound.sf
#' @export
#' @family compound

compound.sf <- function (x, y) 
{
    if (y) 
        fcn <- sum
    else fcn <- compound
    w <- rowSums(mat.to.obs(x)) > dim(x)[2]/2
    x <- zav(x)
    z <- rep(NA, dim(x)[1])
    if (any(w)) 
        z[w] <- mat.compound(x[w, ])
    z
}

#' correl
#' 
#' the estimated correlation between <x> and <y> or the columns of <x>
#' @param x = a numeric vector/matrix/data frame
#' @param y = either missing or a numeric isomekic vector
#' @param n = T/F depending on whether rank correlations are desired
#' @keywords correl
#' @export

correl <- function (x, y, n = T) 
{
    if (missing(y)) 
        fcn.mat.col(cor, x, , n)
    else fcn.mat.col(cor, x, y, n)
}

#' correl.PrcMo
#' 
#' returns correlation of <n> day flows with price momentum (175d lag 10)
#' @param x = one-day flow percentage
#' @param y = total return index
#' @param n = flow window
#' @param w = the number of days needed for the flow data to be known
#' @keywords correl.PrcMo
#' @export

correl.PrcMo <- function (x, y, n, w) 
{
    x <- compound.flows(x, n, 1, F)
    dimnames(x)[[1]] <- yyyymmdd.lag(dimnames(x)[[1]], -w)
    z <- map.rname(y, yyyymmdd.lag(dimnames(y)[[1]], 175))
    z <- nonneg(z)
    y <- as.matrix(y)/z
    dimnames(y)[[1]] <- yyyymmdd.lag(dimnames(y)[[1]], -10)
    x <- qtl.eq(x, 5)
    y <- qtl.eq(y, 5)
    x <- x[is.element(dimnames(x)[[1]], dimnames(y)[[1]]), ]
    y <- y[dimnames(x)[[1]], ]
    z <- correl(unlist(x), unlist(y), F)
    z
}

#' covar
#' 
#' efficient estimated covariance between the columns of <x>
#' @param x = a matrix
#' @keywords covar
#' @export

covar <- function (x) 
{
    cov(x, use = "pairwise.complete.obs")
}

#' cpt.RgnSec
#' 
#' makes Region-Sector groupings
#' @param x = a vector of Sectors
#' @param y = a vector of country codes
#' @keywords cpt.RgnSec
#' @export

cpt.RgnSec <- function (x, y) 
{
    y <- Ctry.to.CtryGrp(y)
    z <- GSec.to.GSgrp(x)
    z <- ifelse(is.element(z, "Cyc"), x, z)
    vec <- c(seq(15, 25, 5), "Def", "Fin")
    vec <- txt.expand(vec, c("Pac", "Oth"), , T)
    vec <- vec.named(c(seq(1, 9, 2), 1 + seq(1, 9, 2)), vec)
    vec["45-Pac"] <- vec["45-Oth"] <- 11
    z <- paste(z, y, sep = "-")
    z <- map.rname(vec, z)
    z <- as.numeric(z)
    z
}

#' cptRollingAverageWeights
#' 
#' Returns weights on individual weeks with the most recent week being to the RIGHT
#' @param x = number of trailing weeks to use
#' @param y = weight on the earliest as a percentage of weight on latest week
#' @param n = number of additional weeks to lag data
#' @keywords cptRollingAverageWeights
#' @export

cptRollingAverageWeights <- function (x = 4, y = 100, n = 0) 
{
    z <- x - 1
    z <- (y/100)^(1/z)
    z <- (z^(x:1 - 1))
    z <- z/sum(z)
    z <- c(z, rep(0, n))
    z
}

#' Ctry.info
#' 
#' handles the addition and removal of countries from an index
#' @param x = a vector of country codes
#' @param y = a column in the classif-ctry file
#' @keywords Ctry.info
#' @export
#' @family Ctry
#' @examples
#' Ctry.info("PK", "CtryNm")

Ctry.info <- function (x, y) 
{
    z <- mat.read(parameters("classif-ctry"), ",")
    z <- map.rname(z, x)[, y]
    z
}

#' Ctry.msci
#' 
#' Countries added or removed from the index in ascending order
#' @param x = an index name such as ACWI/EAFE/EM
#' @keywords Ctry.msci
#' @export
#' @family Ctry

Ctry.msci <- function (x) 
{
    z <- parameters("MsciCtryClassification")
    z <- mat.read(z, "\t", NULL)
    z <- z[order(z$yyyymm), ]
    if (x == "ACWI") {
        rein <- c("Developed", "Emerging")
    }
    else if (x == "EAFE") {
        rein <- "Developed"
    }
    else if (x == "EM") {
        rein <- "Emerging"
    }
    else stop("Bad Index")
    raus <- setdiff(c("Developed", "Emerging", "Frontier", "Standalone"), 
        rein)
    vec <- as.character(unlist(mat.subset(z, c("From", "To"))))
    vec <- ifelse(is.element(vec, rein), "in", vec)
    vec <- ifelse(is.element(vec, raus), "out", vec)
    z[, c("From", "To")] <- vec
    z <- z[z$From != z$To, ]
    z <- mat.subset(z, c("CCode", "To", "yyyymm"))
    dimnames(z)[[2]] <- c("CCODE", "ACTION", "YYYYMM")
    z$ACTION <- toupper(z$ACTION)
    z
}

#' Ctry.msci.index.changes
#' 
#' handles the addition and removal of countries from an index
#' @param x = a matrix/df of total returns indexed by the beginning of the period (trade date in yyyymmdd format)
#' @param y = an MSCI index such as ACWI/EAFE/EM
#' @keywords Ctry.msci.index.changes
#' @export
#' @family Ctry

Ctry.msci.index.changes <- function (x, y) 
{
    super.set <- Ctry.msci.members.rng(y, dimnames(x)[[1]][1], 
        dimnames(x)[[1]][dim(x)[1]])
    z <- Ctry.msci(y)
    if (nchar(dimnames(x)[[1]][1]) == 8) 
        z$YYYYMM <- yyyymmdd.ex.yyyymm(z$YYYYMM)
    if (nchar(dimnames(x)[[2]][1]) == 3) {
        z$CCODE <- Ctry.info(z$CCODE, "Curr")
        super.set <- Ctry.info(super.set, "Curr")
        z <- z[!is.element(z$CCODE, c("USD", "EUR")), ]
    }
    w <- !is.element(z$CCODE, dimnames(x)[[2]])
    if (any(w)) {
        w2 <- is.element(super.set, z$CCODE[w])
        z <- z[!w, ]
        if (any(w2)) 
            err.raise(super.set[w2], F, "Warning: No data for the following")
    }
    u.Ctry <- z$CCODE[!duplicated(z$CCODE)]
    z <- z[order(z$YYYYMM), ]
    for (i in u.Ctry) {
        vec <- z$CCODE == i
        if (z[vec, "ACTION"][1] == "OUT") 
            vec <- c("19720809", z[vec, "YYYYMM"])
        else vec <- z[vec, "YYYYMM"]
        if (length(vec)%%2 == 0) 
            vec <- c(vec, "30720809")
        w <- dimnames(x)[[1]] < vec[1]
        vec <- vec[-1]
        while (length(vec) > 0) {
            w <- w | (dimnames(x)[[1]] >= vec[1] & dimnames(x)[[1]] < 
                vec[2])
            vec <- vec[-1]
            vec <- vec[-1]
        }
        x[w, i] <- NA
    }
    z <- x
    z
}

#' Ctry.msci.members
#' 
#' lists countries in an index at <y>
#' @param x = an index name such as ACWI/EAFE/EM
#' @param y = one of the following: (a) a YYYYMM date (b) a YYYYMMDD date (c) "" for a static series
#' @keywords Ctry.msci.members
#' @export
#' @family Ctry

Ctry.msci.members <- function (x, y) 
{
    z <- mat.read(parameters("MsciCtry2016"), ",")
    z <- dimnames(z)[[1]][is.element(z[, x], 1)]
    if (y != "" & txt.left(y, 4) != "2016") {
        x <- Ctry.msci(x)
        point.in.2016 <- "201612"
        if (nchar(y) == 8) {
            x$YYYYMM <- yyyymmdd.ex.yyyymm(x$YYYYMM)
            point.in.2016 <- "20161231"
        }
    }
    if (y != "" & txt.left(y, 4) > "2016") {
        w <- x$YYYYMM >= point.in.2016
        w <- w & x$YYYYMM <= y
        if (any(w)) {
            for (i in 1:sum(w)) {
                if (x[w, "ACTION"][i] == "IN") 
                  z <- union(z, x[w, "CCODE"][i])
                if (x[w, "ACTION"][i] == "OUT") 
                  z <- setdiff(z, x[w, "CCODE"][i])
            }
        }
    }
    if (y != "" & txt.left(y, 4) < "2016") {
        w <- x$YYYYMM <= point.in.2016
        w <- w & x$YYYYMM > y
        if (any(w)) {
            x <- mat.reverse(x)
            w <- rev(w)
            x[, "ACTION"] <- ifelse(x[, "ACTION"] == "IN", "OUT", 
                "IN")
            for (i in 1:sum(w)) {
                if (x[w, "ACTION"][i] == "IN") 
                  z <- union(z, x[w, "CCODE"][i])
                if (x[w, "ACTION"][i] == "OUT") 
                  z <- setdiff(z, x[w, "CCODE"][i])
            }
        }
    }
    z
}

#' Ctry.msci.members.rng
#' 
#' lists countries that were ever in an index between <y> and <n>
#' @param x = an index name such as ACWI/EAFE/EM
#' @param y = a YYYYMM or YYYYMMDD date
#' @param n = after <y> and of the same date type
#' @keywords Ctry.msci.members.rng
#' @export
#' @family Ctry

Ctry.msci.members.rng <- function (x, y, n) 
{
    if (nchar(y) != nchar(n) | y >= n) 
        stop("Problem")
    z <- Ctry.msci.members(x, y)
    x <- Ctry.msci(x)
    if (nchar(y) == 8) 
        x$YYYYMM <- yyyymmdd.ex.yyyymm(x$YYYYMM)
    w <- x$YYYYMM >= y
    w <- w & x$YYYYMM <= n
    w <- w & x$ACTION == "IN"
    if (any(w)) 
        z <- union(z, x[w, "CCODE"])
    z
}

#' Ctry.msci.sql
#' 
#' SQL query to get date restriction
#' @param fcn = function to convert from yyyymm to yyyymmdd
#' @param x = output of Ctry.msci
#' @param y = single two-character country code
#' @param n = date field such as DayEnding or WeightDate
#' @keywords Ctry.msci.sql
#' @export
#' @family Ctry

Ctry.msci.sql <- function (fcn, x, y, n) 
{
    w <- x$CCODE == y
    if (sum(w) == 1 & x[w, "ACTION"][1] == "IN") {
        z <- paste0(n, " >= '", fcn(x[w, "YYYYMM"][1]), "'")
    }
    else if (sum(w) == 1 & x[w, "ACTION"][1] == "OUT") {
        z <- paste0(n, " < '", fcn(x[w, "YYYYMM"][1]), "'")
    }
    else if (sum(w) == 2 & x[w, "ACTION"][1] == "IN") {
        z <- paste0(n, " >= '", fcn(x[w, "YYYYMM"][1]), "' and ", 
            n, " < '", fcn(x[w, "YYYYMM"][2]), "'")
    }
    else if (sum(w) == 2 & x[w, "ACTION"][1] == "OUT") {
        z <- paste0(n, " < '", fcn(x[w, "YYYYMM"][1]), "' or ", 
            n, " >= '", fcn(x[w, "YYYYMM"][2]), "'")
    }
    else stop("Can't handle this!")
    z
}

#' Ctry.to.CtryGrp
#' 
#' makes Country groups
#' @param x = a vector of country codes
#' @keywords Ctry.to.CtryGrp
#' @export
#' @family Ctry

Ctry.to.CtryGrp <- function (x) 
{
    z <- c("JP", "AU", "NZ", "HK", "SG", "CN", "KR", "TW", "PH", 
        "ID", "TH", "MY", "KY", "BM")
    z <- ifelse(is.element(x, z), "Pac", "Oth")
    z
}

#' dataset.subset
#' 
#' subsets all files in <x> so that column <y> is made up of elements of <n>. Original files are overwritten.
#' @param x = a local folder (e.g. "C:\\\\temp\\\\crap")
#' @param y = column on which to subset
#' @param n = a vector of identifiers
#' @keywords dataset.subset
#' @export

dataset.subset <- function (x, y, n) 
{
    x <- dir.all.files(x, "*.*")
    while (length(x) > 0) {
        z <- scan(x[1], what = "", sep = "\n", nlines = 1, quiet = T)
        m <- as.numeric(regexpr(y, z, fixed = T))
        if (m > 0) {
            m <- m + nchar(y)
            if (m <= nchar(z)) {
                m <- substring(z, m, m)
                z <- mat.read(x[1], m, NULL, T)
                write.table(z[is.element(z[, y], n), ], "C:\\temp\\write.csv", 
                  sep = m, col.names = T, quote = F, row.names = F)
            }
            else cat("Can't subset", x[1], "\n")
        }
        else cat("Can't subset", x[1], "\n")
        x <- x[-1]
    }
    invisible()
}

#' day.ex.date
#' 
#' calendar dates
#' @param x = a vector of R dates
#' @keywords day.ex.date
#' @export
#' @family day

day.ex.date <- function (x) 
{
    format(x, "%Y%m%d")
}

#' day.ex.int
#' 
#' the <x>th day after Monday, January 1, 2018
#' @param x = an integer or vector of integers
#' @keywords day.ex.int
#' @export
#' @family day

day.ex.int <- function (x) 
{
    format(as.Date(x, origin = "2018-01-01"), "%Y%m%d")
}

#' day.lag
#' 
#' lags <x> by <y> days.
#' @param x = a vector of calendar dates
#' @param y = an integer or vector of integers (if <x> and <y> are vectors then <y> isomekic)
#' @keywords day.lag
#' @export
#' @family day

day.lag <- function (x, y) 
{
    obj.lag(x, y, day.to.int, day.ex.int)
}

#' day.seq
#' 
#' returns a sequence of calendar dates between (and including) x and y
#' @param x = a single calendar date
#' @param y = a single calendar date
#' @param n = quantum size in calendar date
#' @keywords day.seq
#' @export
#' @family day

day.seq <- function (x, y, n = 1) 
{
    obj.seq(x, y, day.to.int, day.ex.int, n)
}

#' day.to.date
#' 
#' converts to an R date
#' @param x = a vector of calendar dates
#' @keywords day.to.date
#' @export
#' @family day

day.to.date <- function (x) 
{
    as.Date(x, "%Y%m%d")
}

#' day.to.int
#' 
#' number of days after Monday, January 1, 2018
#' @param x = a vector of calendar dates
#' @keywords day.to.int
#' @export
#' @family day

day.to.int <- function (x) 
{
    as.numeric(day.to.date(x) - as.Date("2018-01-01"))
}

#' day.to.week
#' 
#' maps days to weeks
#' @param x = a vector of calendar dates
#' @param y = an integer representing the day the week ends on 0 is Sun, 1 is Mon, ..., 6 is Sat
#' @keywords day.to.week
#' @export
#' @family day

day.to.week <- function (x, y) 
{
    x <- day.to.int(x)
    z <- (x + 1)%%7
    z <- ifelse(z <= y, y - z, 7 + y - z)
    z <- day.ex.int(x + z)
    z
}

#' day.to.weekday
#' 
#' Converts to 0 = Sun, 1 = Mon, ..., 6 = Sat
#' @param x = a vector of calendar dates
#' @keywords day.to.weekday
#' @export
#' @family day

day.to.weekday <- function (x) 
{
    z <- day.to.int(x)
    z <- z + 1
    z <- as.character(z%%7)
    z
}

#' dir.all.files
#' 
#' Returns all files in the folder including sub-directories
#' @param x = a path such as "C:\\\\temp"
#' @param y = a string such as "*.txt"
#' @keywords dir.all.files
#' @export
#' @family dir

dir.all.files <- function (x, y) 
{
    z <- dir(x, y, recursive = T)
    if (length(z) > 0) {
        z <- paste(x, z, sep = "\\")
        z <- txt.replace(z, "/", "\\")
    }
    z
}

#' dir.clear
#' 
#' rids <x> of files of type <y>
#' @param x = a path such as "C:\\\\temp"
#' @param y = a string such as "*.txt"
#' @keywords dir.clear
#' @export
#' @family dir

dir.clear <- function (x, y) 
{
    cat("Ridding folder", x, "of", y, "files ...\n")
    z <- dir(x, y)
    if (length(x) > 0) 
        file.kill(paste(x, z, sep = "\\"))
    invisible()
}

#' dir.ensure
#' 
#' Creates necessary folders so files can be copied to <x>
#' @param x = a vector of full file paths
#' @keywords dir.ensure
#' @export
#' @family dir

dir.ensure <- function (x) 
{
    x <- dirname(x)
    x <- x[!duplicated(x)]
    x <- x[!dir.exists(x)]
    z <- x
    while (length(z) > 0) {
        z <- dirname(z)
        z <- z[!dir.exists(z)]
        x <- union(z, x)
    }
    if (length(x) > 0) 
        dir.make(x)
    invisible()
}

#' dir.kill
#' 
#' removes <x>
#' @param x = a vector of full folder paths
#' @keywords dir.kill
#' @export
#' @family dir

dir.kill <- function (x) 
{
    w <- dir.exists(x)
    if (any(w)) 
        unlink(x[w], recursive = T)
    invisible()
}

#' dir.make
#' 
#' creates folders <x>
#' @param x = a vector of full folder paths
#' @keywords dir.make
#' @export
#' @family dir

dir.make <- function (x) 
{
    for (z in x) dir.create(z)
    invisible()
}

#' dir.parameters
#' 
#' returns full path to relevant parameters sub-folder
#' @param x = desired sub-folder
#' @keywords dir.parameters
#' @export
#' @family dir

dir.parameters <- function (x) 
{
    paste(fcn.dir(), "New Model Concept\\General", x, sep = "\\")
}

#' dir.parent
#' 
#' returns paths to the parent directory
#' @param x = a string of full paths
#' @keywords dir.parent
#' @export
#' @family dir

dir.parent <- function (x) 
{
    z <- dirname(x)
    z <- ifelse(z == ".", "", z)
    z <- txt.replace(z, "/", "\\")
    z
}

#' dir.publications
#' 
#' desired output directory for relevant publication
#' @param x = desired sub-folder
#' @keywords dir.publications
#' @export
#' @family dir

dir.publications <- function (x) 
{
    dir.parameters(paste("Publications", x, sep = "\\"))
}

#' dir.size
#' 
#' size of directory <x> in KB
#' @param x = a SINGLE path to a directory
#' @keywords dir.size
#' @export
#' @family dir

dir.size <- function (x) 
{
    z <- dir.all.files(x, "*.*")
    if (length(z) == 0) {
        z <- 0
    }
    else {
        z <- file.size(z)
        z <- sum(z, na.rm = T)/2^10
    }
    z
}

#' EHD
#' 
#' named vector of item between <w> and <h> sorted ascending
#' @param x = connection type (StockFlows/Regular/Quant)
#' @param y = item (Flow/AssetsStart/AssetsEnd)
#' @param n = frequency (one of D/W/M)
#' @param w = begin date in YYYYMMDD
#' @param h = end date in YYYYMMDD
#' @param u = vector of filters
#' @keywords EHD
#' @export

EHD <- function (x, y, n, w, h, u = NULL) 
{
    z <- as.character(vec.named(c("DailyData", "WeeklyData", 
        "MonthlyData"), c("D", "W", "M"))[n])
    n <- as.character(vec.named(c("DayEnding", "WeekEnding", 
        "MonthEnding"), c("D", "W", "M"))[n])
    u <- split(u, ifelse(txt.has(u, "InstOrRetail", T), "ShareClass", 
        "Fund"))
    if (any(names(u) == "ShareClass")) 
        u[["ShareClass"]] <- sql.in("SCId", sql.tbl("SCId", "ShareClass", 
            u[["ShareClass"]]))
    if (any(names(u) == "Fund")) 
        u[["Fund"]] <- sql.in("HFundId", sql.FundHistory("", 
            u[["Fund"]], F))
    u[["Beg"]] <- paste(n, ">=", paste0("'", w, "'"))
    u[["End"]] <- paste(n, "<=", paste0("'", h, "'"))
    if (txt.right(y, 1) == "%") {
        y <- paste0("[", y, "] ", sql.Mo(txt.left(y, nchar(y) - 
            1), "AssetsStart", NULL, T))
    }
    else {
        y <- paste0(y, " = sum(", y, ")")
    }
    y <- c(paste0(n, " = convert(char(8), ", n, ", 112)"), y)
    z <- paste(sql.unbracket(sql.tbl(y, z, sql.and(u), n)), collapse = "\n")
    z <- sql.query(z, x, F)
    z <- mat.index(z)
    z <- z[order(names(z))]
    z
}

#' err.raise
#' 
#' error message
#' @param x = a vector
#' @param y = T/F depending on whether output goes on many lines
#' @param n = main line of error message
#' @keywords err.raise
#' @export
#' @family err

err.raise <- function (x, y, n) 
{
    cat(err.raise.txt(x, y, n), "\n")
    invisible()
}

#' err.raise.txt
#' 
#' error message
#' @param x = a vector
#' @param y = T/F depending on whether output goes on many lines
#' @param n = main line of error message
#' @keywords err.raise.txt
#' @export
#' @family err

err.raise.txt <- function (x, y, n) 
{
    n <- paste0(n, ":")
    if (y) {
        z <- paste(c(n, paste0("\t", x)), collapse = "\n")
    }
    else {
        z <- paste0(n, "\n\t", paste(x, collapse = " "))
    }
    z <- paste0(z, "\n")
    z
}

#' event.read
#' 
#' data frame with events sorted and numbered
#' @param x = path to a text file of dates in dd/mm/yyyy format
#' @keywords event.read
#' @export

event.read <- function (x) 
{
    z <- vec.read(x, F)
    z <- yyyymmdd.ex.txt(z, "/", "DMY")
    z <- z[order(z)]
    x <- 1:length(z)
    z <- data.frame(z, x, row.names = x, stringsAsFactors = F)
    dimnames(z)[[2]] <- c("Date", "EventNo")
    z
}

#' excise.zeroes
#' 
#' Coverts zeroes to NA
#' @param x = a vector/matrix/dataframe
#' @keywords excise.zeroes
#' @export

excise.zeroes <- function (x) 
{
    fcn <- function(x) ifelse(!is.na(x) & abs(x) < 1e-06, NA, 
        x)
    z <- fcn.mat.vec(fcn, x, , T)
    z
}

#' extract.AnnMn.sf
#' 
#' Subsets to "AnnMn" and re-labels columns
#' @param x = a 3D object. The first dimension has AnnMn/AnnSd/Sharp/HitRate The second dimension has bins Q1/Q2/Qna/Q3/Q4/Q5 The third dimension is some kind of parameter
#' @param y = a string which must be one of AnnMn/AnnSd/Sharp/HitRate
#' @keywords extract.AnnMn.sf
#' @export
#' @family extract

extract.AnnMn.sf <- function (x, y) 
{
    z <- x
    w <- dimnames(z)[[2]] != "uRet"
    z <- as.data.frame(t(z[y, w, ]))
    z <- mat.last.to.first(z)
    z
}

#' extract.AnnMn.sf.wrapper
#' 
#' Subsets to "AnnMn" and re-labels columns
#' @param x = a list object, each element of which is a 3D object The first dimension has AnnMn/AnnSd/Sharp/HitRate The second dimension has bins Q1/Q2/Qna/Q3/Q4/Q5 The third dimension is some kind of parameter
#' @param y = a string which must be one of AnnMn/AnnSd/Sharp/HitRate
#' @keywords extract.AnnMn.sf.wrapper
#' @export
#' @family extract

extract.AnnMn.sf.wrapper <- function (x, y = "AnnMn") 
{
    fcn <- function(x) extract.AnnMn.sf(x, y)
    if (dim(x[[1]])[3] == 1) 
        z <- t(sapply(x, fcn))
    else z <- mat.ex.matrix(lapply(x, fcn))
    z
}

#' factordump.rds
#' 
#' Dumps variable <x> to folder <y> in standard text format
#' @param x = variable name (e.g. "HerdingLSV")
#' @param y = local folder (e.g. "C:\\\\temp\\\\mystuff")
#' @param n = starting QTR
#' @param w = ending QTR
#' @param h = list object containing the following items: a) classif - classif file b) conn - a connection, the output of odbcDriverConnect c) fldr - stock-flows folder
#' @param u = output variable name
#' @keywords factordump.rds
#' @export
#' @family factordump

factordump.rds <- function (x, y, n, w, h, u) 
{
    for (j in qtr.seq(n, w)) {
        z <- list()
        for (k in yyyymm.lag(yyyymm.ex.qtr(j), 2:0)) {
            cat(k, "")
            df <- sql.query.underlying(sql.HSIdmap(k), h$conn, 
                F)
            is.dup <- duplicated(df$SecurityId)
            if (any(is.dup)) {
                df <- df[!is.dup, ]
                cat("Removing", sum(is.dup), "duplicated SecurityId at", 
                  k, "...\n")
            }
            df <- vec.named(df[, "HSecurityId"], df[, "SecurityId"])
            vbl <- fetch(x, yyyymm.lag(k, -1), 1, paste(h$fldr, 
                "derived", sep = "\\"), h$classif)
            is.data <- !is.na(vbl) & is.element(dimnames(h$classif)[[1]], 
                names(df))
            vbl <- vbl[is.data]
            df <- as.character(df[dimnames(h$classif)[[1]][is.data]])
            df <- data.frame(rep(yyyymm.to.day(k), length(vbl)), 
                df, vbl)
            dimnames(df)[[2]] <- c("ReportDate", "HSecurityId", 
                x)
            z[[k]] <- df
        }
        z <- Reduce(rbind, z)
        factordump.write(z, paste0(y, "\\", u, j, ".txt"))
        cat("\n")
    }
    invisible()
}

#' factordump.sql
#' 
#' Dumps variable <x> to folder <y> in standard text format
#' @param x = variable name (e.g. "Herfindahl")
#' @param y = local folder (e.g. "C:\\\\temp\\\\mystuff")
#' @param n = starting QTR
#' @param w = ending QTR
#' @param h = one of StockFlows/Regular/Quant
#' @keywords factordump.sql
#' @export
#' @family factordump

factordump.sql <- function (x, y, n, w, h) 
{
    filters <- vec.named(c("", "AllActive", "AllPassive", "AllETF", 
        "AllMF"), c("Aggregate", "Active", "Passive", "ETF", 
        "Mutual"))
    for (filter in names(filters)) {
        cat(txt.hdr(filter), "\n")
        myconn <- sql.connect(h)
        for (j in qtr.seq(n, w)) {
            z <- list()
            for (k in yyyymm.lag(yyyymm.ex.qtr(j), 2:0)) {
                cat(k, "")
                z[[k]] <- sql.query.underlying(ftp.sql.factor(x, 
                  yyyymm.to.day(k), filter, "All"), myconn, F)
            }
            z <- Reduce(rbind, z)
            factordump.write(z, paste0(y, "\\", x, "\\", filter, 
                "\\", x, filters[filter], j, ".txt"))
            cat("\n")
        }
        close(myconn)
    }
    invisible()
}

#' factordump.write
#' 
#' Dumps variable <x> to path <y> in standard text format
#' @param x = a matrix/data-frame
#' @param y = output path
#' @keywords factordump.write
#' @export
#' @family factordump

factordump.write <- function (x, y) 
{
    x[, "ReportDate"] <- yyyymmdd.to.txt(x[, "ReportDate"])
    dir.ensure(y)
    write.table(x, y, sep = "\t", , row.names = F, col.names = T, 
        quote = F)
    invisible()
}

#' farben
#' 
#' vector of R colours
#' @param x = number of colours needed
#' @keywords farben
#' @export

farben <- function (x) 
{
    if (x == 5) {
        z <- c(178, 61, 150, 0, 0, 0, 90, 176, 49, 64, 70, 80, 
            172, 218, 160)
    }
    else if (x == 4) {
        z <- c(178, 61, 150, 0, 0, 0, 0, 113, 60, 165, 207, 128)
    }
    else if (x == 3) {
        z <- c(178, 61, 150, 0, 0, 0, 90, 176, 49)
    }
    else if (x == 2) {
        z <- c(178, 61, 150, 90, 176, 49)
    }
    else if (x == 1) {
        z <- c(178, 61, 150)
    }
    else {
        stop("farben: Can't handle this!")
    }
    z <- mat.ex.matrix(matrix(z, 3, x))
    z <- lapply(z, function(x) paste(txt.right(paste0("0", as.hexmode(x)), 
        2), collapse = ""))
    z <- paste0("#", toupper(as.character(unlist(z))))
    z
}

#' fcn.all.canonical
#' 
#' Checks all functions are in standard form
#' @keywords fcn.all.canonical
#' @export
#' @family fcn

fcn.all.canonical <- function () 
{
    x <- fcn.list()
    w <- sapply(vec.to.list(x), fcn.canonical)
    if (all(w)) 
        cat("All functions are canonical ...\n")
    if (any(!w)) 
        err.raise(x[!w], F, "The following functions are non-canonical")
    invisible()
}

#' fcn.all.roxygenize
#' 
#' roxygenizes all functions
#' @param x = path to output file
#' @keywords fcn.all.roxygenize
#' @export
#' @family fcn

fcn.all.roxygenize <- function (x) 
{
    n <- fcn.list()
    n <- txt.parse(n, ".")
    n <- n[n[, 2] != "", 1]
    n <- vec.count(n)
    n <- names(n)[n > 1]
    y <- vec.named("mat.read", "utils")
    y["stats"] <- "ret.outliers"
    y["RODBC"] <- "mk.1mPerfTrend"
    y["RDCOMClient"] <- "email"
    z <- NULL
    for (w in names(y)) z <- c(z, "", fcn.roxygenize(y[w], w, 
        n))
    y <- setdiff(fcn.list(), y)
    for (w in y) z <- c(z, "", fcn.roxygenize(w, , n))
    cat(z, file = x, sep = "\n")
    invisible()
}

#' fcn.all.sub
#' 
#' a string vector of names of all sub-functions
#' @param x = a vector of function names
#' @keywords fcn.all.sub
#' @export
#' @family fcn

fcn.all.sub <- function (x) 
{
    fcn.indirect(fcn.direct.sub, x)
}

#' fcn.all.super
#' 
#' names of all functions that depend on <x>
#' @param x = a vector of function names
#' @keywords fcn.all.super
#' @export
#' @family fcn

fcn.all.super <- function (x) 
{
    fcn.indirect(fcn.direct.super, x)
}

#' fcn.args.actual
#' 
#' list of actual arguments
#' @param x = a SINGLE function name
#' @keywords fcn.args.actual
#' @export
#' @family fcn

fcn.args.actual <- function (x) 
{
    names(formals(x))
}

#' fcn.canonical
#' 
#' T/F depending on whether <x> is in standard form
#' @param x = a SINGLE function name
#' @keywords fcn.canonical
#' @export
#' @family fcn

fcn.canonical <- function (x) 
{
    y <- fcn.to.comments(x)
    z <- fcn.comments.parse(y)
    if (z$canonical) {
        if (z$name != x) {
            cat(x, "has a problem with NAME!\n")
            z$canonical <- F
        }
    }
    if (z$canonical) {
        if (!ascending(fcn.dates.parse(z$date))) {
            cat(x, "has a problem with DATE!\n")
            z$canonical <- F
        }
    }
    if (z$canonical) {
        actual.args <- fcn.args.actual(x)
        if (length(z$args) != length(actual.args)) {
            cat(x, "has a problem with NUMBER of COMMENTED ARGUMENTS!\n")
            z$canonical <- F
        }
    }
    if (z$canonical) {
        if (any(z$args != actual.args)) {
            cat(x, "has a problem with COMMENTED ARGUMENTS NOT MATCHING ACTUAL!\n")
            z$canonical <- F
        }
    }
    canon <- c("fcn", "x", "y", "n", "w", "h")
    if (z$canonical) {
        if (length(z$args) < length(canon)) {
            n <- length(z$args)
            if (any(z$args != canon[1:n]) & any(z$args != canon[1:n + 
                1])) {
                cat(x, "has NON-CANONICAL ARGUMENTS!\n")
                z$canonical <- F
            }
        }
    }
    if (z$canonical) {
        z <- fcn.indent.proper(x)
    }
    else z <- F
    z
}

#' fcn.clean
#' 
#' removes trailing spaces and tabs & indents properly
#' @keywords fcn.clean
#' @export
#' @family fcn

fcn.clean <- function () 
{
    z <- vec.read(fcn.path(), F)
    w.com <- fcn.indent.ignore(z, 0)
    w.del <- txt.has(z, paste("#", txt.space(65, "-")), T)
    w.beg <- txt.has(z, " <- function(", T) & c(w.del[-1], F)
    if (any(!w.com)) 
        z[!w.com] <- txt.trim(z[!w.com], c(" ", "\t"))
    i <- 1
    n <- length(z)
    while (i <= n) {
        if (w.beg[i]) {
            i <- i + 1
            phase <- 1
        }
        else if (phase == 1 & w.del[i]) {
            phase <- 2
            w <- 1
        }
        else if (phase == 2 & fcn.indent.else(toupper(z[i]), 
            1)) {
            w <- w - 1
            z[i] <- paste0(txt.space(w, "\t"), z[i])
            w <- w + 1
        }
        else if (phase == 2 & fcn.indent.decrease(toupper(z[i]), 
            1)) {
            w <- w - 1
            z[i] <- paste0(txt.space(w, "\t"), z[i])
        }
        else if (phase == 2 & fcn.indent.increase(toupper(z[i]), 
            0)) {
            z[i] <- paste0(txt.space(w, "\t"), z[i])
            w <- w + 1
        }
        else if (phase == 2 & !w.com[i]) {
            z[i] <- paste0(txt.space(w, "\t"), z[i])
        }
        i <- i + 1
    }
    cat(z, file = fcn.path(), sep = "\n")
    invisible()
}

#' fcn.comments.parse
#' 
#' extracts information from the comments
#' @param x = comments section of a function
#' @keywords fcn.comments.parse
#' @export
#' @family fcn

fcn.comments.parse <- function (x) 
{
    z <- list(canonical = !is.null(x))
    if (z$canonical) {
        if (txt.left(x[1], 10) != "# Name\t\t: ") {
            cat("Problem with NAME!\n")
            z$canonical <- F
        }
        else {
            z$name <- txt.right(x[1], nchar(x[1]) - 10)
            x <- x[-1]
        }
    }
    if (z$canonical) {
        if (txt.left(x[1], 11) != "# Author\t: ") {
            cat("Problem with AUTHOR!\n")
            z$canonical <- F
        }
        else {
            z$author <- txt.right(x[1], nchar(x[1]) - 11)
            x <- x[-1]
        }
    }
    if (z$canonical) {
        if (txt.left(x[1], 10) != "# Date\t\t: ") {
            cat("Problem with DATE!\n")
            z$canonical <- F
        }
        else {
            z$date <- txt.right(x[1], nchar(x[1]) - 10)
            x <- x[-1]
            while (length(x) > 0 & txt.left(x[1], 5) == "#\t\t: ") {
                z$date <- paste0(z$date, txt.right(x[1], nchar(x[1]) - 
                  5))
                x <- x[-1]
            }
        }
    }
    if (z$canonical) {
        if (txt.left(x[1], 10) != "# Args\t\t: ") {
            cat("Problem with ARGS!\n")
            z$canonical <- F
        }
        else {
            z$detl.args <- x[1]
            x <- x[-1]
            while (length(x) > 0 & any(txt.left(x[1], 5) == c("#\t\t: ", 
                "#\t\t:\t"))) {
                z$detl.args <- c(z$detl.args, x[1])
                x <- x[-1]
            }
            z$detl.args <- fcn.extract.args(z$detl.args)
            if (length(z$detl.args) == 1 & z$detl.args[1] != 
                "none") {
                z$args <- as.character(txt.parse(z$detl.args, 
                  " =")[1])
            }
            else if (length(z$detl.args) > 1) 
                z$args <- txt.parse(z$detl.args, " =")[, 1]
        }
    }
    if (z$canonical) {
        if (txt.left(x[1], 11) != "# Output\t: ") {
            cat("Problem with OUTPUT!\n")
            z$canonical <- F
        }
        else {
            z$out <- x[1]
            x <- x[-1]
            while (length(x) > 0 & any(txt.left(x[1], 5) == c("#\t\t: ", 
                "#\t\t:\t"))) {
                z$out <- c(z$out, x[1])
                x <- x[-1]
            }
            z$out <- fcn.extract.out(z$out)
        }
    }
    if (z$canonical & length(x) > 0) {
        if (txt.left(x[1], 11) == "# Notes\t\t: ") {
            x <- x[-1]
            while (length(x) > 0 & any(txt.left(x[1], 5) == c("#\t\t: ", 
                "#\t\t:\t"))) x <- x[-1]
        }
    }
    if (z$canonical & length(x) > 0) {
        if (txt.left(x[1], 12) == "# Example\t: ") {
            z$example <- txt.right(x[1], nchar(x[1]) - 12)
            x <- x[-1]
        }
    }
    if (z$canonical & length(x) > 0) {
        if (txt.left(x[1], 11) == "# Import\t: ") {
            z$import <- txt.right(x[1], nchar(x[1]) - 11)
            x <- x[-1]
        }
    }
    if (z$canonical & length(x) > 0) {
        cat("Other bizarre problem!\n")
        z$canonical <- F
    }
    z
}

#' fcn.date
#' 
#' date of last modification
#' @param x = a SINGLE function name
#' @keywords fcn.date
#' @export
#' @family fcn

fcn.date <- function (x) 
{
    max(fcn.dates.parse(fcn.comments.parse(fcn.to.comments(x))$date))
}

#' fcn.dates.parse
#' 
#' dates a function was modified
#' @param x = date item from fcn.comments.parse
#' @keywords fcn.dates.parse
#' @export
#' @family fcn

fcn.dates.parse <- function (x) 
{
    z <- as.character(txt.parse(x, ","))
    if (length(z) == 1) 
        z <- yyyymmdd.ex.txt(z)
    if (length(z) > 1) {
        z <- txt.parse(z, "/")[, 1:3]
        z[, 3] <- fix.gaps(as.numeric(z[, 3]))
        z[, 3] <- yyyy.ex.yy(z[, 3])
        z <- matrix(as.numeric(unlist(z)), dim(z)[1], dim(z)[2], 
            F, dimnames(z))
        z <- as.character(colSums(t(z) * 100^c(1, 0, 2)))
    }
    z
}

#' fcn.dir
#' 
#' folder of function source file
#' @keywords fcn.dir
#' @export
#' @family fcn

fcn.dir <- function () 
{
    z <- machine("C:\\temp\\Automation", "C:\\Users\\vik\\Documents")
    z <- vec.read(paste(z, "root.txt", sep = "\\"), F)
    z
}

#' fcn.direct.sub
#' 
#' a string vector of names of all direct sub-functions
#' @param x = a SINGLE function name
#' @keywords fcn.direct.sub
#' @export
#' @family fcn

fcn.direct.sub <- function (x) 
{
    x <- fcn.to.txt(x)
    z <- fcn.list()
    fcn <- function(z) {
        txt.has(x, paste0(z, "("), T)
    }
    w <- sapply(vec.to.list(z), fcn)
    if (any(w)) 
        z <- z[w]
    else z <- NULL
    z
}

#' fcn.direct.super
#' 
#' names of all functions that directly depend on <x>
#' @param x = a SINGLE function name
#' @keywords fcn.direct.super
#' @export
#' @family fcn

fcn.direct.super <- function (x) 
{
    fcn.has(paste0(x, "("))
}

#' fcn.expressions.count
#' 
#' number of expressions
#' @param x = a SINGLE function name
#' @keywords fcn.expressions.count
#' @export
#' @family fcn

fcn.expressions.count <- function (x) 
{
    z <- fcn.lines.code(x, F)
    z <- parse(text = z)
    z <- length(z)
    z
}

#' fcn.extract.args
#' 
#' vector of arguments with explanations
#' @param x = string vector representing argument section of comments
#' @keywords fcn.extract.args
#' @export
#' @family fcn

fcn.extract.args <- function (x) 
{
    n <- length(x)
    x <- txt.right(x, nchar(x) - ifelse(1:n == 1, 10, 5))
    if (n > 1) {
        w <- txt.has(x, "=", T)
        while (any(w[-n] & !w[-1])) {
            i <- 2:n - 1
            i <- i[w[-n] & !w[-1]][1]
            j <- i:n + 1
            j <- j[c(w, T)[j]][1] - 1
            x[i] <- paste(txt.trim(x[i:j], "\t"), collapse = " ")
            while (j > i) {
                x <- x[-j]
                w <- w[-j]
                j <- j - 1
                n <- n - 1
            }
        }
    }
    z <- x
    z
}

#' fcn.extract.out
#' 
#' extracts output
#' @param x = string vector representing output section of comments
#' @keywords fcn.extract.out
#' @export
#' @family fcn

fcn.extract.out <- function (x) 
{
    n <- length(x)
    z <- txt.right(x, nchar(x) - ifelse(1:n == 1, 11, 5))
    z <- paste(z, collapse = " ")
    z
}

#' fcn.has
#' 
#' Checks all functions are in standard form
#' @param x = substring to be searched for
#' @keywords fcn.has
#' @export
#' @family fcn

fcn.has <- function (x) 
{
    fcn <- function(y) txt.has(fcn.to.txt(y, F), x, T)
    z <- fcn.list()
    z <- z[sapply(vec.to.list(z), fcn)]
    z
}

#' fcn.indent.decrease
#' 
#' T/F depending on whether indent should be decreased
#' @param x = a line of code in a function
#' @param y = number of tabs
#' @keywords fcn.indent.decrease
#' @export
#' @family fcn

fcn.indent.decrease <- function (x, y) 
{
    txt.left(x, y) == paste0(txt.space(y - 1, "\t"), "}")
}

#' fcn.indent.else
#' 
#' T/F depending on whether line has an else statement
#' @param x = a line of code in a function
#' @param y = number of tabs
#' @keywords fcn.indent.else
#' @export
#' @family fcn

fcn.indent.else <- function (x, y) 
{
    h <- "} ELSE "
    z <- any(txt.left(x, nchar(h) + y - 1) == paste0(txt.space(y - 
        1, "\t"), h))
    z <- z & txt.right(x, 1) == "{"
    z
}

#' fcn.indent.ignore
#' 
#' T/F depending on whether line should be ignored
#' @param x = a line of code in a function
#' @param y = number of tabs
#' @keywords fcn.indent.ignore
#' @export
#' @family fcn

fcn.indent.ignore <- function (x, y) 
{
    txt.left(txt.trim.left(x, "\t"), 1) == "#"
}

#' fcn.indent.increase
#' 
#' T/F depending on whether indent should be increased
#' @param x = a line of code in a function
#' @param y = number of tabs
#' @keywords fcn.indent.increase
#' @export
#' @family fcn

fcn.indent.increase <- function (x, y) 
{
    h <- c("FOR (", "WHILE (", "IF (")
    z <- any(txt.left(x, nchar(h) + y) == paste0(txt.space(y, 
        "\t"), h))
    z <- z | txt.has(x, " <- FUNCTION(", T)
    z <- z & txt.right(x, 1) == "{"
    z
}

#' fcn.indent.proper
#' 
#' T/F depending on whether the function is indented properly
#' @param x = a SINGLE function name
#' @keywords fcn.indent.proper
#' @export
#' @family fcn

fcn.indent.proper <- function (x) 
{
    y <- toupper(fcn.lines.code(x, T))
    n <- c(LETTERS, 1:9)
    w <- 1
    i <- 1
    z <- T
    while (i < 1 + length(y) & z) {
        if (fcn.indent.decrease(y[i], w) & !fcn.indent.else(y[i], 
            w)) {
            w <- w - 1
        }
        else if (fcn.indent.increase(y[i], w)) {
            w <- w + 1
        }
        else if (!fcn.indent.ignore(y[i], w) & !fcn.indent.else(y[i], 
            w)) {
            z <- nchar(y[i]) > nchar(txt.space(w, "\t"))
            if (z) 
                z <- is.element(substring(y[i], w + 1, w + 1), 
                  n)
            if (!z) 
                cat(x, ":", y[i], "\n")
        }
        i <- i + 1
    }
    z
}

#' fcn.indirect
#' 
#' applies <fcn> recursively
#' @param fcn = a function to apply
#' @param x = vector of function names
#' @keywords fcn.indirect
#' @export
#' @family fcn

fcn.indirect <- function (fcn, x) 
{
    z <- NULL
    while (length(x) > 0) {
        y <- NULL
        for (j in x) y <- union(y, fcn(j))
        y <- setdiff(y, x)
        z <- union(z, y)
        x <- y
    }
    z
}

#' fcn.lines.code
#' 
#' lines of actual code
#' @param x = a SINGLE function name
#' @param y = T/F depending on whether internal comments count
#' @keywords fcn.lines.code
#' @export
#' @family fcn

fcn.lines.code <- function (x, y) 
{
    z <- length(fcn.to.comments(x))
    x <- fcn.to.txt(x, T)
    x <- as.character(txt.parse(x, "\n"))
    z <- x[seq(z + 4, length(x) - 1)]
    if (!y) 
        z <- z[txt.left(txt.trim.left(z, "\t"), 1) != "#"]
    z
}

#' fcn.lines.count
#' 
#' number of lines of code
#' @param x = a SINGLE function name
#' @param y = T/F depending on whether internal comments count
#' @keywords fcn.lines.count
#' @export
#' @family fcn

fcn.lines.count <- function (x, y = T) 
{
    length(fcn.lines.code(x, y))
}

#' fcn.list
#' 
#' Returns the names of objects that are or are not functions
#' @param x = pattern you want to see in returned objects
#' @keywords fcn.list
#' @export
#' @family fcn

fcn.list <- function (x = "*") 
{
    w <- globalenv()
    while (!is.element("fcn.list", ls(envir = w))) w <- parent.env(w)
    z <- ls(envir = w, all.names = T, pattern = x)
    w <- is.element(z, as.character(lsf.str(envir = w, all.names = T)))
    z <- z[w]
    z
}

#' fcn.mat.col
#' 
#' applies <fcn> to the columns of <x> pairwise
#' @param fcn = function mapping two vectors to a single value
#' @param x = a vector/matrix/dataframe
#' @param y = either missing or a numeric isomekic vector
#' @param n = T/F depending on whether inputs should be ranked
#' @keywords fcn.mat.col
#' @export
#' @family fcn

fcn.mat.col <- function (fcn, x, y, n) 
{
    if (missing(y)) {
        z <- matrix(NA, dim(x)[2], dim(x)[2], F, list(dimnames(x)[[2]], 
            dimnames(x)[[2]]))
        for (i in 1:dim(x)[2]) for (j in 1:dim(x)[2]) z[i, j] <- fcn.num.nonNA(fcn, 
            x[, i], x[, j], n)
    }
    else if (is.null(dim(x))) {
        z <- fcn.num.nonNA(fcn, x, y, n)
    }
    else {
        z <- rep(NA, dim(x)[2])
        for (i in 1:dim(x)[2]) z[i] <- fcn.num.nonNA(fcn, x[, 
            i], y, n)
    }
    z
}

#' fcn.mat.num
#' 
#' applies <fcn> to <x> if a vector or the columns/rows of <x> otherwise
#' @param fcn = function mapping vector(s) to a single value
#' @param x = a vector/matrix/dataframe
#' @param y = a number/vector or matrix/dataframe with the same dimensions as <x>
#' @param n = T/F depending on whether you want <fcn> applied to columns or rows
#' @keywords fcn.mat.num
#' @export
#' @family fcn

fcn.mat.num <- function (fcn, x, y, n) 
{
    if (is.null(dim(x)) & missing(y)) {
        z <- fcn(x)
    }
    else if (is.null(dim(x)) & !missing(y)) {
        z <- fcn(x, y)
    }
    else if (missing(y)) {
        z <- apply(x, as.numeric(n) + 1, fcn)
    }
    else if (is.null(dim(y))) {
        z <- apply(x, as.numeric(n) + 1, fcn, y)
    }
    else {
        w <- dim(x)[2 - as.numeric(n)]
        fcn.loc <- function(x) fcn(x[1:w], x[1:w + w])
        if (n) 
            x <- rbind(x, y)
        else x <- cbind(x, y)
        z <- apply(x, as.numeric(n) + 1, fcn.loc)
    }
    z
}

#' fcn.mat.vec
#' 
#' applies <fcn> to <x> if a vector or the columns/rows of <x> otherwise
#' @param fcn = function mapping vector(s) to an isomekic vector
#' @param x = a vector/matrix/dataframe
#' @param y = a number/vector or matrix/dataframe with the same dimensions as <x>
#' @param n = T/F depending on whether you want <fcn> applied to columns or rows
#' @keywords fcn.mat.vec
#' @export
#' @family fcn

fcn.mat.vec <- function (fcn, x, y, n) 
{
    if (is.null(dim(x)) & missing(y)) {
        z <- fcn(x)
    }
    else if (is.null(dim(x)) & !missing(y)) {
        z <- fcn(x, y)
    }
    else if (n & missing(y)) {
        z <- sapply(mat.ex.matrix(x), fcn)
    }
    else if (!n & missing(y)) {
        z <- t(sapply(mat.ex.matrix(t(x)), fcn))
    }
    else if (n & is.null(dim(y))) {
        z <- sapply(mat.ex.matrix(x), fcn, y)
    }
    else if (!n & is.null(dim(y))) {
        z <- t(sapply(mat.ex.matrix(t(x)), fcn, y))
    }
    else if (n) {
        w <- dim(x)[1]
        fcn.loc <- function(x) fcn(x[1:w], x[1:w + w])
        y <- rbind(x, y)
        z <- sapply(mat.ex.matrix(y), fcn.loc)
    }
    else {
        w <- dim(x)[2]
        fcn.loc <- function(x) fcn(x[1:w], x[1:w + w])
        y <- cbind(x, y)
        z <- t(sapply(mat.ex.matrix(t(y)), fcn.loc))
    }
    if (!is.null(dim(x))) 
        dimnames(z) <- dimnames(x)
    z
}

#' fcn.nonNA
#' 
#' applies <fcn> to the non-NA values of <x>
#' @param fcn = a function that maps a vector to a vector
#' @param x = a vector
#' @keywords fcn.nonNA
#' @export
#' @family fcn

fcn.nonNA <- function (fcn, x) 
{
    w <- !is.na(x)
    z <- rep(NA, length(x))
    if (any(w)) 
        z[w] <- fcn(x[w])
    z
}

#' fcn.num.nonNA
#' 
#' applies <fcn> to the non-NA values of <x> and <y>
#' @param fcn = a function that maps a vector to a number
#' @param x = a vector
#' @param y = either missing or an isomekic vector
#' @param n = T/F depending on whether inputs should be ranked
#' @keywords fcn.num.nonNA
#' @export
#' @family fcn

fcn.num.nonNA <- function (fcn, x, y, n) 
{
    if (missing(y)) 
        w <- !is.na(x)
    else w <- !is.na(x) & !is.na(y)
    if (all(!w)) {
        z <- NA
    }
    else if (missing(y) & !n) {
        z <- fcn(x[w])
    }
    else if (missing(y) & n) {
        z <- fcn(rank(x[w]))
    }
    else if (!n) {
        z <- fcn(x[w], y[w])
    }
    else if (n) {
        z <- fcn(rank(x[w]), rank(y[w]))
    }
    z
}

#' fcn.order
#' 
#' functions in alphabetical order
#' @keywords fcn.order
#' @export
#' @family fcn

fcn.order <- function () 
{
    x <- fcn.list()
    x <- split(x, x)
    fcn <- function(x) paste(x, "<-", fcn.to.txt(x, T, F))
    x <- sapply(x, fcn)
    cat(x, file = fcn.path(), sep = "\n")
    invisible()
}

#' fcn.path
#' 
#' path to function source file
#' @keywords fcn.path
#' @export
#' @family fcn

fcn.path <- function () 
{
    paste(fcn.dir(), "functionsVKS.r", sep = "\\")
}

#' fcn.roxygenize
#' 
#' roxygenized function format
#' @param x = function name
#' @param y = library to import
#' @param n = vector of function families
#' @keywords fcn.roxygenize
#' @export
#' @family fcn

fcn.roxygenize <- function (x, y, n) 
{
    w <- fcn.to.comments(x)
    w <- txt.replace(w, "\\", "\\\\")
    w <- txt.replace(w, "%", "\\%")
    w <- txt.replace(w, "@", "@@")
    w <- fcn.comments.parse(w)
    z <- c(w$name, "", w$out)
    if (any(names(w) == "args")) 
        z <- c(z, paste("@param", w$detl.args))
    z <- c(z, paste("@keywords", w$name), "@export")
    if (!missing(n)) {
        if (any(x == n) | any(txt.left(x, nchar(n) + 1) == paste0(n, 
            "."))) {
            z <- c(z, paste("@family", txt.parse(x, ".")[1]))
        }
    }
    if (!missing(y)) {
        z <- c(z, paste("@import", y))
    }
    else if (any(names(w) == "import")) 
        z <- c(z, w$import)
    if (any(names(w) == "example")) 
        z <- c(z, "@examples", w$example)
    z <- c(paste("#'", z), "")
    x <- fcn.to.txt(x, F, T)
    x[1] <- paste(w$name, "<-", x[1])
    z <- c(z, x)
    z
}

#' fcn.sho
#' 
#' cats <x> to the screen
#' @param x = a SINGLE function name
#' @keywords fcn.sho
#' @export
#' @family fcn

fcn.sho <- function (x) 
{
    x <- fcn.to.txt(x, T)
    cat(x, "\n")
    invisible()
}

#' fcn.simple
#' 
#' T/F depending on whether <x> has multi-line expressions
#' @param x = a SINGLE function name
#' @keywords fcn.simple
#' @export
#' @family fcn

fcn.simple <- function (x) 
{
    fcn.lines.count(x, F) == fcn.expressions.count(x)
}

#' fcn.to.comments
#' 
#' returns the comment section
#' @param x = a SINGLE function name
#' @keywords fcn.to.comments
#' @export
#' @family fcn

fcn.to.comments <- function (x) 
{
    y <- fcn.to.txt(x, T, T)
    z <- all(!is.element(txt.right(y, 1), c(" ", "\t")))
    if (!z) 
        cat(x, "has lines with trailing whitespace!\n")
    if (z & txt.left(y[1], 9) != "function(") {
        cat(x, "has a first line with non-canonical leading characters!\n")
        z <- F
    }
    if (z & any(!is.element(txt.left(y[-1], 1), c("#", "\t", 
        "}")))) {
        cat(x, "has lines with non-canonical leading characters!\n")
        z <- F
    }
    comment.delimiter <- paste("#", txt.space(65, "-"))
    w <- y == comment.delimiter
    if (z & sum(w) != 2) {
        cat(x, "does not have precisely two comment delimiters!\n")
        z <- F
    }
    w <- seq(1, length(y))[w]
    if (z & w[1] != 2) {
        cat(x, "does not have a proper beginning comment delimiter!\n")
        z <- F
    }
    if (z & w[2] - w[1] < 5) {
        cat(x, "has an ending too close to the beginning comment delimiter!\n")
        z <- F
    }
    if (z & length(y) - w[2] > 2) {
        z <- is.element(y[length(y) - 1], c("\tz", "\tinvisible()"))
        if (!z) 
            cat(x, "returns a non-canonical variable!\n")
    }
    if (z) 
        z <- y[seq(w[1] + 1, w[2] - 1)]
    else z <- NULL
    z
}

#' fcn.to.txt
#' 
#' represents <x> as a string or string vector
#' @param x = a SINGLE function name
#' @param y = T/F vbl controlling whether comments are returned
#' @param n = T/F vbl controlling whether output is a string vector
#' @keywords fcn.to.txt
#' @export
#' @family fcn

fcn.to.txt <- function (x, y = F, n = F) 
{
    x <- get(x)
    if (y) 
        z <- deparse(x, control = "useSource")
    else z <- deparse(x)
    if (!n) 
        z <- paste(z, collapse = "\n")
    z
}

#' fcn.vec.grp
#' 
#' applies <fcn> to <x> within groups <y>
#' @param fcn = function to be applied within groups
#' @param x = a vector/matrix/dataframe
#' @param y = a vector of groups (e.g. GSec)
#' @keywords fcn.vec.grp
#' @export
#' @family fcn

fcn.vec.grp <- function (fcn, x, y) 
{
    x <- split(x, y)
    z <- lapply(x, fcn)
    z <- unsplit(z, y)
    z
}

#' fcn.vec.num
#' 
#' applies <fcn> to <x>
#' @param fcn = function mapping elements to elements
#' @param x = an element or vector
#' @param y = an element or isomekic vector
#' @keywords fcn.vec.num
#' @export
#' @family fcn

fcn.vec.num <- function (fcn, x, y) 
{
    n <- length(x)
    if (n == 1 & missing(y)) {
        z <- fcn(x)
    }
    else if (n == 1 & !missing(y)) {
        z <- fcn(x, y)
    }
    else if (n > 1 & missing(y)) {
        z <- rep(NA, n)
        for (i in 1:n) z[i] <- fcn(x[i])
    }
    else if (n > 1 & length(y) == 1) {
        z <- rep(NA, n)
        for (i in 1:n) z[i] <- fcn(x[i], y)
    }
    else {
        z <- rep(NA, n)
        for (i in 1:n) z[i] <- fcn(x[i], y[i])
    }
    z
}

#' fetch
#' 
#' fetches <x> for the trailing <n> periods ending at <y>
#' @param x = either a single variable or a vector of variable names
#' @param y = the YYYYMM or YYYYMMDD for which you want data
#' @param n = number of daily/monthly trailing periods
#' @param w = R-object folder
#' @param h = classif file
#' @keywords fetch
#' @export

fetch <- function (x, y, n, w, h) 
{
    daily <- nchar(y) == 8
    if (daily) {
        yyyy <- yyyymmdd.to.yyyymm(y)
        mm <- txt.right(y, 2)
    }
    else {
        yyyy <- yyyymm.to.yyyy(y)
        mm <- as.numeric(txt.right(y, 2))
    }
    if (n > 1 & length(x) > 1) {
        stop("Can't handle this!\n")
    }
    else if (n > 1) {
        z <- paste0(w, "\\", x, ".", yyyy, ".r")
        lCol <- paste(x, mm, sep = ".")
        z <- readRDS(z)
        m <- 1:dim(z)[2]
        m <- m[dimnames(z)[[2]] == lCol]
        dimnames(z)[[2]] <- paste(dimnames(z)[[2]], yyyy, sep = ".")
        while (m < n) {
            if (daily) 
                yyyy <- yyyymm.lag(yyyy, 1)
            else yyyy <- yyyy - 1
            df <- paste0(w, "\\", x, ".", yyyy, ".r")
            df <- readRDS(df)
            dimnames(df)[[2]] <- paste(dimnames(df)[[2]], yyyy, 
                sep = ".")
            z <- data.frame(df, z)
            m <- m + dim(df)[2]
        }
        z <- z[, seq(m - n + 1, m)]
    }
    else if (length(x) > 1) {
        z <- matrix(NA, dim(h)[1], length(x), F, list(dimnames(h)[[1]], 
            x))
        z <- mat.ex.matrix(z)
        for (i in dimnames(z)[[2]]) {
            df <- paste0(w, "\\", i, ".", yyyy, ".r")
            lCol <- paste(i, mm, sep = ".")
            if (file.exists(df)) {
                z[, i] <- readRDS(df)[, lCol]
            }
            else {
                cat("Warning:", df, "does not exist. Proceeding regardless ...\n")
            }
        }
    }
    else {
        z <- paste0(w, "\\", x, ".", yyyy, ".r")
        lCol <- paste(x, mm, sep = ".")
        if (file.exists(z)) {
            z <- readRDS(z)[, lCol]
        }
        else {
            cat("Warning:", z, "does not exist. Proceeding regardless ...\n")
            z <- rep(NA, dim(h)[1])
        }
    }
    z
}

#' file.bkp
#' 
#' Copies <x> to <y>
#' @param x = a string of full paths
#' @param y = an isomekic string of full paths
#' @keywords file.bkp
#' @export
#' @family file

file.bkp <- function (x, y) 
{
    w <- file.exists(x)
    if (any(!w)) 
        err.raise(x[!w], T, "Warning: The following files to be copied do not exist")
    if (any(w)) {
        x <- x[w]
        y <- y[w]
        file.kill(y)
        dir.ensure(y)
        file.copy(x, y)
    }
    invisible()
}

#' file.break
#' 
#' breaks up the file into 1GB chunks and rewrites to same directory with a "-001", "-002", etc extension
#' @param x = path to a file
#' @keywords file.break
#' @export
#' @family file

file.break <- function (x) 
{
    y <- c(txt.left(x, nchar(x) - 4), txt.right(x, 4))
    m <- ceiling(log(2 * file.size(x)/2^30, base = 10))
    w <- 1e+06
    n <- scan(file = x, what = "", skip = 0, sep = "\n", quiet = T, 
        nlines = w)
    n <- as.numeric(object.size(n))/2^30
    n <- round(w/n)
    i <- 1
    z <- scan(file = x, what = "", skip = (i - 1) * n, sep = "\n", 
        quiet = T, nlines = n)
    while (length(z) == n) {
        cat(z, file = paste0(y[1], "-", txt.right(10^m + i, m), 
            y[2]), sep = "\n")
        i <- i + 1
        z <- scan(file = x, what = "", skip = (i - 1) * n, sep = "\n", 
            quiet = T, nlines = n)
    }
    cat(z, file = paste0(y[1], "-", txt.right(10^m + i, m), y[2]), 
        sep = "\n")
    invisible()
}

#' file.date
#' 
#' Returns the last modified date in yyyymmdd format
#' @param x = a vector of full file paths
#' @keywords file.date
#' @export
#' @family file

file.date <- function (x) 
{
    z <- file.mtime(x)
    z <- day.ex.date(z)
    z
}

#' file.kill
#' 
#' Deletes designated files
#' @param x = a string of full paths
#' @keywords file.kill
#' @export
#' @family file

file.kill <- function (x) 
{
    unlink(x)
    invisible()
}

#' file.mtime.to.time
#' 
#' Converts to HHMMSS times
#' @param x = a vector of dates
#' @keywords file.mtime.to.time
#' @export
#' @family file

file.mtime.to.time <- function (x) 
{
    format(x, "%H%M%S")
}

#' file.time
#' 
#' Returns the last modified date in yyyymmdd format
#' @param x = a vector of full file paths
#' @keywords file.time
#' @export
#' @family file

file.time <- function (x) 
{
    z <- file.mtime(x)
    z <- file.mtime.to.time(z)
    z
}

#' file.to.last
#' 
#' the last YYYYMMDD or the last day of the YYYYMM for which we have data
#' @param x = csv file containing the predictors
#' @keywords file.to.last
#' @export
#' @family file

file.to.last <- function (x) 
{
    z <- mat.read(x, ",")
    z <- mat.to.last.Idx(z)
    if (nchar(z) == 6) 
        z <- yyyymm.to.day(z)
    z
}

#' find.data
#' 
#' returns the position of the first/last true value of x
#' @param x = a logical vector
#' @param y = T/F depending on whether the position of the first/last true value of x is desired
#' @keywords find.data
#' @export
#' @family find

find.data <- function (x, y = T) 
{
    z <- 1:length(x)
    if (!y) {
        x <- rev(x)
        z <- rev(z)
    }
    z <- z[x & !duplicated(x)]
    z
}

#' find.gaps
#' 
#' returns the position of the first and last true value of x together with the first positions of all gaps
#' @param x = a logical vector
#' @keywords find.gaps
#' @export
#' @family find

find.gaps <- function (x) 
{
    m <- find.data(x, T)
    n <- find.data(x, F)
    z <- list(pos = NULL, size = NULL)
    while (n - m + 1 > sum(x[m:n])) {
        m <- m + find.data((!x)[m:n], T) - 1
        gap.size <- find.data(x[m:n], T) - 1
        z[["pos"]] <- c(z[["pos"]], m)
        z[["size"]] <- c(z[["size"]], gap.size)
        m <- m + gap.size
    }
    z <- vec.named(z[["size"]], z[["pos"]])
    z
}

#' find.whitespace.trail
#' 
#' cats 2 lines above and below lines with trailing white space
#' @param x = the name of a function
#' @keywords find.whitespace.trail
#' @export
#' @family find

find.whitespace.trail <- function (x) 
{
    z <- deparse(get(x), control = "useSource")
    n <- seq(1, length(z))[is.element(txt.right(z, 1), c(" ", 
        "\t"))]
    n <- c(n, n + 1, n + 2, n - 1, n - 2)
    n <- n[!duplicated(n)]
    n <- n[order(n)]
    n <- vec.min(n, length(z))
    n <- vec.max(n, 1)
    z <- z[n]
    vec.cat(z)
    invisible()
}

#' fix.gaps
#' 
#' replaces NA's by previous value
#' @param x = a vector
#' @keywords fix.gaps
#' @export

fix.gaps <- function (x) 
{
    if (is.na(x[1])) 
        stop("Problem")
    z <- x
    n <- length(z)
    w <- is.na(z[-1])
    while (any(w)) {
        z[-1] <- ifelse(w, z[-n], z[-1])
        w <- is.na(z[-1])
    }
    z
}

#' flowdate.diff
#' 
#' returns <x - y> in terms of flowdates
#' @param x = a vector of flow dates in YYYYMMDD format
#' @param y = an isomekic vector of flow dates in YYYYMMDD format
#' @keywords flowdate.diff
#' @export
#' @family flowdate

flowdate.diff <- function (x, y) 
{
    obj.diff(flowdate.to.int, x, y)
}

#' flowdate.ex.int
#' 
#' the <x>th daily flow-publication date after Friday, December 29, 2017
#' @param x = an integer or vector of integers
#' @keywords flowdate.ex.int
#' @export
#' @family flowdate

flowdate.ex.int <- function (x) 
{
    z <- c(0, x)
    z <- y <- seq(min(z), max(z))
    w <- !flowdate.exists(yyyymmdd.ex.int(z))
    while (any(w)) {
        if (any(w & z <= 0)) {
            for (h in sort(z[w & z <= 0], decreasing = T)) {
                z <- ifelse(z <= h, z - 1, z)
            }
        }
        if (any(w & z > 0)) {
            for (h in z[w & z > 0]) {
                z <- ifelse(z >= h, z + 1, z)
            }
        }
        w <- !flowdate.exists(yyyymmdd.ex.int(z))
    }
    if (length(z) > 1) 
        z <- approx(y, z, x)$y
    z <- yyyymmdd.ex.int(z)
    z
}

#' flowdate.ex.yyyymm
#' 
#' last/all trading days daily flow-publication dates in <x>
#' @param x = a vector/single YYYYMM depending on if y is T/F
#' @param y = T/F variable depending on whether the last or all daily flow-publication dates in <x> are desired
#' @keywords flowdate.ex.yyyymm
#' @export
#' @family flowdate

flowdate.ex.yyyymm <- function (x, y = T) 
{
    z <- yyyymmdd.ex.yyyymm(x, y)
    if (!y) 
        z <- z[flowdate.exists(z)]
    z
}

#' flowdate.exists
#' 
#' returns T if <x> is a daily flow-publication date
#' @param x = a vector of calendar dates
#' @keywords flowdate.exists
#' @export
#' @family flowdate

flowdate.exists <- function (x) 
{
    yyyymmdd.exists(x) & !is.element(txt.right(x, 4), c("0101", 
        "1225"))
}

#' flowdate.lag
#' 
#' lags <x> by <y> daily flow-publication dates
#' @param x = a vector of daily flow-publication dates
#' @param y = an integer
#' @keywords flowdate.lag
#' @export
#' @family flowdate

flowdate.lag <- function (x, y) 
{
    obj.lag(x, y, flowdate.to.int, flowdate.ex.int)
}

#' flowdate.seq
#' 
#' a sequence of dly flow-pub dates starting at <x> and, if possible, ending at <y>
#' @param x = a single daily flow-publication date
#' @param y = a single daily flow-publication date
#' @param n = a positive integer
#' @keywords flowdate.seq
#' @export
#' @family flowdate

flowdate.seq <- function (x, y, n = 1) 
{
    if (any(!flowdate.exists(c(x, y)))) 
        stop("Inputs are not daily flow-publication dates")
    z <- obj.seq(x, y, flowdate.to.int, flowdate.ex.int, n)
    z
}

#' flowdate.to.int
#' 
#' number of daily flow-publication dates after Friday, December 29, 2017
#' @param x = a vector of flow dates in YYYYMMDD format
#' @keywords flowdate.to.int
#' @export
#' @family flowdate

flowdate.to.int <- function (x) 
{
    z <- unique(c("2018", yyyymm.to.yyyy(yyyymmdd.to.yyyymm(x))))
    z <- as.numeric(z)[order(z)]
    z <- seq(z[1], z[length(z)])
    z <- txt.expand(z, c("0101", "1225"), "")
    z <- z[yyyymmdd.exists(z)]
    z <- vec.named(1:length(z), z)
    z <- z - z["20180101"]
    x <- yyyymmdd.to.int(x)
    y <- floor(approx(yyyymmdd.to.int(names(z)), z, x, rule = 1:2)$y)
    z <- x - ifelse(is.na(y), z[1] - 1, y)
    z
}

#' fop
#' 
#' an array of summary statistics of each quantile, indexed by parameter
#' @param x = a matrix/data frame of predictors
#' @param y = a matrix/data frame of total return indices
#' @param delay = the number of days needed for the predictors to be known
#' @param lags = a numeric vector of predictor lags
#' @param floW = a numeric vector of trailing flow windows
#' @param retW = a numeric vector of forward return windows
#' @param nBins = a numeric vector
#' @param grp.fcn = a function that maps yyyymmdd dates to groups of interest (e.g. day of the week)
#' @param convert2df = T/F depending on whether you want the output converted to a data frame
#' @param reverse.vbl = T/F depending on whether you want the variable reversed
#' @param prd.size = size of each compounding period in terms of days (days = 1, wks = 5, etc.)
#' @param first.ret.date = if F grp.fcn is applied to formation dates. Otherwise it is applied to the first day in forward the return window.
#' @param findOptimalParametersFcn = the function you are using to summarize your results
#' @param sum.flows = if T, flows get summed. Otherwise they get compounded
#' @param sprds = T/F depending on whether spread changes, rather than returns, are needed
#' @keywords fop
#' @export
#' @family fop

fop <- function (x, y, delay, lags, floW, retW, nBins, grp.fcn, convert2df, 
    reverse.vbl, prd.size, first.ret.date, findOptimalParametersFcn, 
    sum.flows, sprds) 
{
    z <- NULL
    for (i in floW) {
        cat(txt.hdr(paste("floW", i, sep = " = ")), "\n")
        x.comp <- compound.flows(x, i, prd.size, sum.flows)
        if (reverse.vbl) 
            x.comp <- -x.comp
        if (nchar(dimnames(x.comp)[[1]][1]) == 6 & nchar(dimnames(y)[[1]][1]) == 
            8) 
            x.comp <- yyyymmdd.ex.AllocMo(x.comp)
        for (h in lags) {
            cat("lag =", h, "")
            pctFlo <- x.comp
            j <- h
            delay.loc <- delay
            if (nchar(dimnames(pctFlo)[[1]][1]) == 8 & nchar(dimnames(y)[[1]][1]) == 
                6) {
                pctFlo <- mat.lag(pctFlo, j + delay, F, F)
                pctFlo <- mat.daily.to.monthly(pctFlo, F)
                delay.loc <- 0
                j <- 0
            }
            vec <- fop.grp.map(grp.fcn, pctFlo, j, delay.loc, 
                first.ret.date)
            for (n in retW) {
                if (n != retW[1]) 
                  cat("\t")
                cat("retW =", n, ":")
                fwdRet <- bbk.fwdRet(pctFlo, y, n, j, delay.loc, 
                  T)
                for (k in nBins) {
                  cat(k, "")
                  rslt <- findOptimalParametersFcn(pctFlo, fwdRet, 
                    vec, n, k)
                  if (is.null(z)) 
                    z <- array(NA, c(length(floW), length(lags), 
                      length(retW), length(nBins), dim(rslt)), 
                      list(floW, lags, retW, nBins, dimnames(rslt)[[1]], 
                        dimnames(rslt)[[2]], dimnames(rslt)[[3]]))
                  z[as.character(i), as.character(j), as.character(n), 
                    as.character(k), dimnames(rslt)[[1]], dimnames(rslt)[[2]], 
                    dimnames(rslt)[[3]]] <- rslt
                }
                cat("\n")
            }
            cat("\n")
        }
        cat("\n")
    }
    if (convert2df) 
        z <- mat.ex.array(aperm(z, order(1:7 != 5)))
    z
}

#' fop.Bin
#' 
#' Summarizes bin excess returns by sub-periods of interest (as defined by <vec>)
#' @param x = a matrix/df with rows indexed by time and columns indexed by bins
#' @param y = a matrix/data frame of returns of the same dimension as <x>
#' @param n = a vector corresponding to the rows of <x> that maps each row to a sub-period of interest (e.g. calendat year)
#' @param w = return horizon in weekdays or months
#' @param h = number of bins into which you are going to divide your predictors
#' @keywords fop.Bin
#' @export
#' @family fop

fop.Bin <- function (x, y, n, w, h) 
{
    fop.Bin.underlying(bbk.bin.rets.summ, x, y, n, w, h, bbk.bin.xRet)
}

#' fop.Bin.underlying
#' 
#' Summarizes bin excess returns by sub-periods of interest (as defined by <vec>)
#' @param fcn = overall summary function
#' @param x = a matrix/df with rows indexed by time and columns indexed by bins
#' @param y = a matrix/data frame of returns of the same dimension as <x>
#' @param n = a vector corresponding to the rows of <x> that maps each row to a sub-period of interest (e.g. calendat year)
#' @param w = return horizon in weekdays or months
#' @param h = number of bins into which you are going to divide your predictors
#' @param fcn.prd = per period summary function
#' @keywords fop.Bin.underlying
#' @export
#' @family fop

fop.Bin.underlying <- function (fcn, x, y, n, w, h, fcn.prd) 
{
    x <- fcn.prd(x, y, h)
    m <- yyyy.periods.count(dimnames(x)[[1]])
    z <- bbk.bin.rets.prd.summ(fcn, x, n, m/w)
    z
}

#' fop.correl
#' 
#' computes IC
#' @param x = a matrix/df with rows indexed by time and columns indexed by bins
#' @param y = a matrix/data frame of returns of the same dimension as <x>
#' @param n = an argument which is not used
#' @keywords fop.correl
#' @export
#' @family fop

fop.correl <- function (x, y, n) 
{
    x <- fop.rank.xRet(x, y)
    y <- fop.rank.xRet(y, x)
    z <- matrix(mat.correl(x, y), dim(x)[1], 2, F, list(dimnames(x)[[1]], 
        c("IC", "Crap")))
    z
}

#' fop.grp.map
#' 
#' maps dates to date groups
#' @param fcn = a function that maps yyyymmdd dates to groups of interest (e.g. day of the week)
#' @param x = a matrix/data frame of predictors
#' @param y = the number of days the predictors are lagged
#' @param n = the number of days needed for the predictors to be known
#' @param w = if F <fcn> is applied to formation dates. Otherwise it is applied to the first day in forward the return window.
#' @keywords fop.grp.map
#' @export
#' @family fop

fop.grp.map <- function (fcn, x, y, n, w) 
{
    z <- dimnames(x)[[1]]
    if (w) 
        z <- yyyymm.lag(z, -n - y - 1)
    z <- fcn(z)
    z
}

#' fop.IC
#' 
#' Summarizes bin excess returns by sub-periods of interest (as defined by <vec>)
#' @param x = a matrix/df with rows indexed by time and columns indexed by bins
#' @param y = a matrix/data frame of returns of the same dimension as <x>
#' @param n = a vector corresponding to the rows of <x> that maps each row to a sub-period of interest (e.g. calendar year)
#' @param w = return horizon in weekdays
#' @param h = an argument which is not used
#' @keywords fop.IC
#' @export
#' @family fop

fop.IC <- function (x, y, n, w, h) 
{
    fop.Bin.underlying(fop.IC.summ, x, y, n, w, h, fop.correl)
}

#' fop.IC.summ
#' 
#' Summarizes IC's
#' @param x = a vector of IC's
#' @param y = an argument which is not used
#' @param n = an argument which is not used
#' @keywords fop.IC.summ
#' @export
#' @family fop

fop.IC.summ <- function (x, y, n) 
{
    z <- matrix(NA, 2, dim(x)[2], F, list(c("Mean", "HitRate"), 
        dimnames(x)[[2]]))
    z["Mean", ] <- apply(x, 2, mean, na.rm = T)
    z["HitRate", ] <- apply(sign(x), 2, mean, na.rm = T) * 50
    z
}

#' fop.rank.xRet
#' 
#' Ranks <x> only when <y> is available
#' @param x = a matrix/df of predictors, the rows of which are indexed by time
#' @param y = an isomekic isoplatic matrix/df containing associated forward returns
#' @keywords fop.rank.xRet
#' @export
#' @family fop

fop.rank.xRet <- function (x, y) 
{
    z <- bbk.holidays(x, y)
    z <- mat.rank(z)
    z
}

#' fop.wrapper
#' 
#' a table of Sharpes, IC's and annualized mean excess returns for: Q1 - a strategy that goes long the top fifth and short the equal-weight universe TxB - a strategy that goes long and short the top and bottom fifth respectively
#' @param x = a matrix/data frame of predictors, the rows of which are YYYYMM or YYYYMMDD
#' @param y = a matrix/data frame of total return indices, the rows of which are YYYYMM or YYYYMMDD
#' @param retW = a numeric vector of forward return windows
#' @param prd.size = size of each compounding period in terms of days (days = 1, wks = 5, etc.) if <x> is indexed by YYYYMMDD or months if <x> is indexed by YYYYMM
#' @param sum.flows = if T, flows get summed. Otherwise they get compounded.
#' @param lag = an integer of predictor lags
#' @param delay = the number of days needed for the predictors to be known
#' @param floW = a numeric vector of trailing flow windows
#' @param nBin = a non-negative integer
#' @param reverse.vbl = T/F depending on whether you want the variable reversed
#' @param sprds = T/F depending on whether spread changes, rather than returns, are needed
#' @keywords fop.wrapper
#' @export
#' @family fop

fop.wrapper <- function (x, y, retW, prd.size = 5, sum.flows = F, lag = 0, delay = 2, 
    floW = 1:20, nBin = 5, reverse.vbl = F, sprds = F) 
{
    z <- fop(x, y, delay, lag, floW, retW, 0, yyyymmdd.to.unity, 
        F, reverse.vbl, prd.size, F, fop.IC, sum.flows, sprds)
    z <- z[, as.character(lag), , "0", "Mean", "IC", "1"]
    dimnames(z)[[2]] <- paste("IC", dimnames(z)[[2]])
    x <- fop(x, y, delay, lag, floW, retW, nBin, yyyymmdd.to.unity, 
        F, reverse.vbl, prd.size, F, fop.Bin, sum.flows, sprds)
    x <- x[, as.character(lag), , as.character(nBin), c("Sharpe", 
        "AnnMn"), c("Q1", "TxB"), "1"]
    x <- mat.ex.array(x)
    z <- data.frame(t(x), z, stringsAsFactors = F)
    z <- z[, txt.expand(c("Q1.Sharpe", "TxB.Sharpe", "IC", "Q1.AnnMn", 
        "TxB.AnnMn"), retW, ".")]
    z
}

#' ftp.all.dir
#' 
#' remote-site directory listing of all sub-folders
#' @param x = remote folder on an ftp site (e.g. "/ftpdata/mystuff")
#' @param y = ftp site (defaults to standard)
#' @param n = user id (defaults to standard)
#' @param w = password (defaults to standard)
#' @keywords ftp.all.dir
#' @export
#' @family ftp

ftp.all.dir <- function (x, y, n, w) 
{
    if (missing(y)) 
        y <- ftp.credential("ftp")
    if (missing(n)) 
        n <- ftp.credential("user")
    if (missing(w)) 
        w <- ftp.credential("pwd")
    z <- ftp.all.files.underlying(x, y, n, w, F)
    z <- txt.right(z, nchar(z) - nchar(x) - 1)
    z
}

#' ftp.all.files
#' 
#' remote-site directory listing of files (incl. sub-folders)
#' @param x = remote folder on an ftp site (e.g. "/ftpdata/mystuff")
#' @param y = ftp site (defaults to standard)
#' @param n = user id (defaults to standard)
#' @param w = password (defaults to standard)
#' @keywords ftp.all.files
#' @export
#' @family ftp

ftp.all.files <- function (x, y, n, w) 
{
    if (missing(y)) 
        y <- ftp.credential("ftp")
    if (missing(n)) 
        n <- ftp.credential("user")
    if (missing(w)) 
        w <- ftp.credential("pwd")
    z <- ftp.all.files.underlying(x, y, n, w, T)
    if (x == "/") 
        x <- ""
    z <- txt.right(z, nchar(z) - nchar(x) - 1)
    z
}

#' ftp.all.files.underlying
#' 
#' remote-site directory listing of files or folders
#' @param x = remote folder on an ftp site (e.g. "/ftpdata/mystuff")
#' @param y = ftp site
#' @param n = user id
#' @param w = password
#' @param h = T/F depending on whether you want files or folders
#' @keywords ftp.all.files.underlying
#' @export
#' @family ftp

ftp.all.files.underlying <- function (x, y, n, w, h) 
{
    z <- NULL
    while (length(x) > 0) {
        cat(x[1], "...\n")
        m <- ftp.dir(x[1], y, n, w, F)
        if (!is.null(m)) {
            j <- names(m)
            if (x[1] != "/" & x[1] != "") 
                j <- paste(x[1], j, sep = "/")
            else j <- paste0("/", j)
            if (any(m == h)) 
                z <- c(z, j[m == h])
            if (any(!m)) 
                x <- c(x, j[!m])
        }
        x <- x[-1]
    }
    z
}

#' ftp.credential
#' 
#' relevant ftp credential
#' @param x = one of ftp/user/pwd
#' @keywords ftp.credential
#' @export
#' @family ftp

ftp.credential <- function (x) 
{
    as.character(map.rname(vec.read(parameters("ftp-credential"), 
        T), x))
}

#' ftp.delete.script
#' 
#' ftp script to delete contents of remote directory
#' @param x = remote folder on an ftp site (e.g. "/ftpdata/mystuff")
#' @param y = ftp site
#' @param n = user id
#' @param w = password
#' @keywords ftp.delete.script
#' @export
#' @family ftp

ftp.delete.script <- function (x, y, n, w) 
{
    if (missing(y)) 
        y <- ftp.credential("ftp")
    if (missing(n)) 
        n <- ftp.credential("user")
    if (missing(w)) 
        w <- ftp.credential("pwd")
    z <- c(paste("open", y), n, w, ftp.delete.script.underlying(x, 
        y, n, w))
    z
}

#' ftp.delete.script.underlying
#' 
#' ftp script to delete contents of remote directory
#' @param x = remote folder on an ftp site (e.g. "/ftpdata/mystuff")
#' @param y = ftp site
#' @param n = user id
#' @param w = password
#' @keywords ftp.delete.script.underlying
#' @export
#' @family ftp

ftp.delete.script.underlying <- function (x, y, n, w) 
{
    z <- paste0("cd \"", x, "\"")
    m <- ftp.dir(x, y, n, w, F)
    h <- names(m)
    if (any(m)) 
        z <- c(z, paste0("del \"", h[m], "\""))
    if (any(!m)) {
        for (j in h[!m]) {
            z <- c(z, ftp.delete.script.underlying(paste(x, j, 
                sep = "/"), y, n, w))
            z <- c(z, paste0("rmdir \"", x, "/", j, "\""))
        }
    }
    z
}

#' ftp.dir
#' 
#' string vector of, or YYYYMMDD vector indexed by, remote file names
#' @param x = remote folder on an ftp site (e.g. "/ftpdata/mystuff")
#' @param y = ftp site (defaults to standard)
#' @param n = user id (defaults to standard)
#' @param w = password (defaults to standard)
#' @param h = T/F depending on whether you want time stamps
#' @keywords ftp.dir
#' @export
#' @family ftp

ftp.dir <- function (x, y, n, w, h = F) 
{
    if (missing(y)) 
        y <- ftp.credential("ftp")
    if (missing(n)) 
        n <- ftp.credential("user")
    if (missing(w)) 
        w <- ftp.credential("pwd")
    ftp.file <- "C:\\temp\\foo.ftp"
    month.abbrv <- vec.named(1:12, month.abb)
    cat(ftp.dir.ftp.code(x, y, n, w, "dir"), file = ftp.file)
    y <- shell(paste0("ftp -i -s:", ftp.file), intern = T)
    y <- ftp.dir.excise.crap(y, "150 Opening data channel for directory listing", 
        "226 Successfully transferred")
    if (!is.null(y)) {
        n <- min(nchar(y)) - 4
        while (any(!is.element(substring(y, n, n + 4), paste0(" ", 
            names(month.abbrv), " ")))) n <- n - 1
        z <- substring(y, n + 1, nchar(y))
        y <- substring(y, 1, n - 1)
        z <- data.frame(substring(z, 1, 3), as.numeric(substring(z, 
            5, 6)), substring(z, 8, 12), substring(z, 14, nchar(z)), 
            stringsAsFactors = F)
        names(z) <- c("mm", "dd", "yyyy", "file")
        if (h) {
            z$mm <- map.rname(month.abbrv, z$mm)
            z$yyyy <- ifelse(txt.has(z$yyyy, ":", T), yyyymm.to.yyyy(yyyymmdd.to.yyyymm(today())), 
                z$yyyy)
            z$yyyy <- as.numeric(z$yyyy)
            z <- vec.named(10000 * z$yyyy + 100 * z$mm + z$dd, 
                z$file)
        }
        else {
            z <- vec.named(substring(y, 1, 1) == "-", z$file)
        }
    }
    else {
        z <- NULL
    }
    z
}

#' ftp.dir.excise.crap
#' 
#' cleans up output
#' @param x = output from ftp directory listing
#' @param y = string demarcating the beginning of useful output
#' @param n = string demarcating the end of useful output
#' @keywords ftp.dir.excise.crap
#' @export
#' @family ftp

ftp.dir.excise.crap <- function (x, y, n) 
{
    w <- y
    w <- txt.left(x, nchar(w)) == w
    proceed <- sum(w) == 1
    if (proceed) {
        m <- length(x)
        x <- x[seq((1:m)[w] + 1, m)]
    }
    if (proceed) {
        w <- n
        w <- txt.left(x, nchar(w)) == w
        proceed <- sum(w) == 1
    }
    if (proceed) {
        m <- length(x)
        if (!w[1]) 
            z <- x[seq(1, (1:m)[w] - 1)]
        else z <- NULL
    }
    if (!proceed) 
        z <- NULL
    z
}

#' ftp.dir.ftp.code
#' 
#' generates ftp code for remote site directory listing
#' @param x = remote folder or file on ftp site (e.g. "/ftpdata/mystuff")
#' @param y = ftp site
#' @param n = user id
#' @param w = password
#' @param h = command to execute (e.g. "ls" or "pwd" or "get")
#' @keywords ftp.dir.ftp.code
#' @export
#' @family ftp

ftp.dir.ftp.code <- function (x, y, n, w, h) 
{
    z <- ftp.txt(y, n, w)
    if (h == "get") {
        z <- paste0(z, "\n", h, " \"", x, "\"")
    }
    else {
        z <- paste0(z, "\ncd \"", x, "\"\n", h)
    }
    z <- paste(z, "disconnect", "quit", sep = "\n")
    z
}

#' ftp.download.script
#' 
#' creates bat/ftp files to get all files from an ftp folder
#' @param x = remote folder on an ftp site (e.g. "/ftpdata/mystuff")
#' @param y = local folder (e.g. "C:\\\\temp\\\\mystuff")
#' @param n = ftp site
#' @param w = user id
#' @param h = password
#' @keywords ftp.download.script
#' @export
#' @family ftp

ftp.download.script <- function (x, y, n, w, h) 
{
    if (missing(n)) 
        n <- ftp.credential("ftp")
    if (missing(w)) 
        w <- ftp.credential("user")
    if (missing(h)) 
        h <- ftp.credential("pwd")
    z <- ftp.all.files(x, n, w, h)
    h <- c(paste("open", n), w, h)
    w <- z
    w.par <- dir.parent(w)
    u.par <- w.par[!duplicated(w.par)]
    u.par <- u.par[order(nchar(u.par))]
    w2.par <- u.par != ""
    z <- txt.left(y, 2)
    if (any(w2.par)) 
        z <- c(z, paste0("mkdir \"", y, "\\", u.par[w2.par], 
            "\""))
    vec <- ifelse(u.par == "", "", "\\")
    vec <- paste0(y, vec, u.par)
    vec <- paste0("cd \"", vec, "\"")
    vec <- c(vec, paste0("ftp -i -s:", y, "\\script\\ftp", 1:length(u.par), 
        ".ftp"))
    vec <- vec[order(rep(seq(1, length(vec)/2), 2))]
    z <- c(z, vec)
    dir.ensure(paste(y, "script", "bat.bat", sep = "\\"))
    cat(z, file = paste(y, "script", "bat.bat", sep = "\\"), 
        sep = "\n")
    for (i.n in 1:length(u.par)) {
        i <- u.par[i.n]
        w2.par <- is.element(w.par, i)
        z <- txt.replace(i, "\\", "/")
        if (x != "" & x != "/") 
            z <- paste(x, z, sep = "/")
        if (txt.right(z, 1) == "/") 
            z <- txt.left(z, nchar(z) - 1)
        z <- paste0("cd \"", z, "\"")
        z <- c(h, z)
        if (i == "") {
            i <- w[w2.par]
        }
        else {
            i <- txt.right(w[w2.par], nchar(w[w2.par]) - nchar(i) - 
                1)
        }
        z <- c(z, paste0("get \"", i, "\""))
        z <- c(z, "disconnect", "quit")
        cat(z, file = paste0(y, "\\script\\", "ftp", i.n, ".ftp"), 
            sep = "\n")
    }
    invisible()
}

#' ftp.file.size
#' 
#' returns file size in KB
#' @param x = a file on ftp site
#' @param y = ftp site
#' @param n = user id
#' @param w = password
#' @keywords ftp.file.size
#' @export
#' @family ftp

ftp.file.size <- function (x, y, n, w) 
{
    if (missing(y)) 
        y <- ftp.credential("ftp")
    if (missing(n)) 
        n <- ftp.credential("user")
    if (missing(w)) 
        w <- ftp.credential("pwd")
    ftp.file <- "C:\\temp\\foo.ftp"
    z <- ftp.txt(y, n, w)
    z <- paste0(z, "\ndir \"", x, "\"")
    z <- paste(z, "disconnect", "quit", sep = "\n")
    cat(z, file = ftp.file)
    z <- NULL
    while (is.null(z)) {
        z <- shell(paste0("ftp -i -s:", ftp.file), intern = T)
        z <- ftp.dir.excise.crap(z, "150 Opening data channel for directory listing", 
            "226 Successfully transferred")
    }
    z <- txt.itrim(z)
    z <- as.numeric(txt.parse(z, txt.space(1))[5])
    if (!is.na(z)) 
        z <- z * 2^-10
    z
}

#' ftp.get
#' 
#' file <x> from remote site
#' @param x = remote file on an ftp site (e.g. "/ftpdata/mystuff/foo.txt")
#' @param y = local folder (e.g. "C:\\\\temp")
#' @param n = ftp site (defaults to standard)
#' @param w = user id (defaults to standard)
#' @param h = password (defaults to standard)
#' @keywords ftp.get
#' @export
#' @family ftp

ftp.get <- function (x, y, n, w, h) 
{
    if (missing(n)) 
        n <- ftp.credential("ftp")
    if (missing(w)) 
        w <- ftp.credential("user")
    if (missing(h)) 
        h <- ftp.credential("pwd")
    ftp.file <- "C:\\temp\\foo.ftp"
    cat(ftp.dir.ftp.code(x, n, w, h, "get"), file = ftp.file)
    bat.file <- "C:\\temp\\foo.bat"
    cat(paste0("C:\ncd \"", y, "\"\nftp -i -s:", ftp.file), file = bat.file)
    z <- shell(bat.file, intern = T)
    invisible()
}

#' ftp.info
#' 
#' parameter <n> associated with <x> flows at the <y> level with the <w> filter
#' @param x = M/W/D depending on whether flows are monthly/weekly/daily
#' @param y = T/F depending on whether you want to check Fund or Share-Class level data
#' @param n = one of sql.table/date.field/ftp.path
#' @param w = filter (e.g. Aggregate/Active/Passive/ETF/Mutual)
#' @keywords ftp.info
#' @export
#' @family ftp

ftp.info <- function (x, y, n, w) 
{
    z <- mat.read(parameters("classif-ftp"), "\t", NULL)
    z <- z[z[, "Type"] == x & z[, "FundLvl"] == y & z[, "filter"] == 
        w, n]
    z
}

#' ftp.put
#' 
#' Writes ftp script to put the relevant file to the right folder
#' @param x = name of the strategy
#' @param y = "daily" or "weekly"
#' @param n = location of the folder on the ftp server
#' @keywords ftp.put
#' @export
#' @family ftp

ftp.put <- function (x, y, n) 
{
    z <- paste0("cd /\ncd \"", n, "\"")
    z <- paste0(z, "\ndel ", strategy.file(x, y))
    z <- paste0(z, "\nput \"", strategy.path(x, y), "\"")
    z
}

#' ftp.sql.factor
#' 
#' SQL code to validate <x> flows at the <y> level
#' @param x = vector of M/W/D depending on whether flows are monthly/weekly/daily
#' @param y = flow date in YYYYMMDD format
#' @param n = fund filter (e.g. Aggregate/Active/Passive/ETF/Mutual)
#' @param w = stock filter (e.g. All/China/Japan)
#' @keywords ftp.sql.factor
#' @export
#' @family ftp

ftp.sql.factor <- function (x, y, n, w) 
{
    if (all(is.element(x, paste0("Flo", c("Trend", "Diff", "Diff2"))))) {
        z <- sql.1dFloTrend(y, c(x, qa.filter.map(n)), 26, w, 
            T)
    }
    else if (all(is.element(x, paste0("ActWt", c("Trend", "Diff", 
        "Diff2"))))) {
        z <- sql.1dActWtTrend(y, c(x, qa.filter.map(n)), w, T)
    }
    else if (all(x == "FloMo")) {
        z <- sql.1dFloMo(y, c(x, qa.filter.map(n)), w, T)
    }
    else if (all(x == "StockD")) {
        z <- sql.1dFloMo(y, c("FloDollar", qa.filter.map(n)), 
            w, T)
    }
    else if (all(x == "FundCtD")) {
        z <- sql.1dFundCt(y, c("FundCt", qa.filter.map(n)), w, 
            T)
    }
    else if (all(x == "FundCtM")) {
        z <- sql.1mFundCt(yyyymmdd.to.yyyymm(y), c("FundCt", 
            qa.filter.map(n)), w, T)
    }
    else if (all(x == "HoldSum")) {
        z <- sql.1mFundCt(yyyymmdd.to.yyyymm(y), c("HoldSum", 
            qa.filter.map(n)), w, T)
    }
    else if (all(x == "Dispersion")) {
        z <- sql.Dispersion(yyyymmdd.to.yyyymm(y), c(x, qa.filter.map(n)), 
            w, T)
    }
    else if (all(is.element(x, c("FundCt", "Herfindahl")))) {
        z <- sql.Herfindahl(yyyymmdd.to.yyyymm(y), c(x, qa.filter.map(n)), 
            w, T)
    }
    else if (all(x == "StockM")) {
        z <- sql.1mFloMo(yyyymmdd.to.yyyymm(y), c("FloDollar", 
            qa.filter.map(n)), w, T)
    }
    else if (all(x == "IOND")) {
        z <- sql.1dFloMo(y, c("Inflow", "Outflow", qa.filter.map(n)), 
            w, T)
    }
    else if (all(x == "IONM")) {
        z <- sql.1mFloMo(yyyymmdd.to.yyyymm(y), c("Inflow", "Outflow", 
            qa.filter.map(n)), w, T)
    }
    else if (all(is.element(x, paste0("Alloc", c("Trend", "Diff", 
        "Mo"))))) {
        z <- sql.1mAllocMo(yyyymmdd.to.yyyymm(y), c(x, qa.filter.map(n)), 
            w, T)
    }
    else if (all(x == "AllocD")) {
        z <- sql.1mAllocD(yyyymmdd.to.yyyymm(y), c("AllocDA", 
            "AllocDInc", "AllocDDec", "AllocDAdd", "AllocDRem", 
            qa.filter.map(n)), w, T)
    }
    else if (all(x == "AllocSkew")) {
        z <- sql.1mAllocSkew(yyyymmdd.to.yyyymm(y), c(x, qa.filter.map(n)), 
            w, T)
    }
    else if (all(is.element(x, c("FwtdEx0", "FwtdIn0", "SwtdEx0", 
        "SwtdIn0")))) {
        z <- sql.TopDownAllocs(yyyymmdd.to.yyyymm(y), c(x, qa.filter.map(n)), 
            w, T)
    }
    else {
        stop("Bad factor")
    }
    z
}

#' ftp.sql.other
#' 
#' SQL code to validate <x> flows at the <y> level
#' @param x = M/W/D/C/I/S depending on flows or allocations
#' @param y = flow date in YYYYMMDD format
#' @param n = filter (e.g. Aggregate/Active/Passive/ETF/Mutual)
#' @keywords ftp.sql.other
#' @export
#' @family ftp

ftp.sql.other <- function (x, y, n) 
{
    sql.table <- ftp.info(x, T, "sql.table", n)
    h <- ftp.info(x, T, "date.field", n)
    cols <- qa.columns(x)[-1][-1]
    if (any(x == c("M", "W", "D"))) {
        w <- list(A = sql.ui(), B = paste(h, "= @dy"))
        w <- sql.and(w)
        z <- c("FundId", paste0("ReportDate = convert(char(8), ", 
            h, ", 112)"))
        z <- c(z, paste0(cols, " = sum(", cols, ")"))
        z <- sql.tbl(z, paste(sql.table, "t1 inner join FundHistory t2 on t1.HFundId = t2.HFundId"), 
            w, paste(h, "FundId", sep = ", "))
    }
    else if (any(x == c("C", "I", "S"))) {
        w <- list(A = sql.ui(), B = paste(h, "= @dy"), C = "FundType in ('B', 'E')")
        if (x == "C") 
            w[["D"]] <- c("(", sql.and(sql.cross.border(F), "", 
                "or"), ")")
        w <- sql.and(w)
        z <- c("t2.FundId", paste0("ReportDate = convert(char(8), ", 
            h, ", 112)"))
        z <- c(z, cols)
        z <- sql.tbl(z, c(paste(sql.table, "t1"), "inner join", 
            "FundHistory t2 on t2.HFundId = t1.HFundId"), w)
    }
    else {
        stop("Bad Argument")
    }
    z <- c(sql.declare("@dy", "datetime", y), sql.unbracket(z))
    z <- paste(z, collapse = "\n")
    z
}

#' ftp.txt
#' 
#' credentials needed to access ftp
#' @param x = ftp site
#' @param y = user id
#' @param n = password
#' @keywords ftp.txt
#' @export
#' @family ftp

ftp.txt <- function (x, y, n) 
{
    paste(c(paste("open", x), y, n), collapse = "\n")
}

#' ftp.upload.script
#' 
#' returns ftp script to copy up files from the local machine
#' @param x = empty remote folder on an ftp site (e.g. "/ftpdata/mystuff")
#' @param y = local folder containing the data (e.g. "C:\\\\temp\\\\mystuff")
#' @param n = ftp site (defaults to standard)
#' @param w = user id (defaults to standard)
#' @param h = password (defaults to standard)
#' @keywords ftp.upload.script
#' @export
#' @family ftp

ftp.upload.script <- function (x, y, n, w, h) 
{
    if (missing(n)) 
        n <- ftp.credential("ftp")
    if (missing(w)) 
        w <- ftp.credential("user")
    if (missing(h)) 
        h <- ftp.credential("pwd")
    z <- c(paste0("open", n), w, h, paste("cd \"", x, "\""), 
        ftp.upload.script.underlying(y), "disconnect", "quit")
    z
}

#' ftp.upload.script.underlying
#' 
#' returns ftp script to copy up files from the local machine
#' @param x = local folder containing the data (e.g. "C:\\\\temp\\\\mystuff")
#' @keywords ftp.upload.script.underlying
#' @export
#' @family ftp

ftp.upload.script.underlying <- function (x) 
{
    y <- dir(x)
    z <- NULL
    if (length(y) > 0) {
        w <- !file.info(paste(x, y, sep = "\\"))$isdir
        if (any(w)) 
            z <- c(z, paste0("put \"", x, "\\", y[w], "\""))
        if (any(!w)) {
            for (n in y[!w]) {
                z <- c(z, paste0(c("mkdir", "cd"), " \"", n, 
                  "\""))
                z <- c(z, ftp.upload.script.underlying(paste(x, 
                  n, sep = "\\")))
                z <- c(z, "cd ..")
            }
        }
    }
    z
}

#' fwd.probs
#' 
#' probability that forward return is positive given predictor is positive
#' @param x = predictor indexed by yyyymmdd or yyyymm
#' @param y = total return index indexed by yyyymmdd or yyyymm
#' @param floW = flow window in days
#' @param sum.flows = T/F depending on whether the predictor is to be summed or compounded
#' @param lag = number of periods to lag the predictor
#' @param delay = delay in knowing data
#' @param doW = day of the week you will trade on (5 = Fri, NULL for monthlies)
#' @param retW = size of forward return horizon
#' @param idx = the index within which you trade
#' @param prd.size = size of each period in terms of days if the rows of <x> are yyyymmdd or months otherwise
#' @keywords fwd.probs
#' @export
#' @family fwd

fwd.probs <- function (x, y, floW, sum.flows, lag, delay, doW, retW, idx, 
    prd.size) 
{
    x <- bbk.data(x, y, floW, sum.flows, lag, delay, doW, retW, 
        idx, prd.size, F)
    y <- x$fwdRet
    x <- x$x
    z <- c("All", "Pos", "Exc", "Last")
    z <- matrix(NA, dim(x)[2], length(z), F, list(dimnames(x)[[2]], 
        z))
    z[, "Last"] <- unlist(x[dim(x)[1], ])
    for (j in dimnames(x)[[2]]) {
        w1 <- x[, j]
        w2 <- y[, j]
        z[j, "All"] <- sum(!is.na(w2) & w2 > 0)/sum(!is.na(w2))
        z[j, "Pos"] <- sum(!is.na(w1) & !is.na(w2) & w2 > 0 & 
            w1 > 0)/sum(!is.na(w1) & !is.na(w2) & w1 > 0)
    }
    z[, "Exc"] <- z[, "Pos"] - z[, "All"]
    z
}

#' fwd.probs.wrapper
#' 
#' probability that forward return is positive given predictor is positive
#' @param x = predictor indexed by yyyymmdd or yyyymm
#' @param y = total return index indexed by yyyymmdd or yyyymm
#' @param floW = flow window in days
#' @param sum.flows = T/F depending on whether the predictor is to be summed or compounded
#' @param lags = number of periods to lag the predictor
#' @param delay = delay in knowing data
#' @param doW = day of the week you will trade on (5 = Fri, NULL for monthlies)
#' @param hz = a vector of forward return windows
#' @param idx = the index within which you trade
#' @param prd.size = size of each period in terms of days if the rows of <x> are yyyymmdd or months otherwise
#' @keywords fwd.probs.wrapper
#' @export
#' @family fwd

fwd.probs.wrapper <- function (x, y, floW, sum.flows, lags, delay, doW, hz, idx, prd.size) 
{
    z <- list()
    for (retW in hz) {
        z[[as.character(retW)]] <- list()
        for (lag in lags) z[[as.character(retW)]][[as.character(lag)]] <- fwd.probs(x, 
            y, floW, sum.flows, lag, delay, doW, retW, idx, prd.size)
        z[[as.character(retW)]] <- simplify2array(z[[as.character(retW)]])
    }
    z <- simplify2array(z)
    z
}

#' gram.schmidt
#' 
#' Gram-Schmidt orthogonalization of <x> to <y>
#' @param x = a numeric vector/matrix/data frame
#' @param y = a numeric isomekic vector
#' @keywords gram.schmidt
#' @export

gram.schmidt <- function (x, y) 
{
    x - tcrossprod(y, crossprod(x, y)/sum(y^2))
}

#' greek.ex.english
#' 
#' returns a named vector
#' @keywords greek.ex.english
#' @export

greek.ex.english <- function () 
{
    vec.named(c("platos", "mekos", "hypsos", "bathos"), c("breadth", 
        "length", "height", "depth"))
}

#' GSec.to.GSgrp
#' 
#' makes Sector groups
#' @param x = a vector of sectors
#' @keywords GSec.to.GSgrp
#' @export

GSec.to.GSgrp <- function (x) 
{
    z <- rep("", length(x))
    z <- ifelse(is.element(x, c(15, 20, 25, 45)), "Cyc", z)
    z <- ifelse(is.element(x, c(10, 30, 35, 50, 55)), "Def", 
        z)
    z <- ifelse(is.element(x, 40), "Fin", z)
    z
}

#' html.flow.english
#' 
#' writes a flow report in English
#' @param x = a named vector of integers (numbers need to be rounded)
#' @param y = a named text vector
#' @param n = line number at which to insert a statement
#' @param w = statement to be inserted
#' @keywords html.flow.english
#' @export
#' @family html

html.flow.english <- function (x, y, n, w) 
{
    z <- format(day.to.date(y["date"]), "%B %d %Y")
    z <- paste("For the week ended", z, "fund flow data from EPFR for", 
        y["AssetClass"], "($")
    z <- paste0(z, int.format(x["AUM"]), "m total assets) reported net")
    z <- paste(z, ifelse(x["last"] > 0, "INFLOWS", "OUTFLOWS"), 
        "of $")
    z <- paste0(z, int.format(abs(x["last"])), "m vs an")
    z <- paste(z, ifelse(x["prior"] > 0, "inflow", "outflow"), 
        "of $")
    z <- paste0(z, int.format(abs(x["prior"])), "m the prior week.")
    if (x["straight"] > 0) {
        u <- paste("These", ifelse(x["last"] > 0, "inflows", 
            "outflows"), "have been taking place for")
        u <- paste(u, x["straight"], ifelse(x["straight"] > 4, 
            "straight", "consecutive"), "weeks")
    }
    else if (x["straight"] == -1) {
        u <- paste("This is the first week of", ifelse(x["last"] > 
            0, "inflows,", "outflows,"))
        u <- paste(u, "the prior week seeing", ifelse(x["last"] > 
            0, "outflows", "inflows"))
    }
    else {
        u <- paste("This is the first week of", ifelse(x["last"] > 
            0, "inflows,", "outflows,"))
        u <- paste(u, "the prior", -x["straight"], "weeks seeing", 
            ifelse(x["last"] > 0, "outflows", "inflows"))
    }
    z <- c(z, u)
    u <- paste(txt.left(y["date"], 4), "YTD has seen")
    if (x["YtdCountInWks"] == 0) {
        u <- paste(u, "no weeks of inflows and")
    }
    else if (x["YtdCountInWks"] == 1) {
        u <- paste(u, "one week of inflows and")
    }
    else {
        u <- paste(u, x["YtdCountInWks"], "weeks of inflows and")
    }
    if (x["YtdCountOutWks"] == 0) {
        u <- paste(u, "no weeks of outflows")
    }
    else if (x["YtdCountOutWks"] == 1) {
        u <- paste(u, "one week of outflows")
    }
    else {
        u <- paste(u, x["YtdCountOutWks"], "weeks of outflows")
    }
    if (x["YtdCountInWks"] > 0 & x["YtdCountOutWks"] > 0) {
        u <- paste0(u, " (largest inflow $", int.format(x["YtdBigIn"]), 
            "m; largest outflow $", int.format(x["YtdBigOut"]), 
            "m)")
    }
    else if (x["YtdCountInWks"] > 0) {
        u <- paste0(u, " (largest inflow $", int.format(x["YtdBigIn"]), 
            "m)")
    }
    else {
        u <- paste0(u, " (largest outflow $", int.format(x["YtdBigOut"]), 
            "m)")
    }
    z <- c(z, u)
    u <- paste("For", txt.left(y["PriorYrWeek"], 4), "there were")
    if (x["PriorYrCountInWks"] == 0) {
        u <- paste(u, "no weeks of inflows and")
    }
    else if (x["PriorYrCountInWks"] == 1) {
        u <- paste(u, "one week of inflows and")
    }
    else {
        u <- paste(u, x["PriorYrCountInWks"], "weeks of inflows and")
    }
    if (x["PriorYrCountOutWks"] == 0) {
        u <- paste(u, "no weeks of outflows")
    }
    else if (x["PriorYrCountOutWks"] == 1) {
        u <- paste(u, "one week of outflows")
    }
    else {
        u <- paste(u, x["PriorYrCountOutWks"], "weeks of outflows")
    }
    if (x["PriorYrCountInWks"] > 0 & x["PriorYrCountOutWks"] > 
        0) {
        u <- paste0(u, " (largest inflow $", int.format(x["PriorYrBigIn"]), 
            "m; largest outflow $", int.format(x["PriorYrBigOut"]), 
            "m)")
    }
    else if (x["PriorYrCountInWks"] > 0) {
        u <- paste0(u, " (largest inflow $", int.format(x["PriorYrBigIn"]), 
            "m)")
    }
    else {
        u <- paste0(u, " (largest outflow $", int.format(x["PriorYrBigOut"]), 
            "m)")
    }
    z <- c(z, u)
    if (x["FourWeekAvg"] > 0) {
        u <- paste0("4-week moving average: $", int.format(x["FourWeekAvg"]), 
            "m inflow (4-week cumulative: $", int.format(x["FourWeekSum"]), 
            "m inflow)")
    }
    else {
        u <- paste0("4-week moving average: $", int.format(-x["FourWeekAvg"]), 
            "m outflow (4-week cumulative: $", int.format(-x["FourWeekSum"]), 
            "m outflow)")
    }
    z <- c(z, u)
    u <- paste(txt.left(y["date"], 4), "flow data (through", 
        format(day.to.date(y["date"]), "%B %d"))
    if (x["YtdCumSum"] > 0) {
        u <- paste0(u, "): $", int.format(x["YtdCumSum"]), "m cumulative INFLOW, or weekly average of $", 
            int.format(x["YtdCumAvg"]), "m inflow")
    }
    else {
        u <- paste0(u, "): $", int.format(-x["YtdCumSum"]), "m cumulative OUTFLOW, or weekly average of $", 
            int.format(-x["YtdCumAvg"]), "m outflow")
    }
    z <- c(z, u)
    u <- paste(txt.left(y["PriorYrWeek"], 4), "flow data (through", 
        format(day.to.date(y["PriorYrWeek"]), "%B %d"))
    if (x["PriorYrCumSum"] > 0) {
        u <- paste0(u, "): $", int.format(x["PriorYrCumSum"]), 
            "m cumulative INFLOW, or weekly average of $", int.format(x["PriorYrCumAvg"]), 
            "m inflow")
    }
    else {
        u <- paste0(u, "): $", int.format(-x["PriorYrCumSum"]), 
            "m cumulative OUTFLOW, or weekly average of $", int.format(-x["PriorYrCumAvg"]), 
            "m outflow")
    }
    z <- c(z, u)
    if (!missing(n) & !missing(w)) 
        z <- c(z[1:n], w, z[seq(n + 1, length(z))])
    z[1] <- paste0("<br>", z[1], "<ul>")
    z[-1] <- paste0("<li>", z[-1], "</li>")
    z <- c(z, "</ul></p>")
    z <- paste(z, collapse = "\n")
    z
}

#' html.flow.underlying
#' 
#' list object containing the following items: a) text - dates and text information about flows b) numbers - numeric summary of the flows
#' @param x = a numeric vector indexed by YYYYMMDD
#' @keywords html.flow.underlying
#' @export
#' @family html

html.flow.underlying <- function (x) 
{
    x <- x[order(names(x), decreasing = T)]
    z <- vec.named(x[1:2], c("last", "prior"))
    n <- vec.named(names(x)[1], "date")
    z["FourWeekAvg"] <- mean(x[1:4])
    z["FourWeekSum"] <- sum(x[1:4])
    y <- x > 0
    y <- seq(1, length(y))[!duplicated(y)][2] - 1
    if (y > 1) {
        z["straight"] <- y
    }
    else {
        y <- x > 0
        y <- y[-1]
        y <- seq(1, length(y))[!duplicated(y)][2] - 1
        z["straight"] <- -y
    }
    y <- x[txt.left(names(x), 4) == txt.left(names(x)[1], 4)]
    z["YtdCountInWks"] <- sum(y > 0)
    z["YtdCountOutWks"] <- sum(y < 0)
    z["YtdBigIn"] <- max(y)
    z["YtdBigOut"] <- -min(y)
    y <- x[txt.left(names(x), 4) != txt.left(names(x)[1], 4)]
    y <- y[txt.left(names(y), 4) == txt.left(names(y)[1], 4)]
    z["PriorYrCountInWks"] <- sum(y > 0)
    z["PriorYrCountOutWks"] <- sum(y < 0)
    z["PriorYrBigIn"] <- max(y)
    z["PriorYrBigOut"] <- -min(y)
    y <- x[txt.left(names(x), 4) == txt.left(names(x)[1], 4)]
    z["YtdCumAvg"] <- mean(y)
    z["YtdCumSum"] <- sum(y)
    y <- x[txt.left(names(x), 4) != txt.left(names(x)[1], 4)]
    y <- y[txt.left(names(y), 4) == txt.left(names(y)[1], 4)]
    y <- y[order(names(y))]
    y <- y[1:sum(txt.left(names(x), 4) == txt.left(names(x)[1], 
        4))]
    y <- y[order(names(y), decreasing = T)]
    n["PriorYrWeek"] <- names(y)[1]
    z["PriorYrCumAvg"] <- mean(y)
    z["PriorYrCumSum"] <- sum(y)
    z <- list(numbers = z, text = n)
    z
}

#' html.tbl
#' 
#' renders <x> in html
#' @param x = matrix/data-frame
#' @param y = T/F depending on whether integer format is to be applied
#' @keywords html.tbl
#' @export
#' @family html

html.tbl <- function (x, y) 
{
    if (y) {
        x <- round(x)
        x <- mat.ex.matrix(lapply(x, int.format), dimnames(x)[[1]])
    }
    z <- "<TABLE border=\"0\""
    z <- c(z, paste0("<TR><TH><TH>", paste(dimnames(x)[[2]], 
        collapse = "<TH>")))
    y <- dimnames(x)[[1]]
    x <- mat.ex.matrix(x)
    x$sep <- "</TD><TD align=\"right\">"
    z <- c(z, paste0("<TR><TH>", y, "<TD align=\"right\">", do.call(paste, 
        x)))
    z <- paste(c(z, "</TABLE>"), collapse = "\n")
    z
}

#' int.format
#' 
#' adds commas "1,234,567"
#' @param x = a vector of integers
#' @keywords int.format
#' @export
#' @family int

int.format <- function (x) 
{
    z <- as.character(x)
    y <- ifelse(txt.left(z, 1) == "-", "-", "")
    z <- ifelse(txt.left(z, 1) == "-", txt.right(z, nchar(z) - 
        1), z)
    n <- 3
    w <- nchar(z)
    while (any(w > n)) {
        z <- ifelse(w > n, paste(txt.left(z, w - n), txt.right(z, 
            n), sep = ","), z)
        w <- w + ifelse(w > n, 1, 0)
        n <- n + 4
    }
    z <- paste0(y, z)
    z
}

#' int.to.prime
#' 
#' prime factors of <x>
#' @param x = an integer
#' @keywords int.to.prime
#' @export
#' @family int

int.to.prime <- function (x) 
{
    n <- floor(sqrt(x))
    while (n > 1 & x%%n > 0) n <- n - 1
    if (n == 1) 
        z <- x
    else z <- z <- c(int.to.prime(n), int.to.prime(x/n))
    z <- z[order(z)]
    z
}

#' knapsack.count
#' 
#' number of ways to subdivide <x> things amongst <y> people
#' @param x = a non-negative integer
#' @param y = a positive integer
#' @keywords knapsack.count
#' @export
#' @family knapsack

knapsack.count <- function (x, y) 
{
    z <- matrix(1, x + 1, y, F, list(0:x, 1:y))
    if (x > 0 & y > 1) 
        for (i in 1:x) for (j in 2:y) z[i + 1, j] <- z[i, j] + 
            z[i + 1, j - 1]
    z <- z[x + 1, y]
    z
}

#' knapsack.ex.int
#' 
#' inverse of knapsack.to.int; returns a vector of length <n>, the elements of which sum to <y>
#' @param x = a positive integer
#' @param y = a positive integer
#' @param n = a positive integer
#' @keywords knapsack.ex.int
#' @export
#' @family knapsack

knapsack.ex.int <- function (x, y, n) 
{
    z <- NULL
    while (x != 1) {
        x <- x - 1
        i <- 0
        while (x > 0) {
            i <- i + 1
            h <- knapsack.count(i, n - 1)
            x <- x - h
        }
        z <- c(y - i, z)
        x <- x + h
        y <- y - z[1]
        n <- n - 1
    }
    z <- c(rep(0, n - 1), y, z)
    z
}

#' knapsack.next
#' 
#' next way to subdivide <sum(x)> things amongst <length(x)> people
#' @param x = a vector of non-negative integers
#' @keywords knapsack.next
#' @export
#' @family knapsack

knapsack.next <- function (x) 
{
    m <- length(x)
    w <- x > 0
    w <- w & !duplicated(w)
    if (w[1]) {
        n <- x[1]
        x[1] <- 0
        w <- x > 0
        w <- w & !duplicated(w)
        x[(1:m)[w] - 1:0] <- x[(1:m)[w] - 1:0] + c(1 + n, -1)
    }
    else {
        x[(1:m)[w] - 1:0] <- x[(1:m)[w] - 1:0] + c(1, -1)
    }
    z <- x
    z
}

#' knapsack.prev
#' 
#' inverse of knapsack.next
#' @param x = a vector of non-negative integers
#' @keywords knapsack.prev
#' @export
#' @family knapsack

knapsack.prev <- function (x) 
{
    m <- length(x)
    w <- x > 0
    w <- w & !duplicated(w)
    w <- (1:m)[w]
    if (x[w] == 1 | w == 1) {
        x[w + 0:1] <- x[w + 0:1] + c(-1, 1)
    }
    else {
        x[c(1, w + 0:1)] <- x[c(1, w + 0:1)] + c(x[w] - 1, -x[w], 
            1)
    }
    z <- x
    z
}

#' knapsack.to.int
#' 
#' maps each particular way to subdivide <sum(x)> things amongst <length(x)> people to the number line
#' @param x = a vector of non-negative integers
#' @keywords knapsack.to.int
#' @export
#' @family knapsack

knapsack.to.int <- function (x) 
{
    n <- sum(x)
    z <- 1
    m <- length(x) - 1
    while (m > 0) {
        i <- sum(x[1:m])
        while (i > 0) {
            z <- z + knapsack.count(i - 1, m)
            i <- i - 1
        }
        m <- m - 1
    }
    z
}

#' latin.ex.arabic
#' 
#' returns <x> expressed as lower-case latin numerals
#' @param x = a numeric vector
#' @keywords latin.ex.arabic
#' @export
#' @family latin

latin.ex.arabic <- function (x) 
{
    y <- latin.to.arabic.underlying()
    x <- as.numeric(x)
    w <- is.na(x) | x < 0 | round(x) != x
    z <- rep("", length(x))
    if (all(!w)) {
        for (i in names(y)) {
            w <- x >= y[i]
            while (any(w)) {
                z[w] <- paste0(z[w], i)
                x[w] <- x[w] - y[i]
                w <- x >= y[i]
            }
        }
    }
    else z[!w] <- latin.ex.arabic(x[!w])
    z
}

#' latin.to.arabic
#' 
#' returns <x> expressed as an integer
#' @param x = a character vector of latin numerals
#' @keywords latin.to.arabic
#' @export
#' @family latin

latin.to.arabic <- function (x) 
{
    y <- latin.to.arabic.underlying()
    x <- as.character(x)
    x <- txt.trim(x)
    x <- ifelse(is.na(x), "NA", x)
    x <- tolower(x)
    w <- x
    for (i in names(y)) w <- txt.replace(w, i, "")
    w <- w == ""
    if (all(w)) {
        z <- rep(0, length(x))
        for (i in names(y)) {
            n <- nchar(i)
            w <- txt.left(x, n) == i
            while (any(w)) {
                z[w] <- z[w] + as.numeric(y[i])
                x[w] <- txt.right(x[w], nchar(x[w]) - n)
                w <- txt.left(x, n) == i
            }
        }
    }
    else {
        z <- rep(NA, length(x))
        z[w] <- latin.to.arabic(x[w])
    }
    z
}

#' latin.to.arabic.underlying
#' 
#' basic map of latin to arabic numerals
#' @keywords latin.to.arabic.underlying
#' @export
#' @family latin

latin.to.arabic.underlying <- function () 
{
    z <- c(1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 
        1)
    names(z) <- c("m", "cm", "d", "cd", "c", "xc", "l", "xl", 
        "x", "ix", "v", "iv", "i")
    z
}

#' list.common.row.space
#' 
#' list object with the elements mapped to the common row space
#' @param fcn = function used to combine row spaces
#' @param x = a list of mat objects
#' @param y = column containing row names
#' @keywords list.common.row.space
#' @export

list.common.row.space <- function (fcn, x, y) 
{
    x <- lapply(x, mat.index, y, F)
    fcn.loc <- function(x) dimnames(x)[[1]]
    z <- lapply(x, fcn.loc)
    z <- Reduce(fcn, z)
    z <- z[order(z)]
    z <- lapply(x, map.rname, z)
    z
}

#' load.dy.vbl
#' 
#' Loads a daily variable
#' @param beg = a single YYYYMMDD
#' @param end = a single YYYYMMDD
#' @param mk.fcn = a function
#' @param optional.args = passed down to <mk.fcn>
#' @param vbl.name = name under which the variable is to be stored
#' @param out.fldr = R-object folder
#' @param env = stock-flows environment
#' @keywords load.dy.vbl
#' @export
#' @family load

load.dy.vbl <- function (beg, end, mk.fcn, optional.args, vbl.name, out.fldr, 
    env) 
{
    load.dy.vbl.underlying(beg, end, mk.fcn, optional.args, vbl.name, 
        out.fldr, env, yyyymmdd.to.yyyymm, load.dy.vbl.1obj)
    invisible()
}

#' load.dy.vbl.1obj
#' 
#' Loads a daily variable
#' @param beg = a single YYYYMMDD
#' @param end = a single YYYYMMDD
#' @param mk.fcn = a function
#' @param optional.args = passed down to <mk.fcn>
#' @param vbl.name = name under which the variable is to be stored
#' @param mo = the YYYYMM for which the object is to be made
#' @param env = stock-flows environment
#' @keywords load.dy.vbl.1obj
#' @export
#' @family load

load.dy.vbl.1obj <- function (beg, end, mk.fcn, optional.args, vbl.name, mo, env) 
{
    z <- flowdate.ex.yyyymm(mo, F)
    z <- paste(vbl.name, txt.right(z, 2), sep = ".")
    z <- matrix(NA, dim(env$classif)[1], length(z), F, list(dimnames(env$classif)[[1]], 
        z))
    dd <- txt.right(dimnames(z)[[2]], 2)
    dd <- dd[as.numeric(paste0(mo, dd)) >= as.numeric(beg)]
    dd <- dd[as.numeric(paste0(mo, dd)) <= as.numeric(end)]
    for (i in dd) {
        cat(i, "")
        z[, paste(vbl.name, i, sep = ".")] <- mk.fcn(paste0(mo, 
            i), optional.args, env)
    }
    z <- mat.ex.matrix(z)
    z
}

#' load.dy.vbl.underlying
#' 
#' Loads a variable
#' @param beg = a single YYYYMMDD
#' @param end = a single YYYYMMDD
#' @param mk.fcn = a function
#' @param optional.args = passed down to <mk.fcn>
#' @param vbl.name = name under which the variable is to be stored
#' @param out.fldr = R-object folder
#' @param env = stock-flows environment
#' @param fcn.conv = conversion from period of columns to period of objects
#' @param fcn.load = function to load one object
#' @keywords load.dy.vbl.underlying
#' @export
#' @family load

load.dy.vbl.underlying <- function (beg, end, mk.fcn, optional.args, vbl.name, out.fldr, 
    env, fcn.conv, fcn.load) 
{
    for (mo in yyyymm.seq(fcn.conv(beg), fcn.conv(end))) {
        cat(mo, ":")
        z <- fcn.load(beg, end, mk.fcn, optional.args, vbl.name, 
            mo, env)
        saveRDS(z, file = paste(out.fldr, paste(vbl.name, mo, 
            "r", sep = "."), sep = "\\"), ascii = T)
        cat("\n")
    }
    invisible()
}

#' load.mo.vbl
#' 
#' Loads a monthly variable
#' @param beg = a single YYYYMM
#' @param end = a single YYYYMM
#' @param mk.fcn = a function
#' @param optional.args = passed down to <mk.fcn>
#' @param vbl.name = name under which the variable is to be stored
#' @param out.fldr = R-object folder
#' @param env = stock-flows environment
#' @keywords load.mo.vbl
#' @export
#' @family load

load.mo.vbl <- function (beg, end, mk.fcn, optional.args, vbl.name, out.fldr, 
    env) 
{
    load.dy.vbl.underlying(beg, end, mk.fcn, optional.args, vbl.name, 
        out.fldr, env, yyyymm.to.yyyy, load.mo.vbl.1obj)
    invisible()
}

#' load.mo.vbl.1obj
#' 
#' Loads a monthly variable
#' @param beg = a single YYYYMM
#' @param end = a single YYYYMM
#' @param mk.fcn = a function
#' @param optional.args = passed down to <mk.fcn>
#' @param vbl.name = name under which the variable is to be stored
#' @param yyyy = the period for which the object is to be made
#' @param env = stock-flows environment
#' @keywords load.mo.vbl.1obj
#' @export
#' @family load

load.mo.vbl.1obj <- function (beg, end, mk.fcn, optional.args, vbl.name, yyyy, env) 
{
    z <- paste(vbl.name, 1:12, sep = ".")
    z <- matrix(NA, dim(env$classif)[1], length(z), F, list(dimnames(env$classif)[[1]], 
        z))
    mm <- 1:12
    mm <- mm[100 * yyyy + mm >= beg]
    mm <- mm[100 * yyyy + mm <= end]
    for (i in mm) {
        cat(i, "")
        z[, paste(vbl.name, i, sep = ".")] <- mk.fcn(as.character(100 * 
            yyyy + i), optional.args, env)
    }
    z <- mat.ex.matrix(z)
    z
}

#' machine
#' 
#' folder of function source file
#' @param x = argument that applies to Vik's machine
#' @param y = argument that applies to prod dev
#' @keywords machine
#' @export

machine <- function (x, y) 
{
    if (Sys.info()[["nodename"]] != "OpsServerDev") 
        x
    else y
}

#' map.classif
#' 
#' Maps data to the row space of <y>
#' @param x = a named vector
#' @param y = <classif>
#' @param n = something like "isin" or "HSId"
#' @keywords map.classif
#' @export
#' @family map

map.classif <- function (x, y, n) 
{
    z <- vec.to.list(intersect(c(n, paste0(n, 1:5)), dimnames(y)[[2]]))
    fcn <- function(i) as.numeric(map.rname(x, y[, i]))
    z <- avail(sapply(z, fcn))
    z
}

#' map.rname
#' 
#' returns a matrix/df, the row names of which match up with <y>
#' @param x = a vector/matrix/data-frame
#' @param y = a vector (usually string)
#' @keywords map.rname
#' @export
#' @family map

map.rname <- function (x, y) 
{
    if (is.null(dim(x))) {
        z <- vec.named(, y)
        w <- is.element(y, names(x))
        if (any(w)) 
            z[w] <- x[names(z)[w]]
    }
    else {
        w <- !is.element(y, dimnames(x)[[1]])
        if (any(w)) {
            y.loc <- matrix(NA, sum(w), dim(x)[2], F, list(y[w], 
                dimnames(x)[[2]]))
            x <- rbind(x, y.loc)
        }
        if (dim(x)[2] == 1) {
            z <- matrix(x[as.character(y), 1], length(y), 1, 
                F, list(y, dimnames(x)[[2]]))
        }
        else z <- x[as.character(y), ]
    }
    z
}

#' mat.combine
#' 
#' Combines <x> and <y>
#' @param fcn = the function you want applied to row space of <x> and <y>
#' @param x = a matrix/df
#' @param y = a matrix/df
#' @keywords mat.combine
#' @export
#' @family mat

mat.combine <- function (fcn, x, y) 
{
    z <- fcn(dimnames(x)[[1]], dimnames(y)[[1]])
    z <- z[order(z)]
    x <- map.rname(x, z)
    y <- map.rname(y, z)
    z <- data.frame(x, y)
    z
}

#' mat.compound
#' 
#' Compounds across the rows
#' @param x = a matrix/df of percentage returns
#' @keywords mat.compound
#' @export
#' @family mat

mat.compound <- function (x) 
{
    fcn.mat.num(compound, x, , F)
}

#' mat.correl
#' 
#' Returns the correlation of <x> & <y> if <x> is a vector or those between the rows of <x> and <y> otherwise
#' @param x = a vector/matrix/data-frame
#' @param y = an isomekic vector or isomekic isoplatic matrix/data-frame
#' @keywords mat.correl
#' @export
#' @family mat

mat.correl <- function (x, y) 
{
    fcn.mat.num(correl, x, y, F)
}

#' mat.count
#' 
#' counts observations of the columns of <x>
#' @param x = a matrix/df
#' @keywords mat.count
#' @export
#' @family mat

mat.count <- function (x) 
{
    fcn <- function(x) sum(!is.na(x))
    z <- fcn.mat.num(fcn, x, , T)
    z <- c(z, round(100 * z/dim(x)[1], 1))
    z <- matrix(z, dim(x)[2], 2, F, list(dimnames(x)[[2]], c("obs", 
        "pct")))
    z
}

#' mat.daily.to.monthly
#' 
#' returns latest data in each month indexed by <yyyymm> ascending
#' @param x = a matrix/df of daily data
#' @param y = T/F depending on whether data points must be from month ends
#' @keywords mat.daily.to.monthly
#' @export
#' @family mat

mat.daily.to.monthly <- function (x, y = F) 
{
    z <- x[order(dimnames(x)[[1]], decreasing = T), ]
    z <- z[!duplicated(yyyymmdd.to.yyyymm(dimnames(z)[[1]])), 
        ]
    if (y) {
        w <- yyyymmdd.to.yyyymm(dimnames(z)[[1]])
        w <- yyyymmdd.ex.yyyymm(w)
        w <- w == dimnames(z)[[1]]
        z <- z[w, ]
    }
    dimnames(z)[[1]] <- yyyymmdd.to.yyyymm(dimnames(z)[[1]])
    z <- mat.reverse(z)
    z
}

#' mat.daily.to.weekly
#' 
#' returns latest data in each week in ascending order
#' @param x = a matrix/df of daily data
#' @param y = an integer representing the day the week ends on 0 is Sun, 1 is Mon, ..., 6 is Sat
#' @keywords mat.daily.to.weekly
#' @export
#' @family mat

mat.daily.to.weekly <- function (x, y) 
{
    z <- x[order(dimnames(x)[[1]], decreasing = T), ]
    z <- z[!duplicated(day.to.week(dimnames(z)[[1]], y)), ]
    dimnames(z)[[1]] <- day.to.week(dimnames(z)[[1]], y)
    z <- mat.reverse(z)
    z
}

#' mat.ex.array
#' 
#' a data frame with the first dimension forming the column space
#' @param x = an array
#' @keywords mat.ex.array
#' @export
#' @family mat

mat.ex.array <- function (x) 
{
    z <- do.call(paste, rev(expand.grid(dimnames(x)[-1], stringsAsFactors = F)))
    z <- matrix(as.vector(x), length(z), dim(x)[1], T, list(z, 
        dimnames(x)[[1]]))
    z
}

#' mat.ex.array3d
#' 
#' unlists the contents of an array to a data frame
#' @param x = a three-dimensional numerical array
#' @param y = a vector of length 3
#' @keywords mat.ex.array3d
#' @export
#' @family mat

mat.ex.array3d <- function (x, y = 1:3) 
{
    z <- aperm(x, order(y))
    z <- t(mat.ex.array(z))
    z
}

#' mat.ex.matrix
#' 
#' converts into a data frame
#' @param x = a matrix
#' @param y = desired row names (defaults to NULL)
#' @keywords mat.ex.matrix
#' @export
#' @family mat

mat.ex.matrix <- function (x, y = NULL) 
{
    as.data.frame(x, row.names = y, stringsAsFactors = F)
}

#' mat.ex.vec
#' 
#' transforms into a 1/0 matrix of bin memberships if <y> is missing or the values of <y> otherwise
#' @param x = a numeric or character vector
#' @param y = an isomekic vector of associated values
#' @param n = T/F depending on whether "Q" is to be appended to column headers
#' @keywords mat.ex.vec
#' @export
#' @family mat

mat.ex.vec <- function (x, y, n = T) 
{
    if (!is.null(names(x))) 
        w <- names(x)
    else w <- 1:length(x)
    x <- as.vector(x)
    z <- x[!duplicated(x)]
    z <- z[!is.na(z)]
    z <- z[order(z)]
    z <- matrix(x, length(x), length(z), F, list(w, z))
    z <- !is.na(z) & z == matrix(dimnames(z)[[2]], dim(z)[1], 
        dim(z)[2], T)
    if (!missing(y)) 
        z <- ifelse(z, y, NA)
    else z <- fcn.mat.vec(as.numeric, z, , T)
    if (n) 
        dimnames(z)[[2]] <- paste0("Q", dimnames(z)[[2]])
    z <- mat.ex.matrix(z)
    z
}

#' mat.fake
#' 
#' Returns a data frame for testing purposes
#' @keywords mat.fake
#' @export
#' @family mat

mat.fake <- function () 
{
    n <- 7
    m <- 5
    z <- seq(1, n * m)
    z <- z[order(rnorm(n * m))]
    z <- matrix(z, n, m, F, list(1:n, char.ex.int(64 + 1:m)))
    z <- mat.ex.matrix(z)
    z
}

#' mat.index
#' 
#' indexes <x> by, and, if <n>, removes, columns <y>
#' @param x = a matrix/df
#' @param y = columns
#' @param n = T/F depending on whether you remove columns <y>
#' @keywords mat.index
#' @export
#' @family mat

mat.index <- function (x, y = 1, n = T) 
{
    if (all(is.element(y, 1:dim(x)[2]))) {
        w <- is.element(1:dim(x)[2], y)
    }
    else {
        w <- is.element(dimnames(x)[[2]], y)
    }
    if (sum(w) > 1) 
        z <- do.call(paste, mat.ex.matrix(x)[, y])
    else z <- x[, w]
    if (any(is.na(z))) 
        stop("NA's in row indices ...")
    if (any(duplicated(z))) 
        stop("Duplicated row indices ...")
    if (!n) {
        dimnames(x)[[1]] <- z
        z <- x
    }
    else if (sum(!w) > 1) {
        dimnames(x)[[1]] <- z
        z <- x[, !w]
    }
    else {
        z <- vec.named(x[, !w], z)
    }
    z
}

#' mat.lag
#' 
#' Returns data lagged <y> periods with the same row space as <x>
#' @param x = a matrix/df indexed by time running FORWARDS
#' @param y = number of periods over which to lag
#' @param n = if T simple positional lagging is used. If F, yyyymm.lag is invoked.
#' @param w = used only when !n. Maps to the original row space of <x>
#' @param h = T/F depending on whether you wish to lag by yyyymmdd or flowdate
#' @keywords mat.lag
#' @export
#' @family mat

mat.lag <- function (x, y, n, w = T, h = T) 
{
    z <- x
    if (n) {
        if (y > 0) {
            z[seq(1 + y, dim(x)[1]), ] <- x[seq(1, dim(x)[1] - 
                y), ]
            z[1:y, ] <- NA
        }
        if (y < 0) {
            z[seq(1, dim(x)[1] + y), ] <- x[seq(1 - y, dim(x)[1]), 
                ]
            z[seq(dim(x)[1] + y + 1, dim(x)[1]), ] <- NA
        }
    }
    else {
        dimnames(z)[[1]] <- yyyymm.lag(dimnames(x)[[1]], -y, 
            h)
        if (w) 
            z <- map.rname(z, dimnames(x)[[1]])
    }
    z
}

#' mat.last.to.first
#' 
#' Re-orders so the last <y> columns come first
#' @param x = a matrix/df
#' @param y = a non-negative integer
#' @keywords mat.last.to.first
#' @export
#' @family mat

mat.last.to.first <- function (x, y = 1) 
{
    x[, order((1:dim(x)[2] + y - 1)%%dim(x)[2])]
}

#' mat.rank
#' 
#' ranks <x> if <x> is a vector or the rows of <x> otherwise
#' @param x = a vector/matrix/data-frame
#' @keywords mat.rank
#' @export
#' @family mat

mat.rank <- function (x) 
{
    fcn <- function(x) fcn.nonNA(rank, -x)
    z <- fcn.mat.vec(fcn, x, , F)
    z
}

#' mat.reverse
#' 
#' reverses row order
#' @param x = a matrix/data-frame
#' @keywords mat.reverse
#' @export
#' @family mat

mat.reverse <- function (x) 
{
    x[dim(x)[1]:1, ]
}

#' mat.same
#' 
#' T/F depending on whether <x> and <y> are identical
#' @param x = a matrix/df
#' @param y = an isomekic isoplatic matrix/df
#' @keywords mat.same
#' @export
#' @family mat

mat.same <- function (x, y) 
{
    all(fcn.mat.num(vec.same, x, y, T))
}

#' mat.subset
#' 
#' <x> subset to <y>
#' @param x = a matrix/df
#' @param y = a vector
#' @keywords mat.subset
#' @export
#' @family mat

mat.subset <- function (x, y) 
{
    w <- is.element(y, dimnames(x)[[2]])
    if (any(!w)) {
        err.raise(y[!w], F, "Warning: The following columns are missing")
        z <- t(map.rname(t(x), y))
    }
    else if (length(y) == 1) {
        z <- vec.named(x[, y], dimnames(x)[[1]])
    }
    else {
        z <- x[, y]
    }
    z
}

#' mat.to.first.data.row
#' 
#' the row number of the first row containing data
#' @param x = a matrix/data-frame
#' @keywords mat.to.first.data.row
#' @export
#' @family mat

mat.to.first.data.row <- function (x) 
{
    z <- 1
    while (all(is.na(unlist(x[z, ])))) z <- z + 1
    z
}

#' mat.to.lags
#' 
#' a 3D array of <x> together with itself lagged 1, ..., <y> - 1 times
#' @param x = a matrix/df indexed by time running FORWARDS
#' @param y = number of lagged values desired plus one
#' @param n = if T simple positional lagging is used. If F, yyyymm.lag is invoked
#' @param w = size of each period in terms of YYYYMMDD or YYYYMM depending on the rows of <x>
#' @keywords mat.to.lags
#' @export
#' @family mat

mat.to.lags <- function (x, y, n = T, w = 1) 
{
    z <- array(NA, c(dim(x), y), list(dimnames(x)[[1]], dimnames(x)[[2]], 
        paste0("lag", 1:y - 1)))
    for (i in 1:y) z[, , i] <- unlist(mat.lag(x, (i - 1) * w, 
        n))
    z
}

#' mat.to.last.Idx
#' 
#' the last row index for which we have data
#' @param x = a matrix/df
#' @keywords mat.to.last.Idx
#' @export
#' @family mat

mat.to.last.Idx <- function (x) 
{
    z <- dimnames(x)[[1]][dim(x)[1]]
    cat("Original data had", dim(x)[1], "rows ending at", z, 
        "...\n")
    z
}

#' mat.to.matrix
#' 
#' converts <x> to a matrix
#' @param x = a matrix/data-frame with 3 columns corresponding respectively with the rows, columns and entries of the resulting matrix
#' @keywords mat.to.matrix
#' @export
#' @family mat

mat.to.matrix <- function (x) 
{
    u.row <- vec.unique(x[, 1])
    u.col <- vec.unique(x[, 2])
    x <- vec.named(x[, 3], paste(x[, 1], x[, 2]))
    n.row <- length(u.row)
    n.col <- length(u.col)
    vec <- rep(u.row, n.col)
    vec <- paste(vec, rep(u.col, n.row)[order(rep(1:n.col, n.row))])
    vec <- as.numeric(map.rname(x, vec))
    z <- matrix(vec, n.row, n.col, F, list(u.row, u.col))
    z
}

#' mat.to.obs
#' 
#' Returns 0 if <x> is NA or 1 otherwise.
#' @param x = a vector/matrix/dataframe
#' @keywords mat.to.obs
#' @export
#' @family mat

mat.to.obs <- function (x) 
{
    fcn <- function(x) as.numeric(!is.na(x))
    z <- fcn.mat.vec(fcn, x, , T)
    z
}

#' mat.to.xlModel
#' 
#' prepends the trade open and close dates and re-indexes by data date (as needed)
#' @param x = a data frame indexed by data dates or trade open dates
#' @param y = number of days needed for flow data to be known
#' @param n = return horizon in weekdays
#' @param w = T/F depending on whether the index is data or trade-open date
#' @keywords mat.to.xlModel
#' @export
#' @family mat

mat.to.xlModel <- function (x, y = 2, n = 5, w = F) 
{
    z <- c("Open", "Close")
    z <- matrix(NA, dim(x)[1], length(z), F, list(dimnames(x)[[1]], 
        z))
    if (w) 
        z[, "Open"] <- yyyymm.lag(dimnames(z)[[1]], -y)
    if (!w) {
        z[, "Open"] <- dimnames(z)[[1]]
        dimnames(z)[[1]] <- yyyymm.lag(z[, "Open"], y)
    }
    z[, "Close"] <- yyyymm.lag(z[, "Open"], -n)
    if (all(nchar(dimnames(x)[[1]]) == 8)) {
        if (any(day.to.weekday(z[, "Open"]) != "5") | any(day.to.weekday(z[, 
            "Close"]) != "5")) {
            cat("WARNING: YOU ARE NOT TRADING FRIDAY TO FRIDAY!\n")
        }
    }
    z <- cbind(z, x)
    z <- z[order(dimnames(z)[[1]], decreasing = T), ]
    z
}

#' mat.write
#' 
#' Writes <x> as a <n>-separated file to <y>
#' @param x = any matrix/df
#' @param y = file intended to receive the output
#' @param n = the separator
#' @keywords mat.write
#' @export
#' @family mat

mat.write <- function (x, y, n = ",") 
{
    if (missing(y)) 
        y <- paste(machine("C:\\temp", "C:\\Users\\vik\\Documents\\temp"), 
            "write.csv", sep = "\\")
    write.table(x, y, sep = n, col.names = NA, quote = F)
    invisible()
}

#' mat.zScore
#' 
#' zScores <x> within groups <n> using weights <y>
#' @param x = a vector/matrix/data-frame
#' @param y = a 1/0 membership vector
#' @param n = a vector of groups (e.g. GSec)
#' @keywords mat.zScore
#' @export
#' @family mat

mat.zScore <- function (x, y, n) 
{
    h <- is.null(dim(x))
    if (h) {
        m <- length(x)
        z <- rep(NA, m)
    }
    else {
        m <- dim(x)[1]
        z <- matrix(NA, m, dim(x)[2], F, dimnames(x))
    }
    if (missing(y)) 
        y <- rep(1, m)
    if (missing(n)) 
        n <- rep(1, m)
    y <- is.element(y, 1)
    w <- !is.na(n)
    x <- data.frame(x, y, stringsAsFactors = F)
    x <- fcn.vec.grp(zScore.underlying, x[w, ], n[w])
    if (any(w) & h) {
        z[w] <- x
    }
    else {
        z[w, ] <- unlist(x)
    }
    z
}

#' mk.1dFloMo
#' 
#' Returns a flow variable with the same row space as <n>
#' @param x = a single YYYYMMDD
#' @param y = a string vector of variables to build with the last elements specifying the type of funds to use
#' @param n = list object containing the following items: a) classif - classif file b) conn - a connection, the output of odbcDriverConnect c) DB - any of StockFlows/China/Japan/CSI300/Energy
#' @keywords mk.1dFloMo
#' @export
#' @family mk

mk.1dFloMo <- function (x, y, n) 
{
    vbls <- sql.arguments(y)[["factor"]]
    x <- flowdate.lag(x, 2)
    if (any(y[1] == c("FloMo", "FloMoCB", "FloDollar", "FloDollarGross"))) {
        z <- sql.1dFloMo(x, y, n$DB, F)
    }
    else if (any(y[1] == c("FloTrendPMA", "FloDiffPMA", "FloDiff2PMA"))) {
        z <- sql.1dFloTrend(x, y, 1, n$DB, F)
    }
    else if (any(y[1] == c("FloTrend", "FloDiff", "FloDiff2"))) {
        z <- sql.1dFloTrend(x, y, 26, n$DB, F)
    }
    else if (any(y[1] == c("FloTrendCB", "FloDiffCB", "FloDiff2CB"))) {
        z <- sql.1dFloTrend(x, y, 26, n$DB, F)
    }
    else if (any(y[1] == c("ActWtTrend", "ActWtDiff", "ActWtDiff2"))) {
        z <- sql.1dActWtTrend(x, y, n$DB, F)
    }
    else if (any(y[1] == c("FwtdIn0", "FwtdEx0", "SwtdIn0", "SwtdEx0"))) {
        z <- sql.1dFloMoAggr(x, vbls, n$DB)
    }
    else if (any(y[1] == c("ION$", "ION%"))) {
        z <- sql.1dION(x, y, 26, n$DB)
    }
    else stop("Bad Argument")
    z <- sql.map.classif(z, vbls, n$conn, n$classif)
    z
}

#' mk.1mAllocMo
#' 
#' Returns a flow variable with the same row space as <n>
#' @param x = a single YYYYMM
#' @param y = a string vector of variables to build with the last elements specifying the type of funds to use
#' @param n = list object containing the following items: a) classif - classif file b) conn - a connection, the output of odbcDriverConnect c) DB - any of StockFlows/China/Japan/CSI300/Energy
#' @keywords mk.1mAllocMo
#' @export
#' @family mk

mk.1mAllocMo <- function (x, y, n) 
{
    vbls <- sql.arguments(y)[["factor"]]
    x <- yyyymm.lag(x, 1)
    if (y[1] == "AllocSkew") {
        z <- sql.1mAllocSkew(x, y, n$DB, F)
    }
    else if (y[1] == "Dispersion") {
        z <- sql.Dispersion(x, y, n$DB, F)
    }
    else if (any(y[1] == c("Herfindahl", "HerfindahlEq", "FundCt"))) {
        z <- sql.Herfindahl(x, y, n$DB, F)
    }
    else if (any(y[1] == c("AllocDInc", "AllocDDec", "AllocDAdd", 
        "AllocDRem"))) {
        z <- sql.1mAllocD(x, y, n$DB, F)
    }
    else if (any(y[1] == paste0("Alloc", c("Mo", "Trend", "Diff")))) {
        z <- sql.1mAllocMo(x, y, n$DB, F)
    }
    else {
        z <- sql.1mFloMo(x, y, n$DB, F)
    }
    z <- sql.map.classif(z, vbls, n$conn, n$classif)
    z
}

#' mk.ActWt
#' 
#' Active weight
#' @param x = a single YYYYMM
#' @param y = a string vector of names of the portfolio and benchmark
#' @param n = list object containing the following items: a) classif - classif file b) fldr - stock-flows folder
#' @keywords mk.ActWt
#' @export
#' @family mk

mk.ActWt <- function (x, y, n) 
{
    z <- fetch(y[1], x, 1, paste(n$fldr, "data", sep = "\\"), 
        n$classif)
    w <- fetch(y[2], yyyymm.lag(x), 1, paste(n$fldr, "data", 
        sep = "\\"), n$classif)
    z <- z - w
    z
}

#' mk.Alpha
#' 
#' makes Alpha
#' @param x = a single YYYYMM
#' @param y = a string vector, the first two elements of which are universe and group to zScore on and within. This is then followed by a list of variables which are, in turn, followed by weights to put on variables
#' @param n = list object containing the following items: a) classif - classif file b) fldr - stock-flows folder
#' @keywords mk.Alpha
#' @export
#' @family mk

mk.Alpha <- function (x, y, n) 
{
    m <- length(y)
    if (m%%2 != 0) 
        stop("Bad Arguments")
    univ <- y[1]
    grp.nm <- y[2]
    vbls <- y[seq(3, m/2 + 1)]
    wts <- renorm(as.numeric(y[seq(m/2 + 2, m)]))/100
    z <- fetch(vbls, x, 1, paste(n$fldr, "derived", sep = "\\"), 
        n$classif)
    grp <- n$classif[, grp.nm]
    mem <- fetch(univ, x, 1, paste0(n$fldr, "\\data"), n$classif)
    z <- mat.zScore(z, mem, grp)
    z <- zav(z)
    z <- as.matrix(z)
    z <- z %*% wts
    z <- as.numeric(z)
    z
}

#' mk.Alpha.daily
#' 
#' makes Alpha
#' @param x = a single YYYYMMDD
#' @param y = a string vector, the first two elements of which are universe and group to zScore on and within. This is then followed by a list of variables which are, in turn, followed by weights to put on variables and a logical vector indicating whether the variables are daily.
#' @param n = list object containing the following items: a) classif - classif file b) fldr - stock-flows folder
#' @keywords mk.Alpha.daily
#' @export
#' @family mk

mk.Alpha.daily <- function (x, y, n) 
{
    m <- length(y)
    if ((m - 2)%%3 != 0) 
        stop("Bad Arguments")
    univ <- y[1]
    grp.nm <- y[2]
    wts <- renorm(as.numeric(y[seq((m + 7)/3, (2 * m + 2)/3)]))/100
    vbls <- vec.named(as.logical(y[seq((2 * m + 5)/3, m)]), y[seq(3, 
        (m + 4)/3)])
    vbls[univ] <- F
    z <- matrix(NA, dim(n$classif)[1], length(vbls), F, list(dimnames(n$classif)[[1]], 
        names(vbls)))
    for (i in names(vbls)) {
        if (vbls[i]) 
            x.loc <- x
        else x.loc <- yyyymm.lag(yyyymmdd.to.yyyymm(x))
        if (i == univ) 
            sub.fldr <- "data"
        else sub.fldr <- "derived"
        z[, i] <- fetch(i, x.loc, 1, paste(n$fldr, sub.fldr, 
            sep = "\\"), n$classif)
    }
    z <- mat.ex.matrix(z)
    z$grp <- n$classif[, grp.nm]
    vbls <- setdiff(names(vbls), univ)
    z <- mat.zScore(z[, vbls], z[, univ], z$grp)
    z <- zav(z)
    z <- as.matrix(z)
    z <- z %*% wts
    z <- as.numeric(z)
    z
}

#' mk.avail
#' 
#' Returns leftmost non-NA variable
#' @param x = a single YYYYMM or YYYYMMDD
#' @param y = a string vector, the elements of which are: 1) folder to fetch data from 2+) variables to fetch
#' @param n = list object containing the following items: a) classif - classif file b) fldr - stock-flows folder
#' @keywords mk.avail
#' @export
#' @family mk

mk.avail <- function (x, y, n) 
{
    avail(fetch(y[-1], x, 1, paste(n$fldr, y[1], sep = "\\"), 
        n$classif))
}

#' mk.beta
#' 
#' Computes monthly beta versus relevant benchmark
#' @param x = a single YYYYMM
#' @param y = a string vector, the elements of which are: 1) benchmark (e.g. "Eafe") 2) number of trailing months of returns (e.g. 12)
#' @param n = list object containing the following items: a) classif - classif file b) fldr - stock-flows folder
#' @keywords mk.beta
#' @export
#' @family mk

mk.beta <- function (x, y, n) 
{
    m <- as.numeric(y[2])
    univ <- y[1]
    w <- paste(dir.parameters("csv"), "IndexReturns-Monthly.csv", 
        sep = "\\")
    w <- mat.read(w, ",")
    z <- fetch("Ret", x, m, paste(n$fldr, "data", sep = "\\"), 
        n$classif)
    vec <- map.rname(w, yyyymm.lag(x, m:1 - 1))[, univ]
    vec <- matrix(c(rep(1, m), vec), m, 2, F, list(1:m, c("Intercept", 
        univ)))
    z <- run.cs.reg(z, vec)
    z <- as.numeric(z[, univ])
    z
}

#' mk.EigenCentrality
#' 
#' Returns EigenCentrality with the same row space as <n>
#' @param x = a single YYYYMM
#' @param y = a string vector of variables to build with the last elements specifying the type of funds to use
#' @param n = list object containing the following items: a) classif - classif file b) conn - a connection, the output of odbcDriverConnect c) DB - any of StockFlows/China/Japan/CSI300/Energy
#' @keywords mk.EigenCentrality
#' @export
#' @family mk

mk.EigenCentrality <- function (x, y, n) 
{
    x <- yyyymm.lag(x, 1)
    x <- sql.declare("@floDt", "datetime", yyyymm.to.day(x))
    z <- sql.and(list(A = "ReportDate = @floDt", B = sql.in("t1.HSecurityId", 
        sql.RDSuniv(n[["DB"]]))))
    h <- c("Holdings t1", "inner join", "SecurityHistory id on id.HSecurityId = t1.HSecurityId")
    z <- c(x, sql.unbracket(sql.tbl("HFundId, SecurityId", h, 
        z, "HFundId, SecurityId")))
    z <- paste(z, collapse = "\n")
    x <- sql.query.underlying(z, n$conn, F)
    x <- x[is.element(x[, "SecurityId"], dimnames(n$classif)[[1]]), 
        ]
    x <- split(x[, "HFundId"], x[, "SecurityId"])
    w <- Reduce(union, x)
    x <- sapply(x, function(x) is.element(w, x))
    dimnames(x)[[1]] <- w
    x <- crossprod(x)
    w <- diag(x) > 9
    x <- x[w, w]
    w <- order(diag(x))
    x <- x[w, w]
    w <- floor(dim(x)[2]/50)
    w <- qtl.fast(diag(x), w)
    diag(x) <- NA
    z <- matrix(F, dim(x)[1], dim(x)[2], F, dimnames(x))
    for (j in 1:max(w)) {
        for (k in 1:max(w)) {
            y <- x[w == j, w == k]
            y <- as.numeric(unlist(y))
            y[!is.na(y)] <- is.element(qtl.fast(y[!is.na(y)], 
                20), 1)
            y[is.na(y)] <- F
            z[w == j, w == k] <- as.logical(y)
        }
    }
    x <- rep(1, dim(z)[1])
    x <- x/sqrt(sum(x^2))
    y <- z %*% x
    y <- y/sqrt(sum(y^2))
    while (sqrt(sum((y - x)^2)) > 1e-06) {
        x <- y
        y <- z %*% x
        y <- y/sqrt(sum(y^2))
    }
    z <- dim(z)[1] * y
    z <- as.numeric(map.rname(z, dimnames(n[["classif"]])[[1]]))
    z
}

#' mk.FloAlphaLt.Ctry
#' 
#' Monthly Country Flow Alpha
#' @param x = a single YYYYMM
#' @param y = an object name (preceded by #) or the path to a ".csv" file
#' @param n = list object containing the following items: a) classif - classif file
#' @keywords mk.FloAlphaLt.Ctry
#' @export
#' @family mk

mk.FloAlphaLt.Ctry <- function (x, y, n) 
{
    z <- read.prcRet(y)
    z <- unlist(z[yyyymmdd.ex.yyyymm(x), ])
    z <- map.rname(z, n$classif$CCode)
    z <- as.numeric(z)
    z
}

#' mk.Fragility
#' 
#' Generates the fragility measure set forth in Greenwood & Thesmar (2011) "Stock Price Fragility"
#' @param x = a single YYYYMM
#' @param y = vector containing the following items: a) folder - where the underlying data live b) trail - number of return periods to use c) factors - number of eigenvectors to use
#' @param n = list object containing the following items: a) classif - classif file b) fldr - stock-flows folder
#' @keywords mk.Fragility
#' @export
#' @family mk

mk.Fragility <- function (x, y, n) 
{
    trail <- as.numeric(y[2])
    eigen <- as.numeric(y[3])
    y <- y[1]
    x <- yyyymm.lag(x)
    h <- readRDS(paste(y, "FlowPct.r", sep = "\\"))
    h <- t(h[, yyyymm.lag(x, trail:1 - 1)])
    x <- readRDS(paste0(y, "\\HoldingValue-", x, ".r"))
    h <- h[, mat.count(h)[, 1] == trail & is.element(dimnames(h)[[2]], 
        dimnames(x)[[2]])]
    h <- principal.components.covar(h, eigen)
    x <- x[is.element(dimnames(x)[[1]], dimnames(n$classif)[[1]]), 
        is.element(dimnames(x)[[2]], dimnames(h)[[1]])]
    h <- h[is.element(dimnames(h)[[1]], dimnames(x)[[2]]), ]
    h <- h[, dimnames(h)[[1]]]
    h <- tcrossprod(h, x)
    z <- colSums(t(x) * h)
    x <- rowSums(x)^2
    z <- z/nonneg(x)
    z <- as.numeric(map.rname(z, dimnames(n$classif)[[1]]))
    z
}

#' mk.FundsMem
#' 
#' Returns a 1/0 vector with the same row space as <n> that is 1 whenever it has the right fund type as well as one-month forward return.
#' @param x = a single YYYYMM
#' @param y = a string vector, the elements of which are: 1) column to match in classif (e.g. "FundType") 2) column value (e.g. "E" or "B")
#' @param n = list object containing the following items: a) classif - classif file b) fldr - stock-flows folder
#' @keywords mk.FundsMem
#' @export
#' @family mk

mk.FundsMem <- function (x, y, n) 
{
    w <- is.element(n[, y[1]], y[2])
    z <- fetch("Ret", yyyymm.lag(x, -1), 1, paste(n$fldr, "data", 
        sep = "\\"), n$classif)
    z <- w & !is.na(z)
    z <- as.numeric(z)
    z
}

#' mk.HerdingLSV
#' 
#' Generates the herding measure set forth in LSV's 1991 paper "Do institutional investors destabilize stock prices?"
#' @param x = a single YYYYMM
#' @param y = a string vector, the elements of which are: 1) file to read from 2) variable to compute (LSV/DIR)
#' @param n = list object containing the following items: a) fldr - stock-flows folder
#' @keywords mk.HerdingLSV
#' @export
#' @family mk

mk.HerdingLSV <- function (x, y, n) 
{
    x <- paste0(n$fldr, "\\sqlDump\\", y[1], ".", x, ".r")
    x <- readRDS(x)[, c("B", "S", "expPctBuy")]
    u <- x[, "expPctBuy"]
    u <- u[!is.na(u)][1]
    n <- rowSums(x[, c("B", "S")])
    h <- vec.unique(nonneg(n))
    z <- rep(NA, length(n))
    for (i in h) {
        w <- is.element(n, i)
        if (y[2] == "LSV") {
            z[w] <- abs(x[w, "B"]/n[w] - u) - sum(abs(0:i/i - 
                u) * dbinom(0:i, i, u))
        }
        else if (y[2] == "DIR") {
            w2 <- w & x[, "B"] >= x[, "S"]
            if (any(w2)) 
                z[w2] <- pbinom(x[w2, "B"] - 1, i, u)
            if (any(w & !w2)) 
                z[w & !w2] <- -pbinom(x[w & !w2, "B"], i, u, 
                  F)
        }
        else {
            stop("Bad <y> argument!")
        }
    }
    z
}

#' mk.HoldValTot
#' 
#' Total Holding Value ($MM)
#' @param x = a single YYYYMM
#' @param y = one of All/Act/Pas/Etf/Mutual/JP/xJP/CBE
#' @param n = list object containing the following items: a) classif - classif file b) conn - a connection, the output of odbcDriverConnect
#' @keywords mk.HoldValTot
#' @export
#' @family mk

mk.HoldValTot <- function (x, y, n) 
{
    x <- sql.declare("@mo", "datetime", yyyymm.to.day(yyyymm.lag(x)))
    y <- list(A = sql.in("HFundId", sql.FundHistory("", y, T)), 
        B = "ReportDate = @mo")
    w <- "Holdings t1 inner join SecurityHistory t2 on t1.HSecurityId = t2.HSecurityId"
    z <- sql.tbl("SecurityId, AUM = sum(HoldingValue)", w, sql.and(y), 
        "SecurityId")
    z <- paste(c(x, sql.unbracket(z)), collapse = "\n")
    z <- sql.map.classif(z, "AUM", n$conn, n$classif)
    z
}

#' mk.isin
#' 
#' Looks up date from external file and maps on isin
#' @param x = a single YYYYMM or YYYYMMDD
#' @param y = a string vector, the elements of which are: 1) an object name (preceded by #) or the path to a ".csv" file 2) defaults to "isin"
#' @param n = list object containing the following items: a) classif - classif file
#' @keywords mk.isin
#' @export
#' @family mk

mk.isin <- function (x, y, n) 
{
    if (length(y) == 1) 
        y <- c(y, "isin")
    z <- read.prcRet(y[1])
    z <- vec.named(z[, x], dimnames(z)[[1]])
    z <- map.classif(z, n[["classif"]], y[2])
    z
}

#' mk.JensensAlpha.fund
#' 
#' Returns variable with the same row space as <n>
#' @param x = a single YYYYMM
#' @param y = number of months of trailing returns to use
#' @param n = list object containing the following items: a) classif - classif file b) fldr - stock-flows folder c) CATRETS - category returns
#' @keywords mk.JensensAlpha.fund
#' @export
#' @family mk

mk.JensensAlpha.fund <- function (x, y, n) 
{
    y <- as.numeric(y)
    fndR <- fetch("1mPrcMo", x, y, paste(n$fldr, "derived", sep = "\\"), 
        n$classif)
    fndR <- as.matrix(fndR)
    dimnames(fndR)[[2]] <- yyyymm.lag(x, y:1 - 1)
    catR <- n$CATRETS[, dimnames(fndR)[[2]]]
    w <- as.logical(apply(mat.to.obs(cbind(fndR, catR)), 1, min))
    z <- rep(NA, dim(fndR)[1])
    if (any(w)) {
        fndM <- rowMeans(fndR[w, ])
        catM <- rowMeans(catR[w, ])
        beta <- rowSums((catR[w, ] - catM) * (catR[w, ] - catM))
        beta <- rowSums((fndR[w, ] - fndM) * (catR[w, ] - catM))/nonneg(beta)
        z[w] <- fndM - beta * catM
    }
    z
}

#' mk.Mem
#' 
#' Returns a 1/0 membership vector
#' @param x = a single YYYYMM
#' @param y = a single FundId
#' @param n = list object containing the following items: a) classif - classif file b) conn - a connection, the output of odbcDriverConnect
#' @keywords mk.Mem
#' @export
#' @family mk

mk.Mem <- function (x, y, n) 
{
    y <- sql.and(list(A = sql.in("HFundId", sql.tbl("HFundId", 
        "FundHistory", paste("FundId =", y))), B = "ReportDate = @mo"))
    z <- c("Holdings t1", "inner join", "SecurityHistory t2 on t1.HSecurityId = t2.HSecurityId")
    z <- sql.unbracket(sql.tbl("SecurityId, Mem = sign(HoldingValue)", 
        z, y))
    z <- paste(c(sql.declare("@mo", "datetime", yyyymm.to.day(x)), 
        z), collapse = "\n")
    z <- sql.map.classif(z, "Mem", n$conn, n$classif)
    z <- zav(z)
    z
}

#' mk.SatoMem
#' 
#' Returns a 1/0 membership vector
#' @param x = an argument which is never used
#' @param y = path to a file containing isin's
#' @param n = list object containing the following items: a) classif - classif file
#' @keywords mk.SatoMem
#' @export
#' @family mk

mk.SatoMem <- function (x, y, n) 
{
    n <- n[["classif"]]
    y <- vec.read(y, F)
    z <- vec.to.list(intersect(c("isin", paste0("isin", 1:5)), 
        dimnames(n)[[2]]))
    fcn <- function(i) is.element(n[, i], y)
    z <- sapply(z, fcn)
    z <- as.numeric(apply(z, 1, max))
    z
}

#' mk.sqlDump
#' 
#' Returns variable with the same row space as <n>
#' @param x = a single YYYYMM
#' @param y = a string vector, the elements of which are: 1) file to read from 2) variable to read 3) lag (defaults to zero)
#' @param n = list object containing the following items: a) fldr - stock-flows folder
#' @keywords mk.sqlDump
#' @export
#' @family mk

mk.sqlDump <- function (x, y, n) 
{
    if (length(y) > 2) 
        x <- yyyymm.lag(x, as.numeric(y[3], F))
    z <- paste0(n$fldr, "\\sqlDump\\", y[1], ".", x, ".r")
    z <- readRDS(z)
    z <- z[, y[2]]
    z
}

#' mk.SRIMem
#' 
#' 1/0 depending on whether <y> or more SRI funds own the stock
#' @param x = a single YYYYMM
#' @param y = a positive integer
#' @param n = list object containing the following items: a) classif - classif file b) conn - a connection, the output of odbcDriverConnect c) DB - any of StockFlows/China/Japan/CSI300/Energy
#' @keywords mk.SRIMem
#' @export
#' @family mk

mk.SRIMem <- function (x, y, n) 
{
    x <- yyyymm.lag(x)
    x <- sql.SRI(x, n$DB)
    z <- sql.map.classif(x, "Ct", n$conn, n$classif)
    z <- as.numeric(!is.na(z) & z >= y)
    z
}

#' mk.vbl.chg
#' 
#' Makes the MoM change in the variable
#' @param x = a single YYYYMM
#' @param y = variable name
#' @param n = list object containing the following items: a) classif - classif file b) fldr - stock-flows folder
#' @keywords mk.vbl.chg
#' @export
#' @family mk

mk.vbl.chg <- function (x, y, n) 
{
    z <- fetch(y, x, 2, paste(n$fldr, "data", sep = "\\"), n$classif)
    z <- z[, 2] - z[, 1]
    z
}

#' mk.vbl.diff
#' 
#' Computes the difference of the two variables
#' @param x = a single YYYYMM
#' @param y = a string vector, the elements of which are the variables being subtracted and subtracted from respectively.
#' @param n = list object containing the following items: a) classif - classif file b) fldr - stock-flows folder
#' @keywords mk.vbl.diff
#' @export
#' @family mk

mk.vbl.diff <- function (x, y, n) 
{
    z <- fetch(y, x, 1, paste(n$fldr, "data", sep = "\\"), n$classif)
    z <- z[, 1] - z[, 2]
    z
}

#' mk.vbl.lag
#' 
#' Lags the variable
#' @param x = a single YYYYMM
#' @param y = a string vector, the elements of which are: 1) the variable to be lagged 2) the lag in months 3) the sub-folder in which the variable lives
#' @param n = list object containing the following items: a) classif - classif file b) fldr - stock-flows folder
#' @keywords mk.vbl.lag
#' @export
#' @family mk

mk.vbl.lag <- function (x, y, n) 
{
    x <- yyyymm.lag(x, as.numeric(y[2]))
    z <- fetch(y[1], x, 1, paste(n$fldr, y[3], sep = "\\"), n$classif)
    z
}

#' mk.vbl.max
#' 
#' Computes the maximum of the two variables
#' @param x = a single YYYYMM
#' @param y = a string vector of names of two variables
#' @param n = list object containing the following items: a) classif - classif file b) fldr - stock-flows folder
#' @keywords mk.vbl.max
#' @export
#' @family mk

mk.vbl.max <- function (x, y, n) 
{
    z <- fetch(y, x, 1, paste(n$fldr, "data", sep = "\\"), n$classif)
    z <- vec.max(z[, 1], z[, 2])
    z
}

#' mk.vbl.ratio
#' 
#' Computes the ratio of the two variables
#' @param x = a single YYYYMM
#' @param y = a string vector, the elements of which are the numerator and denominator respectively.
#' @param n = list object containing the following items: a) classif - classif file b) fldr - stock-flows folder
#' @keywords mk.vbl.ratio
#' @export
#' @family mk

mk.vbl.ratio <- function (x, y, n) 
{
    z <- fetch(y, x, 1, paste(n$fldr, "data", sep = "\\"), n$classif)
    z <- z[, 1]/nonneg(z[, 2])
    z
}

#' mk.vbl.scale
#' 
#' Linearly scales the first variable based on percentiles of the second. Top decile goes to scaling factor. Bot decile is fixed.
#' @param x = a single YYYYMM
#' @param y = a string vector, the elements of which are: 1) the variable to be scaled 2) the secondary variable 3) the universe within which to scale 4) the grouping within which to scale 5) scaling factor on top decile
#' @param n = list object containing the following items: a) classif - classif file b) fldr - stock-flows folder
#' @keywords mk.vbl.scale
#' @export
#' @family mk

mk.vbl.scale <- function (x, y, n) 
{
    w <- is.element(fetch(y[3], x, 1, paste(n$fldr, "data", sep = "\\"), 
        n$classif), 1)
    h <- n$classif[, y[4]]
    x <- fetch(y[1:2], x, 1, paste(n$fldr, "derived", sep = "\\"), 
        n$classif)
    y <- as.numeric(y[5])
    x[w, 2] <- 1 - fcn.vec.grp(ptile, x[w, 2], h[w])/100
    x[w, 2] <- ifelse(is.na(x[w, 2]), 0.5, x[w, 2])
    z <- rep(NA, dim(x)[1])
    z[w] <- (x[w, 2] * 5 * (1 - y)/4 + (9 * y - 1)/8) * x[w, 
        1]
    z
}

#' mk.vbl.sum
#' 
#' Computes the sum of the two variables
#' @param x = a single YYYYMM
#' @param y = a string vector, the elements of which are the variables to be added.
#' @param n = list object containing the following items: a) classif - classif file b) fldr - stock-flows folder
#' @keywords mk.vbl.sum
#' @export
#' @family mk

mk.vbl.sum <- function (x, y, n) 
{
    z <- fetch(y, x, 1, paste(n$fldr, "data", sep = "\\"), n$classif)
    z <- z[, 1] + z[, 2]
    z
}

#' mk.vbl.trail.fetch
#' 
#' compounded variable over some trailing window
#' @param x = a single YYYYMM or YYYYMMDD
#' @param y = a string vector, the elements of which are: 1) variable to fetch (e.g. "AllocMo"/"AllocDiff"/"AllocTrend"/"Ret") 2) number of trailing periods to use (e.g. "11") 3) number of periods to lag (defaults to "0") 4) sub-folder to fetch basic variable from (defaults to "derived") 5) T/F depending on whether the compounded variable is daily (defaults to F, matters only if <x> is monthly)
#' @param n = list object containing the following items: a) classif - classif file b) fldr - stock-flows folder
#' @keywords mk.vbl.trail.fetch
#' @export
#' @family mk

mk.vbl.trail.fetch <- function (x, y, n) 
{
    if (length(y) == 2) 
        y <- c(y, 0, "derived", F)
    if (length(y) == 3) 
        y <- c(y, "derived", F)
    if (length(y) == 4) 
        y <- c(y, F)
    m <- as.numeric(y[2])
    trail <- m + as.numeric(y[3])
    if (nchar(x) == 6 & as.logical(y[5])) 
        x <- yyyymmdd.ex.yyyymm(x)
    z <- fetch(y[1], x, trail, paste(n$fldr, y[4], sep = "\\"), 
        n$classif)
    z <- z[, 1:m]
    z
}

#' mk.vbl.trail.sum
#' 
#' compounded variable over some trailing window
#' @param x = a single YYYYMM or YYYYMMDD
#' @param y = a string vector, the elements of which are: 1) variable to fetch (e.g. "1mAllocMo"/"1dAllocDiff"/"1dAllocTrend"/"Ret") 2) T to sum or F to compound (e.g. "T") 3) number of trailing periods to use (e.g. "11") 4) number of periods to lag (defaults to "0") 5) sub-folder to fetch basic variable from (defaults to "derived") 6) T/F depending on whether the compounded variable is daily (defaults to F, matters only if <x> is monthly)
#' @param n = list object containing the following items: a) classif - classif file b) fldr - stock-flows folder
#' @keywords mk.vbl.trail.sum
#' @export
#' @family mk

mk.vbl.trail.sum <- function (x, y, n) 
{
    z <- mk.vbl.trail.fetch(x, y[-2], n)
    z <- compound.sf(z, as.logical(y[2]))
    z <- as.numeric(z)
    z
}

#' mk.vbl.vol
#' 
#' volatility of variable over some trailing window
#' @param x = a single YYYYMM or YYYYMMDD
#' @param y = a string vector, the elements of which are: 1) variable to fetch (e.g. "AllocMo"/"AllocDiff"/"AllocTrend"/"Ret") 2) number of trailing periods to use (e.g. "11") 3) number of periods to lag (defaults to "0") 4) sub-folder to fetch basic variable from (defaults to "derived") 5) T/F depending on whether the compounded variable is daily (defaults to F, matters only if <x> is monthly)
#' @param n = list object containing the following items: a) classif - classif file b) fldr - stock-flows folder
#' @keywords mk.vbl.vol
#' @export
#' @family mk

mk.vbl.vol <- function (x, y, n) 
{
    z <- mk.vbl.trail.fetch(x, y, n)
    z <- apply(z, 1, sd)
    z <- as.numeric(z)
    z
}

#' mk.Wt
#' 
#' Generates the SQL query to get monthly index weight for individual stocks
#' @param x = a single YYYYMM
#' @param y = FundId of the fund of interest
#' @param n = list object containing the following items: a) classif - classif file b) conn - a connection, the output of odbcDriverConnect
#' @keywords mk.Wt
#' @export
#' @family mk

mk.Wt <- function (x, y, n) 
{
    y <- sql.and(list(A = sql.in("t1.HFundId", sql.tbl("HFundId", 
        "FundHistory", paste("FundId =", y))), B = "ReportDate = @mo"))
    z <- c("Holdings t1", "inner join", sql.label(sql.MonthlyAssetsEnd("@mo"), 
        "t3"), "\ton t1.HFundId = t3.HFundId")
    z <- c(z, "inner join", "SecurityHistory t2 on t1.HSecurityId = t2.HSecurityId")
    z <- sql.unbracket(sql.tbl("SecurityId, Wt = 100 * HoldingValue/AssetsEnd", 
        z, y))
    z <- paste(c(sql.declare("@mo", "datetime", yyyymm.to.day(x)), 
        z), collapse = "\n")
    z <- sql.map.classif(z, "Wt", n$conn, n$classif)
    z <- zav(z)
    z
}

#' multi.asset
#' 
#' Reads in data relevant to the multi-asset strategy
#' @param x = a vector of paths to files
#' @keywords multi.asset
#' @export

multi.asset <- function (x) 
{
    n <- length(x)
    i <- 1
    z <- mat.read(x[i], ",")
    while (i < n) {
        i <- i + 1
        z <- mat.combine(intersect, z, mat.read(x[i], ","))
    }
    z
}

#' nameTo
#' 
#' pct name turnover between <x> and <y> if <x> is a vector or their rows otherwise
#' @param x = a logical vector/matrix/dataframe without NA's
#' @param y = a logical value, isomekic vector or isomekic isoplatic matrix/df without NA's
#' @keywords nameTo
#' @export

nameTo <- function (x, y) 
{
    fcn <- function(x, y) nameTo.underlying(sum(x), sum(y), sum(x & 
        y))
    z <- fcn.mat.num(fcn, x, y, F)
    z
}

#' nameTo.underlying
#' 
#' percent name turnover
#' @param x = a vector of counts over the current period
#' @param y = a vector of counts over the previous period
#' @param n = a vector of numbers of names common between current and previous periods
#' @keywords nameTo.underlying
#' @export

nameTo.underlying <- function (x, y, n) 
{
    100 - 100 * n/max(x, y)
}

#' nonneg
#' 
#' returns <x> if non-negative or NA otherwise
#' @param x = a vector/matrix/dataframe
#' @keywords nonneg
#' @export

nonneg <- function (x) 
{
    fcn <- function(x) ifelse(!is.na(x) & x > 0, x, NA)
    z <- fcn.mat.vec(fcn, x, , T)
    z
}

#' nyse.holidays
#' 
#' returns full day NYSE holidays from the year 2000 and after
#' @param x = either "yyyymmdd" or "reason"
#' @keywords nyse.holidays
#' @export

nyse.holidays <- function (x = "yyyymmdd") 
{
    z <- parameters("NyseHolidays")
    z <- scan(z, what = list(yyyymmdd = "", reason = ""), sep = "\t", 
        quote = "", quiet = T)
    z <- z[[x]]
    z
}

#' obj.diff
#' 
#' returns <x - y>
#' @param fcn = a function mapping objects to the number line
#' @param x = a vector
#' @param y = an isomekic isotypic vector
#' @keywords obj.diff
#' @export
#' @family obj

obj.diff <- function (fcn, x, y) 
{
    fcn(x) - fcn(y)
}

#' obj.lag
#' 
#' lags <x> by <y>
#' @param x = a vector of objects
#' @param y = an integer or vector of integers (if <x> and <y> are vectors then <y> isomekic)
#' @param n = a function mapping these objects to the number line
#' @param w = the bijective inverse of <n>
#' @keywords obj.lag
#' @export
#' @family obj

obj.lag <- function (x, y, n, w) 
{
    w(n(x) - y)
}

#' obj.seq
#' 
#' returns a sequence of objects between (and including) <x> and <y>
#' @param x = a SINGLE object
#' @param y = a SINGLE object of the same type as <x>
#' @param n = a function mapping these objects to the number line
#' @param w = the bijective inverse of <n>
#' @param h = a positive integer representing quantum size
#' @keywords obj.seq
#' @export
#' @family obj

obj.seq <- function (x, y, n, w, h) 
{
    x <- n(x)
    y <- n(y)
    if (x > y) 
        z <- -h
    else z <- h
    z <- seq(x, y, z)
    z <- w(z)
    z
}

#' optimal
#' 
#' Performance statistics of the optimal zero-cost unit-variance portfolio
#' @param x = a matrix/df of indicators
#' @param y = an isomekic isoplatic matrix/df containing associated forward returns
#' @param n = an isoplatic matrix/df of daily returns on which to train the risk model
#' @param w = a numeric vector, the elements of which are: 1) number of trailing days to train the risk model on 2) number of principal components (when 0 raw return matrix is used) 3) number of bins (when 0, indicator is ptiled) 4) forward return window in days or months depending on the row space of <x>
#' @keywords optimal
#' @export

optimal <- function (x, y, n, w) 
{
    period.count <- yyyy.periods.count(dimnames(x)[[1]])
    if (w[3] > 0) {
        x <- qtl.eq(x, w[3])
        x <- (1 + w[3] - 2 * x)/(w[3] - 1)
        x <- ifelse(!is.na(x) & abs(x) < 1, 0, x)
    }
    else x <- ptile(x)
    for (j in dimnames(x)[[1]]) {
        if (period.count == 260) 
            z <- j
        else z <- yyyymmdd.ex.yyyymm(j)
        z <- map.rname(n, flowdate.lag(z, w[1]:1 - 1))
        z <- z[, mat.count(z)[, 1] == w[1] & !is.na(x[j, ])]
        if (w[2] != 0) {
            z <- principal.components.covar(z, w[2])
        }
        else {
            z <- covar(z)/(1 - 1/w[1] + 1/w[1]^2)
        }
        opt <- solve(z) %*% map.rname(x[j, ], dimnames(z)[[2]])
        unity <- solve(z) %*% rep(1, dim(z)[1])
        opt <- opt - unity * as.numeric(crossprod(opt, z) %*% 
            unity)/as.numeric(crossprod(unity, z) %*% unity)
        opt <- opt[, 1]/sqrt(260 * (crossprod(opt, z) %*% opt)[1, 
            1])
        x[j, ] <- zav(map.rname(opt, dimnames(x)[[2]]))
    }
    x <- rowSums(x * zav(y))
    y <- period.count/w[4]
    z <- vec.named(, c("AnnMn", "AnnSd", "Sharpe", "HitRate"))
    z["AnnMn"] <- mean(x) * y
    z["AnnSd"] <- sd(x) * sqrt(y)
    z["Sharpe"] <- 100 * z["AnnMn"]/z["AnnSd"]
    z["HitRate"] <- mean(sign(x)) * 50
    z <- z/100
    z
}

#' parameters
#' 
#' returns full path to relevant parameters file
#' @param x = parameter type
#' @keywords parameters
#' @export

parameters <- function (x) 
{
    paste0(dir.parameters("parameters"), "\\", x, ".txt")
}

#' permutations
#' 
#' all possible permutations of <x>
#' @param x = a string vector without NA's
#' @keywords permutations
#' @export

permutations <- function (x) 
{
    h <- length(x)
    w <- 1:h
    z <- NULL
    while (!is.null(w)) {
        z <- c(z, paste(x[w], collapse = " "))
        w <- permutations.next(w)
    }
    z
}

#' permutations.next
#' 
#' returns the next permutation in dictionary order
#' @param x = a vector of integers 1:length(<x>) in some order
#' @keywords permutations.next
#' @export

permutations.next <- function (x) 
{
    z <- x
    n <- length(z)
    j <- n - 1
    while (z[j] > z[j + 1] & j > 1) j <- j - 1
    if (z[j] > z[j + 1]) {
        z <- NULL
    }
    else {
        k <- n
        while (z[j] > z[k]) k <- k - 1
        z <- vec.swap(z, j, k)
        r <- n
        s <- j + 1
        while (r > s) {
            z <- vec.swap(z, r, s)
            r <- r - 1
            s <- s + 1
        }
    }
    z
}

#' phone.list
#' 
#' Cat's phone list to the screen
#' @param x = number of desired columns
#' @keywords phone.list
#' @export

phone.list <- function (x = 4) 
{
    y <- parameters("PhoneList")
    y <- mat.read(y, "\t", NULL, F)
    y <- paste(y[, 1], y[, 2], sep = "\t")
    vec <- seq(0, length(y) - 1)
    z <- split(y, vec%%x)
    z[["sep"]] <- "\t\t"
    z <- do.call(paste, z)
    z <- paste(z, collapse = "\n")
    cat(z, "\n")
    invisible()
}

#' pivot
#' 
#' returns a table, the rows and columns of which are unique members of rowIdx and colIdx The cells of the table are the <fcn> of <x> whenever <y> and <n> take on their respective values
#' @param fcn = summary function to be applied
#' @param x = a numeric vector
#' @param y = a grouping vector
#' @param n = a grouping vector
#' @keywords pivot
#' @export

pivot <- function (fcn, x, y, n) 
{
    z <- aggregate(x = x, by = list(row = y, col = n), FUN = fcn)
    z <- mat.to.matrix(z)
    z
}

#' pivot.1d
#' 
#' returns a table, having the same column space of <x>, the rows of which are unique members of <grp> The cells of the table are the summ.fcn of <x> whenever <grp> takes on its respective value
#' @param fcn = summary function to be applied
#' @param x = a grouping vector
#' @param y = a numeric vector/matrix/data-frame
#' @keywords pivot.1d
#' @export

pivot.1d <- function (fcn, x, y) 
{
    z <- aggregate(x = y, by = list(grp = x), FUN = fcn)
    z <- mat.index(z)
    z
}

#' plurality.map
#' 
#' returns a map from <x> to <y>
#' @param x = a vector
#' @param y = an isomekic vector
#' @keywords plurality.map
#' @export

plurality.map <- function (x, y) 
{
    w <- !is.na(x) & !is.na(y)
    x <- x[w]
    y <- y[w]
    z <- vec.count(paste(x, y))
    z <- data.frame(txt.parse(names(z), " "), z)
    names(z) <- c("x", "map", "obs")
    z <- z[order(-z$obs), ]
    z <- z[!duplicated(z$x), ]
    z <- mat.index(z, "x")
    z$pct <- 100 * z$obs/map.rname(vec.count(x), dimnames(z)[[1]])
    z <- z[order(-z$pct), ]
    z
}

#' portfolio.beta
#' 
#' beta of <x> with respect to <y>
#' @param x = a numeric vector/matrix/data-frame
#' @param y = an isomekic numeric vector
#' @param n = T/F depending on whether all observations required
#' @keywords portfolio.beta
#' @export
#' @family portfolio

portfolio.beta <- function (x, y, n) 
{
    if (n) {
        z <- cov(x, y)/nonneg(cov(y, y))
    }
    else {
        w <- !is.na(x) & !is.na(y)
        if (sum(w) < 2) {
            z <- NA
        }
        else {
            z <- cov(x[w], y[w])/nonneg(cov(y[w], y[w]))
        }
    }
    z
}

#' portfolio.beta.wrapper
#' 
#' <n> day beta of columns of <x> with respect to benchmark <y>
#' @param x = a file of total return indices indexed so that time runs forward
#' @param y = the name of the benchmark w.r.t. which beta is to be computed (e.g. "ACWorld")
#' @param n = the window in days over which beta is to be computed
#' @keywords portfolio.beta.wrapper
#' @export
#' @family portfolio

portfolio.beta.wrapper <- function (x, y, n) 
{
    y <- map.rname(mat.read(paste(dir.parameters("csv"), "IndexReturns-Daily.csv", 
        sep = "\\")), dimnames(x)[[1]])[, y]
    y <- 100 * y/c(NA, y[-dim(x)[1]]) - 100
    z <- mat.ex.matrix(ret.ex.idx(x, 1, F, F, T))
    y <- vec.to.lags(y, n, T)
    z <- lapply(z, vec.to.lags, n, T)
    fcn <- function(x) x - apply(x, 1, mean)
    y <- fcn(y)
    z <- lapply(z, fcn)
    fcn <- function(x) rowSums(x * y)/rowSums(y * y)
    z <- sapply(z, fcn)
    dimnames(z)[[1]] <- dimnames(x)[[1]]
    z
}

#' portfolio.residual
#' 
#' residual of <x> after factoring out <y>
#' @param x = a numeric vector
#' @param y = an isomekic numeric vector
#' @keywords portfolio.residual
#' @export
#' @family portfolio

portfolio.residual <- function (x, y) 
{
    x - portfolio.beta(x, y, F) * y
}

#' position.floPct
#' 
#' Latest four-week flow percentage
#' @param x = strategy path
#' @param y = subset
#' @param n = last publication date
#' @keywords position.floPct
#' @export

position.floPct <- function (x, y, n) 
{
    x <- strategy.path(x, "daily")
    x <- multi.asset(x)
    if (all(n != dimnames(x)[[1]])) {
        cat("Date", n, "not recognized! No output will be published ...\n")
        z <- NULL
    }
    else {
        if (dimnames(x)[[1]][dim(x)[1]] != n) {
            cat("Warning: Latest data not being used! Proceeding regardless ...\n")
            x <- x[dimnames(x)[[1]] <= n, ]
        }
        if (missing(y)) 
            y <- dimnames(x)[[2]]
        else x <- mat.subset(x, y)
        z <- x[dim(x)[1] - 19:0, ]
        z <- vec.named(mat.compound(t(z)), y)
        z <- z[order(-z)]
        x <- x[dim(x)[1] - 19:0 - 5, ]
        x <- vec.named(mat.compound(t(x)), y)
        x <- map.rname(x, names(z))
        x <- rank(z) - rank(x)
        y <- vec.named(qtl.eq(z), names(z))
        y <- mat.ex.vec(y, z)
        z <- 0.01 * data.frame(z, 100 * x, y)
        dimnames(z)[[2]][1:2] <- c("Current", "RankChg")
    }
    z
}

#' principal.components
#' 
#' first <y> principal components
#' @param x = a matrix/df
#' @param y = number of principal components desired
#' @keywords principal.components
#' @export
#' @family principal

principal.components <- function (x, y = 2) 
{
    principal.components.underlying(x, y)$factor
}

#' principal.components.covar
#' 
#' covariance using first <y> components as factors
#' @param x = a matrix/df
#' @param y = number of principal components considered important
#' @keywords principal.components.covar
#' @export
#' @family principal

principal.components.covar <- function (x, y) 
{
    z <- principal.components.underlying(x, y)
    if (is.null(dim(z$factor))) {
        z <- tcrossprod(as.matrix(z$factor), as.matrix(z$exposure))
    }
    else {
        z <- tcrossprod(z$factor, z$exposure)
    }
    x <- x - z
    z <- crossprod(z)/(dim(x)[1] - 1)
    diag(z) <- diag(z) + colSums(x^2)/(dim(x)[1] - 1)
    z
}

#' principal.components.underlying
#' 
#' first <y> principal components
#' @param x = a matrix/df
#' @param y = number of principal components desired
#' @keywords principal.components.underlying
#' @export
#' @family principal

principal.components.underlying <- function (x, y) 
{
    x <- scale(x, scale = F)
    z <- svd(x)
    dimnames(z$u)[[1]] <- dimnames(x)[[1]]
    dimnames(z$v)[[1]] <- dimnames(x)[[2]]
    if (y < 1) 
        y <- scree(z$d)
    if (y == 1) {
        z <- list(factor = z$u[, 1] * z$d[1], exposure = z$v[, 
            1])
    }
    else {
        z <- list(factor = z$u[, 1:y] %*% diag(z$d[1:y]), exposure = z$v[, 
            1:y])
    }
    z
}

#' product
#' 
#' product of <x>
#' @param x = a numeric vector
#' @keywords product
#' @export

product <- function (x) 
{
    exp(sum(log(x)))
}

#' production.write
#' 
#' Writes production output if warranted
#' @param x = latest output
#' @param y = path to output
#' @keywords production.write
#' @export

production.write <- function (x, y) 
{
    proceed <- !is.null(x)
    if (proceed) {
        w <- mat.read(y, ",")
        proceed <- dim(w)[2] == dim(x)[[2]]
    }
    if (proceed) 
        proceed <- all(dimnames(w)[[2]] == dimnames(x)[[2]])
    if (proceed) 
        proceed <- dim(x)[1] > dim(w)[1]
    if (proceed) 
        proceed <- all(is.element(dimnames(w)[[1]], dimnames(x)[[1]]))
    if (proceed) 
        proceed <- all(colSums(mat.to.obs(x[dimnames(w)[[1]], 
            ])) == colSums(mat.to.obs(w)))
    if (proceed) 
        proceed <- all(unlist(zav(x[dimnames(w)[[1]], ]) == zav(w)))
    if (proceed) {
        mat.write(x, y)
        cat("Writing to", y, "...\n")
    }
    invisible()
}

#' pstudent2
#' 
#' Returns cumulative t-distribution with df = 2
#' @param x = any real number
#' @keywords pstudent2
#' @export

pstudent2 <- function (x) 
{
    return(pt(x, 2))
}

#' ptile
#' 
#' Converts <x>, if a vector, or the rows of <x> otherwise, to a ptile
#' @param x = a vector/matrix/data-frame
#' @keywords ptile
#' @export

ptile <- function (x) 
{
    fcn <- function(x) 100 * (rank(x) - 1)/(length(x) - 1)
    fcn2 <- function(x) fcn.nonNA(fcn, x)
    z <- fcn.mat.vec(fcn2, x, , F)
    z
}

#' publications.data
#' 
#' additional data is got and stale data removed
#' @param x = a vector of desired dates
#' @param y = SQL query OR a function taking a date as argument
#' @param n = folder where the data live
#' @param w = one of StockFlows/Regular/Quant
#' @keywords publications.data
#' @export

publications.data <- function (x, y, n, w) 
{
    h <- dir(n, "*.csv")
    if (length(h) > 0) 
        h <- h[!is.element(h, paste0(x, ".csv"))]
    if (length(h) > 0) {
        err.raise(h, F, paste("Removing the following from", 
            n))
        file.kill(paste(n, h, sep = "\\"))
    }
    h <- dir(n, "*.csv")
    if (length(h) > 0) {
        h <- txt.left(h, nchar(h) - nchar(".csv"))
        x <- x[!is.element(x, h)]
    }
    if (length(x) > 0) {
        cat("Updating", n, "for the following periods:\n")
        conn <- sql.connect(w)
        for (i in x) {
            cat("\t", i, "...\n")
            if (is.function(y)) {
                h <- y(i)
            }
            else {
                h <- txt.replace(y, "'YYYYMMDD'", paste0("'", 
                  i, "'"))
            }
            h <- sql.query.underlying(h, conn, F)
            mat.write(h, paste0(n, "\\", i, ".csv"), ",")
        }
        close(conn)
    }
    invisible()
}

#' publish.daily.last
#' 
#' last daily flow-publication date
#' @param x = a YYYYMMDD date
#' @keywords publish.daily.last
#' @export
#' @family publish

publish.daily.last <- function (x) 
{
    if (missing(x)) 
        x <- today()
    z <- flowdate.lag(x, 2)
    z
}

#' publish.date
#' 
#' the date on which country/sector allocations are published
#' @param x = a vector of yyyymm months
#' @keywords publish.date
#' @export
#' @family publish

publish.date <- function (x) 
{
    z <- yyyymm.lag(x, -1)
    z <- paste0(z, "23")
    w <- day.to.weekday(z)
    z[w == 0] <- paste0(txt.left(z[w == 0], 6), "24")
    z[w == 6] <- paste0(txt.left(z[w == 6], 6), "25")
    z
}

#' publish.monthly.last
#' 
#' date of last monthly publication
#' @param x = a YYYYMMDD date
#' @param y = calendar day in the next month when allocations are known (usually the 23rd)
#' @keywords publish.monthly.last
#' @export
#' @family publish

publish.monthly.last <- function (x, y = 23) 
{
    if (missing(x)) 
        x <- today()
    z <- yyyymmdd.lag(x, 1)
    z <- yyyymmdd.to.AllocMo(z, y)
    z <- yyyymm.to.day(z)
    z
}

#' publish.weekly.last
#' 
#' date of last weekly publication
#' @param x = a YYYYMMDD date
#' @keywords publish.weekly.last
#' @export
#' @family publish

publish.weekly.last <- function (x) 
{
    if (missing(x)) 
        x <- today()
    z <- as.numeric(day.to.weekday(x))
    if (any(z == 5:6)) 
        z <- z - 3
    else z <- z + 4
    z <- day.lag(x, z)
    z
}

#' qa.columns
#' 
#' columns expected in ftp file
#' @param x = M/W/D depending on whether flows are monthly/weekly/daily
#' @keywords qa.columns
#' @export
#' @family qa

qa.columns <- function (x) 
{
    if (any(x == c("M", "W", "D"))) {
        z <- c("ReportDate", "FundId", "Flow", "AssetsStart", 
            "AssetsEnd", "ForexChange", "PortfolioChange")
    }
    else if (x == "S") {
        z <- mat.read(parameters("classif-GSec"))$AllocTable[1:10]
        z <- c("ReportDate", "FundId", z)
    }
    else if (x == "I") {
        z <- mat.read(parameters("classif-GIgrp"))$AllocTable
        z <- c("ReportDate", "FundId", z)
    }
    else if (x == "C") {
        z <- mat.read(parameters("classif-ctry"), ",")
        z <- z$AllocTable[is.element(z$OnFTP, 1)]
        z <- c("ReportDate", "FundId", z)
    }
    else if (any(x == c("StockM", "StockD"))) {
        z <- c("ReportDate", "HSecurityId", "GeoId", "CalculatedStockFlow")
    }
    else if (any(x == c("FundCtM", "FundCtD"))) {
        z <- c("ReportDate", "HSecurityId", "GeoId", "FundCt")
    }
    else if (any(x == c("IOND", "IONM"))) {
        z <- c("ReportDate", "HSecurityId", "Inflow", "Outflow")
    }
    else if (any(x == c("FwtdEx0", "FwtdIn0", "SwtdEx0", "SwtdIn0"))) {
        z <- c("ReportDate", "HSecurityId", "GeoId", "AverageAllocation")
    }
    else if (x == "AllocD") {
        z <- c("ReportDate", "SecurityId", "AllocDA", "AllocDInc", 
            "AllocDDec", "AllocDAdd", "AllocDRem")
    }
    else if (x == "HoldSum") {
        z <- c("ReportDate", "HSecurityId", "GeoId", x)
    }
    else {
        z <- c("ReportDate", "HSecurityId", x)
    }
    z
}

#' qa.filter.map
#' 
#' maps to appropriate code on the R side
#' @param x = filter (e.g. Aggregate/Active/Passive/ETF/Mutual)
#' @keywords qa.filter.map
#' @export
#' @family qa

qa.filter.map <- function (x) 
{
    z <- c("All", "Act", "Pas", "Etf", "Mutual")
    names(z) <- c("Aggregate", "Active", "Passive", "ETF", "Mutual")
    x <- as.character(txt.parse(x, ","))
    z <- as.character(map.rname(z, x))
    z <- ifelse(is.na(z), x, z)
    z <- paste(z, collapse = ",")
    z
}

#' qa.flow
#' 
#' Compares flow file to data from Quant server
#' @param x = a YYYYMM month
#' @param y = M/W/D depending on whether flows are monthly/weekly/daily
#' @param n = T for fund or F for share-class level
#' @param w = fund filter (e.g. Aggregate/Active/Passive/ETF/Mutual)
#' @param h = a connection, the output of odbcDriverConnect
#' @param u = stock filter (e.g. All/China/Japan)
#' @keywords qa.flow
#' @export
#' @family qa

qa.flow <- function (x, y, n, w, h, u) 
{
    fldr <- "C:\\temp\\crap"
    isMacro <- any(y == c("M", "W", "D", "C", "I", "S"))
    isFactor <- all(y != c("HoldSum", "FundCtM", "FundCtD", "StockM", 
        "StockD", "FwtdEx0", "FwtdIn0", "SwtdEx0", "SwtdIn0")) & 
        !isMacro
    cols <- qa.columns(y)
    if (ftp.info(y, n, "frequency", w) == "D") {
        dts <- flowdate.ex.yyyymm(x, F)
    }
    else if (ftp.info(y, n, "frequency", w) == "W") {
        dts <- yyyymmdd.ex.yyyymm(x, F)
        dts <- dts[day.to.weekday(dts) == ifelse(dts >= "20010919", 
            3, 5)]
    }
    else if (ftp.info(y, n, "frequency", w) == "M") {
        dts <- yyyymm.to.day(x)
    }
    else if (ftp.info(y, n, "frequency", w) == "S") {
        dts <- x
    }
    else if (ftp.info(y, n, "frequency", w) == "Q") {
        dts <- yyyymm.to.day(yyyymm.lag(yyyymm.ex.qtr(x), 2:0))
    }
    else {
        stop("Bad frequency")
    }
    z <- c("isFTP", "goodFile", "badDts", "DupFunds", "isSQL", 
        "SQLxFTP", "FTPxSQL", "Common")
    if (any(y == c("M", "W", "D"))) {
        z <- c(z, txt.expand(c("sum", "max"), cols[-1][-1], "Abs", 
            T))
    }
    else if (any(y == c("StockM", "StockD"))) {
        z <- c(z, txt.expand(c("sum", "max"), "CalculatedStockFlow", 
            "", T))
    }
    else {
        z <- c(z, txt.expand(c("sum", "max"), "Turnover", "", 
            T))
    }
    z <- matrix(NA, length(dts), length(z), F, list(dts, z))
    ftpFile <- txt.replace(ftp.info(y, n, "ftp.path", w), "YYYYMM", 
        x)
    df <- qa.mat.read(ftpFile, fldr)
    z[, "isFTP"] <- as.numeric(!is.null(df))
    if (z[, "isFTP"][1] == 1) {
        z[, "goodFile"] <- as.numeric(all(is.element(cols, dimnames(df)[[2]])))
        if (!n & all(dimnames(df)[[2]] != "ShareId")) 
            z[, "goodFile"] <- 0
    }
    else {
        z[, "goodFile"] <- 0
    }
    if (z[, "goodFile"][1] == 1 & !isMacro) 
        df <- df[!is.na(df[, dim(df)[2]]), ]
    if (z[, "goodFile"][1] == 1 & substring(x, 5, 5) == "Q") {
        z[, "badDts"] <- as.numeric(any(yyyymm.to.qtr(yyyymmdd.to.yyyymm(dimnames(z)[[1]])) != 
            x))
    }
    else if (ftp.info(y, n, "frequency", w) == "S") {
        z[, "badDts"] <- as.numeric(any(dimnames(z)[[1]] != x))
    }
    else if (z[, "goodFile"][1] == 1) {
        z[, "badDts"] <- as.numeric(any(yyyymmdd.to.yyyymm(dimnames(z)[[1]]) != 
            x))
    }
    else {
        z[, "badDts"] <- 1
    }
    if (z[, "goodFile"][1] == 1) {
        for (j in dimnames(z)[[1]]) {
            if (n) {
                vec <- qa.index(df, isMacro, isFactor)
            }
            else {
                vec <- df[, "ShareId"]
            }
            vec <- vec[is.element(df[, "ReportDate"], j)]
            z[j, "DupFunds"] <- as.numeric(any(duplicated(vec)))
        }
        df <- df[, cols]
        if (dim(df)[1] > 0) {
            if (isMacro | isFactor) {
                df <- pivot.1d(sum, paste(df[, 1], df[, 2]), 
                  df[, cols[-1][-1]])
            }
            else {
                df <- pivot.1d(sum, paste(df[, 1], df[, 2], df[, 
                  3]), df[, cols[-1][-1][-1]])
            }
            if (is.null(dim(df))) {
                df <- data.frame(txt.parse(names(df), " "), df)
            }
            else {
                df <- data.frame(txt.parse(dimnames(df)[[1]], 
                  " "), df)
            }
            dimnames(df)[[2]] <- cols
            dimnames(df)[[1]] <- 1:dim(df)[1]
        }
    }
    else {
        z[, "DupFunds"] <- 1
    }
    for (j in dimnames(z)[[1]][is.element(z[, "goodFile"], 0)]) {
        z[j, "isSQL"] <- 0
        if (z[j, "goodFile"] == 1) {
            z[j, "FTPxSQL"] <- sum(is.element(df[, "ReportDate"], 
                j))
        }
        else {
            z[j, "FTPxSQL"] <- 0
        }
        z[j, "Common"] <- 0
        z[j, "SQLxFTP"] <- 0
        z[j, 9:dim(z)[2]] <- 0
    }
    if (any(is.element(z[, "goodFile"], 1)) & missing(h)) {
        h <- sql.connect(ftp.info(y, n, "connection", w))
        close.connection <- T
    }
    else {
        close.connection <- F
    }
    for (j in dimnames(z)[[1]][is.element(z[, "goodFile"], 1)]) {
        if (isMacro) {
            v <- ftp.sql.other(y, j, w)
        }
        else {
            v <- ftp.sql.factor(y, j, w, u)
        }
        v <- sql.query.underlying(v, h, F)
        z[j, "isSQL"] <- as.numeric(!is.null(dim(v)))
        if (z[j, "isSQL"] == 1) 
            z[j, "isSQL"] <- as.numeric(dim(v)[1] > 0)
        if (z[j, "isSQL"] == 1 & !isMacro) 
            v <- v[!is.na(v[, dim(v)[2]]), ]
        if (z[j, "isSQL"] == 1) {
            vec <- qa.index(df, isMacro, isFactor)[df[, "ReportDate"] == 
                j]
            dimnames(v)[[1]] <- qa.index(v, isMacro, isFactor)
            v <- v[, cols]
            z[j, "SQLxFTP"] <- sum(!is.element(dimnames(v)[[1]], 
                vec))
            z[j, "FTPxSQL"] <- sum(!is.element(vec, dimnames(v)[[1]]))
            z[j, "Common"] <- sum(is.element(vec, dimnames(v)[[1]]))
        }
        else {
            if (z[j, "goodFile"] == 1) {
                z[j, "FTPxSQL"] <- sum(is.element(df[, "ReportDate"], 
                  j))
            }
            else {
                z[j, "FTPxSQL"] <- 0
            }
            z[j, "Common"] <- 0
            z[j, "SQLxFTP"] <- 0
            z[j, 9:dim(z)[2]] <- 0
        }
        if (z[j, "Common"] > 100) {
            vec <- qa.index(df, isMacro, isFactor)
            vec <- is.element(df[, "ReportDate"], j) & is.element(vec, 
                dimnames(v)[[1]])
            if (isMacro) {
                v <- v[as.character(df[vec, "FundId"]), cols[-1][-1]]
                v <- abs(zav(df[vec, dimnames(v)[[2]]]) - zav(v))
            }
            else if (isFactor) {
                v <- v[as.character(qa.index(df, isMacro, isFactor)[vec]), 
                  cols[-1][-1]]
                if (any(y == c("IONM", "IOND", "AllocD"))) {
                  v <- abs(zav(df[vec, dimnames(v)[[2]]]) - zav(v))
                }
                else {
                  v <- abs(zav(df[vec, y]) - zav(v))
                }
            }
            else {
                v <- v[paste(df[vec, "HSecurityId"], df[vec, 
                  "GeoId"]), dim(v)[2]]
                v <- abs(zav(df[vec, dim(df)[2]]) - zav(v))
            }
            if (any(y == c("M", "W", "D"))) {
                z[j, paste("sum", dimnames(v)[[2]], sep = "Abs")] <- apply(v, 
                  2, sum)
                z[j, paste("max", dimnames(v)[[2]], sep = "Abs")] <- apply(v, 
                  2, max)
            }
            else if (!isMacro & !isFactor) {
                z[j, 9] <- sum(v)
                z[j, 10] <- max(v)
            }
            else {
                z[j, 9] <- sum(unlist(v))
                if (is.null(dim(v))) {
                  z[j, 10] <- max(v)
                }
                else {
                  z[j, 10] <- max(rowSums(v))
                }
            }
        }
        else {
            z[j, 9:dim(z)[2]] <- 0
        }
    }
    if (close.connection) 
        close(h)
    z
}

#' qa.index
#' 
#' unique index for <x>
#' @param x = data frame
#' @param y = T/F depending on whether <x> pertains to a macro strategy
#' @param n = T/F depending on whether <x> pertains to a factor
#' @keywords qa.index
#' @export
#' @family qa

qa.index <- function (x, y, n) 
{
    if (y) {
        z <- x[, "FundId"]
    }
    else if (n) {
        z <- c("HSecurityId", "SecurityId")
        w <- is.element(z, dimnames(x)[[2]])
        z <- x[, z[w & !duplicated(w)]]
    }
    else {
        z <- paste(x[, "HSecurityId"], x[, "GeoId"])
    }
    z
}

#' qa.mat.read
#' 
#' contents of <x> as a data frame
#' @param x = remote file on an ftp site (e.g. "/ftpdata/mystuff/foo.txt")
#' @param y = local folder (e.g. "C:\\\\temp")
#' @param n = ftp site (defaults to standard)
#' @param w = user id (defaults to standard)
#' @param h = password (defaults to standard)
#' @keywords qa.mat.read
#' @export
#' @family qa

qa.mat.read <- function (x, y, n, w, h) 
{
    local <- txt.left(x, 1) != "/"
    if (!local) {
        if (missing(n)) 
            n <- ftp.credential("ftp")
        if (missing(w)) 
            w <- ftp.credential("user")
        if (missing(h)) 
            h <- ftp.credential("pwd")
        ftp.get(x, y, n, w, h)
        x <- txt.right(x, nchar(x) - nchar(dirname(x)) - 1)
        x <- paste(y, x, sep = "\\")
    }
    z <- NULL
    if (file.exists(x)) {
        z <- mat.read(x, "\t", NULL)
        if (!local) {
            Sys.sleep(1)
            file.kill(x)
        }
        dimnames(z)[[2]][1] <- "ReportDate"
        z[, "ReportDate"] <- yyyymmdd.ex.txt(z[, "ReportDate"])
    }
    z
}

#' qa.secMenu
#' 
#' compares HSecurityId/ReportDate pairs in Security Menu versus Flow Dollar
#' @param x = a YYYYMM month
#' @param y = SecMenuM/SecMenuD
#' @param n = a connection, the output of odbcDriverConnect
#' @param w = stock filter (e.g. All/China/Japan)
#' @keywords qa.secMenu
#' @export
#' @family qa

qa.secMenu <- function (x, y, n, w) 
{
    fldr <- "C:\\temp\\crap"
    z <- vec.named(, c("isFTP", "isSQL", "DUP", "FTP", "SQL", 
        "FTPxSQL", "SQLxFTP"))
    secMenuFile <- txt.replace(ftp.info(y, T, "ftp.path", "Aggregate"), 
        "YYYYMM", x)
    secMenuFile <- qa.mat.read(secMenuFile, fldr)
    z["isFTP"] <- as.numeric(!is.null(secMenuFile))
    if (z["isFTP"] == 1) {
        floDolrFile <- ftp.sql.factor(txt.replace(y, "SecMenu", 
            "Stock"), yyyymm.to.day(x), "Aggregate", w)
        floDolrFile <- sql.query.underlying(floDolrFile, n, F)
        z["isSQL"] <- as.numeric(!is.null(floDolrFile))
    }
    if (z["isFTP"] == 1 & z["isSQL"] == 1) {
        x <- paste(floDolrFile[, "ReportDate"], floDolrFile[, 
            "HSecurityId"])
        x <- x[!duplicated(x)]
        y <- paste(secMenuFile[, "ReportDate"], secMenuFile[, 
            "HSecurityId"])
        z["DUP"] <- sum(duplicated(y))
        y <- y[!duplicated(y)]
    }
    if (z["isFTP"] == 1 & z["isSQL"] == 1) {
        z["FTP"] <- sum(length(y))
        z["SQL"] <- sum(length(x))
        z["FTPxSQL"] <- sum(!is.element(y, x))
        z["SQLxFTP"] <- sum(!is.element(x, y))
    }
    z
}

#' qtl
#' 
#' performs an equal-weight binning on <x> so that the members of <mem> are divided into <n> equal bins within each group <w>
#' @param x = a vector
#' @param y = number of desired bins
#' @param n = a weight vector
#' @param w = a vector of groups (e.g. GSec)
#' @keywords qtl
#' @export
#' @family qtl

qtl <- function (x, y, n, w) 
{
    if (missing(n)) 
        n <- rep(1, length(x))
    if (missing(w)) 
        w <- rep(1, length(x))
    h <- !is.na(x) & !is.na(w)
    x <- data.frame(x, n, stringsAsFactors = F)
    fcn <- function(x) qtl.single.grp(x, y)
    z <- rep(NA, length(h))
    if (any(h)) 
        z[h] <- fcn.vec.grp(fcn, x[h, ], w[h])
    z
}

#' qtl.eq
#' 
#' performs an equal-weight binning on <x> if <x> is a vector or the rows of <x> otherwise
#' @param x = a vector/matrix/data-frame
#' @param y = number of desired bins
#' @keywords qtl.eq
#' @export
#' @family qtl

qtl.eq <- function (x, y = 5) 
{
    fcn.mat.vec(qtl, x, y, F)
}

#' qtl.fast
#' 
#' performs a FAST equal-weight binning on <x>. Can't handle NAs.
#' @param x = a vector
#' @param y = number of desired bins
#' @keywords qtl.fast
#' @export
#' @family qtl

qtl.fast <- function (x, y = 5) 
{
    x <- order(-x)
    z <- ceiling((length(x)/y) * (0:y) + 0.5) - 1
    z <- z[-1] - z[-(y + 1)]
    z <- rep(1:y, z)[order(x)]
    z
}

#' qtl.single.grp
#' 
#' an equal-weight binning so that the first column of <x> is divided into <y> equal bins. Weights determined by the 2nd column
#' @param x = a two-column numeric data frame. No NA's in first two columns
#' @param y = number of desired bins
#' @keywords qtl.single.grp
#' @export
#' @family qtl

qtl.single.grp <- function (x, y) 
{
    n <- x[, 2]
    x <- x[, 1]
    z <- rep(NA, length(x))
    w <- !is.element(n, 0) & !is.na(n)
    w <- w & !is.na(x)
    if (any(w)) 
        z[w] <- qtl.underlying(x[w], n[w], y)
    w2 <- is.element(n, 0) | is.na(n)
    w2 <- w2 & !is.na(x)
    if (any(w) & any(w2)) 
        z[w2] <- qtl.zero.weight(x[w], z[w], x[w2], y)
    z
}

#' qtl.underlying
#' 
#' divided <x> into <n> equal bins of roughly equal weight (as defined by <y>)
#' @param x = a vector with no NA's
#' @param y = an isomekic vector lacking NA's or zeroes
#' @param n = a positive integer
#' @keywords qtl.underlying
#' @export
#' @family qtl

qtl.underlying <- function (x, y, n) 
{
    if (any(y < 0)) 
        stop("Can't handle negative weights!")
    if (n < 2) 
        stop("Can't do this either!")
    y <- y/sum(y)
    ord <- order(-x)
    x <- x[ord]
    y <- y[ord]
    if (all(y == y[1])) {
        h <- ceiling((length(x)/n) * (0:n) + 0.5) - 1
    }
    else {
        h <- 0
        for (i in 2:n - 1) h <- c(h, qtl.weighted(y, i/n))
        h <- c(h, length(x))
        h <- floor(h)
    }
    h <- h[-1] - h[-(n + 1)]
    z <- rep(1:n, h)
    z <- z[order(ord)]
    z
}

#' qtl.weighted
#' 
#' returns a number <z> so that the sum of x[1:z] is as close as possible to <y>.
#' @param x = an isomekic vector, lacking NA's or zeroes, that sums to unity
#' @param y = a number between zero and one
#' @keywords qtl.weighted
#' @export
#' @family qtl

qtl.weighted <- function (x, y) 
{
    beg <- 0
    end <- 1 + length(x)
    while (end > beg + 1) {
        z <- floor((beg + end)/2)
        if (sum(x[1:z]) - x[z]/2 >= y) 
            end <- z
        else beg <- z
    }
    z <- (beg + end)/2
    z
}

#' qtl.zero.weight
#' 
#' assigns the members of <x> to bins
#' @param x = a vector of variables
#' @param y = a corresponding vector of bin assignments
#' @param n = a vector of variables that are to be assigned to bins
#' @param w = number of bins to divide <x> into
#' @keywords qtl.zero.weight
#' @export
#' @family qtl

qtl.zero.weight <- function (x, y, n, w) 
{
    z <- approx(x, y, n, "constant", yleft = 1, yright = w)$y
    z <- ifelse(is.na(z), max(y), z)
    z
}

#' qtr.ex.int
#' 
#' returns a vector of <yyyymm> months
#' @param x = a vector of integers
#' @keywords qtr.ex.int
#' @export
#' @family qtr

qtr.ex.int <- function (x) 
{
    z <- (x - 1)%/%4
    x <- x - 4 * z
    z <- paste(z, x, sep = "Q")
    z <- txt.prepend(z, 6, 0)
    z
}

#' qtr.lag
#' 
#' lags <x> by <y> quarters
#' @param x = a vector of quarters
#' @param y = a number
#' @keywords qtr.lag
#' @export
#' @family qtr

qtr.lag <- function (x, y) 
{
    obj.lag(x, y, qtr.to.int, qtr.ex.int)
}

#' qtr.seq
#' 
#' returns a sequence of QTR between (and including) x and y
#' @param x = a QTR
#' @param y = a QTR
#' @param n = quantum size in QTR
#' @keywords qtr.seq
#' @export
#' @family qtr

qtr.seq <- function (x, y, n = 1) 
{
    obj.seq(x, y, qtr.to.int, qtr.ex.int, n)
}

#' qtr.to.int
#' 
#' returns a vector of integers
#' @param x = a vector of <qtr>
#' @keywords qtr.to.int
#' @export
#' @family qtr

qtr.to.int <- function (x) 
{
    z <- as.numeric(substring(x, 1, 4))
    z <- 4 * z + as.numeric(substring(x, 6, 6))
    z
}

#' read.EPFR
#' 
#' reads in the file
#' @param x = a path to a file written by the dev team
#' @keywords read.EPFR
#' @export
#' @family read

read.EPFR <- function (x) 
{
    z <- read.table(x, T, "\t", row.names = NULL, quote = "", 
        as.is = T, na.strings = txt.na(), comment.char = "")
    names(z)[1] <- "ReportDate"
    z$ReportDate <- yyyymmdd.ex.txt(z$ReportDate)
    z
}

#' read.prcRet
#' 
#' returns the contents of the file
#' @param x = an object name (preceded by #) or the path to a ".csv" file
#' @keywords read.prcRet
#' @export
#' @family read

read.prcRet <- function (x) 
{
    if (txt.left(x, 1) == "#") {
        z <- substring(x, 2, nchar(x))
        z <- get(z)
    }
    else z <- mat.read(x, ",")
    z
}

#' read.split.adj.prices
#' 
#' reads the split-adjusted prices that Matt provides
#' @param x = full path to a file that has the following columns: a) PRC containing raw prices b) CFACPR containing split factor that you divide PRC by c) CUSIP containing eight-digit cusip d) date containing date in yyyymmdd format
#' @param y = classif file
#' @keywords read.split.adj.prices
#' @export
#' @family read

read.split.adj.prices <- function (x, y) 
{
    z <- mat.read(x, ",", NULL)
    z$date <- as.character(z$date)
    z <- mat.subset(z, c("date", "CUSIP", "PRC", "CFACPR"))
    z$PRC <- z$PRC/nonneg(z$CFACPR)
    z <- mat.subset(z, c("CUSIP", "date", "PRC"))
    z <- mat.to.matrix(z)
    n <- paste0("isin", 1:3)
    w <- rep(y$CCode, length(n))
    n <- as.character(unlist(y[, n]))
    w <- is.element(w, c("US", "CA")) & nchar(n) == 12 & txt.left(n, 
        2) == w
    n <- n[w]
    n <- n[is.element(substring(n, 3, 10), dimnames(z)[[1]])]
    if (any(duplicated(substring(n, 3, 10)))) 
        stop("Haven't handled this")
    names(n) <- substring(n, 3, 10)
    z <- map.rname(z, names(n))
    dimnames(z)[[1]] <- as.character(n)
    z
}

#' refresh.predictors
#' 
#' refreshes the text file contains flows data from SQL
#' @param path = csv file containing the predictors
#' @param sql.query = query needed to get full history
#' @param sql.end.stub = last part of the query that goes after the date restriction
#' @param connection.type = one of StockFlows/Regular/Quant
#' @param ignore.data.changes = T/F depending on whether you want changes in data to be ignored
#' @param date.field = column corresponding to date in relevant sql table
#' @param publish.fcn = a function that returns the last complete publication period
#' @keywords refresh.predictors
#' @export
#' @family refresh

refresh.predictors <- function (path, sql.query, sql.end.stub, connection.type, ignore.data.changes, 
    date.field, publish.fcn) 
{
    last.date <- file.to.last(path)
    if (last.date < publish.fcn()) {
        z <- refresh.predictors.script(sql.query, sql.end.stub, 
            date.field, last.date)
        z <- sql.query(z, connection.type)
        x <- mat.read(path, ",")
        z <- refresh.predictors.append(x, z, ignore.data.changes, 
            F)
    }
    else {
        cat("There is no need to update the data ...\n")
        z <- NULL
    }
    z
}

#' refresh.predictors.append
#' 
#' Appends new to old data after performing checks
#' @param x = old data
#' @param y = new data
#' @param n = T/F depending on whether you want changes in data to be ignored
#' @param w = T/F depending on whether the data already have row names
#' @keywords refresh.predictors.append
#' @export
#' @family refresh

refresh.predictors.append <- function (x, y, n = F, w = F) 
{
    if (!w) 
        y <- mat.index(y)
    if (dim(y)[2] != dim(x)[2]) 
        stop("Problem 3")
    if (any(!is.element(dimnames(y)[[2]], dimnames(x)[[2]]))) 
        stop("Problem 4")
    z <- y[, dimnames(x)[[2]]]
    w <- is.element(dimnames(z)[[1]], dimnames(x)[[1]])
    if (sum(w) != 1) 
        stop("Problem 5")
    m <- data.frame(unlist(z[w, ]), unlist(x[dimnames(z)[[1]][w], 
        ]), stringsAsFactors = F)
    m <- correl(m[, 1], m[, 2])
    m <- zav(m)
    if (!n & m < 0.99) 
        stop("Problem: Correlation between new and old data is", 
            round(100 * m), "!")
    z <- rbind(x, z[!w, ])
    z <- z[order(dimnames(z)[[1]]), ]
    last.date <- dimnames(z)[[1]][dim(z)[1]]
    cat("Final data have", dim(z)[1], "rows ending at", last.date, 
        "...\n")
    z
}

#' refresh.predictors.daily
#' 
#' refreshes the text file contains flows data from SQL
#' @param x = csv file containing the predictors
#' @param y = query needed to get full history
#' @param n = last part of the query that goes after the date restriction
#' @param w = one of StockFlows/Regular/Quant
#' @param h = T/F depending on whether you want changes in data to be ignored
#' @keywords refresh.predictors.daily
#' @export
#' @family refresh

refresh.predictors.daily <- function (x, y, n, w, h = F) 
{
    refresh.predictors(x, y, n, w, h, "DayEnding", publish.daily.last)
}

#' refresh.predictors.monthly
#' 
#' refreshes the text file contains flows data from SQL
#' @param x = csv file containing the predictors
#' @param y = query needed to get full history
#' @param n = last part of the query that goes after the date restriction
#' @param w = one of StockFlows/Regular/Quant
#' @param h = when T, ignores the fact that data for the last row has changed
#' @keywords refresh.predictors.monthly
#' @export
#' @family refresh

refresh.predictors.monthly <- function (x, y, n, w, h) 
{
    refresh.predictors(x, y, n, w, h, "WeightDate", publish.monthly.last)
}

#' refresh.predictors.script
#' 
#' generates the SQL script to refresh predictors
#' @param x = query needed to get full history
#' @param y = last part of the query that goes after the date restriction
#' @param n = column corresponding to date in relevant sql table
#' @param w = last date for which you already have data
#' @keywords refresh.predictors.script
#' @export
#' @family refresh

refresh.predictors.script <- function (x, y, n, w) 
{
    if (nchar(y) > 0) {
        z <- paste0(txt.left(x, nchar(x) - nchar(y)), "where\n\t", 
            n, " >= '", w, "'\n", y)
    }
    else {
        z <- x
    }
    z
}

#' refresh.predictors.weekly
#' 
#' refreshes the text file contains flows data from SQL
#' @param x = csv file containing the predictors
#' @param y = query needed to get full history
#' @param n = last part of the query that goes after the date restriction
#' @param w = one of StockFlows/Regular/Quant
#' @param h = T/F depending on whether you want changes in data to be ignored
#' @keywords refresh.predictors.weekly
#' @export
#' @family refresh

refresh.predictors.weekly <- function (x, y, n, w, h = F) 
{
    refresh.predictors(x, y, n, w, h, "WeekEnding", publish.weekly.last)
}

#' renorm
#' 
#' renormalizes, so the absolute weights sum to 100, <x>, if a vector, or the rows of <x> otherwise
#' @param x = a numeric vector
#' @keywords renorm
#' @export

renorm <- function (x) 
{
    fcn <- function(x) 100 * x/excise.zeroes(sum(abs(x)))
    fcn2 <- function(x) fcn.nonNA(fcn, x)
    z <- fcn.mat.vec(fcn2, x, , F)
    z
}

#' ret.ex.idx
#' 
#' computes return
#' @param x = a file of total return indices indexed so that time runs forward
#' @param y = number of periods over which the return is computed
#' @param n = if T simple positional lagging is used. If F, yyyymm.lag is invoked.
#' @param w = if T the result is labelled by the beginning of the period, else by the end.
#' @param h = T/F depending on whether returns or spread changes are needed
#' @keywords ret.ex.idx
#' @export
#' @family ret

ret.ex.idx <- function (x, y, n, w, h) 
{
    z <- mat.lag(x, y, n)
    if (h) 
        z <- 100 * x/z - 100
    else z <- x - z
    if (w) 
        z <- mat.lag(z, -y, n)
    z
}

#' ret.idx.gaps.fix
#' 
#' replaces NA's by latest available total return index (i.e. zero return over that period)
#' @param x = a file of total return indices indexed by <yyyymmdd> dates so that time runs forward
#' @keywords ret.idx.gaps.fix
#' @export
#' @family ret

ret.idx.gaps.fix <- function (x) 
{
    fcn.mat.vec(fix.gaps, yyyymmdd.bulk(x), , T)
}

#' ret.to.idx
#' 
#' computes a total-return index
#' @param x = a file of total returns indexed so that time runs forward
#' @keywords ret.to.idx
#' @export
#' @family ret

ret.to.idx <- function (x) 
{
    if (is.null(dim(x))) {
        z <- x
        w <- !is.na(z)
        n <- find.data(w, T)
        m <- find.data(w, F)
        if (n > 1) 
            n <- n - 1
        z[n] <- 100
        while (n < m) {
            n <- n + 1
            z[n] <- (1 + zav(z[n])/100) * z[n - 1]
        }
    }
    else {
        z <- fcn.mat.vec(ret.to.idx, x, , T)
    }
    z
}

#' ret.to.log
#' 
#' converts to logarithmic return
#' @param x = a vector of returns
#' @keywords ret.to.log
#' @export
#' @family ret

ret.to.log <- function (x) 
{
    log(1 + x/100)
}

#' rgb.diff
#' 
#' distance between RGB colours <x> and <y>
#' @param x = a vector of length three containing numbers between 0 and 256
#' @param y = a vector of length three containing numbers between 0 and 256
#' @keywords rgb.diff
#' @export

rgb.diff <- function (x, y) 
{
    z <- (x[1] + y[1])/2
    z <- c(z/256, 2, 1 - z/256) + 2
    z <- sqrt(sum(z * (x - y)^2))
    z
}

#' rrw
#' 
#' regression results
#' @param prdBeg = a first-return date in yyyymm format representing the first month of the backtest
#' @param prdEnd = a first-return date in yyyymm format representing the last month of the backtest
#' @param vbls = vector of variables against which return is to be regressed
#' @param univ = universe (e.g. "R1Mem")
#' @param grp.nm = neutrality group (e.g. "GSec")
#' @param ret.nm = return variable (e.g. "Ret")
#' @param fldr = stock-flows folder
#' @param orth.factor = factor to orthogonalize all variables to (e.g. "PrcMo")
#' @param classif = classif file
#' @keywords rrw
#' @export
#' @family rrw

rrw <- function (prdBeg, prdEnd, vbls, univ, grp.nm, ret.nm, fldr, orth.factor = NULL, 
    classif) 
{
    dts <- yyyymm.seq(prdBeg, prdEnd)
    df <- NULL
    for (i in dts) {
        if (txt.right(i, 2) == "01") 
            cat("\n", i, "")
        else cat(txt.right(i, 2), "")
        x <- rrw.underlying(i, vbls, univ, grp.nm, ret.nm, fldr, 
            orth.factor, classif)
        x <- mat.subset(x, c("ret", vbls))
        dimnames(x)[[1]] <- paste(i, dimnames(x)[[1]])
        if (is.null(df)) 
            df <- x
        else df <- rbind(df, x)
    }
    cat("\n")
    z <- list(value = map.rname(rrw.factors(df), vbls), corr = correl(df), 
        data = df)
    z
}

#' rrw.factors
#' 
#' Returns the t-values of factors that best predict return
#' @param x = a data frame, the first column of which has returns
#' @keywords rrw.factors
#' @export
#' @family rrw

rrw.factors <- function (x) 
{
    y <- dimnames(x)[[2]]
    names(y) <- fcn.vec.num(col.ex.int, 1:dim(x)[2])
    dimnames(x)[[2]] <- names(y)
    z <- summary(lm(txt.regr(dimnames(x)[[2]]), x))$coeff[-1, 
        "t value"]
    while (any(z < 0)) {
        x <- x[, !is.element(dimnames(x)[[2]], names(z)[order(z)][1])]
        z <- summary(lm(txt.regr(dimnames(x)[[2]]), x))$coeff[, 
            "t value"][-1]
    }
    names(z) <- map.rname(y, names(z))
    z
}

#' rrw.underlying
#' 
#' Runs regressions
#' @param prd = a first-return date in yyyymm format representing the return period of interest
#' @param vbls = vector of variables against which return is to be regressed
#' @param univ = universe (e.g. "R1Mem")
#' @param grp.nm = neutrality group (e.g. "GSec")
#' @param ret.nm = return variable (e.g. "Ret")
#' @param fldr = parent directory containing derived/data
#' @param orth.factor = factor to orthogonalize all variables to (e.g. "PrcMo")
#' @param classif = classif file
#' @keywords rrw.underlying
#' @export
#' @family rrw

rrw.underlying <- function (prd, vbls, univ, grp.nm, ret.nm, fldr, orth.factor, 
    classif) 
{
    z <- fetch(c(vbls, orth.factor), yyyymm.lag(prd, 1), 1, paste0(fldr, 
        "\\derived"), classif)
    grp <- classif[, grp.nm]
    mem <- fetch(univ, yyyymm.lag(prd, 1), 1, paste0(fldr, "\\data"), 
        classif)
    z <- mat.ex.matrix(mat.zScore(z, mem, grp))
    z$grp <- grp
    z$mem <- mem
    z$ret <- fetch(ret.nm, prd, 1, paste0(fldr, "\\data"), classif)
    z <- mat.last.to.first(z)
    z <- z[is.element(z$mem, 1) & !is.na(z$grp) & !is.na(z$ret), 
        ]
    if (!is.null(orth.factor)) {
        z[, orth.factor] <- zav(z[, orth.factor])
        for (j in vbls) {
            w <- !is.na(z[, j])
            z[w, j] <- as.numeric(summary(lm(txt.regr(c(j, orth.factor)), 
                z[w, ]))$residuals)
            z[, j] <- mat.zScore(z[, j], z$mem, z$grp)
        }
    }
    w <- apply(mat.to.obs(z[, c(vbls, "ret")]), 1, max) > 0
    z <- mat.ex.matrix(zav(z[w, ]))
    z$ret <- z$ret - mean(z$ret)
    z
}

#' run.cs.reg
#' 
#' regresses each row of <x> on design matrix <y>
#' @param x = a matrix of n columns (usually stocks go down and returns go across)
#' @param y = a matrix of n rows (whatever vectors you're regressing on)
#' @keywords run.cs.reg
#' @export

run.cs.reg <- function (x, y) 
{
    y <- as.matrix(y)
    z <- tcrossprod(as.matrix(x), tcrossprod(solve(crossprod(y)), 
        y))
    z
}

#' scree
#' 
#' number of eigenvectors to use (by looking at the "kink")
#' @param x = a decreasing numerical vector
#' @keywords scree
#' @export

scree <- function (x) 
{
    n <- length(x)
    y <- x[1]/n
    x <- x[-n] - x[-1]
    x <- 1.5 * pi - atan(x[1 - n]/y) - atan(y/x[-1])
    z <- (3:n - 1)[order(x)][1]
    z
}

#' seconds.sho
#' 
#' time elapsed since <x> in hh:mm:ss format
#' @param x = a number
#' @keywords seconds.sho
#' @export

seconds.sho <- function (x) 
{
    z <- proc.time()[["elapsed"]] - x
    z <- round(z)
    z <- base.ex.int(z, 60)
    n <- length(z)
    if (n > 3) {
        z <- c(base.to.int(z[3:n - 2], 60), z[n - 1:0])
        n <- 3
    }
    while (n < 3) {
        z <- c(0, z)
        n <- n + 1
    }
    z <- paste(txt.right(100 + z, 2), collapse = ":")
    z
}

#' sf
#' 
#' runs a stock-flows simulation
#' @param prdBeg = first-return date in YYYYMM
#' @param prdEnd = first-return date in YYYYMM after <prdBeg>
#' @param vbl.nm = variable
#' @param univ = membership (e.g. "EafeMem" or c("GemMem", 1))
#' @param grp.nm = group within which binning is to be performed
#' @param ret.nm = return variable
#' @param trails = number of trailing periods to compound/sum over
#' @param sum.flows = T/F depending on whether you want flows summed or compounded.
#' @param fldr = data folder
#' @param dly.vbl = if T then a daily predictor is assumed else a monthly one
#' @param vbl.lag = lags by <vbl.lag> weekdays or months depending on whether <dly.vbl> is true.
#' @param nBins = number of bins
#' @param reverse.vbl = T/F depending on whether you want the variable reversed
#' @param geom.comp = T/F depending on whether you want bin excess returns summarized geometrically or arithmetically
#' @param retHz = forward return horizon in months
#' @param classif = classif file
#' @keywords sf
#' @export
#' @family sf

sf <- function (prdBeg, prdEnd, vbl.nm, univ, grp.nm, ret.nm, trails, 
    sum.flows, fldr, dly.vbl = T, vbl.lag = 0, nBins = 5, reverse.vbl = F, 
    geom.comp = F, retHz = 1, classif) 
{
    n.trail <- length(trails)
    fcn <- ifelse(geom.comp, "bbk.bin.rets.geom.summ", "bbk.bin.rets.summ")
    fcn <- get(fcn)
    fcn.loc <- function(x) {
        fcn(x, 12/retHz)
    }
    z <- list()
    for (j in 1:n.trail) {
        cat(trails[j], "")
        if (j%%10 == 0) 
            cat("\n")
        x <- sf.single.bsim(prdBeg, prdEnd, vbl.nm, univ, grp.nm, 
            ret.nm, fldr, dly.vbl, trails[j], sum.flows, vbl.lag, 
            T, nBins, reverse.vbl, retHz, classif)
        x <- t(map.rname(t(x), c(dimnames(x)[[2]], "TxB")))
        x[, "TxB"] <- x[, "Q1"] - x[, paste0("Q", nBins)]
        x <- mat.ex.matrix(x)
        z[[as.character(trails[j])]] <- summ.multi(fcn.loc, x, 
            retHz)
    }
    z <- simplify2array(z)
    cat("\n")
    z
}

#' sf.bin.nms
#' 
#' returns bin names
#' @param x = number of bins
#' @param y = T/F depending on whether you want universe returns returned
#' @keywords sf.bin.nms
#' @export
#' @family sf

sf.bin.nms <- function (x, y) 
{
    z <- c(1:x, "na")
    z <- z[order(c(1:x, x/2 + 0.25))]
    z <- paste0("Q", z)
    if (y) 
        z <- c(z, "uRet")
    z
}

#' sf.daily
#' 
#' runs stock-flows simulation
#' @param prdBeg = first-return date in YYYYMMDD
#' @param prdEnd = first-return date in YYYYMMDD (must postdate <prdBeg>)
#' @param vbl.nm = variable
#' @param univ = membership (e.g. "EafeMem" or c("GemMem", 1))
#' @param grp.nm = group within which binning is to be performed
#' @param ret.nm = return variable
#' @param trail = number of trailing periods to compound/sum over
#' @param sum.flows = T/F depending on whether you want flows summed or compounded.
#' @param fldr = data folder
#' @param vbl.lag = lags by <vbl.lag> weekdays or months depending on whether <dly.vbl> is true.
#' @param dly.vbl = whether the predictor is daily or monthly
#' @param retHz = forward return horizon in days
#' @param classif = classif file
#' @keywords sf.daily
#' @export
#' @family sf

sf.daily <- function (prdBeg, prdEnd, vbl.nm, univ, grp.nm, ret.nm, trail, 
    sum.flows, fldr, vbl.lag, dly.vbl, retHz, classif) 
{
    grp <- classif[, grp.nm]
    dts <- yyyymm.seq(prdBeg, prdEnd)
    dts <- dts[!is.element(dts, nyse.holidays())]
    m <- length(dts)
    dts <- vec.named(c(yyyymmdd.diff(dts[seq(retHz + 1, m)], 
        dts[seq(1, m - retHz)]), rep(retHz, retHz)), dts)
    x <- sf.bin.nms(5, F)
    x <- matrix(NA, m, length(x), F, list(names(dts), x))
    for (i in 1:dim(x)[1]) {
        if (i%%10 == 0) 
            cat(dimnames(x)[[1]][i], "")
        if (i%%100 == 0) 
            cat("\n")
        i.dt <- dimnames(x)[[1]][i]
        vec <- sf.underlying(vbl.nm, univ, ret.nm, i.dt, trail, 
            sum.flows, grp, dly.vbl, 5, fldr, vbl.lag, F, F, 
            dts[i.dt], classif)
        vec <- map.rname(vec, dimnames(x)[[2]])
        x[i.dt, ] <- as.numeric(vec)
    }
    cat("\n")
    x <- mat.ex.matrix(x)
    x$TxB <- x[, 1] - x[, dim(x)[2]]
    x <- mat.last.to.first(x)
    fcn <- function(x) bbk.bin.rets.summ(x, 250/retHz)
    z <- summ.multi(fcn, x, retHz)
    z
}

#' sf.detail
#' 
#' runs a stock-flows simulation
#' @param prdBeg = first-return date in YYYYMM
#' @param prdEnd = first-return date in YYYYMM after <prdBeg>
#' @param vbl.nm = variable
#' @param univ = membership (e.g. "EafeMem" or c("GemMem", 1))
#' @param grp.nm = group within which binning is to be performed
#' @param ret.nm = return variable
#' @param trail = number of trailing periods to compound/sum over
#' @param sum.flows = T/F depending on whether you want flows summed or compounded.
#' @param fldr = data folder
#' @param dly.vbl = if T then a daily predictor is assumed else a monthly one
#' @param vbl.lag = lags by <vbl.lag> weekdays or months depending on whether <dly.vbl> is true.
#' @param nBins = number of bins
#' @param reverse.vbl = T/F depending on whether you want the variable reversed
#' @param classif = classif file
#' @keywords sf.detail
#' @export
#' @family sf

sf.detail <- function (prdBeg, prdEnd, vbl.nm, univ, grp.nm, ret.nm, trail, 
    sum.flows, fldr, dly.vbl = T, vbl.lag = 0, nBins = 5, reverse.vbl = F, 
    classif) 
{
    cat(vbl.nm, univ[1], "...\n")
    x <- sf.single.bsim(prdBeg, prdEnd, vbl.nm, univ, grp.nm, 
        ret.nm, fldr, dly.vbl, trail, sum.flows, vbl.lag, T, 
        nBins, reverse.vbl, 1, classif)
    x <- t(map.rname(t(x), c(dimnames(x)[[2]], "TxB")))
    x[, "TxB"] <- x[, "Q1"] - x[, paste0("Q", nBins)]
    x <- mat.ex.matrix(x)
    z <- bbk.bin.rets.summ(x, 12)
    z.ann <- t(bbk.bin.rets.prd.summ(bbk.bin.rets.summ, x, txt.left(dimnames(x)[[1]], 
        4), 12)["AnnMn", , ])
    z <- list(summ = z, annSumm = z.ann)
    z
}

#' sf.single.bsim
#' 
#' runs a single quintile simulation
#' @param prdBeg = first-return date in YYYYMM
#' @param prdEnd = first-return date in YYYYMM after <prdBeg>
#' @param vbl.nm = variable
#' @param univ = membership (e.g. "EafeMem" or c("GemMem", 1))
#' @param grp.nm = group within which binning is to be performed
#' @param ret.nm = return variable
#' @param fldr = data folder
#' @param dly.vbl = T/F depending on whether the variable used is daily or monthly
#' @param trail = number of trailing periods to compound/sum over
#' @param sum.flows = if T, flows get summed. Otherwise they get compounded.
#' @param vbl.lag = lags by <vbl.lag> weekdays or months depending on whether <dly.vbl> is true.
#' @param uRet = T/F depending on whether the equal-weight universe return is desired
#' @param nBins = number of bins
#' @param reverse.vbl = T/F depending on whether you want the variable reversed
#' @param retHz = forward return horizon in months
#' @param classif = classif file
#' @keywords sf.single.bsim
#' @export
#' @family sf

sf.single.bsim <- function (prdBeg, prdEnd, vbl.nm, univ, grp.nm, ret.nm, fldr, 
    dly.vbl = F, trail = 1, sum.flows = T, vbl.lag = 0, uRet = F, 
    nBins = 5, reverse.vbl = F, retHz = 1, classif) 
{
    grp <- classif[, grp.nm]
    z <- sf.bin.nms(nBins, uRet)
    dts <- yyyymm.seq(prdBeg, prdEnd)
    z <- matrix(NA, length(dts), length(z), F, list(dts, z))
    for (i in dimnames(z)[[1]]) {
        vec <- sf.underlying(vbl.nm, univ, ret.nm, i, trail, 
            sum.flows, grp, dly.vbl, nBins, fldr, vbl.lag, uRet, 
            reverse.vbl, retHz, classif)
        z[i, ] <- map.rname(vec, dimnames(z)[[2]])
    }
    z
}

#' sf.subset
#' 
#' Returns a 1/0 mem vector
#' @param x = membership (e.g. "EafeMem" or c("GemMem", 1))
#' @param y = a YYYYMM or YYYYMMDD
#' @param n = folder in which to find the data
#' @param w = classif file
#' @keywords sf.subset
#' @export
#' @family sf

sf.subset <- function (x, y, n, w) 
{
    m <- length(x)
    if (m == 1) 
        x <- c(x, 1)
    z <- y
    if (nchar(y) == 8) 
        z <- yyyymmdd.to.yyyymm(z)
    z <- yyyymm.lag(z, 1)
    z <- fetch(x[1], z, 1, paste(n, "data", sep = "\\"), w)
    z <- is.element(z, x[2])
    if (m > 2) 
        z <- z & is.element(w[, x[3]], x[4])
    z <- as.numeric(z)
    z
}

#' sf.underlying
#' 
#' Creates bin excess returns for a single period
#' @param vbl.nm = variable
#' @param univ = membership (e.g. "EafeMem" or c("GemMem", 1))
#' @param ret.nm = return variable
#' @param ret.prd = the period for which you want returns
#' @param trail = number of trailing periods to compound/sum over
#' @param sum.flows = if T, flows get summed. Otherwise they get compounded.
#' @param grp = group within which binning is to be performed
#' @param dly.vbl = if T then a daily predictor is assumed else a monthly one
#' @param nBins = number of bins
#' @param fldr = data folder
#' @param vbl.lag = lags by <vbl.lag> weekdays or months depending on whether <dly.vbl> is true.
#' @param uRet = T/F depending on whether the equal-weight universe return is desired
#' @param reverse.vbl = T/F depending on whether you want the variable reversed
#' @param retHz = forward return horizon in months
#' @param classif = classif file
#' @keywords sf.underlying
#' @export
#' @family sf

sf.underlying <- function (vbl.nm, univ, ret.nm, ret.prd, trail, sum.flows, grp, 
    dly.vbl, nBins, fldr, vbl.lag, uRet = F, reverse.vbl = F, 
    retHz = 1, classif) 
{
    x <- sf.underlying.data(vbl.nm, univ, ret.nm, ret.prd, trail, 
        sum.flows, grp, dly.vbl, nBins, fldr, vbl.lag, reverse.vbl, 
        retHz, classif)
    z <- sf.underlying.summ(x$bin, x$ret, x$mem, nBins, uRet)
    z
}

#' sf.underlying.data
#' 
#' Gets data needed to back-test a single period
#' @param vbl.nm = variable
#' @param univ = membership (e.g. "EafeMem" or c("GemMem", 1))
#' @param ret.nm = return variable
#' @param ret.prd = the period for which you want returns
#' @param trail = number of trailing periods to compound/sum over
#' @param sum.flows = if T, flows get summed. Otherwise they get compounded.
#' @param grp = group within which binning is to be performed
#' @param dly.vbl = if T then a daily predictor is assumed else a monthly one
#' @param nBins = number of bins
#' @param fldr = data folder
#' @param vbl.lag = lags by <vbl.lag> weekdays or months depending on whether <dly.vbl> is true.
#' @param reverse.vbl = T/F depending on whether you want the variable reversed
#' @param retHz = forward return horizon in months
#' @param classif = classif file
#' @keywords sf.underlying.data
#' @export
#' @family sf

sf.underlying.data <- function (vbl.nm, univ, ret.nm, ret.prd, trail, sum.flows, grp, 
    dly.vbl, nBins, fldr, vbl.lag, reverse.vbl, retHz, classif) 
{
    mem <- sf.subset(univ, ret.prd, fldr, classif)
    vbl <- yyyymm.lag(ret.prd, 1)
    if (dly.vbl & nchar(ret.prd) == 6) 
        vbl <- yyyymmdd.ex.yyyymm(vbl)
    if (!dly.vbl & nchar(ret.prd) == 8) 
        vbl <- yyyymm.lag(yyyymmdd.to.yyyymm(vbl))
    if (vbl.lag > 0) 
        vbl <- yyyymm.lag(vbl, vbl.lag)
    vbl <- fetch(vbl.nm, vbl, trail, paste(fldr, "derived", sep = "\\"), 
        classif)
    if (reverse.vbl) 
        vbl <- -vbl
    if (trail > 1) 
        vbl <- compound.sf(vbl, sum.flows)
    if (retHz == 1) {
        ret <- fetch(ret.nm, ret.prd, 1, paste(fldr, "data", 
            sep = "\\"), classif)
    }
    else {
        ret <- fetch(ret.nm, yyyymm.lag(ret.prd, 1 - retHz), 
            retHz, paste(fldr, "data", sep = "\\"), classif)
        ret <- mat.compound(ret)
    }
    bin <- ifelse(is.na(ret), 0, mem)
    bin <- qtl(vbl, nBins, bin, grp)
    bin <- ifelse(is.na(bin), "Qna", paste0("Q", bin))
    z <- data.frame(vbl, bin, ret, mem, grp, row.names = dimnames(classif)[[1]], 
        stringsAsFactors = F)
    z
}

#' sf.underlying.summ
#' 
#' Returns a named vector of bin returns
#' @param x = vector of bins
#' @param y = corresponding numeric vector of forward returns
#' @param n = corresponding 1/0 universe membership vector
#' @param w = number of bins
#' @param h = T/F variable controlling whether universe return is returned
#' @keywords sf.underlying.summ
#' @export
#' @family sf

sf.underlying.summ <- function (x, y, n, w, h) 
{
    n <- is.element(n, 1) & !is.na(y)
    if (any(n)) {
        univ.eq.wt.ret <- mean(y[n])
        y <- y - univ.eq.wt.ret
        z <- pivot.1d(mean, x[n], y[n])
    }
    else {
        univ.eq.wt.ret <- NA
        z <- c(1:w, "na")
        z <- paste0("Q", z)
        z <- vec.named(rep(NA, length(z)), z)
    }
    if (h) 
        z["uRet"] <- univ.eq.wt.ret
    z
}

#' smear.Q1
#' 
#' Returns weights associated with ranks 1:x so that a) every position in the top quintile has an equal positive weight b) every position in the bottom 3 quintiles has an equal negative weight c) second quintile positions get a linear interpolation d) the weights sum to zero e) the positive weights sum to 100
#' @param x = any real number
#' @keywords smear.Q1
#' @export

smear.Q1 <- function (x) 
{
    bin <- qtl.eq(x:1)
    incr <- rep(NA, x)
    w <- bin == 2
    incr[w] <- sum(w):1
    incr[bin == 1] <- 1 + sum(w)
    incr[bin > 2] <- 0
    tot.incr <- sum(incr)
    m <- sum(bin < 3)
    pos.incr <- sum(incr[1:m])
    wt.incr <- 100/(pos.incr - m * tot.incr/x)
    neg.act <- tot.incr * wt.incr/x
    z <- incr * wt.incr - neg.act
    while (abs(sum(vec.max(z, 0)) - 100) > 1e-05) {
        m <- m - 1
        pos.incr <- sum(incr[1:m])
        wt.incr <- 100/(pos.incr - m * tot.incr/x)
        neg.act <- tot.incr * wt.incr/x
        z <- incr * wt.incr - neg.act
    }
    z
}

#' sql.1dActWtTrend
#' 
#' the SQL query to get 1dActWtTrend
#' @param x = the YYYYMMDD for which you want flows (known one day later)
#' @param y = a string vector of factors to be computed, the last element of which is the type of fund used.
#' @param n = any of StockFlows/China/Japan/CSI300/Energy
#' @param w = T/F depending on whether you are checking ftp
#' @keywords sql.1dActWtTrend
#' @export
#' @family sql

sql.1dActWtTrend <- function (x, y, n, w) 
{
    y <- sql.arguments(y)
    z <- sql.1dActWtTrend.underlying(x, y$filter, sql.RDSuniv(n))
    z <- c(z, sql.1dActWtTrend.topline(y$factor, x, w))
    z
}

#' sql.1dActWtTrend.Ctry.underlying
#' 
#' Generates the SQL query
#' @param x = a string vector indexed by allocation-table names
#' @param y = the SQL table from which you get flows (DailyData/MonthlyData)
#' @param n = one of Ctry/FX/Sector
#' @keywords sql.1dActWtTrend.Ctry.underlying
#' @export
#' @family sql

sql.1dActWtTrend.Ctry.underlying <- function (x, y, n) 
{
    z <- c(sql.label(sql.FundHistory("", c("CB", "E"), F, c("FundId", 
        "GeographicFocus")), "t0"), "inner join")
    z <- c(z, paste0(y, " t1"), "\ton t1.HFundId = t0.HFundId", 
        "inner join")
    z <- c(z, sql.label(sql.1dFloMo.Ctry.Allocations(x, n), "t2"), 
        "\ton t2.FundId = t0.FundId")
    if (y == "MonthlyData") {
        z <- c(z, paste("\t\tand t2.WeightDate =", sql.floTbl.to.Col(y, 
            F)))
    }
    else z <- c(z, paste("\t\tand", sql.datediff("WeightDate", 
        sql.floTbl.to.Col(y, F), 23)))
    z <- c(z, "inner join", sql.label(sql.1dFloMo.Ctry.Allocations.GF.avg(x, 
        n), "t3"))
    z <- c(z, "\ton t3.GeographicFocus = t0.GeographicFocus and t3.WeightDate = t2.WeightDate")
    z
}

#' sql.1dActWtTrend.select
#' 
#' select statement to compute <x>
#' @param x = desired factor
#' @keywords sql.1dActWtTrend.select
#' @export
#' @family sql

sql.1dActWtTrend.select <- function (x) 
{
    if (x == "ActWtTrend") {
        z <- paste(x, sql.Trend("Flow * (hld.HoldingValue/aum.PortVal - FundWtdExcl0)"))
    }
    else if (x == "ActWtDiff") {
        z <- paste(x, sql.Diff("Flow", "hld.HoldingValue/aum.PortVal - FundWtdExcl0"))
    }
    else if (x == "ActWtDiff2") {
        z <- paste(x, sql.Diff("hld.HoldingValue/aum.PortVal - FundWtdExcl0", 
            "Flow"))
    }
    else stop("Bad Argument")
    z
}

#' sql.1dActWtTrend.topline
#' 
#' SQL query to get the select statement for 1dActWtTrend
#' @param x = a string vector of factors to be computed
#' @param y = the YYYYMMDD for which you want flows (known one day later)
#' @param n = T/F depending on whether you are checking ftp
#' @keywords sql.1dActWtTrend.topline
#' @export
#' @family sql

sql.1dActWtTrend.topline <- function (x, y, n) 
{
    if (n) {
        z <- c(paste0("ReportDate = '", y, "'"), "hld.HSecurityId")
    }
    else {
        z <- "SecurityId"
    }
    z <- c(z, sapply(vec.to.list(x), sql.1dActWtTrend.select))
    x <- sql.1dActWtTrend.topline.from()
    if (!n) 
        x <- c(x, "inner join", "SecurityHistory id on id.HSecurityId = hld.HSecurityId")
    n <- ifelse(n, "hld.HSecurityId", "SecurityId")
    z <- paste(sql.unbracket(sql.tbl(z, x, , n)), collapse = "\n")
    z
}

#' sql.1dActWtTrend.topline.from
#' 
#' SQL query to get the select statement for 1dActWtTrend
#' @keywords sql.1dActWtTrend.topline.from
#' @export
#' @family sql

sql.1dActWtTrend.topline.from <- function () 
{
    w <- "HSecurityId, GeographicFocusId, FundWtdExcl0 = sum(HoldingValue)/sum(PortVal)"
    z <- c("#FLO t1", "inner join", "#HLD t2 on t2.FundId = t1.FundId", 
        "inner join", "#AUM t3 on t3.FundId = t1.FundId")
    w <- sql.label(sql.tbl(w, z, , "HSecurityId, GeographicFocusId"), 
        "mnW")
    z <- c("#FLO flo", "inner join", "#HLD hld on hld.FundId = flo.FundId", 
        "inner join", "#AUM aum on aum.FundId = hld.FundId", 
        "inner join")
    z <- c(z, w, "\ton mnW.HSecurityId = hld.HSecurityId and mnW.GeographicFocusId = flo.GeographicFocusId")
    z
}

#' sql.1dActWtTrend.underlying
#' 
#' the SQL query to get the data for 1dActWtTrend
#' @param x = the YYYYMMDD for which you want flows (known one day later)
#' @param y = the type of fund used in the computation
#' @param n = "" or the SQL query to subset to securities desired
#' @keywords sql.1dActWtTrend.underlying
#' @export
#' @family sql

sql.1dActWtTrend.underlying <- function (x, y, n) 
{
    mo.end <- yyyymm.to.day(yyyymmdd.to.AllocMo(x, 26))
    z <- c("DailyData t1", "inner join", sql.label(sql.FundHistory("", 
        y, T, c("FundId", "GeographicFocusId")), "t2"), "on t2.HFundId = t1.HFundId")
    z <- sql.tbl("FundId, GeographicFocusId, Flow = sum(Flow), AssetsStart = sum(AssetsStart)", 
        z, paste0("ReportDate = '", x, "'"), "FundId, GeographicFocusId")
    z <- c("insert into", "\t#FLO (FundId, GeographicFocusId, Flow, AssetsStart)", 
        sql.unbracket(z))
    z <- c("create clustered index TempRandomFloIndex ON #FLO(FundId)", 
        z)
    z <- c("create table #FLO (FundId int not null, GeographicFocusId int, Flow float, AssetsStart float)", 
        z)
    z <- c(sql.drop(c("#AUM", "#HLD", "#FLO")), "", z)
    z <- c(z, "", "create table #AUM (FundId int not null, PortVal float not null)", 
        "create clustered index TempRandomAumIndex ON #AUM(FundId)")
    w <- c("MonthlyData t1", "inner join", "FundHistory t2 on t2.HFundId = t1.HFundId")
    w <- sql.unbracket(sql.tbl("FundId, PortVal = sum(AssetsEnd)", 
        w, paste0("ReportDate = '", mo.end, "'"), "FundId", "sum(AssetsEnd) > 0"))
    z <- c(z, "insert into", "\t#AUM (FundId, PortVal)", w)
    z <- c(z, "", "create table #HLD (FundId int not null, HFundId int not null, HSecurityId int not null, HoldingValue float)")
    z <- c(z, "create clustered index TempRandomHoldIndex ON #HLD(FundId, HSecurityId)")
    z <- c(z, "insert into", "\t#HLD (FundId, HFundId, HSecurityId, HoldingValue)", 
        sql.unbracket(sql.MonthlyAlloc(paste0("'", mo.end, "'"))))
    if (any(y == "Pseudo")) {
        cols <- c("FundId", "HFundId", "HSecurityId", "HoldingValue")
        z <- c(z, "", sql.Holdings.bulk("#HLD", cols, mo.end, 
            "#BMKHLD", "#BMKAUM"), "")
    }
    if (n[1] != "") 
        z <- c(z, "", "delete from #HLD where", paste0("\t", 
            sql.in("HSecurityId", n, F)))
    z <- c(z, "", "delete from #HLD where", paste0("\t", sql.in("FundId", 
        sql.tbl("FundId", "#FLO"), F)), "")
    z <- paste(z, collapse = "\n")
    z
}

#' sql.1dFloMo
#' 
#' Generates the SQL query to get the data for 1dFloMo for individual stocks
#' @param x = the date for which you want flows (known one day later)
#' @param y = a string vector of factors to be computed, the last element of which is the type of fund used
#' @param n = any of StockFlows/China/Japan/CSI300/Energy
#' @param w = T/F depending on whether you are checking ftp
#' @keywords sql.1dFloMo
#' @export
#' @family sql

sql.1dFloMo <- function (x, y, n, w) 
{
    h <- sql.1dFloMo.underlying(x)
    if (any(y == "Pseudo")) {
        cols <- c("FundId", "HFundId", "HSecurityId", "HoldingValue")
        h <- c(h, "", sql.Holdings.bulk("#HLD", cols, yyyymm.to.day(yyyymmdd.to.AllocMo(x, 
            26)), "#BMKHLD", "#BMKAUM"), "")
    }
    z <- sql.1dFloMo.select.wrapper(x, y, w)
    grp <- sql.1dFloMo.grp(y, w)
    y <- c(sql.label(sql.1dFloMo.filter(y, w), "t0"), "inner join", 
        "#HLD t1 on t1.FundId = t0.FundId")
    y <- c(y, "inner join", sql.label(sql.tbl("HFundId, Flow, AssetsStart", 
        "DailyData", paste0("ReportDate = '", x, "'")), "t2 on t2.HFundId = t0.HFundId"))
    y <- c(y, "inner join", "#AUM t3 on t3.FundId = t1.FundId")
    if (!w) 
        y <- c(y, "inner join", "SecurityHistory id on id.HSecurityId = t1.HSecurityId")
    if (n == "All") {
        z <- sql.tbl(z, y, , grp, "sum(HoldingValue/AssetsEnd) > 0")
    }
    else {
        z <- sql.tbl(z, y, sql.in("t1.HSecurityId", sql.RDSuniv(n)), 
            grp, "sum(HoldingValue/AssetsEnd) > 0")
    }
    z <- c(paste(h, collapse = "\n"), paste(sql.unbracket(z), 
        collapse = "\n"))
    z
}

#' sql.1dFloMo.Ctry
#' 
#' Generates the SQL query to get daily 1dFloMo for countries
#' @param x = Ctry/FX/Sector
#' @param y = item (Flow/AssetsStart/AssetsEnd)
#' @keywords sql.1dFloMo.Ctry
#' @export
#' @family sql

sql.1dFloMo.Ctry <- function (x, y = "Flow%") 
{
    w <- sql.1dFloMo.Ctry.List(x)
    if (x == "EMDM") {
        x <- sql.1dFloMo.Ctry.Allocations(w, x, vec.named(c("EAFE", 
            "EM"), c("DM", "EM")))
    }
    else {
        x <- sql.1dFloMo.Ctry.Allocations(w, x)
    }
    z <- paste0("[", unique(w), "]")
    if (txt.right(y, 1) == "%") {
        z <- paste(z, sql.Mo(txt.left(y, nchar(y) - 1), "AssetsStart", 
            z, T))
    }
    else {
        z <- paste0(z, " = 0.01 * sum(", y, " * ", z, ")")
    }
    z <- c("DayEnding = convert(char(8), DayEnding, 112)", z)
    w <- c(sql.label(sql.FundHistory("", c("CB", "E"), F, "FundId"), 
        "t0"), "inner join", "DailyData t1 on t1.HFundId = t0.HFundId", 
        "inner join")
    w <- c(w, sql.label(x, "t2"), "\ton t2.FundId = t0.FundId", 
        paste0("\tand ", sql.datediff("WeightDate", "DayEnding", 
            23)))
    z <- paste(sql.unbracket(sql.tbl(z, w, , "DayEnding")), collapse = "\n")
    z
}

#' sql.1dFloMo.Ctry.Allocations
#' 
#' Generates the SQL query to get daily 1dFloMo for countries
#' @param x = a string vector indexed by allocation-table names
#' @param y = one of Ctry/FX/Sector
#' @param n = missing or a named vector of EAFE/EM/ACWI indexed by the elements of <x>
#' @keywords sql.1dFloMo.Ctry.Allocations
#' @export
#' @family sql

sql.1dFloMo.Ctry.Allocations <- function (x, y, n) 
{
    w <- !duplicated(x)
    x <- c(vec.named(x[w], x[w]), x)
    x <- split(names(x), x)
    if (missing(n)) 
        n <- vec.named(, names(x))
    else n <- map.rname(n, names(x))
    fcn <- function(x) paste0("[", x[1], "] = ", sql.1dFloMo.Ctry.Allocations.term(x[-1], 
        n[x[1]]))
    z <- c("FundId", "WeightDate", sapply(x, fcn))
    z <- sql.tbl(z, sql.AllocTbl(y))
    z
}

#' sql.1dFloMo.Ctry.Allocations.GF.avg
#' 
#' Generates the SQL query to get daily 1dFloMo for countries
#' @param x = a string vector indexed by allocation-table names
#' @param y = one of Ctry/FX/Sector
#' @keywords sql.1dFloMo.Ctry.Allocations.GF.avg
#' @export
#' @family sql

sql.1dFloMo.Ctry.Allocations.GF.avg <- function (x, y) 
{
    y <- c(paste(sql.AllocTbl(y), "x"), "inner join", "FundHistory y", 
        "\ton x.HFundId = y.HFundId")
    x <- split(names(x), x)
    fcn <- function(x) {
        z <- paste(paste0("isnull(", x, ", 0)"), collapse = " + ")
        paste0("sum((", z, ") * FundSize)/sum(FundSize)")
    }
    z <- sapply(x, fcn)
    z <- c("WeightDate", "GeographicFocus", paste0("[", names(x), 
        "] = ", z))
    z <- sql.tbl(z, y, "FundType = 'E'", "WeightDate, GeographicFocus")
    z
}

#' sql.1dFloMo.Ctry.Allocations.term
#' 
#' total weight allocated to countries <x> in index <y>
#' @param x = a string vector of allocation-table names
#' @param y = NA or one of EM/EAFE/ACWI
#' @keywords sql.1dFloMo.Ctry.Allocations.term
#' @export
#' @family sql

sql.1dFloMo.Ctry.Allocations.term <- function (x, y) 
{
    if (!is.na(y)) {
        y <- Ctry.msci(y)
        y <- y[order(y$YYYYMM), ]
        y[, "CCODE"] <- Ctry.info(y[, "CCODE"], "AllocTable")
        w <- !is.element(x, y[, "CCODE"])
    }
    else {
        w <- rep(T, length(x))
    }
    if (sum(!w) > 1) 
        x[!w] <- y[is.element(y[, "CCODE"], x) & !duplicated(y[, 
            "CCODE"]), "CCODE"]
    z <- paste(paste0("isnull(", x[w], ", 0)"), collapse = " + ")
    if (any(!w)) {
        for (j in x[!w]) {
            z <- paste0(z, "\n\t+ case when ", Ctry.msci.sql(yyyymm.to.day, 
                y, j, "WeightDate"), " then isnull(", j, ", 0) else 0 end")
        }
    }
    z
}

#' sql.1dFloMo.Ctry.List
#' 
#' Generates the SQL query to get daily 1dFloMo for countries
#' @param x = one of Ctry/FX/Sector/EMDM
#' @keywords sql.1dFloMo.Ctry.List
#' @export
#' @family sql

sql.1dFloMo.Ctry.List <- function (x) 
{
    classif.type <- x
    sep <- ","
    if (x == "Ctry") {
        z <- Ctry.msci.members.rng("ACWI", "200704", "300012")
        classif.type <- "Ctry"
    }
    else if (x == "LatAm") {
        z <- mat.read(parameters("classif-Ctry"))
        z <- dimnames(z)[[1]][is.element(z$EpfrRgn, x)]
        classif.type <- "Ctry"
    }
    else if (x == "EMDM") {
        z <- Ctry.msci.members.rng("ACWI", "199710", "300012")
        classif.type <- "Ctry"
    }
    else if (x == "FX") {
        z <- Ctry.msci.members.rng("ACWI", "200704", "300012")
        z <- c(z, "CY", "EE", "LV", "LT", "SK", "SI")
        classif.type <- "Ctry"
    }
    else if (x == "Sector") {
        z <- dimnames(mat.read(parameters("classif-GSec"), "\t"))[[1]]
        classif.type <- "GSec"
        sep <- "\t"
    }
    y <- parameters(paste("classif", classif.type, sep = "-"))
    y <- mat.read(y, sep)
    y <- map.rname(y, z)
    if (any(x == c("Ctry", "Sector", "LatAm"))) {
        z <- vec.named(z, y$AllocTable)
    }
    else if (x == "EMDM") {
        w.dm <- is.element(z, c("US", "CA", Ctry.msci.members.rng("EAFE", 
            "199710", "300012")))
        w.em <- is.element(z, Ctry.msci.members.rng("EM", "199710", 
            "300012"))
        z <- c(vec.named(rep("DM", sum(w.dm)), y$AllocTable[w.dm]), 
            vec.named(rep("EM", sum(w.em)), y$AllocTable[w.em]))
    }
    else if (x == "FX") {
        z <- vec.named(y$Curr, y$AllocTable)
    }
    z
}

#' sql.1dFloMo.CtryFlow
#' 
#' SQL query for country-flow percentage for date <x>
#' @param x = the date for which you want flows (known one day later)
#' @param y = FundType (one of E/B)
#' @param n = item (one of Flow/AssetsStart/AssetsEnd/Flow\%)
#' @param w = country list (one of Ctry/LatAm)
#' @keywords sql.1dFloMo.CtryFlow
#' @export
#' @family sql

sql.1dFloMo.CtryFlow <- function (x, y, n, w) 
{
    h <- sql.1dFloMo.Ctry.List(w)
    z <- paste0("[", h, "] = avg(", names(h), ")")
    z <- c("WeightDate", "GeographicFocus", "Advisor", z)
    u <- sql.label(sql.FundHistory("", c("CB", y, "UI"), F, c("GeographicFocus", 
        "Advisor")), "t2")
    u <- c("CountryAllocations t1", "inner join", u, "\ton t2.HFundId = t1.HFundId")
    z <- sql.label(sql.tbl(z, u, , "WeightDate, GeographicFocus, Advisor"), 
        "t")
    u <- c("WeightDate", "GeographicFocus", paste0("[", h, "] = avg([", 
        h, "])"))
    u <- sql.tbl(u, z, , "WeightDate, GeographicFocus")
    if (n == "Flow%") {
        z <- c("Flow", "AssetsStart")
    }
    else {
        z <- n
    }
    z <- c("DayEnding", "HFundId", paste0(z, " = sum(", z, ")"))
    z <- sql.tbl(z, "DailyData", "DayEnding >= @floDt", "DayEnding, HFundId")
    w <- sql.label(sql.FundHistory("", c(y, "UI"), F, "GeographicFocus"), 
        "t2")
    z <- c(sql.label(z, "t1"), "inner join", w, "\ton t2.HFundId = t1.HFundId")
    z <- c(z, "left join", sql.label(u, "t3"), "\ton t3.GeographicFocus = t2.GeographicFocus")
    z <- c(z, "\t\tand datediff(month, WeightDate, DayEnding) = case when day(DayEnding) < 23 then 2 else 1 end")
    w <- Ctry.info(h, "GeoId")
    if (n == "Flow%") {
        u <- paste0("case when t2.GeographicFocus = ", w, " then 100 else [", 
            h, "] end")
        u <- ifelse(is.na(w), paste0("[", h, "]"), u)
        u <- sql.Mo("Flow", "AssetsStart", u, T)
        u <- paste0("[", h, "] ", u)
    }
    else {
        u <- paste0("case when t2.GeographicFocus = ", w, " then 100 else [", 
            h, "] end")
        u <- ifelse(is.na(w), paste0("[", h, "]"), u)
        u <- paste0("sum(0.01 * ", n, " * cast(", u, " as float))")
        u <- paste0("[", h, "] = ", u)
    }
    u <- c("DayEnding = convert(char(8), DayEnding, 112)", u)
    z <- sql.tbl(u, z, , "DayEnding")
    z <- c(sql.declare("@floDt", "datetime", x), sql.unbracket(z))
    z <- paste(z, collapse = "\n")
    z
}

#' sql.1dFloMo.FI
#' 
#' Generates the SQL query to get daily 1dFloMo for fixed income
#' @keywords sql.1dFloMo.FI
#' @export
#' @family sql

sql.1dFloMo.FI <- function () 
{
    x <- c("GLOBEM", "WESEUR", "HYIELD", "FLOATS", "USTRIN", 
        "USTRLT", "USTRST", "CASH", "USMUNI", "GLOFIX")
    z <- paste0("sum(case when grp = '", x, "' then AssetsStart else NULL end)")
    z <- sql.nonneg(z)
    z <- paste0(x, " = 100 * sum(case when grp = '", x, "' then Flow else NULL end)/", 
        z)
    z <- c("DayEnding = convert(char(8), DayEnding, 112)", z)
    z <- paste(sql.unbracket(sql.tbl(z, sql.1dFloMo.FI.underlying(), 
        , "DayEnding")), collapse = "\n")
    z
}

#' sql.1dFloMo.FI.underlying
#' 
#' Generates the SQL query to get daily 1dFloMo for fixed income
#' @keywords sql.1dFloMo.FI.underlying
#' @export
#' @family sql

sql.1dFloMo.FI.underlying <- function () 
{
    z <- c("HFundId", "grp =", "\tcase", "\twhen FundType = 'M' then 'CASH'", 
        "\twhen StyleSector = 130 then 'FLOATS'")
    z <- c(z, "\twhen StyleSector = 134 and GeographicFocus = 77 then 'USTRIN'", 
        "\twhen StyleSector = 137 and GeographicFocus = 77 then 'USTRLT'")
    z <- c(z, "\twhen StyleSector = 141 and GeographicFocus = 77 then 'USTRST'", 
        "\twhen StyleSector = 185 and GeographicFocus = 77 then 'USMUNI'")
    z <- c(z, "\twhen StyleSector = 125 and Category = '9' then 'HYIELD'", 
        "\twhen Category = '8' then 'WESEUR'")
    z <- c(z, "\twhen GeographicFocus = 31 then 'GLOBEM'", "\twhen GeographicFocus = 30 then 'GLOFIX'", 
        "\telse 'OTHER'", "\tend")
    z <- sql.label(sql.tbl(z, "FundHistory", "FundType in ('B', 'M')"), 
        "t2")
    z <- c("DailyData t1", "inner join", z, "\ton t2.HFundId = t1.HFundId")
    z
}

#' sql.1dFloMo.filter
#' 
#' implements filters for 1dFloMo
#' @param x = a string vector of factors to be computed, the last elements of which are the type of fund used
#' @param y = T/F depending on whether you are checking ftp
#' @keywords sql.1dFloMo.filter
#' @export
#' @family sql

sql.1dFloMo.filter <- function (x, y) 
{
    x <- sql.arguments(x)
    if (y & x$factor[1] == "FloDollar") {
        z <- sql.FundHistory("", x$filter, T, c("FundId", "GeographicFocusId"))
    }
    else {
        z <- sql.FundHistory("", x$filter, T, "FundId")
    }
    z
}

#' sql.1dFloMo.grp
#' 
#' group by clause for 1dFloMo
#' @param x = a string vector of factors to be computed
#' @param y = T/F depending on whether you are checking ftp
#' @keywords sql.1dFloMo.grp
#' @export
#' @family sql

sql.1dFloMo.grp <- function (x, y) 
{
    if (y & x[1] == "FloDollar") {
        z <- "HSecurityId, GeographicFocusId"
    }
    else {
        z <- ifelse(y, "HSecurityId", "SecurityId")
    }
    z
}

#' sql.1dFloMo.Rgn
#' 
#' Generates the SQL query to get daily 1dFloMo for regions
#' @keywords sql.1dFloMo.Rgn
#' @export
#' @family sql

sql.1dFloMo.Rgn <- function () 
{
    rgn <- c(4, 24, 43, 46, 55, 76, 77)
    names(rgn) <- c("AsiaXJP", "EurXGB", "Japan", "LatAm", "PacXJP", 
        "UK", "USA")
    x <- paste0("sum(case when grp = ", rgn, " then AssetsStart else NULL end)")
    x <- sql.nonneg(x)
    z <- paste0(names(rgn), " = 100 * sum(case when grp = ", 
        rgn, " then Flow else NULL end)/", x)
    z <- c("DayEnding = convert(char(8), DayEnding, 112)", z)
    y <- c("HFundId, grp = case when GeographicFocus in (6, 80, 35, 66) then 55 else GeographicFocus end")
    w <- sql.and(list(A = "FundType = 'E'", B = "Idx = 'N'", 
        C = sql.in("GeographicFocus", "(4, 24, 43, 46, 55, 76, 77, 6, 80, 35, 66)")))
    y <- c(sql.label(sql.tbl(y, "FundHistory", w), "t1"), "inner join", 
        "DailyData t2", "\ton t2.HFundId = t1.HFundId")
    z <- paste(sql.unbracket(sql.tbl(z, y, , "DayEnding")), collapse = "\n")
    z
}

#' sql.1dFloMo.select
#' 
#' select statement to compute <x>
#' @param x = desired factor
#' @keywords sql.1dFloMo.select
#' @export
#' @family sql

sql.1dFloMo.select <- function (x) 
{
    if (is.element(x, paste0("FloMo", c("", "CB", "PMA")))) {
        z <- paste(x, sql.Mo("Flow", "AssetsStart", "HoldingValue/AssetsEnd", 
            T))
    }
    else if (x == "FloDollar") {
        z <- paste(x, "= sum(Flow * HoldingValue/AssetsEnd)")
    }
    else if (x == "Inflow") {
        z <- paste(x, "= sum(case when Flow > 0 then Flow else 0 end * HoldingValue/AssetsEnd)")
    }
    else if (x == "Outflow") {
        z <- paste(x, "= sum(case when Flow < 0 then Flow else 0 end * HoldingValue/AssetsEnd)")
    }
    else if (x == "FloDollarGross") {
        z <- paste(x, "= sum(abs(Flow) * HoldingValue/AssetsEnd)")
    }
    else stop("Bad Argument")
    z
}

#' sql.1dFloMo.select.wrapper
#' 
#' Generates the SQL query to get the data for 1mFloMo for individual stocks
#' @param x = the YYYYMM for which you want data (known 16 days later)
#' @param y = a string vector of factors to be computed, the last elements of are the type of fund used
#' @param n = T/F depending on whether you are checking ftp
#' @keywords sql.1dFloMo.select.wrapper
#' @export
#' @family sql

sql.1dFloMo.select.wrapper <- function (x, y, n) 
{
    y <- sql.arguments(y)$factor
    if (n & y[1] == "FloDollar") {
        z <- c(paste0("ReportDate = '", x, "'"), "GeoId = GeographicFocusId", 
            "HSecurityId")
    }
    else if (n) {
        z <- c(paste0("ReportDate = '", x, "'"), "HSecurityId")
    }
    else {
        z <- c("SecurityId")
    }
    for (i in y) {
        if (n & i == "FloDollar") {
            z <- c(z, paste("CalculatedStockFlow", txt.right(sql.1dFloMo.select(i), 
                nchar(sql.1dFloMo.select(i)) - nchar(i) - 1)))
        }
        else {
            z <- c(z, sql.1dFloMo.select(i))
        }
    }
    z
}

#' sql.1dFloMo.underlying
#' 
#' Underlying part of SQL query to get 1dFloMo for individual stocks
#' @param x = the date for which you want flows (known one day later)
#' @keywords sql.1dFloMo.underlying
#' @export
#' @family sql

sql.1dFloMo.underlying <- function (x) 
{
    x <- yyyymm.to.day(yyyymmdd.to.AllocMo(x, 26))
    z <- c(sql.into(sql.MonthlyAlloc(paste0("'", x, "'")), "#HLD"))
    z <- c(z, "", sql.into(sql.MonthlyAssetsEnd(paste0("'", x, 
        "'"), "", F, T), "#AUM"))
    z <- c(sql.drop(c("#HLD", "#AUM")), "", z, "")
    z
}

#' sql.1dFloMoAggr
#' 
#' Generates the SQL query to get the data for aggregate 1dFloMo
#' @param x = the YYYYMMDD for which you want flows (known two days later)
#' @param y = one or more of FwtdIn0/FwtdEx0/SwtdIn0/SwtdEx0
#' @param n = any of StockFlows/China/Japan/CSI300/Energy
#' @keywords sql.1dFloMoAggr
#' @export
#' @family sql

sql.1dFloMoAggr <- function (x, y, n) 
{
    mo.end <- yyyymmdd.to.AllocMo(x, 26)
    mo.end <- yyyymm.to.day(mo.end)
    z <- list(A = paste0("ReportDate = '", mo.end, "'"), B = sql.in("HSecurityId", 
        sql.RDSuniv(n)))
    z <- sql.Holdings(sql.and(z), c("ReportDate", "HFundId", 
        "HSecurityId", "HoldingValue"), "#HLDGS")
    h <- "GeographicFocusId, Flow = sum(Flow), AssetsStart = sum(AssetsStart)"
    w <- c("FundHistory t1", "inner join", "DailyData t2 on t2.HFundId = t1.HFundId")
    z <- c(z, "", sql.into(sql.tbl(h, w, paste0("ReportDate = '", 
        x, "'"), "GeographicFocusId", "sum(AssetsStart) > 0"), 
        "#FLOWS"))
    z <- c(z, "", sql.AggrAllocations(y, "#HLDGS", paste0("'", 
        mo.end, "'"), "GeographicFocusId", "#ALLOC"))
    y <- c("SecurityId", paste0(y, " = 100 * sum(Flow * ", y, 
        ")/", sql.nonneg(paste0("sum(AssetsStart * ", y, ")"))))
    w <- c("#ALLOC t1", "inner join", "#FLOWS t2 on t1.GeographicFocusId = t2.GeographicFocusId")
    w <- c(w, "inner join", "SecurityHistory id on id.HSecurityId = t1.HSecurityId")
    w <- paste(sql.unbracket(sql.tbl(y, w, , "SecurityId")), 
        collapse = "\n")
    z <- paste(c(sql.drop(c("#FLOWS", "#HLDGS", "#ALLOC")), "", 
        z), collapse = "\n")
    z <- c(z, w)
    z
}

#' sql.1dFloTrend
#' 
#' Generates the SQL query to get the data for 1dFloTrend
#' @param x = data date in YYYYMMDD (known two days later)
#' @param y = a string vector of factors to be computed,       the last element of which is the type of fund used.
#' @param n = the delay in knowing allocations
#' @param w = any of StockFlows/China/Japan/CSI300/Energy
#' @param h = T/F depending on whether you are checking ftp
#' @keywords sql.1dFloTrend
#' @export
#' @family sql

sql.1dFloTrend <- function (x, y, n, w, h) 
{
    y <- sql.arguments(y)
    if (h) {
        z <- c(paste0("ReportDate = '", x, "'"), "n1.HSecurityId")
    }
    else {
        z <- "n1.SecurityId"
    }
    z <- c(z, sapply(vec.to.list(y$factor), sql.1dFloTrend.select))
    x <- sql.1dFloTrend.underlying(y$filter, w, x, n)
    h <- ifelse(h, "n1.HSecurityId", "n1.SecurityId")
    z <- c(paste(x$PRE, collapse = "\n"), paste(sql.unbracket(sql.tbl(z, 
        x$FINAL, , h)), collapse = "\n"))
    z
}

#' sql.1dFloTrend.Ctry
#' 
#' For Ctry/FX generates the SQL query to get daily 1d a) FloDiff		= sql.1dFloTrend.Ctry("?", "Flo", "Diff") b) FloTrend		= sql.1dFloTrend.Ctry("?", "Flo", "Trend") c) ActWtDiff		= sql.1dFloTrend.Ctry("?", "ActWt", "Diff") d) ActWtTrend		= sql.1dFloTrend.Ctry("?", "ActWt", "Trend") e) FloDiff2		= sql.1dFloTrend.Ctry("?", "Flo", "Diff2") f) ActWtDiff2		= sql.1dFloTrend.Ctry("?", "ActWt", "Diff2") g) AllocMo		= sql.1dFloTrend.Ctry("?", "Flo", "AllocMo") h) AllocDiff		= sql.1dFloTrend.Ctry("?", "Flo", "AllocDiff") i) AllocTrend		= sql.1dFloTrend.Ctry("?", "Flo", "AllocTrend") j) AllocSkew		= sql.1dFloTrend.Ctry("?", "ActWt", "AllocSkew")
#' @param x = one of Ctry/FX/Sector
#' @param y = one of Flo/ActWt
#' @param n = one of Diff/Diff2/Trend/AllocMo/AllocDiff/AllocTrend
#' @keywords sql.1dFloTrend.Ctry
#' @export
#' @family sql

sql.1dFloTrend.Ctry <- function (x, y, n) 
{
    if (x == "Sector") 
        floTbl <- "WeeklyData"
    else floTbl <- "DailyData"
    if (is.element(n, c("AllocMo", "AllocDiff", "AllocTrend", 
        "AllocSkew"))) 
        floTbl <- "MonthlyData"
    ctry <- sql.1dFloMo.Ctry.List(x)
    z <- sql.1dFloTrend.Ctry.topline(n, ctry, floTbl)
    fcn <- get(paste0("sql.1d", y, "Trend.Ctry.underlying"))
    z <- paste(sql.unbracket(sql.tbl(z, fcn(ctry, floTbl, x), 
        , sql.floTbl.to.Col(floTbl, F))), collapse = "\n")
    z
}

#' sql.1dFloTrend.Ctry.topline
#' 
#' Generates the SQL query to get daily 1d Flo/ActWt Diff/Trend for Ctry/FX
#' @param x = one of Trend/Diff/Diff2/AllocMo/AllocDiff/AllocTrend/AllocSkew
#' @param y = country list
#' @param n = one of DailyData/WeeklyData/MonthlyData
#' @keywords sql.1dFloTrend.Ctry.topline
#' @export
#' @family sql

sql.1dFloTrend.Ctry.topline <- function (x, y, n) 
{
    if (x == "Trend") {
        fcn <- function(i) sql.Trend(paste0("Flow * (t2.[", i, 
            "] - t3.[", i, "])"))
    }
    else if (x == "Diff") {
        fcn <- function(i) sql.Diff("Flow", paste0("t2.[", i, 
            "] - t3.[", i, "]"))
    }
    else if (x == "Diff2") {
        fcn <- function(i) sql.Diff(paste0("(t2.[", i, "] - t3.[", 
            i, "])"), "Flow")
    }
    else if (x == "AllocDiff") {
        fcn <- function(i) sql.Diff("(AssetsStart + AssetsEnd)", 
            paste0("t2.[", i, "] - t3.[", i, "]"))
    }
    else if (x == "AllocTrend") {
        fcn <- function(i) sql.Trend(paste0("(AssetsStart + AssetsEnd) * (t2.[", 
            i, "] - t3.[", i, "])"))
    }
    else if (x == "AllocSkew") {
        fcn <- function(i) sql.Diff("AssetsEnd", paste0("t3.[", 
            i, "] - t2.[", i, "]"))
    }
    else if (x == "AllocMo") {
        fcn <- function(i) paste0("= 2 * sum((AssetsStart + AssetsEnd) * (t2.[", 
            i, "] - t3.[", i, "]))", "/", sql.nonneg(paste0("sum((AssetsStart + AssetsEnd) * (t2.[", 
                i, "] + t3.[", i, "]))")))
    }
    else stop("Unknown Computation")
    z <- sql.floTbl.to.Col(n, T)
    y <- y[!duplicated(y)]
    for (i in y) z <- c(z, paste0("[", i, "] ", fcn(i)))
    z
}

#' sql.1dFloTrend.Ctry.underlying
#' 
#' Generates the SQL query to get daily 1dFloMo for countries
#' @param x = a string vector indexed by allocation-table names
#' @param y = the SQL table from which you get flows (DailyData/MonthlyData)
#' @param n = one of Ctry/FX/Sector
#' @keywords sql.1dFloTrend.Ctry.underlying
#' @export
#' @family sql

sql.1dFloTrend.Ctry.underlying <- function (x, y, n) 
{
    z <- c(sql.label(sql.FundHistory("", c("CB", "E"), F, "FundId"), 
        "t0"), "inner join")
    z <- c(z, paste0(y, " t1 on t1.HFundId = t0.HFundId"), "inner join")
    z <- c(z, paste0(sql.1dFloMo.Ctry.Allocations(x, n)))
    z <- c(sql.label(z, "t2"), "\ton t2.FundId = t0.FundId")
    if (y == "MonthlyData") {
        z <- c(z, paste("\t\tand t2.WeightDate =", sql.floTbl.to.Col(y, 
            F)))
    }
    else z <- c(z, paste("\t\tand", sql.datediff("WeightDate", 
        sql.floTbl.to.Col(y, F), 23)))
    z <- c(z, "inner join", sql.1dFloMo.Ctry.Allocations(x, n))
    z <- c(sql.label(z, "t3"), "\ton t3.FundId = t2.FundId and datediff(month, t3.WeightDate, t2.WeightDate) = 1")
    z
}

#' sql.1dFloTrend.select
#' 
#' select statement to compute <x>
#' @param x = desired factor
#' @keywords sql.1dFloTrend.select
#' @export
#' @family sql

sql.1dFloTrend.select <- function (x) 
{
    if (is.element(x, paste0("FloTrend", c("", "CB", "PMA")))) {
        z <- paste0(x, " ", sql.Trend("Flow * (n1.HoldingValue/n2.AssetsEnd - o1.HoldingValue/o2.AssetsEnd)"))
    }
    else if (is.element(x, paste0("FloDiff", c("", "CB", "PMA")))) {
        z <- paste0(x, " ", sql.Diff("Flow", "n1.HoldingValue/n2.AssetsEnd - o1.HoldingValue/o2.AssetsEnd"))
    }
    else if (is.element(x, paste0("FloDiff2", c("", "CB", "PMA")))) {
        z <- paste0(x, " ", sql.Diff("n1.HoldingValue/n2.AssetsEnd - o1.HoldingValue/o2.AssetsEnd", 
            "Flow"))
    }
    else stop("Bad Argument")
    z
}

#' sql.1dFloTrend.underlying
#' 
#' Generates the SQL query to get the data for 1dFloTrend
#' @param x = a vector of filters
#' @param y = any of All/StockFlows/China/Japan/CSI300/Energy
#' @param n = flow date in YYYYMMDD (known two days later)
#' @param w = the delay in knowing allocations
#' @keywords sql.1dFloTrend.underlying
#' @export
#' @family sql

sql.1dFloTrend.underlying <- function (x, y, n, w) 
{
    vec <- vec.named(c("#NEW", "#OLD"), c("n", "o"))
    z <- sql.into(sql.DailyFlo(paste0("'", n, "'")), "#DLYFLO")
    n <- yyyymmdd.to.AllocMo(n, w)
    n <- c(n, yyyymm.lag(n))
    z <- c(z, "", sql.into(sql.MonthlyAlloc(paste0("'", yyyymm.to.day(n[1]), 
        "'")), "#NEWHLD"))
    z <- c(z, "", sql.into(sql.MonthlyAssetsEnd(paste0("'", yyyymm.to.day(n[1]), 
        "'"), "", F, T), "#NEWAUM"))
    z <- c(z, "", sql.into(sql.MonthlyAlloc(paste0("'", yyyymm.to.day(n[2]), 
        "'")), "#OLDHLD"))
    z <- c(z, "", sql.into(sql.MonthlyAssetsEnd(paste0("'", yyyymm.to.day(n[2]), 
        "'"), "", F, T), "#OLDAUM"))
    if (any(x == "Pseudo")) {
        cols <- c("FundId", "HFundId", "HSecurityId", "HoldingValue")
        z <- c(z, "", sql.Holdings.bulk("#NEWHLD", cols, yyyymm.to.day(n[1]), 
            "#NEWBMKHLD", "#NEWBMKAUM"), "")
        z <- c(z, "", sql.Holdings.bulk("#OLDHLD", cols, yyyymm.to.day(n[2]), 
            "#OLDBMKHLD", "#OLDBMKAUM"), "")
    }
    if (y != "All") 
        z <- c(z, "", "delete from #NEWHLD where", paste0("\t", 
            sql.in("HSecurityId", sql.RDSuniv(y), F)), "")
    h <- c(sql.drop(c("#DLYFLO", txt.expand(vec, c("HLD", "AUM"), 
        ""))), "", z, "")
    z <- c(sql.label(sql.FundHistory("", x, T, "FundId"), "his"), 
        "inner join", "#DLYFLO flo on flo.HFundId = his.HFundId")
    for (i in names(vec)) {
        y <- c(paste0(vec[i], "HLD t"), "inner join", "SecurityHistory id on id.HSecurityId = t.HSecurityId")
        y <- sql.label(sql.tbl("FundId, HFundId, t.HSecurityId, SecurityId, HoldingValue", 
            y), paste0(i, "1"))
        z <- c(z, "inner join", y, paste0("\ton ", i, "1.FundId = his.FundId"))
    }
    z <- c(z, "\tand o1.SecurityId = n1.SecurityId")
    for (i in names(vec)) z <- c(z, "inner join", paste0(vec[i], 
        "AUM ", i, "2 on ", i, "2.FundId = ", i, "1.FundId"))
    z <- list(PRE = h, FINAL = z)
    z
}

#' sql.1dFundCt
#' 
#' Generates FundCt, the ownership breadth measure set forth in Chen, Hong & Stein (2001)"Breadth of ownership and stock returns"
#' @param x = the YYYYMM for which you want data (known 26 days later)
#' @param y = a string vector of factors to be computed, the last element of which is the type of fund used.
#' @param n = any of StockFlows/China/Japan/CSI300/Energy
#' @param w = T/F depending on whether you are checking ftp
#' @keywords sql.1dFundCt
#' @export
#' @family sql

sql.1dFundCt <- function (x, y, n, w) 
{
    y <- sql.arguments(y)
    z <- x
    x <- sql.declare("@dy", "datetime", z)
    if (n != "All") 
        n <- list(A = sql.in("h.HSecurityId", sql.RDSuniv(n)))
    else n <- list()
    n[[char.ex.int(length(n) + 65)]] <- "flo.ReportDate = @dy"
    if (y$filter != "All") 
        n[[char.ex.int(length(n) + 65)]] <- sql.FundHistory.sf(y$filter)
    if (length(n) == 1) 
        n <- n[[1]]
    else n <- sql.and(n)
    if (w) {
        z <- c(paste0("ReportDate = '", z, "'"), "GeoId = GeographicFocusId", 
            "HSecurityId")
    }
    else {
        z <- "SecurityId"
    }
    for (j in y$factor) {
        if (j == "FundCt") {
            z <- c(z, paste(j, "count(distinct flo.HFundId)", 
                sep = " = "))
        }
        else {
            stop("Bad factor", j)
        }
    }
    h <- "datediff(month, h.ReportDate, flo.ReportDate) = case when day(flo.ReportDate) < 26 then 2 else 1 end"
    h <- c("inner join", paste("Holdings h on h.FundId = his.FundId", 
        h, sep = " and "))
    h <- c("DailyData flo", "inner join", "FundHistory his on his.HFundId = flo.HFundId", 
        h)
    if (!w) 
        h <- c(h, "inner join", "SecurityHistory id on id.HSecurityId = h.HSecurityId")
    w <- ifelse(w, "HSecurityId, GeographicFocusId", "SecurityId")
    z <- sql.tbl(z, h, n, w)
    z <- paste(c(x, sql.unbracket(z)), collapse = "\n")
    z
}

#' sql.1dFundRet
#' 
#' Generates the SQL query to get monthly AIS for countries
#' @param x = a list of fund identifiers
#' @keywords sql.1dFundRet
#' @export
#' @family sql

sql.1dFundRet <- function (x) 
{
    x <- sql.tbl("HFundId, FundId", "FundHistory", sql.in("FundId", 
        paste0("(", paste(x, collapse = ", "), ")")))
    x <- c("DailyData t1", "inner join", sql.label(x, "t2"), 
        "\ton t2.HFundId = t1.HFundId")
    z <- "DayEnding = convert(char(8), DayEnding, 112), FundId, FundRet = sum(PortfolioChange)/sum(AssetsStart)"
    z <- paste(sql.unbracket(sql.tbl(z, x, , "DayEnding, FundId", 
        "sum(AssetsStart) > 0")), collapse = "\n")
    z
}

#' sql.1dION
#' 
#' Generates the SQL query to get the data for 1dION$ & 1dION\%
#' @param x = data date (known two days later)
#' @param y = a vector of variables, the last element of which is ignored
#' @param n = the delay in knowing allocations
#' @param w = any of StockFlows/China/Japan/CSI300/Energy
#' @keywords sql.1dION
#' @export
#' @family sql

sql.1dION <- function (x, y, n, w) 
{
    m <- length(y)
    h <- vec.named(c("Flow * HoldingValue/AssetsEnd", "HoldingValue/AssetsEnd"), 
        c("ION$", "ION%"))
    z <- c("SecurityId", paste0("[", y[-m], "] ", sql.ION("Flow", 
        h[y[-m]])))
    y <- c(sql.label(sql.FundHistory("", y[m], T, "FundId"), 
        "t0"), "inner join", sql.MonthlyAlloc("@allocDt"))
    y <- c(sql.label(y, "t1"), "\ton t1.FundId = t0.FundId", 
        "inner join", sql.DailyFlo("@floDt"))
    y <- c(sql.label(y, "t2"), "\ton t2.HFundId = t0.HFundId", 
        "inner join", sql.MonthlyAssetsEnd("@allocDt"))
    y <- c(sql.label(y, "t3"), "\ton t3.HFundId = t1.HFundId", 
        "inner join", "SecurityHistory id", "\ton id.HSecurityId = t1.HSecurityId")
    x <- sql.declare(c("@floDt", "@allocDt"), "datetime", c(x, 
        yyyymm.to.day(yyyymmdd.to.AllocMo(x, n))))
    z <- paste(c(x, sql.unbracket(sql.tbl(z, y, sql.in("t1.HSecurityId", 
        sql.RDSuniv(w)), "SecurityId"))), collapse = "\n")
    z
}

#' sql.1mActPas.Ctry
#' 
#' Generates the SQL query to get monthly AIS for countries
#' @keywords sql.1mActPas.Ctry
#' @export
#' @family sql

sql.1mActPas.Ctry <- function () 
{
    rgn <- c(as.character(sql.1dFloMo.Ctry.List("Ctry")), "LK", 
        "VE")
    x <- paste0("avg(case when Idx = 'Y' then ", Ctry.info(rgn, 
        "AllocTable"), " else NULL end)")
    x <- sql.nonneg(x)
    x <- paste0("[", rgn, "] = avg(case when Idx = 'Y' then NULL else ", 
        Ctry.info(rgn, "AllocTable"), " end)/", x)
    z <- c("WeightDate = convert(char(6), WeightDate, 112)", 
        paste(x, "- 1"))
    x <- c(sql.label(sql.FundHistory("", c("CB", "E"), F, c("FundId", 
        "Idx")), "t1"), "inner join", "CountryAllocations t2 on t2.HFundId = t1.HFundId")
    z <- paste(sql.unbracket(sql.tbl(z, x, , "WeightDate")), 
        collapse = "\n")
    z
}

#' sql.1mActWt
#' 
#' Generates the SQL query to get the following active weights: a) EqlAct = equal weight average (incl 0) less the benchmark b) CapAct = fund weight average (incl 0) less the benchmark c) PosAct = fund weight average (incl 0) less the benchmark (positive flows only) d) NegAct = fund weight average (incl 0) less the benchmark (negative flows only)
#' @param x = the YYYYMM for which you want data (known 24 days later)
#' @param y = a string vector, the elements of which are: 1) FundId for the fund used as the benchmark 2) BenchIndexId of the benchmark
#' @keywords sql.1mActWt
#' @export
#' @family sql

sql.1mActWt <- function (x, y) 
{
    w <- c("Eql", "Cap", "Pos", "Neg")
    w <- c("SecurityId", paste0(w, "Act = ", w, "Wt - BmkWt"))
    z <- c("SecurityId", "EqlWt = sum(HoldingValue/AssetsEnd)/count(AssetsEnd)", 
        "CapWt = sum(HoldingValue)/sum(AssetsEnd)", "BmkWt = avg(BmkWt)")
    z <- c(z, "PosWt = sum(case when Flow > 0 then HoldingValue else NULL end)/sum(case when Flow > 0 then AssetsEnd else NULL end)")
    z <- c(z, "NegWt = sum(case when Flow < 0 then HoldingValue else NULL end)/sum(case when Flow < 0 then AssetsEnd else NULL end)")
    z <- sql.unbracket(sql.tbl(w, sql.label(sql.tbl(z, sql.1mActWt.underlying(0, 
        "\t"), , "SecurityId"), "t")))
    z <- paste(c(sql.declare(c("@fundId", "@bmkId", "@allocDt"), 
        c("int", "int", "datetime"), c(y, yyyymm.to.day(x))), 
        z), collapse = "\n")
    z
}

#' sql.1mActWt.underlying
#' 
#' Generates tail end of an SQL query
#' @param x = the month for which you want data (0 = latest, 1 = lagged one month, etc.)
#' @param y = characters you want put in front of the query
#' @keywords sql.1mActWt.underlying
#' @export
#' @family sql

sql.1mActWt.underlying <- function (x, y) 
{
    w <- list(A = paste("datediff(month, ReportDate, @allocDt) =", 
        x), B = sql.in("HFundId", sql.tbl("HFundId", "FundHistory", 
        "FundId = @fundId")))
    z <- c(sql.label(sql.tbl("HSecurityId, HoldingValue", "Holdings", 
        sql.and(w)), "t1"), "cross join")
    w <- list(A = paste("datediff(month, ReportDate, @allocDt) =", 
        x), B = sql.in("HFundId", sql.tbl("HFundId", "FundHistory", 
        "FundId = @fundId")))
    z <- c(z, sql.label(sql.tbl("AssetsEnd = sum(AssetsEnd)", 
        "MonthlyData", sql.and(w)), "t2"))
    z <- sql.label(paste0("\t", sql.tbl("HSecurityId, BmkWt = HoldingValue/AssetsEnd", 
        z)), "t0 -- Securities in the benchmark At Month End")
    w <- list(A = paste("datediff(month, ReportDate, @allocDt) =", 
        x))
    w[["B"]] <- sql.in("HFundId", sql.tbl("HFundId", "FundHistory", 
        "BenchIndexId = @bmkId"))
    w[["C"]] <- sql.in("HFundId", sql.Holdings(paste("datediff(month, ReportDate, @allocDt) =", 
        x), "HFundId"))
    w <- paste0("\t", sql.tbl("HFundId, Flow = sum(Flow), AssetsEnd = sum(AssetsEnd)", 
        "MonthlyData", sql.and(w), "HFundId", "sum(AssetsEnd) > 0"))
    z <- c(z, "cross join", sql.label(w, "t1 -- Funds Reporting Both Monthly Flows and Allocations with the right benchmark"))
    z <- c(z, "left join", paste0("\t", sql.Holdings(paste("datediff(month, ReportDate, @allocDt) =", 
        x), c("HSecurityId", "HFundId", "HoldingValue"))))
    z <- c(sql.label(z, "t2"), "\t\ton t2.HFundId = t1.HFundId and t2.HSecurityId = t0.HSecurityId", 
        "inner join")
    z <- c(z, "\tSecurityHistory id on id.HSecurityId = t0.HSecurityId")
    z <- paste0(y, z)
    z
}

#' sql.1mAllocD
#' 
#' Generates the SQL query to get the data for 1mAllocMo
#' @param x = the YYYYMM for which you want data (known 26 days later)
#' @param y = a string vector of factors to be computed, the last element of which is the type of fund used.
#' @param n = any of StockFlows/China/Japan/CSI300/Energy
#' @param w = T/F depending on whether you are checking ftp
#' @keywords sql.1mAllocD
#' @export
#' @family sql

sql.1mAllocD <- function (x, y, n, w) 
{
    y <- sql.arguments(y)
    h <- paste0("'", yyyymm.to.day(x), "'")
    h <- sql.label(sql.MonthlyAssetsEnd(h, "", F, F), "t1")
    h <- c(h, "inner join", sql.label(sql.FundHistory("", y$filter, 
        T, "FundId"), "his on his.HFundId = t1.HFundId"))
    h <- c(h, "inner join", "Holdings t2 on t2.HFundId = t1.HFundId")
    h <- c(h, "inner join", "SecurityHistory t3 on t3.HSecurityId = t2.HSecurityId")
    u <- sql.and(list(A = paste0("ReportDate = '", yyyymm.to.day(x), 
        "'"), B = "HoldingValue > 0"))
    z <- sql.into(sql.tbl(c("his.FundId", "SecurityId", "Allocation = HoldingValue/AssetsEnd"), 
        h, u), "#NEW")
    h <- paste0("'", yyyymm.to.day(yyyymm.lag(x)), "'")
    h <- sql.label(sql.MonthlyAssetsEnd(h, "", F, F), "t1")
    h <- c(h, "inner join", "Holdings t2 on t2.HFundId = t1.HFundId")
    h <- c(h, "inner join", "SecurityHistory t3 on t3.HSecurityId = t2.HSecurityId")
    u <- list(A = paste0("ReportDate = '", yyyymm.to.day(yyyymm.lag(x)), 
        "'"), B = "HoldingValue > 0")
    u[["C"]] <- sql.in("FundId", sql.tbl("FundId", "#NEW"))
    u <- sql.and(u)
    u <- sql.into(sql.tbl(c("FundId", "SecurityId", "Allocation = HoldingValue/AssetsEnd"), 
        h, u), "#OLD")
    z <- c(sql.drop(c("#NEW", "#OLD")), "", z, "", u)
    h <- paste(c(z, "", "delete from #NEW where FundId not in (select FundId from #OLD)"), 
        collapse = "\n")
    z <- "SecurityId = isnull(t1.SecurityId, t2.SecurityId)"
    if (w) 
        z <- c(paste("ReportDate = '", yyyymm.to.day(x), "'", 
            sep = ""), z)
    for (i in y$factor) z <- c(z, sql.1mAllocD.select(i))
    u <- c("#NEW t1", "full outer join", "#OLD t2 on t2.FundId = t1.FundId and t2.SecurityId = t1.SecurityId")
    z <- paste(sql.unbracket(sql.tbl(z, u, , "isnull(t1.SecurityId, t2.SecurityId)")), 
        collapse = "\n")
    z <- c(h, z)
    z
}

#' sql.1mAllocD.select
#' 
#' select term to compute <x>
#' @param x = the factor to be computed
#' @keywords sql.1mAllocD.select
#' @export
#' @family sql

sql.1mAllocD.select <- function (x) 
{
    if (x == "AllocDA") {
        z <- "count(isnull(t1.SecurityId, t2.SecurityId))"
    }
    else if (x == "AllocDInc") {
        z <- "sum(case when t1.Allocation > t2.Allocation then 1 else 0 end)"
    }
    else if (x == "AllocDDec") {
        z <- "sum(case when t2.Allocation > t1.Allocation then 1 else 0 end)"
    }
    else if (x == "AllocDAdd") {
        z <- "sum(case when t2.Allocation is null then 1 else 0 end)"
    }
    else if (x == "AllocDRem") {
        z <- "sum(case when t1.Allocation is null then 1 else 0 end)"
    }
    else stop("Bad Argument")
    z <- paste(x, z, sep = " = ")
    z
}

#' sql.1mAllocMo
#' 
#' Generates the SQL query to get the data for 1mAllocMo
#' @param x = the YYYYMM for which you want data (known 26 days later)
#' @param y = a string vector of factors to be computed, the last element of which is the type of fund used.
#' @param n = any of StockFlows/China/Japan/CSI300/Energy
#' @param w = T/F depending on whether you are checking ftp
#' @keywords sql.1mAllocMo
#' @export
#' @family sql

sql.1mAllocMo <- function (x, y, n, w) 
{
    y <- sql.arguments(y)
    if (w) {
        z <- c(paste("ReportDate = '", yyyymm.to.day(x), "'", 
            sep = ""), "n1.HSecurityId")
    }
    else {
        z <- "n1.SecurityId"
    }
    for (i in y$factor) z <- c(z, sql.1mAllocMo.select(i, any(y$filter == 
        "Num")))
    h <- sql.1mAllocMo.underlying.pre(y$filter, yyyymm.to.day(x), 
        yyyymm.to.day(yyyymm.lag(x)))
    y <- sql.1mAllocMo.underlying.from(y$filter)
    if (w) {
        if (n == "All") {
            z <- sql.tbl(z, y, , "n1.HSecurityId")
        }
        else {
            z <- sql.tbl(z, y, sql.in("n1.HSecurityId", sql.RDSuniv(n)), 
                "n1.HSecurityId")
        }
    }
    else {
        y <- c(y, "inner join", "SecurityHistory id on id.HSecurityId = n1.HSecurityId")
        z <- sql.tbl(z, y, sql.in("n1.HSecurityId", sql.RDSuniv(n)), 
            "n1.SecurityId")
    }
    z <- paste(sql.unbracket(z), collapse = "\n")
    z <- c(paste(h, collapse = "\n"), z)
    z
}

#' sql.1mAllocMo.select
#' 
#' select term to compute <x>
#' @param x = the factor to be computed
#' @param y = T/F depending on whether only the numerator is wanted
#' @keywords sql.1mAllocMo.select
#' @export
#' @family sql

sql.1mAllocMo.select <- function (x, y) 
{
    if (x == "AllocMo") {
        z <- "2 * sum((AssetsStart + AssetsEnd) * (n1.HoldingValue/AssetsEnd - o1.HoldingValue/AssetsStart))"
        if (!y) 
            z <- paste0(z, "/", sql.nonneg("sum((AssetsStart + AssetsEnd) * (n1.HoldingValue/AssetsEnd + o1.HoldingValue/AssetsStart))"))
    }
    else if (x == "AllocDiff" & y) {
        z <- "sum((AssetsStart + AssetsEnd) * sign(n1.HoldingValue/AssetsEnd - o1.HoldingValue/AssetsStart))"
    }
    else if (x == "AllocDiff" & !y) {
        z <- sql.Diff("AssetsStart + AssetsEnd", "n1.HoldingValue/AssetsEnd - o1.HoldingValue/AssetsStart")
        z <- txt.right(z, nchar(z) - nchar("= "))
    }
    else if (x == "AllocTrend") {
        z <- "sum((AssetsStart + AssetsEnd) * (n1.HoldingValue/AssetsEnd - o1.HoldingValue/AssetsStart))"
        if (!y) 
            z <- paste0(z, "/", sql.nonneg("sum(abs((AssetsStart + AssetsEnd) * (n1.HoldingValue/AssetsEnd - o1.HoldingValue/AssetsStart)))"))
    }
    else stop("Bad Argument")
    z <- paste(x, z, sep = " = ")
    z
}

#' sql.1mAllocMo.underlying.from
#' 
#' FROM for 1mAllocMo
#' @param x = filter list
#' @keywords sql.1mAllocMo.underlying.from
#' @export
#' @family sql

sql.1mAllocMo.underlying.from <- function (x) 
{
    z <- c("#MOFLOW t", "inner join", sql.label(sql.FundHistory("", 
        x, T, "FundId"), "his"), "\ton his.HFundId = t.HFundId")
    y <- c("#NEWHLD t", "inner join", "SecurityHistory id on id.HSecurityId = t.HSecurityId")
    y <- sql.label(sql.tbl("FundId, HFundId, t.HSecurityId, SecurityId, HoldingValue", 
        y), "n1")
    z <- c(z, "inner join", y, "\ton n1.FundId = his.FundId")
    y <- c("#OLDHLD t", "inner join", "SecurityHistory id on id.HSecurityId = t.HSecurityId")
    y <- sql.label(sql.tbl("FundId, HFundId, t.HSecurityId, SecurityId, HoldingValue", 
        y), "o1")
    z <- c(z, "inner join", y, "\ton o1.FundId = his.FundId and o1.SecurityId = n1.SecurityId")
    z
}

#' sql.1mAllocMo.underlying.pre
#' 
#' FROM and WHERE for 1mAllocMo
#' @param x = filter list
#' @param y = date for new holdings in YYYYMMDD
#' @param n = date for old holdings in YYYYMMDD
#' @keywords sql.1mAllocMo.underlying.pre
#' @export
#' @family sql

sql.1mAllocMo.underlying.pre <- function (x, y, n) 
{
    z <- sql.into(sql.MonthlyAssetsEnd(paste0("'", y, "'"), "", 
        T), "#MOFLOW")
    if (any(x == "Up")) 
        z <- c(z, "\tand", "\t\tsum(AssetsEnd - AssetsStart - Flow) > 0")
    z <- c(z, "", sql.into(sql.MonthlyAlloc(paste0("'", y, "'")), 
        "#NEWHLD"))
    z <- c(z, "", sql.into(sql.MonthlyAlloc(paste0("'", n, "'")), 
        "#OLDHLD"))
    if (any(x == "Pseudo")) {
        cols <- c("FundId", "HFundId", "HSecurityId", "HoldingValue")
        z <- c(z, "", sql.Holdings.bulk("#NEWHLD", cols, y, "#BMKHLD", 
            "#BMKAUM"), "")
        z <- c(z, "", sql.Holdings.bulk("#OLDHLD", cols, n, "#OLDBMKHLD", 
            "#OLDBMKAUM"), "")
    }
    z <- c(sql.drop(c("#MOFLOW", "#NEWHLD", "#OLDHLD")), "", 
        z, "")
    z
}

#' sql.1mAllocSkew
#' 
#' Generates the SQL query to get the data for 1mAllocTrend
#' @param x = the YYYYMM for which you want data (known 26 days later)
#' @param y = a string vector of factors to be computed, the last element of which is the type of fund used.
#' @param n = any of StockFlows/China/Japan/CSI300/Energy
#' @param w = T/F depending on whether you are checking ftp
#' @keywords sql.1mAllocSkew
#' @export
#' @family sql

sql.1mAllocSkew <- function (x, y, n, w) 
{
    y <- sql.arguments(y)
    x <- yyyymm.to.day(x)
    cols <- c("HFundId", "FundId", "HSecurityId", "HoldingValue")
    z <- sql.into(sql.tbl("HFundId, PortVal = sum(AssetsEnd)", 
        "MonthlyData", paste0("ReportDate = '", x, "'"), "HFundId", 
        "sum(AssetsEnd) > 0"), "#AUM")
    z <- c(sql.drop(c("#AUM", "#HLD")), "", z, "")
    h <- paste0("ReportDate = '", x, "'")
    if (n != "All") 
        h <- sql.and(list(A = h, B = sql.in("HSecurityId", sql.RDSuniv(n))))
    z <- c(z, sql.Holdings(h, cols, "#HLD"), "")
    if (any(y$filter == "Pseudo")) 
        z <- c(z, sql.Holdings.bulk("#HLD", cols, x, "#BMKHLD", 
            "#BMKAUM"), "")
    if (any(y$filter == "Up")) {
        h <- sql.tbl("HFundId", "MonthlyData", paste0("ReportDate = '", 
            x, "'"), "HFundId", "sum(AssetsEnd - AssetsStart - Flow) < 0")
        z <- c(z, c("delete from #HLD where", sql.in("HFundId", 
            h)), "")
    }
    if (w) {
        x <- c(paste("ReportDate = '", x, "'", sep = ""), "n1.HSecurityId")
    }
    else {
        x <- "SecurityId"
    }
    if (length(y$factor) != 1 | y$factor[1] != "AllocSkew") 
        stop("Bad Argument")
    h <- "AllocSkew = sum(PortVal * sign(FundWtdExcl0 - n1.HoldingValue/PortVal))"
    x <- c(x, paste0(h, "/", sql.nonneg("sum(PortVal)")))
    h <- sql.1mAllocSkew.topline.from(y$filter)
    if (!w) 
        h <- c(h, "inner join", "SecurityHistory id on id.HSecurityId = n1.HSecurityId")
    w <- ifelse(w, "n1.HSecurityId", "SecurityId")
    z <- c(paste(z, collapse = "\n"), paste(sql.unbracket(sql.tbl(x, 
        h, , w)), collapse = "\n"))
    z
}

#' sql.1mAllocSkew.topline.from
#' 
#' from part of the final select statement in 1mAllocTrend
#' @param x = filter to be applied All/Act/Pas/Mutual/Etf/xJP
#' @keywords sql.1mAllocSkew.topline.from
#' @export
#' @family sql

sql.1mAllocSkew.topline.from <- function (x) 
{
    z <- c("HSecurityId", "GeographicFocusId", "FundWtdExcl0 = sum(HoldingValue)/sum(PortVal)")
    y <- c("#AUM t3", "inner join", sql.label(sql.FundHistory("", 
        x, T, c("FundId", "GeographicFocusId")), "t1"), "\ton t1.HFundId = t3.HFundId")
    y <- c(y, "inner join", "#HLD t2 on t2.FundId = t1.FundId")
    z <- sql.tbl(z, y, , "HSecurityId, GeographicFocusId")
    z <- c("inner join", sql.label(z, "mnW"), "\ton mnW.GeographicFocusId = his.GeographicFocusId and mnW.HSecurityId = n1.HSecurityId")
    z <- c("inner join", "#HLD n1 on n1.FundId = his.FundId", 
        z)
    z <- c(sql.label(sql.FundHistory("", x, T, c("FundId", "GeographicFocusId")), 
        "his"), "\ton his.HFundId = t.HFundId", z)
    z <- c("#AUM t", "inner join", z)
    z
}

#' sql.1mChActWt
#' 
#' Generates the SQL query to get the following active weights: a) EqlChAct = equal weight average change in active weight b) BegChAct = beginning-of-period-asset weighted change in active weight c) EndChAct = end-of-period-asset weighted change in active weight d) BegPosChAct = beginning-of-period-asset weighted change in active weight (positive flows only) e) EndPosChAct = end-of-period-asset weighted change in active weight (positive flows only) f) BegNegChAct = beginning-of-period-asset weighted change in active weight (negative flows only) g) EndNegChAct = end-of-period-asset weighted change in active weight (negative flows only)
#' @param x = the YYYYMM for which you want data (known 24 days later)
#' @param y = a string vector, the elements of which are: 1) FundId for the fund used as the benchmark 2) BenchIndexId of the benchmark
#' @keywords sql.1mChActWt
#' @export
#' @family sql

sql.1mChActWt <- function (x, y) 
{
    x <- sql.declare(c("@fundId", "@bmkId", "@allocDt"), c("int", 
        "int", "datetime"), c(y, yyyymm.to.day(x)))
    w <- sql.tbl("SecurityId, t1.HFundId, ActWt = isnull(HoldingValue, 0)/AssetsEnd - BmkWt, AssetsEnd, Flow", 
        sql.1mActWt.underlying(0, ""))
    z <- c("FundHistory t1", "inner join", sql.label(w, "t2"), 
        "\ton t2.HFundId = t1.HFundId", "inner join", "FundHistory t3")
    w <- sql.tbl("SecurityId, t1.HFundId, ActWt = isnull(HoldingValue, 0)/AssetsEnd - BmkWt, AssetsEnd", 
        sql.1mActWt.underlying(1, ""))
    w <- c(z, "\ton t3.FundId = t1.FundId", "inner join", sql.label(w, 
        "t4"), "\ton t4.HFundId = t3.HFundId and t4.SecurityId = t2.SecurityId")
    z <- c("t2.SecurityId", "EqlChAct = avg(t2.ActWt - t4.ActWt)")
    z <- c(z, "BegChAct = sum(t4.AssetsEnd * (t2.ActWt - t4.ActWt))/sum(t4.AssetsEnd)")
    z <- c(z, "EndChAct = sum(t2.AssetsEnd * (t2.ActWt - t4.ActWt))/sum(t2.AssetsEnd)")
    z <- c(z, "BegPosChAct = sum(case when Flow > 0 then t4.AssetsEnd else NULL end * (t2.ActWt - t4.ActWt))/sum(case when Flow > 0 then t4.AssetsEnd else NULL end)")
    z <- c(z, "EndPosChAct = sum(case when Flow > 0 then t2.AssetsEnd else NULL end * (t2.ActWt - t4.ActWt))/sum(case when Flow > 0 then t2.AssetsEnd else NULL end)")
    z <- c(z, "BegNegChAct = sum(case when Flow < 0 then t4.AssetsEnd else NULL end * (t2.ActWt - t4.ActWt))/sum(case when Flow < 0 then t4.AssetsEnd else NULL end)")
    z <- c(z, "EndNegChAct = sum(case when Flow < 0 then t2.AssetsEnd else NULL end * (t2.ActWt - t4.ActWt))/sum(case when Flow < 0 then t2.AssetsEnd else NULL end)")
    z <- paste(c(x, "", sql.unbracket(sql.tbl(z, w, , "t2.SecurityId"))), 
        collapse = "\n")
    z
}

#' sql.1mFloMo
#' 
#' Generates the SQL query to get the data for 1mFloMo for individual stocks
#' @param x = the YYYYMM for which you want data (known 16 days later)
#' @param y = a string vector of factors to be computed, the last element of which is the type of fund used
#' @param n = any of StockFlows/China/Japan/CSI300/Energy
#' @param w = T/F depending on whether you are checking ftp
#' @keywords sql.1mFloMo
#' @export
#' @family sql

sql.1mFloMo <- function (x, y, n, w) 
{
    z <- sql.tbl("ReportDate, HFundId, AssetsEnd = sum(AssetsEnd)", 
        "MonthlyData", "ReportDate = @dy", "ReportDate, HFundId", 
        "sum(AssetsEnd) > 0")
    z <- c(sql.label(z, "t0"), "inner join", sql.label(sql.tbl("ReportDate, HFundId, Flow, AssetsStart", 
        "MonthlyData", "ReportDate = @dy"), "t1"))
    z <- c(z, "\ton t1.HFundId = t0.HFundId", "inner join", sql.label(sql.1dFloMo.filter(y, 
        w), "t3"), "\ton t3.HFundId = t1.HFundId")
    z <- c(z, "inner join", "Holdings t2 on t3.FundId = t2.FundId and t2.ReportDate = t1.ReportDate")
    if (!w) 
        z <- c(z, "inner join", "SecurityHistory id on id.HSecurityId = t2.HSecurityId")
    grp <- sql.1dFloMo.grp(y, w)
    y <- sql.1dFloMo.select.wrapper(yyyymm.to.day(x), y, w)
    if (n == "All") {
        z <- sql.tbl(y, z, , grp, "sum(HoldingValue/AssetsEnd) > 0")
    }
    else {
        z <- sql.tbl(y, z, sql.in("t2.HSecurityId", sql.RDSuniv(n)), 
            grp, "sum(HoldingValue/AssetsEnd) > 0")
    }
    z <- paste(c(sql.declare("@dy", "datetime", yyyymm.to.day(x)), 
        sql.unbracket(z)), collapse = "\n")
    z
}

#' sql.1mFundCt
#' 
#' Generates FundCt, the ownership breadth measure set forth in Chen, Hong & Stein (2001)"Breadth of ownership and stock returns"
#' @param x = the YYYYMM for which you want data (known 26 days later)
#' @param y = a string vector of factors to be computed, the last element of which is the type of fund used.
#' @param n = any of StockFlows/China/Japan/CSI300/Energy
#' @param w = T/F depending on whether you are checking ftp
#' @keywords sql.1mFundCt
#' @export
#' @family sql

sql.1mFundCt <- function (x, y, n, w) 
{
    y <- sql.arguments(y)
    z <- yyyymm.to.day(x)
    x <- sql.declare("@dy", "datetime", z)
    if (n != "All") 
        n <- list(A = sql.in("h.HSecurityId", sql.RDSuniv(n)))
    else n <- list()
    n[[char.ex.int(length(n) + 65)]] <- "ReportDate = @dy"
    if (y$filter != "All") 
        n[[char.ex.int(length(n) + 65)]] <- sql.FundHistory.sf(y$filter)
    n[[char.ex.int(length(n) + 65)]] <- sql.in("his.HFundId", 
        sql.tbl("HFundId", "MonthlyData", "ReportDate = @dy"))
    n <- sql.and(n)
    if (w) {
        z <- c(paste0("ReportDate = '", z, "'"), "GeoId = GeographicFocusId", 
            "HSecurityId")
    }
    else {
        z <- "SecurityId"
    }
    for (j in y$factor) {
        if (j == "FundCt") {
            z <- c(z, paste(j, "count(h.HFundId)", sep = " = "))
        }
        else if (j == "HoldSum") {
            z <- c(z, paste(j, "sum(HoldingValue)", sep = " = "))
        }
        else {
            stop("Bad factor", j)
        }
    }
    h <- c("Holdings h", "inner join", "FundHistory his on his.FundId = h.FundId")
    if (!w) 
        h <- c(h, "inner join", "SecurityHistory id on id.HSecurityId = h.HSecurityId")
    w <- ifelse(w, "HSecurityId, GeographicFocusId", "SecurityId")
    z <- sql.tbl(z, h, n, w)
    z <- paste(c(x, sql.unbracket(z)), collapse = "\n")
    z
}

#' sql.1wFlow.Corp
#' 
#' Generates the SQL query to get weekly corporate flow ($MM)
#' @param x = YYYYMMDD from which flows are to be computed
#' @keywords sql.1wFlow.Corp
#' @export
#' @family sql

sql.1wFlow.Corp <- function (x) 
{
    h <- mat.read(parameters("classif-StyleSector"))
    h <- map.rname(h, c(136, 133, 140, 135, 132, 139, 142, 125))
    h$Domicile <- ifelse(dimnames(h)[[1]] == 125, "US", NA)
    z <- vec.named(paste("StyleSector", dimnames(h)[[1]], sep = " = "), 
        h[, "Abbrv"])
    z[!is.na(h$Domicile)] <- paste(z[!is.na(h$Domicile)], "Domicile = 'US'", 
        sep = " and ")
    names(z)[!is.na(h$Domicile)] <- paste(names(z)[!is.na(h$Domicile)], 
        "US")
    z <- paste0("[", names(z), "] = sum(case when ", z, " then Flow else NULL end)")
    z <- c("WeekEnding = convert(char(8), WeekEnding, 112)", 
        z)
    y <- list(A = "FundType = 'B'", B = "GeographicFocus = 77")
    y[["C"]] <- sql.in("StyleSector", paste0("(", paste(dimnames(h)[[1]], 
        collapse = ", "), ")"))
    y[["D"]] <- paste0("WeekEnding >= '", x, "'")
    z <- sql.tbl(z, c("WeeklyData t1", "inner join", "FundHistory t2 on t2.HFundId = t1.HFundId"), 
        sql.and(y), "WeekEnding")
    z <- paste(sql.unbracket(z), collapse = "\n")
    z
}

#' sql.ActWtDiff2
#' 
#' ActWtDiff2 on R1 Materials for positioning
#' @param x = flow date
#' @keywords sql.ActWtDiff2
#' @export
#' @family sql

sql.ActWtDiff2 <- function (x) 
{
    mo.end <- yyyymmdd.to.AllocMo(x, 26)
    w <- sql.and(list(A = "StyleSectorId = 101", B = "GeographicFocusId = 77", 
        C = "[Index] = 1"))
    w <- sql.in("HFundId", sql.tbl("HFundId", "FundHistory", 
        w))
    w <- list(A = w, B = paste0("ReportDate = '", yyyymm.to.day(mo.end), 
        "'"))
    z <- sql.in("HFundId", sql.tbl("HFundId", "FundHistory", 
        "FundId = 5152"))
    z <- sql.and(list(A = z, B = paste0("ReportDate = '", yyyymm.to.day(mo.end), 
        "'")))
    z <- sql.tbl("HSecurityId", "Holdings", z, "HSecurityId")
    w[["C"]] <- sql.in("HSecurityId", z)
    w <- sql.tbl("HSecurityId", "Holdings", sql.and(w), "HSecurityId")
    z <- sql.1dActWtTrend.underlying(x, "All", w)
    z <- c(z, sql.1dActWtTrend.topline("ActWtDiff2", , F))
    z
}

#' sql.AggrAllocations
#' 
#' Generates the SQL query to get aggregate allocations for StockFlows
#' @param x = one of FwtdIn0/FwtdEx0/SwtdIn0/SwtdEx0
#' @param y = the name of the table containing Holdings (e.g. "#HLDGS")
#' @param n = a date of the form "@@allocDt" or "'20151231'"
#' @param w = the grouping column (e.g. "GeographicFocusId")
#' @param h = the temp table for output
#' @keywords sql.AggrAllocations
#' @export
#' @family sql

sql.AggrAllocations <- function (x, y, n, w, h) 
{
    z <- sql.tbl("ReportDate, HSecurityId", y, paste("ReportDate =", 
        n), "ReportDate, HSecurityId")
    z <- sql.label(z, "t0 -- Securities Held At Month End")
    tmp <- sql.and(list(A = "h.ReportDate = MonthlyData.ReportDate", 
        B = "h.HFundId = MonthlyData.HFundId"))
    tmp <- sql.exists(sql.tbl("ReportDate, HFundId", paste(y, 
        "h"), tmp))
    n <- sql.and(list(A = paste("ReportDate =", n), B = tmp))
    n <- sql.tbl("HFundId, AssetsEnd = sum(AssetsEnd)", "MonthlyData", 
        n, "HFundId", "sum(AssetsEnd) > 0")
    z <- c(z, "cross join", sql.label(n, "t1 -- Funds Reporting Both Monthly Flows and Allocations"), 
        "inner join")
    z <- c(z, "FundHistory t2 on t1.HFundId = t2.HFundId", "left join", 
        paste(y, "t3"))
    n <- c(z, "\ton t3.HFundId = t1.HFundId and t3.HSecurityId = t0.HSecurityId and t3.ReportDate = t0.ReportDate")
    z <- c("t0.HSecurityId", w, sql.TopDownAllocs.items(x))
    z <- sql.into(sql.tbl(z, n, , paste("t0.HSecurityId", w, 
        sep = ", "), "sum(HoldingValue) > 0"), h)
    z
}

#' sql.AllocTbl
#' 
#' Finds the relevant allocation table
#' @param x = one of Ctry/FX/Sector
#' @keywords sql.AllocTbl
#' @export
#' @family sql

sql.AllocTbl <- function (x) 
{
    ifelse(x == "Sector", "SectorAllocations", "CountryAllocations")
}

#' sql.and
#' 
#' and segment of an SQL statement
#' @param x = list object of string vectors
#' @param y = prependix
#' @param n = logical operator to use
#' @keywords sql.and
#' @export
#' @family sql

sql.and <- function (x, y = "", n = "and") 
{
    m <- length(x)
    if (m > 1) {
        fcn <- function(x) c(n, paste0(y, "\t", x))
        z <- unlist(lapply(x, fcn))[-1]
    }
    else {
        z <- x[[1]]
    }
    z
}

#' sql.arguments
#' 
#' splits <x> into factor and filters
#' @param x = a string vector of variables to build with the last elements specifying the type of funds to use
#' @keywords sql.arguments
#' @export
#' @family sql

sql.arguments <- function (x) 
{
    filters <- c("All", "Act", "Pas", "Etf", "Mutual", "Num", 
        "Pseudo", "Up", "xJP", "JP", "CBE")
    m <- length(x)
    while (any(x[m] == filters)) m <- m - 1
    if (m == length(x)) 
        x <- c(x, "All")
    w <- seq(1, length(x)) > m
    z <- list(factor = x[!w], filter = x[w])
    z
}

#' sql.bcp
#' 
#' code to bcp data out of server
#' @param x = SQL table to perform the bulk copy from
#' @param y = the location of the output file
#' @param n = One of "StockFlows", "Quant", "QuantSF" or "Regular"
#' @param w = the database on which <x> resides
#' @param h = the owner of <x>
#' @keywords sql.bcp
#' @export
#' @family sql

sql.bcp <- function (x, y, n = "Quant", w = "EPFRUI", h = "dbo") 
{
    h <- paste(w, h, x, sep = ".")
    x <- parameters("SQL")
    x <- mat.read(x, "\t")
    z <- is.element(dimnames(x)[[1]], n)
    if (sum(z) != 1) 
        stop("Bad type", n)
    if (sum(z) == 1) {
        z <- paste("-S", x[, "DB"], "-U", x[, "UID"], "-P", x[, 
            "PWD"])[z]
        z <- paste("bcp", h, "out", y, z, "-c")
    }
    z
}

#' sql.connect
#' 
#' Opens an SQL connection
#' @param x = One of "StockFlows", "Quant" or "Regular"
#' @keywords sql.connect
#' @export
#' @family sql
#' @@importFrom RODBC odbcDriverConnect

sql.connect <- function (x) 
{
    y <- mat.read(parameters("SQL"), "\t")
    if (all(dimnames(y)[[1]] != x)) 
        stop("Bad SQL connection!")
    z <- t(y)[c("PWD", "UID", "DSN"), x]
    z["Connection Timeout"] <- "0"
    z <- paste(paste(names(z), z, sep = "="), collapse = ";")
    z <- odbcDriverConnect(z, readOnlyOptimize = T)
    z
}

#' sql.cross.border
#' 
#' Returns a list object of cross-border Geo. Foci and their names
#' @param x = T/F depending on whether StockFlows data are being used
#' @keywords sql.cross.border
#' @export
#' @family sql

sql.cross.border <- function (x) 
{
    y <- parameters("classif-GeoId")
    y <- mat.read(y, "\t")
    y <- y[is.element(y$xBord, 1), ]
    if (x) 
        x <- "GeographicFocusId"
    else x <- "GeographicFocus"
    z <- paste(x, "=", paste(dimnames(y)[[1]], y[, "Name"], sep = "--"))
    z <- split(z, y[, "Abbrv"])
    z
}

#' sql.DailyFlo
#' 
#' Generates the SQL query to get the data for daily Flow
#' @param x = the date for which you want flows (known one day later)
#' @param y = the temp table to hold output
#' @param n = T/F depending on whether StockFlows data are being used
#' @keywords sql.DailyFlo
#' @export
#' @family sql

sql.DailyFlo <- function (x, y, n = T) 
{
    z <- c("HFundId, Flow = sum(Flow), AssetsStart = sum(AssetsStart)")
    z <- sql.tbl(z, "DailyData", paste(ifelse(n, "ReportDate", 
        "DayEnding"), "=", x), "HFundId")
    if (!missing(y)) 
        z <- sql.into(z, y)
    z
}

#' sql.datediff
#' 
#' Before <n>, falls back two else one month
#' @param x = column in the monthly table
#' @param y = column in the daily table
#' @param n = calendar day on which previous month's data available
#' @keywords sql.datediff
#' @export
#' @family sql

sql.datediff <- function (x, y, n) 
{
    paste0("datediff(month, ", x, ", ", y, ") = case when day(", 
        y, ") < ", n, " then 2 else 1 end")
}

#' sql.declare
#' 
#' declare statement
#' @param x = variable names
#' @param y = variable types
#' @param n = values
#' @keywords sql.declare
#' @export
#' @family sql

sql.declare <- function (x, y, n) 
{
    c(paste("declare", x, y), paste0("set ", x, " = '", n, "'"))
}

#' sql.Diff
#' 
#' SQL statement for diffusion
#' @param x = vector
#' @param y = isomekic vector
#' @keywords sql.Diff
#' @export
#' @family sql

sql.Diff <- function (x, y) 
{
    paste0("= sum((", x, ") * cast(sign(", y, ") as float))", 
        "/", sql.nonneg(paste0("sum(abs(", x, "))")))
}

#' sql.Dispersion
#' 
#' Generates the dispersion measure set forth in Jiang & Sun (2011) "Dispersion in beliefs among active mutual funds and the cross-section of stock returns"
#' @param x = the YYYYMM for which you want data (known 26 days later)
#' @param y = a string vector of factors to be computed, the last element of which is the type of fund used.
#' @param n = any of StockFlows/China/Japan/CSI300/Energy
#' @param w = T/F depending on whether you are checking ftp
#' @keywords sql.Dispersion
#' @export
#' @family sql

sql.Dispersion <- function (x, y, n, w) 
{
    x <- paste0("ReportDate = '", yyyymm.to.day(x), "'")
    z <- sql.drop(c("#HLD", "#BMK"))
    z <- c(z, "", "create table #BMK (BenchIndexId int not null, HSecurityId int not null, HoldingValue float not null)")
    z <- c(z, "create clustered index TempRandomBmkIndex ON #BMK(BenchIndexId, HSecurityId)")
    u <- sql.and(list(A = x, B = "[Index] = 1"))
    h <- "Holdings t1 inner join FundHistory t2 on t2.HFundId = t1.HFundId"
    h <- sql.tbl("BenchIndexId, HSecurityId, HoldingValue = sum(HoldingValue)", 
        h, u, "BenchIndexId, HSecurityId", "sum(HoldingValue) > 0")
    z <- c(z, "insert into #BMK", sql.unbracket(h))
    h <- sql.label(sql.tbl("BenchIndexId, AUM = sum(HoldingValue)", 
        "#BMK", , "BenchIndexId", "sum(HoldingValue) > 0"), "t")
    h <- sql.unbracket(sql.tbl("HoldingValue = HoldingValue/AUM", 
        h, "#BMK.BenchIndexId = t.BenchIndexId"))
    z <- c(z, "", "update #BMK set", h[-1])
    z <- c(z, "", "create table #HLD (HFundId int not null, HSecurityId int not null, HoldingValue float not null)")
    z <- c(z, "create clustered index TempRandomHldIndex ON #HLD(HFundId, HSecurityId)")
    u <- "BenchIndexId in (select BenchIndexId from #BMK)"
    u <- sql.and(list(A = x, B = "[Index] = 0", C = u, D = "HoldingValue > 0"))
    h <- "Holdings t1 inner join FundHistory t2 on t2.HFundId = t1.HFundId"
    h <- sql.tbl("t1.HFundId, HSecurityId, HoldingValue", h, 
        u)
    z <- c(z, "insert into #HLD", sql.unbracket(h))
    h <- sql.label(sql.tbl("HFundId, AUM = sum(HoldingValue)", 
        "#HLD", , "HFundId", "sum(HoldingValue) > 0"), "t")
    h <- sql.unbracket(sql.tbl("HoldingValue = HoldingValue/AUM", 
        h, "#HLD.HFundId = t.HFundId"))
    z <- c(z, "", "update #HLD set", h[-1])
    h <- c("FundHistory t1", "inner join", "#BMK t2 on t2.BenchIndexId = t1.BenchIndexId")
    u <- "#HLD.HFundId = t1.HFundId and #HLD.HSecurityId = t2.HSecurityId"
    h <- sql.unbracket(sql.tbl("HoldingValue = #HLD.HoldingValue - t2.HoldingValue", 
        h, u))
    z <- c(z, "", "update #HLD set", h[-1])
    u <- sql.tbl("HFundId, HSecurityId", "#HLD t", "t1.HFundId = t.HFundId and t2.HSecurityId = t.HSecurityId")
    u <- sql.and(list(A = sql.exists(u, F), B = "t1.HFundId in (select HFundId from #HLD)"))
    h <- c("FundHistory t1", "inner join", "#BMK t2 on t2.BenchIndexId = t1.BenchIndexId")
    h <- sql.tbl("HFundId, HSecurityId, -HoldingValue", h, u)
    z <- c(z, "", "insert into #HLD", sql.unbracket(h))
    if (n != "All") 
        z <- c(z, "", "delete from #HLD where", sql.in("HSecurityId", 
            sql.RDSuniv(n), F))
    z <- paste(z, collapse = "\n")
    h <- "#HLD hld"
    if (w) {
        u <- c(x, "HSecurityId")
    }
    else {
        h <- c(h, "inner join", "SecurityHistory id on id.HSecurityId = hld.HSecurityId")
        u <- "SecurityId"
    }
    w <- ifelse(w, "HSecurityId", "SecurityId")
    u <- c(u, "Dispersion = 10000 * (avg(square(HoldingValue)) - square(avg(HoldingValue)))")
    z <- c(z, paste(sql.unbracket(sql.tbl(u, h, , w)), collapse = "\n"))
    z
}

#' sql.drop
#' 
#' drops the elements of <x> if they exist
#' @param x = a vector of temp-table names
#' @keywords sql.drop
#' @export
#' @family sql

sql.drop <- function (x) 
{
    paste0("IF OBJECT_ID('tempdb..", x, "') IS NOT NULL DROP TABLE ", 
        x)
}

#' sql.exists
#' 
#' <x> in <y> if <n> or <x> not in <y> otherwise
#' @param x = SQL statement
#' @param y = T/F depending on whether exists/not exists
#' @keywords sql.exists
#' @export
#' @family sql

sql.exists <- function (x, y = T) 
{
    c(ifelse(y, "exists", "not exists"), paste0("\t", x))
}

#' sql.FloMo.Funds
#' 
#' Generates the SQL query to get monthly/daily data for Funds
#' @param x = the month/day for which you want \% flow, \% portfolio change, & assets end
#' @keywords sql.FloMo.Funds
#' @export
#' @family sql

sql.FloMo.Funds <- function (x) 
{
    if (nchar(x) == 6) {
        sql.table <- "MonthlyData"
        flo.dt <- yyyymm.to.day(x)
        dt.col <- "MonthEnding"
    }
    else {
        sql.table <- "DailyData"
        flo.dt <- x
        dt.col <- "DayEnding"
    }
    flo.dt <- sql.declare("@floDt", "datetime", flo.dt)
    z <- c("SecurityId = FundId", "PortfolioChangePct = 100 * sum(PortfolioChange)/sum(AssetsStart)")
    z <- c(z, "FlowPct = 100 * sum(Flow)/sum(AssetsStart)", "AssetsEnd = sum(AssetsEnd)")
    x <- c(sql.label(sql.table, "t1"), "inner join", "FundHistory t2 on t1.HFundId = t2.HFundId")
    z <- paste(sql.unbracket(sql.tbl(z, x, paste(dt.col, "= @floDt"), 
        "FundId", "sum(AssetsStart) > 0")), collapse = "\n")
    z
}

#' sql.floTbl.to.Col
#' 
#' derived the appropriate date column from the flow table name
#' @param x = one of DailyData/WeeklyData/MonthlyData
#' @param y = T/F depending on whether you want the date formatted.
#' @keywords sql.floTbl.to.Col
#' @export
#' @family sql

sql.floTbl.to.Col <- function (x, y) 
{
    n <- vec.named(c(8, 8, 6), c("DailyData", "WeeklyData", "MonthlyData"))
    z <- vec.named(c("DayEnding", "WeekEnding", "MonthEnding"), 
        names(n))
    z <- as.character(z[x])
    n <- as.numeric(n[x])
    if (y) 
        z <- paste0(z, " = convert(char(", n, "), ", z, ", 112)")
    z
}

#' sql.FundHistory
#' 
#' SQL query to restrict to Global and Regional equity funds
#' @param x = characters to place before each line of the SQL query part
#' @param y = a vector of filters
#' @param n = T/F depending on whether StockFlows data are being used
#' @param w = columns needed in addition to HFundId
#' @keywords sql.FundHistory
#' @export
#' @family sql

sql.FundHistory <- function (x, y, n, w) 
{
    if (length(y) == 1) 
        y <- as.character(txt.parse(y, ","))
    if (y[1] == "All" & n & length(y) > 1) 
        y <- y[-1]
    if (any(y[1] == c("Pseudo", "Up"))) 
        y <- ifelse(n, "All", "E")
    if (missing(w)) 
        w <- "HFundId"
    else w <- c("HFundId", w)
    if (y[1] == "All" & n) {
        z <- sql.tbl(w, "FundHistory")
    }
    else {
        if (n) {
            y <- sql.FundHistory.sf(y)
        }
        else {
            y <- sql.FundHistory.macro(y)
        }
        z <- sql.tbl(w, "FundHistory", sql.and(y))
    }
    z <- paste0(x, z)
    z
}

#' sql.FundHistory.macro
#' 
#' SQL query where clause
#' @param x = a vector of filters
#' @keywords sql.FundHistory.macro
#' @export
#' @family sql

sql.FundHistory.macro <- function (x) 
{
    z <- list()
    for (y in x) {
        if (any(y == dimnames(mat.read(parameters("classif-FundType")))[[1]])) {
            z[[char.ex.int(length(z) + 65)]] <- paste0("FundType = '", 
                y, "'")
        }
        else if (y == "Act") {
            z[[char.ex.int(length(z) + 65)]] <- "isnull(Idx, 'N') = 'N'"
        }
        else if (y == "Mutual") {
            z[[char.ex.int(length(z) + 65)]] <- "not ETF = 'Y'"
        }
        else if (y == "Etf") {
            z[[char.ex.int(length(z) + 65)]] <- "ETF = 'Y'"
        }
        else if (y == "CB") {
            z[[char.ex.int(length(z) + 65)]] <- c("(", sql.and(sql.cross.border(F), 
                "", "or"), ")")
        }
        else if (y == "UI") {
            z[[char.ex.int(length(z) + 65)]] <- sql.ui()
        }
        else {
            z[[char.ex.int(length(z) + 65)]] <- y
        }
    }
    z
}

#' sql.FundHistory.sf
#' 
#' SQL query where clause
#' @param x = a vector of filters
#' @keywords sql.FundHistory.sf
#' @export
#' @family sql

sql.FundHistory.sf <- function (x) 
{
    z <- list()
    for (h in x) {
        if (h == "Act") {
            z[[char.ex.int(length(z) + 65)]] <- "[Index] = 0"
        }
        else if (h == "Pas") {
            z[[char.ex.int(length(z) + 65)]] <- "[Index] = 1"
        }
        else if (h == "Etf") {
            z[[char.ex.int(length(z) + 65)]] <- "ETFTypeId is not null"
        }
        else if (h == "Mutual") {
            z[[char.ex.int(length(z) + 65)]] <- "ETFTypeId is null"
        }
        else if (h == "JP") {
            z[[char.ex.int(length(z) + 65)]] <- "DomicileId = 'JP'"
        }
        else if (h == "Europe") {
            z[[char.ex.int(length(z) + 65)]] <- "DomicileId in ('BE', 'BG', 'DK', 'DE', 'IE', 'GR', 'ES', 'FR', 'IT', 'LU', 'HU', 'NL', 'AT', 'PL', 'PT', 'RO', 'FI', 'SE', 'GB', 'SI', 'EE')"
        }
        else if (h == "xJP") {
            z[[char.ex.int(length(z) + 65)]] <- "not DomicileId = 'JP'"
        }
        else if (h == "CBE") {
            z[[char.ex.int(length(z) + 65)]] <- c("(", sql.and(sql.cross.border(T), 
                "", "or"), ")")
        }
        else {
            stop("Bad Argument x =", h)
        }
    }
    z
}

#' sql.HerdingLSV
#' 
#' Generates ingredients of the herding measure set forth in LSV's 1991 paper "Do institutional investors destabilize stock prices?"
#' @param x = the YYYYMM for which you want data (known 26 days later)
#' @param y = any of StockFlows/China/Japan/CSI300/Energy
#' @keywords sql.HerdingLSV
#' @export
#' @family sql

sql.HerdingLSV <- function (x, y) 
{
    z <- sql.drop(c("#NEW", "#OLD", "#FLO"))
    z <- c(z, "", sql.into(sql.tbl("HSecurityId, HFundId, FundId, HoldingValue", 
        "Holdings", paste0("ReportDate = '", yyyymm.to.day(x), 
            "'")), "#NEW"))
    z <- c(z, "", sql.into(sql.tbl("HSecurityId, FundId, HoldingValue", 
        "Holdings", paste0("ReportDate = '", yyyymm.to.day(yyyymm.lag(x)), 
            "'")), "#OLD"))
    w <- list(A = paste0("ReportDate = '", yyyymm.to.day(x), 
        "'"))
    w[["B"]] <- "t1.HFundId in (select HFundId from FundHistory where [Index] = 0)"
    w[["C"]] <- "t1.HFundId in (select HFundId from #NEW)"
    w[["D"]] <- "FundId in (select FundId from #OLD)"
    w <- sql.tbl("t1.HFundId, FundId, Flow = sum(Flow)", "MonthlyData t1 inner join FundHistory t2 on t2.HFundId = t1.HFundId", 
        sql.and(w), "t1.HFundId, FundId")
    z <- paste(c(z, "", sql.into(w, "#FLO")), collapse = "\n")
    h <- c("t1.HSecurityId", "prcRet = sum(t1.HoldingValue)/sum(t2.HoldingValue)")
    h <- sql.tbl(h, "#NEW t1 inner join #OLD t2 on t2.FundId = t1.FundId and t2.HSecurityId = t1.HSecurityId", 
        "t1.HFundId in (select HFundId from FundHistory where [Index] = 1)", 
        "t1.HSecurityId", "sum(t2.HoldingValue) > 0")
    h <- c("#FLO t0", "cross join", sql.label(h, "t1"), "cross join")
    h <- c(h, sql.label(sql.tbl("expPctBuy = sum(case when Flow > 0 then 1.0 else 0.0 end)/count(HFundId)", 
        "#FLO"), "t4"))
    h <- c(h, "left join", "#NEW t2 on t2.HFundId = t0.HFundId and t2.HSecurityId = t1.HSecurityId")
    h <- c(h, "left join", "#OLD t3 on t3.FundId = t0.FundId and t3.HSecurityId = t1.HSecurityId")
    h <- c(h, "inner join", "SecurityHistory id on id.HSecurityId = t1.HSecurityId")
    w <- c("SecurityId", "B = sum(case when isnull(t2.HoldingValue, 0) > isnull(t3.HoldingValue, 0) * prcRet then 1 else 0 end)")
    w <- c(w, "S = sum(case when isnull(t2.HoldingValue, 0) < isnull(t3.HoldingValue, 0) * prcRet then 1 else 0 end)", 
        "expPctBuy = avg(expPctBuy)")
    w <- sql.tbl(w, h, sql.in("t1.HSecurityId", sql.RDSuniv(y)), 
        "SecurityId")
    z <- c(z, paste(sql.unbracket(w), collapse = "\n"))
    z
}

#' sql.Herfindahl
#' 
#' Generates Herfindahl dispersion and FundCt, the ownership breadth measure set forth in Chen, Hong & Stein (2001)"Breadth of ownership and stock returns"
#' @param x = the YYYYMM for which you want data (known 26 days later)
#' @param y = a string vector of factors to be computed, the last element of which is the type of fund used.
#' @param n = any of StockFlows/China/Japan/CSI300/Energy
#' @param w = T/F depending on whether you are checking ftp
#' @keywords sql.Herfindahl
#' @export
#' @family sql

sql.Herfindahl <- function (x, y, n, w) 
{
    y <- sql.arguments(y)
    z <- yyyymm.to.day(x)
    x <- sql.declare("@mo", "datetime", z)
    if (n != "All") 
        n <- list(A = sql.in("h.HSecurityId", sql.RDSuniv(n)))
    else n <- list()
    n[["B"]] <- "ReportDate = @mo"
    if (y$filter != "All") 
        n[["C"]] <- sql.in("h.HFundId", sql.FundHistory("", y$filter, 
            T))
    if (length(n) == 1) 
        n <- n[[1]]
    else n <- sql.and(n)
    if (w & any(y$factor == "FundCt")) {
        z <- c(paste0("ReportDate = '", z, "'"), "GeoId = GeographicFocusId", 
            "HSecurityId")
    }
    else if (w & all(y$factor != "FundCt")) {
        z <- c(paste("ReportDate = '", z, "'", sep = ""), "HSecurityId")
    }
    else {
        z <- "SecurityId"
    }
    for (j in y$factor) {
        if (j == "Herfindahl") {
            z <- c(z, paste(j, "1 - sum(square(HoldingValue))/square(sum(HoldingValue))", 
                sep = " = "))
        }
        else if (j == "HerfindahlEq") {
            z <- c(z, paste(j, "1 - sum(square(HoldingValue/AssetsEnd))/square(sum(HoldingValue/AssetsEnd))", 
                sep = " = "))
        }
        else if (j == "FundCt") {
            z <- c(z, paste(j, "count(h.HFundId)", sep = " = "))
        }
        else {
            stop("Bad factor", j)
        }
    }
    h <- "Holdings h"
    if (any(y$factor == "FundCt") & w) 
        h <- c(h, "inner join", "FundHistory t on t.HFundId = h.HFundId")
    if (!w) 
        h <- c(h, "inner join", "SecurityHistory id on id.HSecurityId = h.HSecurityId")
    if (any(y$factor == "HerfindahlEq")) {
        h <- c(h, "inner join", sql.label(sql.MonthlyAssetsEnd("@mo"), 
            "t on t.HFundId = h.HFundId"))
    }
    if (any(y$factor == "FundCt") & w) {
        w <- "HSecurityId, GeographicFocusId"
    }
    else {
        w <- ifelse(w, "HSecurityId", "SecurityId")
    }
    z <- sql.tbl(z, h, n, w, "sum(HoldingValue) > 0")
    z <- paste(c(x, sql.unbracket(z)), collapse = "\n")
    z
}

#' sql.Holdings
#' 
#' query to access stock-holdings data
#' @param x = where clause
#' @param y = columns you want fetched
#' @param n = the temp table for the output
#' @keywords sql.Holdings
#' @export
#' @family sql

sql.Holdings <- function (x, y, n) 
{
    z <- sql.tbl(y, "Holdings", x)
    if (!missing(n)) 
        z <- sql.into(z, n)
    z
}

#' sql.Holdings.bulk
#' 
#' query to bulk data with known benchmark holdings
#' @param x = name of temp table with holdings
#' @param y = columns of <x> (in order)
#' @param n = the holdings date in YYYYMMDD
#' @param w = unused temp table name for benchmark holdings
#' @param h = unused temp table name for benchmark AUM
#' @keywords sql.Holdings.bulk
#' @export
#' @family sql

sql.Holdings.bulk <- function (x, y, n, w, h) 
{
    vec <- c(w, h)
    z <- sql.tbl("HFundId", "MonthlyData", paste0("ReportDate = '", 
        n, "'"), "HFundId", "sum(AssetsEnd) > 0")
    z <- list(A = sql.in("HFundId", z), B = sql.in("HFundId", 
        sql.tbl("HFundId", "FundHistory", "[Index] = 1")))
    z <- sql.into(sql.tbl(y, x, sql.and(z)), vec[1])
    h <- list(A = sql.in("HFundId", sql.tbl("HFundId", vec[1])), 
        B = paste0("ReportDate = '", n, "'"))
    z <- c(z, "", sql.into(sql.tbl("HFundId, AUM = sum(AssetsEnd)", 
        "MonthlyData", sql.and(h), "HFundId"), vec[2]))
    h <- sql.tbl("BenchIndexId, AUM = max(AUM)", c(paste(vec[2], 
        "t1"), "inner join", "FundHistory t2 on t1.HFundId = t2.HFundId"), 
        , "BenchIndexId")
    h <- c("FundHistory t1", "inner join", sql.label(h, "t2 on t1.BenchIndexId = t2.BenchIndexId"))
    h <- sql.tbl("HFundId, AUM", h, sql.and(list(A = paste(vec[2], 
        "HFundId = t1.HFundId", sep = "."), B = paste(vec[2], 
        "AUM = t2.AUM", sep = "."))))
    z <- c(z, "", paste("delete from", vec[2], "where not exists"), 
        paste0("\t", h))
    z <- c(z, "", paste("delete from", vec[1], "where HFundId not in (select HFundId from", 
        vec[2], ")"), "")
    z <- c(z, paste0("update ", vec[1], " set HoldingValue = HoldingValue/AUM from ", 
        vec[2], " where ", vec[1], ".HFundId = ", vec[2], ".HFundId"))
    z <- c(z, "", sql.drop(vec[2]))
    w <- sql.tbl("HFundId, AUM = sum(AssetsEnd)", "MonthlyData", 
        paste0("ReportDate = '", n, "'"), "HFundId", "sum(AssetsEnd) > 0")
    w <- c(sql.label(w, "t1"), "inner join", "FundHistory t2 on t1.HFundId = t2.HFundId")
    w <- c(w, "inner join", "FundHistory t3 on t2.BenchIndexId = t3.BenchIndexId")
    w <- c(w, "inner join", paste(vec[1], "t4 on t4.HFundId = t3.HFundId"))
    h <- sql.and(list(A = "t2.[Index] = 1", B = sql.in("t1.HFundId", 
        sql.tbl("HFundId", x), F)))
    y <- ifelse(y == "FundId", "t2.FundId", y)
    y <- ifelse(y == "HFundId", "t1.HFundId", y)
    y <- ifelse(y == "HoldingValue", "HoldingValue = t4.HoldingValue * t1.AUM", 
        y)
    z <- c(z, "", "insert into", paste0("\t", x), sql.unbracket(sql.tbl(y, 
        w, h)), "", sql.drop(vec[1]))
    z
}

#' sql.HSIdmap
#' 
#' Generates the SQL query to map SecurityId to HSecurityId
#' @param x = the YYYYMM for which you want data (known 26 days later)
#' @keywords sql.HSIdmap
#' @export
#' @family sql

sql.HSIdmap <- function (x) 
{
    z <- sql.in("HSecurityId", sql.tbl("HSecurityId", "Holdings", 
        "ReportDate = @mo", "HSecurityId"))
    z <- sql.unbracket(sql.tbl(c("SecurityId", "HSecurityId"), 
        "SecurityHistory", z))
    z <- paste(c(sql.declare("@mo", "datetime", yyyymm.to.day(x)), 
        z), collapse = "\n")
    z
}

#' sql.in
#' 
#' <x> in <y> if <n> or <x> not in <y> otherwise
#' @param x = column
#' @param y = SQL statement
#' @param n = T/F depending on whether <x> is in <y>
#' @keywords sql.in
#' @export
#' @family sql

sql.in <- function (x, y, n = T) 
{
    c(paste(x, ifelse(n, "in", "not in")), paste0("\t", y))
}

#' sql.into
#' 
#' unbrackets and selects into <y>
#' @param x = SQL statement
#' @param y = the temp table for the output
#' @keywords sql.into
#' @export
#' @family sql

sql.into <- function (x, y) 
{
    z <- sql.unbracket(x)
    n <- length(z)
    w <- z == "from"
    w <- w & !duplicated(w)
    if (sum(w) != 1) 
        stop("Failure in sql.into!")
    w <- c(1:n, (1:n)[w] + 1:2/3 - 1)
    z <- c(z, "into", paste0("\t", y))[order(w)]
    z
}

#' sql.ION
#' 
#' sum(case when <x> > 0 then <y> else 0 end)/case when sum(abs(<y>)) > 0 then sum(abs(<y>)) else NULL end
#' @param x = bit of SQL string
#' @param y = bit of SQL string
#' @keywords sql.ION
#' @export
#' @family sql

sql.ION <- function (x, y) 
{
    z <- paste0("= sum(case when ", x, " > 0 then ", y, " else 0 end)")
    z <- paste0(z, "/", sql.nonneg(paste0("sum(abs(", y, "))")))
    z
}

#' sql.isin.old.to.new
#' 
#' Returns the latest isin
#' @param x = Historical Isin
#' @keywords sql.isin.old.to.new
#' @export
#' @family sql

sql.isin.old.to.new <- function (x) 
{
    z <- sql.tbl("Id", "SecurityCode", sql.and(list(A = "SecurityCodeTypeId = 1", 
        B = "SecurityCode = @isin")))
    z <- sql.tbl("HSecurityId", "SecurityCodeMapping", sql.in("SecurityCodeId", 
        z))
    z <- sql.tbl("SecurityId", "SecurityHistory", sql.in("HSecurityId", 
        z))
    z <- sql.tbl("HSecurityId", "SecurityHistory", sql.and(list(A = "EndDate is NULL", 
        B = sql.in("SecurityId", z))))
    z <- sql.tbl("SecurityCodeId", "SecurityCodeMapping", sql.and(list(A = "SecurityCodeTypeId = 1", 
        B = sql.in("HSecurityId", z))))
    z <- sql.tbl("SecurityCode", "SecurityCode", sql.and(list(A = "SecurityCodeTypeId = 1", 
        B = sql.in("Id", z))))
    z <- paste(c(sql.declare("@isin", "char(12)", x), z), collapse = "\n")
    z
}

#' sql.label
#' 
#' labels <x> as <y>
#' @param x = SQL statement
#' @param y = label
#' @keywords sql.label
#' @export
#' @family sql

sql.label <- function (x, y) 
{
    z <- length(x)
    if (z == 1) 
        z <- paste(x, y)
    else z <- c(x[-z], paste(x[z], y))
    z
}

#' sql.map.classif
#' 
#' Returns flow variables with the same row space as <w>
#' @param x = SQL queries to be submitted
#' @param y = names of factors to be returned
#' @param n = a connection, the output of odbcDriverConnect
#' @param w = classif file
#' @keywords sql.map.classif
#' @export
#' @family sql
#' @@importFrom RODBC sqlQuery

sql.map.classif <- function (x, y, n, w) 
{
    z <- sql.query.underlying(x, n, F)
    if (any(duplicated(z[, "SecurityId"]))) 
        stop("Problem...\n")
    dimnames(z)[[1]] <- z[, "SecurityId"]
    z <- map.rname(z, dimnames(w)[[1]])
    z <- z[, y]
    if (length(y) == 1) 
        z <- as.numeric(z)
    z
}

#' sql.mat.cofactor
#' 
#' SQL for the cofactor matrix
#' @param x = square character matrix
#' @keywords sql.mat.cofactor
#' @export
#' @family sql

sql.mat.cofactor <- function (x) 
{
    z <- matrix("", dim(x)[1], dim(x)[2], F, dimnames(x))
    for (i in 1:dim(z)[1]) {
        for (j in 1:dim(z)[2]) {
            z[i, j] <- sql.mat.determinant(x[-i, -j])
            if ((i + j)%%2 == 1) 
                z[i, j] <- sql.mat.flip(z[i, j])
        }
    }
    z
}

#' sql.mat.crossprod
#' 
#' SQL for entries of X'X
#' @param x = vector of names
#' @param y = T/F depending on whether there's an intercept term
#' @keywords sql.mat.crossprod
#' @export
#' @family sql

sql.mat.crossprod <- function (x, y) 
{
    m <- length(x)
    names(x) <- 1:m
    z <- rep(1:m, m)
    w <- z[order(rep(1:m, m))]
    h <- vec.max(w, z)
    z <- vec.min(w, z)
    z <- map.rname(x, z)
    h <- map.rname(x, h)
    z <- ifelse(z == h, paste0("sum(square(", z, "))"), paste0("sum(", 
        z, " * ", h, ")"))
    z <- matrix(z, m, m, F, list(x, x))
    if (y) {
        z <- map.rname(z, c("Unity", x))
        z <- t(map.rname(t(z), c("Unity", x)))
        z[1, -1] <- z[-1, 1] <- paste0("sum(", x, ")")
        z[1, 1] <- paste0("count(", x[1], ")")
    }
    z
}

#' sql.mat.crossprod.vector
#' 
#' SQL for entries of X'Y
#' @param x = vector of names
#' @param y = a string
#' @param n = T/F depending on whether there's an intercept term
#' @keywords sql.mat.crossprod.vector
#' @export
#' @family sql

sql.mat.crossprod.vector <- function (x, y, n) 
{
    z <- vec.named(paste0("sum(", x, " * ", y, ")"), x)
    if (n) {
        z["Unity"] <- paste0("sum(", y, ")")
        w <- length(z)
        z <- z[order(1:w%%w)]
    }
    z
}

#' sql.mat.determinant
#' 
#' SQL for the determinant
#' @param x = square character matrix
#' @keywords sql.mat.determinant
#' @export
#' @family sql

sql.mat.determinant <- function (x) 
{
    n <- dim(x)[2]
    if (is.null(n)) {
        z <- x
    }
    else if (n == 2) {
        z <- sql.mat.multiply(x[1, 2], x[2, 1])
        z <- paste0(sql.mat.multiply(x[1, 1], x[2, 2]), " - ", 
            z)
    }
    else {
        i <- 1
        z <- paste0(x[1, i], " * (", sql.mat.determinant(x[-1, 
            -i]), ")")
        for (i in 2:n) {
            h <- ifelse(i%%2 == 0, " - ", " + ")
            z <- paste(z, paste0(x[1, i], " * (", sql.mat.determinant(x[-1, 
                -i]), ")"), sep = h)
        }
    }
    z
}

#' sql.mat.flip
#' 
#' flips the sign for a term in a matrix
#' @param x = square character matrix
#' @keywords sql.mat.flip
#' @export
#' @family sql

sql.mat.flip <- function (x) 
{
    h <- NULL
    n <- nchar(x)
    i <- 1
    m <- 0
    while (i <= n) {
        if (m == 0 & is.element(substring(x, i, i), c("+", "-"))) {
            h <- c(h, i)
        }
        else if (substring(x, i, i) == "(") {
            m <- m + 1
        }
        else if (substring(x, i, i) == ")") {
            m <- m - 1
        }
        i <- i + 1
    }
    if (!is.null(h)) {
        h <- c(-1, h, n + 2)
        i <- 2
        z <- substring(x, h[i] + 2, h[i + 1] - 2)
        while (i + 3 <= length(h)) {
            i <- i + 2
            z <- paste(z, substring(x, h[i] + 2, h[i + 1] - 2), 
                sep = " + ")
        }
        i <- -1
        while (i + 3 <= length(h)) {
            i <- i + 2
            z <- paste(z, substring(x, h[i] + 2, h[i + 1] - 2), 
                sep = " - ")
        }
    }
    else {
        z <- paste0("(-", x, ")")
    }
    z
}

#' sql.mat.multiply
#' 
#' SQL for the determinant
#' @param x = string
#' @param y = string
#' @keywords sql.mat.multiply
#' @export
#' @family sql

sql.mat.multiply <- function (x, y) 
{
    if (x == y) {
        z <- paste0("square(", x, ")")
    }
    else {
        z <- paste(x, y, sep = " * ")
    }
    z
}

#' sql.Mo
#' 
#' SQL statement for momentum
#' @param x = vector of "flow"
#' @param y = isomekic vector of "assets"
#' @param n = isomekic vector of "weights" (can be NULL)
#' @param w = T/F depending on whether to handle division by zero
#' @keywords sql.Mo
#' @export
#' @family sql

sql.Mo <- function (x, y, n, w) 
{
    if (is.null(n)) {
        z <- paste0("sum(", y, ")")
    }
    else {
        z <- paste0("sum(", y, " * cast(", n, " as float))")
    }
    if (w) {
        w <- sql.nonneg(z)
    }
    else {
        w <- z
    }
    if (is.null(n)) {
        z <- paste0("sum(", x, ")")
    }
    else {
        z <- paste0("sum(", x, " * cast(", n, " as float))")
    }
    z <- paste0("= 100 * ", z, "/", w)
    z
}

#' sql.MonthlyAlloc
#' 
#' Generates the SQL query to get the data for monthly allocations for StockFlows
#' @param x = YYYYMM for which you want allocations (known 26 days after month end)
#' @param y = characters that get pasted in front of every line (usually tabs for indentation)
#' @keywords sql.MonthlyAlloc
#' @export
#' @family sql

sql.MonthlyAlloc <- function (x, y = "") 
{
    paste0(y, sql.Holdings(paste0("ReportDate = ", x), c("FundId", 
        "HFundId", "HSecurityId", "HoldingValue")))
}

#' sql.MonthlyAssetsEnd
#' 
#' Generates the SQL query to get the data for monthly Assets End
#' @param x = YYYYMMDD for which you want flows (known one day later)
#' @param y = characters that get pasted in front of every line (usually tabs for indentation)
#' @param n = T/F variable depending on whether you want AssetsStart/AssetsEnd or just AssetsEnd
#' @param w = T/F depending on whether data are indexed by FundId
#' @keywords sql.MonthlyAssetsEnd
#' @export
#' @family sql

sql.MonthlyAssetsEnd <- function (x, y = "", n = F, w = F) 
{
    z <- ifelse(w, "FundId", "HFundId")
    z <- c(z, "AssetsEnd = sum(AssetsEnd)")
    h <- "sum(AssetsEnd) > 0"
    if (n) {
        z <- c(z, "AssetsStart = sum(AssetsStart)")
        h <- sql.and(list(A = h, B = "sum(AssetsStart) > 0"))
    }
    if (w) {
        z <- sql.tbl(z, "MonthlyData t1 inner join FundHistory t2 on t2.HFundId = t1.HFundId", 
            paste("ReportDate =", x), "FundId", h)
    }
    else {
        z <- sql.tbl(z, "MonthlyData", paste("ReportDate =", 
            x), "HFundId", h)
    }
    z <- paste0(y, z)
    z
}

#' sql.nonneg
#' 
#' case when <x> > 0 then <x> else NULL end
#' @param x = bit of sql string
#' @keywords sql.nonneg
#' @export
#' @family sql

sql.nonneg <- function (x) 
{
    paste("case when", x, "> 0 then", x, "else NULL end")
}

#' sql.query
#' 
#' opens a connection, executes sql query, then closes the connection
#' @param x = query needed for the update
#' @param y = one of StockFlows/Regular/Quant
#' @param n = T/F depending on whether you wish to output number of rows of data got
#' @keywords sql.query
#' @export
#' @family sql
#' @@importFrom RODBC sqlQuery

sql.query <- function (x, y, n = T) 
{
    y <- sql.connect(y)
    z <- sql.query.underlying(x, y, n)
    close(y)
    z
}

#' sql.query.underlying
#' 
#' opens a connection, executes sql query, then closes the connection
#' @param x = query needed for the update
#' @param y = a connection, the output of odbcDriverConnect
#' @param n = T/F depending on whether you wish to output number of rows of data got
#' @keywords sql.query.underlying
#' @export
#' @family sql
#' @@importFrom RODBC sqlQuery

sql.query.underlying <- function (x, y, n = T) 
{
    for (i in x) z <- sqlQuery(y, i, stringsAsFactors = F)
    if (n) 
        cat("Getting ", dim(z)[1], " new rows of data ...\n")
    z
}

#' sql.RDSuniv
#' 
#' Generates the SQL query to get the row space for a stock flows research data set
#' @param x = any of StockFlows/China/Japan/CSI300/Energy
#' @keywords sql.RDSuniv
#' @export
#' @family sql

sql.RDSuniv <- function (x) 
{
    if (any(x == c("StockFlows", "Japan", "CSI300"))) {
        if (x == "CSI300") {
            bmks <- vec.named("CSI300", 31873)
        }
        else if (x == "Japan") {
            bmks <- vec.named(c("Nikkei", "Topix"), c(13667, 
                17558))
        }
        else if (x == "StockFlows") {
            bmks <- c("S&P500", "Eafe", "Gem", "R3", "EafeSc", 
                "GemSc", "Canada", "CanadaSc", "R1", "R2", "Nikkei", 
                "Topix", "CSI300")
            names(bmks) <- c(5164, 4430, 4835, 5158, 14602, 16621, 
                7744, 29865, 5152, 5155, 13667, 17558, 31873)
        }
        z <- sql.and(vec.to.list(paste("FundId =", paste(names(bmks), 
            bmks, sep = " --"))), n = "or")
        z <- sql.in("HFundId", sql.tbl("HFundId", "FundHistory", 
            z))
        z <- sql.tbl("HSecurityId", "Holdings", z, "HSecurityId")
    }
    else if (x == "Energy") {
        z <- "(340228, 696775, 561380, 656067, 308571, 420631, 902846, 673356, 911907, 763388,"
        z <- c(z, "\t98654, 664044, 742638, 401296, 308355, 588468, 612083, 682720, 836332, 143750)")
        z <- sql.tbl("HSecurityId", "SecurityHistory", sql.in("SecurityId", 
            z))
    }
    else if (x == "China") {
        z <- sql.tbl("HCompanyId", "CompanyHistory", "CountryCode = 'CN'")
        z <- sql.tbl("HSecurityId", "SecurityHistory", sql.in("HCompanyId", 
            z))
        z <- sql.in("HSecurityId", z)
        z <- list(A = z, B = sql.in("HFundId", sql.tbl("HFundId", 
            "FundHistory", "GeographicFocusId = 16")))
        z <- sql.and(z, n = "or")
        z <- sql.tbl("HSecurityId", "Holdings", z, "HSecurityId")
    }
    else if (x == "All") {
        z <- ""
    }
    z
}

#' sql.regr
#' 
#' SQL for regression coefficients
#' @param x = a string vector (independent variable(s))
#' @param y = a string (dependent variable)
#' @param n = T/F depending on whether there's an intercept term
#' @keywords sql.regr
#' @export
#' @family sql

sql.regr <- function (x, y, n) 
{
    y <- sql.mat.crossprod.vector(x, y, n)
    x <- sql.mat.crossprod(x, n)
    h <- sql.mat.cofactor(x)
    n <- sql.mat.determinant(x)
    z <- NULL
    for (j in 1:length(y)) {
        w <- paste(paste0(y, " * (", h[, j], ")"), collapse = " + ")
        w <- paste0("(", w, ")/(", n, ")")
        z <- c(z, paste(names(y)[j], w, sep = " = "))
    }
    z
}

#' sql.sf.wtd.avg
#' 
#' Computes Fund/Smpl weighted Incl/Excl zero for all names in the S&P
#' @param x = YYYYMM at the end of which allocations are desired
#' @param y = a string. Must be one of All/Etf/MF.
#' @keywords sql.sf.wtd.avg
#' @export
#' @family sql

sql.sf.wtd.avg <- function (x, y) 
{
    x <- sql.declare(c("@benchId", "@hFundId", "@geoId", "@allocDt"), 
        c("int", "int", "int", "datetime"), c(1487, 8068, 77, 
            yyyymm.to.day(x)))
    w <- list(A = "GeographicFocusId = @geoId", B = "BenchIndexId = @benchId", 
        C = "StyleSectorId in (108, 109, 110)")
    if (y == "Etf") {
        w[["D"]] <- "ETFTypeId is not null"
    }
    else if (y == "MF") {
        w[["D"]] <- "ETFTypeId is null"
    }
    else if (y != "All") 
        stop("Bad type argument")
    w <- list(A = sql.in("HFundId", sql.tbl("HFundId", "FundHistory", 
        sql.and(w))))
    w[["B"]] <- "ReportDate = @allocDt"
    w[["C"]] <- sql.in("HFundId", sql.Holdings("ReportDate = @allocDt", 
        "HFundId"))
    z <- sql.label(sql.tbl("HFundId, PortVal = sum(AssetsEnd)", 
        "MonthlyData", sql.and(w), "HFundId"), "t1")
    w <- sql.tbl("HSecurityId", "Holdings", sql.and(list(A = "ReportDate = @allocDt", 
        B = "HFundId = @hFundId")))
    z <- sql.label(sql.tbl("HFundId, HSecurityId, PortVal", c(z, 
        "cross join", sql.label(w, "t2"))), " t")
    z <- c(z, "inner join", "SecurityCodeMapping map on map.HSecurityId = t.HSecurityId")
    w <- sql.Holdings("ReportDate = @allocDt", c("HSecurityId", 
        "HFundId", "HoldingValue"))
    z <- c(z, "left join", sql.label(w, "t3"), "\ton t3.HFundId = t.HFundId and t3.HSecurityId = t.HSecurityId")
    w <- sql.tbl("Id, SecurityCode", "SecurityCode", "SecurityCodeTypeId = 1")
    w <- c(z, "left join", sql.label(w, "isin"), "\ton isin.Id = map.SecurityCodeId")
    z <- c("t.HSecurityId", "isin = isnull(isin.SecurityCode, '')", 
        "SmplWtdExcl0 = avg(HoldingValue/PortVal)")
    z <- c(z, "SmplWtdIncl0 = sum(HoldingValue/PortVal)/count(PortVal)")
    z <- c(z, "FundWtdExcl0 = sum(HoldingValue)/sum(case when HoldingValue is not null then PortVal else NULL end)")
    z <- c(z, "FundWtdIncl0 = sum(HoldingValue)/sum(PortVal)")
    z <- sql.unbracket(sql.tbl(z, w, , "t.HSecurityId, isnull(isin.SecurityCode, '')", 
        "sum(HoldingValue) > 0"))
    z <- paste(c(x, z), collapse = "\n")
    z
}

#' sql.SRI
#' 
#' number of SRI funds holding the stock at time <x>
#' @param x = the YYYYMM for which you want data (known 26 days later)
#' @param y = any of StockFlows/Japan/CSI300/Energy
#' @keywords sql.SRI
#' @export
#' @family sql

sql.SRI <- function (x, y) 
{
    w <- list(A = "ReportDate = @holdDt", B = "HFundId in (select HFundId from FundHistory where SRI = 1)")
    z <- sql.label(sql.tbl("HSecurityId, Ct = count(HFundId)", 
        "Holdings", sql.and(w), "HSecurityId"), "t1")
    z <- c(z, "inner join", "SecurityHistory id on id.HSecurityId = t1.HSecurityId")
    z <- sql.tbl("SecurityId, Ct = sum(Ct)", z, sql.in("t1.HSecurityId", 
        sql.RDSuniv(y)), "SecurityId")
    z <- c(sql.declare("@holdDt", "datetime", yyyymm.to.day(x)), 
        sql.unbracket(z))
    z <- paste(z, collapse = "\n")
    z
}

#' sql.tbl
#' 
#' Full SQL statement
#' @param x = needed columns
#' @param y = table
#' @param n = where segment
#' @param w = group by segment
#' @param h = having
#' @keywords sql.tbl
#' @export
#' @family sql

sql.tbl <- function (x, y, n, w, h) 
{
    m <- length(x)
    z <- c(txt.left(x[-1], 1) != "\t", F)
    z <- paste0(x, ifelse(z, ",", ""))
    z <- c("(select", paste0("\t", txt.replace(z, "\n", "\n\t")))
    x <- txt.right(y, 5) == " join"
    x <- x & txt.left(c(y[-1], ""), 1) != "\t"
    x <- ifelse(x, "", "\t")
    z <- c(z, "from", paste0(x, txt.replace(y, "\n", "\n\t")))
    if (!missing(n)) 
        z <- c(z, "where", paste0("\t", n))
    if (!missing(w)) 
        z <- c(z, "group by", paste0("\t", w))
    if (!missing(h)) 
        z <- c(z, "having", paste0("\t", h))
    z <- c(z, ")")
    z
}

#' sql.TopDownAllocs
#' 
#' Generates the SQL query to get Active/Passive Top-Down Allocations
#' @param x = the YYYYMM for which you want data (known 26 days later)
#' @param y = a string vector of top-down allocations wanted, the last element of which is the type of fund to be used.
#' @param n = any of StockFlows/Japan/CSI300/Energy
#' @param w = T/F depending on whether you are checking ftp
#' @keywords sql.TopDownAllocs
#' @export
#' @family sql

sql.TopDownAllocs <- function (x, y, n, w) 
{
    m <- length(y)
    x <- sql.declare("@allocDt", "datetime", yyyymm.to.day(x))
    if (n == "All") {
        n <- "ReportDate = @allocDt"
    }
    else {
        n <- sql.and(list(A = "ReportDate = @allocDt", B = sql.in("HSecurityId", 
            sql.RDSuniv(n))))
    }
    h <- sql.label(sql.tbl("HFundId, AssetsEnd = sum(AssetsEnd)", 
        "MonthlyData", "ReportDate = @allocDt", "HFundId", "sum(AssetsEnd) > 0"), 
        "t1")
    h <- c(h, "inner join", sql.label(sql.FundHistory("", y[m], 
        T, c("FundId", "GeographicFocusId")), "t2"), "\ton t2.HFundId = t1.HFundId")
    h <- sql.tbl(c("FundId", "GeographicFocusId", "AssetsEnd"), 
        h, sql.in("FundId", sql.tbl("FundId", "Holdings h", "ReportDate = @allocDt")))
    h <- c(sql.label(h, "t2"), "cross join", sql.label(sql.tbl("ReportDate, HSecurityId", 
        "Holdings", n, "ReportDate, HSecurityId"), "t1"))
    h <- c(h, "left join", sql.label(sql.Holdings("ReportDate = @allocDt", 
        c("FundId", "HSId = HSecurityId", "HoldingValue")), "t3"))
    h <- c(h, "\ton t3.FundId = t2.FundId and HSId = HSecurityId")
    if (!w) 
        h <- c(h, "inner join", "SecurityHistory id on id.HSecurityId = t1.HSecurityId")
    if (w & m == 2) {
        cols <- c("GeoId", "AverageAllocation")
        n <- sql.TopDownAllocs.items(y[1])
        n <- txt.right(n, nchar(n) - nchar(y[1]) - 1)
        n <- paste(cols[2], n)
        z <- sql.tbl(c("ReportDate = convert(char(8), t1.ReportDate, 112)", 
            "GeoId = GeographicFocusId", "HSecurityId", n), h, 
            , "t1.ReportDate, GeographicFocusId, HSecurityId", 
            sql.TopDownAllocs.items(y[1], F))
    }
    else if (w & m > 2) {
        z <- c("ReportDate = convert(char(8), t1.ReportDate, 112)", 
            "GeoId = GeographicFocusId", "HSecurityId", sql.TopDownAllocs.items(y[-m]))
        z <- sql.tbl(z, h, , "t1.ReportDate, GeographicFocusId, HSecurityId")
    }
    else {
        z <- c("SecurityId", sql.TopDownAllocs.items(y[-m]))
        z <- sql.tbl(z, h, , "SecurityId")
    }
    z <- paste(c(x, "", sql.unbracket(z)), collapse = "\n")
    z
}

#' sql.TopDownAllocs.items
#' 
#' allocations to select in Top-Down Allocations SQL query
#' @param x = a string vector specifying types of allocation wanted
#' @param y = T/F depending on whether select item or having entry is desired
#' @keywords sql.TopDownAllocs.items
#' @export
#' @family sql

sql.TopDownAllocs.items <- function (x, y = T) 
{
    if (y) {
        z <- NULL
        for (i in x) {
            if (i == "SwtdEx0") {
                z <- c(z, "SwtdEx0 = 100 * avg(HoldingValue/AssetsEnd)")
            }
            else if (i == "SwtdIn0") {
                z <- c(z, "SwtdIn0 = 100 * sum(HoldingValue/AssetsEnd)/count(AssetsEnd)")
            }
            else if (i == "FwtdEx0") {
                z <- c(z, "FwtdEx0 = 100 * sum(HoldingValue)/sum(case when HoldingValue is not null then AssetsEnd else NULL end)")
            }
            else if (i == "FwtdIn0") {
                z <- c(z, "FwtdIn0 = 100 * sum(HoldingValue)/sum(AssetsEnd)")
            }
            else {
                stop("Bad Argument")
            }
        }
    }
    else if (length(x) > 1) {
        stop("Element expected, not vector")
    }
    else {
        if (x == "SwtdEx0") {
            z <- "count(HoldingValue/AssetsEnd) > 0"
        }
        else if (x == "SwtdIn0") {
            z <- "count(AssetsEnd) > 0"
        }
        else if (x == "FwtdEx0") {
            z <- "sum(case when HoldingValue is not null then AssetsEnd else NULL end) > 0"
        }
        else if (x == "FwtdIn0") {
            z <- "sum(AssetsEnd) > 0"
        }
        else {
            stop("Bad Argument")
        }
    }
    z
}

#' sql.Trend
#' 
#'  = sum(<x>)/case when sum(<x>) = 0 then NULL else sum(<x>) end
#' @param x = bit of SQL string
#' @keywords sql.Trend
#' @export
#' @family sql

sql.Trend <- function (x) 
{
    z <- paste0("= sum(", x, ")")
    z <- paste0(z, "/", sql.nonneg(paste0("sum(abs(", x, "))")))
    z
}

#' sql.ui
#' 
#' funds to be displayed on the UI
#' @keywords sql.ui
#' @export
#' @family sql

sql.ui <- function () 
{
    z <- list()
    z[["A"]] <- "FundType in ('M', 'A', 'Y', 'B', 'E')"
    z[["B"]] <- "GeographicFocus not in (0, 18, 48)"
    z[["C"]] <- "Category >= '1'"
    z[["D"]] <- "isActive = 'Y'"
    z <- c("(", sql.and(z), ")")
    x <- list()
    x[["A"]] <- "Commodity = 'Y'"
    x[["B"]] <- "StyleSector in (101, 103)"
    x[["C"]] <- "FundType in ('Y', 'E')"
    x[["D"]] <- "isActive = 'Y'"
    x <- c("(", sql.and(x), ")")
    z <- list(A = z, B = x)
    z <- c("(", sql.and(z, , "or"), ")")
    z
}

#' sql.unbracket
#' 
#' removes brackets around an SQL block
#' @param x = string vector
#' @keywords sql.unbracket
#' @export
#' @family sql

sql.unbracket <- function (x) 
{
    n <- length(x)
    if (txt.left(x[1], 1) != "(" | x[n] != ")") 
        stop("Can't unbracket!")
    x[1] <- txt.right(x[1], nchar(x[1]) - 1)
    z <- x[-n]
    z
}

#' sqlts.FloDollar.daily
#' 
#' SQL query for daily dollar flow
#' @param x = the security id for which you want data
#' @keywords sqlts.FloDollar.daily
#' @export
#' @family sqlts

sqlts.FloDollar.daily <- function (x) 
{
    x <- sql.declare("@secId", "int", x)
    z <- sql.tbl(c("ReportDate", "HFundId", "Flow = sum(Flow)"), 
        "DailyData", , "ReportDate, HFundId")
    z <- c(sql.label(z, "t1"), "inner join", "FundHistory t2 on t2.HFundId = t1.HFundId")
    z <- c(z, "inner join", "Holdings t3 on t3.FundId = t2.FundId", 
        paste("\tand", sql.datediff("t3.ReportDate", "t1.ReportDate", 
            26)))
    h <- sql.tbl("ReportDate, HFundId, AUM = sum(AssetsEnd)", 
        "MonthlyData", , "ReportDate, HFundId", "sum(AssetsEnd) > 0")
    z <- c(z, "inner join", sql.label(h, "t4"), "\ton t4.HFundId = t3.HFundId and t4.ReportDate = t3.ReportDate")
    h <- sql.in("HSecurityId", sql.tbl("HSecurityId", "SecurityHistory", 
        "SecurityId = @secId"))
    z <- sql.tbl(c("yyyymmdd = convert(char(8), t1.ReportDate, 112)", 
        "FloDlr = sum(Flow * HoldingValue/AUM)"), z, h, "t1.ReportDate")
    z <- paste(c(x, "", sql.unbracket(z)), collapse = "\n")
    z
}

#' sqlts.FloDollar.monthly
#' 
#' SQL query for monthly dollar flow
#' @param x = the security id for which you want data
#' @keywords sqlts.FloDollar.monthly
#' @export
#' @family sqlts

sqlts.FloDollar.monthly <- function (x) 
{
    x <- sql.declare("@secId", "int", x)
    z <- sql.tbl(c("ReportDate", "HFundId", "Flow = sum(Flow)", 
        "AUM = sum(AssetsEnd)"), "MonthlyData", , "ReportDate, HFundId", 
        "sum(AssetsEnd) > 0")
    z <- c(sql.label(z, "t1"), "inner join", "Holdings t2 on t2.HFundId = t1.HFundId and t2.ReportDate = t1.ReportDate")
    h <- sql.in("HSecurityId", sql.tbl("HSecurityId", "SecurityHistory", 
        "SecurityId = @secId"))
    z <- sql.tbl(c("yyyymm = convert(char(6), t1.ReportDate, 112)", 
        "FloDlr = sum(Flow * HoldingValue/AUM)"), z, h, "t1.ReportDate")
    z <- paste(c(x, "", sql.unbracket(z)), collapse = "\n")
    z
}

#' sqlts.TopDownAllocs
#' 
#' SQL query for Top-Down Allocations
#' @param x = the security id for which you want data
#' @param y = a string vector specifying types of allocation wanted
#' @keywords sqlts.TopDownAllocs
#' @export
#' @family sqlts

sqlts.TopDownAllocs <- function (x, y) 
{
    if (missing(y)) 
        y <- paste0(txt.expand(c("S", "F"), c("Ex", "In"), "wtd"), 
            "0")
    x <- sql.declare("@secId", "int", x)
    z <- sql.and(list(A = "h.ReportDate = t.ReportDate", B = "h.HFundId = t.HFundId"))
    z <- sql.exists(sql.tbl("ReportDate, HFundId", "Holdings h", 
        z))
    z <- sql.tbl("ReportDate, HFundId, AssetsEnd = sum(AssetsEnd)", 
        "MonthlyData t", z, "ReportDate, HFundId", "sum(AssetsEnd) > 0")
    z <- sql.label(z, "t1")
    h <- sql.in("HSecurityId", sql.tbl("HSecurityId", "SecurityHistory", 
        "SecurityId = @secId"))
    h <- sql.label(sql.Holdings(h, c("ReportDate", "HFundId", 
        "HoldingValue")), "t2")
    z <- c(z, "left join", h, "\ton t2.HFundId = t1.HFundId and t2.ReportDate = t1.ReportDate")
    z <- sql.tbl(c("yyyymm = convert(char(6), t1.ReportDate, 112)", 
        sql.TopDownAllocs.items(y)), z, , "t1.ReportDate")
    z <- paste(c(x, "", sql.unbracket(z)), collapse = "\n")
    z
}

#' sqlts.wrapper
#' 
#' SQL query for monthly dollar flow
#' @param x = a vector of security id's
#' @param y = data item wanted (Daily/Monthly/Allocation)
#' @keywords sqlts.wrapper
#' @export
#' @family sqlts

sqlts.wrapper <- function (x, y) 
{
    w <- vec.named(c("sqlts.FloDollar.daily", "sqlts.FloDollar.monthly", 
        "sqlts.TopDownAllocs"), c("Daily", "Monthly", "Allocation"))
    y <- get(w[y])
    z <- list()
    h <- sql.connect("StockFlows")
    for (i in x) {
        cat(i, "...\n")
        z[[as.character(i)]] <- sqlQuery(h, y(i), stringsAsFactors = F)
    }
    close(h)
    z <- list.common.row.space(union, z, 1)
    z <- sapply(z, as.matrix, simplify = "array")[, -1, ]
    z
}

#' strategy.dir
#' 
#' factor folder
#' @param x = "daily" or "weekly"
#' @keywords strategy.dir
#' @export
#' @family strategy

strategy.dir <- function (x) 
{
    paste(dir.parameters("data"), x, sep = "\\")
}

#' strategy.file
#' 
#' Returns the file in which the factor lives
#' @param x = name of the strategy (e.g. "FX" or "PremSec-JP")
#' @param y = "daily" or "weekly"
#' @keywords strategy.file
#' @export
#' @family strategy

strategy.file <- function (x, y) 
{
    paste0(x, "-", y, ".csv")
}

#' strategy.path
#' 
#' Returns the full path to the factor file
#' @param x = name of the strategy (e.g. "FX" or "PremSec-JP")
#' @param y = "daily" or "weekly"
#' @keywords strategy.path
#' @export
#' @family strategy

strategy.path <- function (x, y) 
{
    paste(strategy.dir(y), strategy.file(x, y), sep = "\\")
}

#' stunden
#' 
#' vector of <x> random numbers within +/-1 of, and averaging to, <y>
#' @param x = integer
#' @param y = integer
#' @keywords stunden
#' @export

stunden <- function (x, y = 8) 
{
    z <- y - 1
    while (mean(z) != y) {
        z <- NULL
        while (length(z) < x) {
            n <- seq(-1, 1) + y
            z <- c(z, n[order(rnorm(length(n)))][1])
        }
    }
    z
}

#' summ.multi
#' 
#' summarizes the multi-period back test
#' @param fcn = a function that summarizes the data
#' @param x = a df of bin returns indexed by time
#' @param y = forward return horizon size
#' @keywords summ.multi
#' @export

summ.multi <- function (fcn, x, y) 
{
    if (y == 1) {
        z <- fcn(x)
    }
    else {
        z <- split(x, 1:dim(x)[1]%%y)
        z <- sapply(z, fcn, simplify = "array")
        z <- apply(z, 2:length(dim(z)) - 1, mean)
    }
    z
}

#' today
#' 
#' returns system date as a yyyymmdd
#' @keywords today
#' @export

today <- function () 
{
    z <- Sys.Date()
    z <- day.ex.date(z)
    z
}

#' txt.anagram
#' 
#' all possible anagrams
#' @param x = a SINGLE string
#' @param y = a file of potentially-usable capitalized words
#' @param n = vector of minimum number of characters for first few words
#' @keywords txt.anagram
#' @export
#' @family txt

txt.anagram <- function (x, y, n = 0) 
{
    x <- toupper(x)
    x <- txt.to.char(x)
    x <- x[is.element(x, LETTERS)]
    x <- paste(x, collapse = "")
    if (missing(y)) 
        y <- txt.words()
    else y <- txt.words(y)
    y <- y[order(y, decreasing = T)]
    y <- y[order(nchar(y))]
    z <- txt.anagram.underlying(x, y, n)
    z
}

#' txt.anagram.underlying
#' 
#' all possible anagrams
#' @param x = a SINGLE string
#' @param y = potentially-usable capitalized words
#' @param n = vector of minimum number of characters for first few words
#' @keywords txt.anagram.underlying
#' @export
#' @family txt

txt.anagram.underlying <- function (x, y, n) 
{
    y <- y[txt.excise(y, txt.to.char(x)) == ""]
    z <- NULL
    m <- length(y)
    proceed <- m > 0
    if (proceed) 
        proceed <- nchar(y[m]) >= n[1]
    while (proceed) {
        w <- txt.excise(x, txt.to.char(y[m]))
        if (nchar(w) == 0) {
            z <- c(z, y[m])
        }
        else if (m > 1) {
            w <- txt.anagram.underlying(w, y[2:m - 1], c(n, 0)[-1])
            if (!is.null(w)) 
                z <- c(z, paste(y[m], w))
        }
        m <- m - 1
        proceed <- m > 0
        if (proceed) 
            proceed <- nchar(y[m]) >= n[1]
    }
    z
}

#' txt.core
#' 
#' renders with upper-case letters, spaces and numbers only
#' @param x = a vector
#' @keywords txt.core
#' @export
#' @family txt

txt.core <- function (x) 
{
    x <- toupper(x)
    m <- nchar(x)
    n <- max(m)
    while (n > 0) {
        w <- m >= n
        w[w] <- !is.element(substring(x[w], n, n), c(" ", LETTERS, 
            0:9))
        h <- w & m == n
        if (any(h)) {
            x[h] <- txt.left(x[h], n - 1)
            m[h] <- m[h] - 1
        }
        h <- w & m > n
        if (any(h)) 
            x[h] <- paste(txt.left(x[h], n - 1), substring(x[h], 
                n + 1, m[h]))
        n <- n - 1
    }
    x <- txt.trim(x)
    z <- txt.itrim(x)
    z
}

#' txt.count
#' 
#' counts the number of occurences of <y> in each element of <x>
#' @param x = a vector of strings
#' @param y = a substring
#' @keywords txt.count
#' @export
#' @family txt

txt.count <- function (x, y) 
{
    z <- txt.replace(x, y, "")
    z <- nchar(z)
    z <- nchar(x) - z
    z <- z/nchar(y)
    z
}

#' txt.ex.file
#' 
#' reads in the file as a single string
#' @param x = path to a text file
#' @keywords txt.ex.file
#' @export
#' @family txt

txt.ex.file <- function (x) 
{
    paste(vec.read(x, F), collapse = "\n")
}

#' txt.excise
#' 
#' cuts out elements of <y> from <x> wherever found
#' @param x = a vector
#' @param y = a vector
#' @keywords txt.excise
#' @export
#' @family txt

txt.excise <- function (x, y) 
{
    z <- x
    for (j in y) {
        m <- nchar(j)
        j <- as.numeric(regexpr(j, z, fixed = T))
        n <- nchar(z)
        z <- ifelse(j == 1, substring(z, m + 1, n), z)
        z <- ifelse(j == n - m + 1, substring(z, 1, j - 1), z)
        z <- ifelse(j > 1 & j < n - m + 1, paste0(substring(z, 
            1, j - 1), substring(z, j + m, n)), z)
    }
    z
}

#' txt.expand
#' 
#' Returns all combinations OF <x> and <y> pasted together
#' @param x = a vector of strings
#' @param y = a vector of strings
#' @param n = paste separator
#' @param w = T/F variable controlling paste order
#' @keywords txt.expand
#' @export
#' @family txt

txt.expand <- function (x, y, n = "-", w = F) 
{
    z <- list(x = x, y = y)
    if (w) 
        z <- expand.grid(z, stringsAsFactors = F)
    else z <- rev(expand.grid(rev(z), stringsAsFactors = F))
    z[["sep"]] <- n
    z <- do.call(paste, z)
    z
}

#' txt.gunning
#' 
#' the Gunning fog index measuring the number of years of  schooling beyond kindergarten needed to comprehend <x>
#' @param x = a string representing a text passage
#' @param y = a file of potentially-usable capitalized words
#' @param n = a file of potentially-usable capitalized words considered "simple"
#' @keywords txt.gunning
#' @export
#' @family txt

txt.gunning <- function (x, y, n) 
{
    x <- toupper(x)
    x <- txt.replace(x, "-", " ")
    x <- txt.replace(x, "?", ".")
    x <- txt.replace(x, "!", ".")
    x <- txt.to.char(x)
    x <- x[is.element(x, c(LETTERS, " ", "."))]
    x <- paste(x, collapse = "")
    x <- txt.replace(x, ".", " . ")
    x <- txt.trim(x)
    while (x != txt.replace(x, txt.space(2), txt.space(1))) x <- txt.replace(x, 
        txt.space(2), txt.space(1))
    if (txt.right(x, 1) == ".") 
        x <- txt.left(x, nchar(x) - 1)
    x <- txt.trim(x)
    if (missing(y)) 
        y <- txt.words()
    else y <- txt.words(y)
    x <- as.character(txt.parse(x, " "))
    x <- x[is.element(x, c(y, "."))]
    z <- 1 + sum(x == ".")
    x <- x[x != "."]
    h <- length(x)
    if (h < 100) 
        cat("Passage needs to have at least a 100 words.\nNeed at least", 
            100 - h, "more words ...\n")
    z <- h/nonneg(z)
    if (missing(n)) {
        n <- union(txt.words(1), txt.words(2))
    }
    else {
        n <- txt.words(n)
    }
    if (any(!is.element(x, n))) {
        x <- x[!is.element(x, n)]
        n <- length(x)/nonneg(h)
        x <- x[!duplicated(x)]
        x <- x[order(nchar(x))]
    }
    else {
        n <- 0
        x <- NULL
    }
    z <- list(result = 0.4 * (z + 100 * n), complex = x)
    z
}

#' txt.has
#' 
#' the elements of <x> that contain <y> if <n> is F or a logical vector otherwise
#' @param x = a vector of strings
#' @param y = a single string
#' @param n = T/F depending on whether a logical vector is desired
#' @keywords txt.has
#' @export
#' @family txt

txt.has <- function (x, y, n = F) 
{
    z <- grepl(y, x, fixed = T)
    if (!n) 
        z <- x[z]
    z
}

#' txt.hdr
#' 
#' nice-looking header
#' @param x = any string
#' @keywords txt.hdr
#' @export
#' @family txt

txt.hdr <- function (x) 
{
    n <- nchar(x)
    if (n%%2 == 1) {
        x <- paste0(x, " ")
        n <- n + 1
    }
    n <- 100 - n
    n <- n/2
    z <- paste0(txt.space(n, "*"), x, txt.space(n, "*"))
    z
}

#' txt.itrim
#' 
#' gets rid of multiple consecutive spaces
#' @param x = a vector of strings
#' @keywords txt.itrim
#' @export
#' @family txt

txt.itrim <- function (x) 
{
    z <- txt.replace(x, txt.space(2), txt.space(1))
    w <- z != x
    while (any(w)) {
        x[w] <- z[w]
        z[w] <- txt.replace(x[w], txt.space(2), txt.space(1))
        w[w] <- z[w] != x[w]
    }
    z
}

#' txt.left
#' 
#' Returns the left <y> characters
#' @param x = a vector of string
#' @param y = a positive integer
#' @keywords txt.left
#' @export
#' @family txt

txt.left <- function (x, y) 
{
    substring(x, 1, y)
}

#' txt.levenshtein
#' 
#' Levenshtein distance between <x> and <y>
#' @param x = a string
#' @param y = a string
#' @keywords txt.levenshtein
#' @export
#' @family txt

txt.levenshtein <- function (x, y) 
{
    n <- nchar(x)
    m <- nchar(y)
    if (min(m, n) == 0) {
        z <- max(m, n)
    }
    else {
        x <- c("", txt.to.char(x))
        y <- c("", txt.to.char(y))
        z <- matrix(NA, n + 1, m + 1, F, list(x, y))
        z[1, ] <- 0:m
        z[, 1] <- 0:n
        for (i in 1:m + 1) {
            for (j in 1:n + 1) {
                z[j, i] <- min(z[j - 1, i], z[j, i - 1]) + 1
                z[j, i] <- min(z[j, i], z[j - 1, i - 1] + as.numeric(x[j] != 
                  y[i]))
            }
        }
        z <- z[n + 1, m + 1]
    }
    z
}

#' txt.na
#' 
#' Returns a list of strings considered NA
#' @keywords txt.na
#' @export
#' @family txt

txt.na <- function () 
{
    c("#N/A", "NA", "NULL", "<NA>", "--", "#N/A N/A")
}

#' txt.name.format
#' 
#' capitalizes first letter of each word, rendering remaining letters in lower case
#' @param x = a string vector
#' @keywords txt.name.format
#' @export
#' @family txt

txt.name.format <- function (x) 
{
    if (any(txt.has(x, " ", T))) {
        z <- txt.parse(x, " ")
        z <- fcn.mat.vec(txt.name.format, z, , T)
        z <- do.call(paste, mat.ex.matrix(z))
        z <- txt.trim(z)
    }
    else {
        x <- tolower(x)
        z <- txt.left(x, 1)
        x <- txt.right(x, nchar(x) - 1)
        z <- paste0(toupper(z), x)
    }
    z
}

#' txt.parse
#' 
#' breaks up string <x> by <y>
#' @param x = a vector of strings
#' @param y = a string that serves as a delimiter
#' @keywords txt.parse
#' @export
#' @family txt

txt.parse <- function (x, y) 
{
    if (any(is.na(x))) 
        stop("Bad")
    x0 <- x
    ctr <- 1
    z <- list()
    w <- as.numeric(regexpr(y, x, fixed = T))
    while (any(!is.element(w, -1))) {
        w <- ifelse(is.element(w, -1), 1 + nchar(x), w)
        vec <- ifelse(w > 1, substring(x, 1, w - 1), "")
        z[[paste("pos", ctr, sep = ".")]] <- vec
        x <- txt.right(x, nchar(x) - nchar(vec) - nchar(y))
        ctr <- ctr + 1
        w <- as.numeric(regexpr(y, x, fixed = T))
    }
    z[[paste("pos", ctr, sep = ".")]] <- x
    if (length(x0) > 1) {
        z <- mat.ex.matrix(z)
        if (all(!duplicated(x0))) 
            dimnames(z)[[1]] <- x0
    }
    else z <- unlist(z)
    z
}

#' txt.prepend
#' 
#' bulks up each string to have at least <y> characters by adding <n> to the beginning of each string
#' @param x = a vector of strings
#' @param y = number of characters to add
#' @param n = the characters to add at the beginning
#' @keywords txt.prepend
#' @export
#' @family txt

txt.prepend <- function (x, y, n) 
{
    z <- x
    w <- nchar(z) < y
    while (any(w)) {
        z[w] <- paste0(n, z[w])
        w <- nchar(z) < y
    }
    z
}

#' txt.regr
#' 
#' returns the string you need to regress the first column on the others
#' @param x = a vector of column names
#' @param y = T/F depending on whether regression has an intercept
#' @keywords txt.regr
#' @export
#' @family txt

txt.regr <- function (x, y = T) 
{
    z <- x[1]
    x <- x[-1]
    if (!y) 
        x <- c("-1", x)
    x <- paste(x, collapse = " + ")
    z <- paste(z, x, sep = " ~ ")
    z
}

#' txt.replace
#' 
#' replaces all instances of <txt.out> by <txt.by>
#' @param x = a vector of strings
#' @param y = a string to be swapped out
#' @param n = a string to replace <txt.out> with
#' @keywords txt.replace
#' @export
#' @family txt

txt.replace <- function (x, y, n) 
{
    gsub(y, n, x, fixed = T)
}

#' txt.reverse
#' 
#' reverses the constitutent characters of <x>
#' @param x = vector of strings
#' @keywords txt.reverse
#' @export
#' @family txt

txt.reverse <- function (x) 
{
    fcn <- function(x) paste(rev(txt.to.char(x)), collapse = "")
    z <- fcn.vec.num(fcn, x)
    z
}

#' txt.right
#' 
#' Returns the right <y> characters
#' @param x = a vector of string
#' @param y = a positive integer
#' @keywords txt.right
#' @export
#' @family txt

txt.right <- function (x, y) 
{
    substring(x, nchar(x) - y + 1, nchar(x))
}

#' txt.space
#' 
#' returns <x> iterations of <y> pasted together
#' @param x = any integer
#' @param y = a single character
#' @keywords txt.space
#' @export
#' @family txt

txt.space <- function (x, y = " ") 
{
    z <- ""
    while (x > 0) {
        z <- paste0(z, y)
        x <- x - 1
    }
    z
}

#' txt.to.char
#' 
#' a vector of the constitutent characters of <x>
#' @param x = a SINGLE string
#' @keywords txt.to.char
#' @export
#' @family txt

txt.to.char <- function (x) 
{
    strsplit(x, "")[[1]]
}

#' txt.trim
#' 
#' trims leading/trailing spaces
#' @param x = a vector of string
#' @param y = a vector of verboten strings, each of the same length
#' @keywords txt.trim
#' @export
#' @family txt

txt.trim <- function (x, y = " ") 
{
    txt.trim.right(txt.trim.left(x, y), y)
}

#' txt.trim.end
#' 
#' trims off leading or trailing elements of <y>
#' @param fcn = a function that returns characters from the bad end
#' @param x = a vector of string
#' @param y = a vector of verboten strings, each of the same length
#' @param n = a functon that returns characters from the opposite end
#' @keywords txt.trim.end
#' @export
#' @family txt

txt.trim.end <- function (fcn, x, y, n) 
{
    h <- nchar(y[1])
    z <- x
    w <- nchar(z) > h - 1 & is.element(fcn(z, h), y)
    while (any(w)) {
        z[w] <- n(z[w], nchar(z[w]) - h)
        w <- nchar(z) > h - 1 & is.element(fcn(z, h), y)
    }
    z
}

#' txt.trim.left
#' 
#' trims off leading elements of <y>
#' @param x = a vector of string
#' @param y = a vector of verboten strings, each of the same length
#' @keywords txt.trim.left
#' @export
#' @family txt

txt.trim.left <- function (x, y) 
{
    txt.trim.end(txt.left, x, y, txt.right)
}

#' txt.trim.right
#' 
#' trims off trailing elements of <y>
#' @param x = a vector of string
#' @param y = a vector of verboten strings, each of the same length
#' @keywords txt.trim.right
#' @export
#' @family txt

txt.trim.right <- function (x, y) 
{
    txt.trim.end(txt.right, x, y, txt.left)
}

#' txt.words
#' 
#' a vector of capitalized words
#' @param x = missing or an integer
#' @keywords txt.words
#' @export
#' @family txt

txt.words <- function (x = "All") 
{
    if (any(x == c("All", 1:2))) {
        if (x == "All") {
            z <- "EnglishWords.txt"
        }
        else if (x == 1) {
            z <- "EnglishWords-1syllable.txt"
        }
        else if (x == 2) {
            z <- "EnglishWords-2syllables.txt"
        }
        z <- paste(dir.parameters("data"), z, sep = "\\")
    }
    else {
        z <- x
    }
    z <- vec.read(z, F)
    z
}

#' urn.exact
#' 
#' probability of drawing precisely <x> balls from an urn containing <y> balls
#' @param x = a vector of integers
#' @param y = an isomekic vector of integers that is pointwise greater than or equal to <x>
#' @keywords urn.exact
#' @export

urn.exact <- function (x, y) 
{
    z <- 1
    for (i in 1:length(x)) z <- z * factorial(y[i])/(factorial(x[i]) * 
        factorial(y[i] - x[i]))
    z <- (z/factorial(sum(y))) * factorial(sum(x)) * factorial(sum(y - 
        x))
    z
}

#' variance.ratio.test
#' 
#' tests whether <x> follows a random walk (i.e. <x> independent of prior values)
#' @param x = vector
#' @param y = an integer greater than 1
#' @keywords variance.ratio.test
#' @export

variance.ratio.test <- function (x, y) 
{
    y <- as.numeric(y)
    if (is.na(y) | y == 1) 
        stop("Bad value of y ...")
    x <- x - mean(x)
    T <- length(x)
    sd.1 <- sum(x^2)/(T - 1)
    z <- x[y:T]
    for (i in 2:y - 1) z <- z + x[y:T - i]
    sd.y <- sum(z^2)/(T - y - 1)
    z <- sd.y/(y * sd.1 * (1 - y/T))
    z
}

#' vec.cat
#' 
#' displays on screen
#' @param x = vector
#' @keywords vec.cat
#' @export
#' @family vec

vec.cat <- function (x) 
{
    cat(paste(x, collapse = "\n"), "\n")
}

#' vec.count
#' 
#' Counts unique instances of <x>
#' @param x = a numeric vector
#' @keywords vec.count
#' @export
#' @family vec

vec.count <- function (x) 
{
    pivot.1d(sum, x, rep(1, length(x)))
}

#' vec.last.element.increment
#' 
#' increments last element of <x> by <y>
#' @param x = a numeric vector
#' @param y = increment (defaults to unity)
#' @keywords vec.last.element.increment
#' @export
#' @family vec

vec.last.element.increment <- function (x, y = 1) 
{
    n <- length(x)
    x[n] <- x[n] + 1
    z <- x
    z
}

#' vec.max
#' 
#' Returns the piecewise maximum of <x> and <y>
#' @param x = a vector/matrix/dataframe
#' @param y = a number/vector or matrix/dataframe with the same dimensions as <x>
#' @keywords vec.max
#' @export
#' @family vec

vec.max <- function (x, y) 
{
    fcn <- function(x, y) ifelse(!is.na(x) & !is.na(y) & x < 
        y, y, x)
    z <- fcn.mat.vec(fcn, x, y, T)
    z
}

#' vec.min
#' 
#' Returns the piecewise minimum of <x> and <y>
#' @param x = a vector/matrix/dataframe
#' @param y = a number/vector or matrix/dataframe with the same dimensions as <x>
#' @keywords vec.min
#' @export
#' @family vec

vec.min <- function (x, y) 
{
    fcn <- function(x, y) ifelse(!is.na(x) & !is.na(y) & x > 
        y, y, x)
    z <- fcn.mat.vec(fcn, x, y, T)
    z
}

#' vec.named
#' 
#' Returns a vector with values <x> and names <y>
#' @param x = a vector
#' @param y = an isomekic vector
#' @keywords vec.named
#' @export
#' @family vec

vec.named <- function (x, y) 
{
    if (missing(x)) 
        x <- rep(NA, length(y))
    z <- x
    names(z) <- y
    z
}

#' vec.read
#' 
#' reads into a vector
#' @param x = path to a vector
#' @param y = T/F depending on whether the elements are named
#' @keywords vec.read
#' @export
#' @family vec

vec.read <- function (x, y) 
{
    if (!y & !file.exists(x)) {
        stop("File ", x, " doesn't exist!\n")
    }
    else if (!y) {
        z <- scan(x, what = "", sep = "\n", quiet = T)
    }
    else z <- as.matrix(mat.read(x, ",", , F))[, 1]
    z
}

#' vec.same
#' 
#' T/F depending on whether <x> and <y> are identical
#' @param x = a vector
#' @param y = an isomekic vector
#' @keywords vec.same
#' @export
#' @family vec

vec.same <- function (x, y) 
{
    z <- all(is.na(x) == is.na(y))
    if (z) {
        w <- !is.na(x)
        if (any(w)) 
            z <- all(abs(x[w] - y[w]) < 1e-06)
    }
    z
}

#' vec.swap
#' 
#' swaps elements <y> and <n> of vector <x>
#' @param x = a vector
#' @param y = an integer between 1 and length(<x>)
#' @param n = an integer between 1 and length(<x>)
#' @keywords vec.swap
#' @export
#' @family vec

vec.swap <- function (x, y, n) 
{
    z <- x[y]
    x[y] <- x[n]
    x[n] <- z
    z <- x
    z
}

#' vec.to.lags
#' 
#' a data frame of <x> together with itself lagged 1, ..., <y> - 1 times
#' @param x = a numeric vector (time flows forward)
#' @param y = number of lagged values desired plus one
#' @param n = T/F depending on whether time flows forwards
#' @keywords vec.to.lags
#' @export
#' @family vec

vec.to.lags <- function (x, y, n = T) 
{
    m <- length(x)
    z <- mat.ex.matrix(matrix(NA, m, y, F, list(1:m, paste0("lag", 
        1:y - 1))))
    if (!n) 
        x <- rev(x)
    for (i in 1:y) z[i:m, i] <- x[i:m - i + 1]
    if (!n) 
        z <- mat.reverse(z)
    z
}

#' vec.to.list
#' 
#' list object
#' @param x = string vector
#' @keywords vec.to.list
#' @export
#' @family vec

vec.to.list <- function (x) 
{
    split(x, 1:length(x))
}

#' vec.unique
#' 
#' returns unique values of <x> in ascending order
#' @param x = a numeric vector
#' @keywords vec.unique
#' @export
#' @family vec

vec.unique <- function (x) 
{
    z <- unlist(x)
    z <- z[!is.na(z)]
    z <- z[!duplicated(z)]
    z <- z[order(z)]
    z
}

#' weekday.to.name
#' 
#' Converts to 0 = Sun, 1 = Mon, ..., 6 = Sat
#' @param x = a vector of numbers between 0 and 6
#' @keywords weekday.to.name
#' @export

weekday.to.name <- function (x) 
{
    y <- c("Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat")
    y <- vec.named(y, 0:6)
    z <- map.rname(y, x)
    z <- as.character(z)
    z
}

#' yyyy.ex.period
#' 
#' the year in which the return window ends
#' @param x = vector of trade dates
#' @param y = return window in days or months depending on whether <x> is YYYYMMDD or YYYYMM
#' @keywords yyyy.ex.period
#' @export
#' @family yyyy

yyyy.ex.period <- function (x, y) 
{
    txt.left(yyyymm.lag(x, -y), 4)
}

#' yyyy.ex.yy
#' 
#' returns a vector of YYYY
#' @param x = a vector of non-negative integers
#' @keywords yyyy.ex.yy
#' @export
#' @family yyyy

yyyy.ex.yy <- function (x) 
{
    x <- as.numeric(x)
    z <- ifelse(x < 100, ifelse(x < 50, 2000, 1900), 0) + x
    z
}

#' yyyy.periods.count
#' 
#' the number of periods that typically fall in a year
#' @param x = a string vector
#' @keywords yyyy.periods.count
#' @export
#' @family yyyy

yyyy.periods.count <- function (x) 
{
    ifelse(all(nchar(x) == 6), ifelse(all(substring(x, 5, 5) == 
        "Q"), 4, 12), 260)
}

#' yyyymm.diff
#' 
#' returns <x - y> in terms of YYYYMM
#' @param x = a vector of YYYYMM
#' @param y = an isomekic vector of YYYYMM
#' @keywords yyyymm.diff
#' @export
#' @family yyyymm

yyyymm.diff <- function (x, y) 
{
    obj.diff(yyyymm.to.int, x, y)
}

#' yyyymm.ex.int
#' 
#' returns a vector of <yyyymm> months
#' @param x = a vector of integers
#' @keywords yyyymm.ex.int
#' @export
#' @family yyyymm

yyyymm.ex.int <- function (x) 
{
    z <- (x - 1)%/%12
    x <- x - 12 * z
    z <- 100 * z + x
    z <- as.character(z)
    z <- txt.prepend(z, 6, 0)
    z
}

#' yyyymm.ex.qtr
#' 
#' returns quarter end in yyyymm
#' @param x = a vector of quarters
#' @keywords yyyymm.ex.qtr
#' @export
#' @family yyyymm

yyyymm.ex.qtr <- function (x) 
{
    z <- qtr.to.int(x)
    z <- yyyymm.ex.int(z * 3)
    z
}

#' yyyymm.lag
#' 
#' lags <x> by <y> periods
#' @param x = a vector of <yyyymm> months or <yyyymmdd> days
#' @param y = an integer or an isomekic vector of integers
#' @param n = T/F depending on whether you wish to lag by yyyymmdd or flowdate
#' @keywords yyyymm.lag
#' @export
#' @family yyyymm

yyyymm.lag <- function (x, y = 1, n = T) 
{
    if (nchar(x[1]) == 8 & n) {
        z <- yyyymmdd.lag(x, y)
    }
    else if (nchar(x[1]) == 8 & !n) {
        z <- flowdate.lag(x, y)
    }
    else if (substring(x[1], 5, 5) == "Q") {
        z <- qtr.lag(x, y)
    }
    else {
        z <- obj.lag(x, y, yyyymm.to.int, yyyymm.ex.int)
    }
    z
}

#' yyyymm.seq
#' 
#' returns a sequence between (and including) x and y
#' @param x = a YYYYMM or YYYYMMDD or YYYY
#' @param y = an isotypic element
#' @param n = quantum size in YYYYMM or YYYYMMDD or YYYY
#' @keywords yyyymm.seq
#' @export
#' @family yyyymm

yyyymm.seq <- function (x, y, n = 1) 
{
    if (nchar(x) == 4) {
        z <- seq(x, y, n)
    }
    else if (nchar(x) == 8) {
        z <- yyyymmdd.seq(x, y, n)
    }
    else {
        z <- obj.seq(x, y, yyyymm.to.int, yyyymm.ex.int, n)
    }
    z
}

#' yyyymm.to.day
#' 
#' Returns the last day in the month whether weekend or not.
#' @param x = a vector of months in yyyymm format
#' @keywords yyyymm.to.day
#' @export
#' @family yyyymm

yyyymm.to.day <- function (x) 
{
    day.lag(paste0(yyyymm.lag(x, -1), "01"), 1)
}

#' yyyymm.to.int
#' 
#' returns a vector of integers
#' @param x = a vector of <yyyymm> months
#' @keywords yyyymm.to.int
#' @export
#' @family yyyymm

yyyymm.to.int <- function (x) 
{
    z <- as.numeric(substring(x, 1, 4))
    z <- 12 * z + as.numeric(substring(x, 5, 6))
    z
}

#' yyyymm.to.qtr
#' 
#' returns associated quarters
#' @param x = a vector of yyyymm
#' @keywords yyyymm.to.qtr
#' @export
#' @family yyyymm

yyyymm.to.qtr <- function (x) 
{
    z <- yyyymm.to.int(x)
    z <- z + (3 - z)%%3
    z <- qtr.ex.int(z/3)
    z
}

#' yyyymm.to.yyyy
#' 
#' Converts to yyyy years
#' @param x = a vector of dates in yyyymm format
#' @keywords yyyymm.to.yyyy
#' @export
#' @family yyyymm

yyyymm.to.yyyy <- function (x) 
{
    z <- as.numeric(x)
    z <- z%/%100
    z
}

#' yyyymmdd.bulk
#' 
#' Eliminates YYYYMMDD gaps
#' @param x = a matrix/df indexed by YYYYMMDD
#' @keywords yyyymmdd.bulk
#' @export
#' @family yyyymmdd

yyyymmdd.bulk <- function (x) 
{
    z <- dimnames(x)[[1]]
    z <- yyyymm.seq(z[1], z[dim(x)[1]])
    w <- !is.element(z, dimnames(x)[[1]])
    if (any(w)) 
        err.raise(z[w], F, "Following weekdays missing from data")
    z <- map.rname(x, z)
    z
}

#' yyyymmdd.diff
#' 
#' returns <x - y> in terms of weekdays
#' @param x = a vector of weekdays
#' @param y = an isomekic vector of weekdays
#' @keywords yyyymmdd.diff
#' @export
#' @family yyyymmdd

yyyymmdd.diff <- function (x, y) 
{
    obj.diff(yyyymmdd.to.int, x, y)
}

#' yyyymmdd.ex.AllocMo
#' 
#' Returns an object indexed by flow dates
#' @param x = an object indexed by allocation months
#' @keywords yyyymmdd.ex.AllocMo
#' @export
#' @family yyyymmdd

yyyymmdd.ex.AllocMo <- function (x) 
{
    y <- dimnames(x)[[1]]
    y <- y[order(y)]
    begPrd <- yyyymmdd.ex.yyyymm(y[1], F)[1]
    endPrd <- yyyymmdd.ex.yyyymm(yyyymm.lag(y[dim(x)[1]], -2), 
        T)
    y <- yyyymmdd.seq(begPrd, endPrd)
    y <- vec.named(yyyymmdd.to.AllocMo(y), y)
    y <- y[is.element(y, dimnames(x)[[1]])]
    z <- map.rname(x, y)
    dimnames(z)[[1]] <- names(y)
    z
}

#' yyyymmdd.ex.day
#' 
#' Falls back to the closest weekday
#' @param x = a vector of calendar dates
#' @keywords yyyymmdd.ex.day
#' @export
#' @family yyyymmdd

yyyymmdd.ex.day <- function (x) 
{
    z <- day.to.int(x)
    z <- z - vec.max(z%%7 - 4, 0)
    z <- day.ex.int(z)
    z
}

#' yyyymmdd.ex.int
#' 
#' the <x>th weekday after Monday, January 1, 2018
#' @param x = an integer or vector of integers
#' @keywords yyyymmdd.ex.int
#' @export
#' @family yyyymmdd

yyyymmdd.ex.int <- function (x) 
{
    day.ex.int(x + 2 * (x%/%5))
}

#' yyyymmdd.ex.txt
#' 
#' a vector of calendar dates in YYYYMMDD format
#' @param x = a vector of dates in some format
#' @param y = separators used within <x>
#' @param n = order in which month, day and year are represented
#' @keywords yyyymmdd.ex.txt
#' @export
#' @family yyyymmdd

yyyymmdd.ex.txt <- function (x, y = "/", n = "MDY") 
{
    m <- as.numeric(regexpr(" ", x))
    m <- ifelse(m == -1, 1 + nchar(x), m)
    x <- substring(x, 1, m - 1)
    z <- list()
    z[[txt.left(n, 1)]] <- substring(x, 1, as.numeric(regexpr(y, 
        x)) - 1)
    x <- substring(x, 2 + nchar(z[[1]]), nchar(x))
    z[[substring(n, 2, 2)]] <- substring(x, 1, as.numeric(regexpr(y, 
        x)) - 1)
    z[[substring(n, 3, 3)]] <- substring(x, 2 + nchar(z[[2]]), 
        nchar(x))
    x <- yyyy.ex.yy(z[["Y"]])
    z <- 10000 * x + 100 * as.numeric(z[["M"]]) + as.numeric(z[["D"]])
    z <- as.character(z)
    z
}

#' yyyymmdd.ex.yyyymm
#' 
#' last/all weekdays in <x>
#' @param x = a vector/single YYYYMM depending on if y is T/F
#' @param y = T/F variable depending on whether the last or all trading days in that month are desired
#' @keywords yyyymmdd.ex.yyyymm
#' @export
#' @family yyyymmdd

yyyymmdd.ex.yyyymm <- function (x, y = T) 
{
    z <- paste0(yyyymm.lag(x, -1), "01")
    z <- yyyymmdd.ex.day(z)
    w <- yyyymmdd.to.yyyymm(z) != x
    if (any(w)) 
        z[w] <- yyyymm.lag(z[w])
    if (!y & length(x) > 1) 
        stop("You can't do this ...\n")
    if (!y) {
        x <- paste0(x, "01")
        x <- yyyymmdd.ex.day(x)
        if (yyyymmdd.to.yyyymm(x) != yyyymmdd.to.yyyymm(z)) 
            x <- yyyymm.lag(x, -1)
        z <- yyyymm.seq(x, z)
    }
    z
}

#' yyyymmdd.exists
#' 
#' returns T if <x> is a weekday
#' @param x = a vector of calendar dates
#' @keywords yyyymmdd.exists
#' @export
#' @family yyyymmdd

yyyymmdd.exists <- function (x) 
{
    is.element(day.to.weekday(x), 1:5)
}

#' yyyymmdd.lag
#' 
#' lags <x> by <y> weekdays
#' @param x = a vector of weekdays
#' @param y = an integer
#' @keywords yyyymmdd.lag
#' @export
#' @family yyyymmdd

yyyymmdd.lag <- function (x, y) 
{
    obj.lag(x, y, yyyymmdd.to.int, yyyymmdd.ex.int)
}

#' yyyymmdd.seq
#' 
#' a sequence of weekdays starting at <x> and, if possible, ending at <y>
#' @param x = a single weekday
#' @param y = a single weekday
#' @param n = a positive integer
#' @keywords yyyymmdd.seq
#' @export
#' @family yyyymmdd

yyyymmdd.seq <- function (x, y, n = 1) 
{
    if (any(!yyyymmdd.exists(c(x, y)))) 
        stop("Inputs are not weekdays")
    z <- obj.seq(x, y, yyyymmdd.to.int, yyyymmdd.ex.int, n)
    z
}

#' yyyymmdd.to.AllocMo
#' 
#' Returns the month for which you need to get allocations Flows as of the 23rd of each month are known by the 24th. By this time allocations from the previous month are known
#' @param x = the date for which you want flows (known one day later)
#' @param y = calendar day in the next month when allocations are known (usually the 23rd)
#' @keywords yyyymmdd.to.AllocMo
#' @export
#' @family yyyymmdd

yyyymmdd.to.AllocMo <- function (x, y = 23) 
{
    n <- txt.right(x, 2)
    n <- as.numeric(n)
    n <- ifelse(n < y, 2, 1)
    z <- yyyymmdd.to.yyyymm(x)
    z <- yyyymm.lag(z, n)
    z
}

#' yyyymmdd.to.CalYrDyOfWk
#' 
#' Converts to 0 = Sun, 1 = Mon, ..., 6 = Sat
#' @param x = a vector of dates in yyyymmdd format
#' @keywords yyyymmdd.to.CalYrDyOfWk
#' @export
#' @family yyyymmdd

yyyymmdd.to.CalYrDyOfWk <- function (x) 
{
    z <- day.to.weekday(x)
    z <- as.numeric(z)
    z <- z/10
    x <- substring(x, 1, 4)
    x <- as.numeric(x)
    z <- x + z
    z
}

#' yyyymmdd.to.int
#' 
#' number of weekdays after Monday, January 1, 2018
#' @param x = a vector of weekdays in YYYYMMDD format
#' @keywords yyyymmdd.to.int
#' @export
#' @family yyyymmdd

yyyymmdd.to.int <- function (x) 
{
    z <- day.to.int(x)
    z <- z - 2 * (z%/%7)
    z
}

#' yyyymmdd.to.txt
#' 
#' Engineering date format
#' @param x = a vector of YYYYMMDD
#' @keywords yyyymmdd.to.txt
#' @export
#' @family yyyymmdd

yyyymmdd.to.txt <- function (x) 
{
    paste(format(day.to.date(x), "%m/%d/%Y"), "12:00:00 AM")
}

#' yyyymmdd.to.unity
#' 
#' returns a vector of 1's corresponding to the length of <x>
#' @param x = a vector of dates in yyyymmdd format
#' @keywords yyyymmdd.to.unity
#' @export
#' @family yyyymmdd

yyyymmdd.to.unity <- function (x) 
{
    rep(1, length(x))
}

#' yyyymmdd.to.weekofmonth
#' 
#' returns 1 if the date fell in the first week of the month, 2 if it fell in the second, etc.
#' @param x = a vector of dates in yyyymmdd format
#' @keywords yyyymmdd.to.weekofmonth
#' @export
#' @family yyyymmdd

yyyymmdd.to.weekofmonth <- function (x) 
{
    z <- substring(x, 7, 8)
    z <- as.numeric(z)
    z <- (z - 1)%/%7 + 1
    z
}

#' yyyymmdd.to.yyyymm
#' 
#' Converts to yyyymm format
#' @param x = a vector of dates in yyyymmdd format
#' @param y = if T then falls back one month
#' @keywords yyyymmdd.to.yyyymm
#' @export
#' @family yyyymmdd

yyyymmdd.to.yyyymm <- function (x, y = F) 
{
    z <- substring(x, 1, 6)
    if (y) 
        z <- yyyymm.lag(z, 1)
    z
}

#' zav
#' 
#' Coverts NA's to zero
#' @param x = a vector/matrix/dataframe
#' @keywords zav
#' @export

zav <- function (x) 
{
    fcn <- function(x) ifelse(is.na(x), 0, x)
    z <- fcn.mat.vec(fcn, x, , T)
    z
}

#' zScore
#' 
#' Converts <x>, if a vector, or the rows of <x> otherwise, to a zScore
#' @param x = a vector/matrix/data-frame
#' @keywords zScore
#' @export

zScore <- function (x) 
{
    fcn.mat.vec(mat.zScore, x, , F)
}

#' zScore.underlying
#' 
#' zScores the first columns of <x> using the last column as weight
#' @param x = a vector/matrix/data-frame. The first columns are numeric while the last column is logical without NA's
#' @keywords zScore.underlying
#' @export

zScore.underlying <- function (x) 
{
    m <- dim(x)[1]
    n <- dim(x)[2]
    y <- x[, n]
    x <- x[, -n]
    if (sum(y) > 1 & n == 2) {
        mx <- mean(x[y], na.rm = T)
        sx <- nonneg(sd(x[y], na.rm = T))
        z <- (x - mx)/sx
    }
    else if (n == 2) {
        z <- rep(NA, length(x))
    }
    else if (sum(y) > 1) {
        mx <- colMeans(x[y, ], na.rm = T)
        sx <- apply(x[y, ], 2, sd, na.rm = T)
        z <- t(x)
        z <- (z - mx)/nonneg(sx)
        z <- mat.ex.matrix(t(z))
    }
    else {
        z <- matrix(NA, m, n - 1, F, dimnames(x))
        z <- mat.ex.matrix(z)
    }
    z
}
