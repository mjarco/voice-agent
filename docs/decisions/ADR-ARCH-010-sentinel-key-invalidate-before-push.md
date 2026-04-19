# ADR-ARCH-010: Sentinel-key family providers require invalidation before push

Status: Accepted
Proposed in: P024

## Context

`StateNotifierProvider.family` keyed by a `String conversationId` allows each thread to have its
own notifier instance. For the "new conversation" flow, the literal string `'new'` is used as the
key (`threadNotifierProvider('new')`). Riverpod keeps family instances alive until explicitly
disposed or invalidated.

After a new conversation is created (the user sends a message and receives a result), the `'new'`
instance transitions to `ThreadState.loaded` carrying the real `conversationId`. If the user taps
"+" a second time and pushes `/chat/new` without prior invalidation, Riverpod returns the same
existing `'new'` notifier instance — which already holds a completed conversation — instead of a
fresh notifier with a new UUID.

## Decision

Before every `context.push('/chat/new')`, the caller must call
`ref.invalidate(threadNotifierProvider('new'))`. This disposes the existing `'new'` notifier and
causes Riverpod to create a fresh instance on the next read, which generates a new client-side
UUID and starts in an empty state.

Pattern:

```dart
// In ConversationsScreen "+" button handler:
ref.invalidate(threadNotifierProvider('new'));
await context.push('/chat/new');
ref.read(conversationsNotifierProvider.notifier).refresh();
```

The `ref.invalidate(...)` call MUST precede `context.push(...)`. The push happens immediately
after, so the new notifier is created synchronously by `ThreadScreen`'s `ConsumerStatefulWidget`
init.

## Rationale

The alternative — adding `.autoDispose` to the family provider — would dispose the notifier when
it loses all listeners (screen pops). However, an in-progress SSE stream must survive navigation
away (the stream should complete cleanly even if the user backs out). `autoDispose` would cancel
the notifier mid-stream. Keeping the provider alive (non-autoDispose) and invalidating explicitly
before each new-conversation push achieves the correct lifecycle: streams run to completion,
and each "+" tap starts fresh.

## Consequences

- The "+" button handler in `ConversationsScreen` must always include the invalidate call before
  the push. Omitting it causes the second new-conversation attempt to reuse stale state.
- Code review must verify the `ref.invalidate` + `context.push` pair is present wherever
  `/chat/new` is pushed.
- This pattern applies to any `family` provider that uses a sentinel key for a "new/draft"
  state. Future proposals that introduce similar sentinel-key patterns should follow this
  invalidate-before-push convention.
