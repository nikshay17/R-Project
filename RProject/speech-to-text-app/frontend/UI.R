library(shinyjs)
library(DT)

ui <- fluidPage(
  useShinyjs(),
  tags$head(
    tags$style(HTML("
      /* Main styling */
      body {
        background-color: #f8f9fa;
        font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
      }
      .well {
        background-color: white;
        border-radius: 8px;
        box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        border: 1px solid #e0e0e0;
      }
      .main-header {
        color: #2c3e50;
        border-bottom: 2px solid #3498db;
        padding-bottom: 10px;
        margin-bottom: 20px;
      }
      
      /* File input areas */
      .file-input-area {
        background-color: #f1f8fe;
        padding: 15px;
        border-radius: 8px;
        margin-bottom: 20px;
      }
      
      /* Plots and tables */
      .plot-container {
        background-color: white;
        padding: 15px;
        border-radius: 8px;
        box-shadow: 0 1px 3px rgba(0,0,0,0.1);
        margin-bottom: 20px;
      }
      .plot-title {
        color: #2c3e50;
        font-weight: 600;
        margin-bottom: 15px;
      }
      
      /* Results tables */
      .dataTables_wrapper {
        background-color: white;
        padding: 15px;
        border-radius: 8px;
        box-shadow: 0 1px 3px rgba(0,0,0,0.1);
      }
      
      /* Debug console */
      .debug-console {
        font-family: 'Courier New', monospace;
        background-color: #2c3e50;
        color: #ecf0f1;
        padding: 15px;
        border-radius: 8px;
        height: 300px;
        overflow-y: scroll;
        white-space: pre-wrap;
      }
      
      /* Buttons */
      .btn-primary {
        background-color: #3498db;
        border-color: #2980b9;
        font-weight: 500;
      }
      .btn-primary:hover {
        background-color: #2980b9;
      }
      
      /* Tabs */
      .nav-tabs > li > a {
        color: #7f8c8d;
        font-weight: 500;
      }
      .nav-tabs > li.active > a {
        color: #3498db;
        border-bottom: 2px solid #3498db;
      }
      .tab-content {
        padding: 15px 0;
      }
      .file-header {
        font-size: 1.1em;
        margin-bottom: 15px;
        color: #3498db;
      }
    "))
  ),
  
  titlePanel(
    div(class = "main-header",
        icon("chart-bar", class = "fa-lg"),
        " Professional Audio Analysis Dashboard"
    )
  ),
  
  tabsetPanel(
    id = "main_tabs",
    tabPanel(
      title = span(icon("file-audio"), "Single File Analysis"),
      sidebarLayout(
        sidebarPanel(
          width = 3,
          div(class = "well",
              h4("File Input"),
              textOutput("current_file"),
              hr(),
              fileInput("audio_file", "Upload Audio",
                        accept = c(".wav", ".mp3")),
              actionButton("analyze_btn", "Analyze", 
                           class = "btn-primary btn-block")
          )
        ),
        mainPanel(
          width = 9,
          tabsetPanel(
            tabPanel("Transcript",
                     div(class = "file-header", textOutput("current_file")),
                     verbatimTextOutput("transcript")
            ),
            tabPanel("Speaking Metrics",
                     div(class = "plot-title", "Speaking Rate Timeline"),
                     imageOutput("wpm_plot"),
                     div(class = "plot-title", "Pause Analysis"),
                     imageOutput("pause_confidence_plot"),
                     DTOutput("speech_stats")
            ),
            tabPanel("Vocabulary Analysis",
                     div(class = "plot-title", "Word Usage Heatmap"),
                     imageOutput("vocab_heatmap"),
                     div(class = "plot-title", "Audio Energy Patterns"),
                     imageOutput("energy_confidence_plot"),
                     DTOutput("vocab_stats")
            )
          )
        )
      )
    ),
    
    tabPanel(
      title = span(icon("copy"), "Multi-File Comparison"),
      sidebarLayout(
        sidebarPanel(
          width = 3,
          div(class = "file-input-area",
              fileInput("compare_files", 
                        label = h4("Upload Audio Files", icon("upload")),
                        multiple = TRUE,
                        accept = c(".wav", ".mp3"),
                        buttonLabel = "Browse...",
                        placeholder = "Select 2-5 files"),
              
              actionButton("compare_btn", 
                           label = "Compare Files", 
                           icon = icon("play"),
                           class = "btn-primary btn-block"),
              
              tags$hr(),
              
              div(style = "font-size: 0.9em; color: #7f8c8d;",
                  p(icon("info-circle"), 
                    "For reliable comparison, upload:"),
                  tags$ul(
                    tags$li("2-5 audio files"),
                    tags$li("Similar duration (1-10 mins)"),
                    tags$li("Clear speech content")
                  )
              )
          )
        ),
        mainPanel(
          width = 9,
          tabsetPanel(
            tabPanel("Visual Comparison",
                     div(class = "plot-container",
                         h3(class = "plot-title", "Speaking Metrics Comparison"),
                         imageOutput("metrics_comparison")
                     ),
                     
                     div(class = "plot-container",
                         h3(class = "plot-title", "Vocabulary vs Confidence"),
                         imageOutput("vocab_conf_comparison")
                     )
            ),
            tabPanel("Numerical Results",
                     DTOutput("comparison_table"),
                     div(class = "plot-container",
                         h3(class = "plot-title", "Statistical Significance"),
                         verbatimTextOutput("anova_result"),
                         div(style = "margin-top: 10px; font-size: 0.9em;",
                             icon("lightbulb"), 
                             "A p-value < 0.05 indicates significantly different speaking rates")
                     )
            )
          )
        )
      )
    ),
    
    tabPanel(
      title = span(icon("bug"), "Debug Console"),
      div(class = "debug-console",
          h4("System Log"),
          verbatimTextOutput("debug_log")
      )
    )
  )
)