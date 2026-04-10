package main

import (
	"flag"
	"log"
	"time"

	"orbital-agent/internal/alert"
	"orbital-agent/internal/config"
	"orbital-agent/internal/metrics"
)

func main() {
	cfgPath := flag.String("config", "config.json", "path to config file")
	flag.Parse()

	cfg, err := config.Load(*cfgPath)
	if err != nil {
		log.Fatalf("FATAL: %v", err)
	}

	log.Printf("orbital-agent starting — server_id=%s server_name=%q poll=%ds cooldown=%dm",
		cfg.ServerID, cfg.DisplayName(), cfg.PollIntervalSeconds, cfg.CooldownMinutes)
	log.Printf("thresholds — cpu=%.0f%% ram=%.0f%% disk=%.0f%%",
		cfg.Thresholds.CPUPercent, cfg.Thresholds.RAMPercent, cfg.Thresholds.DiskPercent)

	reader := metrics.NewReader()
	checker := alert.NewChecker(cfg)

	// Prime the CPU reader — first Read() establishes the baseline sample;
	// the returned CPUPercent will be 0 and is intentionally not checked.
	if _, err := reader.Read(); err != nil {
		log.Printf("WARNING: initial metrics read failed: %v", err)
	}

	ticker := time.NewTicker(time.Duration(cfg.PollIntervalSeconds) * time.Second)
	defer ticker.Stop()

	for range ticker.C {
		snap, err := reader.Read()
		if err != nil {
			log.Printf("ERROR: metrics read failed: %v", err)
			continue
		}
		log.Printf("metrics — cpu=%.1f%% ram=%.1f%% disk=%.1f%%",
			snap.CPUPercent, snap.RAMPercent, snap.DiskPercent)
		checker.Check(snap)
	}
}
