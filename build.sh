#!/usr/bin/env bash
# Build an unofficial 32-bit ARM (armv7, armhf) Grafana Alloy release:
# the binary and a .deb laid out like the official package.
#
# Usage: ./build.sh <alloy-tag> [out-dir]      e.g. ./build.sh v1.21.3 dist
# Needs: git, docker. Builds inside grafana/alloy-build-image, like upstream CI.
#
# Env:
#   CGO_ENABLED  default 0. With 1 the old cross-linker in the build image fails
#                (ld 2.35.2 assertion in elf32-arm.c); 0 uses Go's own linker,
#                at the cost of the systemd journal log source.
#   GO_PARALLEL  packages compiled at once (default 2). Some packages need
#                several GB of RAM each to compile.
set -euo pipefail

tag="${1:?usage: $0 <alloy-tag> [out-dir]}"
out="$(mkdir -p "${2:-dist}" && cd "${2:-dist}" && pwd)"
cgo="${CGO_ENABLED:-0}"
par="${GO_PARALLEL:-2}"
version="${tag#v}"
image="${BUILD_IMAGE:-}"
work="$(mktemp -d)"
# The build container writes root-owned files into the clone on Linux hosts,
# so delete them from a container too, then the (now empty) temp dir.
cleanup() {
  [ -n "$image" ] && docker run --rm -v "$work":/w "$image" rm -rf /w/alloy || true
  rm -rf "$work"
}
trap cleanup EXIT

git clone -q --depth 1 --branch "$tag" https://github.com/grafana/alloy.git "$work/alloy"

# 32-bit fixes (see patches/README.md). git apply fails loudly if one no longer applies.
here="$(cd "$(dirname "$0")" && pwd)"
for p in "$here"/patches/*.patch; do
  echo "applying $(basename "$p")"
  git -C "$work/alloy" apply "$p"
done

if [ -z "$image" ]; then
  # Use the same build image upstream CI uses for this tag.
  image="$(grep -oE 'grafana/alloy-build-image:[^ "]+' "$work/alloy/.github/workflows/build.yml" | head -1)"
fi
echo "Building Alloy $tag for linux/arm (GOARM=7, CGO_ENABLED=$cgo) in $image"

tags="netgo embedalloyui"
[ "$cgo" = 1 ] && tags="$tags promtail_journal_enabled"

docker run --rm \
  -v "$work/alloy":/src -v "$out":/out -w /src \
  -v alloy-gocache:/root/.cache -v alloy-gomod:/go/pkg/mod \
  -e USE_CONTAINER=0 -e GOFLAGS="-p=$par" \
  "$image" bash -euo pipefail -c "
    git config --global --add safe.directory /src
    make alloy RELEASE_BUILD=1 VERSION=$tag GOOS=linux GOARCH=arm GOARM=7 \
      CGO_ENABLED=$cgo GO_TAGS='$tags'
    if go version -m build/alloy | grep -q gore2regex; then
      echo 'gore2regex is still in the build tags; the binary would crash on 32-bit ARM' >&2
      exit 1
    fi
    install -m 755 build/alloy /out/alloy-linux-armv7
    # Same fpm call as upstream build-tools/make/packaging.mk, with vendor and
    # description marking this as an unofficial build.
    fpm -s dir -v $version -a armhf -n alloy --iteration 1 -f --log error \
      --license 'Apache 2.0' \
      --vendor 'Unofficial armv7 build (github.com/gpolitis/alloy-armv7)' \
      --url 'https://github.com/gpolitis/alloy-armv7' \
      --description 'Grafana Alloy, unofficial 32-bit ARM (armv7) build of the upstream $tag release.' \
      -t deb \
      --after-install packaging/deb/control/postinst \
      --before-remove packaging/deb/control/prerm \
      --config-files /etc/alloy/config.alloy \
      --config-files /etc/alloy/config.yaml \
      --config-files /etc/default/alloy \
      --package /out/alloy_${version}-1_armhf.deb \
        /out/alloy-linux-armv7=/usr/bin/alloy \
        packaging/config.alloy=/etc/alloy/config.alloy \
        packaging/config.yaml=/etc/alloy/config.yaml \
        packaging/environment-file=/etc/default/alloy \
        packaging/systemd/alloy-wrapper=/usr/lib/alloy/alloy-wrapper \
        packaging/deb/alloy.service=/usr/lib/systemd/system/alloy.service
    cp LICENSE /out/LICENSE
  "

cd "$out"
if command -v sha256sum >/dev/null; then sum=sha256sum; else sum="shasum -a 256"; fi
$sum alloy-linux-armv7 "alloy_${version}-1_armhf.deb" > SHA256SUMS
ls -lh
