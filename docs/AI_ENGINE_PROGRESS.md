# AI Engine migration — project checkpoint

Last updated: 2026-10-10

## Goal
Move OMNI_AI away from Gemini as its default/central AI provider. Keep the provider layer replaceable, support optional on-device inference, and only use a cloud provider for tasks that need it and when the user has enabled it.

## Branch safety
- Repository: `vanes961/omni_ai`
- Work branch: `feat/ai-engine-foundation`
- Never commit changes to `main`.

## Current implementation
- `AIProvider` interface and `AIEngine` cancellation/timeout wrapper exist.
- Gemini provider still exists and is currently constructed by `AIDependencies`; it has not been removed or replaced in the app.
- `path_provider` and `llama_flutter_android: ^0.2.6` are in `pubspec.yaml`.
- `LocalModelStorage` downloads a GGUF file into app-private support storage, reports byte progress, uses a `.part` file, and supports deletion.
- Current model catalog candidate: Qwen3 0.6B Q4_K_M. Its source URL and approximate size are provisional and must be verified before shipping.
- No local inference provider, model download UI, memory/preferences repository, or provider routing is wired into the app yet.
- Do not claim device acceleration is available until verified on the target device.

## Latest commit
- `99cefee152fd0c2b48480f161345f7d27aa62b42` — `style: format local model storage`
- This corrects the formatting failure reported by CI for `local_model_storage.dart`.

## CI state before formatting fix
Run: https://github.com/vanes961/omni_ai/actions/runs/38046079684
- Dependency resolution passed, including `llama_flutter_android 0.2.6`.
- Formatting step failed only because `local_model_storage.dart` needed formatting.
- Analyze, tests, and Android APK build were skipped as a result.
- A new CI run must be checked after the formatting commit. Do not claim the build passes until the run completes successfully.

## Next steps
1. Check CI for commit `99cefee`; resolve formatting/analyzer/test/build failures before adding more features.
2. Verify the real API of `llama_flutter_android` version 0.2.6 from its package documentation/source. Do not guess method names or model-loading APIs.
3. Verify the Qwen model URL, license, exact file size, and model compatibility; change the catalog if needed.
4. Implement a local `AIProvider` adapter only against the verified plugin API, including cancellation/disposal and resource limits.
5. Add a provider-selection/routing abstraction that prefers local inference for supported simple/offline tasks; keep cloud fallback opt-in and never silently send prompts to a cloud service.
6. Treat OpenAI or any other cloud model as an optional adapter, not as a bundled secret. Do not embed API secrets in the APK; document a safe key strategy before implementation.
7. Add persistent memory/preferences as a separate service/repository, independent of the model provider.
8. Wire UI/download controls only after core provider tests pass. Run CI and verify actual inference on the target HONOR Magic V2; no performance or accelerator promises before device testing.

## User decisions
- Replace Gemini as the primary/default AI direction.
- Prioritize local Qwen first, with optional cloud provider for complex requests.
- Keep APK small; download the model separately only when the user chooses to.
- Continue autonomously when the user says “Продолжай”; avoid repeatedly asking for permission.
