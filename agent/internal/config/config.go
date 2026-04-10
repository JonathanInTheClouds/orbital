package config

import (
	"encoding/json"
	"fmt"
	"os"
)

type Thresholds struct {
	CPUPercent  float64 `json:"cpu_percent"`
	RAMPercent  float64 `json:"ram_percent"`
	DiskPercent float64 `json:"disk_percent"`
}

type Config struct {
	ServerID            string     `json:"server_id"`
	ServerName          string     `json:"server_name"`
	RelayURL            string     `json:"relay_url"`
	AuthToken           string     `json:"auth_token"`
	PollIntervalSeconds int        `json:"poll_interval_seconds"`
	CooldownMinutes     int        `json:"cooldown_minutes"`
	Thresholds          Thresholds `json:"thresholds"`
}

// DisplayName returns ServerName if set, otherwise falls back to ServerID.
func (c *Config) DisplayName() string {
	if c.ServerName != "" {
		return c.ServerName
	}
	return c.ServerID
}

func Load(path string) (*Config, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, fmt.Errorf("open config: %w", err)
	}
	defer f.Close()

	var cfg Config
	if err := json.NewDecoder(f).Decode(&cfg); err != nil {
		return nil, fmt.Errorf("parse config: %w", err)
	}

	if err := cfg.validate(); err != nil {
		return nil, err
	}

	cfg.applyDefaults()
	return &cfg, nil
}

func (c *Config) validate() error {
	if c.ServerID == "" {
		return fmt.Errorf("config: server_id is required")
	}
	if c.RelayURL == "" {
		return fmt.Errorf("config: relay_url is required")
	}
	return nil
}

func (c *Config) applyDefaults() {
	if c.PollIntervalSeconds <= 0 {
		c.PollIntervalSeconds = 30
	}
	if c.CooldownMinutes <= 0 {
		c.CooldownMinutes = 5
	}
	if c.Thresholds.CPUPercent <= 0 {
		c.Thresholds.CPUPercent = 90
	}
	if c.Thresholds.RAMPercent <= 0 {
		c.Thresholds.RAMPercent = 90
	}
	if c.Thresholds.DiskPercent <= 0 {
		c.Thresholds.DiskPercent = 85
	}
}
