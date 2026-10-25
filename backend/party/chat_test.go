package party

import (
	"fmt"
	"strings"
	"testing"

	"github.com/ifallertzia/ifallmusic/backend/clock"
	"github.com/ifallertzia/ifallmusic/backend/config"
)

func chatParty(t *testing.T) (*Party, *Member) {
	t.Helper()
	p := NewParty("CHAT01")
	m, err := p.Join("user-a", "device-a", "Alice", nil)
	if err != nil {
		t.Fatalf("Join failed: %v", err)
	}
	return p, m
}

func TestAddChatCleansAndStores(t *testing.T) {
	p, m := chatParty(t)
	msg, added := p.AddChat(m, "id-1", "  hello \t   world  ")
	if !added || msg == nil {
		t.Fatalf("AddChat = (%v, %v), want message stored", msg, added)
	}
	if msg.Text != "hello world" {
		t.Errorf("text = %q, want whitespace collapsed", msg.Text)
	}
	if msg.Name != "Alice" || msg.UserId != "user-a" || msg.MemberId != m.MemberId {
		t.Errorf("message carries wrong sender: %+v", msg)
	}
	if p.ChatSeq != 1 || len(p.Chat) != 1 {
		t.Errorf("ChatSeq/len = %d/%d, want 1/1", p.ChatSeq, len(p.Chat))
	}
}

func TestAddChatRejectsEmptyAndTruncatesLong(t *testing.T) {
	p, m := chatParty(t)
	if msg, added := p.AddChat(m, "id-empty", "   \t "); msg != nil || added {
		t.Errorf("empty message stored: %v", msg)
	}
	long := strings.Repeat("é", config.ChatMaxRunes+50)
	msg, added := p.AddChat(m, "id-long", long)
	if !added {
		t.Fatal("long message refused outright, want truncation")
	}
	if got := len([]rune(msg.Text)); got != config.ChatMaxRunes {
		t.Errorf("truncated to %d runes, want %d", got, config.ChatMaxRunes)
	}
}

func TestAddChatDedupesRetryById(t *testing.T) {
	p, m := chatParty(t)
	first, _ := p.AddChat(m, "retry-me", "hello")
	second, added := p.AddChat(m, "retry-me", "hello")
	if added {
		t.Fatal("same id from same member landed twice")
	}
	if second != first {
		t.Errorf("retry should return the stored message")
	}
	if len(p.Chat) != 1 || p.ChatSeq != 1 {
		t.Errorf("ChatSeq/len = %d/%d after retry, want 1/1", p.ChatSeq, len(p.Chat))
	}
	// The same id from a *different* member is not a retry of ours.
	other, err := p.Join("user-b", "device-b", "Bob", nil)
	if err != nil {
		t.Fatalf("Join failed: %v", err)
	}
	if _, added := p.AddChat(other, "retry-me", "mine now"); !added {
		t.Errorf("other member's message swallowed as a retry")
	}
}

func TestChatWindowIsBounded(t *testing.T) {
	p, m := chatParty(t)
	for i := 0; i < config.ChatMaxMessages+10; i++ {
		p.AddChat(m, fmt.Sprintf("id-%d", i), fmt.Sprintf("message %d", i))
	}
	if len(p.Chat) != config.ChatMaxMessages {
		t.Fatalf("chat len = %d, want cap %d", len(p.Chat), config.ChatMaxMessages)
	}
	if p.Chat[0].Text != "message 10" {
		t.Errorf("oldest kept = %q, want the window to have rolled", p.Chat[0].Text)
	}
	if p.ChatSeq != int64(config.ChatMaxMessages+10) {
		t.Errorf("ChatSeq = %d, want every landed message counted", p.ChatSeq)
	}
}

func TestChatDiscardedWhenPartyEmpties(t *testing.T) {
	p, m := chatParty(t)
	p.AddChat(m, "id-1", "secret last words")
	p.Remove(m.MemberId)
	if len(p.Chat) != 0 || p.ChatSeq != 0 {
		t.Errorf("chat survived an empty party: %d messages, seq %d", len(p.Chat), p.ChatSeq)
	}
}

func TestHostHandoverGoesToEarliestMember(t *testing.T) {
	p := NewParty("HOST01")
	host, _ := p.Join("u-host", "d-host", "Host", nil)
	second, _ := p.Join("u-two", "d-two", "Second", nil)
	second.JoinedAtMs = host.JoinedAtMs + 1000
	third, _ := p.Join("u-three", "d-three", "Third", nil)
	third.JoinedAtMs = host.JoinedAtMs + 2000
	p.Remove(host.MemberId)
	if !second.IsHost || third.IsHost {
		t.Errorf("host went to the wrong member (second=%v third=%v)", second.IsHost, third.IsHost)
	}
}

func TestEndedAdvancesOnceNearTheEnd(t *testing.T) {
	p, m := chatParty(t)
	dur := int64(180000)
	a := &Track{VideoId: "aaaaaaaaaaa", Title: "A", DurationMs: &dur}
	b := &Track{VideoId: "bbbbbbbbbbb", Title: "B", DurationMs: &dur}
	p.Playback.SetQueue(&m.MemberId, []*Track{a, b}, 0)
	p.Playback.SetTrack(&m.MemberId, a, 0, true, intPtr(0), &m.DisplayName)

	// Mid-song: the server does not believe the song is over.
	if p.Playback.Ended(&m.MemberId, a.VideoId, &m.DisplayName) {
		t.Fatal("Ended honoured in the middle of the track")
	}
	// Near the end, the first report moves the room on…
	p.Playback.Seek(&m.MemberId, dur-5000)
	if !p.Playback.Ended(&m.MemberId, a.VideoId, &m.DisplayName) {
		t.Fatal("Ended ignored near the end of the track")
	}
	if p.Playback.Track.VideoId != b.VideoId {
		t.Fatalf("track = %s, want %s", p.Playback.Track.VideoId, b.VideoId)
	}
	// …and the second device reporting the same finished song does not
	// skip the new one.
	if p.Playback.Ended(&m.MemberId, a.VideoId, &m.DisplayName) {
		t.Fatal("stale Ended advanced the room again")
	}
	if p.Playback.Track.VideoId != b.VideoId {
		t.Fatal("stale Ended changed the track")
	}
}

func TestEndedAtQueueEndStopsAtTheEnd(t *testing.T) {
	p, m := chatParty(t)
	dur := int64(120000)
	a := &Track{VideoId: "aaaaaaaaaaa", Title: "Only", DurationMs: &dur}
	p.Playback.SetQueue(&m.MemberId, []*Track{a}, 0)
	p.Playback.SetTrack(&m.MemberId, a, 0, true, intPtr(0), &m.DisplayName)
	p.Playback.Seek(&m.MemberId, dur-1000)
	if !p.Playback.Ended(&m.MemberId, a.VideoId, &m.DisplayName) {
		t.Fatal("Ended at the end of the queue changed nothing")
	}
	if p.Playback.IsPlaying {
		t.Error("room still 'playing' past the last track")
	}
	if got := p.Playback.PositionAt(clock.NowMs()); got != dur {
		t.Errorf("position = %d, want stopped at the end (%d)", got, dur)
	}
}

func intPtr(v int) *int { return &v }
