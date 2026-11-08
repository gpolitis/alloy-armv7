# alloy-armv7

Unofficial **32-bit ARM (armv7 / armhf)** builds of [Grafana Alloy](https://github.com/grafana/alloy), for devices like the Raspberry Pi 2 that upstream doesn't ship builds for.

**Not affiliated with or supported by Grafana Labs.** Each release is the upstream tag, unmodified, built with `GOARCH=arm GOARM=7` inside the same `grafana/alloy-build-image` upstream CI uses.

## What's in a release
- `alloy-linux-armv7`: the binary.
- `alloy_<version>-1_armhf.deb`: packaged like the official `.deb` (same `alloy.service`, `/etc/alloy/config.alloy`, `/etc/default/alloy`, `alloy` user), using upstream's own packaging files.
- `SHA256SUMS`, and upstream's `LICENSE` (Apache 2.0).

A scheduled workflow checks daily for a new stable upstream release and builds it.

## Differences from official builds
- **Built with `CGO_ENABLED=0`.** With cgo, the 32-bit ARM cross-linker in the upstream build image fails (`ld` 2.35.2: `assertion fail elf32-arm.c`). Without cgo, Go's own linker is used. The cost: no systemd journal log source (`loki.source.journal`), which needs cgo.
- **Without the `gore2regex` build tag.** Upstream's Makefile always adds it, switching `loki.secretfilter` (via gitleaks) to the go-re2 library. go-re2 reserves 1 GiB of address space when its package initializes, which fails in a 32-bit process: the binary panics with `cannot allocate memory` before doing anything. `build.sh` removes that line from the Makefile, so those regexps use Go's standard library (slower for `loki.secretfilter`, otherwise the same).
- No Docker images, no boringcrypto variant, no `.rpm`.

## Install (Debian / Raspberry Pi OS, armhf)
```sh
tag=$(curl -fsSL https://api.github.com/repos/gpolitis/alloy-armv7/releases/latest | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p')
curl -fsSLO "https://github.com/gpolitis/alloy-armv7/releases/download/$tag/alloy_${tag#v}-1_armhf.deb"
sudo apt-get install ./alloy_${tag#v}-1_armhf.deb
```

### Automatic updates
`updater/` has a small script plus a systemd timer that installs a newer release when one appears (checks `SHA256SUMS` first):
```sh
sudo install -m 755 updater/alloy-armv7-update /usr/local/sbin/
sudo install -m 644 updater/alloy-armv7-update.service updater/alloy-armv7-update.timer /etc/systemd/system/
sudo systemctl daemon-reload && sudo systemctl enable --now alloy-armv7-update.timer
```

## Build locally
Needs git and Docker. Some packages need several GB of RAM each to compile: with 8 GB for Docker, `GO_PARALLEL=1` works and 3 gets the compiler killed. The default is 2 (GitHub's standard runners have 16 GB).
```sh
GO_PARALLEL=1 ./build.sh v1.21.3 dist
```
