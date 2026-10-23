# example

Pinch-to-zoom photo grid (2/3/4/6/10 columns) with an instrumentation panel:
requests, completions, cancels, request-to-frame latency p50/p95, peak
in-flight requests, frames over 16 ms, memory-pressure events, and live native
buffers (must read 0 at rest). "Memory pressure" calls
`PaintingBinding.handleMemoryPressure()` so the cancel logic can be checked
against `imageCache.clear()` on a device.
