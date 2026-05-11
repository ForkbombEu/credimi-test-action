#!/usr/bin/env bash

err() {
  echo "Error: $*" >&2
  exit 1
}

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
    err "runner must be a runner type or formatted as 'runner-id/runner-type': ${runner_spec}"
  fi

  out_runner_id="${runner_spec%/*}"
  out_runner_type="${runner_spec##*/}"

  if [[ -z "${out_runner_id}" ]]; then
    err "runner id cannot be empty in runner spec: ${runner_spec}"
  fi

  if ! is_valid_runner_type "${out_runner_type}"; then
    err "runner type must be one of: android_emulator, redroid, android_phone, ios_simulator."
  fi
}

make_run_key() {
  local pipeline_id="$1"
  local runner_type="$2"
  local runner_id="$3"

  printf '%s\t%s\t%s' "${pipeline_id}" "${runner_type}" "${runner_id}"
}

add_run() {
  local pipeline_id="$1"
  local runner_type="${2:-}"
  local runner_id="${3:-}"
  local key

  if [[ -z "${pipeline_id}" ]]; then
    err "pipeline id cannot be empty."
  fi

  if [[ -n "${runner_type}" ]] && ! is_valid_runner_type "${runner_type}"; then
    err "runner type must be one of: android_emulator, redroid, android_phone, ios_simulator."
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
  local runner_type="${2:-}"
  local runner_id="${3:-}"
  local key

  key="$(make_run_key "${pipeline_id}" "${runner_type}" "${runner_id}")"
  unset "run_seen[${key}]"
}

add_runs_from_lines() {
  local lines="$1"
  local source_name="$2"
  local mode="$3"
  local allow_pipeline_only="${4:-false}"
  local line pipeline_id runner_spec extra runner_id runner_type

  while IFS= read -r line || [[ -n "${line}" ]]; do
    line="$(trim "${line}")"
    if [[ -z "${line}" ]]; then
      continue
    fi

    read -r pipeline_id runner_spec extra <<< "${line}"
    if [[ -z "${pipeline_id}" || -n "${extra:-}" ]]; then
      err "each ${source_name} line must contain exactly: '<pipeline-id> <runner-type|runner-id/runner-type>'."
    fi

    if [[ -z "${runner_spec}" ]]; then
      if [[ "${allow_pipeline_only}" != true ]]; then
        err "each ${source_name} line must contain exactly: '<pipeline-id> <runner-type|runner-id/runner-type>'."
      fi

      runner_id=""
      runner_type=""
    else
      parse_runner_spec "${runner_spec}" runner_id runner_type
    fi

    if [[ "${mode}" == "add" ]]; then
      add_run "${pipeline_id}" "${runner_type}" "${runner_id}"
    else
      remove_run "${pipeline_id}" "${runner_type}" "${runner_id}"
    fi
  done <<< "${lines}"
}

validate_target_inputs() {
  local has_apk_file=false
  local has_apk_url=false
  local has_issuer_url=false
  local has_credential_ids=false

  if ! is_blank "${CREDIMI_APK_FILE:-}"; then
    has_apk_file=true
  fi

  if ! is_blank "${CREDIMI_APK_URL:-}"; then
    has_apk_url=true
  fi

  if ! is_blank "${CREDIMI_ISSUER_URL:-}"; then
    has_issuer_url=true
  fi

  if ! is_blank "${CREDIMI_CREDENTIAL_IDS:-}"; then
    has_credential_ids=true
  fi

  if [[ "${has_apk_file}" == true && "${has_apk_url}" == true ]]; then
    err "'apk-url' and 'apk-file' are mutually exclusive."
  fi

  if [[ "${has_issuer_url}" != "${has_credential_ids}" ]]; then
    err "'issuer-url' and 'credential-ids' must be provided together."
  fi

  if [[ ("${has_apk_file}" == true || "${has_apk_url}" == true) && "${has_issuer_url}" == true ]]; then
    err "wallet inputs ('apk-file' or 'apk-url') and issuer inputs ('issuer-url' and 'credential-ids') are mutually exclusive."
  fi

  if [[ "${has_apk_file}" == false && "${has_apk_url}" == false && "${has_issuer_url}" == false ]]; then
    err "provide either exactly one of 'apk-url' or 'apk-file', or both 'issuer-url' and 'credential-ids'."
  fi

  if [[ "${has_apk_file}" == true ]]; then
    if [[ ! -f "${CREDIMI_APK_FILE}" ]]; then
      err "APK file does not exist: ${CREDIMI_APK_FILE}"
    fi

    printf '%s' "wallet"
    return 0
  fi

  if [[ "${has_apk_url}" == true ]]; then
    printf '%s' "wallet"
    return 0
  fi

  printf '%s' "issuer"
}

json_array_from_lines() {
  local lines="$1"

  jq -R -s -c '
    split("\n")
    | map(gsub("^[[:space:]]+|[[:space:]]+$"; ""))
    | map(select(length > 0))
  ' <<< "${lines}"
}

build_metadata() {
  local github_context="${GITHUB_CONTEXT:-}"

  if [[ -z "${github_context}" ]]; then
    github_context="{}"
  fi

  jq -c \
    '
    del(
      .token,
      .event.repository.owner.email,
      .event.sender.email,
      .event.pusher.email
    )
    ' <<< "${github_context}"
}

active_run_count() {
  local key
  local count=0

  for key in "${run_keys[@]}"; do
    if [[ -n "${run_seen[${key}]:-}" ]]; then
      count=$((count + 1))
    fi
  done

  printf '%s' "${count}"
}
