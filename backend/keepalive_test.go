package main

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestKeepAliveBasePriority(t *testing.T) {
	env := map[string]string{
		"JAM_SELF_PING_URL":   "https://self.example/",
		"RENDER_EXTERNAL_URL": "https://render.example",
		"JAM_PUBLIC_ORIGIN":   "https://origin.example",
	}
	get := func(k string) string { return env[k] }

	if got := keepAliveBase(get); got != "https://self.example" {
		t.Fatalf("self ping url should win, got %q", got)
	}
	delete(env, "JAM_SELF_PING_URL")
	if got := keepAliveBase(get); got != "https://render.example" {
		t.Fatalf("render external url should be next, got %q", got)
	}
	delete(env, "RENDER_EXTERNAL_URL")
	if got := keepAliveBase(get); got != "https://origin.example" {
		t.Fatalf("public origin is the fallback, got %q", got)
	}
	delete(env, "JAM_PUBLIC_ORIGIN")
	if got := keepAliveBase(get); got != "" {
		t.Fatalf("no env means no keep-alive, got %q", got)
	}
}

func TestPingHealth(t *testing.T) {
	hits := 0
	ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		hits++
		if r.URL.Path != "/healthz" {
			w.WriteHeader(http.StatusNotFound)
			return
		}
		_, _ = w.Write([]byte(`{"ok":true}`))
	}))
	defer ts.Close()

	if err := pingHealth(context.Background(), ts.Client(), ts.URL); err != nil {
		t.Fatalf("pinging a healthy server: %v", err)
	}
	if hits != 1 {
		t.Fatalf("expected exactly one /healthz hit, got %d", hits)
	}
	if err := pingHealth(context.Background(), ts.Client(), ts.URL+"/nope"); err == nil {
		t.Fatal("a 404 healthz must be reported as an error")
	}
}
