package party

import (
	"testing"
)

func TestChatReplyEditReactionsAndReceipts(t *testing.T) {
	p, alice := chatParty(t)
	bob, err := p.Join("user-b", "device-b", "Bob", nil)
	if err != nil {
		t.Fatalf("Join failed: %v", err)
	}

	reply := &ChatReply{Id: "older", By: "Bob", Text: "first line"}
	msg, added := p.AddChat(alice, "id-1", "  hello  there ", reply)
	if !added || msg == nil {
		t.Fatal("message with a reply was not stored")
	}
	if msg.Seq != 1 || p.ChatSeq != 1 {
		t.Fatalf("seq = %d, room seq = %d, want 1/1", msg.Seq, p.ChatSeq)
	}
	if msg.ReplyTo == nil || msg.ReplyTo.Id != "older" || msg.ReplyTo.Text != "first line" {
		t.Errorf("reply quote = %+v, want the original id and text", msg.ReplyTo)
	}

	// Only the author may edit, and the seq is untouched.
	if _, ok := p.EditChat(bob, "id-1", "hacked"); ok {
		t.Error("another member edited Alice's message")
	}
	edited, ok := p.EditChat(alice, "id-1", "  hello   again ")
	if !ok || edited.Text != "hello again" {
		t.Fatalf("edit = (%+v, %v), want cleaned text", edited, ok)
	}
	if edited.Seq != 1 || edited.EditedAtMs == 0 {
		t.Errorf("edit changed the sequence/timestamp: %+v", edited)
	}

	// Reactions are per-member toggles, not an ever-growing list.
	reacted, ok := p.ToggleReaction(bob, "id-1", "🔥")
	if !ok || len(reacted.Reactions["🔥"]) != 1 {
		t.Fatalf("reaction not recorded: %+v", reacted.Reactions)
	}
	if _, ok := p.ToggleReaction(alice, "id-1", "🔥"); !ok {
		t.Fatal("Alice could not react to the same line")
	}
	if got := len(p.ChatById("id-1").Reactions["🔥"]); got != 2 {
		t.Errorf("reaction count = %d, want 2", got)
	}
	if _, ok := p.ToggleReaction(bob, "id-1", "🔥"); !ok {
		t.Fatal("Bob could not remove his reaction")
	}
	if got := len(p.ChatById("id-1").Reactions["🔥"]); got != 1 {
		t.Errorf("reaction count after toggle = %d, want 1", got)
	}
	if _, ok := p.ToggleReaction(bob, "id-1", "not-an-emoji"); ok {
		t.Error("an arbitrary string was accepted as a reaction")
	}
	if p.ChatSeq != 1 || len(p.Chat) != 1 {
		t.Errorf("edits/reactions appended chat lines: seq %d, len %d", p.ChatSeq, len(p.Chat))
	}

	// Bob reads the line; Alice sees a double tick. A stale frame cannot
	// move the receipt backwards, and it cannot run past chatSeq.
	if !p.MarkChatRead(bob, 99) {
		t.Fatal("read receipt was not recorded")
	}
	reads := p.ChatReadsWire()
	if reads[bob.MemberId] != 1 {
		t.Errorf("receipt = %d, want clamped to chatSeq 1", reads[bob.MemberId])
	}
	if p.MarkChatRead(bob, 0) {
		t.Error("read receipt moved backwards")
	}
	if reads[alice.MemberId] != 0 {
		t.Errorf("Alice has an unearned receipt: %d", reads[alice.MemberId])
	}
	if got := p.ToWire()["chatReads"].(map[string]int64)[bob.MemberId]; got != 1 {
		t.Errorf("snapshot receipt = %d, want 1", got)
	}
}
