# NPYViewer

Native macOS `.npy` image viewer for ParaSight data.

This v0.0 build supports 2D C-order NumPy arrays with:

- `float32` (`<f4`) displayed directly as grayscale, clamped to `[0, 1]`
- `complex64` (`<c8`) displayed as magnitude by default, with phase/real/imag modes

The app keeps the mapped `.npy` payload resident on the CPU for exact hover readout, uploads once to a Metal texture, and renders through `MTKView`.

## Install

One-line installer:

```bash
curl -fsSL https://raw.githubusercontent.com/rspcunningham/npy-viewer/main/install.sh | bash
```

The installer downloads the latest notarized GitHub Release and installs `NPYViewer.app` into `/Applications` when writable, otherwise `~/Applications`.

Direct zip download:

[NPYViewer-0.0.1-macOS-arm64.zip](https://github.com/rspcunningham/npy-viewer/releases/download/v0.0.1/NPYViewer-0.0.1-macOS-arm64.zip)

To choose a location:

```bash
curl -fsSL https://raw.githubusercontent.com/rspcunningham/npy-viewer/main/install.sh | INSTALL_DIR="$HOME/Applications" bash
```

## Build

```bash
./script/build_and_run.sh --build-only
```

The app bundle is staged at:

```text
dist/NPYViewer.app
```

The local build path signs with the first available `Apple Development` identity and falls back to ad-hoc signing when none exists. That means coworkers can build from source without Apple Developer accounts.

## Release Build

For a downloadable macOS artifact, use Developer ID signing and notarization:

```bash
./script/package_release.sh
```

That script requires:

- A valid `Developer ID Application` certificate in your keychain
- A notarytool keychain profile named `NPYViewerNotaryProfile`

Create the notary profile once with:

```bash
xcrun notarytool store-credentials "NPYViewerNotaryProfile"
```

The release script signs with hardened runtime and a trusted timestamp, uploads a zip to Apple notarization, staples the ticket to the `.app`, validates the staple, runs Gatekeeper assessment, and writes:

```text
dist/release/NPYViewer-0.0.1-macOS-arm64.zip
```

If your Developer ID identity has a nonstandard name, set:

```bash
DEVELOPER_ID_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./script/package_release.sh
```

## Automated Releases

GitHub Actions can build, Developer ID sign, notarize, staple, validate, and publish a release zip when you push a version tag:

```bash
git tag v0.0.2
git push origin v0.0.2
```

Configure these repository secrets first:

- `DEVELOPER_ID_CERTIFICATE_BASE64`: base64-encoded exported Developer ID `.p12`
- `DEVELOPER_ID_CERTIFICATE_PASSWORD`: password for that `.p12`
- `APPLE_ID`: Apple ID email for notarization
- `APPLE_TEAM_ID`: Apple Developer team ID
- `APPLE_APP_SPECIFIC_PASSWORD`: app-specific password for `notarytool`

Create the certificate secret from an exported `.p12`:

```bash
base64 -i DeveloperIDApplication.p12 | pbcopy
```

The workflow only runs on `v*` tag pushes so signing credentials are not exposed to pull requests.

## Run

```bash
./script/build_and_run.sh
```

You can also open a sample directly:

```bash
open -n dist/NPYViewer.app --args "$PWD/Samples/reconstruction.npy"
```

## Controls

- Scroll: zoom around cursor
- Drag: pan
- Hover: exact CPU-side pixel value
- `a`: complex magnitude
- `p`: complex phase
- `r`: complex real
- `i`: complex imaginary
- `m`: cycle complex modes
- `0`: reset view
