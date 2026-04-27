# NPYViewer

Native macOS `.npy` image viewer for ParaSight data.

This v0.0 build supports 2D C-order NumPy arrays with:

- `float32` (`<f4`) displayed directly as grayscale, clamped to `[0, 1]`
- `complex64` (`<c8`) displayed as magnitude by default, with phase/real/imag modes

The app keeps the mapped `.npy` payload resident on the CPU for exact hover readout, uploads once to a Metal texture, and renders through `MTKView`.

## Build

```bash
./script/build_and_run.sh --build-only
```

The app bundle is staged at:

```text
dist/NPYViewer.app
```

The script signs with the first available `Developer ID Application` identity, then the first `Apple Development` identity, and falls back to ad-hoc signing when neither exists. That means coworkers can build from source without Apple Developer accounts. For frictionless sharing of a prebuilt app outside this machine, use a Developer ID certificate and notarization.

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
