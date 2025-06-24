library(shiny)
library(tidyverse)
library(TTR)
library(signal)
library(ggrepel)  # Load ggrepel for label repelling

# Define UI
ui <- fluidPage(
  titlePanel("Wheelchair Kinematic Summary"),
  
  # Add background color to the entire app
  tags$style(type = "text/css", "body {background-color: #f2e9ff;}"),
  
  # Add logo image to the top right corner
  tags$img(src = "lu_logo.png", height = 50, width = 175, style = "position: absolute; top: 10px; right: 10px;"),
  
  sidebarLayout(
    sidebarPanel(
      width = 3,  # Adjust the width of the sidebar panel
      
      # New selectInput for file selection
      selectInput("file", "Choose a Trial to Analyze",
                  choices = list.files("Trials", pattern = "\\.csv$", full.names = TRUE)),
      
      # # Slider inputs for start and end times
      # sliderInput("start_time", "Start Time (seconds):", min = 0, max = 100, value = 0),
      # sliderInput("end_time", "End Time (seconds):", min = 0, max = 100, value = 100),
      
      sliderInput("start_time", "Start Time (seconds):", min = 0, max = 100, value = 0),
      sliderInput("end_time", "End Time (seconds):", min = 0, max = 100, value = 100),
      
      tags$hr(),
      h5("Note: The red dashed line in the Linear and Rotational tabs represent the average for that plot")
      
    ),
    
    mainPanel(
      width = 9,  # Adjust the width of the main panel
      tabsetPanel(
        id = "tabs",
        tabPanel("Raw Data", plotOutput("raw_plot", height = "300px")),  # Adjust height here
        tabPanel("Linear Metrics", 
                 plotOutput("forward_acceleration", height = "300px"),  # Adjust height here
                 plotOutput("forward_velocity", height = "300px"),  # Adjust height here
                 plotOutput("distance_covered", height = "300px")),  # Adjust height here
        tabPanel("Rotational Metrics",
                 plotOutput("rotational_acceleration", height = "300px"),  # Adjust height here
                 plotOutput("rotational_velocity", height = "300px"),  # Adjust height here
                 plotOutput("total_rotation", height = "300px")), # Adjust height here
        # Add the Help tab
        tabPanel("Help", 
                 h3("How to Use and Interpret the App"),
                 p("This app helps analyze wheelchair kinematic data by calculating linear and rotational metrics."),
                 p("1. Choose a CSV file from the drop-down list - 
                   Each individual file contains kinematic data from a specific wheelchair basketball drill conducted by a participant."),
                 p("2. Use the sliders to select the start and end times for the analysis."),
                 p("3. The 'Raw Data' tab displays the raw data with important peaks labeled."),
                 p("4. Explore different metrics in the Linear and Rotational tabs."),
                 p("5. The Linear Metrics tab shows the forward acceleration, velocity, and distance covered over time."),
                 p("6. The Rotational Metrics tab shows the rotational acceleration, velocity, and total rotation over time."),
                 p("These graphs can be used by wheelchair basketball athletes to monitor their performance and identify areas for improvement and set performance goals."))
      )
    )
  ),
  
  # Adjust UI style
  tags$head(
    tags$style(HTML("
                    .tab-content {
                      padding: 20px;
                    }
                    .navbar-default {
                      background-color: #f2f2f7;
                      border-color: #e7e7e7;
                    }
                    .sidebar-panel {
                      border-right: 1px solid #ddd;
                      padding-top: 20px;
                    }
                    "))
  )
)

server <- function(input, output, session) {
  
  # Reactive expression to read and process data based on selected file
  data <- reactive({
    req(input$file)
    
    # Read the CSV file
    file_path <- input$file
    data <- read.csv(file_path, header = FALSE, col.names = paste0("V", 1:7))
    
    # Process the data
    data <- data %>%
      dplyr::filter(!grepl("putty", V1, ignore.case = TRUE)) %>%
      slice((which(V1 == "Time (ms)") + 1):n())
    
    # Assign and clean column names
    colnames(data) <- unlist(data[1, ])
    data <- data[-1, ]
    rownames(data) <- NULL
    colnames(data) <- gsub("\\s*\\(.*\\)", "", colnames(data))
    colnames(data) <- make.unique(colnames(data))
    data <- mutate_all(data, ~as.numeric(as.character(.)))
    colnames(data) <- c("time", "accX", "accY", "accZ", "rotX", "rotY", "rotZ")
    
    # Convert time to seconds
    data$time_s <- data$time / 1000
    
    return(data)
  })
  
  # Update slider inputs when a new file is selected
  observeEvent(input$file, {
    req(data())
    max_time <- ceiling(max(data()$time_s, na.rm = TRUE))
    
    # Set slider limits based on new data
    updateSliderInput(session, "start_time", min = 0, max = max_time, value = 0)
    updateSliderInput(session, "end_time", min = 0, max = max_time, value = max_time)
  })
  
  # Reactive expression for data smoothing, filtering, and selecting based on slider inputs
  sensor_data <- reactive({
    req(data(), input$start_time, input$end_time)
    window_size <- 5
    data <- data()
    
    # Apply smoothing
    data$accX_smoothed <- SMA(data$accX, n = window_size)
    data$accY_smoothed <- SMA(data$accY, n = window_size)
    data$accZ_smoothed <- SMA(data$accZ, n = window_size)
    data$rotX_smoothed <- SMA(data$rotX, n = window_size)
    data$rotY_smoothed <- SMA(data$rotY, n = window_size)
    data$rotZ_smoothed <- SMA(data$rotZ, n = window_size)
    
    # Apply Butterworth filter
    sampling_frequency <- 84
    cutoff_frequency <- 3
    normalized_cutoff <- cutoff_frequency / (sampling_frequency / 2)
    butterworth_filter <- butter(4, normalized_cutoff, type = "low")
    
    # Filter each axis
    data$accX_adj <- filtfilt(butterworth_filter, data$accX_smoothed)
    data$accY_adj <- filtfilt(butterworth_filter, data$accY_smoothed)
    data$accZ_adj <- filtfilt(butterworth_filter, data$accZ_smoothed)
    data$rotX_adj <- filtfilt(butterworth_filter, data$rotX_smoothed)
    data$rotY_adj <- filtfilt(butterworth_filter, data$rotY_smoothed)
    data$rotZ_adj <- filtfilt(butterworth_filter, data$rotZ_smoothed)
    
    # Filter by start and end times from sliders
    data <- subset(data, time_s >= input$start_time & time_s <= input$end_time)
    
    # Identify start and end indices
    start_index <- which(abs(data$accX_adj) > 1.2 | abs(data$rotZ_adj) > 1.2)[1]
    while (start_index > 1) {
      if (abs(data$accX_adj[start_index]) < 0.002 | abs(data$rotZ_adj[start_index]) < 0.002) break
      start_index <- start_index - 1
    }
    
    end_index <- length(data$accX_adj) - which(abs(rev(data$accX_adj)) > 1.2 | abs(rev(data$rotZ_adj)) > 1.2)[1] + 1
    while (end_index < nrow(data)) {
      if (abs(data$accX_adj[end_index]) < 0.002 | abs(data$rotZ_adj[end_index]) < 0.002) break
      end_index <- end_index + 1
    }
    
    # Create final dataframe and clean it
    sensor_data <- data[start_index:end_index, ]
    sensor_data <- subset(sensor_data, select = -c(accX, accY, accZ, rotX, rotY, rotZ, accX_smoothed, accY_smoothed, accZ_smoothed, rotX_smoothed, rotY_smoothed, rotZ_smoothed))
    names(sensor_data) <- gsub("_adj", "", names(sensor_data))
    rownames(sensor_data) <- NULL
    sensor_data <- mutate(sensor_data, time_s = time_s - min(time_s))
    sensor_data$rotation_direction <- ifelse(sensor_data$rotZ > 0, "Anticlockwise", "Clockwise")
    
    return(sensor_data)
  })

  
  output$raw_plot <- renderPlot({
    req(sensor_data())
    data <- sensor_data()
    # Find peaks for each variable
    peak_accX <- which.max(data$accX)
    peak_accZ <- which.max(data$accZ)
    peak_rotZ <- which.max(data$rotZ)
    # Get peak values and times
    peak_value_accX <- data$accX[peak_accX]
    peak_time_accX <- data$time_s[peak_accX]
    peak_value_accZ <- data$accZ[peak_accZ]
    peak_time_accZ <- data$time_s[peak_accZ]
    peak_value_rotZ <- data$rotZ[peak_rotZ]
    peak_time_rotZ <- data$time_s[peak_rotZ]
    ggplot(data, aes(x = time_s)) +
      geom_line(aes(y = accX, color = "Forward Acceleration (m/s^2)"), size = 1.1) +
      geom_line(aes(y = accZ, color = "Vertical Acceleration (m/s^2)"), size = 1.1) +
      geom_line(aes(y = rotZ, color = "Rotational Velocity (rad/s)"), size = 1.1) +
      geom_label_repel(data = data.frame(time_s = peak_time_accX, accX = peak_value_accX), 
                       aes(x = peak_time_accX, y = peak_value_accX, label = paste0("Peak accX: ", round(peak_value_accX, 2))), 
                       nudge_y = 1, color = "red", size = 5) +  # Add label for accX peak
      geom_label_repel(data = data.frame(time_s = peak_time_accZ, accZ = peak_value_accZ), 
                       aes(x = peak_time_accZ, y = peak_value_accZ, label = paste0("Peak accZ: ", round(peak_value_accZ, 2))), 
                       nudge_y = 1, color = "blue", size = 5) +  # Add label for accZ peak
      geom_label_repel(data = data.frame(time_s = peak_time_rotZ, rotZ = peak_value_rotZ), 
                       aes(x = peak_time_rotZ, y = peak_value_rotZ, label = paste0("Peak rotZ: ", round(peak_value_rotZ, 2))), 
                       nudge_y = 1, color = "darkgreen", size = 5) +  # Add label for rotZ peak
      labs(x = "Time (seconds)", y = "Value", color = "Variables") +
      scale_x_continuous(breaks = seq(0, max(data$time_s), by = 2)) +
      theme_minimal() +
      theme(
        text = element_text(size = 14, face = "bold"),
        legend.position = "bottom"
      )
  })
  
  
  output$forward_acceleration <- renderPlot({
    req(sensor_data())
    data <- sensor_data()
    ggplot(data, aes(x = time_s, y = accX)) +
      geom_line(size = 1.1) +
      geom_hline(yintercept = mean(data$accX), linetype = "dashed", color = "red") +  
      geom_point(data = data[data$accX == max(data$accX), ], aes(x = time_s, y = accX), color = "blue", size = 5, shape = 16) +  
      geom_label_repel(data = data[data$accX == max(data$accX), ], aes(x = time_s, y = accX, label = paste("Peak Acc:", round(max(data$accX), 2))), 
                       nudge_y = 1, color = "blue", size = 5) +  # Add label for peak
      xlab("Time (seconds)") +
      ylab("Forward Acceleration (m/s^2)") +
      ggtitle("Forward Acceleration vs Time") +
      theme(
        text = element_text(size = 14, face = "bold")
      )
  })
  
  output$forward_velocity <- renderPlot({
    req(sensor_data())
    data <- sensor_data()
    data <- data %>%
      mutate(velocity_x = cumsum(accX * c(0, diff(time_s))))
    ggplot(data, aes(x = time_s, y = velocity_x)) +
      geom_line(size = 1.1) +
      geom_hline(yintercept = mean(data$velocity_x), linetype = "dashed", color = "red") +
      geom_point(data = data[data$velocity_x == max(data$velocity_x),], aes(x = time_s, y = velocity_x), color = "blue", size = 5) +
      geom_label_repel(data = data[data$velocity_x == max(data$velocity_x),], aes(x = time_s, y = velocity_x, label = paste("Peak Vel:", round(max(data$velocity_x), 2))), 
                       nudge_y = 1, color = "blue", size = 5) +  # Add label for peak
      labs(x = "Time (s)", y = "Forward Velocity (m/s)") +
      ggtitle("Forward Velocity vs.Time") +
      theme(
        text = element_text(size = 14, face = "bold")
      )
  })
  
  output$distance_covered <- renderPlot({
    req(sensor_data())
    data <- sensor_data()
    data <- data %>%
      mutate(velocity_x = cumsum(accX * c(0, diff(time_s))),
             distance_covered = cumsum(velocity_x * c(0, diff(time_s))))
    ggplot(data, aes(x = time_s, y = distance_covered)) +
      geom_line(size = 1.1) +
      labs(x = "Time (s)", y = "Distance Covered") +
      ggtitle("Distance Covered vs. Time") +
      theme(
        text = element_text(size = 14, face = "bold")
      )
  })
  
  output$rotational_acceleration <- renderPlot({
    req(sensor_data())
    data <- sensor_data()
    data <- data %>%
      mutate(rotational_acceleration = c(0, diff(rotZ) / diff(time_s)))
    peak_index <- which.max(data$rotational_acceleration)
    peak_value <- ifelse(length(peak_index) > 0, data$rotational_acceleration[peak_index], NA)
    peak_time <- ifelse(length(peak_index) > 0, data$time_s[peak_index], NA)
    ggplot(data, aes(x = time_s, y = rotational_acceleration)) +
      geom_line(size = 1.1) +
      geom_hline(yintercept = mean(data$rotational_acceleration, na.rm = TRUE), linetype = "dashed", color = "red") +
      geom_point(data = data.frame(time_s = peak_time, rotational_acceleration = peak_value), aes(x = time_s, y = rotational_acceleration), color = "blue", size = 5) +
      geom_label_repel(data = data.frame(time_s = peak_time, rotational_acceleration = peak_value), 
                       aes(x = time_s, y = rotational_acceleration, label = paste0("Peak: ", round(peak_value, 2))), 
                       nudge_y = 1, color = "blue", size = 5) +  # Add label for peak
      xlab("Time (seconds)") +
      ylab("Rotational Acceleration (rad/s^2)") +
      ggtitle("Rotational Acceleration vs Time") +
      theme(
        text = element_text(size = 14, face = "bold")
      )
  })
  
  output$rotational_velocity <- renderPlot({
    req(sensor_data())
    data <- sensor_data()
    peak_index <- which.max(data$rotZ)
    peak_value <- ifelse(length(peak_index) > 0, data$rotZ[peak_index], NA)
    peak_time <- ifelse(length(peak_index) > 0, data$time_s[peak_index], NA)
    ggplot(data, aes(x = time_s, y = rotZ)) +
      geom_line(size = 1.1) +
      geom_hline(yintercept = mean(data$rotZ), linetype = "dashed", color = "red") + 
      geom_point(data = data[peak_index, ], aes(x = peak_time, y = peak_value), color = "blue", size = 5, shape = 16) + 
      geom_label_repel(data = data[peak_index, ], aes(x = peak_time, y = peak_value, label = paste0("Peak: ", round(peak_value, 2))), 
                       nudge_y = 1, color = "blue", size = 5) +  # Add label for peak
      xlab("Time (seconds)") +
      ylab("Rotational Velocity (rad/s)") +
      ggtitle("Rotational Velocity vs Time") +
      theme(
        text = element_text(size = 14, face = "bold")
      )
  })
  
  output$total_rotation <- renderPlot({
    req(sensor_data())
    ggplot(sensor_data(), aes(x = time_s, y = cumsum(rotZ) * (time_s[2] - time_s[1]))) +
      geom_line(size = 1.1) +
      xlab("Time (seconds)") +
      ylab("Total Rotation (radians)") +
      ggtitle("Total Rotation vs Time") +
      theme(
        text = element_text(size = 14, face = "bold")
      )
  })
  
}

# Run the application
shinyApp(ui = ui, server = server)
