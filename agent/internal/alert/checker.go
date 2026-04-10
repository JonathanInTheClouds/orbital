package alert

import (
	"bytes"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"sync"
	"time"

	"orbital-agent/internal/config"
	"orbital-agent/internal/metrics"
)

type Payload struct {
	ServerID   string  `json:"server_id"`
	ServerName string  `json:"server_name,omitempty"`
	Metric     string  `json:"metric"`
	Value      float64 `json:"value"`
	Threshold  float64 `json:"threshold"`
	Timestamp  string  `json:"timestamp"`
}

// Checker compares a Snapshot against configured thresholds, enforces
// per-metric cooldowns, and fires HTTP POSTs when an alert should be sent.
type Checker struct {
	cfg      *config.Config
	mu       sync.Mutex
	lastSent map[string]time.Time
	client   *http.Client
}

func NewChecker(cfg *config.Config) *Checker {
	return &Checker{
		cfg:      cfg,
		lastSent: make(map[string]time.Time),
		client:   &http.Client{Timeout: 10 * time.Second},
	}
}

func (c *Checker) Check(snap *metrics.Snapshot) {
	c.maybeAlert("cpu", snap.CPUPercent, c.cfg.Thresholds.CPUPercent)
	c.maybeAlert("ram", snap.RAMPercent, c.cfg.Thresholds.RAMPercent)
	c.maybeAlert("disk", snap.DiskPercent, c.cfg.Thresholds.DiskPercent)
}

func (c *Checker) maybeAlert(metric string, value, threshold float64) {
	if value < threshold {
		return
	}

	c.mu.Lock()
	cooldown := time.Duration(c.cfg.CooldownMinutes) * time.Minute
	if last, exists := c.lastSent[metric]; exists && time.Since(last) < cooldown {
		c.mu.Unlock()
		log.Printf("ALERT %s=%.1f%% suppressed (cooldown %dm)", metric, value, c.cfg.CooldownMinutes)
		return
	}
	c.mu.Unlock()

	now := time.Now().UTC()
	log.Printf("ALERT %s=%.1f%% exceeds threshold %.1f%% — sending", metric, value, threshold)

	p := Payload{
		ServerID:   c.cfg.ServerID,
		ServerName: c.cfg.DisplayName(),
		Metric:     metric,
		Value:      value,
		Threshold:  threshold,
		Timestamp:  now.Format(time.RFC3339),
	}

	if err := c.post(p); err != nil {
		log.Printf("ERROR sending alert: %v", err)
	} else {
		c.mu.Lock()
		c.lastSent[metric] = now
		c.mu.Unlock()
		log.Printf("alert sent successfully")
	}
}

func (c *Checker) post(p Payload) error {
	body, err := json.Marshal(p)
	if err != nil {
		return fmt.Errorf("marshal payload: %w", err)
	}

	req, err := http.NewRequest(http.MethodPost, c.cfg.RelayURL, bytes.NewReader(body))
	if err != nil {
		return fmt.Errorf("build request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")
	if c.cfg.AuthToken != "" {
		req.Header.Set("Authorization", "Bearer "+c.cfg.AuthToken)
	}

	resp, err := c.client.Do(req)
	if err != nil {
		return fmt.Errorf("http post: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode >= 300 {
		return fmt.Errorf("relay returned HTTP %d", resp.StatusCode)
	}
	return nil
}
