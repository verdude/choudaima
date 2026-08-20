#!/bin/sh
set -eu

cd "$(dirname "$0")/.."
if ! vim -Nu NONE -n -i NONE -es -S test/test_choudaima.vim; then
  if [ -f test/test-errors.log ]; then
    sed -n '1,240p' test/test-errors.log >&2
  fi
  exit 1
fi
