# OMNI AI Android signing baseline

## Current installable baseline

- Android application ID: `com.omniai.omni_ai`
- Baseline version: `1.0.1+2`
- Build type: full, universal release APK (not split by ABI)
- Local model: not bundled in the APK
- Signing certificate SHA-256: `814791f4c44b12adf0619067b4feaa51a9bdff28c24ceba21d445348ce0639a4`
- Signing key alias: `androiddebugkey`
- GitHub Actions cache key: `omni-ai-stable-debug-keystore-v1`
- Workflow: [Android installable APK](../.github/workflows/android-test-apk.yml)

## Rules for future updates

1. Keep the application ID unchanged.
2. Never generate a replacement signing key silently. The workflow must fail if the established key cannot be restored.
3. Keep increasing the Android `versionCode` for each published update.
4. Validate the APK archive, zip alignment, package ID, native ABIs, and certificate before publishing.
5. Upload only the APK as a GitHub Actions artifact; extract `app-release.apk` from the downloaded artifact ZIP before installing it.

## Important key-storage limitation

The private signing key currently survives through the GitHub Actions cache. The certificate fingerprint above identifies the key, but **a fingerprint cannot reconstruct the private key**. GitHub cache entries can eventually be evicted, so this is not yet a permanent backup.

For durable recovery, export the existing keystore from a trusted runner and store it as a protected GitHub Actions secret (for example, a base64-encoded keystore secret), then update the workflow to restore that secret before building. Never commit the keystore or publish it as a workflow artifact: this repository is public. Until that protected backup is configured, do not clear or rename the signing-key cache and do not accept a build that uses a different certificate.
