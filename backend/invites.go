package main

import (
	"crypto/rand"
	"encoding/hex"
	"net/http"
	"strings"
	"sync"
	"time"

	"github.com/ifallertzia/ifallmusic/backend/clock"
	"github.com/ifallertzia/ifallmusic/backend/codes"
	"github.com/ifallertzia/ifallmusic/backend/config"
	"github.com/ifallertzia/ifallmusic/backend/presence"
)

// Friend invites: "Rahul wants to listen with you", the way games do it,
// without accounts, a database or a push service.
//
// There is no user directory. Two devices only ever learn each other's
// install id (a random UUID the app generates once) by having been in a
// party together — the members frame already carries it — and each app
// keeps its own friends list on-device. What this file adds is the meeting
// point:
//
//   - every app heartbeats POST /api/invites/heartbeat with its own id and
//     the ids of its friends; the answer carries any invites waiting for
//     it, any answers to invites it sent, and which friends are online.
//   - POST /api/invites/send files an invite, but only from a device that
//     is genuinely a member of the party it is inviting to (the server
//     checks the party, and takes the sender's name from the party too,
//     so an invite cannot lie about who it is from or point at a room the
//     sender is not in).
//   - POST /api/invites/respond files the answer for the sender's next
//     heartbeat.
//
// Everything lives in memory and expires in minutes, like the parties
// themselves. An invite to a phone whose app is fully closed cannot wake
// it — that needs a push service — so the app says so and offers the share
// link instead; an invite to a running app lands within one heartbeat.

type invite struct {
	Id          string `json:"id"`
	FromUserId  string `json:"fromUserId"`
	FromName    string `json:"fromName"`
	ToUserId    string `json:"-"`
	Code        string `json:"code"`
	AtMs        int64  `json:"atMs"`
	ExpiresAtMs int64  `json:"expiresAtMs"`
}

type inviteResponse struct {
	InviteId string `json:"inviteId"`
	ByUserId string `json:"byUserId"`
	ByName   string `json:"byName"`
	Code     string `json:"code"`
	Accepted bool   `json:"accepted"`
	AtMs     int64  `json:"atMs"`
}

type invitePresence struct {
	name string
	atMs int64
}

type inviteStore struct {
	mu        sync.Mutex
	online    map[string]invitePresence
	pending   map[string][]*invite
	responses map[string][]*inviteResponse
	total     int
}

func newInviteStore() *inviteStore {
	return &inviteStore{
		online:    make(map[string]invitePresence),
		pending:   make(map[string][]*invite),
		responses: make(map[string][]*inviteResponse),
	}
}

// purgeLocked drops expired invites and answers. Ran on the heartbeat path
// and from the sweeper; both are cheap at this feature's scale.
func (s *inviteStore) purgeLocked(now int64) {
	for to, list := range s.pending {
		kept := list[:0]
		for _, inv := range list {
			if now <= inv.ExpiresAtMs {
				kept = append(kept, inv)
			} else {
				s.total--
			}
		}
		if len(kept) == 0 {
			delete(s.pending, to)
		} else {
			s.pending[to] = kept
		}
	}
	for to, list := range s.responses {
		kept := list[:0]
		for _, res := range list {
			if now-res.AtMs <= config.InviteTtlMs {
				kept = append(kept, res)
			}
		}
		if len(kept) == 0 {
			delete(s.responses, to)
		} else {
			s.responses[to] = kept
		}
	}
	for id, seen := range s.online {
		if now-seen.atMs > config.InvitePresenceTtlMs*4 {
			delete(s.online, id)
		}
	}
}

func (s *inviteStore) sweep(now int64) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.purgeLocked(now)
}

func (s *inviteStore) isOnline(userId string, now int64) bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	seen, ok := s.online[userId]
	return ok && now-seen.atMs <= config.InvitePresenceTtlMs
}

// heartbeat registers this install as reachable and collects what is
// waiting for it. Answers are consumed (they are a toast, not a mailbox);
// invites are not, so a heartbeat that raced the UI never loses one.
func (s *inviteStore) heartbeat(userId, name string, friendIds []string, now int64) (invites []*invite, answers []*inviteResponse, onlineFriends []string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.purgeLocked(now)
	s.online[userId] = invitePresence{name: name, atMs: now}
	invites = append(invites, s.pending[userId]...)
	answers = append(answers, s.responses[userId]...)
	delete(s.responses, userId)
	for _, friendId := range friendIds {
		if friendId == userId {
			continue
		}
		if seen, ok := s.online[friendId]; ok && now-seen.atMs <= config.InvitePresenceTtlMs {
			onlineFriends = append(onlineFriends, friendId)
		}
	}
	return invites, answers, onlineFriends
}

// send files an invite. A repeat from the same sender to the same room
// just refreshes its expiry — double-tapping "invite" must not stack two.
func (s *inviteStore) send(inv *invite, now int64) bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.purgeLocked(now)
	for _, existing := range s.pending[inv.ToUserId] {
		if existing.FromUserId == inv.FromUserId && existing.Code == inv.Code {
			existing.AtMs = now
			existing.ExpiresAtMs = inv.ExpiresAtMs
			return true
		}
	}
	if len(s.pending[inv.ToUserId]) >= config.InviteMaxPending {
		return false
	}
	if config.InviteMaxEntries > 0 && s.total >= config.InviteMaxEntries {
		return false
	}
	s.pending[inv.ToUserId] = append(s.pending[inv.ToUserId], inv)
	s.total++
	return true
}

func (s *inviteStore) respond(userId, inviteId string, accepted bool, now int64) bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.purgeLocked(now)
	list := s.pending[userId]
	for i, inv := range list {
		if inv.Id != inviteId {
			continue
		}
		s.pending[userId] = append(list[:i], list[i+1:]...)
		if len(s.pending[userId]) == 0 {
			delete(s.pending, userId)
		}
		s.total--
		name := ""
		if seen, ok := s.online[userId]; ok {
			name = seen.name
		}
		answers := append(s.responses[inv.FromUserId], &inviteResponse{
			InviteId: inv.Id,
			ByUserId: userId,
			ByName:   name,
			Code:     inv.Code,
			Accepted: accepted,
			AtMs:     now,
		})
		if len(answers) > 10 {
			answers = answers[len(answers)-10:]
		}
		s.responses[inv.FromUserId] = answers
		return true
	}
	return false
}

var (
	invites       = newInviteStore()
	inviteLimiter = newIPRateLimiter(time.Minute, 60, config.RateLimitMaxEntries)
)

// inviteUserId normalises an install id to the lower-case UUID form the
// presence parser accepts, so the same phone keys the same inbox however
// the id was cased on the way in.
func inviteUserId(raw string) (string, bool) {
	id := strings.ToLower(strings.TrimSpace(raw))
	if _, ok := presence.ParseID(id); !ok {
		return "", false
	}
	return id, true
}

func inviteName(raw string) string {
	name := strings.Join(strings.Fields(raw), " ")
	runes := []rune(name)
	if len(runes) > 40 {
		name = string(runes[:40])
	}
	if name == "" {
		name = "Listener"
	}
	return name
}

// partyMemberName reports the display name userId is known by inside the
// party, and whether they are in it at all.
func partyMemberName(code, userId string) (string, bool) {
	p := store.Find(code)
	if p == nil {
		return "", false
	}
	p.Lock()
	defer p.Unlock()
	for _, m := range p.Members {
		if m.UserId == userId {
			return m.DisplayName, true
		}
	}
	return "", false
}

func inviteRandomId() string {
	b := make([]byte, 12)
	_, _ = rand.Read(b)
	return hex.EncodeToString(b)
}

func rejectBrowserInvite(w http.ResponseWriter, r *http.Request) bool {
	// Like presence: only the apps call these, and they send no Origin.
	if r.Header.Get("Origin") != "" {
		jsonError(w, http.StatusForbidden, "origin_not_allowed", "Invites are only accepted from the apps.")
		return true
	}
	if !inviteLimiter.Allow(clientIP(r)) {
		jsonError(w, http.StatusTooManyRequests, "rate_limited", "Too many invite requests from this address.")
		return true
	}
	return false
}

// POST /api/invites/heartbeat {userId, displayName, friendIds[]}
// → {invites, responses, onlineFriendIds, intervalSec, serverMs}
func handleInviteHeartbeat(w http.ResponseWriter, r *http.Request) {
	if rejectBrowserInvite(w, r) {
		return
	}
	var body struct {
		UserId      string   `json:"userId"`
		DisplayName string   `json:"displayName"`
		FriendIds   []string `json:"friendIds"`
	}
	if !decodeJSONBody(w, r, &body) {
		return
	}
	userId, ok := inviteUserId(body.UserId)
	if !ok {
		jsonError(w, http.StatusUnprocessableEntity, "invalid_id", "userId must be a UUID.")
		return
	}
	friendIds := make([]string, 0, len(body.FriendIds))
	for _, raw := range body.FriendIds {
		if len(friendIds) >= 50 {
			break
		}
		if id, valid := inviteUserId(raw); valid {
			friendIds = append(friendIds, id)
		}
	}
	now := clock.NowMs()
	pending, answers, online := invites.heartbeat(userId, inviteName(body.DisplayName), friendIds, now)
	if pending == nil {
		pending = []*invite{}
	}
	if answers == nil {
		answers = []*inviteResponse{}
	}
	if online == nil {
		online = []string{}
	}
	jsonResponse(w, http.StatusOK, map[string]interface{}{
		"invites":         pending,
		"responses":       answers,
		"onlineFriendIds": online,
		"intervalSec":     config.InviteIntervalSec,
		"serverMs":        now,
	})
}

// POST /api/invites/send {fromUserId, toUserId, code}
// → {ok, online, expiresAtMs}
func handleInviteSend(w http.ResponseWriter, r *http.Request) {
	if rejectBrowserInvite(w, r) {
		return
	}
	var body struct {
		FromUserId string `json:"fromUserId"`
		ToUserId   string `json:"toUserId"`
		Code       string `json:"code"`
	}
	if !decodeJSONBody(w, r, &body) {
		return
	}
	fromId, okFrom := inviteUserId(body.FromUserId)
	toId, okTo := inviteUserId(body.ToUserId)
	if !okFrom || !okTo {
		jsonError(w, http.StatusUnprocessableEntity, "invalid_id", "fromUserId and toUserId must be UUIDs.")
		return
	}
	if fromId == toId {
		jsonError(w, http.StatusUnprocessableEntity, "self_invite", "You cannot invite yourself.")
		return
	}
	code := codes.Normalise(body.Code)
	if !codes.IsValid(code) {
		jsonError(w, http.StatusUnprocessableEntity, "invalid_code", "That is not a party code.")
		return
	}
	if store.Find(code) == nil {
		jsonError(w, http.StatusNotFound, "no_such_party", "That room has ended.")
		return
	}
	fromName, inRoom := partyMemberName(code, fromId)
	if !inRoom {
		jsonError(w, http.StatusForbidden, "not_in_room", "Join the room before inviting anyone to it.")
		return
	}
	if _, already := partyMemberName(code, toId); already {
		jsonError(w, http.StatusConflict, "already_in_room", "They are already in this room.")
		return
	}
	now := clock.NowMs()
	inv := &invite{
		Id:          inviteRandomId(),
		FromUserId:  fromId,
		FromName:    inviteName(fromName),
		ToUserId:    toId,
		Code:        code,
		AtMs:        now,
		ExpiresAtMs: now + config.InviteTtlMs,
	}
	if !invites.send(inv, now) {
		jsonError(w, http.StatusTooManyRequests, "inbox_full", "Their invite inbox is full right now.")
		return
	}
	jsonResponse(w, http.StatusOK, map[string]interface{}{
		"ok":          true,
		"online":      invites.isOnline(toId, now),
		"expiresAtMs": inv.ExpiresAtMs,
		"serverMs":    now,
	})
}

// POST /api/invites/respond {userId, inviteId, accept} → {ok}
func handleInviteRespond(w http.ResponseWriter, r *http.Request) {
	if rejectBrowserInvite(w, r) {
		return
	}
	var body struct {
		UserId   string `json:"userId"`
		InviteId string `json:"inviteId"`
		Accept   *bool  `json:"accept"`
	}
	if !decodeJSONBody(w, r, &body) {
		return
	}
	userId, ok := inviteUserId(body.UserId)
	if !ok || body.Accept == nil || strings.TrimSpace(body.InviteId) == "" {
		jsonError(w, http.StatusUnprocessableEntity, "invalid_response", "userId, inviteId and accept are required.")
		return
	}
	if !invites.respond(userId, strings.TrimSpace(body.InviteId), *body.Accept, clock.NowMs()) {
		jsonError(w, http.StatusNotFound, "invite_expired", "That invite has already expired.")
		return
	}
	jsonResponse(w, http.StatusOK, map[string]bool{"ok": true})
}
