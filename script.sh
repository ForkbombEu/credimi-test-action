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

endpoint="${CREDIMI_API_BASE_URL%/}/api/pipeline/run-wallet-apk"

if [[ -n "${CREDIMI_APK_URL}" ]]; then
  payload="$(jq -n \
    --arg pipeline_identifier "${CREDIMI_PIPELINE_ID}" \
    --arg commit_sha "${COMMIT_SHA}" \
    --arg runner_id "${CREDIMI_RUNNER_ID}" \
    --arg apk_url "${CREDIMI_APK_URL}" \
    '
    {
      pipeline_identifier: $pipeline_identifier,
      runner_id: $runner_id
      commit_sha: $commit_sha,
      apk_url: $apk_url
    }'
  )"

  curl --fail-with-body --silent --show-error \
    --request POST "${endpoint}" \
    --header "Credimi-Api-Key: ${CREDIMI_API_KEY}" \
    --header "Content-Type: application/json" \
    --data "${payload}"
else
  if [[ ! -f "${CREDIMI_APK_FILE}" ]]; then
    echo "Error: APK file does not exist: ${CREDIMI_APK_FILE}" >&2
    exit 1
  fi

  curl_args=(
    --fail-with-body
    --silent
    --show-error
    --request POST "${endpoint}"
    --header "Credimi-Api-Key: ${CREDIMI_API_KEY}"
    --form "pipeline_identifier=${CREDIMI_PIPELINE_ID}"
    --form "runner_id=${CREDIMI_RUNNER_ID}"
    --form "commit_sha=${COMMIT_SHA}"
    --form "apk_file=@${CREDIMI_APK_FILE}"
  )

  curl "${curl_args[@]}"
fi