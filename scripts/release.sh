#!/usr/bin/env bash
set -Eeuo pipefail

package='apalachex'
repository='kokjinsam/apalachex'
notes_file=''

finish() {
  exit_code=$?
  if [[ -n "$notes_file" ]]; then
    rm -f -- "$notes_file"
  fi
  if ((exit_code != 0)); then
    printf 'release: stopped; manual recovery is required before another release attempt\n' >&2
  fi
  exit "$exit_code"
}
trap finish EXIT

fail() {
  printf 'release: %s\n' "$*" >&2
  return 1
}

require_selected_version() {
  name=$1
  expected=$2
  selected=$(asdf current "$name" | awk -v name="$name" '$1 == name { print $2; exit }')
  [[ "$selected" == "$expected" ]] || fail "$name $expected must be selected; found ${selected:-nothing}"
}

require_clean_main() {
  [[ "$(git branch --show-current)" == 'main' ]] || fail 'the current branch must be main'
  status_output=''
  status_result=0
  status_output=$(git status --porcelain --untracked-files=all) || status_result=$?
  [[ "$status_result" == '0' ]] || fail 'could not inspect the working tree'
  [[ -z "$status_output" ]] || fail 'the working tree must be clean'
}

require_artifacts_absent() {
  local_tag_status=0
  git show-ref --verify --quiet "refs/tags/$tag" || local_tag_status=$?
  case "$local_tag_status" in
    0) fail "local tag $tag already exists" ;;
    1) ;;
    *) fail "could not verify that local tag $tag is absent" ;;
  esac

  remote_tag_status=0
  git ls-remote --exit-code --tags origin "refs/tags/$tag" >/dev/null 2>&1 || remote_tag_status=$?
  case "$remote_tag_status" in
    0) fail "remote tag $tag already exists" ;;
    2) ;;
    *) fail "could not verify that remote tag $tag is absent" ;;
  esac

  hex_output=''
  if hex_output=$(mix hex.info "$package" "$version" 2>&1); then
    fail "Hex version $package $version already exists"
  fi
  [[ "$hex_output" == "No release with name $package $version" ]] ||
    fail "could not verify that Hex version $package $version is absent"

  github_output=''
  if github_output=$(gh release view "$tag" --repo "$repository" 2>&1); then
    fail "GitHub release $tag already exists"
  fi
  [[ "$github_output" == 'release not found' ]] ||
    fail "could not verify that GitHub release $tag is absent"
}

[[ $# -eq 0 ]] || fail 'no arguments are accepted'
[[ -z "${CI:-}" ]] || fail 'CI must not be set'

command -v asdf >/dev/null || fail 'asdf 0.16.5 is required'
[[ "$(asdf --version)" == 'asdf version 0.16.5' ]] || fail "asdf 0.16.5 is required; found $(asdf --version)"
require_selected_version erlang 27.0
require_selected_version elixir 1.20.0-otp-27
require_selected_version java 'temurin-17.0.20+8'
require_selected_version just 1.54.0
require_selected_version apalache 0.58.3
require_selected_version github-cli 2.87.3

require_clean_main
origin_url=$(git remote get-url origin)
case "$origin_url" in
  https://github.com/kokjinsam/apalachex | https://github.com/kokjinsam/apalachex.git | git@github.com:kokjinsam/apalachex.git) ;;
  *) fail "origin must be GitHub repository $repository; found $origin_url" ;;
esac
git fetch origin main
origin_url=$(git remote get-url origin)
case "$origin_url" in
  https://github.com/kokjinsam/apalachex | https://github.com/kokjinsam/apalachex.git | git@github.com:kokjinsam/apalachex.git) ;;
  *) fail "origin must be GitHub repository $repository; found $origin_url" ;;
esac
git fetch origin --tags
release_sha=$(git rev-parse HEAD)
readonly release_sha
origin_sha=$(git rev-parse origin/main)
[[ "$release_sha" == "$origin_sha" ]] || fail 'HEAD must equal origin/main'

version=$(mix eval --no-compile --no-deps-check --no-archives-check 'IO.write(Mix.Project.config()[:version])')
elixir -e '
  version = List.first(System.argv())

  case Version.parse(version) do
    {:ok, parsed} ->
      canonical = "#{parsed.major}.#{parsed.minor}.#{parsed.patch}"

      if parsed.pre != [] or parsed.build != nil or version != canonical do
        System.halt(1)
      end

    :error ->
      System.halt(1)
  end
' "$version" || fail "Mix project version must be stable X.Y.Z; found $version"
tag="v$version"

escaped_version=${version//./\\.}
heading_count=$(grep -Ec "^## $escaped_version - [0-9]{4}-[0-9]{2}-[0-9]{2}$" CHANGELOG.md || true)
[[ "$heading_count" == '1' ]] || fail "CHANGELOG.md must contain exactly one dated heading for $version"
changelog_heading=$(grep -E "^## $escaped_version - [0-9]{4}-[0-9]{2}-[0-9]{2}$" CHANGELOG.md)
changelog_date=${changelog_heading##* - }
elixir -e '
  case Date.from_iso8601(List.first(System.argv())) do
    {:ok, _date} -> :ok
    {:error, _reason} -> System.halt(1)
  end
' "$changelog_date" || fail "CHANGELOG.md date for $version must be a valid calendar date"

mix hex.user whoami >/dev/null 2>&1
gh auth status --hostname github.com >/dev/null 2>&1
github_repository=$(gh repo view "$repository" --json nameWithOwner --jq .nameWithOwner)
[[ "$github_repository" == "$repository" ]] || fail "GitHub repository must be $repository; found $github_repository"

require_artifacts_absent

notes_file=$(mktemp "${TMPDIR:-/tmp}/apalachex-release-notes.XXXXXX")
awk -v heading="$changelog_heading" '
  $0 == heading { in_section = 1; next }
  in_section && /^##([[:space:]]|$)/ { exit }
  in_section && /^[[:space:]]*$/ {
    if (has_body) {
      blank_lines = blank_lines $0 ORS
    }
    next
  }
  in_section {
    if (has_body) {
      printf "%s", blank_lines
    }
    print
    has_body = 1
    blank_lines = ""
  }
' CHANGELOG.md >"$notes_file"
[[ -s "$notes_file" ]] || fail "the $version changelog section must contain a body"

just check
just docs
just package-audit
just consumer-smoke
just test-apalache
mix hex.publish --dry-run

require_clean_main
origin_url=$(git remote get-url origin)
case "$origin_url" in
  https://github.com/kokjinsam/apalachex | https://github.com/kokjinsam/apalachex.git | git@github.com:kokjinsam/apalachex.git) ;;
  *) fail "origin must be GitHub repository $repository; found $origin_url" ;;
esac
git fetch origin main
head_sha=$(git rev-parse HEAD)
origin_sha=$(git rev-parse origin/main)
[[ "$head_sha" == "$release_sha" ]] || fail "HEAD must still equal release SHA $release_sha"
[[ "$origin_sha" == "$release_sha" ]] || fail "origin/main must still equal release SHA $release_sha"
require_artifacts_absent

printf '\nRelease summary\n'
printf '  Version:    %s\n' "$version"
printf '  Tag:        %s\n' "$tag"
printf '  SHA:        %s\n' "$release_sha"
printf '  Package:    %s\n' "$package"
printf '  Repository: %s\n' "$repository"
printf '\nExternal actions\n'
printf '  1. Create annotated local tag %s at %s\n' "$tag" "$release_sha"
printf '  2. Publish %s %s to Hex\n' "$package" "$version"
printf '  3. Push only %s to origin\n' "$tag"
printf '  4. Create GitHub release %s\n' "$tag"
printf '\nType %s to continue: ' "$tag"
IFS= read -r confirmation
[[ "$confirmation" == "$tag" ]] || fail "confirmation did not exactly match $tag"

require_clean_main
origin_url=$(git remote get-url origin)
case "$origin_url" in
  https://github.com/kokjinsam/apalachex | https://github.com/kokjinsam/apalachex.git | git@github.com:kokjinsam/apalachex.git) ;;
  *) fail "origin must be GitHub repository $repository; found $origin_url" ;;
esac
git fetch origin main
head_sha=$(git rev-parse HEAD)
origin_sha=$(git rev-parse origin/main)
[[ "$head_sha" == "$release_sha" ]] || fail "HEAD must still equal release SHA $release_sha"
[[ "$origin_sha" == "$release_sha" ]] || fail "origin/main must still equal release SHA $release_sha"
require_artifacts_absent

git tag --annotate --message "Release $tag" "$tag" "$release_sha"
mix hex.publish --yes
git push origin "refs/tags/$tag:refs/tags/$tag"
gh release create "$tag" \
  --repo "$repository" \
  --verify-tag \
  --title "v$version" \
  --notes-file "$notes_file"

mix hex.info "$package" "$version" >/dev/null
remote_tag_sha=$(git ls-remote origin "refs/tags/$tag^{}" | awk 'NR == 1 { print $1 }')
[[ "$remote_tag_sha" == "$release_sha" ]] || fail "remote tag $tag does not resolve to $release_sha"
released_tag=$(gh release view "$tag" --repo "$repository" --json tagName --jq .tagName)
[[ "$released_tag" == "$tag" ]] || fail "GitHub release $tag could not be verified"

printf 'release: published %s %s from %s and created %s\n' "$package" "$version" "$release_sha" "$tag"
