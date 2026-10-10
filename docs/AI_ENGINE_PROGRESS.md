# AI Engine migration — project checkpoint

Last updated: 2026-10-10

## Goal
Move OMNI_AI away from Gemini as its default/central AI provider. Keep provider adapters replaceable, support optional on-device inference, and only use a cloud provider for tasks that need it and when the user has explicitly enabled it.

## Branch safety
- Repository: `vanes961/omni_ai`
- Work branch: `feat/ai-engine-foundation`
- Never commit changes to `main`.

## Current implementation
- `AIProvider` interface and `AIEngine` cancellation/timeout wrapper exist.
- Gemini provider still exists and is currently constructed by `AIDependencies`; it has not been removed or replaced in app wiring.
- `path_provider` and `llama_flutter_android: ^0.2.6` are in `pubspec.yaml`.
- `LocalModelStorage` downloads a GGUF file into app-private support storage, reports byte progress, uses a `.part` file, and supports deletion.
- Added `LocalLlamaProvider` adapter in `lib/core/ai_engine/local/local_llama_provider.dart` using the documented `LlamaController` API. It checks that the model exists/is loaded, generates locally, supports cancellation via controller.stop(), and exposes explicit model loading/disposal.
- The adapter is not wired into UI/DI yet, and has not passed CI or device tests yet.
- Current model catalog candidate: Qwen3 0.6B Q4_K_M. Source URL, license, exact size and model/template compatibility remain to be verified before shipping.
- No provider router, download UI, or separate memory/preferences repository is wired into the app yet.
- Plugin documentation lists Vulkan GPU support, but actual GPU support/performance on the target device must be tested; don't promise acceleration.

## Latest commits
- `362aada55e1ef8c88ab428c633979679ab5fd62a` — `feat: add local llama AI provider adapter`
- `99cefee152fd0c2b48480f161345f7d27aa62b42` — `style: format local model storage`
- `79b6068f110c6204d6b075093260a4b297c8fae5` — `docs: save AI engine migration checkpoint`

## CI state
Previous run: https://github.com/vanes961/omni_ai/actions/runs/38046079684
- Dependency resolution passed, including `llama_flutter_android 0.2.6`.
- Formatting failed because `local_model_storage.dart` needed formatting. The formatting fix was committed afterward.
- Analyze, tests, and Android APK build were skipped on that run.
- A new run must be checked after commits; don't claim CI passes until a completed run succeeds.

## Next steps
1. Run/check CI on the latest commit; fix formatting, analyzer, tests and Android build issues before wiring UI.
2. Verify adapter API against version 0.2.6 and add tests around not-loaded model, cancellation, empty output and disposal where feasible.
3. Verify the Qwen model URL, license, exact file size, chat template and model compatibility; update catalog if necessary.
4. Add explicit model download/load controls and progress UI only after core code passes.
5. Add a provider-selection/router abstraction that prefers local inference for suitable/offline tasks; cloud fallback must be opt-in and never silently send prompts off-device.
6. Treat OpenAI or another cloud model as an optional adapter. Do not embed API secrets in the APK; define a safe key strategy before implementation.
7. Add persistent memory/preferences as a separate service/repository, independent of model provider.
8. Verify real inference and resource use on the HONOR Magic V2 before making performance/acceleration claims.

## User decisions
- Replace Gemini as the primary/default AI direction.
- Prioritize local Qwen first, with optional cloud provider for complex requests.
- Keep APK small; download the model separately only when the user chooses to.
- Continue autonomously when the user says “Продолжай”; avoid repeatedly asking for permission.
