#!/bin/sh

if [ "$1" = "login" ] && [ "$2" = "status" ]; then
  if [ -n "${CHOUDAIMA_FAKE_AUTH_LOG:-}" ]; then
    printf '%s\n' "check" >> "$CHOUDAIMA_FAKE_AUTH_LOG"
  fi
  if [ -n "${CHOUDAIMA_FAKE_AUTH_DELAY:-}" ]; then
    sleep "$CHOUDAIMA_FAKE_AUTH_DELAY"
  fi
  case "${CHOUDAIMA_FAKE_AUTH:-chatgpt}" in
    chatgpt)
      echo "Logged in using ChatGPT"
      exit 0
      ;;
    apikey)
      echo "Logged in using an API key"
      exit 0
      ;;
    *)
      echo "Not logged in" >&2
      exit 1
      ;;
  esac
fi

if [ "$1" != "exec" ]; then
  echo "unexpected fake Codex command: $*" >&2
  exit 64
fi

payload=$(sed -n '1p')
request_id=$(printf '%s\n' "$payload" | sed -n 's/.*"request_id":\([0-9][0-9]*\).*/\1/p')
if [ -z "$request_id" ]; then
  echo "fake Codex could not find request_id" >&2
  exit 65
fi

if [ -n "${CHOUDAIMA_FAKE_RESPONSES_DIR:-}" ]; then
  printf '%s\n' "$payload" > "$CHOUDAIMA_FAKE_RESPONSES_DIR/$request_id.stdin"
  printf '%s\n' "$@" > "$CHOUDAIMA_FAKE_RESPONSES_DIR/$request_id.args"

  if [ -f "$CHOUDAIMA_FAKE_RESPONSES_DIR/$request_id.delay" ]; then
    delay=$(sed -n '1p' "$CHOUDAIMA_FAKE_RESPONSES_DIR/$request_id.delay")
    sleep "$delay"
  fi

  if [ -f "$CHOUDAIMA_FAKE_RESPONSES_DIR/$request_id.exit" ]; then
    status=$(sed -n '1p' "$CHOUDAIMA_FAKE_RESPONSES_DIR/$request_id.exit")
    echo "forced fake Codex failure" >&2
    exit "$status"
  fi

  if [ -f "$CHOUDAIMA_FAKE_RESPONSES_DIR/$request_id.json" ]; then
    sed -n '1,$p' "$CHOUDAIMA_FAKE_RESPONSES_DIR/$request_id.json"
    exit 0
  fi
fi

printf '%s\n' "${CHOUDAIMA_FAKE_RESPONSE:-{\"replacement_lines\":[\"replacement\"]}}"
