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
    --arg runner_id "${CREDIMI_RUNNER_ID}" \
    --arg apk_url "${CREDIMI_APK_URL}" \
    --argjson metadata "${metadata}" \
    '
    {
      pipeline_identifier: $pipeline_identifier,
      runner_id: $runner_id,
      apk_url: $apk_url,
      metadata: $metadata
    }'
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
    --form "runner_id=${CREDIMI_RUNNER_ID}"
    --form "metadata=${metadata};type=application/json"
    --form "apk_file=@${CREDIMI_APK_FILE}"
  )

  response="$(curl "${curl_args[@]}")"
fi

echo "${response}"
