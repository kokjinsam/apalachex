#!/bin/sh
set -eu

version=0.58.3
archive_name="apalache-$version.tgz"
checksum=ba622db9538aebf942cc7a7815f942a6b2b419012707e16dfdc25a73ff95d0a5
install_root=${1:?usage: install_apalache.sh INSTALL_ROOT}
work_root=$(mktemp -d "${TMPDIR:-/tmp}/apalachex-install.XXXXXX")
archive="$work_root/$archive_name"
extract_root="$work_root/extract"
staged="$work_root/install"

if [ -e "$install_root" ]; then
  printf 'refusing to overwrite existing path: %s\n' "$install_root" >&2
  exit 1
fi

mkdir "$extract_root" "$staged"
curl --fail --location --retry 3 \
  --output "$archive" \
  "https://github.com/apalache-mc/apalache/releases/download/v$version/$archive_name"
printf '%s  %s\n' "$checksum" "$archive" | sha256sum --check --status
tar -xzf "$archive" -C "$extract_root"

binary=$(find "$extract_root" -type f -path '*/bin/apalache-mc' -print | head -n 1)
[ -n "$binary" ] || { printf '%s\n' "apalache-mc missing from archive" >&2; exit 1; }
distribution=$(CDPATH= cd -- "$(dirname -- "$binary")/.." && pwd)
cp -R "$distribution"/. "$staged"/
chmod +x "$staged/bin/apalache-mc"
"$staged/bin/apalache-mc" version
mv "$staged" "$install_root"
