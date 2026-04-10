package push

import (
	"fmt"
	"log"

	"orbital-relay/internal/config"
)

type Sender interface {
	Send(deviceToken, title, body string, data map[string]string) error
}

type Dispatcher struct {
	fcm Sender
}

func NewDispatcher(cfg *config.Config) (*Dispatcher, error) {
	var fcmSender Sender
	var err error

	if cfg.FCM.Stub {
		fcmSender = &StubSender{platform: "fcm"}
		log.Println("push: FCM running in STUB mode — notifications will be logged only")
	} else {
		fcmSender, err = NewFCMSender(cfg.FCM.ServiceAccountFile, cfg.FCM.ProjectID)
		if err != nil {
			return nil, fmt.Errorf("init fcm: %w", err)
		}
		log.Println("push: FCM sender ready")
	}

	return &Dispatcher{fcm: fcmSender}, nil
}

// Send routes all platforms through FCM — Firebase handles APNs delivery for iOS.
func (d *Dispatcher) Send(platform, deviceToken, title, body string, data map[string]string) error {
	return d.fcm.Send(deviceToken, title, body, data)
}

type StubSender struct {
	platform string
}

func (s *StubSender) Send(deviceToken, title, body string, data map[string]string) error {
	preview := deviceToken
	if len(preview) > 12 {
		preview = preview[:12] + "..."
	}
	log.Printf("[STUB %s] would send → token=%s title=%q body=%q data=%v",
		s.platform, preview, title, body, data)
	return nil
}
