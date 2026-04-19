# ADR-ARCH-011: Post-navigation list refresh via awaited context.push()

Status: Accepted
Proposed in: P024

## Context

When a user navigates from a list screen to a detail/edit screen (or a "new item" screen) and
then returns, the list may be stale: items may have been created, modified, or deleted during the
sub-navigation. Without a refresh, the list shows data from the previous load.

Two approaches were considered:

- **Watch the data source live (e.g., stream from storage):** Correct for locally-persisted data
  where the client owns the source of truth. Not applicable here — conversation data lives on the
  backend; there is no local reactive store.
- **Refresh after pop (pull-on-return):** Trigger a refresh after the sub-route returns. Works
  for any backend-fetched list without a local reactive store.

## Decision

For screens that navigate to a child route and need a fresh list on return, use
`await context.push(...)` followed by an explicit notifier refresh:

```dart
// Navigation to detail or new-item screen:
await context.push('/chat/${conv.conversationId}');
ref.read(conversationsNotifierProvider.notifier).refresh();

// Navigation to new-conversation screen:
ref.invalidate(threadNotifierProvider('new'));  // per ADR-ARCH-010
await context.push('/chat/new');
ref.read(conversationsNotifierProvider.notifier).refresh();
```

`context.push()` returns a `Future` that completes when the pushed route pops. `await`-ing it
allows the caller to run the refresh exactly once, synchronously after pop, with no polling and
no dependency on the popped route's internal state.

## Rationale

GoRouter's `context.push()` returns a `Future<T>` that resolves on pop. `await`-ing it is idiomatic
GoRouter and avoids adding listeners, callbacks, or event buses between screens. The refreshed
data loads in the background while the list is already visible — the `RefreshIndicator` or loading
state in the list notifier handles UI feedback.

## Consequences

- List screens that navigate to child screens must use `await context.push(...)` (not
  `context.push(...)` without await, and not `context.go(...)`).
- The notifier must expose a public `refresh()` method. If only `load()` exists,
  rename or alias it.
- The refresh triggers a network call on every pop from the child screen — acceptable for
  occasional list navigation. If the list becomes large or frequently accessed, add staleness
  detection or local caching in a follow-up.
- `context.go(...)` MUST NOT be used for child navigation from shell branches — it destroys
  shell state (per ADR-ARCH-002). Always use `context.push(...)`.
