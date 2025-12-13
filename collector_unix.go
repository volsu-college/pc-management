//go:build linux || darwin || freebsd || openbsd || netbsd || dragonfly || aix || solaris

package main

import (
	"bytes"
	"log/slog"
	"os"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/common/expfmt"
	"github.com/prometheus/common/promslog"
	"github.com/prometheus/node_exporter/collector"
)

func collectMetricsDirectly() ([]byte, error) {
	// Create a logger with default config
	promslogConfig := &promslog.Config{}
	logger := promslog.New(promslogConfig)

	// Create prometheus registry
	registry := prometheus.NewRegistry()

	// Create node collector with default collectors
	nc, err := collector.NewNodeCollector(logger)
	if err != nil {
		return nil, err
	}

	// Register the collector
	if err := registry.Register(nc); err != nil {
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
