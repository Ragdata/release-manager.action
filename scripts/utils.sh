#!/usr/bin/env bash
# shellcheck disable=SC2034
# shellcheck disable=SC2091
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
# CORE FUNCTIONS
####################################################################
rm::getReleaseVersion()
{
	local p="" v="" s="" b="" d

	$INPUT_PRE_RELEASE && s="-alpha"

	case "$INPUT_TYPE" in
		auto)
			if [[ "$isFirst" ]]; then
				[[ -n "${CURRENT_VERSION['prefix']}" ]] && p="${CURRENT_VERSION['prefix']}"
				v="${CURRENT_VERSION['version']}"
			else
				if [[ -n "${LATEST_REPO_TAG['prefix']}" ]] && [[ ! $INPUT_PRE_RELEASE ]]; then
					v="${LATEST_REPO_TAG['version']}"
				elif [[ -n "${LATEST_REPO_TAG['prefix']}" ]] && $INPUT_PRE_RELEASE; then
					err::exit "Cannot auto-increment pre-release to pre-release versions"
				else
					d="${LATEST_REPO_TAG['minor']}"
					((d+=1))
					v="${LATEST_REPO_TAG['major']}.$d.0"
				fi
			fi
			;;
		version)
			[[ -n "${IN_VERSION['prefix']}" ]] && p="${IN_VERSION['prefix']}"
			v="${IN_VERSION['version']}"
			[[ -n "${IN_VERSION['suffix']}" ]] && s="${IN_VERSION['suffix']}"
			[[ -n "${IN_VERSION['build']}" ]] && b="${IN_VERSION['build']}"
			;;
		patch|minor|major)
			[[ -n "${LATEST_REPO_TAG['prefix']}" ]] && p="${LATEST_REPO_TAG['prefix']}"
			case "$INPUT_TYPE" in
				patch)
					d="${LATEST_REPO_TAG['patch']}"
					((d+=1))
					v="${LATEST_REPO_TAG['major']}.${LATEST_REPO_TAG['minor']}.$d"
					;;
				minor)
					d="${LATEST_REPO_TAG['minor']}"
					((d+=1))
					v="${LATEST_REPO_TAG['major']}.$d.0"
					;;
				major)
					d="${LATEST_REPO_TAG['major']}"
					((d+=1))
					v="$d.0.0"
					;;
			esac
			;;
	esac

	echo "$p$v$s$b"
}

rm::parseVersion()
{
	local ver="${1:-0.0.0}"
	local -n arr="${2}"

	[[ -z "$ver" ]] && err::exit "Version not passed"
	if [[ $ver =~ ^([a-z]+[-.]?)?(([0-9]+)\.?([0-9]*)\.?([0-9]*))(-([0-9a-zA-Z\.-]*))?(\+([0-9a-zA-Z\.-]*))?$ ]]; then
		arr['full']="${BASH_REMATCH[0]}"
		arr['prefix']="${BASH_REMATCH[1]}"
		arr['version']="${BASH_REMATCH[2]}"
		arr['major']="${BASH_REMATCH[3]}"
		arr['minor']="${BASH_REMATCH[4]}"
		arr['patch']="${BASH_REMATCH[5]}"
		arr['suffix']="${BASH_REMATCH[7]}"
		arr['build']="${BASH_REMATCH[9]}"
		arr['n_version']="${arr['major']}${arr['minor']}${arr['patch']}"
	else
		err::exit "Invalid version format - '$ver'"
	fi
}


####################################################################
# ARRAY FUNCTIONS
####################################################################
arr::getIndex()
{
	local val="${1:-}"
	# shellcheck disable=SC2178
	local -a arr="${2:-}"

	for i in "${!arr[@]}"; do
		[[ "${arr[$i]}" = "${val}" ]] && { echo "${i}"; return 0; }
	done

	return 1
}

arr::hasKey()
{
	local -n array="$1"
	local key="$2"

	[[ ${array[$key]+_} ]] && return 0

	return 1
}

arr::hasVal()
{
	local e val="${1}"
	shift

	for e; do [[ "$e" == "$val" ]] && return 0; done

	return 1
}

####################################################################
# ERROR FUNCTIONS
####################################################################
err::errHandler()
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

	if [[ "${#BASH_SOURCE[@]}" -gt 1 ]]; then
		outputArray+=('source_trace:')
		for item in "${BASH_SOURCE[@]}"; do
			outputArray+=(" - ${item}")
		done
	else
		outputArray+=("source_trace: [${BASH_SOURCE[*]}]")
	fi

	if [[ "${lastCommandHeight}" -gt 1 ]]; then
		outputArray+=('last_command: ->' "${lastCommand}")
	else
		outputArray+=("last_command: ${lastCommand}")
	fi

	outputArray+=('---')

	printf '%s\n' "${outputArray[@]}" >&2

	exit "$code"
}

err::exit()
{
	local msg="${1:-"Unknown Error"}"
	local code="${2:-1}"

	echo "::error::${msg}"
	exit "${code}"
}
