#!/usr/bin/env bash
# shellcheck disable=SC2154
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

#-------------------------------------------------------------------
# Initialisation
#-------------------------------------------------------------------
declare -Ax PROFILE

PROFILE["STARTTIME"]="$(date +%s.%N)"

trap 'err::errHandler "LINENO" "BASH_LINENO" "${BASH_COMMAND}" "${?}"' ERR

git config --global --add safe.directory "$GITHUB_WORKSPACE"
#-------------------------------------------------------------------
# Dependencies
#-------------------------------------------------------------------
source /usr/local/bin/scripts/vars.sh || { echo "::error::Unable to load dependency '/usr/local/bin/scripts/vars.sh'"; exit 1; }
source /usr/local/bin/scripts/utils.sh || { echo "::error::Unable to load dependency '/usr/local/bin/scripts/utils.sh'"; exit 1; }

#-------------------------------------------------------------------
# MAIN
#-------------------------------------------------------------------
echo "::group::📑 Configuring Release Manager"

# Get all git tags
echo "Querying git for latest tag ..."

latestTag="$(git tag -l --sort=version:refname | head -n 1)"

## shellcheck disable=SC2034
rm::parseVersion "$latestTag" "LATEST_TAG"

debug1="$(declare -p LATEST_TAG)"; echo "::debug::$debug1"

echo "Querying GitHub for latest release tag ..."

#url="https://api.github.com/repos/${GITHUB_REPOSITORY}/releases/latest"
url="https://api.github.com/repos/ragdata/.github/releases/latest"

result=$(curl -s "${HEADERS[@]}" -w '%{http_code}' "$url")

RESPONSE['code']=$(tail -n1 <<< "$result")
RESPONSE['body']=$(sed '$ d' <<< "$result")

echo "::debug::HTTP STATUS = ${RESPONSE['code']} @ $url"

[[ "${RESPONSE['code']}" != 200 ]] && err::exit "GitHub API returned status code ${RESPONSE['code']} @ $url"

if [[ "${#RESPONSE['body']}" -gt 0 ]]; then
	echo "${RESPONSE['body']}" | yq 'has("tag_name")' - && rm::parseVersion "$(echo "${RESPONSE['body']}" | yq '.tag_name' -)" "LATEST_REPO_TAG"
fi

# Look for current version in config
echo "Querying configuration file for current version ..."

if [[ -f "$cfgFile" ]]; then
	if yq 'has("version")' "$cfgFile"; then
		echo "Current version obtained from configuration file"
		rm::parseVersion "$(yq '.version' "$cfgFile")" "CURRENT_VERSION"
	fi
elif (( ${#LATEST_REPO_TAG[@]} )); then
	echo "Current version obtained from GitHub Release"
	rm::parseVersion "${LATEST_REPO_TAG['version']}" "CURRENT_VERSION"
else
	echo "Current version assigned as default first version"
	# shellcheck disable=SC2034
	rm::parseVersion "0.1.0" "CURRENT_VERSION"
fi

echo "::debug::CURRENT_VERSION = ${CURRENT_VERSION['full']}"

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

rm::readConfig "$cfgFile"

echo "Checking Git Config ..."

if ! git config --get user.email; then
	[[ -z "$GIT_USER_NAME" ]] && err::exit "Git username not configured"
	[[ -z "$GIT_USER_EMAIL" ]] && err::exit "No email address configured"
	git config --global user.name = "$GIT_USER_NAME"
	git config --global user.email = "$GIT_USER_EMAIL"
	echo "Git global user configuration set: $GIT_USER_NAME <$GIT_USER_EMAIL>"
fi

echo "Get input variables ..."

case "$INPUT_TYPE" in
	version)
		[[ -z "$INPUT_VERSION" ]] && err::exit "Bump Type = 'version', but no release version specified"
		;;
	first)
		[[ -z "$INPUT_VERSION" ]] && INPUT_VERSION="1.0.0"
		;;
	patch)
		(( "${#LATEST_REPO_TAG[@]}" )) || err::exit "Bump Type = 'patch', but no previous releases"
		;;
	minor)
		(( "${#LATEST_REPO_TAG[@]}" )) || err::exit "Bump Type = 'minor', but no previous releases"
		;;
	major)
		(( "${#LATEST_REPO_TAG[@]}" )) || err::exit "Bump Type = 'major', but no previous releases"
		;;
	*)
		err::exit "Invalid Bump Type"
		;;
esac

[[ -z "$INPUT_BRANCH" ]] && INPUT_BRANCH="${GITHUB_REF_NAME}"

[[ -n "$INPUT_VERSION" ]] && rm::parseVersion "$INPUT_VERSION" "IN_VERSION"

echo "INPUT_VERSION = ${INPUT_VERSION}"
echo "INPUT_TYPE = ${INPUT_TYPE}"
echo "INPUT_BRANCH = ${INPUT_BRANCH}"
echo "INPUT_PRE_RELEASE = ${INPUT_PRE_RELEASE}"
echo "INPUT_DRAFT = ${INPUT_DRAFT}"

echo "Get release version ..."

releaseTag=""
tagPrefix=""
tagSuffix=""
tagBuild=""

$INPUT_PRE_RELEASE && tagSuffix="-alpha"

case "$INPUT_TYPE" in
	version)
		if [[ -n "${IN_VERSION['prefix']}" ]]; then tagPrefix="${IN_VERSION['prefix']}"; else tagPrefix="$PREFIX"; fi
		if $INPUT_PRE_RELEASE && [[ "${IN_VERSION['suffix']}" ]]; then tagSuffix="${IN_VERSION['suffix']}"; fi
		if [[ -n "${IN_VERSION['build']}" ]]; then tagBuild="+${IN_VERSION['build']}"; fi
		releaseTag="$tagPrefix${IN_VERSION['version']}$tagSuffix$tagBuild"
		;;
	first)
		releaseTag="$tagPrefix${IN_VERSION['version']}$tagSuffix"
		;;
	patch)
		tagDigit="${LATEST_REPO_TAG['patch']}"
		((tagDigit+=1))
		releaseTag="$tagPrefix${LATEST_REPO_TAG['major']}.${LATEST_REPO_TAG['minor']}.$tagDigit$tagSuffix"
		;;
	minor)
		tagDigit="${LATEST_REPO_TAG['minor']}"
		((tagDigit+=1))
		releaseTag="$tagPrefix${LATEST_REPO_TAG['major']}.$tagDigit.0$tagSuffix"
		;;
	major)
		tagDigit="${LATEST_REPO_TAG['major']}"
		((tagDigit+=1))
		releaseTag="$tagPrefix$tagDigit.0.0$tagSuffix"
		;;
esac

echo "Release Version: $releaseTag"

rm::parseVersion "$releaseTag" "RELEASE_VERSION"

echo "::endgroup::"



#-------------------------------------------------------------------
# Configuration
#-------------------------------------------------------------------
#echo "::group::🎁 Processing ..."
#rm::getReleaseTag
##rm::createBranch
##rm::createTag
#echo "::endgroup::"

#-------------------------------------------------------------------
# Write Job Summary
#-------------------------------------------------------------------
summaryTable="
| Variable	   | Value		                |
|:-------------|:--------------------------:|
| Release Tag  | ${RELEASE_VERSION['full']} |
"

cat << EOF >> "$GITHUB_STEP_SUMMARY"
### :gift: Ragdata's Release Manager Action Summary
$summaryTable
EOF

exit 0
