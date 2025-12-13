//go:build windows

package main

import (
	"bytes"
	"context"
	"log/slog"
	"os"
	"time"

	"github.com/prometheus-community/windows_exporter/pkg/collector"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/common/expfmt"
)

func collectMetricsDirectly() ([]byte, error) {
	// Create a logger
	logger := slog.New(slog.NewTextHandler(os.Stderr, &slog.HandlerOptions{
		Level: slog.LevelWarn,
	}))

	// Create prometheus registry
	registry := prometheus.NewRegistry()

	// Initialize windows collectors with default empty configuration to use defaults
	collectors := collector.NewWithConfig(collector.Config{})

	// Build the collectors - Build expects context.Context as first argument, then logger
	ctx := context.Background()
	if err := collectors.Build(ctx, logger); err != nil {
		return nil, err
	}

	// Create a Handler that implements prometheus.Collector for the collection
	// Use all collectors with a max scrape duration of 30 seconds
	handler, err := collectors.NewHandler(30*time.Second, logger, []string{})
	if err != nil {
		return nil, err
	}

	// Register the handler (which implements prometheus.Collector)
	if err := registry.Register(handler); err != nil {
		return nil, err
	}

	// Gather metrics
	metricFamilies, err := registry.Gather()
	if err != nil {
		return nil, err
	}

	// Convert to Prometheus text format
	var buffer bytes.Buffer
	encoder := expfmt.NewEncoder(&buffer, expfmt.NewFormat(expfmt.TypeTextPlain))
	for _, mf := range metricFamilies {
		if err := encoder.Encode(mf); err != nil {
			logger.Error("error encoding metrics", "err", err)
			continue
		}
	}

	return buffer.Bytes(), nil
}

func init() {
	// Set minimal log level to avoid excessive logging from collectors
	slog.SetDefault(slog.New(slog.NewTextHandler(os.Stderr, &slog.HandlerOptions{
		Level: slog.LevelWarn,
	})))
}
