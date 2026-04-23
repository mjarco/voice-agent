# P000: Backlog

Known issues and design gaps that don't yet warrant a standalone proposal. Each item should be resolved in the context of the slice where it becomes concrete.

Cross-project items reference `personal-agent/docs/proposals/P000-backlog.md` where backend work must land together.

---

## VAD hangover tuning — optimal default and dynamic adjustment

**Promoted to proposal:** [031-vad-hangover-tuning.md](031-vad-hangover-tuning.md)

**Origin:** Rozmowa 2026-04-22 (sesja testów voice agenta)

**Problem:** Wypowiedzi są dzielone na fragmenty — VAD za szybko uznaje przerwę za koniec wypowiedzi i wysyła kawałek do STT. W trakcie sesji przetestowano 10 s → 1000 ms → 800 ms. Wartość 800 ms daje rozsądny kompromis między swobodą naturalnych pauz a latencją reakcji agenta.

**Proposed direction — dynamic hangover:**
- Formuła: `hangover = base_hangover + (noise_level * scaling_factor)`
- Sygnały do dynamicznej regulacji: poziom szumu tła, długość poprzedniej wypowiedzi, kontekst (agent zadał pytanie otwarte → większy bufor), tempo mowy użytkownika
- Alternatywa pragmatyczna: start 800 ms + strojenie na podstawie feedbacku i metryk (ile razy wypowiedź dociera w wielu fragmentach vs. w całości)

**Research needed:**
- Zbadać typowe wartości hangover w produkcyjnych aplikacjach VAD (Alexa, Siri, Google Assistant)
- Zebrać metryki fragmentacji wypowiedzi na realnych użyciach z 800 ms

**Related proposals:** 012-hands-free-local-vad, 013-vad-advanced-settings.

**Related ADRs:** ADR-AUDIO-006-immutable-vad-config (może wymagać rewizji, jeśli hangover staje się runtime-dynamic).

**When to address:** Po okresie zbierania danych z 800 ms (≥ 1 tydzień realnych użyć).

---

## "New conversation" button in voice agent UI

**Promoted to proposal:** [032-new-conversation-button.md](032-new-conversation-button.md)

**Origin:** Rozmowa 2026-04-22

**Decision:** Przycisk do rozpoczęcia nowej konwersacji ma być w kliencie mobilnym (voice agent), nie w web UI personal-agent. Uzasadnienie: primary flow jest głosowy, w mobilce — UI webowe to widok wtórny.

**Proposed solution:** Widget (button albo swipe gesture) w recording screen lub chat screen. Akcja: zamknięcie bieżącej `conversation_id`, wyczyszczenie lokalnego stanu rozmowy, start nowej sesji i nowej konwersacji.

**Related proposals:** 014-recording-mode-overhaul, 024-chat-screen, 029-honor-session-control-signals (shared SessionIdCoordinator).

**When to address:** Niska priorytet — dotyka UX recording/chat screen; zrobić w ramach najbliższego pass nad mobile UX.

---

## Honor session-control signals from backend metadata (reset session, stop recording)

**Promoted to proposal:** [029-honor-session-control-signals.md](029-honor-session-control-signals.md) (full draft)

**Cross-project pair:** personal-agent P049 (full draft) — must ship together.

**Status:** Both proposals are fully designed. Ready for review and implementation.

---

## Daily / monthly API cost dashboard in mobile UI

**Promoted to proposal:** [033-api-cost-dashboard.md](033-api-cost-dashboard.md)

**Origin:** Rozmowa 2026-04-22

**Problem:** User chce widzieć agregaty kosztów API (dzień / miesiąc) w mobilce. Uzupełnienie możliwości zapytania agenta głosowo o koszt bieżącej rozmowy — dashboard dla wglądu retrospektywnego.

**Proposed solution:** Nowy ekran "Usage" / "Koszty" albo sekcja w settings screen. Pobiera agregaty z `/api/v1/usage?from=&to=`. Wykres dzienny dla bieżącego miesiąca + licznik miesięczny (aktualny + poprzedni).

**Related (personal-agent):** P033 api-usage-and-cost-tracking (dane istnieją, brak endpointu agregującego — potrzebny nowy proposal ~P055), P051 agent-tool-cost-of-conversation (komplementarnie z dashboardem).

**Related proposals (voice-agent):** 021-agenda-screen (wzorzec ekranu z agregatami), 006-settings-screen (jeśli jako podsekcja).

**When to address:** Po stworzeniu endpointu agregującego po stronie personal-agent. P051 nie blokuje — to komplementarna funkcja (głos + wizualne).

---

## TTS mixed-language support — honor SSML `<lang>` tags

**Promoted to proposal:** [030-tts-mixed-language-ssml.md](030-tts-mixed-language-ssml.md) (full draft)

**Cross-project pair:** personal-agent P054 (full draft) — must ship together; P054 has a kill switch (`CHAT_SSML_WRAPPER_ENABLED=false`) until voice-agent 030 is deployed.

**Status:** Both proposals are fully designed. Ready for review and implementation.
