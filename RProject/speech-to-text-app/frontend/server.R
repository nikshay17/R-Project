library(shiny)
library(httr)
library(jsonlite)
library(ggplot2)
library(shinyjs)
library(DT)
library(plotly)

server <- function(input, output, session) {
  # Reactive values for both single and multi-file analysis
  rv <- reactiveValues(
    transcript = "",
    stats = NULL,
    plots = list(),
    comparison = NULL,
    debug_log = paste(format(Sys.time(), "[%H:%M:%S]"), "System initialized. Ready for file upload.\n"),
    current_file = NULL
  )
  
  # Debug logging function
  log_msg <- function(msg) {
    rv$debug_log <- paste0(rv$debug_log, format(Sys.time(), "[%H:%M:%S] "), msg, "\n")
  }
  
  # Single file analysis handler
  observeEvent(input$analyze_btn, {
    req(input$audio_file)
    rv$current_file <- input$audio_file$name
    log_msg(paste("Starting single file analysis:", input$audio_file$name))
    
    tryCatch({
      # Disable button during processing
      shinyjs::disable("analyze_btn")
      on.exit(shinyjs::enable("analyze_btn"))
      
      res <- POST(
        "http://localhost:5000/analyze",
        body = list(files = upload_file(input$audio_file$datapath)),
        encode = "multipart"
      )
      
      if (res$status_code == 200) {
        data <- fromJSON(rawToChar(res$content))
        if (data$success) {
          rv$transcript <- data$transcript
          rv$stats <- data$stats
          rv$plots <- data$plots
          log_msg("Single file analysis completed successfully")
          showNotification("Analysis completed", type = "message")
        } else {
          log_msg(paste("Analysis failed:", data$error))
          showNotification(paste("Error:", data$error), type = "error")
        }
      } else {
        log_msg(paste("Server error:", res$status_code))
        showNotification("Server error occurred", type = "error")
      }
    }, error = function(e) {
      log_msg(paste("Critical error during single file analysis:", e$message))
      showNotification("Processing failed", type = "error")
    })
  })
  
  # Multi-file comparison handler
  observeEvent(input$compare_btn, {
    req(input$compare_files)
    
    # Validate we have between 2-3 files
    if (length(input$compare_files$name) < 2) {
      log_msg("ERROR: Need at least 2 files for comparison")
      showNotification("Please upload at least 2 files", type = "error")
      return()
    }
    
    if (length(input$compare_files$name) > 3) {
      log_msg("WARNING: More than 3 files uploaded. Using first 3 files.")
      showNotification("Using first 3 files (max limit)", type = "warning")
    }
    
    # Get first 3 files
    files_to_analyze <- input$compare_files[1:min(3, length(input$compare_files$name)), ]
    rv$current_file <- paste(files_to_analyze$name, collapse = ", ")
    log_msg(paste("Starting multi-file analysis:", rv$current_file))
    
    tryCatch({
      # Disable button during processing
      shinyjs::disable("compare_btn")
      on.exit(shinyjs::enable("compare_btn"))
      
      # Create proper form data with all files
      body <- list()
      for (i in seq_along(files_to_analyze$datapath)) {
        body[[paste0("files", i)]] <- httr::upload_file(files_to_analyze$datapath[i])
      }
      
      # Send request to Flask backend
      res <- POST(
        url = "http://localhost:5000/analyze",
        body = body,
        encode = "multipart",
        timeout(120)  # 30 second timeout
      )
      
      # Handle response
      if (res$status_code == 200) {
        # Parse JSON with error handling
        data <- tryCatch({
          fromJSON(rawToChar(res$content))
        }, error = function(e) {
          log_msg(paste("JSON parsing failed:", e$message))
          return(NULL)
        })
        
        if (!is.null(data)) {
          if (isTRUE(data$success)) {
            # Clean NaN values in ANOVA results
            if (!is.null(data$anova_results)) {
              data$anova_results$wpm_pvalue <- ifelse(
                is.nan(data$anova_results$wpm_pvalue),
                NA,
                data$anova_results$wpm_pvalue
              )
            }
            
            rv$comparison <- data
            log_msg("Multi-file analysis completed successfully")
            
            # Format p-value for display
            pval <- ifelse(is.null(data$anova_results$wpm_pvalue) || is.na(data$anova_results$wpm_pvalue),
                           NA,
                           data$anova_results$wpm_pvalue)
            
            log_msg(paste("ANOVA p-value:", ifelse(is.na(pval), "N/A", format.pval(pval, digits = 3))))
            showNotification("Analysis completed successfully", type = "message")
          } else {
            log_msg(paste("Backend reported error:", data$error))
            showNotification(paste("Error:", data$error), type = "error")
          }
        }
      } else {
        error_msg <- tryCatch({
          err_data <- fromJSON(rawToChar(res$content))
          if (!is.null(err_data$error)) err_data$error else "Unknown error"
        }, error = function(e) rawToChar(res$content))
        
        log_msg(paste("Server error", res$status_code, ":", error_msg))
        showNotification(paste("Server error:", error_msg), type = "error")
      }
    }, error = function(e) {
      log_msg(paste("Critical error during analysis:", e$message))
      showNotification("Processing failed. Please check debug console.", type = "error")
    })
  })
  
  # Plot rendering functions for single file analysis
  output$wpm_plot <- renderImage({
    req(rv$plots$wpm_plot)
    tmpfile <- tempfile(fileext = ".png")
    writeBin(base64enc::base64decode(rv$plots$wpm_plot), tmpfile)
    list(src = tmpfile, width = "100%")
  }, deleteFile = TRUE)
  
  output$pause_confidence_plot <- renderImage({
    req(rv$plots$pause_confidence_plot)
    tmpfile <- tempfile(fileext = ".png")
    writeBin(base64enc::base64decode(rv$plots$pause_confidence_plot), tmpfile)
    list(src = tmpfile, width = "100%")
  }, deleteFile = TRUE)
  
  output$vocab_heatmap <- renderImage({
    req(rv$plots$vocab_heatmap)
    tmpfile <- tempfile(fileext = ".png")
    writeBin(base64enc::base64decode(rv$plots$vocab_heatmap), tmpfile)
    list(src = tmpfile, width = "100%")
  }, deleteFile = TRUE)
  
  output$energy_confidence_plot <- renderImage({
    req(rv$plots$energy_confidence_plot)
    tmpfile <- tempfile(fileext = ".png")
    writeBin(base64enc::base64decode(rv$plots$energy_confidence_plot), tmpfile)
    list(src = tmpfile, width = "100%")
  }, deleteFile = TRUE)
  
  # Plot rendering functions for multi-file comparison
  output$metrics_comparison <- renderImage({
    req(rv$comparison$comparison_plots$metrics_comparison)
    tmpfile <- tempfile(fileext = ".png")
    writeBin(base64enc::base64decode(rv$comparison$comparison_plots$metrics_comparison), tmpfile)
    list(src = tmpfile, width = "100%")
  }, deleteFile = TRUE)
  
  output$vocab_conf_comparison <- renderImage({
    req(rv$comparison$comparison_plots$vocab_conf_comparison)
    tmpfile <- tempfile(fileext = ".png")
    writeBin(base64enc::base64decode(rv$comparison$comparison_plots$vocab_conf_comparison), tmpfile)
    list(src = tmpfile, width = "100%")
  }, deleteFile = TRUE)
  
  # Data tables for single file analysis
  output$speech_stats <- renderDT({
    req(rv$stats)
    datatable(
      data.frame(
        Metric = c("Avg WPM", "WPM Variability", "Silence Ratio", "Avg Pause Duration"),
        Value = c(
          rv$stats$speech_metrics$mean_wpm,
          rv$stats$speech_metrics$wpm_variability,
          paste0(round(rv$stats$speech_metrics$silence_ratio * 100, 1), "%"),
          paste(round(rv$stats$speech_metrics$avg_pause_duration, 2), "s")
        )
      ),
      options = list(dom = 't', pageLength = 4),
      rownames = FALSE
    )
  })
  
  output$vocab_stats <- renderDT({
    req(rv$stats)
    datatable(
      data.frame(
        Metric = c("Unique Words", "Lexical Diversity", "Avg Word Length"),
        Value = c(
          rv$stats$vocab_metrics$unique_words,
          rv$stats$vocab_metrics$lexical_diversity,
          rv$stats$vocab_metrics$avg_word_length
        )
      ),
      options = list(dom = 't', pageLength = 3),
      rownames = FALSE
    )
  })
  
  # Data tables for multi-file comparison
  output$comparison_table <- renderDT({
    req(rv$comparison$files)
    datatable(
      do.call(rbind, lapply(rv$comparison$files, function(x) {
        data.frame(
          File = x$filename,
          WPM = round(x$stats$speech_metrics$mean_wpm, 1),
          Confidence = paste0(round(x$stats$confidence_metrics$high_confidence_ratio * 100, 1), "%"),
          
          'Lexical Diversity' = round(x$stats$vocab_metrics$lexical_diversity, 2),
          check.names = FALSE
        )
      })),
      options = list(
        pageLength = 5,
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
      rownames = FALSE
    )
  })
  
  # Statistical results output
  output$anova_result <- renderText({
    req(rv$comparison$anova_results)
    pval <- rv$comparison$anova_results$wpm_pvalue
    
    if (is.null(pval) || is.na(pval)) {
      return("ANOVA RESULTS:\nCould not calculate statistical significance (insufficient data variation)")
    }
    
    sig <- ifelse(pval < 0.05, 
                  "\nCONCLUSION: Speaking rates are significantly different (p < 0.05)",
                  "\nCONCLUSION: No significant difference in speaking rates")
    paste("ANOVA RESULTS:\n",
          "p-value: ", format.pval(pval, digits=4), 
          sig)
  })
  
  # Debug console output
  output$debug_log <- renderText({
    rv$debug_log
  })
  
  # Transcript output
  output$transcript <- renderText({
    rv$transcript
  })
  
  # Current file indicator
  output$current_file <- renderText({
    ifelse(is.null(rv$current_file), "No file loaded", paste("Analyzing:", rv$current_file))
  })
}