//go:build windows

package main

import (
	"bytes"
	"log/slog"
	"os"

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

	// Build the collectors
	if err := collectors.Build(logger, nil); err != nil {
		return nil, err
	}

	// Register the collector
	if err := registry.Register(collectors); err != nil {
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
