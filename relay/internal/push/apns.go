package push

// ── APNs sender ───────────────────────────────────────────────────────────────
//
// To activate:
//   1. Download your .p8 key from Apple Developer → Certificates, IDs & Profiles
//      → Keys → create a key with "Apple Push Notifications service (APNs)" enabled.
//   2. Note the Key ID shown on the download page.
//   3. Find your Team ID in the top-right of the Apple Developer portal.
//   4. Set in config.json:
//        "apns": {
//          "stub": false,
//          "key_file": "/etc/orbital-relay/AuthKey_XXXXXXXXXX.p8",
//          "key_id":   "XXXXXXXXXX",
//          "team_id":  "YYYYYYYYYY",
//          "bundle_id": "com.your.app",
//          "sandbox": true
//        }
// ─────────────────────────────────────────────────────────────────────────────

import (
	"bytes"
	"crypto/ecdsa"
	"crypto/rand"
	"crypto/sha256"
	"crypto/x509"
	"encoding/base64"
	"encoding/json"
	"encoding/pem"
	"fmt"
	"net/http"
	"os"
	"sync"
	"time"
)

type APNsSender struct {
	key      *ecdsa.PrivateKey
	keyID    string
	teamID   string
	bundleID string
	baseURL  string
	client   *http.Client

	mu        sync.Mutex
	token     string
	tokenTime time.Time
}

func NewAPNsSender(keyFile, keyID, teamID, bundleID string, sandbox bool) (*APNsSender, error) {
	data, err := os.ReadFile(keyFile)
	if err != nil {
		return nil, fmt.Errorf("read apns key file: %w", err)
	}

	block, _ := pem.Decode(data)
	if block == nil {
		return nil, fmt.Errorf("failed to decode PEM from APNs key file")
	}

	raw, err := x509.ParsePKCS8PrivateKey(block.Bytes)
	if err != nil {
		return nil, fmt.Errorf("parse apns key: %w", err)
	}

	ecKey, ok := raw.(*ecdsa.PrivateKey)
	if !ok {
		return nil, fmt.Errorf("APNs key is not an EC private key")
	}

	baseURL := "https://api.push.apple.com"
	if sandbox {
		baseURL = "https://api.sandbox.push.apple.com"
	}

	return &APNsSender{
		key:      ecKey,
		keyID:    keyID,
		teamID:   teamID,
		bundleID: bundleID,
		baseURL:  baseURL,
		client:   &http.Client{Timeout: 10 * time.Second},
	}, nil
}

func (s *APNsSender) Send(
	deviceToken, title, body string,
	data map[string]string,
) error {
	token, err := s.bearerToken()
	if err != nil {
		return fmt.Errorf("apns bearer token: %w", err)
	}

	payload := map[string]any{
		"aps": map[string]any{
			"alert": map[string]string{
				"title": title,
				"body":  body,
			},
			"sound": "default",
		},
	}
	for k, v := range data {
		payload[k] = v
	}

	encodedPayload, _ := json.Marshal(payload)

	url := fmt.Sprintf("%s/3/device/%s", s.baseURL, deviceToken)
	req, err := http.NewRequest(
		http.MethodPost,
		url,
		bytes.NewReader(encodedPayload),
	)
	if err != nil {
		return err
	}
	req.Header.Set("Authorization", "Bearer "+token)
	req.Header.Set("apns-topic", s.bundleID)
	req.Header.Set("apns-push-type", "alert")
	req.Header.Set("Content-Type", "application/json")

	resp, err := s.client.Do(req)
	if err != nil {
		return fmt.Errorf("apns http: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		var result map[string]string
		json.NewDecoder(resp.Body).Decode(&result)
		return fmt.Errorf("apns HTTP %d: %v", resp.StatusCode, result)
	}
	return nil
}

func (s *APNsSender) bearerToken() (string, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	if s.token == "" || time.Since(s.tokenTime) > 55*time.Minute {
		t, err := s.makeJWT()
		if err != nil {
			return "", err
		}
		s.token = t
		s.tokenTime = time.Now()
	}
	return s.token, nil
}

func (s *APNsSender) makeJWT() (string, error) {
	header, _ := json.Marshal(map[string]string{
		"alg": "ES256",
		"kid": s.keyID,
	})
	payload, _ := json.Marshal(map[string]any{
		"iss": s.teamID,
		"iat": time.Now().Unix(),
	})

	signingInput := b64url(header) + "." + b64url(payload)
	hash := sha256.Sum256([]byte(signingInput))

	r, sig, err := ecdsa.Sign(rand.Reader, s.key, hash[:])
	if err != nil {
		return "", fmt.Errorf("sign jwt: %w", err)
	}

	sigBytes := make([]byte, 64)
	rb, sb := r.Bytes(), sig.Bytes()
	copy(sigBytes[32-len(rb):32], rb)
	copy(sigBytes[64-len(sb):64], sb)

	return signingInput + "." + base64.RawURLEncoding.EncodeToString(sigBytes), nil
}

func b64url(data []byte) string {
	return base64.RawURLEncoding.EncodeToString(data)
}
