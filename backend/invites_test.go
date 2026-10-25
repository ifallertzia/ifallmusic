package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/ifallertzia/ifallmusic/backend/clock"
	"github.com/ifallertzia/ifallmusic/backend/config"
)

const (
	inviteUserAlice = "11111111-1111-4111-8111-111111111119"
	inviteUserBob   = "22222222-2222-4222-8222-222222222229"
	inviteUserCarol = "33333333-3333-4333-8333-333333333339"
)

func setupInviteServer() *httptest.Server {
	mux := http.NewServeMux()
	mux.HandleFunc("POST /api/parties", handleCreateParty)
	mux.HandleFunc("POST /api/invites/heartbeat", handleInviteHeartbeat)
	mux.HandleFunc("POST /api/invites/send", handleInviteSend)
	mux.HandleFunc("POST /api/invites/respond", handleInviteRespond)
	return httptest.NewServer(corsMiddleware(mux))
}

func postJSON(t *testing.T, url string, body map[string]interface{}) (int, map[string]interface{}) {
	t.Helper()
	b, _ := json.Marshal(body)
	res, err := http.Post(url, "application/json", bytes.NewReader(b))
	if err != nil {
		t.Fatalf("POST %s: %v", url, err)
	}
	defer res.Body.Close()
	var out map[string]interface{}
	_ = json.NewDecoder(res.Body).Decode(&out)
	return res.StatusCode, out
}

func TestInviteFlowEndToEnd(t *testing.T) {
	old := invites
	invites = newInviteStore()
	defer func() { invites = old }()
	// The suite shares the package-level create limiter (2/minute/IP) and
	// the older tests spend exactly that budget between them; run this
	// flow on a fresh limiter and hand back a fresh one so test order
	// never turns a party creation into a 429 here or there.
	createLimiter = newIPRateLimiter(time.Minute, 100, 1000)
	defer func() {
		createLimiter = newIPRateLimiter(time.Minute, config.CreateRatePerMinute, config.RateLimitMaxEntries)
	}()

	ts := setupInviteServer()
	defer ts.Close()

	// Bob's app is running: it heartbeats and learns nobody wants it yet.
	status, beat := postJSON(t, ts.URL+"/api/invites/heartbeat", map[string]interface{}{
		"userId": inviteUserBob, "displayName": "Bob",
		"friendIds": []string{inviteUserAlice},
	})
	if status != http.StatusOK {
		t.Fatalf("heartbeat status = %d (%v)", status, beat)
	}
	if got := beat["invites"].([]interface{}); len(got) != 0 {
		t.Fatalf("fresh inbox carried %d invites", len(got))
	}
	if got := beat["onlineFriendIds"].([]interface{}); len(got) != 0 {
		t.Fatalf("Alice reported online before she ever heartbeat: %v", got)
	}

	// Alice starts a room (her install id is her userId in the party too).
	status, created := postJSON(t, ts.URL+"/api/parties", map[string]interface{}{
		"userId": inviteUserAlice, "deviceId": "device-alice", "displayName": "Alice",
	})
	if status != http.StatusCreated {
		t.Fatalf("create status = %d (%v)", status, created)
	}
	code, _ := created["code"].(string)
	if code == "" {
		t.Fatal("create returned no code")
	}

	// Carol is not in the room: her invite is refused.
	status, _ = postJSON(t, ts.URL+"/api/invites/send", map[string]interface{}{
		"fromUserId": inviteUserCarol, "toUserId": inviteUserBob, "code": code,
	})
	if status != http.StatusForbidden {
		t.Fatalf("non-member invite status = %d, want 403", status)
	}

	// Alice invites Bob, twice (double tap) — still one invite.
	for i := 0; i < 2; i++ {
		status, sent := postJSON(t, ts.URL+"/api/invites/send", map[string]interface{}{
			"fromUserId": inviteUserAlice, "toUserId": inviteUserBob, "code": code,
		})
		if status != http.StatusOK {
			t.Fatalf("send %d status = %d (%v)", i, status, sent)
		}
		if sent["online"] != true {
			t.Errorf("Bob heartbeat recently but was not reported online")
		}
	}

	// Bob's next heartbeat carries exactly one invite, from Alice, and by
	// now Alice counts as an online friend (she is in her app sending).
	status, beat = postJSON(t, ts.URL+"/api/invites/heartbeat", map[string]interface{}{
		"userId": inviteUserBob, "displayName": "Bob",
		"friendIds": []string{inviteUserAlice},
	})
	if status != http.StatusOK {
		t.Fatalf("heartbeat 2 status = %d", status)
	}
	pending := beat["invites"].([]interface{})
	if len(pending) != 1 {
		t.Fatalf("pending = %d, want 1 after a double-tapped invite", len(pending))
	}
	inv := pending[0].(map[string]interface{})
	if inv["code"] != code || inv["fromName"] != "Alice" || inv["fromUserId"] != inviteUserAlice {
		t.Fatalf("invite = %v, want Alice's room %s", inv, code)
	}
	inviteId, _ := inv["id"].(string)

	// Alice heartbeats so friend-online state exists both ways.
	postJSON(t, ts.URL+"/api/invites/heartbeat", map[string]interface{}{
		"userId": inviteUserAlice, "displayName": "Alice",
		"friendIds": []string{inviteUserBob},
	})

	// Bob accepts. Alice's next heartbeat carries the answer, once.
	status, _ = postJSON(t, ts.URL+"/api/invites/respond", map[string]interface{}{
		"userId": inviteUserBob, "inviteId": inviteId, "accept": true,
	})
	if status != http.StatusOK {
		t.Fatalf("respond status = %d", status)
	}
	_, beatAlice := postJSON(t, ts.URL+"/api/invites/heartbeat", map[string]interface{}{
		"userId": inviteUserAlice, "displayName": "Alice",
		"friendIds": []string{inviteUserBob},
	})
	answers := beatAlice["responses"].([]interface{})
	if len(answers) != 1 {
		t.Fatalf("answers = %d, want 1", len(answers))
	}
	ans := answers[0].(map[string]interface{})
	if ans["accepted"] != true || ans["byUserId"] != inviteUserBob || ans["code"] != code {
		t.Errorf("answer = %v, want Bob accepting %s", ans, code)
	}
	if got := beatAlice["onlineFriendIds"].([]interface{}); len(got) != 1 || got[0] != inviteUserBob {
		t.Errorf("onlineFriendIds = %v, want [Bob]", got)
	}
	_, beatAlice = postJSON(t, ts.URL+"/api/invites/heartbeat", map[string]interface{}{
		"userId": inviteUserAlice, "displayName": "Alice",
		"friendIds": []string{},
	})
	if got := beatAlice["responses"].([]interface{}); len(got) != 0 {
		t.Errorf("answer delivered twice: %v", got)
	}

	// The answered invite has left Bob's inbox, and a second response 404s.
	_, beat = postJSON(t, ts.URL+"/api/invites/heartbeat", map[string]interface{}{
		"userId": inviteUserBob, "displayName": "Bob", "friendIds": []string{},
	})
	if got := beat["invites"].([]interface{}); len(got) != 0 {
		t.Errorf("answered invite still pending: %v", got)
	}
	status, _ = postJSON(t, ts.URL+"/api/invites/respond", map[string]interface{}{
		"userId": inviteUserBob, "inviteId": inviteId, "accept": false,
	})
	if status != http.StatusNotFound {
		t.Errorf("double respond status = %d, want 404", status)
	}
}

func TestInviteSendValidatesInputs(t *testing.T) {
	ts := setupInviteServer()
	defer ts.Close()

	status, _ := postJSON(t, ts.URL+"/api/invites/send", map[string]interface{}{
		"fromUserId": "not-a-uuid", "toUserId": inviteUserBob, "code": "ABC123",
	})
	if status != http.StatusUnprocessableEntity {
		t.Errorf("bad id status = %d, want 422", status)
	}

	status, _ = postJSON(t, ts.URL+"/api/invites/send", map[string]interface{}{
		"fromUserId": inviteUserAlice, "toUserId": inviteUserBob, "code": "nope!",
	})
	if status != http.StatusUnprocessableEntity {
		t.Errorf("bad code status = %d, want 422", status)
	}

	// A well-formed code for a room that does not exist is a clean 404.
	status, _ = postJSON(t, ts.URL+"/api/invites/send", map[string]interface{}{
		"fromUserId": inviteUserAlice, "toUserId": inviteUserBob, "code": "ZZZZ99",
	})
	if status != http.StatusNotFound {
		t.Errorf("missing room status = %d, want 404", status)
	}
}

func TestInviteStoreExpiresAndCaps(t *testing.T) {
	s := newInviteStore()
	now := clock.NowMs()
	mk := func(code string, at int64) *invite {
		return &invite{
			Id: inviteRandomId(), FromUserId: inviteUserAlice, FromName: "Alice",
			ToUserId: inviteUserBob, Code: code, AtMs: at,
			ExpiresAtMs: at + config.InviteTtlMs,
		}
	}
	for i := 0; i < config.InviteMaxPending; i++ {
		if !s.send(mk(fmt.Sprintf("ROOM%d%d", i, i), now), now) {
			t.Fatalf("invite %d refused under the cap", i)
		}
	}
	if s.send(mk("ONETOO", now), now) {
		t.Error("invite past the per-inbox cap was filed")
	}
	later := now + config.InviteTtlMs + 1
	pending, _, _ := s.heartbeat(inviteUserBob, "Bob", nil, later)
	if len(pending) != 0 {
		t.Errorf("expired invites still delivered: %d", len(pending))
	}
}
