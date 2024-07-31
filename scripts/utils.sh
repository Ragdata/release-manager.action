#!/usr/bin/env bash
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
rm::checkBranch()
{
	# shellcheck disable=SC2034
	BRANCH_CURRENT="$(git branch --show-current)"

	if [[ -n "$INPUT_BRANCH" ]]; then
		if [[ "$BRANCH_CURRENT" != "$INPUT_BRANCH" ]]; then git checkout "$INPUT_BRANCH" || err::exit "Failed to checkout requested branch '$INPUT_BRANCH'"; fi
	elif [[ -n "$BRANCH_PROD" ]] && [[ "$BRANCH_CURRENT" != "$BRANCH_PROD" ]]; then
		git checkout "$BRANCH_PROD" || err::exit "Failed to checkout production branch '$BRANCH_PROD'"
	fi

#	while read -r line; do
#		line="$(echo "$line" | tr -d '\n')"
#		BRANCHES+=("$line")
#	done <<< "$(git branch -l | sed 's/^\*\s*//')"

#	$(arr::hasVal "${BRANCH_PROD}" "${BRANCHES[@]}") || { git branch "${BRANCH_PROD}"; BRANCHES+=("${BRANCH_PROD}"); echo "::debug::Added '${BRANCH_PROD}' to BRANCHES"; }
#	$(arr::hasVal "${BRANCH_PATCH}" "${BRANCHES[@]}") || { git branch "${BRANCH_PATCH}"; BRANCHES+=("${BRANCH_PATCH}"); echo "::debug::Added '${BRANCH_PATCH}' to BRANCHES"; }
#	$(arr::hasVal "${BRANCH_RELEASE}" "${BRANCHES[@]}") || { git branch "${BRANCH_RELEASE}"; BRANCHES+=("${BRANCH_RELEASE}"); echo "::debug::Added '${BRANCH_RELEASE}' to BRANCHES"; }
#	$(arr::hasVal "${BRANCH_STAGE}" "${BRANCHES[@]}") || { git branch "${BRANCH_STAGE}"; BRANCHES+=("${BRANCH_STAGE}"); echo "::debug::Added '${BRANCH_STAGE}' to BRANCHES"; }
}

#[[ "$(git status -s | head -c1 | wc -c)" -ne 0 ]] && err::exit "Commit staged / unversioned files first, then re-run workflow"

rm::createTag()
{
	echo "Checking existance of release tag ..."

	$(arr::hasValue "${RELEASE_VERSION['full']}" "${TAGS[@]}") && err::exit "Tag '${RELEASE_VERSION['full']}' already exists"
}

rm::parseVersion()
{
	local ver="${1:-0.0.0}"
	local -n arr="${2:-}"

	[[ -z "$ver" ]] && err::exit "Version not passed"
	if [[ "$ver" =~ ^([a-z]+[-.]?)?(([0-9]+)\.?([0-9]*)\.?([0-9]*))(-([0-9a-z-.]*))?(\+([0-9a-z-.]*))?$ ]]; then
		arr['full']="${BASH_MATCH[0]}"
		arr['prefix']="${BASH_MATCH[1]}"
		arr['version']="${BASH_MATCH[2]}"
		arr['major']="${BASH_MATCH[3]}"
		arr['minor']="${BASH_MATCH[4]}"
		arr['patch']="${BASH_MATCH[5]}"
		arr['suffix']="${BASH_MATCH[7]}"
		arr['build']="${BASH_MATCH[9]}"
		arr['n_version']="${arr['major']}${arr['minor']}${arr['patch']}"
	else
		err::exit "Invalid version format"
	fi
}

rm::readConfig()
{
	local filePath="${1:-}"
	local extends extFilePath tmpFilePath

	[[ -f "$filePath" ]] || err::exit "Configuration file '$filePath' not found"

	echo "Parsing Configuration Files ..."

	$(yq 'has("extends")' "$filePath") && extends="$(yq '.extends' "$filePath")"

	if [[ -n "$extends" ]]; then
		extFilePath="$TMPL_DIR/$extends"
		tmpFilePath="$TMP_DIR/$extends"

		[[ -f "$extFilePath" ]] || err::exit "Base configuration file '$extFilePath' not found"

		echo "Configuration file extends base config '$extFilePath'"

		rm::validateConfig "$extFilePath"

		envsubst < "$extFilePath" > "$tmpFilePath" || err::exit "Environment substitution failure"

		$(yq 'has("prefix")' "$tmpFilePath") && { PREFIX="$(yq '.prefix' "$tmpFilePath")"; echo "::debug::PREFIX = $PREFIX"; }
		if $(yq 'has("git_user")' "$tmpFilePath"); then
			$(yq '.git_user | has("name")' "$tmpFilePath") && { GIT_USER_NAME="$(yq '.git_user.name' "$tmpFilePath")"; echo "::debug::GIT_USER_NAME = $GIT_USER_NAME"; }
			$(yq '.git_user | has("email")' "$tmpFilePath") && { GIT_USER_EMAIL="$(yq '.git_user.email' "$tmpFilePath")"; echo "::debug::GIT_USER_EMAIL = $GIT_USER_EMAIL"; }
		fi
		if $(yq 'has("branch")' "$tmpFilePath"); then
			$(yq '.branch | has("prod")' "$tmpFilePath") && { BRANCH_PROD="$(yq '.branch.prod' "$tmpFilePath")"; echo "::debug::BRANCH_PROD = $BRANCH_PROD"; }
			$(yq '.branch | has("stage")' "$tmpFilePath") && { BRANCH_STAGE="$(yq '.branch.stage' "$tmpFilePath")"; echo "::debug::BRANCH_STAGE = $BRANCH_STAGE"; }
			$(yq '.branch | has("patch")' "$tmpFilePath") && { BRANCH_PATCH="$(yq '.branch.patch' "$tmpFilePath")"; echo "::debug::BRANCH_PATCH = $BRANCH_PATCH"; }
			$(yq '.branch | has("release")' "$tmpFilePath") && { BRANCH_RELEASE="$(yq '.branch.release' "$tmpFilePath")"; echo "::debug::BRANCH_RELEASE = $BRANCH_RELEASE"; }
		fi
		if $(yq 'has("message")' "$tmpFilePath"); then
			$(yq '.message | has("commit")' "$tmpFilePath") && { MESSAGE_COMMIT="$(yq '.message.commit' "$tmpFilePath")"; echo "::debug::MESSAGE_COMMIT = $MESSAGE_COMMIT"; }
			$(yq '.message | has("release")' "$tmpFilePath") && { MESSAGE_RELEASE="$(yq '.message.release' "$tmpFilePath")"; echo "::debug::MESSAGE_RELEASE = $MESSAGE_RELEASE"; }
		fi
		if $(yq 'has("types")' "$tmpFilePath"); then
			# shellcheck disable=SC2034
			readarray TYPES < <(yq -o=j -I=0 '.types[]' "$tmpFilePath")
#			for json in "${TYPES[@]}"; do
#				type=$(echo "$json" | yq '.type' -)
#			done
		fi
		if $(yq 'has("aliases")' "$tmpFilePath"); then
			# shellcheck disable=SC2034
			readarray TYPE_ALIASES < <(yq -o=j -I=0 '.aliases[]' "$tmpFilePath")
		fi
		if $(yq 'has("logged")' "$tmpFilePath"); then
			# shellcheck disable=SC2034
			readarray LOGGED_TYPES < <(yq '.logged[]' "$tmpFilePath")
		fi
		echo "Base configuration file processed"
	fi

	rm::validateConfig "$filePath"

	$(yq 'has("prefix")' "$filePath") && { PREFIX="$(yq '.prefix' "$filePath")"; echo "::debug::PREFIX = $PREFIX"; }
	$(yq 'has("name")' "$filePath") && { REPO_NAME="$(yq '.name' "$filePath")"; echo "::debug::REPO_NAME = $REPO_NAME"; }
	$(yq 'has("description")' "$filePath") && { REPO_DESC="$(yq '.description' "$filePath")"; echo "::debug::REPO_DESC = $REPO_DESC"; }
	$(yq 'has("repo_url")' "$filePath") && { REPO_URL="$(yq '.repo_url' "$filePath")"; echo "::debug::REPO_URL = $REPO_URL"; }
	$(yq 'has("copyright")' "$filePath") && { COPYRIGHT="$(yq '.copyright' "$filePath")"; echo "::debug::COPYRIGHT = $COPYRIGHT"; }
	$(yq 'has("website")' "$filePath") && { WEBSITE="$(yq '.website' "$filePath")"; echo "::debug::WEBSITE = $WEBSITE"; }
	if $(yq 'has("git_user")' "$filePath"); then
		$(yq '.git_user | has("name")' "$filePath") && { GIT_USER_NAME="$(yq '.git_user.name' "$filePath")"; echo "::debug::GIT_USER_NAME = $GIT_USER_NAME"; }
		$(yq '.git_user | has("email")' "$filePath") && { GIT_USER_EMAIL="$(yq '.git_user.email' "$filePath")"; echo "::debug::GIT_USER_EMAIL = $GIT_USER_EMAIL"; }
	fi
	if $(yq 'has("authors")' "$filePath"); then
		# shellcheck disable=SC2034
		readarray AUTHORS < <(yq -o=j -I=0 '.authors[]' "$filePath")
	fi
	if $(yq 'has("branch")' "$filePath"); then
		$(yq '.branch | has("prod")' "$filePath") && { BRANCH_PROD="$(yq '.branch.prod' "$filePath")"; echo "::debug::BRANCH_PROD = $BRANCH_PROD"; }
		$(yq '.branch | has("stage")' "$filePath") && { BRANCH_STAGE="$(yq '.branch.stage' "$filePath")"; echo "::debug::BRANCH_STAGE = $BRANCH_STAGE"; }
		$(yq '.branch | has("patch")' "$filePath") && { BRANCH_PATCH="$(yq '.branch.patch' "$filePath")"; echo "::debug::BRANCH_PATCH = $BRANCH_PATCH"; }
		$(yq '.branch | has("release")' "$filePath") && { BRANCH_RELEASE="$(yq '.branch.release' "$filePath")"; echo "::debug::BRANCH_RELEASE = $BRANCH_RELEASE"; }
	fi
	if $(yq 'has("message")' "$filePath"); then
		$(yq '.message | has("commit")' "$filePath") && { MESSAGE_COMMIT="$(yq '.message.commit' "$filePath")"; echo "::debug::MESSAGE_COMMIT = $MESSAGE_COMMIT"; }
		$(yq '.message | has("release")' "$filePath") && { MESSAGE_RELEASE="$(yq '.message.release' "$filePath")"; echo "::debug::MESSAGE_RELEASE = $MESSAGE_RELEASE"; }
	fi
	if $(yq 'has("types")' "$filePath"); then
		# shellcheck disable=SC2034
		readarray TYPES < <(yq -o=j -I=0 '.types[]' "$filePath")
	fi
	if $(yq 'has("aliases")' "$filePath"); then
		# shellcheck disable=SC2034
		readarray TYPE_ALIASES < <(yq -o=j -I=0 '.aliases[]' "$filePath")
	fi
	if $(yq 'has("logged")' "$filePath"); then
		# shellcheck disable=SC2034
		readarray LOGGED_TYPES < <(yq '.logged[]' "$filePath")
	fi
	$(yq 'has("protect_prod")' "$filePath") && { PROTECT_PROD="$(yq '.protect_prod' "$filePath")"; echo "::debug::PROTECT_PROD = $PROTECT_PROD"; }
	$(yq 'has("changelog")' "$filePath") && { CHANGELOG="$(yq '.changelog' "$filePath")"; echo "::debug::CHANGELOG = $CHANGELOG"; }

	echo "Release Manager configuration file processed"
}

rm::writeConfig()
{
	local source="${1}"
	local dest="${2}"

	envsubst < "$source" > "$dest" || err::exit "Failed to write config file"
}

rm::validateConfig()
{
	[[ -z "${1}" ]] && err::exit "No Configuration Filepath Passed!"
	[[ -f "${1}" ]] || err::exit "Configuration Filepath '${1}' Not Found!"
	$(yq --exit-status 'tag == "!!map" or tag == "!!seq"' "${1}") || err::exit "Invalid Configuration File '${1}'"
	echo "::debug::Configuration File '${1}' Validated"
}

####################################################################
# ARRAY FUNCTIONS
####################################################################
arr::hasVal()
{
	local e val="${1}"
	shift

	for e; do [[ "$e" == "$val" ]] && return 0; done

	return 1
}

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

####################################################################
# GITHUB FUNCTIONS
####################################################################
gh::api()
{
	local OPTIND opt
	local url data method="-X GET"
	local methods=("GET" "POST" "PUT" "PATCH" "DELETE")
	local headers="-H \"Accept: application/vnd.github+json\" -H \"Authorization: Bearer ${GITHUB_TOKEN}\" -H \"X-GitHub-Api-Version: 2022-11-28\""

	while getopts ":X:d:" opt; do
		case "$opt" in
			X)
				$(arr::hasVal "${opt^^}" "${methods[@]}") || err::exit "Invalid method option '${opt^^}'"
				method="-X ${opt^^}"
				;;
			d)	data="-d ${opt}"
				;;
			:)
				err::exit "Option -${OPTARG} requires an argument"
				;;
			?)
				err::exit "Invalid option: -${OPTARG}"
				;;
			*)
				err::exit "Unknown error while processing options"
				;;
		esac
	done

	# shellcheck disable=SC2004
	[[ $(( $# - $OPTIND )) -lt 1 ]] && err::exit "Missing URL"

	# shellcheck disable=SC2124
	url="${@:$OPTIND:1}"

	result=$(curl -sSL "$method" "$headers" "$data" -w '%{http_code}' "$url")

	RESPONSE['code']=$(tail -n1 <<< "$result")
	RESPONSE['body']=$(sec '$ d' <<< "$result")
}
