package main

import (
	"context"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"strings"
	"time"
)

// Self keep-alive for free-tier hosts.
//
// Render's free plan spins a service down after ~15 idle minutes, which
// drops every party and makes the next room wait out a cold start.
// BitChord's answer in production is an always-free VM where the process
// simply stays up (see deploy/), with "a free uptime monitor pinging
// /healthz every 12 minutes" as the Render alternative. This is that
// monitor, built in: while the process is up it requests its own public
// /healthz through the host's router every 10 minutes, which counts as
// inbound traffic and resets the idle timer — so the first request is
// the only cold one. A scheduled GitHub Actions ping
// (.github/workflows/party_server.yml) covers restarts from outside.
//
// The public base is the first of JAM_SELF_PING_URL, RENDER_EXTERNAL_URL
// (Render sets it automatically), JAM_PUBLIC_ORIGIN. With none set
// (local runs, the Oracle VM behind its own domain can pass
// JAM_PUBLIC_ORIGIN) this is a no-op, and JAM_SELF_PING=off disables it.
func keepAliveBase(getenv func(string) string) string {
	for _, key := range []string{"JAM_SELF_PING_URL", "RENDER_EXTERNAL_URL", "JAM_PUBLIC_ORIGIN"} {
		if v := strings.TrimRight(strings.TrimSpace(getenv(key)), "/"); v != "" {
			return v
		}
	}
	return ""
}

func pingHealth(ctx context.Context, client *http.Client, base string) error {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, base+"/healthz", nil)
	if err != nil {
		return err
	}
	resp, err := client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	_, _ = io.Copy(io.Discard, resp.Body)
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return fmt.Errorf("healthz answered %s", resp.Status)
	}
	return nil
}

func startSelfKeepAlive() {
	if strings.EqualFold(strings.TrimSpace(os.Getenv("JAM_SELF_PING")), "off") {
		return
	}
	base := keepAliveBase(os.Getenv)
	if base == "" {
		return
	}
	go func() {
		log.Printf("self keep-alive: pinging %s/healthz every 10m", base)
		client := &http.Client{Timeout: 30 * time.Second}
		ticker := time.NewTicker(10 * time.Minute)
		defer ticker.Stop()
		for range ticker.C {
			ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
			if err := pingHealth(ctx, client, base); err != nil {
				log.Printf("self keep-alive ping failed: %v", err)
			}
			cancel()
		}
	}()
}
