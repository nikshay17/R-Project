library(shiny)
library(httr)
library(jsonlite)
library(DT)
library(shinyjs)

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
      
      /* File input area */
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
      
      /* Results table */
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
    "))
  ),
  
  titlePanel(
    div(class = "main-header",
        icon("chart-bar", class = "fa-lg"),
        " Audio File Comparison Dashboard"
    )
  ),
  
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
        type = "tabs",
        tabPanel(
          title = span(icon("chart-column"), "Visual Comparison"),
          div(class = "plot-container",
              h3(class = "plot-title", "Speaking Metrics Comparison"),
              imageOutput("comparison_plot", height = "400px")
          ),
          
          div(class = "plot-container",
              h3(class = "plot-title", "Statistical Significance"),
              verbatimTextOutput("anova_result"),
              div(style = "margin-top: 10px; font-size: 0.9em;",
                  icon("lightbulb"), 
                  "A p-value < 0.05 indicates significantly different speaking rates")
          )
        ),
        
        tabPanel(
          title = span(icon("table"), "Numerical Results"),
          div(style = "margin-top: 20px;",
              DTOutput("results_table")
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
  )
)

server <- function(input, output, session) {
  rv <- reactiveValues(
    comparison = NULL,
    debug_log = paste(format(Sys.time(), "[%H:%M:%S]"), "System initialized. Ready for file upload.\n")
  )
  
  log_msg <- function(msg) {
    rv$debug_log <- paste0(rv$debug_log, format(Sys.time(), "[%H:%M:%S] "), msg, "\n")
  }
  
  observeEvent(input$compare_btn, {
    req(input$compare_files)
    if (length(input$compare_files$name) < 2) {
      log_msg("ERROR: Need at least 2 files for comparison")
      showNotification("Please upload at least 2 files", type = "error")
      return()
    }
    
    if (length(input$compare_files$name) > 5) {
      log_msg("WARNING: More than 5 files uploaded. Using first 5 files.")
      showNotification("Using first 5 files (max limit)", type = "warning")
    }
    
    log_msg(paste("Starting analysis of:", paste(input$compare_files$name[1:min(5, length(input$compare_files$name))], collapse=", ")))
    
    # Disable button during processing
    shinyjs::disable("compare_btn")
    on.exit(shinyjs::enable("compare_btn"))
    
    tryCatch({
      res <- POST(
        "http://localhost:5000/compare",
        body = list(files = lapply(input$compare_files$datapath[1:min(5, length(input$compare_files$name))], upload_file)),
        encode = "multipart"
      )
      
      if (res$status_code == 200) {
        data <- fromJSON(rawToChar(res$content))
        if (data$success) {
          rv$comparison <- data
          log_msg("SUCCESS: Comparison completed")
          showNotification("Analysis completed", type = "message")
        } else {
          log_msg(paste("ERROR:", data$error))
          showNotification(paste("Error:", data$error), type = "error")
        }
      } else {
        log_msg(paste("SERVER ERROR:", res$status_code))
        showNotification("Server error occurred", type = "error")
      }
    }, error = function(e) {
      log_msg(paste("CRITICAL ERROR:", e$message))
      showNotification("Processing failed", type = "error")
    })
  })
  
  output$comparison_plot <- renderImage({
    req(rv$comparison$comparison_plot)
    tmpfile <- tempfile(fileext = ".png")
    writeBin(base64enc::base64decode(rv$comparison$comparison_plot), tmpfile)
    list(src = tmpfile, width = "100%", height = "400px")
  }, deleteFile = TRUE)
  
  output$results_table <- renderDT({
    req(rv$comparison$files)
    datatable(
      do.call(rbind, lapply(rv$comparison$files, function(x) {
        data.frame(
          File = x$filename,
          Avg WPM = round(x$mean_wpm, 1),
          Total Words = x$total_words,
          Confidence = paste0(round(x$confidence * 100, 1), "%"),
          check.names = FALSE
        )
      })),
      options = list(
        pageLength = 10,
        dom = 'tip',
        initComplete = JS(
          "function(settings, json) {
            $(this.api().table().header()).css({
              'background-color': '#3498db',
              'color': 'white'
            });
          }"
        )
      ),
      rownames = FALSE,
      class = "hover"
    )
  })
  
  output$anova_result <- renderText({
    req(rv$comparison$anova_pvalue)
    pval <- rv$comparison$anova_pvalue
    sig <- ifelse(pval < 0.05, 
                  "\nCONCLUSION: Speaking rates are significantly different (p < 0.05)",
                  "\nCONCLUSION: No significant difference in speaking rates")
    paste("ANOVA RESULTS:\n",
          "p-value: ", format.pval(pval, digits=4), 
          sig)
  })
  
  output$debug_log <- renderText({
    rv$debug_log
  })
}

shinyApp(ui, server)