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
	echo "Checking Git Readiness ..."
}

rm::getConfig()
{
	# shellcheck disable=SC2154
	if [[ -z "$cfgFile" ]]; then
		if [[ -f "$cfgDefault" ]]; then
			cfgFile="$GITHUB_WORKSPACE/.release.yml"
			echo "Writing config file to '$cfgFile'"
			rm::writeConfig "$cfgDefault" "$cfgFile"
		else
			err::errorExit "Configuration Files Not Found!"
		fi
	fi

	rm::validateConfig "$cfgFile"
	rm::readConfig "$cfgFile"

#	if [[ -z "$(git config --get user.email)" ]]; then
#		[[ $(yq '.git.user | has("name")' "$cfgFile") ]] && USER_NAME=$(yq '.git.user.name' "$cfgFile") || USER_NAME="Release Manager"
#		[[ $(yq '.git.user | has("email")' "$cfgFile") ]] && USER_EMAIL=$(yq '.git.user.email' "$cfgFile") || USER_EMAIL="$GITHUB_ACTOR_ID+$GITHUB_ACTOR@users.noreply.github.com"
#		git config --global user.name = "$USER_NAME"
#		git config --global user.email = "$USER_EMAIL"
#		echo "Git global user configuration set: $USER_NAME <$USER_EMAIL>"
#	fi
}

rm::getCurrentVersion()
{
	local gitTags numTags

	gitTags="$(git tag -l --sort=version:refname)"

	# Package tags as an array
	# shellcheck disable=SC2206
	TAGS=($gitTags)

	# Get number of tags returned
	numTags="${#TAGS[@]}"
	echo "numTags = $numTags"

	if (( "$numTags" > 0 )); then
		# Get the latest tag straight from the horse's mouth
		LATEST_TAG="$(curl -qsSL -H "Accept: application/vnd.github+json" -H "Authorization: Bearer ${GITHUB_TOKEN}" -H "X-GitHub-Api-Version: 2022-11-28" "${GITHUB_API_URL}/repos/${GITHUB_REPOSITORY}/releases/latest" | jq -r .tag_name)"
		echo "LATEST_TAG = ${LATEST_TAG}"

		# Find the previous tag
		if [[ "$LATEST_TAG" =~ ^v?[0-9]+\.*[0-9]*\.*[0-9]*\-?[0-9a-z\.\+]*$ ]]; then
			i="$(arr::getIndex "${TAGS[@]}" "${LATEST_TAG}")"
			[[ "${i}" == "x" ]] && err::errorExit "Latest Tag not found in git"
			if [[ "${TAGS[$i]}" == "${LATEST_TAG}" ]]; then
				((i+=1))
				PREV_TAG="${TAGS[$i]}"
			else
				err::errorExit "Tag mismatch: '${TAGS[$i]}' != '${LATEST_TAG}'"
			fi
		else
			if [[ "${#TAGS[@]}" -gt 0 ]]; then
				LATEST_TAG="${TAGS[0]}"
				[[ -n "${TAGS[1]}" ]] && PREV_TAG="${TAGS[1]}"
			fi
		fi
	fi
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
		[[ "$INPUT_VERSION" =~ ^[0-9]+\.*[0-9]*\.*[0-9]*\-?[0-9a-z\.\+]*$ ]] || err::errorExit "Invalid release version format"
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
				[[ -z "$INPUT_VERSION" ]] && err::errorExit "Bump Type = 'version', but no release version specified"
				break;;
			update)
				[[ -z "$INPUT_VERSION" ]] && err::errorExit "Bump Type = 'update', but no release version specified"
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

	if [[ "$INPUT_PRE_RELEASE" ]]; then
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

rm::readConfig()
{
	local filePath="${1:-}"
	local extends extFilePath tmpFilePath

	echo "Parsing Configuration Files ..."

	[[ $(yq 'has("extends")' "$filePath") ]] && extends=$(yq '.extends' "$filePath")

	if [[ -n "$extends" ]]; then
		extFilePath="$TMPL_DIR/$extends"
		tmpFilePath="$TMP_DIR/$extends"

		[[ -f "$extFilePath" ]] || err::errorExit "Base configuration file '$extFilePath' not found"

		rm::validateConfig "$extFilePath"

		envsubst < "$extFilePath" > "$tmpFilePath" || err::errorExit "Environment substitution failure"

		echo "::debug::Parsing Base Configuration File '$extFilePath'"

#		[[ $(yq 'has("prefix")' "$tmpFilePath") ]] && { PREFIX="$(yq '.prefix' "$tmpFilePath")"; echo "::debug::PREFIX = $PREFIX"; }
#		if [[ $(yq 'has("git")' "$tmpFilePath") ]]; then
#			if [[ $(yq '.git | has("user")' "$tmpFilePath") ]]; then
#				[[ $(yq '.git.user | has("name")' "$tmpFilePath") ]] && { GIT_USER_NAME="$(yq '.git.user.name' "$tmpFilePath")"; echo "::debug::GIT_USER_NAME = $GIT_USER_NAME"; }
#				[[ $(yq '.git.user | has("email")' "$tmpFilePath") ]] && { GIT_USER_EMAIL="$(yq '.git.user.email' "$tmpFilePath")"; echo "::debug::GIT_USER_EMAIL = $GIT_USER_EMAIL"; }
#			fi
#			if [[ $(yq '.git | has("branches")' "$tmpFilePath") ]]; then
#				[[ $(yq '.git.branches | has("prod")' "$tmpFilePath") ]] && { BRANCH_PROD="$(yq '.git.branches.prod' "$tmpFilePath")"; echo "::debug::BRANCH_PROD = $BRANCH_PROD"; }
#				[[ $(yq '.git.branches | has("stage")' "$tmpFilePath") ]] && { BRANCH_STAGE="$(yq '.git.branches.stage' "$tmpFilePath")"; echo "::debug::BRANCH_STAGE = $BRANCH_PROD"; }
#				[[ $(yq '.git.branches | has("patch")' "$tmpFilePath") ]] && { BRANCH_PATCH="$(yq '.git.branches.patch' "$tmpFilePath")"; echo "::debug::BRANCH_PATCH = $BRANCH_PROD"; }
#				[[ $(yq '.git.branches | has("release")' "$tmpFilePath") ]] && { BRANCH_RELEASE="$(yq '.git.branches.release' "$tmpFilePath")"; echo "::debug::BRANCH_RELEASE = $BRANCH_PROD"; }
#			fi
##			if [[ $(yq '.git | has("branches")' "$tmpFilePath") ]]; then
##				[[ $(yq '' "$tmpFilePath") ]] && {}
##			fi
#		fi






	fi
}

#rm::writeConfig()
#{
#
#}

rm::validateConfig()
{
	[[ -z "${1}" ]] && err::errorExit "No Configuration Filepath Passed!"
	[[ -f "${1}" ]] || err::errorExit "Configuration Filepath '${1}' Not Found!"
	[[ ! $(yq --exit-status 'tag == "!!map" or tag == "!!seq"' "${1}") ]] && err::errorExit "Invalid Configuration File '${1}'"
	echo "::debug::Configuration File Validated"
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
err::errorExit()
{
	local msg="${1:-"Unknown Error"}"
	local code="${2:-1}"

	echo "::error::${msg}"
	exit "${code}"
}

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

