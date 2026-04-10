package push

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"os"

	"golang.org/x/oauth2/google"
)

type FCMSender struct {
	projectID string
	client    *http.Client
}

func NewFCMSender(serviceAccountFile, projectID string) (*FCMSender, error) {
	data, err := os.ReadFile(serviceAccountFile)
	if err != nil {
		return nil, fmt.Errorf("read fcm service account: %w", err)
	}

	conf, err := google.JWTConfigFromJSON(data,
		"https://www.googleapis.com/auth/firebase.messaging")
	if err != nil {
		return nil, fmt.Errorf("parse fcm credentials: %w", err)
	}

	return &FCMSender{
		projectID: projectID,
		client:    conf.Client(context.Background()),
	}, nil
}

func (s *FCMSender) Send(
	deviceToken, title, body string,
	data map[string]string,
) error {
	payloadData := map[string]string{
		"title": title,
		"body":  body,
	}
	for k, v := range data {
		payloadData[k] = v
	}

	// Send as a data-only message with an APNs alert so iOS shows exactly
	// one notification — no notification field means Firebase won't
	// auto-display a second one on top of the APNs-delivered one.
	payload, _ := json.Marshal(map[string]any{
		"message": map[string]any{
			"token": deviceToken,
			// Data payload — available in both foreground and background handlers.
			"data": payloadData,
			// APNs config — tells iOS to show a notification with sound.
			// This is the single notification the user sees.
			"apns": map[string]any{
				"payload": map[string]any{
					"aps": map[string]any{
						"alert": map[string]string{
							"title": title,
							"body":  body,
						},
						"sound": "default",
					},
				},
			},
		},
	})

	url := fmt.Sprintf(
		"https://fcm.googleapis.com/v1/projects/%s/messages:send",
		s.projectID,
	)

	resp, err := s.client.Post(url, "application/json", bytes.NewReader(payload))
	if err != nil {
		return fmt.Errorf("fcm http: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode >= 300 {
		var result map[string]any
		json.NewDecoder(resp.Body).Decode(&result)
		return fmt.Errorf("fcm HTTP %d: %v", resp.StatusCode, result)
	}
	return nil
}

var _ Sender = (*FCMSender)(nil)
