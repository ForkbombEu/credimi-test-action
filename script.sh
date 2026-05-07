#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${CREDIMI_APK_URL}" && -z "${CREDIMI_APK_FILE}" ]]; then
  echo "Error: exactly one of 'apk-url' or 'apk-file' must be provided." >&2
  exit 1
fi

if [[ -n "${CREDIMI_APK_URL}" && -n "${CREDIMI_APK_FILE}" ]]; then
  echo "Error: 'apk-url' and 'apk-file' are mutually exclusive." >&2
  exit 1
fi

runner_id="${CREDIMI_RUNNER_ID:-}"

case "${CREDIMI_RUNNER_TYPE}" in
  android_emulator|redroid|android_phone|ios_simulator)
    ;;
  *)
    echo "Error: 'runner-type' must be one of: android_emulator, redroid, android_phone, ios_simulator." >&2
    exit 1
    ;;
esac

wallet_run_endpoint="${CREDIMI_API_BASE_URL%/}/api/pipeline/run-wallet-apk"

github_context="${GITHUB_CONTEXT:-}"
if [[ -z "${github_context}" ]]; then
  github_context="{}"
fi

metadata="$(
  jq -c \
    '
    del(
      .token,
      .event.repository.owner.email,
      .event.sender.email,
      .event.pusher.email
    )
    ' <<< "${github_context}"
)"

if [[ -n "${CREDIMI_APK_URL}" ]]; then
  payload="$(jq -n \
    --arg pipeline_identifier "${CREDIMI_PIPELINE_ID}" \
    --arg runner_type "${CREDIMI_RUNNER_TYPE}" \
    --arg runner_id "${runner_id}" \
    --arg apk_url "${CREDIMI_APK_URL}" \
    --argjson metadata "${metadata}" \
    '
    {
      pipeline_identifier: $pipeline_identifier,
      runner_type: $runner_type,
      apk_url: $apk_url,
      metadata: $metadata
    }
    + if $runner_id == "" then {} else { runner_id: $runner_id } end'
  )"

  response="$(curl --fail-with-body --silent --show-error \
    --request POST "${wallet_run_endpoint}" \
    --header "Credimi-Api-Key: ${CREDIMI_API_KEY}" \
    --header "Content-Type: application/json" \
    --data "${payload}")"
else
  if [[ ! -f "${CREDIMI_APK_FILE}" ]]; then
    echo "Error: APK file does not exist: ${CREDIMI_APK_FILE}" >&2
    exit 1
  fi

  curl_args=(
    --fail-with-body
    --silent
    --show-error
    --request POST "${wallet_run_endpoint}"
    --header "Credimi-Api-Key: ${CREDIMI_API_KEY}"
    --form "pipeline_identifier=${CREDIMI_PIPELINE_ID}"
    --form "runner_type=${CREDIMI_RUNNER_TYPE}"
    --form "metadata=${metadata};type=application/json"
    --form "apk_file=@${CREDIMI_APK_FILE}"
  )

  if [[ -n "${runner_id}" ]]; then
    curl_args+=(--form "runner_id=${runner_id}")
  fi

  response="$(curl "${curl_args[@]}")"
fi

echo "${response}"
