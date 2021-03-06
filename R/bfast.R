bfast <- function (Yt, h = 0.15, season = c("dummy", "harmonic", "none"), 
                   max.iter = 10, breaks = NULL, hpc = "none", level = 0.05,
                   reg = "lm",
                   type = "OLS-MOSUM", ...) 
{
  # Error catching
  if(!(reg %in% c("lm","rlm"))) stop("Regression method unknown. ?bfast01")
  if(reg == "rlm") require(MASS)
  if(!require("stlplus",quietly = T)) stop("Please install the stlplus package!")
  ## Get Arguments
  season <- match.arg(season)
  level = rep(level, length.out = 2)
  ti <- time(Yt)
  f <- frequency(Yt)
  if (class(Yt) != "ts") 
    stop("Not a time series object")
  output <- list()
  Tt <- 0
  if (season == "harmonic") {
    w <- 1/f
    tl <- 1:length(Yt)
    co <- cos(2 * pi * tl * w)
    si <- sin(2 * pi * tl * w)
    co2 <- cos(2 * pi * tl * w * 2)
    si2 <- sin(2 * pi * tl * w * 2)
    co3 <- cos(2 * pi * tl * w * 3)
    si3 <- sin(2 * pi * tl * w * 3)
    smod <- Wt ~ co + si + co2 + si2 + co3 + si3
    St <- stlplus(Yt,t=ti,"periodic",n.p = f, ...)$data[, "seasonal"]
  }
  else if (season == "dummy") {
    St <-  stlplus(Yt,t=ti,"periodic",n.p = f, ...)$data[, "seasonal"]
    D <- seasonaldummy(Yt)
    D[rowSums(D) == 0, ] <- -1
    smod <- Wt ~ -1 + D
  }
  else if (season == "none") {
    print("No seasonal model will be fitted!")
    St <- 0
  }
  else stop("Not a correct seasonal model is selected ('harmonic' or 'dummy') ")
  Vt.bp <- 0
  Wt.bp <- 0
  CheckTimeTt <- 1
  CheckTimeSt <- 1
  i <- 0
  while ((!identical(CheckTimeTt, Vt.bp) | !identical(CheckTimeSt, 
                                                      Wt.bp)) & i < max.iter) {
    CheckTimeTt <- Vt.bp
    CheckTimeSt <- Wt.bp
    ### Change in trend component
    Vt <- Yt - St # Deasonalized Time series
    p.Vt <- sctest(efp(Vt ~ ti, h = h, type = type))
    if (p.Vt$p.value <= level[1]) {
      bp.Vt <- breakpoints(Vt ~ ti, h = h, breaks = breaks, na.action=na.exclude, 
                           hpc = hpc)
      nobp.Vt <- is.na(breakpoints(bp.Vt)[1])
    }
    else {
      nobp.Vt <- TRUE
      bp.Vt <- NA
    }
    if (nobp.Vt) {
      ## No Change detected
      fm0 <- lm(Vt ~ ti)
      Vt.bp <- 0
      Tt <- ts(data=NA,start = ti[1], end = ti[length(ti)],frequency = f)
      Tt[which(!is.na(Yt))] <- fitted(fm0) # Overwrite non-missing with fitted values
      tsp(Tt) <- tsp(Yt)
      ci.Vt <- NA
    }
    else {
      fm1 <- lm(Vt[which(!is.na(Yt))] ~ breakfactor(bp.Vt)/ti[which(!is.na(Yt))] )
      ci.Vt <- confint(bp.Vt, het.err = FALSE)
      Vt.bp <- ci.Vt$confint[, 2]
      # Define empty copy of original time series
      Tt <- ts(data=NA,start = ti[1], end = ti[length(ti)],frequency = f)
      Tt[which(!is.na(Yt))] <- fitted(fm1) # Overwrite non-missing with fitted values
      tsp(Tt) <- tsp(Yt)
    }
    if (season == "none") {
      Wt <- 0
      St <- 0
      bp.Wt <- NA
      ci.Wt <- NA
      nobp.Wt <- TRUE
    }
    else {
      ### Change in seasonal component
      Wt <- Yt - Tt
      p.Wt <- sctest(efp(smod, h = h, type = type))
      if (p.Wt$p.value <= level[2]) {
        bp.Wt <- breakpoints(smod, h = h, breaks = breaks, 
                             hpc = hpc)
        nobp.Wt <- is.na(breakpoints(bp.Wt)[1])
      }
      else {
        nobp.Wt <- TRUE
        bp.Wt <- NA
      }
      if (nobp.Wt) {
        ## No seasonal change detected
        sm0 <- lm(smod)
        St <- ts(data=NA,start = ti[1], end = ti[length(ti)],frequency = f)
        St[which(!is.na(Yt))] <- fitted(sm0) # Overwrite non-missing with fitted values
        tsp(St) <- tsp(Yt)
        Wt.bp <- 0
        ci.Wt <- NA
      }
      else {
        if (season == "dummy") 
          sm1 <- lm(Wt ~ -1 + D %in% breakfactor(bp.Wt))
        if (season == "harmonic") 
          sm1 <- lm(Wt ~ (co + si + co2 + si2 + co3 + 
                            si3) %in% breakfactor(bp.Wt))
        ci.Wt <- confint(bp.Wt, het.err = FALSE)
        Wt.bp <- ci.Wt$confint[, 2]
        
        # Define empty copy of original time series
        St <- ts(data=NA,start = ti[1], end = ti[length(ti)],frequency = f)
        St[which(!is.na(Yt))] <- fitted(sm1) # Overwrite non-missing with fitted values
        tsp(St) <- tsp(Yt)
        
      }
    }
    i <- i + 1
    output[[i]] <- list(Tt = Tt, St = St, Nt = Yt - Tt - 
                          St, Vt = Vt, bp.Vt = bp.Vt, Vt.bp = Vt.bp, ci.Vt = ci.Vt, 
                        Wt = Wt, bp.Wt = bp.Wt, Wt.bp = Wt.bp, ci.Wt = ci.Wt)
  }
  if (!nobp.Vt) {
    Vt.nrbp <- length(bp.Vt$breakpoints)
    co <- coef(fm1)
    Mag <- matrix(NA, Vt.nrbp, 3)
    for (r in 1:Vt.nrbp) {
      if (r == 1) 
        y1 <- co[1] + co[r + Vt.nrbp + 1] * ti[Vt.bp[r]]
      else y1 <- co[1] + co[r] + co[r + Vt.nrbp + 1] * 
          ti[Vt.bp[r]]
      y2 <- (co[1] + co[r + 1]) + co[r + Vt.nrbp + 2] * 
        ti[Vt.bp[r] + 1]
      Mag[r, 1] <- y1
      Mag[r, 2] <- y2
      Mag[r, 3] <- y2 - y1
    }
    index <- which.max(abs(Mag[, 3]))
    m.x <- rep(Vt.bp[index], 2)
    m.y <- c(Mag[index, 1], Mag[index, 2])
    Magnitude <- Mag[index, 3]
    Time <- Vt.bp[index]
  }
  else {
    m.x <- NA
    m.y <- NA
    Magnitude <- 0
    Time <- NA
    Mag <- 0
  }
  return(structure(list(Yt = Yt, output = output, nobp = list(Vt = nobp.Vt, 
                                                              Wt = nobp.Wt), Magnitude = Magnitude, Mags = Mag, Time = Time, 
                        jump = list(x = ti[m.x], y = m.y)), class = "bfast"))
}