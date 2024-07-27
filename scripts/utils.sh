#!/usr/bin/env bash
####################################################################
# utils.sh
####################################################################
# Release Manager Docker Action - Utilities
#
# File:         utils.sh
# Author:       Ragdata
# Date:         26/07/2024
# License:      MIT License
# Copyright:    Copyright © 2024 Redeyed Technologies
####################################################################
# FUNCTIONS
####################################################################
rm::errorExit()
{
	local msg="${1:-"Unknown Error"}"
	local code="${2:-1}"

	echo "::error::${msg}"
	exit "${code}"
}

rm::errorHandler()
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

rm::getConfig()
{
	cfgFile="$(find "$GITHUB_WORKSPACE" -maxdepth 1 -type f -regextype posix-egrep -iregex ".+\.(release|releaserc|versionrc)(\.yml)?(\.yaml)?")"
	cfgDefault="/usr/local/share/tmpl/.release.yml"

	if [[ -n "$cfgFile" ]]; then
		echo "Found config file at '$cfgFile'"
		rm::readConfig "$cfgFile"
	elif [[ -f "$cfgDefault" ]]; then
		echo "Using default config file '$cfgDefault'"
		rm::readConfig "$cfgDefault"
		cfgFile="$cfgDefault"
	else
		rm::errorExit "Configuration Template File Not Found!"
	fi

	if [[ -z "$(git config --get user.email)" ]]; then
		[[ $(yq -P '.git.user | has("name")' "$cfgFile") ]] && USER_NAME=$(yq -P '.git.user.name' "$cfgFile") || USER_NAME="Release Manager"
		[[ $(yq -P '.git.user | has("email")' "$cfgFile") ]] && USER_EMAIL=$(yq -P '.git.user.email' "$cfgFile") || USER_EMAIL="$GITHUB_ACTOR_ID+$GITHUB_ACTOR@users.noreply.github.com"
		git config --global user.name = "$USER_NAME"
		git config --global user.email = "$USER_EMAIL"
		echo "Git global user configuration set: $USER_NAME <$USER_EMAIL>"
	fi
}

#rm::readConfig()
#{
#
#}

rm::validateConfig()
{
	[[ -z "${1}" ]] && rm::errorExit "No Configuration Filepath Passed!"
	[[ -f "${1}" ]] || rm::errorExit "Configuration Filepath '${1}' Not Found!"
	[[ ! $(yq --exit-status 'tag == "!!map" or tag == "!!seq"' "${1}") ]] && rm::errorExit "Invalid Configuration File '${1}'"
}
