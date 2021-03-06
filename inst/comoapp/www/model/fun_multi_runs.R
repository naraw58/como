multi_runs <- function(Y, times, parameters, input, A, ihr, ifr, mort, popstruc, popbirth, ageing,
                       contact_home, contact_school, contact_work, contact_other){
  
  # Define objects to store results ----
  results <- list()
  
  nb_times <- length(times)
  nb_col <- length(Y) + 1
  aux <- array(0, dim = c(nb_times, nb_col, parameters["iterations"]))
  
  empty_mat <- matrix(0, nrow = nb_times, ncol = parameters["iterations"])
  cases <- empty_mat
  cum_cases <- empty_mat
  day_infections <- empty_mat
  Rt_aux <- empty_mat
  infections <- empty_mat

  # Define spline function ----
  # the parameters give and beds_available have no noise added to them
  fH <- splinefun(c(0, 
                    (1 + parameters["give"]) * parameters["beds_available"] / 2, 
                    (3 - parameters["give"]) * parameters["beds_available"] / 2, 2 * parameters["beds_available"]), 
                  c(1, (1 + parameters["give"]) / 2, (1 - parameters["give"]) / 2, 0), 
                  method = "hyman")
  
  parameters_dup <- parameters  # duplicate parameters to add noise 
  
  for (i in 1:parameters["iterations"]) {
    showNotification(paste("Run", i, "of", parameters["iterations"]), duration = 3, type = "message")
    
    # Add noise to parameters only if there are several iterations
    if (parameters["iterations"] > 1) {
      parameters_dup[parameters_noise] <- parameters[parameters_noise] + 
        rnorm(length(parameters_noise), mean = 0, sd = parameters["noise"] * abs(parameters[parameters_noise]))
    }
    
    covidOdeCpp_reset()
    mat_ode <- ode(y = Y, times = times, method = "euler", hini = 0.05, func = covidOdeCpp, 
                   parms = parameters_dup, input = input, A = A,
                   contact_home=contact_home, contact_school=contact_school,
                   contact_work=contact_work, contact_other=contact_other,
                   popbirth_col2=popbirth[,2], popstruc_col2=popstruc[,2],
                   ageing=ageing, ifr_col2=ifr[,2], ihr_col2=ihr[,2], mort_col=mort)
    
    aux[, , i] <- mat_ode
    
    # Use spline function
    critH <- NULL
    for (t in 1:nb_times) {
      critH[t] <- min(1, 
                      1 - fH(sum(mat_ode[t,(Hindex+1)]) + sum(mat_ode[t,(ICUCindex+1)]) + sum(mat_ode[t,(ICUCVindex+1)]))
        )
    }
    
    # daily incidence
    incidence <- parameters_dup["report"]*parameters_dup["gamma"]*(1-parameters_dup["pclin"])*mat_ode[,(Eindex+1)]%*%(1-ihr[,2])+
      parameters_dup["reportc"]*parameters_dup["gamma"]*parameters_dup["pclin"]*mat_ode[,(Eindex+1)]%*%(1-ihr[,2])+
      parameters_dup["report"]*parameters_dup["gamma"]*(1-parameters_dup["pclin"])*mat_ode[,(QEindex+1)]%*%(1-ihr[,2])+
      parameters_dup["reportc"]*parameters_dup["gamma"]*parameters_dup["pclin"]*mat_ode[,(QEindex+1)]%*%(1-ihr[,2])
    
    incidenceh <- parameters_dup["gamma"]*mat_ode[,(Eindex+1)]%*%ihr[,2]*(1-critH)*(1-parameters_dup["prob_icu"])*parameters_dup["reporth"]+
      parameters_dup["gamma"]*mat_ode[,(Eindex+1)]%*%ihr[,2]*(1-critH)*(1-parameters_dup["prob_icu"])*(1-parameters_dup["reporth"])+
      parameters_dup["gamma"]*mat_ode[,(QEindex+1)]%*%ihr[,2]*(1-critH)*(1-parameters_dup["prob_icu"])+
      parameters_dup["gamma"]*mat_ode[,(Eindex+1)]%*%ihr[,2]*critH*parameters_dup["reporth"]*(1-parameters_dup["prob_icu"])+
      parameters_dup["gamma"]*mat_ode[,(QEindex+1)]%*%ihr[,2]*critH*parameters_dup["reporth"]*(1-parameters_dup["prob_icu"])+
      parameters_dup["gamma"]*mat_ode[,(Eindex+1)]%*%ihr[,2]*parameters_dup["prob_icu"]+
      parameters_dup["gamma"]*mat_ode[,(QEindex+1)]%*%ihr[,2]*parameters_dup["prob_icu"]
    
    cases[,i] <- rowSums(incidence) + rowSums(incidenceh)           # daily incidence cases
    cum_cases[,i] <- colSums(incidence) + colSums(incidenceh)         # cumulative incidence cases
    day_infections[,i]<- round(rowSums(parameters_dup["gamma"]*mat_ode[,(Eindex+1)]+
                                         parameters_dup["gamma"]*mat_ode[,(QEindex+1)]))
    
    # overtime proportion of the  population that is infected
    infections[, i] <- round(100 * cumsum(rowSums(parameters_dup["gamma"]*mat_ode[,(Eindex+1)])) / sum(popstruc[,2]), 1)
    
    for (w in (ceiling(1/parameters_dup["nui"])+1):nb_times){
      Rt_aux[w,i]<-cumsum(sum(parameters_dup["gamma"]*mat_ode[w,(Eindex+1)]))/cumsum(sum(parameters_dup["gamma"]*mat_ode[(w-1/parameters_dup["nui"]),(Eindex+1)]))
      if(Rt_aux[w,i] >= 7) {Rt_aux[w,i]  <- NA}
    }
  }
  
  if (parameters["iterations"] > 1)  showNotification("Aggregation of results (~ 30 secs.)", duration = NULL, type = "message", id = "aggregation_results")
  
  if (parameters["iterations"] == 1) {
    results$mean_infections <- infections
    results$min_infections <- infections
    results$max_infections <- infections
    
    results$mean_cases <- cases
    results$min_cases <- cases
    results$max_cases <- cases

    results$mean_cum_cases <- cum_cases
    results$min_cum_cases <- cum_cases
    results$max_cum_cases <- cum_cases

    results$mean_daily_infection <- day_infections
    results$min_daily_infection <- day_infections
    results$max_daily_infection <- day_infections

    results$mean_Rt <- Rt_aux
    results$min_Rt <- Rt_aux
    results$max_Rt <- Rt_aux

    results$mean <- aux[, , 1]
    results$min <- aux[, , 1]
    results$max <- aux[, , 1]
  }
  
  if (parameters["iterations"] > 1) {
    results$mean_infections <- apply(infections, 1, quantile, probs = 0.5)
    results$min_infections <- apply(infections, 1, quantile, probs = parameters["confidence"])
    results$max_infections <- apply(infections, 1, quantile, probs = (1 - parameters["confidence"]))
    
    results$mean_cases <- apply(cases, 1, quantile, probs = 0.5)
    results$min_cases <- apply(cases, 1, quantile, probs = parameters["confidence"])
    results$max_cases <- apply(cases, 1, quantile, probs = (1 - parameters["confidence"]))

    results$mean_daily_infection <- apply(day_infections, 1, quantile, probs = 0.5)
    results$min_daily_infection <- apply(day_infections, 1, quantile, probs = parameters["confidence"])
    results$max_daily_infection <- apply(day_infections, 1, quantile, probs = (1 - parameters["confidence"]))

    results$mean_Rt <- apply(Rt_aux, 1, quantile, probs = 0.5, na.rm = TRUE)
    results$min_Rt <- apply(Rt_aux, 1, quantile, probs = parameters["confidence"], na.rm = TRUE)
    results$max_Rt <- apply(Rt_aux, 1, quantile, probs = (1 - parameters["confidence"]), na.rm = TRUE)
    
    # runs in 37 sec with 10 runs / 205 days
    results$mean <- apply(aux, 1:2, quantile, probs = 0.5)
    results$min <- apply(aux, 1:2, quantile, probs = parameters["confidence"])
    results$max <- apply(aux, 1:2, quantile, probs = (1 - parameters["confidence"]))
  }
  
  if (parameters["iterations"] > 1)  removeNotification(id = "aggregation_results")
  return(results)
}