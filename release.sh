#!/bin/bash
# Build the package, stamp the manifest, add the changelog entry, check the
# three agree. Commits nothing: pushing to main is what publishes.
#
#   ./release.sh "Fixed the thing" "Added the other thing"
#   ./release.sh -s .1 "Second release today"
set -eu

cd "$(dirname "$0")"

PLUGIN="timemachine-discovery"
PLG="$PLUGIN.plg"
SRC="source/$PLUGIN"
IMAGE="vbatts/slackware:current"

usage() { echo "usage: $0 [-s SUFFIX] \"changelog line\" [...]" >&2; exit 1; }

suffix=""
while getopts "s:" opt; do
  case "$opt" in
    s) suffix=$OPTARG ;;
    *) usage ;;
  esac
done
shift $((OPTIND - 1))
[ $# -gt 0 ] || usage

work=""
cleanup() { rm -f "$PLG.tmp"; [ -n "$work" ] && rm -rf "$work"; return 0; }
trap cleanup EXIT

plg_entity() { sed -n "s/.*<!ENTITY $1 *\"\([^\"]*\)\".*/\1/p" "$PLG"; }
sha_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | cut -d' ' -f1
  else
    shasum -a 256 "$1" | cut -d' ' -f1
  fi
}

# Arch ships an unrelated tool of the same name; brew installs it too.
slackware_makepkg() {
  command -v makepkg >/dev/null 2>&1 && makepkg 2>&1 | grep -q 'package_name'
}

version="$(date +%Y.%m.%d)$suffix"
grep -q "^### $version\$" "$PLG" && {
  echo "error: $PLG already has a '### $version' entry; pick a suffix with -s" >&2
  exit 1
}

if slackware_makepkg; then
  ./pkg_build.sh "$suffix"
elif command -v docker >/dev/null 2>&1; then
  echo "no Slackware makepkg here; building in $IMAGE"
  docker run --rm --platform linux/amd64 -v "$PWD:/w" -w /w "$IMAGE" ./pkg_build.sh "$suffix"
else
  echo "error: need Slackware makepkg, or docker to run it in a container" >&2
  exit 1
fi

stamped=$(plg_entity version)
[ "$stamped" = "$version" ] || {
  echo "error: expected version $version but $PLG says $stamped" >&2
  exit 1
}
pkg="archive/$PLUGIN-$version-x86_64-1.txz"

entry="### $version"
for line in "$@"; do
  entry="$entry
- $line"
done

# Through the environment, because awk -v cannot hold a newline.
entry="$entry" awk '
  { print }
  /^<CHANGES>$/ && !added { print ENVIRON["entry"]; print ""; added = 1 }
' "$PLG" >"$PLG.tmp"
mv "$PLG.tmp" "$PLG"

failed=0
fail() { echo "error: $*" >&2; failed=1; }

[ -f "$pkg" ] || fail "$pkg was not built"
[ "$(sha_of "$pkg")" = "$(plg_entity sha256)" ] || fail "sha256 in $PLG does not match $pkg"
[ "$(grep -m1 '^### ' "$PLG")" = "### $version" ] || fail "newest changelog entry is not ### $version"

work=$(mktemp -d)
tar -xpf "$pkg" -C "$work"
diff -r "$SRC" "$work" >/dev/null || fail "$pkg does not match $SRC"

# diff ignores modes, and an event hook without its exec bit never runs.
while IFS= read -r rel; do
  [ -f "$work/$rel" ] || continue
  if [ -x "$SRC/$rel" ] && [ ! -x "$work/$rel" ]; then fail "$rel lost its exec bit"; fi
  if [ ! -x "$SRC/$rel" ] && [ -x "$work/$rel" ]; then fail "$rel gained an exec bit"; fi
done < <(cd "$SRC" && find . -type f | sed 's|^\./||')

[ "$failed" -eq 0 ] || exit 1

echo
echo "released $version -- commit $pkg and $PLG together, then push"
