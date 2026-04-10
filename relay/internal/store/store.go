package store

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"sync"
)

type Device struct {
	Token    string `json:"token"`
	Platform string `json:"platform"` // "ios" or "android"
}

type Store struct {
	mu   sync.RWMutex
	data map[string][]Device
	path string
}

func New(path string) (*Store, error) {
	s := &Store{
		data: make(map[string][]Device),
		path: path,
	}
	if err := s.load(); err != nil && !os.IsNotExist(err) {
		return nil, fmt.Errorf("load store: %w", err)
	}
	return s, nil
}

// Register associates a device with one or more server IDs under the given
// namespace. In single-tenant mode namespace is ""; in multi-tenant mode it is
// a hash derived from the caller's auth token, keeping each user's data
// isolated without requiring separate storage files.
func (s *Store) Register(namespace string, serverIDs []string, device Device) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	for _, sid := range serverIDs {
		key := storeKey(namespace, sid)
		devices := s.data[key]
		replaced := false
		for i, d := range devices {
			if d.Token == device.Token {
				devices[i] = device
				replaced = true
				break
			}
		}
		if !replaced {
			devices = append(devices, device)
		}
		s.data[key] = devices
	}

	return s.save()
}

// DevicesFor returns all devices registered for serverID under the given
// namespace. See Register for namespace semantics.
func (s *Store) DevicesFor(namespace, serverID string) []Device {
	s.mu.RLock()
	defer s.mu.RUnlock()

	src := s.data[storeKey(namespace, serverID)]
	out := make([]Device, len(src))
	copy(out, src)
	return out
}

// storeKey builds the map key used internally. When namespace is empty
// (single-tenant) the key is just the server ID so existing devices.json
// files remain fully compatible. In multi-tenant mode the namespace prefix
// ensures each user's server IDs are completely isolated.
func storeKey(namespace, serverID string) string {
	if namespace == "" {
		return serverID
	}
	return namespace + ":" + serverID
}

func (s *Store) load() error {
	f, err := os.Open(s.path)
	if err != nil {
		return err
	}
	defer f.Close()
	if err := json.NewDecoder(f).Decode(&s.data); err != nil {
		if errors.Is(err, io.EOF) {
			return nil
		}
		return err
	}
	return nil
}

func (s *Store) save() error {
	tmp := s.path + ".tmp"
	f, err := os.Create(tmp)
	if err != nil {
		return fmt.Errorf("create tmp store: %w", err)
	}
	enc := json.NewEncoder(f)
	enc.SetIndent("", "  ")
	if err := enc.Encode(s.data); err != nil {
		f.Close()
		_ = os.Remove(tmp)
		return fmt.Errorf("encode store: %w", err)
	}

	if err := f.Sync(); err != nil {
		f.Close()
		_ = os.Remove(tmp)
		return fmt.Errorf("sync tmp store: %w", err)
	}

	if err := f.Close(); err != nil {
		_ = os.Remove(tmp)
		return fmt.Errorf("close tmp store: %w", err)
	}

	return os.Rename(tmp, s.path)
}
