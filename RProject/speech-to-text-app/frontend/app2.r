library(shiny)
library(DT)
shiny::shinyApp(
  ui = source("UI.R")$value,
  server = source("server.R")$value,
  comparison=source("comparison.R")$value
)