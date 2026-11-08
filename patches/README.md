# 32-bit fixes applied to upstream Alloy

`build.sh` applies these, in order, to the upstream tag before building. Each one fixes a crash found on a Raspberry Pi 2 (armv7, 32-bit). They're written so they could be proposed upstream as-is.

| Patch | Symptom on 32-bit ARM | Cause | Fix |
|---|---|---|---|
| `0001-makefile-no-gore2regex-on-arm.patch` | `panic: cannot allocate memory` at startup, in `wasilibs/go-re2` package init (via gitleaks / `loki.secretfilter`) | The Makefile always adds the `gore2regex` tag (since grafana/alloy PR #5909). go-re2 reserves 1 GiB of address space at init, which a 32-bit process can't get. | Don't add `gore2regex` when `GOARCH=arm`; regexps fall back to Go's standard library. |
| `0002-fanout-align-64bit-atomic.patch` | `panic: unaligned 64-bit atomic operation` on the first scrape, in `prometheus.(*Fanout).Appender` | `Fanout.lastSeriesCount` (a `go.uber.org/atomic.Int64`) sat after fields whose sizes leave it 4-byte aligned on 32-bit. 64-bit atomics need 8-byte alignment there. | Make it the first field, which Go guarantees is 8-byte aligned in an allocated struct. |
