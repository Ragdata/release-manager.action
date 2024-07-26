#!/usr/bin/env bash
# shellcheck disable=SC2317
####################################################################
# entrypoint.sh
####################################################################
# Release Manager Docker Action Entrypoint
#
# File:         entrypoint.sh
# Author:       Ragdata
# Date:         26/07/2024
# License:      MIT License
# Copyright:    Copyright © 2024 Redeyed Technologies
####################################################################

set -eEuo pipefail

shopt -s inherit_errexit

IFS=$'\n\t'	# set unofficial strict mode @see: http://redsymbol.net/articles/unofficial-bash-strict-mode/

####################################################################
# FUNCTIONS
####################################################################
re::errorHandler()
{
	local -n lineNo="${1:-LINENO}"
	local -n bashLineNo="${2:-BASH_LINENO}"
	local lastCommand="${3:-BASH_COMMAND}"
	local code="${4:-0}"

	local lastCommandHeight

	[[ "$code" -eq 0 ]] && return 0

	lastCommandHeight="$(wc -l <<<"${lastCommand}")"

	local -a outputArray=()

	outputArray+=(
		'---'
		"Line History: [${lineNo} ${bashLineNo[*]}]"
		"Function Trace: [${FUNCNAME[*]}]"
		"Exit Code: ${code}"
	)

	[[ "${#BASH_SOURCE[@]}" -gt 1 ]] && {
		outputArray+=('source_trace:')
		for item in "${BASH_SOURCE[@]}"; do
			outputArray+=(" - ${item}")
		done
	} || outputArray+=("source_trace: [${BASH_SOURCE[*]}]")

	[[ "${lastCommandHeight}" -gt 1 ]] && {
		outputArray+=('last_command: ->' "${lastCommand}")
	} || outputArray+=("last_command: ${lastCommand}")

	outputArray+=('---')

	printf '%s\n' "${outputArray[@]}" >&2

	exit "$code"
}
####################################################################
# MAIN
####################################################################
trap 're::errorHandler "LINENO" "BASH_LINENO" "${BASH_COMMAND}" "${?}"' ERR
