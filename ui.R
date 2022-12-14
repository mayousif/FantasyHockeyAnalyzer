library(shiny)
library(shinyjs)
library(shinyWidgets)
library(shinydashboard)
library(shinydashboardPlus)
library(shinyauthr)
library(stringr)
library(plotly)
library(dplyr)
library(DT)
library(reactable)
library(stringr)
library(lubridate)
library(scales)
library(data.table)
library(tools)
library(sodium)
library(purrr)
library(httr)
library(YFAR)
library(rjson)
library(reactlog)
library(RSQLite)

enableBookmarking(store="server")

# Current directory of the app
currDir <<- getwd()
setwd(currDir)

# Read in all players, current lines, and nhl team names/abvs
playernames <<- read.csv(paste0(currDir,"/Data/PlayerNames.csv"))
playerlines <<- read.csv(paste0(currDir,"/Data/PlayerLines.csv"))
nhlteams <<- read.csv(paste0(currDir,"/Data/TeamNames.csv"))


# Get current season and NHL schedule (and remaining games this+next week)
currentSeason <<- as.integer(lubridate::quarter(Sys.Date(), with_year = TRUE, fiscal_start = 10))
seasonSchedule <<- read.csv(paste0(currDir,"/Data/Schedule/",currentSeason,".csv"))

# Current week
gamesCurrWeek <<- data.frame()
gamesCurrWeek[1:nrow(nhlteams),'teamabv'] <<- nhlteams[,'teamabv']

tempHome = data.frame(count_home = colSums(table(seasonSchedule[seasonSchedule$Date >= Sys.Date() &
                                        seasonSchedule$Date <=  ceiling_date(Sys.Date(), "week"),
                                        c('Date','HomeABV')])))
tempHome = cbind(teamabv = rownames(tempHome),tempHome)
tempVis = data.frame(count_vis = colSums(table(seasonSchedule[seasonSchedule$Date >= Sys.Date() &
                                                             seasonSchedule$Date <=  ceiling_date(Sys.Date(), "week"),
                                                           c('Date','VisABV')])))
tempVis = cbind(teamabv = rownames(tempVis),tempVis)

gamesCurrWeek <<- left_join(gamesCurrWeek,tempHome)
gamesCurrWeek <<- left_join(gamesCurrWeek,tempVis)
gamesCurrWeek[is.na(gamesCurrWeek)] <<- 0
gamesCurrWeek$count <<- gamesCurrWeek$count_home + gamesCurrWeek$count_vis

# Next week
gamesNextWeek <<- data.frame()
gamesNextWeek[1:nrow(nhlteams),'teamabv'] <<- nhlteams[,'teamabv']

tempHome = data.frame(count_home = colSums(table(seasonSchedule[seasonSchedule$Date >= floor_date(Sys.Date()+7,'week',1) &
                                                                  seasonSchedule$Date <=  ceiling_date(Sys.Date()+7, "week",change_on_boundary=F),
                                                                c('Date','HomeABV')])))
tempHome = cbind(teamabv = rownames(tempHome),tempHome)
tempVis = data.frame(count_vis = colSums(table(seasonSchedule[seasonSchedule$Date >= floor_date(Sys.Date()+7,'week',1) &
                                                                seasonSchedule$Date <=  ceiling_date(Sys.Date()+7, "week",change_on_boundary=F),
                                                              c('Date','VisABV')])))
tempVis = cbind(teamabv = rownames(tempVis),tempVis)

gamesNextWeek <<- left_join(gamesNextWeek,tempHome)
gamesNextWeek <<- left_join(gamesNextWeek,tempVis)
gamesNextWeek[is.na(gamesNextWeek)] <<- 0
gamesNextWeek$count <<- gamesNextWeek$count_home + gamesNextWeek$count_vis


# Get current season data for skaters/goalies
skaterData <<- read.csv(paste0(currDir,"/Data/allSkaters/",currentSeason,".csv"))
skaterData <<- left_join(skaterData,playernames,"ID")
goalieData <<- read.csv(paste0(currDir,"/Data/allGoalies/",currentSeason,".csv"))
goalieData <<- left_join(goalieData,playernames,"ID")
skaterDataLS <<- read.csv(paste0(currDir,"/Data/allSkaters/",currentSeason-1,".csv"))
skaterDataLS <<- left_join(skaterDataLS,playernames,"ID")
goalieDataLS <<- read.csv(paste0(currDir,"/Data/allGoalies/",currentSeason-1,".csv"))
goalieDataLS <<- left_join(goalieDataLS,playernames,"ID")

allFantasySkaters <<- unique(rbind(skaterData[,c('ID','Name')],skaterDataLS[,c('ID','Name')]))
allFantasyGoalies <<- unique(rbind(goalieData[,c('ID','Name')],goalieDataLS[,c('ID','Name')]))

# Team logos
logos <<- read.csv(paste0(currDir,"/Data/Logos.csv"))

# JS Function to open links
js_browser <- "
shinyjs.browseURL = function(url) {
  window.open(url,'_blank');
}
"

# # Connect to or setup and connect to local SQLite db
# if (file.exists(paste0(currDir,"/Data/Users/sessiondb"))) {
#   db <<- dbConnect(SQLite(), paste0(currDir,"/Data/Users/sessiondb"))
# } else {
#   db <<- dbConnect(SQLite(), paste0(currDir,"/Data/Users/sessiondb"))
#   dbCreateTable(db, "sessionids", c(user = "TEXT", sessionid = "TEXT", login_time = "TEXT"))
# }
# 
# cookie_expiry <<- 14 # Days until session expires
# 
# # This function must accept two parameters: user and sessionid. It will be called whenever the user
# # successfully logs in with a password.  This function saves to your database.
# add_sessionid_to_db <<- function(user, sessionid, conn = db) {
#   tibble(user = user, sessionid = sessionid, login_time = as.character(now())) %>%
#     dbWriteTable(conn, "sessionids", ., append = TRUE)
# }
# 
# # This function must return a data.frame with columns user and sessionid  Other columns are also okay
# # and will be made available to the app after log in as columns in credentials()$user_auth
# get_sessionids_from_db <<- function(conn = db, expiry = cookie_expiry) {
#   dbReadTable(conn, "sessionids") %>%
#     mutate(login_time = ymd_hms(login_time)) %>%
#     as_tibble() %>%
#     filter(login_time > now() - days(expiry))
# }


## Sidebar =================================
sidebar = dashboardSidebar(
  sidebarMenu(
    id = "tabs",
    menuItem(
      selected = TRUE,
      "Fantasy Metrics", 
      tabName = "teamstats", 
      icon = icon("people-group")
    ),
    menuItem(
      text = "Player Stats",
      startExpanded = TRUE,
      icon = icon("person-skating"),
      menuSubItem(
        tabName = "playerstats",
        icon=NULL,
        selectizeInput(
          "playerInput",
          "Select Player",
          choices = NULL,
          selected = NULL
        )
      )
    )
  )
)
## Main Body =================================
body = dashboardBody(
  useShinyjs(),
  extendShinyjs(text = js_browser, functions = 'browseURL'),
  tags$head(
    tags$meta(name = "viewport", content = "width=1600"),
    tags$link(rel = "stylesheet", type = "text/css", href = "test.css"),
    tags$style(
      HTML('.box-header .box-title {display: block;}'),
      HTML('.box-header {padding-top: 0px;
                        padding-bottom: 0px;}'),
      HTML('.Reactable {padding-top: 10px;}'),
      HTML('.box {background: #f6f8fc}'),
      HTML('.form-group {margin-bottom: 0px}'),
      HTML('.main-sidebar {font-size: 20px;
                         font-weight: 700;}'),
      HTML("
      input[type=number] {
            -moz-appearance:textfield;
      }
      input[type=number]::{
            -moz-appearance:textfield;
      }
      input[type=number]::-webkit-outer-spin-button,
      input[type=number]::-webkit-inner-spin-button {
            -webkit-appearance: none;
            margin: 0;}"
      ),
      HTML("
        .selectize-control.single .selectize-input:after{
        content: none;
        }"
      ),
      HTML('#login-button {margin-top: 10px}'),
      HTML('#loginopen {margin-top: 10px}'),
      HTML('#createacc {margin-top: 10px;
                       margin-right: 20px}'),
      HTML('.modal-content {border: 2px solid #000000;
                           background: #f6f8fc}'),
      HTML('#logout-button {display: block !important}'),
      HTML('#leaguesettingsbox {line-height: 0}'),
      HTML('.skin-blue .main-header .navbar {background-color:#6e8fb0}'),
      HTML('.skin-blue .main-header .logo {background-color:#222d32;}'),
      HTML('.skin-blue .main-header .navbar .sidebar-toggle:hover {background-color:#6e8fb0;}'),
      HTML('.skin-blue .main-header .logo:hover {background-color:#222d32;}'),
      HTML('.box.box-solid.box-primary > .box-header {background-color:#6e8fb0;}'),
      HTML('.btn-primary {background-color:#6e8fb0;}'),
      HTML('.material-switch {padding-top: 18px;}'),
      HTML('.material-switch > label::before {right: -4px};')
    ),
    tags$style(type="text/css",
               ".shiny-output-error {visibility: hidden; }",
               ".shiny-output-error:before {visibility: hidden; }"),
    tags$script("
      Shiny.addCustomMessageHandler('gear_click', function(value) {
      Shiny.setInputValue('gear_click', value);
      });
    ")
  ),
  br(),
  br(),
  br(),
  tabItems(
    # Player stats tab
    tabItem(
      tabName = "playerstats",
      style = "overflow-x: auto;overflow-y: auto;",
      fluidRow(
        box(
          id = "seasonrankingbox",
          width = 4,
          title = h4("Percentile Ranking"),
          solidHeader=T,
          status = "primary",
          collapsible = TRUE,
          collapsed = FALSE,
          fluidRow(
            column(
              width = 3, 
              align = "center",
              uiOutput("playerName"),
              uiOutput("playerImage")
            ),
            column(
              width=9,
              align = "center",
              fluidRow(
                column(
                  width = 4, 
                  align = "center",
                  selectInput(
                    "playerRankSeason",
                    h2("Season"),
                    choices = NA
                  )
                ),
                column(
                  width = 8, 
                  align = "center",
                  radioGroupButtons(
                    "playerRankType",
                    label = h2("Stat Type"),
                    choices = c("Total" = "tot",
                                "Per Game" = "pg",
                                "Per 60" = "p60"),
                    selected = character(0),
                    status = "primary"
                  )
                )
              ),
              fluidRow(
                column(
                  width = 4, 
                  align = "center",
                  selectInput(
                    "playerRankGPFilter",h2("Min. GP"),
                    choices = c("1 GP" = 1, "5 GP"=5,"10 GP" = 10, "20 GP" = 20, "40 GP" = 40),
                    selected = "1 GP"
                  )
                ),
                column(
                  width = 8,
                  align = "center",
                  pickerInput(
                    "playerRankPositionFilter",
                    label = h2("Positions"),
                    choices = NULL,
                    multiple=T,
                    width = '75%'
                  )
                )
              )
            )
          ),
          fluidRow(
            column(width = 4,align="center", style = "padding-right:0px;padding-left:0px;",
                   uiOutput("text1_1"),
                   uiOutput("valueBox1_1"),
                   uiOutput("text2_1"),
                   uiOutput("valueBox2_1"),
                   uiOutput("text3_1"),
                   uiOutput("valueBox3_1")
            ),
            column(width = 4,align="center", style = "padding-right:0px;padding-left:0px;",
                   uiOutput("text1_2"),
                   uiOutput("valueBox1_2"),
                   uiOutput("text2_2"),
                   uiOutput("valueBox2_2"),
                   uiOutput("text3_2"),
                   uiOutput("valueBox3_2")
            ),
            column(width = 4,align="center", style = "padding-right:0px;padding-left:0px;",
                   uiOutput("text1_3"),
                   uiOutput("valueBox1_3"),
                   uiOutput("text2_3"),
                   uiOutput("valueBox2_3"),
                   uiOutput("text3_3"),
                   uiOutput("valueBox3_3")
            )
          )
        ),
        box(
          id = "seasonstatsbox",
          width = 8,
          title = h4("Seasonal Summary"),
          solidHeader=T,
          status = "primary",
          collapsible = TRUE,
          collapsed = FALSE,
          fluidRow(
            column(
              width = 3,
              align="center",
              radioGroupButtons(
                "seasonStatsType",
                label = h2("Stat Type"),
                choices = c("Total" = "tot",
                            "Per Game" = "pg",
                            "Per 60" = "p60"),
                selected = character(0),
                status = "primary"
              )
            )
          ),
          reactableOutput("playerStats")
        )
      )
    ),
    
    # Fantasy team stats tab
    tabItem(
      tabName = "teamstats",
      style = "overflow-x: auto;overflow-y: auto;",
      column(
        width = 9,
        box(
          id = "teamloadingbox",
          width = 12,
          title = h4("Team Builder"),
          solidHeader=T,
          status = "primary",
          collapsible = TRUE,
          fluidRow(
            column(
              width=6,align="center",offset = 1,
              fluidRow(
                h1("Team Slots")
              ),
              fluidRow(
                column(width = 4,
                       selectInput("numLW",h2("LW"),1:9,selected=4)
                ),
                column(width = 4, 
                       selectInput("numC",h2("C"),1:9,selected=4)
                ),
                column(width = 4,
                       selectInput("numRW",h2("RW"),1:9,selected=4)
                )
              ),
              fluidRow(
                column(width = 4,
                       selectInput("numD",h2("D"),1:9,selected=4)
                ),
                column(width = 4,
                       selectInput("numMisc",h2("Misc (Util, IR, IR+)"),1:9,selected=4)
                ),
                column(width = 4,
                       selectInput("numG",h2("G"),1:9,selected=4)
                )
                  
              )
            ),
            column(
              width = 4,align="center",
              radioGroupButtons("datasource",h1("Generate Team"),choices = c("Manually" = "man"),status = "primary"),
              uiOutput("teamloadchoices"),
              uiOutput("fantasyteam")
            )
          ),
          fluidRow(
            column(width=2,align="center",
                  h2("Left Wingers"),
                  uiOutput("leftwings")
            ),
            column(width=2,align="center",
                  h2("Centers"),
                  uiOutput("centers")
            ),
            column(width=2,align="center",
                  h2("Right Wingers"),
                  uiOutput("rightwings")
            ),
            column(width=2,align="center",
                  h2("Defensemen"),
                  uiOutput("defensemen")
            ),
            column(width=2,align="center",
                  h2("Misc"),
                 uiOutput("misc")
            ),
            column(width=2,align="center",
                  h2("Goalies"),
                  uiOutput("goalies")
            )
          )
        )
      ),
      column(
        width = 3,
        box(
          id = "leaguesettingsbox",
          width = 12,
          title = h4("League Settings"),
          solidHeader=T,
          status = "primary",
          collapsible = TRUE,
          collapsed = FALSE,
          column(
            width = 12, align ="center",
            fluidRow(
              radioGroupButtons(
                "leaguetype",h1("League Type"),
                choices = c("Points-based" = "points",
                            "Category-based" = "cat"),
                status = "primary"
              )
            )
          ),
          uiOutput("leaguesettings")
        )
      ),
      column(
        width = 12,
        box(
          id = "teamstatsbox",
          width = 12,
          title = h4("Team Stats"),
          solidHeader=T,
          status = "primary",
          collapsible = TRUE,
          collapsed = FALSE,
          fluidRow(
            column(
              width = 3, 
              align = "center",
              radioGroupButtons(
                "teamStatType",
                label = h2("Stat Type"),
                choices = c("Total" = "tot",
                            "Per Game" = "pg"),
                selected = "tot",
                status = "primary"
              )
            ),
            column(
              width = 3, 
              align = "center",
              selectInput(
                "teamStatRange",
                label = h2("Filter Period"),
                choices = c("Last Season" = "ls",
                          "Current Season" = "s",
                          "Last 30 Days" = 30,
                          "Last 14 Days" = 14,
                          "Last 7 Days" = 7),
                selected = "s"
              )
            )
          ),
          reactableOutput("teamSkaterStats"),
          reactableOutput("teamGoalieStats")
        ),
        box(
          id = "leaguerosterbox",
          width = 12,
          title = h4("Top Available Players"),
          solidHeader=T,
          status = "primary",
          collapsible = TRUE,
          collapsed = FALSE,
          fluidRow(
            column(
              width = 3,
              align = "center",
              radioGroupButtons(
                "rosterStatType",
                label = h2("Stat Type"),
                choices = c("Total" = "tot",
                            "Per Game" = "pg"),
                selected = "tot",
                status = "primary"
              )
            ),
            column(
              width = 3,
              align = "center",
              selectInput(
                "rosterStatRange",
                label = h2("Filter Period"),
                choices = c("Full Season" = "s",
                            "Last 30 Days" = 30,
                            "Last 14 Days" = 14,
                            "Last 7 Days" = 7),
                selected = "s"
              )
            ),
            column(
              width = 3,
              align = "center",
              pickerInput(
                "rosterPositionFilter",
                label = h2("Filter Skater Positions"),
                choices = c("C","LW","RW","D"),
                multiple=T,
                selected = character(0),
                options = list(
                  selectedTextFormat = "count",
                  countSelectedText = "{0} selected",
                  noneSelectedText = "No filter"
                )
              )
            )
          ),
          reactableOutput("rosterSkaterStats"),
          reactableOutput("rosterGoalieStats")
        )
      )
    )
  ),
  div(style = "width: 100%; height: 90vh")
)

## Create Page =================================
shinydashboardPlus::dashboardPage(
      #md=F,
      skin = "blue",
      dashboardHeader(
        fixed = TRUE,
        title = tagList(h5(class = "logo-lg","FHA")),
        #titleWidth =  "15%",
        tags$li(
          class = "dropdown",
          fluidRow(
            actionButton("loginopen",strong("Login")),
            actionButton("createacc",strong("Create Account"))
          )
        ),
        userOutput("user")),
      sidebar,
      body
)

