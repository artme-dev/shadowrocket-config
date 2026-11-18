# 9–11 November 2026 — slow first fallback entry

AUTO held on to Xeovo Netherlands SS because it still answered its availability
check. Native latency to a small ordinary HTTPS endpoint on the Mac fell from
about 4 s to 0.75 s after manually selecting Blanc Amsterdam. The native AI chain
still took about 8–9 s. Stale Proxy Pass selection was considered, but no
controlled restart was performed and that hypothesis was not established.

The 11 November comparison again found Amsterdam stable and Xeovo Netherlands
variable. Germany Trojan failed both attempts. The published personal config
was changed to prioritize Amsterdam, then Almaty, then the remaining Blanc
entries before Xeovo. The published profile was checked byte-for-byte. The
change only reordered AUTO. See `8e39e9d` and the [personal profile guide](../../personal/README.md).

Private evidence is under `out/diagnostics/2026-11-09/`,
`out/diagnostics/2026-11-11/`, and `out/recovery/2026-11-11/`.
