package main

import (
	"bytes"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"runtime"
	"time"
)

const (
	DefaultScrapeInterval = 15 * time.Second
)

func main() {
	// Get hook URL from parameter or environment
	hookURL := os.Getenv("HOOK_URL")
	if len(os.Args) > 1 {
		// Check if it's --hook-url or -hook-url parameter
		for i, arg := range os.Args[1:] {
			if arg == "--hook-url" || arg == "-hook-url" {
				if i+2 < len(os.Args) {
					hookURL = os.Args[i+2]
					break
				}
			}
		}
	}

	if hookURL == "" {
		log.Fatal("Error: HOOK_URL environment variable or --hook-url parameter is required")
	}

	log.Printf("Starting unified metrics exporter")
	log.Printf("Target endpoint: %s", hookURL)
	log.Printf("Platform: %s", runtime.GOOS)
	log.Printf("Scrape interval: %s", DefaultScrapeInterval)

	// Start the metrics collection loop
	ticker := time.NewTicker(DefaultScrapeInterval)
	defer ticker.Stop()

	// Collect and send immediately on startup
	collectAndSend(hookURL)

	for range ticker.C {
		collectAndSend(hookURL)
	}
}

func collectAndSend(hookURL string) {
	metrics, err := collectMetrics()
	if err != nil {
		log.Printf("Error collecting metrics: %v", err)
		return
	}

	if err := sendMetrics(hookURL, metrics); err != nil {
		log.Printf("Error sending metrics: %v", err)
		return
	}

	log.Printf("Successfully sent %d bytes of metrics", len(metrics))
}

func collectMetrics() ([]byte, error) {
	// Platform-specific implementation in collector_unix.go or collector_windows.go
	return collectMetricsDirectly()
}

// collectMetricsDirectly is implemented in platform-specific files:
// - collector_unix.go for Linux/macOS/BSD
// - collector_windows.go for Windows

func sendMetrics(hookURL string, metrics []byte) error {
	req, err := http.NewRequest("POST", hookURL, bytes.NewReader(metrics))
	if err != nil {
		return fmt.Errorf("failed to create request: %w", err)
	}

	req.Header.Set("Content-Type", "text/plain; version=0.0.4")
	req.Header.Set("User-Agent", "unified-exporter/1.0")

	client := &http.Client{
		Timeout: 10 * time.Second,
	}

	resp, err := client.Do(req)
	if err != nil {
		return fmt.Errorf("failed to send request: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		body, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("unexpected status code %d: %s", resp.StatusCode, string(body))
	}

	return nil
}
