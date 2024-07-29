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
# CORE FUNCTIONS
####################################################################
rm::checkGit()
{
	echo "Checking Git Config ..."

	if ! git config --get user.email; then
		[[ -z "$GIT_USER_NAME" ]] && err::exit "Git username not configured"
		[[ -z "$GIT_USER_EMAIL" ]] && err::exit "No email address configured"
		git config --global user.name = "$GIT_USER_NAME"
		git config --global user.email = "$GIT_USER_EMAIL"
		echo "Git global user configuration set: $GIT_USER_NAME <$GIT_USER_EMAIL>"
	fi

	[[ -n "$(git status . -s)" ]] && err::exit "Commit staged files first, then re-run workflow"

#	echo "Creating new release branch ..."
#
#	git checkout -b "$BRANCH_RELEASE"
#
#	echo "Checking for Untracked Files ..."
#
#	if [[ -n $(git status . -s) ]]; then
#		git add . || err::exit "Failed to add untracked files"
#		git commit -am "$MESSAGE_COMMIT" || err::exit "Failed to commit untracked files"
#	fi
}

rm::checkConfig()
{
	echo "Checking configuration files ..."
	# shellcheck disable=SC2154
	if [[ ! -f "$cfgFile" ]]; then
		echo "Release Manager configuration file not present"
		if [[ -f "$cfgDefault" ]]; then
			cfgFile="$TMP_DIR/.release.yml"
			echo "Creating temporary config file"
			envsubst < "$cfgDefault" > "$cfgFile" || err::exit "Failed to write temporary config file"
		else
			err::exit "Default configuration file not found"
		fi
	else
		echo "Release Manager configuration file '$cfgFile' present"
	fi
}

rm::getCurrentVersion()
{
	echo "Querying configuration file for current version ..."

	if [[ -f "$cfgFile" ]]; then
		if yq 'has("version")' "$cfgFile"; then
			echo "Current version obtained from configuration file"
			CURRENT_VERSION="$(yq '.version' "$cfgFile")"
		else
			err::exit "No current version in configuration file"
		fi
	else
		echo "No Configuration File - assigning default first version"
		# shellcheck disable=SC2034
		CURRENT_VERSION="0.1.0"
	fi

	echo "::debug::CURRENT_VERSION = $CURRENT_VERSION"
}

rm::getInputs()
{
	PREFIX=""
	SUFFIX=""
	BUILD=""

	if [[ -n "$INPUT_VERSION" ]]; then
		# Remove the prefix, if it exists
		[[ "${INPUT_VERSION:0:1}" =~ ^[0-9]$ ]] || INPUT_VERSION="${INPUT_VERSION:1}"
		# Validate the INPUT_VERSION format
		[[ "$INPUT_VERSION" =~ ^[0-9]+\.*[0-9]*\.*[0-9]*\-?[0-9a-z\.\+]*$ ]] || err::exit "Invalid release version format"
		# Look for build metadata in INPUT_VERSION
		if [[ "$INPUT_VERSION" == *"+"* ]]; then
			# shellcheck disable=SC2034
			BUILD="${INPUT_VERSION##*+}"
			INPUT_VERSION="${INPUT_VERSION%+*}"
		fi
		# Look for existing suffix in INPUT_VERSION
		if [[ "$INPUT_VERSION" == *"-"* ]]; then
			# shellcheck disable=SC2034
			SUFFIX="${INPUT_VERSION##*-}"
			INPUT_VERSION="${INPUT_VERSION%-*}"
		fi
	fi

	while true
	do
		case "$INPUT_TYPE" in
			first)
				[[ -z "$INPUT_VERSION" ]] && INPUT_VERSION="1.0.0"
				break;;
			version)
				[[ -z "$INPUT_VERSION" ]] && err::exit "Bump Type = 'version', but no release version specified"
				break;;
			update)
				[[ -z "$INPUT_VERSION" ]] && err::exit "Bump Type = 'update', but no release version specified"
				break;;
			patch)
				# PLACEHOLDER
				break;;
			minor)
				# PLACEHOLDER
				break;;
			major)
				# PLACEHOLDER
				break;;
			*)
				INPUT_TYPE="auto"
				break;;
		esac
	done

	[[ -z "$INPUT_BRANCH" ]] && INPUT_BRANCH="${GITHUB_REF_NAME}"

	if $INPUT_PRE_RELEASE; then
		# Don't overwrite a suffix which was included with the release version input
		[[ -z "$SUFFIX" ]] && SUFFIX="-alpha"
	fi

	echo "PREFIX = ${PREFIX}"
	echo "INPUT_VERSION = ${INPUT_VERSION}"
	echo "SUFFIX = ${SUFFIX}"
	echo "BUILD = ${BUILD}"
	echo "INPUT_TYPE = ${INPUT_TYPE}"
	echo "INPUT_BRANCH = ${INPUT_BRANCH}"
}

rm::getLatestTags()
{
	local gitTags numTags

	gitTags="$(git tag -l --sort=version:refname)"

	# Package tags as an array
	# shellcheck disable=SC2206
	TAGS=($gitTags)

	# Get number of tags returned
	numTags="${#TAGS[@]}"

	if (( "$numTags" > 0 )); then
		# Get the latest tag straight from the horse's mouth
		LATEST_TAG="$(curl -qsSL -H "Accept: application/vnd.github+json" -H "Authorization: Bearer ${GITHUB_TOKEN}" -H "X-GitHub-Api-Version: 2022-11-28" "${GITHUB_API_URL}/repos/${GITHUB_REPOSITORY}/releases/latest" | yq '.tag_name')"
		echo "::debug::LATEST_TAG = ${LATEST_TAG}"

		# Find the previous tag
		if [[ "$LATEST_TAG" =~ ^[a-z\-\.]*[0-9]+\.*[0-9]*\.*[0-9]*\-?[0-9a-z\.\+]*$ ]]; then
			i="$(arr::getIndex "${TAGS[@]}" "${LATEST_TAG}")"
			[[ "${i}" == "x" ]] && err::exit "Latest Tag not found in git"
			if [[ "${TAGS[$i]}" == "${LATEST_TAG}" ]]; then
				((i+=1))
				PREV_TAG="${TAGS[$i]}"
			else
				err::exit "Tag mismatch: '${TAGS[$i]}' != '${LATEST_TAG}'"
			fi
		else
			if [[ "${#TAGS[@]}" -gt 0 ]]; then
				LATEST_TAG="${TAGS[0]}"
				[[ -n "${TAGS[1]}" ]] && PREV_TAG="${TAGS[1]}"
			fi
		fi
	fi

	echo "LATEST_TAG = ${LATEST_TAG}"
	echo "PREV_TAG = ${PREV_TAG}"
}

rm::readConfig()
{
	local filePath="${1:-}"
	local extends extFilePath tmpFilePath

	[[ -f "$filePath" ]] || err::exit "Configuration file '$filePath' not found"

	echo "Parsing Configuration Files ..."

	yq 'has("extends")' "$filePath" && extends="$(yq '.extends' "$filePath")"

	if [[ -n "$extends" ]]; then
		extFilePath="$TMPL_DIR/$extends"
		tmpFilePath="$TMP_DIR/$extends"

		[[ -f "$extFilePath" ]] || err::exit "Base configuration file '$extFilePath' not found"

		echo "Configuration file extends base config '$extFilePath'"

		rm::validateConfig "$extFilePath"

		envsubst < "$extFilePath" > "$tmpFilePath" || err::exit "Environment substitution failure"

		if yq 'has("prefix")' "$tmpFilePath"; then PREFIX="$(yq '.prefix' "$tmpFilePath")"; echo "::debug::PREFIX = $PREFIX"; fi
		if yq 'has("git_user")' "$tmpFilePath"; then
			if yq '.git_user | has("name")' "$tmpFilePath"; then GIT_USER_NAME="$(yq '.git_user.name' "$tmpFilePath")"; echo "::debug::GIT_USER_NAME = $GIT_USER_NAME"; fi
			if yq '.git_user | has("email")' "$tmpFilePath"; then GIT_USER_EMAIL="$(yq '.git_user.email' "$tmpFilePath")"; echo "::debug::GIT_USER_EMAIL = $GIT_USER_EMAIL"; fi
		fi
		if yq 'has("branch")' "$tmpFilePath"; then
			if yq '.branch | has("prod")' "$tmpFilePath"; then BRANCH_PROD="$(yq '.branch.prod' "$tmpFilePath")"; echo "::debug::BRANCH_PROD = $BRANCH_PROD"; fi
			if yq '.branch | has("stage")' "$tmpFilePath"; then BRANCH_STAGE="$(yq '.branch.stage' "$tmpFilePath")"; echo "::debug::BRANCH_STAGE = $BRANCH_STAGE"; fi
			if yq '.branch | has("patch")' "$tmpFilePath"; then BRANCH_PATCH="$(yq '.branch.patch' "$tmpFilePath")"; echo "::debug::BRANCH_PATCH = $BRANCH_PATCH"; fi
			if yq '.branch | has("release")' "$tmpFilePath"; then BRANCH_RELEASE="$(yq '.branch.release' "$tmpFilePath")"; echo "::debug::BRANCH_RELEASE = $BRANCH_RELEASE"; fi
		fi
		if yq 'has("message")' "$tmpFilePath"; then
			if yq '.message | has("commit")' "$tmpFilePath"; then MESSAGE_COMMIT="$(yq '.message.commit' "$tmpFilePath")"; echo "::debug::MESSAGE_COMMIT = $MESSAGE_COMMIT"; fi
			if yq '.message | has("release")' "$tmpFilePath"; then MESSAGE_RELEASE="$(yq '.message.release' "$tmpFilePath")"; echo "::debug::MESSAGE_RELEASE = $MESSAGE_RELEASE"; fi
		fi
		if yq 'has("types")' "$tmpFilePath"; then
			# shellcheck disable=SC2034
			readarray TYPES < <(yq -o=j -I=0 '.types[]' "$tmpFilePath")
#			for json in "${TYPES[@]}"; do
#				type=$(echo "$json" | yq '.type' -)
#			done
		fi
		if yq 'has("aliases")' "$tmpFilePath"; then
			# shellcheck disable=SC2034
			readarray TYPE_ALIASES < <(yq -o=j -I=0 '.aliases[]' "$tmpFilePath")
		fi
		if yq 'has("logged")' "$tmpFilePath"; then
			# shellcheck disable=SC2034
			readarray LOGGED_TYPES < <(yq '.logged[]' "$tmpFilePath")
		fi
		echo "Base configuration file processed"
	fi

	rm::validateConfig "$filePath"

	if yq 'has("prefix")' "$filePath"; then PREFIX="$(yq '.prefix' "$filePath")"; echo "::debug::PREFIX = $PREFIX"; fi
	if yq 'has("name")' "$filePath"; then REPO_NAME="$(yq '.name' "$filePath")"; echo "::debug::REPO_NAME = $REPO_NAME"; fi
	if yq 'has("description")' "$filePath"; then REPO_DESC="$(yq '.description' "$filePath")"; echo "::debug::REPO_DESC = $REPO_DESC"; fi
	if yq 'has("repo_url")' "$filePath"; then REPO_URL="$(yq '.repo_url' "$filePath")"; echo "::debug::REPO_URL = $REPO_URL"; fi
	if yq 'has("copyright")' "$filePath"; then COPYRIGHT="$(yq '.copyright' "$filePath")"; echo "::debug::COPYRIGHT = $COPYRIGHT"; fi
	if yq 'has("website")' "$filePath"; then WEBSITE="$(yq '.website' "$filePath")"; echo "::debug::WEBSITE = $WEBSITE"; fi
	if yq 'has("git_user")' "$filePath"; then
		if yq '.git_user | has("name")' "$filePath"; then GIT_USER_NAME="$(yq '.git_user.name' "$filePath")"; echo "::debug::GIT_USER_NAME = $GIT_USER_NAME"; fi
		if yq '.git_user | has("email")' "$filePath"; then GIT_USER_EMAIL="$(yq '.git_user.email' "$filePath")"; echo "::debug::GIT_USER_EMAIL = $GIT_USER_EMAIL"; fi
	fi
	if yq 'has("authors")' "$filePath"; then
		# shellcheck disable=SC2034
		readarray AUTHORS < <(yq -o=j -I=0 '.authors[]' "$filePath")
	fi
	if yq 'has("branch")' "$filePath"; then
		if yq '.branch | has("prod")' "$filePath"; then BRANCH_PROD="$(yq '.branch.prod' "$filePath")"; echo "::debug::BRANCH_PROD = $BRANCH_PROD"; fi
		if yq '.branch | has("stage")' "$filePath"; then BRANCH_STAGE="$(yq '.branch.stage' "$filePath")"; echo "::debug::BRANCH_STAGE = $BRANCH_STAGE"; fi
		if yq '.branch | has("patch")' "$filePath"; then BRANCH_PATCH="$(yq '.branch.patch' "$filePath")"; echo "::debug::BRANCH_PATCH = $BRANCH_PATCH"; fi
		if yq '.branch | has("release")' "$filePath"; then BRANCH_RELEASE="$(yq '.branch.release' "$filePath")"; echo "::debug::BRANCH_RELEASE = $BRANCH_RELEASE"; fi
	fi
	if yq 'has("message")' "$filePath"; then
		if yq '.message | has("commit")' "$filePath"; then MESSAGE_COMMIT="$(yq '.message.commit' "$filePath")"; echo "::debug::MESSAGE_COMMIT = $MESSAGE_COMMIT"; fi
		if yq '.message | has("release")' "$filePath"; then MESSAGE_RELEASE="$(yq '.message.release' "$filePath")"; echo "::debug::MESSAGE_RELEASE = $MESSAGE_RELEASE"; fi
	fi
	if yq 'has("types")' "$filePath"; then
		# shellcheck disable=SC2034
		readarray TYPES < <(yq -o=j -I=0 '.types[]' "$filePath")
	fi
	if yq 'has("aliases")' "$filePath"; then
		# shellcheck disable=SC2034
		readarray TYPE_ALIASES < <(yq -o=j -I=0 '.aliases[]' "$filePath")
	fi
	if yq 'has("logged")' "$filePath"; then
		# shellcheck disable=SC2034
		readarray LOGGED_TYPES < <(yq '.logged[]' "$filePath")
	fi
	if yq 'has("protect_prod")' "$filePath"; then PROTECT_PROD="$(yq '.protect_prod' "$filePath")"; echo "::debug::PROTECT_PROD = $PROTECT_PROD"; fi
	if yq 'has("changelog")' "$filePath"; then CHANGELOG="$(yq '.changelog' "$filePath")"; echo "::debug::CHANGELOG = $CHANGELOG"; fi

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
	yq --exit-status 'tag == "!!map" or tag == "!!seq"' "${1}" || err::exit "Invalid Configuration File '${1}'"
	echo "::debug::Configuration File '${1}' Validated"
}

####################################################################
# ARRAY FUNCTIONS
####################################################################
arr::getIndex()
{
	local arr="${1}"
	local val="${2}"
	local found=false

	for i in "${!arr[@]}"; do
		[[ "${arr[$i]}" = "${val}" ]] && { echo "${i}"; found=true; break; }
	done

	[[ "${found}" ]] || echo "x"
}

####################################################################
# ERROR FUNCTIONS
####################################################################
err::errorHandler()
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
