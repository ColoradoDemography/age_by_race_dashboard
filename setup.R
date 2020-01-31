# SYA by Race Chart Dashboard  Support functions
# Adam Bickford January 2020
# 

library(tidyverse, quietly=TRUE)
library(stringr)
library(readr)
library(readxl, quietly=TRUE)
library(RPostgreSQL)
library(plotly)
library(scales, quietly=TRUE)
library(shiny, quietly=TRUE)
library(shinydashboard, quietly=TRUE)
library(shinyjs, quietly=TRUE)
library(RColorBrewer)


# Additions for Database pool
library('pool') 
library('DBI')
library('stringr')
library('config')

# Set up database pool 
config <- get("database")
DOLAPool <-  dbPool(
  drv <- dbDriver(config$Driver),
  dbname = config$Database,
  host = config$Server,
  port = config$Port,
  user = config$UID,
  password = config$PWD
)

dbGetInfo(DOLAPool)


onStop(function(){
  poolClose(DOLAPool)
})


# Support Functions
# NumFmt formats a numberic variable to a whold number, comma separated value
#
NumFmt <- function(inval){
  outval <- format(round(inval ,digits=0),  big.mark=",")
  return(outval)
}

# simpleCap produces string in Proper case
simpleCap <- function(x) {
  s <- strsplit(x, " ")[[1]]
  paste(toupper(substring(s, 1,1)), tolower(substring(s, 2)),
        sep="", collapse=" ")
}

#YrSelect  Generates a list of years
YrSelect <- function(DBPool) {
   yrStr <- paste0("SELECT DISTINCT year FROM estimates.county_sya_race_estimates;")
   f.yrLookup <- dbGetQuery(DBPool, yrStr) %>% arrange(year)
return(f.yrLookup)   
}
    
# popPlace list of county names
popPlace <- function(DBPool) {
 

  # Create Connection Strings
  clookupStr <- paste0("SELECT DISTINCT countyfips, municipalityname FROM estimates.county_muni_timeseries WHERE placefips = 0;")

    # f.cLookup contains the county records
    f.cLookup <- dbGetQuery(DBPool, clookupStr)
    
 # Counties   
    f.cLookup <- arrange(f.cLookup, countyfips)
    f.cLookup[,2] <- sapply(f.cLookup[,2], function(x) simpleCap(x))
    f.cLookup$municipalityname <- str_replace(f.cLookup$municipalityname,"Colorado State","Colorado")
    
   
  return(f.cLookup)
}

#listToFips retuns a fips code from a county name

listTofips <- function(df, inList1){
  # Function to produce a vector of FIPS codes from an input list of names and codes
  fipsl <- df[which(df$municipalityname == inList1),1]
  return(fipsl)
} #end listTofips


# genPlotData  returns the analysis dataset
genPlotData <- function(DBPool,fips,yr){

  if(fips == 0) {
       sqlSYARace <- paste0("SELECT * FROM estimates.county_sya_race_estimates WHERE year = ",yr,";")
  } else {
       sqlSYARace <- paste0("SELECT * FROM estimates.county_sya_race_estimates WHERE (county_fips = ",fips,"AND year = ",yr,");")
  }

 f.SYARace <-  dbGetQuery(DBPool, sqlSYARace) 
 
 # Assembling data file
   f.SYARaceHisp <- f.SYARace %>% 
             filter(ethnicity == "Hispanic Origin"  & age < 85) %>%
             mutate(race = "Hispanic Origin") %>%
             group_by(race,age) %>%
             summarise(Population = sum(count)) 
   
   f.SYARaceNHisp <- f.SYARace %>% 
             filter(ethnicity != "Hispanic Origin"  & age < 85) %>%
             group_by(race,age) %>%
             summarise(Population = sum(count))
 
    f.SYARaceOut <- bind_rows(f.SYARaceHisp, f.SYARaceNHisp)
    f.SYARaceOut$Population <- ceiling(f.SYARaceOut$Population)
    names(f.SYARaceOut)[2] <- "Age"

return(f.SYARaceOut)
}

# GenPlot returns the Plots
GenPlot <- function(DBPool,ctyfips, ctyname, datyear) {
  
ctysel <- listTofips(ctyfips,ctyname)
f.SYARace <- genPlotData(DBPool = DBPool,fips = ctysel,yr = datyear)

f.SYARace$race <- plyr::revalue(f.SYARace$race, c("Hispanic Origin" = "Hispanic",
                                                  "American Indian" = "American Indian, Not Hispanic",
                                                  "Asian/Pacific Islander" = "Asian/Pacific Islander, Not Hispanic",
                                                  "Black" = "Black, Not Hispanic",
                                                  "White" = "White, Not Hispanic"))




f.SYARace$race <- factor(f.SYARace$race,levels= c("White, Not Hispanic",
                                                  "Hispanic",
                                                  "Black, Not Hispanic",
                                                   "Asian/Pacific Islander, Not Hispanic",
                                                   "American Indian, Not Hispanic"))
f.SYARace[is.na(f.SYARace)] <- 0
 
   f.SYARace$indText  <- paste0(f.SYARace$race," Age: ",f.SYARace$Age," Estimate: ",NumFmt(f.SYARace$Population)) 
   outCAP <- paste0("Colorado State Demography Office, Date Printed: ",as.character(format(Sys.Date(),"%m/%d/%Y")))
   grTitle <- paste0("Single Year of Age by Race: ",ctyname,", ",datyear)  
    xAxis <- list(range=c(0,85), dtick = 5, tick0 = 5, tickmode = "linear", title = "Age")
    yAxis <- list(separators = ',.', title = 'Population')
    
  

ggSYALINE <- plot_ly(f.SYARace, 
                      x = ~Age, y = ~Population, name=~race, type = 'scatter', 
                      mode = 'lines', text = ~indText, hoverinfo = 'text') %>%
     layout( title=grTitle, yaxis = yAxis, xaxis=xAxis,
          showlegend = TRUE, hoverlabel = "right", margin = list(l = 50, r = 50, t = 60, b = 100),  
                      annotations = list(text = outCAP,
                      font = list(size = 10), showarrow = FALSE, yref = 'paper', y = -0.3))


ggSYABARW <- f.SYARace %>%
             filter(race == "White, Not Hispanic") %>%
             plot_ly( x = ~Age, y = ~Population, type = 'bar', color = I("blue"),
                       text = ~indText, hoverinfo = 'text') %>%
     layout( title=list(text = paste0(grTitle,
                                    '<br>',
                                    '<sup>',
                                    'White, Not Hispanic',
                                    '</sup>')), 
          yaxis = yAxis, xaxis=xAxis,
          hoverlabel = "right", margin = list(l = 50, r = 50, t = 60, b = 100),  
                      annotations = list(text = outCAP,
                      font = list(size = 10), showarrow = FALSE, yref = 'paper', y = -0.3))

ggSYABARH <- f.SYARace %>%
             filter(race == "Hispanic") %>%
             plot_ly( x = ~Age, y = ~Population, type = 'bar', color = I("orange"),
                       text = ~indText, hoverinfo = 'text') %>%
     layout( title=list(text = paste0(grTitle,
                                    '<br>',
                                    '<sup>',
                                    'Hispanic',
                                    '</sup>')), 
          yaxis = yAxis, xaxis=xAxis,
          hoverlabel = "right", margin = list(l = 50, r = 50, t = 60, b = 100),  
                      annotations = list(text = outCAP,
                      font = list(size = 10), showarrow = FALSE, yref = 'paper', y = -0.3))

ggSYABARB <- f.SYARace %>%
             filter(race == "Black, Not Hispanic") %>%
             plot_ly( x = ~Age, y = ~Population, type = 'bar', color = I("green"),
                       text = ~indText, hoverinfo = 'text') %>%
     layout( title=list(text = paste0(grTitle,
                                    '<br>',
                                    '<sup>',
                                    'Black, Not Hispanic',
                                    '</sup>')), 
          yaxis = yAxis, xaxis=xAxis,
          hoverlabel = "right", margin = list(l = 50, r = 50, t = 60, b = 100),  
                      annotations = list(text = outCAP,
                      font = list(size = 10), showarrow = FALSE, yref = 'paper', y = -0.3))

ggSYABARAS <- f.SYARace %>%
             filter(race == "Asian/Pacific Islander, Not Hispanic") %>%
             plot_ly( x = ~Age, y = ~Population, type = 'bar', color = I("red"),
                       text = ~indText, hoverinfo = 'text') %>%
     layout( title=list(text = paste0(grTitle,
                                    '<br>',
                                    '<sup>',
                                    'Asian/Pacific Islander, Not Hispanic',
                                    '</sup>')), 
          yaxis = yAxis, xaxis=xAxis,
          hoverlabel = "right", margin = list(l = 50, r = 50, t = 60, b = 100),  
                      annotations = list(text = outCAP,
                      font = list(size = 10), showarrow = FALSE, yref = 'paper', y = -0.3))


ggSYABARAM <- f.SYARace %>%
             filter(race == "American Indian, Not Hispanic") %>%
             plot_ly( x = ~Age, y = ~Population, type = 'bar', color = I("purple"),
                       text = ~indText, hoverinfo = 'text') %>%
     layout( title=list(text = paste0(grTitle,
                                    '<br>',
                                    '<sup>',
                                    'American Indian, Not Hispanic',
                                    '</sup>')), 
          yaxis = yAxis, xaxis=xAxis,
          hoverlabel = "right", margin = list(l = 50, r = 50, t = 60, b = 100),  
                      annotations = list(text = outCAP,
                      font = list(size = 10), showarrow = FALSE, yref = 'paper', y = -0.3))

outlist <- list("LINE" = ggSYALINE, "WHITE" = ggSYABARW, "HISP" = ggSYABARH, "BLACK" = ggSYABARB,
                "ASIAN" = ggSYABARAS, "AMIND" = ggSYABARAM)
return(outlist)
}

genData <- function(DBPool,ctyfips, ctyname, datyear) {

plt_data <- genPlotData(DBPool = DBPool,fips = ctyfips,yr = datyear)
# Generate the plotly pairs
f.SYARace <- plt_data$data

f.SYARace$race <- plyr::revalue(f.SYARace$race, c("Hispanic Origin" = "Hispanic",
                                                  "American Indian" = "American Indian, Not Hispanic",
                                                  "Asian/Pacific Islander" = "Asian/Pacific Islander, Not-Hispanic",
                                                  "Black" = "Black, Not Hispanic",
                                                  "White" = "White, Not Hispanic"))




f.SYARace$race <- factor(f.SYARace$race,levels= c("White, Not Hispanic",
                                                  "Hispanic",
                                                  "Black, Not Hispanic",
                                                   "Asian/Pacific Islander, Not-Hispanic",
                                                   "American Indian, Not Hispanic"))
f.SYARace[is.na(f.SYARace)] <- 0
}
