package api

import (
	"context"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net/http"
	"strings"

	"orbital-relay/internal/push"
	"orbital-relay/internal/store"
)

type alertRequest struct {
	ServerID   string  `json:"server_id"`
	ServerName string  `json:"server_name"`
	Metric     string  `json:"metric"`
	Value      float64 `json:"value"`
	Threshold  float64 `json:"threshold"`
	Timestamp  string  `json:"timestamp"`
}

type registerRequest struct {
	DeviceToken string   `json:"device_token"`
	Platform    string   `json:"platform"`
	ServerIDs   []string `json:"server_ids"`
}

// contextKey is an unexported type for context keys in this package.
type contextKey string

const nsKey contextKey = "namespace"

type Handler struct {
	authToken   string
	multiTenant bool
	store       *store.Store
	dispatcher  *push.Dispatcher
}

const maxJSONBodyBytes = 1 << 20 // 1 MiB

func NewHandler(authToken string, multiTenant bool, s *store.Store, d *push.Dispatcher) *Handler {
	return &Handler{
		authToken:   authToken,
		multiTenant: multiTenant,
		store:       s,
		dispatcher:  d,
	}
}

func (h *Handler) Register(mux *http.ServeMux) {
	mux.HandleFunc("POST /alert", h.requestLogger(h.requireAuth(h.handleAlert)))
	mux.HandleFunc("POST /register", h.requestLogger(h.requireAuth(h.handleRegister)))
	mux.HandleFunc("GET /health", h.requestLogger(h.handleHealth))
}

func (h *Handler) handleAlert(w http.ResponseWriter, r *http.Request) {
	var req alertRequest
	if err := decodeJSONBody(w, r, &req); err != nil {
		return
	}

	if req.ServerID == "" || req.Metric == "" {
		http.Error(w, "server_id and metric are required", http.StatusBadRequest)
		return
	}

	ns := r.Context().Value(nsKey).(string)

	log.Printf("ALERT received server_id=%s server_name=%q metric=%s value=%.1f threshold=%.1f",
		req.ServerID, req.ServerName, req.Metric, req.Value, req.Threshold)

	devices := h.store.DevicesFor(ns, req.ServerID)
	if len(devices) == 0 {
		log.Printf("no devices registered for server_id=%s", req.ServerID)
		w.WriteHeader(http.StatusOK)
		return
	}

	displayName := req.ServerName
	if displayName == "" {
		displayName = req.ServerID
	}
	title := fmt.Sprintf("%s alert — %s", strings.ToUpper(req.Metric), displayName)
	body := fmt.Sprintf("%.1f%% (threshold %.0f%%)", req.Value, req.Threshold)

	var sent, failed int
	for _, d := range devices {
		payload := map[string]string{
			"server_id":    req.ServerID,
			"server_name":  displayName,
			"display_name": displayName,
			"metric":       req.Metric,
			"value":        fmt.Sprintf("%.1f", req.Value),
			"threshold":    fmt.Sprintf("%.1f", req.Threshold),
			"timestamp":    req.Timestamp,
		}

		if err := h.dispatcher.Send(d.Platform, d.Token, title, body, payload); err != nil {
			log.Printf("ERROR sending to %s device: %v", d.Platform, err)
			failed++
		} else {
			sent++
		}
	}

	log.Printf("alert dispatched — server_id=%s display_name=%q sent=%d failed=%d",
		req.ServerID, displayName, sent, failed)
	w.WriteHeader(http.StatusOK)
}

func (h *Handler) handleRegister(w http.ResponseWriter, r *http.Request) {
	var req registerRequest
	if err := decodeJSONBody(w, r, &req); err != nil {
		return
	}

	if req.DeviceToken == "" {
		http.Error(w, "device_token is required", http.StatusBadRequest)
		return
	}
	if req.Platform != "ios" && req.Platform != "android" {
		http.Error(w, `platform must be "ios" or "android"`, http.StatusBadRequest)
		return
	}
	req.ServerIDs = normalizeServerIDs(req.ServerIDs)
	if len(req.ServerIDs) == 0 {
		http.Error(w, "server_ids must not be empty", http.StatusBadRequest)
		return
	}

	ns := r.Context().Value(nsKey).(string)
	device := store.Device{Token: req.DeviceToken, Platform: req.Platform}
	if err := h.store.Register(ns, req.ServerIDs, device); err != nil {
		log.Printf("ERROR registering device: %v", err)
		http.Error(w, "failed to register device", http.StatusInternalServerError)
		return
	}

	log.Printf("registered %s device for servers=%v", req.Platform, req.ServerIDs)
	w.WriteHeader(http.StatusOK)
}

func (h *Handler) handleHealth(w http.ResponseWriter, r *http.Request) {
	w.WriteHeader(http.StatusOK)
	w.Write([]byte("ok"))
}

// requestLogger logs every incoming request — method, path, and remote address.
func (h *Handler) requestLogger(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		log.Printf("REQUEST %s %s from %s", r.Method, r.URL.Path, r.RemoteAddr)
		next(w, r)
	}
}

// requireAuth validates the bearer token. In single-tenant mode it checks
// against the configured auth_token. In multi-tenant mode any token of at
// least 32 characters is accepted; the token is SHA-256 hashed to produce an
// opaque namespace that scopes all store operations for that caller.
func (h *Handler) requireAuth(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		auth := r.Header.Get("Authorization")
		if !strings.HasPrefix(auth, "Bearer ") {
			log.Printf("UNAUTHORIZED %s %s — missing bearer token", r.Method, r.URL.Path)
			http.Error(w, "unauthorized", http.StatusUnauthorized)
			return
		}
		token := strings.TrimPrefix(auth, "Bearer ")

		var ns string
		if h.multiTenant {
			// Accept any sufficiently long token; derive namespace from its hash.
			if len(token) < 32 {
				log.Printf("UNAUTHORIZED %s %s — token too short for multi-tenant mode", r.Method, r.URL.Path)
				http.Error(w, "unauthorized", http.StatusUnauthorized)
				return
			}
			ns = tokenNamespace(token)
		} else {
			// Single-tenant: constant-time comparison against the configured token.
			if subtle.ConstantTimeCompare([]byte(token), []byte(h.authToken)) != 1 {
				log.Printf("UNAUTHORIZED %s %s — invalid token", r.Method, r.URL.Path)
				http.Error(w, "unauthorized", http.StatusUnauthorized)
				return
			}
			ns = "" // no namespace needed; all data belongs to the single tenant
		}

		ctx := context.WithValue(r.Context(), nsKey, ns)
		next(w, r.WithContext(ctx))
	}
}

// tokenNamespace derives a short, opaque namespace string from a bearer token.
// Uses the first 16 hex chars of SHA-256(token) — enough to be collision-free
// in practice while keeping devices.json keys readable.
func tokenNamespace(token string) string {
	h := sha256.Sum256([]byte(token))
	return hex.EncodeToString(h[:8])
}

func decodeJSONBody(w http.ResponseWriter, r *http.Request, dst any) error {
	r.Body = http.MaxBytesReader(w, r.Body, maxJSONBodyBytes)
	dec := json.NewDecoder(r.Body)
	dec.DisallowUnknownFields()

	if err := dec.Decode(dst); err != nil {
		var syntaxErr *json.SyntaxError
		var typeErr *json.UnmarshalTypeError
		switch {
		case errors.As(err, &syntaxErr):
			http.Error(w, "invalid JSON syntax", http.StatusBadRequest)
		case errors.Is(err, io.EOF):
			http.Error(w, "request body must not be empty", http.StatusBadRequest)
		case errors.As(err, &typeErr):
			http.Error(w, "invalid JSON field type", http.StatusBadRequest)
		case strings.HasPrefix(err.Error(), "json: unknown field"):
			http.Error(w, "unknown JSON field", http.StatusBadRequest)
		case strings.Contains(err.Error(), "http: request body too large"):
			http.Error(w, "request body too large", http.StatusRequestEntityTooLarge)
		default:
			http.Error(w, "invalid JSON", http.StatusBadRequest)
		}
		return err
	}

	if err := dec.Decode(&struct{}{}); !errors.Is(err, io.EOF) {
		http.Error(w, "request body must contain a single JSON object", http.StatusBadRequest)
		return err
	}

	return nil
}

func normalizeServerIDs(ids []string) []string {
	seen := make(map[string]struct{}, len(ids))
	out := make([]string, 0, len(ids))
	for _, id := range ids {
		trimmed := strings.TrimSpace(id)
		if trimmed == "" {
			continue
		}
		if _, ok := seen[trimmed]; ok {
			continue
		}
		seen[trimmed] = struct{}{}
		out = append(out, trimmed)
	}
	return out
}
