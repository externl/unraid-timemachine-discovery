#!/bin/bash
# Build the package and stamp its version and sha256 into the manifest.
# Needs Slackware's makepkg, so run it on the Unraid server.
#
#   ./pkg_build.sh      version is today's date
#   ./pkg_build.sh .1   same-day rerun; numeric suffix, see README
set -eu

cd "$(dirname "$0")"
version=$(date +"%Y.%m.%d")${1:-}
pkg="$PWD/archive/timemachine-discovery-${version}-x86_64-1.txz"

mkdir -p archive

# makepkg narrates to stderr even when it succeeds.
buildlog=$(mktemp)
trap 'rm -f "$buildlog"' EXIT
if ! ( cd source/timemachine-discovery && makepkg -l y -c y "$pkg" ) >"$buildlog" 2>&1; then
  cat "$buildlog" >&2
  exit 1
fi

sha=$(sha256sum "$pkg" | cut -d' ' -f1)
sed -i -e "s|\(<!ENTITY version *\"\)[^\"]*\"|\1${version}\"|" \
       -e "s|\(<!ENTITY sha256 *\"\)[^\"]*\"|\1${sha}\"|" timemachine-discovery.plg

echo "built ${pkg##*/}"
echo "sha256 ${sha}"
