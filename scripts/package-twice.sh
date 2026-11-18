#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Packages parsec-html twice, from two fresh checkouts of one commit, and
# fails unless the two .crate files are the same byte for byte. It's how a
# release is built (release.yml), and how anyone can check one: run it at
# the release's tag and compare the printed SHA-256 with the release's.
#
#   scripts/package-twice.sh [COMMIT] [OUT]
#
# COMMIT defaults to HEAD and must be committed: cargo records the commit
# and whether the tree was dirty in the package. Each build gets a worktree
# of its own, which works in a shallow clone too, and no submodules; the
# first checks out with umask 022 and the second with 077, so file modes
# from a checkout can't leak into the package. OUT, when given, gets the
# .crate.
set -euo pipefail

commit=$(git rev-parse --verify "${1:-HEAD}^{commit}")
out=${2:-}
repo=$(git rev-parse --show-toplevel)
work=$(mktemp -d)
trap 'git -C "$repo" worktree remove --force "$work/a" 2>/dev/null; git -C "$repo" worktree remove --force "$work/b" 2>/dev/null; rm -rf "$work"' EXIT

# The commit's time, so anything that reads it gets the same value twice.
SOURCE_DATE_EPOCH=$(git log -1 --format=%ct "$commit")
export SOURCE_DATE_EPOCH

build() { # name umask
	(
		umask "$2"
		git -C "$repo" worktree add --quiet --detach "$work/$1" "$commit"
	)
	cargo package --quiet --manifest-path "$work/$1/Cargo.toml" -p parsec-html \
		--locked --no-verify --target-dir "$work/target-$1"
}

build a 022
build b 077
crate=$(cd "$work/target-a/package" && ls -- *.crate)
sum_a=$(sha256sum "$work/target-a/package/$crate" | cut -d' ' -f1)
sum_b=$(sha256sum "$work/target-b/package/$crate" | cut -d' ' -f1)
if [ "$sum_a" != "$sum_b" ]; then
	echo "$crate differs between two builds of $commit:" >&2
	echo "  $sum_a" >&2
	echo "  $sum_b" >&2
	exit 1
fi
if [ -n "$out" ]; then
	mkdir -p "$out"
	cp "$work/target-a/package/$crate" "$out/"
fi
echo "$sum_a  $crate"
