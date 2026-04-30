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
queue_endpoint="${CREDIMI_API_BASE_URL%/}/api/pipeline/queue"

github_context="${GITHUB_CONTEXT:-}"
if [[ -z "${github_context}" ]]; then
  github_context="{}"
fi

metadata="$(
  jq -c \
    --arg token "${GITHUB_TOKEN:-}" \
    '
    if $token == "" then
      .
    else
      walk(if type == "string" then split($token) | join("***") else . end)
    end
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

ticket_id="$(jq -r '.ticket_id // empty' <<< "${response}")"
pipeline_url="$(jq -r '.pipeline_url // empty' <<< "${response}")"
run_url=""

if [[ -n "${ticket_id}" ]]; then
  for attempt in {1..5}; do
    if queue_response="$(curl --fail-with-body --silent --show-error \
        --get \
        --data-urlencode "runner_ids=${CREDIMI_RUNNER_ID}" \
        --request GET "${queue_endpoint}/${ticket_id}" \
        --header "Credimi-Api-Key: ${CREDIMI_API_KEY}")"; then
      status="$(jq -r '.status // empty' <<< "${queue_response}")"
      if [[ "${status}" == "running" ]]; then
        run_url="$(jq -r '.run_url // empty' <<< "${queue_response}")"
        break
      fi
    fi

    if [[ "${attempt}" -lt 5 ]]; then
      sleep 10
    fi
  done
fi

if [[ "${GITHUB_EVENT_NAME:-}" == "pull_request"* ]]; then
  pr_number="$(jq -r '.pull_request.number // empty' "${GITHUB_EVENT_PATH}")"
  comments_url="${GITHUB_API_URL:-https://api.github.com}/repos/${GITHUB_REPOSITORY}/issues/${pr_number}/comments"
  commit_sha="$(jq -r --arg fallback "${GITHUB_SHA:-}" '.pull_request.head.sha // .sha // $fallback // empty' "${GITHUB_EVENT_PATH}")"
  short_commit_sha="${commit_sha:0:7}"
  comment_url="${run_url:-$pipeline_url}"

  if [[ -n "${pr_number}" && -n "${commit_sha}" ]]; then
    comments_response="$(curl --fail-with-body --silent --show-error \
      --get \
      --data-urlencode "per_page=100" \
      --request GET "${comments_url}" \
      --header "Authorization: Bearer ${GITHUB_TOKEN}" \
      --header "Accept: application/vnd.github+json" \
      --header "X-GitHub-Api-Version: 2022-11-28")"

    marker="<!-- credimi-test-action -->"
    existing_body="$(jq -r --arg marker "${marker}" 'map(select(.body | contains($marker))) | last | .body // empty' <<< "${comments_response}")"
    update_url="$(jq -r --arg marker "${marker}" 'map(select(.body | contains($marker))) | last | .url // empty' <<< "${comments_response}")"

    comment_body="$(
      jq -rn \
        --arg existing_body "${existing_body}" \
        --arg marker "${marker}" \
        --arg commit_sha "${commit_sha}" \
        --arg short_commit_sha "${short_commit_sha}" \
        --arg comment_url "${comment_url}" \
        '
        def run_lines:
          $existing_body
          | split("\n")
          | map(select(startswith("- `") and (contains("credimi-run:" + $commit_sha) | not)));

        (
          ["Track your Credimi pipeline runs:", ""]
          + (run_lines + ["- `" + $short_commit_sha + "`: [pipeline execution](" + $comment_url + ") <!-- credimi-run:" + $commit_sha + " -->"])
          + ["", $marker]
        ) | join("\n")
        '
    )"

    request_method="POST"
    request_url="${comments_url}"
    if [[ -n "${update_url}" ]]; then
      request_method="PATCH"
      request_url="${update_url}"
    fi

    jq -n --arg body "${comment_body}" '{body: $body}' \
      | curl --fail-with-body --silent --show-error \
        --request "${request_method}" "${request_url}" \
        --header "Authorization: Bearer ${GITHUB_TOKEN}" \
        --header "Accept: application/vnd.github+json" \
        --header "X-GitHub-Api-Version: 2022-11-28" \
        --header "Content-Type: application/json" \
        --data @-
  fi
fi
