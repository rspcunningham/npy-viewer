# NPYViewer

Native macOS `.npy` image viewer for ParaSight data.

Install:

```bash
curl -fsSL https://raw.githubusercontent.com/rspcunningham/npy-viewer/main/install.sh | bash
```


## Build

```bash
./script/build_and_run.sh --build-only
```

The app bundle is staged at:

```text
dist/NPYViewer.app
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
