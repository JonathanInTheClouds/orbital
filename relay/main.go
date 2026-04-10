package main

import (
	"flag"
	"log"
	"net/http"
	"time"

	"orbital-relay/internal/api"
	"orbital-relay/internal/config"
	"orbital-relay/internal/push"
	"orbital-relay/internal/store"
)

func main() {
	cfgPath := flag.String("config", "config.json", "path to config file")
	flag.Parse()

	cfg, err := config.Load(*cfgPath)
	if err != nil {
		log.Fatalf("FATAL: %v", err)
	}

	if cfg.MultiTenant {
		log.Printf("orbital-relay starting on %s (multi-tenant mode)", cfg.ListenAddr)
	} else {
		log.Printf("orbital-relay starting on %s (single-tenant mode)", cfg.ListenAddr)
	}

	s, err := store.New(cfg.StoreFile)
	if err != nil {
		log.Fatalf("FATAL: store: %v", err)
	}

	dispatcher, err := push.NewDispatcher(cfg)
	if err != nil {
		log.Fatalf("FATAL: push: %v", err)
	}

	mux := http.NewServeMux()
	handler := api.NewHandler(cfg.AuthToken, cfg.MultiTenant, s, dispatcher)
	handler.Register(mux)

	log.Printf("routes: POST /alert  POST /register  GET /health")

	server := &http.Server{
		Addr:              cfg.ListenAddr,
		Handler:           mux,
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       10 * time.Second,
		WriteTimeout:      15 * time.Second,
		IdleTimeout:       60 * time.Second,
	}

	if err := server.ListenAndServe(); err != nil {
		log.Fatalf("FATAL: server: %v", err)
	}
}
