# ADR-AUDIO-001: 16kHz mono PCM WAV as canonical audio format

Status: Accepted
Proposed in: P001

## Context

The recording module produces audio files consumed by the speech-to-text engine. The STT engine (originally Whisper, later Groq) requires a specific input format. Key parameters: sample rate, channel count, encoding, and container format.

Whisper models are trained on 16kHz mono audio. Submitting other sample rates requires resampling, which degrades quality or adds complexity.

The `record` package offers `AudioEncoder.wav` (WAV container with headers) and `AudioEncoder.pcm16bits` (headerless raw PCM). Headerless PCM requires the consumer to know the exact format parameters out-of-band.

## Decision

All audio recordings use 16kHz, mono, PCM 16-bit in WAV container format (`AudioEncoder.wav`). This is the contract between P001 (recording) and the STT layer.

## Rationale

WAV headers make files self-describing — any consumer can read format parameters without external coordination. 16kHz mono matches Whisper's native format and Groq's API expectations, avoiding resampling.

## Consequences

- Recording module configures `AudioEncoder.wav` at 16000 Hz, 1 channel.
- STT implementations can validate input format by reading WAV headers.
- File sizes are larger than compressed formats (~1.9 MB/min) — acceptable for short voice recordings.
- Changing the audio format requires updating both the recording and STT modules atomically.
