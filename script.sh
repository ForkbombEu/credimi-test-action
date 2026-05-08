#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${CREDIMI_APK_URL:-}" && -z "${CREDIMI_APK_FILE:-}" ]]; then
  echo "Error: exactly one of 'apk-url' or 'apk-file' must be provided." >&2
  exit 1
fi

if [[ -n "${CREDIMI_APK_URL:-}" && -n "${CREDIMI_APK_FILE:-}" ]]; then
  echo "Error: 'apk-url' and 'apk-file' are mutually exclusive." >&2
  exit 1
fi

is_blank() {
  [[ -z "${1//[[:space:]]/}" ]]
}

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "${value}"
}

is_valid_runner_type() {
  case "$1" in
    android_emulator|redroid|android_phone|ios_simulator)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

parse_runner_spec() {
  local runner_spec="$1"
  local -n out_runner_id="$2"
  local -n out_runner_type="$3"

  out_runner_id=""
  out_runner_type=""

  if is_valid_runner_type "${runner_spec}"; then
    out_runner_type="${runner_spec}"
    return 0
  fi

  if [[ "${runner_spec}" != */* ]]; then
    echo "Error: runner must be a runner type or formatted as 'runner-id/runner-type': ${runner_spec}" >&2
    exit 1
  fi

  out_runner_id="${runner_spec%/*}"
  out_runner_type="${runner_spec##*/}"

  if [[ -z "${out_runner_id}" ]]; then
    echo "Error: runner id cannot be empty in runner spec: ${runner_spec}" >&2
    exit 1
  fi

  if ! is_valid_runner_type "${out_runner_type}"; then
    echo "Error: runner type must be one of: android_emulator, redroid, android_phone, ios_simulator." >&2
    exit 1
  fi
}

declare -a run_keys=()
declare -A run_seen=()
declare -A run_pipeline_ids=()
declare -A run_runner_types=()
declare -A run_runner_ids=()

make_run_key() {
  local pipeline_id="$1"
  local runner_type="$2"
  local runner_id="$3"

  printf '%s\t%s\t%s' "${pipeline_id}" "${runner_type}" "${runner_id}"
}

add_run() {
  local pipeline_id="$1"
  local runner_type="$2"
  local runner_id="${3:-}"
  local key

  if [[ -z "${pipeline_id}" ]]; then
    echo "Error: pipeline id cannot be empty." >&2
    exit 1
  fi

  if ! is_valid_runner_type "${runner_type}"; then
    echo "Error: runner type must be one of: android_emulator, redroid, android_phone, ios_simulator." >&2
    exit 1
  fi

  key="$(make_run_key "${pipeline_id}" "${runner_type}" "${runner_id}")"
  if [[ -n "${run_seen[${key}]:-}" ]]; then
    return 0
  fi

  run_seen["${key}"]=1
  run_pipeline_ids["${key}"]="${pipeline_id}"
  run_runner_types["${key}"]="${runner_type}"
  run_runner_ids["${key}"]="${runner_id}"
  run_keys+=("${key}")
}

remove_run() {
  local pipeline_id="$1"
  local runner_type="$2"
  local runner_id="${3:-}"
  local key

  key="$(make_run_key "${pipeline_id}" "${runner_type}" "${runner_id}")"
  unset "run_seen[${key}]"
}

add_runs_from_lines() {
  local lines="$1"
  local source_name="$2"
  local mode="$3"
  local line pipeline_id runner_spec extra runner_id runner_type

  while IFS= read -r line || [[ -n "${line}" ]]; do
    line="$(trim "${line}")"
    if [[ -z "${line}" ]]; then
      continue
    fi

    read -r pipeline_id runner_spec extra <<< "${line}"
    if [[ -z "${pipeline_id}" || -z "${runner_spec}" || -n "${extra:-}" ]]; then
      echo "Error: each ${source_name} line must contain exactly: '<pipeline-id> <runner-type|runner-id/runner-type>'." >&2
      exit 1
    fi

    parse_runner_spec "${runner_spec}" runner_id runner_type
    if [[ "${mode}" == "add" ]]; then
      add_run "${pipeline_id}" "${runner_type}" "${runner_id}"
    else
      remove_run "${pipeline_id}" "${runner_type}" "${runner_id}"
    fi
  done <<< "${lines}"
}

if is_blank "${CREDIMI_PIPELINE_IDS:-}"; then
  echo "Error: at least one pipeline id must be provided in 'pipeline-ids'." >&2
  exit 1
fi

has_runner_types=false
has_runner_ids=false

if ! is_blank "${CREDIMI_RUNNER_TYPES:-}"; then
  has_runner_types=true
fi

if ! is_blank "${CREDIMI_RUNNER_IDS:-}"; then
  has_runner_ids=true
fi

if [[ "${has_runner_types}" == false && "${has_runner_ids}" == false ]]; then
  echo "Error: exactly one of 'runner-types' or 'runner-ids' must be provided." >&2
  exit 1
fi

if [[ "${has_runner_types}" == true && "${has_runner_ids}" == true ]]; then
  echo "Error: 'runner-types' and 'runner-ids' are mutually exclusive." >&2
  exit 1
fi

declare -a pipeline_ids=()
while IFS= read -r pipeline_id || [[ -n "${pipeline_id}" ]]; do
  pipeline_id="$(trim "${pipeline_id}")"
  if [[ -n "${pipeline_id}" ]]; then
    pipeline_ids+=("${pipeline_id}")
  fi
done <<< "${CREDIMI_PIPELINE_IDS}"

if [[ "${#pipeline_ids[@]}" -eq 0 ]]; then
  echo "Error: at least one pipeline id must be provided in 'pipeline-ids'." >&2
  exit 1
fi

if [[ "${has_runner_types}" == true ]]; then
  while IFS= read -r runner_type || [[ -n "${runner_type}" ]]; do
    runner_type="$(trim "${runner_type}")"
    if [[ -z "${runner_type}" ]]; then
      continue
    fi

    if ! is_valid_runner_type "${runner_type}"; then
      echo "Error: runner type must be one of: android_emulator, redroid, android_phone, ios_simulator." >&2
      exit 1
    fi

    for pipeline_id in "${pipeline_ids[@]}"; do
      add_run "${pipeline_id}" "${runner_type}"
    done
  done <<< "${CREDIMI_RUNNER_TYPES}"
else
  while IFS= read -r runner_spec || [[ -n "${runner_spec}" ]]; do
    runner_spec="$(trim "${runner_spec}")"
    if [[ -z "${runner_spec}" ]]; then
      continue
    fi

    parse_runner_spec "${runner_spec}" runner_id runner_type
    if [[ -z "${runner_id}" ]]; then
      echo "Error: runner ids must be formatted as 'runner-id/runner-type'." >&2
      exit 1
    fi

    for pipeline_id in "${pipeline_ids[@]}"; do
      add_run "${pipeline_id}" "${runner_type}" "${runner_id}"
    done
  done <<< "${CREDIMI_RUNNER_IDS}"
fi

if ! is_blank "${CREDIMI_EXTRA_RUNS:-}"; then
  add_runs_from_lines "${CREDIMI_EXTRA_RUNS}" "extra-runs" "add"
fi

if ! is_blank "${CREDIMI_EXCLUDE_RUNS:-}"; then
  add_runs_from_lines "${CREDIMI_EXCLUDE_RUNS}" "exclude-runs" "remove"
fi

wallet_run_endpoint="${CREDIMI_API_BASE_URL:-https://credimi.io}"
wallet_run_endpoint="${wallet_run_endpoint%/}/api/pipeline/run-wallet-apk"

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

active_run_count=0
for key in "${run_keys[@]}"; do
  if [[ -n "${run_seen[${key}]:-}" ]]; then
    active_run_count=$((active_run_count + 1))
  fi
done

if [[ "${active_run_count}" -eq 0 ]]; then
  echo "Error: no pipeline runs remain after applying 'exclude-runs'." >&2
  exit 1
fi

if [[ -n "${CREDIMI_APK_FILE:-}" ]]; then
  if [[ ! -f "${CREDIMI_APK_FILE}" ]]; then
    echo "Error: APK file does not exist: ${CREDIMI_APK_FILE}" >&2
    exit 1
  fi
fi

for key in "${run_keys[@]}"; do
  if [[ -z "${run_seen[${key}]:-}" ]]; then
    continue
  fi

  pipeline_id="${run_pipeline_ids[${key}]}"
  runner_type="${run_runner_types[${key}]}"
  runner_id="${run_runner_ids[${key}]}"

  if [[ -n "${CREDIMI_APK_URL:-}" ]]; then
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

    response="$(curl --fail-with-body --silent --show-error \
      --request POST "${wallet_run_endpoint}" \
      --header "Credimi-Api-Key: ${CREDIMI_API_KEY}" \
      --header "Content-Type: application/json" \
      --data "${payload}")"
  else
    curl_args=(
      --fail-with-body
      --silent
      --show-error
      --request POST "${wallet_run_endpoint}"
      --header "Credimi-Api-Key: ${CREDIMI_API_KEY}"
      --form "pipeline_identifier=${pipeline_id}"
      --form "runner_type=${runner_type}"
      --form "metadata=${metadata};type=application/json"
      --form "apk_file=@${CREDIMI_APK_FILE}"
    )

    if [[ -n "${runner_id}" ]]; then
      curl_args+=(--form "runner_id=${runner_id}")
    fi

    response="$(curl "${curl_args[@]}")"
  fi

  echo "${response}"
done
