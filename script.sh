#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${script_dir}/credimi-utils.sh"

test_target="$(validate_target_inputs)"

if is_blank "${CREDIMI_PIPELINE_IDS:-}"; then
  err "at least one pipeline id must be provided in 'pipeline-ids'."
fi

has_runner_types=false
has_runner_ids=false

if ! is_blank "${CREDIMI_RUNNER_TYPES:-}"; then
  has_runner_types=true
fi

if ! is_blank "${CREDIMI_RUNNER_IDS:-}"; then
  has_runner_ids=true
fi

if [[ "${test_target}" == "wallet" && "${has_runner_types}" == false && "${has_runner_ids}" == false ]]; then
  err "exactly one of 'runner-types' or 'runner-ids' must be provided."
fi

if [[ "${has_runner_types}" == true && "${has_runner_ids}" == true ]]; then
  err "'runner-types' and 'runner-ids' are mutually exclusive."
fi

declare -a pipeline_ids=()
while IFS= read -r pipeline_id || [[ -n "${pipeline_id}" ]]; do
  pipeline_id="$(trim "${pipeline_id}")"
  if [[ -n "${pipeline_id}" ]]; then
    pipeline_ids+=("${pipeline_id}")
  fi
done <<< "${CREDIMI_PIPELINE_IDS}"

if [[ "${#pipeline_ids[@]}" -eq 0 ]]; then
  err "at least one pipeline id must be provided in 'pipeline-ids'."
fi

declare -a run_keys=()
declare -A run_seen=()
declare -A run_pipeline_ids=()
declare -A run_runner_types=()
declare -A run_runner_ids=()
allow_pipeline_only_runs=false

if [[ "${test_target}" == "issuer" || "${test_target}" == "verifier" ]]; then
  allow_pipeline_only_runs=true
fi

if [[ "${has_runner_types}" == true ]]; then
  while IFS= read -r runner_type || [[ -n "${runner_type}" ]]; do
    runner_type="$(trim "${runner_type}")"
    if [[ -z "${runner_type}" ]]; then
      continue
    fi

    if ! is_valid_runner_type "${runner_type}"; then
      err "runner type must be one of: android_emulator, redroid, android_phone, ios_simulator."
    fi

    for pipeline_id in "${pipeline_ids[@]}"; do
      add_run "${pipeline_id}" "${runner_type}"
    done
  done <<< "${CREDIMI_RUNNER_TYPES}"
elif [[ "${has_runner_ids}" == true ]]; then
  while IFS= read -r runner_spec || [[ -n "${runner_spec}" ]]; do
    runner_spec="$(trim "${runner_spec}")"
    if [[ -z "${runner_spec}" ]]; then
      continue
    fi

    parse_runner_spec "${runner_spec}" runner_id runner_type
    if [[ -z "${runner_id}" ]]; then
      err "runner ids must be formatted as 'runner-id/runner-type'."
    fi

    for pipeline_id in "${pipeline_ids[@]}"; do
      add_run "${pipeline_id}" "${runner_type}" "${runner_id}"
    done
  done <<< "${CREDIMI_RUNNER_IDS}"
else
  for pipeline_id in "${pipeline_ids[@]}"; do
    add_run "${pipeline_id}"
  done
fi

if ! is_blank "${CREDIMI_EXTRA_RUNS:-}"; then
  add_runs_from_lines "${CREDIMI_EXTRA_RUNS}" "extra-runs" "add" "${allow_pipeline_only_runs}"
fi

if ! is_blank "${CREDIMI_EXCLUDE_RUNS:-}"; then
  add_runs_from_lines "${CREDIMI_EXCLUDE_RUNS}" "exclude-runs" "remove" "${allow_pipeline_only_runs}"
fi

if [[ "$(active_run_count)" -eq 0 ]]; then
  err "no pipeline runs remain after applying 'exclude-runs'."
fi

api_base_url="${CREDIMI_API_BASE_URL:-https://credimi.io}"
api_base_url="${api_base_url%/}"
metadata="$(build_metadata)"
credential_ids="[]"
use_case_ids="[]"

if [[ "${test_target}" == "issuer" ]]; then
  credential_ids="$(json_array_from_lines "${CREDIMI_CREDENTIAL_IDS}")"
elif [[ "${test_target}" == "verifier" ]]; then
  use_case_ids="$(json_array_from_lines "${CREDIMI_USE_CASE_IDS}")"
fi

run_curl() {
  local response
  local status

  if response="$(curl "$@")"; then
    printf '%s' "${response}"
    return 0
  else
    status=$?
  fi

  if [[ -n "${response}" ]]; then
    printf 'Credimi API error response:\n%s\n' "${response}" >&2
  fi

  return "${status}"
}

for key in "${run_keys[@]}"; do
  if [[ -z "${run_seen[${key}]:-}" ]]; then
    continue
  fi

  pipeline_id="${run_pipeline_ids[${key}]}"
  runner_type="${run_runner_types[${key}]}"
  runner_id="${run_runner_ids[${key}]}"

  if [[ "${test_target}" == "issuer" ]]; then
    payload="$(jq -n \
      --arg pipeline_identifier "${pipeline_id}" \
      --arg runner_type "${runner_type}" \
      --arg runner_id "${runner_id}" \
      --arg issuer_url "${CREDIMI_ISSUER_URL}" \
      --argjson credential_ids "${credential_ids}" \
      --argjson metadata "${metadata}" \
      '
      {
        pipeline_identifier: $pipeline_identifier,
        issuer_url: $issuer_url,
        credential_ids: $credential_ids,
        metadata: $metadata
      }
      + if $runner_type == "" then {} else { runner_type: $runner_type } end
      + if $runner_id == "" then {} else { runner_id: $runner_id } end'
    )"

    response="$(run_curl --fail-with-body --silent --show-error \
      --request POST "${api_base_url}/api/pipeline/run-issuer" \
      --header "Credimi-Api-Key: ${CREDIMI_API_KEY}" \
      --header "Content-Type: application/json" \
      --data "${payload}")"
  elif [[ "${test_target}" == "verifier" ]]; then
    payload="$(jq -n \
      --arg pipeline_identifier "${pipeline_id}" \
      --arg runner_type "${runner_type}" \
      --arg runner_id "${runner_id}" \
      --arg verifier_url "${CREDIMI_VERIFIER_URL}" \
      --argjson use_case_ids "${use_case_ids}" \
      --argjson metadata "${metadata}" \
      '
      {
        pipeline_identifier: $pipeline_identifier,
        verifier_url: $verifier_url,
        use_case_ids: $use_case_ids,
        metadata: $metadata
      }
      + if $runner_type == "" then {} else { runner_type: $runner_type } end
      + if $runner_id == "" then {} else { runner_id: $runner_id } end'
    )"

    response="$(run_curl --fail-with-body --silent --show-error \
      --request POST "${api_base_url}/api/pipeline/run-verifier" \
      --header "Credimi-Api-Key: ${CREDIMI_API_KEY}" \
      --header "Content-Type: application/json" \
      --data "${payload}")"
  elif ! is_blank "${CREDIMI_APK_URL:-}"; then
    payload="$(jq -n \
      --arg pipeline_identifier "${pipeline_id}" \
      --arg runner_type "${runner_type}" \
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

    response="$(run_curl --fail-with-body --silent --show-error \
      --request POST "${api_base_url}/api/pipeline/run-wallet-apk" \
      --header "Credimi-Api-Key: ${CREDIMI_API_KEY}" \
      --header "Content-Type: application/json" \
      --data "${payload}")"
  else
    curl_args=(
      --fail-with-body
      --silent
      --show-error
      --request POST "${api_base_url}/api/pipeline/run-wallet-apk"
      --header "Credimi-Api-Key: ${CREDIMI_API_KEY}"
      --form "pipeline_identifier=${pipeline_id}"
      --form "runner_type=${runner_type}"
      --form "metadata=${metadata};type=application/json"
      --form "apk_file=@${CREDIMI_APK_FILE}"
    )

    if [[ -n "${runner_id}" ]]; then
      curl_args+=(--form "runner_id=${runner_id}")
    fi

    response="$(run_curl "${curl_args[@]}")"
  fi

  echo "${response}"
done
