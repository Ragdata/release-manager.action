#!/usr/bin/env bash
# shellcheck disable=SC2034
####################################################################
# entrypoint.sh
####################################################################
# Release Manager Docker Action Entrypoint
#
# File:         entrypoint.sh
# Author:       Ragdata
# Date:         11/08/2024
# License:      MIT License
# Copyright:    Copyright © 2024 Redeyed Technologies
####################################################################

set -eEuo pipefail

shopt -s inherit_errexit

IFS=$'\n\t'	# set unofficial strict mode @see: http://redsymbol.net/articles/unofficial-bash-strict-mode/

####################################################################
# Initialisation
####################################################################
declare -Ax PROFILE

PROFILE["STARTTIME"]="$(date +%s.%N)"

git config --global --add safe.directory "$GITHUB_WORKSPACE"
####################################################################
# Load SRC Files
####################################################################
readarray -t files <<< "$(find /usr/local/bin/src -maxdepth 1 -not -type d)"

if (( ${#files} > 0 )); then
	for file in "${files[@]}"
	do
		# shellcheck source=/usr/local/bin/src/*
		[ -f "$file" ] && source "$file"
	done
else
	echo "::error::Source files not found"
	exit 1
fi
####################################################################
# MAIN
####################################################################
trap 'err::errHandler "LINENO" "BASH_LINENO" "${BASH_COMMAND}" "${?}"' ERR

echo "::group::📑 Configuring Release Manager"
#-------------------------------------------------------------------
# Get Repository Info
#-------------------------------------------------------------------
echo "Querying GitHub API for repository data"

core::getRepository REPO

REPO_NAME="${REPO['name']}"
REPO_DESC="${REPO['description']}"
REPO_URL="${REPO['html_url']}"
REPO_DEFAULT_BRANCH="${REPO['default_branch']}"
OWNER_LOGIN="${REPO['owner.login']}"
OWNER_ID="${REPO['owner.id']}"
OWNER_LOCATION="${REPO['owner.location']}"
OWNER_COMPANY="${REPO['owner.company']}"
OWNER_BLOG="${REPO['owner.blog']}"
OWNER_TWITTER="${REPO['owner.twitter_username']}"
#-------------------------------------------------------------------
# Get Previous Releases
#-------------------------------------------------------------------
echo "Querying GitHub API for previous releases"

core::getReleases RELEASES

if (( ${#RELEASES[@]} > 0 )); then
	core::parseVersion "$(echo "${RELEASES[0]}" | yq '.tag_name' -)" PREV_RELEASE
else
	core::parseVersion "0.0.0" PREV_RELEASE
	FIRST_RELEASE=true
fi
#-------------------------------------------------------------------
# Determine Current Version
#-------------------------------------------------------------------
echo "Determining current version"

core::getCurrent CURRENT_RELEASE
#-------------------------------------------------------------------
# Process Configuration Files
#-------------------------------------------------------------------
echo "Processing configuration files"

cfg::getPrimary

# The order that the configuration files are read in is important
# Earlier files serve as "default" configuration files with later
# files able to preferentially override any previous value
[[ -n "$CFG_BASE" ]] && cfg::parse "$CFG_BASE"

[[ -n "$STANDARD_CONFIG" ]] && CFG_TYPES="$(cfg::getFile "$STANDARD_CONFIG" "$CFG_TYPES_DEFAULT")"

[[ -n "$CFG_TYPES" ]] && [[ -f "$CFG_TYPES" ]] && cfg::parse "$CFG_TYPES"

cfg::parse "$CFG_FILE"

[[ -n "$CHANGELOG_TEMPLATE" ]] && TMPL_LOG="$(cfg::getFile "$CHANGELOG_TEMPLATE" "$CHANGELOG_TEMPLATE_DEFAULT")"
[[ -n "$RELEASE_TEMPLATE" ]] && TMPL_RELEASE="$(cfg::getFile "$RELEASE_TEMPLATE" "$RELEASE_TEMPLATE_DEFAULT")"
[[ -n "$PULL_REQUEST_TEMPLATE" ]] && TMPL_PULL="$(cfg::getFile "$PULL_REQUEST_TEMPLATE" "$PULL_REQUEST_TEMPLATE_DEFAULT")"
#-------------------------------------------------------------------
# Process Configuration Files
#-------------------------------------------------------------------
echo "Checking Git Config"

if ! git config --get user.email; then
	[[ -z "${GIT_USER_NAME}" ]] && err::exit "Git username not configured"
	[[ -z "${GIT_USER_EMAIL}" ]] && err::exit "Git email address not configured"
	git config --global user.name = "${GIT_USER_NAME}"
	git config --global user.email = "${GIT_USER_EMAIL}"
	echo "Git global user configuration set: ${GIT_USER_NAME} <${GIT_USER_EMAIL}>"
	git config --global push.autoSetupRemote true
	echo "Git global push.autoSetupRemote set: true"
fi
#-------------------------------------------------------------------
# Massage input variables
#-------------------------------------------------------------------
echo "Massage input variables"

case "$INPUT_TYPE" in
	auto)
		# PLACEHOLDER
		;;
	version)
		[[ -z "$INPUT_VERSION" ]] && err::exit "Bump Type = 'version', but no release version specified"
		;;
	patch)
		[[ "${PREV_RELEASE['version']}" == "0.0.0" ]] && err::exit "Bump Type 'patch', but no previous releases"
		;;
	minor)
		[[ "${PREV_RELEASE['version']}" == "0.0.0" ]] && err::exit "Bump Type 'minor', but no previous releases"
		;;
	major)
		[[ "${PREV_RELEASE['version']}" == "0.0.0" ]] && err::exit "Bump Type 'major', but no previous releases"
		;;
	*)
		err::exit "Invalid Bump Type"
		;;
esac

[[ -z "$INPUT_BRANCH" ]] && INPUT_BRANCH="${GITHUB_REF_NAME}"

[[ -n "$INPUT_VERSION" ]] && rm::parseVersion "$INPUT_VERSION" IN_RELEASE

echo "INPUT_VERSION = ${INPUT_VERSION}"
echo "INPUT_TYPE = ${INPUT_TYPE}"
echo "INPUT_BRANCH = ${INPUT_BRANCH}"
echo "INPUT_PRE_RELEASE = ${INPUT_PRE_RELEASE}"
echo "INPUT_DRAFT = ${INPUT_DRAFT}"
#-------------------------------------------------------------------
# Get Branches
#-------------------------------------------------------------------
BRANCH_CURRENT="$(git branch --show-current)"

# Build a list of branches
while read -r line; do
	line="$(echo "$line" | tr -d '\n')"
	BRANCHES+=("$line")
done <<< "$(git branch -l | sed 's/^\*\s*//')"

echo "Get source branch"

if [[ -n "$INPUT_BRANCH" ]]; then
	BRANCH_SOURCE="$INPUT_BRANCH"
elif [[ -n "$BRANCH_PATCH" ]] && [[ "$BRANCH_CURRENT" == "$BRANCH_PATCH/"* ]]; then
	BRANCH_SOURCE="$BRANCH_CURRENT"
elif [[ -n "$BRANCH_PROD" ]]; then
	BRANCH_SOURCE="$BRANCH_PROD"
else
	BRANCH_SOURCE="$BRANCH_CURRENT"
fi

arr::hasVal "$BRANCH_SOURCE" "${BRANCHES[@]}" || err::exit "Source branch '$BRANCH_SOURCE' not found"
#-------------------------------------------------------------------
# Get this release version
#-------------------------------------------------------------------

echo "::endgroup::"
