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
  commit_sha="${GITHUB_SHA:-}"
  comments_url="${GITHUB_API_URL:-https://api.github.com}/repos/${GITHUB_REPOSITORY}/issues/${pr_number}/comments"
  comment_url="${run_url:-$pipeline_url}"
  comment_marker="<!-- credimi-test-action -->"
  new_line="- \`${commit_sha}\`: [pipeline execution](${comment_url})"

  if [[ -n "${pr_number}" ]]; then
    # Look for an existing comment from this action, paginating through all pages
    existing_comment=""
    page=1
    max_pages=10
    while [[ -z "${existing_comment}" && "${page}" -le "${max_pages}" ]]; do
      page_comments="$(curl --fail-with-body --silent --show-error \
          --request GET "${comments_url}?per_page=100&page=${page}" \
          --header "Authorization: Bearer ${GITHUB_TOKEN}" \
          --header "Accept: application/vnd.github+json" \
          --header "X-GitHub-Api-Version: 2022-11-28")"
      page_count="$(jq 'length' <<< "${page_comments}")"
      if [[ "${page_count}" == "0" ]]; then
        break
      fi
      existing_comment="$(jq -r --arg marker "${comment_marker}" \
          'map(select(.body | startswith($marker))) | first // empty' <<< "${page_comments}")"
      if [[ "${page_count}" -lt 100 ]]; then
        break
      fi
      ((page++))
    done

    if [[ -n "${existing_comment}" ]]; then
      existing_body="$(jq -r '.body' <<< "${existing_comment}")"
      comment_id="$(jq -r '.id' <<< "${existing_comment}")"
      updated_body="${existing_body}
${new_line}"
      issue_comment_url="${GITHUB_API_URL:-https://api.github.com}/repos/${GITHUB_REPOSITORY}/issues/comments/${comment_id}"
      jq -n --arg body "${updated_body}" '{body: $body}' \
        | curl --fail-with-body --silent --show-error \
            --request PATCH "${issue_comment_url}" \
            --header "Authorization: Bearer ${GITHUB_TOKEN}" \
            --header "Accept: application/vnd.github+json" \
            --header "X-GitHub-Api-Version: 2022-11-28" \
            --header "Content-Type: application/json" \
            --data @-
    else
      comment_body="${comment_marker}
## 🧪 Credimi Pipeline Executions
${new_line}"
      jq -n --arg body "${comment_body}" '{body: $body}' \
        | curl --fail-with-body --silent --show-error \
            --request POST "${comments_url}" \
            --header "Authorization: Bearer ${GITHUB_TOKEN}" \
            --header "Accept: application/vnd.github+json" \
            --header "X-GitHub-Api-Version: 2022-11-28" \
            --header "Content-Type: application/json" \
            --data @-
    fi
  fi
fi
