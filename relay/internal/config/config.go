package config

import (
	"encoding/json"
	"fmt"
	"os"
)

type APNsConfig struct {
	Stub     bool   `json:"stub"`
	KeyFile  string `json:"key_file"`
	KeyID    string `json:"key_id"`
	TeamID   string `json:"team_id"`
	BundleID string `json:"bundle_id"`
	Sandbox  bool   `json:"sandbox"`
}

type FCMConfig struct {
	Stub               bool   `json:"stub"`
	ServiceAccountFile string `json:"service_account_file"`
	ProjectID          string `json:"project_id"`
}

type Config struct {
	ListenAddr  string     `json:"listen_addr"`
	AuthToken   string     `json:"auth_token"`
	StoreFile   string     `json:"store_file"`
	MultiTenant bool       `json:"multi_tenant"`
	APNs        APNsConfig `json:"apns"`
	FCM         FCMConfig  `json:"fcm"`
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

	cfg.applyDefaults()

	if err := cfg.validate(); err != nil {
		return nil, err
	}

	return &cfg, nil
}

func (c *Config) applyDefaults() {
	if c.ListenAddr == "" {
		c.ListenAddr = ":8080"
	}
	if c.StoreFile == "" {
		c.StoreFile = "./devices.json"
	}
}

func (c *Config) validate() error {
	if !c.MultiTenant && c.AuthToken == "" {
		return fmt.Errorf("config: auth_token is required (or enable multi_tenant)")
	}
	if !c.APNs.Stub {
		if c.APNs.KeyFile == "" || c.APNs.KeyID == "" || c.APNs.TeamID == "" || c.APNs.BundleID == "" {
			return fmt.Errorf("config: apns.key_file, key_id, team_id, bundle_id are required when stub=false")
		}
	}
	if !c.FCM.Stub {
		if c.FCM.ServiceAccountFile == "" || c.FCM.ProjectID == "" {
			return fmt.Errorf("config: fcm.service_account_file and project_id are required when stub=false")
		}
	}
	return nil
}
