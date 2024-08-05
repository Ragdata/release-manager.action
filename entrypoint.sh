#!/usr/bin/env bash
# shellcheck disable=SC2034
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

####################################################################
# Initialisation
####################################################################
declare -Ax PROFILE

PROFILE["STARTTIME"]="$(date +%s.%N)"

trap 'err::errHandler "LINENO" "BASH_LINENO" "${BASH_COMMAND}" "${?}"' ERR

git config --global --add safe.directory "$GITHUB_WORKSPACE"
####################################################################
# Dependencies
####################################################################
source /usr/local/bin/scripts/regex.sh || { echo "::error::Unable to load dependency '/usr/local/bin/scripts/regex.sh'"; exit 1; }
source /usr/local/bin/scripts/vars.sh || { echo "::error::Unable to load dependency '/usr/local/bin/scripts/vars.sh'"; exit 1; }
source /usr/local/bin/scripts/config.sh || { echo "::error::Unable to load dependency '/usr/local/bin/scripts/config.sh'"; exit 1; }
source /usr/local/bin/scripts/utils.sh || { echo "::error::Unable to load dependency '/usr/local/bin/scripts/utils.sh'"; exit 1; }
source /usr/local/bin/scripts/builder.sh || { echo "::error::Unable to load dependency '/usr/local/bin/scripts/builder.sh'"; exit 1; }
source /usr/local/bin/scripts/ghapi.sh || { echo "::error::Unable to load dependency '/usr/local/bin/scripts/ghapi.sh'"; exit 1; }

####################################################################
# MAIN
####################################################################
echo "::group::📑 Configuring Release Manager"

##-------------------------------------------------------------------
## Get latest git tag
##-------------------------------------------------------------------
#echo "Querying git for latest tag ..."
#
#latestTag="$(git tag -l --sort=version:refname | head -n 1)"
#
#if [[ -n "$latestTag" ]]; then
#	rm::parseVersion "$latestTag" LATEST_TAG
#else
#	rm::parseVersion "0.0.0" LATEST_TAG
#fi
#
#debug1="$(declare -p LATEST_TAG)"; echo "::debug::$debug1"

#-------------------------------------------------------------------
# Get latest release tag
#-------------------------------------------------------------------
echo "Querying GitHub for latest release tag ..."

result=$(gh::latestRelease)

RESPONSE['code']=$(tail -n1 <<< "$result")
RESPONSE['body']=$(sed '$ d' <<< "$result")

echo "::debug::HTTP STATUS = ${RESPONSE['code']}"

case "${RESPONSE['code']}" in
	200)
		echo "${RESPONSE['body']}" | yq 'has("tag_name")' - && rm::parseVersion "$(echo "${RESPONSE['body']}" | yq '.tag_name' -)" "LATEST_REPO_TAG"
		;;
	404)
		rm::parseVersion "0.0.0" LATEST_REPO_TAG
		isFirst=true
		;;
	*)
		err::exit "GitHub API returned status code ${RESPONSE['code']}"
		;;
esac

#-------------------------------------------------------------------
# Look for current version in config
#-------------------------------------------------------------------
echo "Querying configuration file for current version ..."

if [[ -f "$cfgFile" ]]; then
	if yq 'has("version")' "$cfgFile"; then
		echo "Current version obtained from configuration file"
		rm::parseVersion "$(yq '.version' "$cfgFile")" CURRENT_VERSION
	fi
elif [[ "${LATEST_REPO_TAG['version']}" != "0.0.0" ]]; then
	echo "Current version obtained from GitHub Release"
	rm::parseVersion "${LATEST_REPO_TAG['version']}" CURRENT_VERSION
else
	echo "Current version assigned as default first version"
	# shellcheck disable=SC2034
	rm::parseVersion "0.1.0" CURRENT_VERSION
fi

echo "::debug::CURRENT_VERSION = ${CURRENT_VERSION['full']}"

#-------------------------------------------------------------------
# Check / read config files
#-------------------------------------------------------------------
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

cfg::read "$cfgFile"

#-------------------------------------------------------------------
# Check git config
#-------------------------------------------------------------------
echo "Checking Git Config ..."

if ! git config --get user.email; then
	[[ -z "$GIT_USER_NAME" ]] && err::exit "Git username not configured"
	[[ -z "$GIT_USER_EMAIL" ]] && err::exit "No email address configured"
	git config --global user.name = "$GIT_USER_NAME"
	git config --global user.email = "$GIT_USER_EMAIL"
	echo "Git global user configuration set: $GIT_USER_NAME <$GIT_USER_EMAIL>"
	git config --global push.autoSetupRemote true
	echo "Git global push.autoSetupRemote set: true"
fi

#-------------------------------------------------------------------
# Get input variables
#-------------------------------------------------------------------
echo "Get input variables ..."

case "$INPUT_TYPE" in
	auto)
		# PLACEHOLDER
		;;
	version)
		[[ -z "$INPUT_VERSION" ]] && err::exit "Bump Type = 'version', but no release version specified"
		;;
	patch)
		[[ "${LATEST_REPO_TAG['version']}" == "0.0.0" ]] && err::exit "Bump Type = 'patch', but no previous releases"
		;;
	minor)
		[[ "${LATEST_REPO_TAG['version']}" == "0.0.0" ]] && err::exit "Bump Type = 'minor', but no previous releases"
		;;
	major)
		[[ "${LATEST_REPO_TAG['version']}" == "0.0.0" ]] && err::exit "Bump Type = 'major', but no previous releases"
		;;
	*)
		err::exit "Invalid Bump Type"
		;;
esac

[[ -z "$INPUT_BRANCH" ]] && INPUT_BRANCH="${GITHUB_REF_NAME}"

[[ -n "$INPUT_VERSION" ]] && rm::parseVersion "$INPUT_VERSION" IN_VERSION

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

echo "Get source branch ..."

# Get source branch
if [[ -n "$INPUT_BRANCH" ]]; then
	BRANCH_SOURCE="$INPUT_BRANCH"
elif [[ -n "$BRANCH_PROD" ]]; then
	BRANCH_SOURCE="$BRANCH_PROD"
else
	BRANCH_SOURCE="$BRANCH_CURRENT"
fi

arr::hasVal "$BRANCH_SOURCE" "${BRANCHES[@]}" || err::exit "Source branch '$BRANCH_SOURCE' not found"
#-------------------------------------------------------------------
# Get next release version
#-------------------------------------------------------------------
echo "Get release version ..."

releaseTag="$(rm::getReleaseVersion)"

echo "Release Version: $releaseTag"

rm::parseVersion "$releaseTag" "RELEASE_VERSION"

CFG['release_version']="${RELEASE_VERSION['full']}"
CFG['release_url']="https://github.com/$GITHUB_REPOSITORY/releases/tag/${RELEASE_VERSION['full']}"
CFG['release_date']="$(date '+%b %d, %Y')"
if [[ "$isFirst" ]]; then CFG['release_notes']="First Release"; else CFG['release_notes']="NOTES"; fi

echo "::endgroup::"

#-------------------------------------------------------------------
# Configuration
#-------------------------------------------------------------------
echo "::group::🎁 Processing ..."

#-------------------------------------------------------------------
# Check / Checkout branches
#-------------------------------------------------------------------

echo "Checking out source branch ..."

# Checkout source branch
if [[ "$BRANCH_CURRENT" != "$BRANCH_SOURCE" ]]; then
	git checkout "$BRANCH_SOURCE" || err::exit "Failed to checkout source branch '$BRANCH_SOURCE'"
fi

[[ "$(git status -s | head -c1 | wc -c)" -ne 0 ]] && err::exit "Commit staged / unversioned files first, then re-run workflow"

# Create release branch
echo "Checking out release branch ..."

releaseBranch="$BRANCH_RELEASE/$releaseTag"

git checkout -b "$releaseBranch" "$BRANCH_SOURCE" || err::exit "Failed to create requested branch '$releaseBranch'"

#-------------------------------------------------------------------
# Write config file if required
#-------------------------------------------------------------------
if [[ ! -f "$GITHUB_WORKSPACE/.github/.release.yml" ]]; then
	echo "Creating release manager config file ..."
	if [[ -f "$TMP_DIR/.release.yml" ]]; then
		cp "$TMP_DIR/.release.yml" "$GITHUB_WORKSPACE/.github/.release.yml" || err::exit "Unable to copy config file from '$TMP_DIR/.release.yml' to '$GITHUB_WORKSPACE/.github/.release.yml'"
	else
		if [[ -f "$cfgDefault" ]]; then
			envsubst < "$cfgDefault" > "$GITHUB_WORKSPACE/.github/.release.yml" || err::exit "Unable to write config file '$GITHUB_WORKSPACE/.github/.release.yml'"
		else
			err::exit "Unable to find default configuration file"
		fi
	fi
fi

#-------------------------------------------------------------------
# Write changelog if required
#-------------------------------------------------------------------
if [[ "$CHANGELOG" ]]; then
	changelogDot="🟢"
	bld::changelog
else
	changelogDot="🔴"
fi

#-------------------------------------------------------------------
# Update release config
#-------------------------------------------------------------------
echo "Updating release config file"
yq -i ".version = \"$releaseTag\"" "$GITHUB_WORKSPACE/.github/.release.yml"

#-------------------------------------------------------------------
# Add / Commit files
#-------------------------------------------------------------------
echo "Committing changes to git"
[[ "$(git ls-files -o --directory --exclude-standard | sed q | wc -l)" -gt 0 ]] && git add .
git commit -am "$MESSAGE_COMMIT"
git push

#-------------------------------------------------------------------
# Tag release
#-------------------------------------------------------------------
echo "Tagging release"
git tag "$releaseTag"
git push --tags


echo "::endgroup::"


#-------------------------------------------------------------------
# Write Job Summary
#-------------------------------------------------------------------
summaryTable="
| Variable	     | Value		  |
|:---------------|:--------------:|
| Release Tag    | $releaseTag	  |
| Source Branch  | $sourceBranch  |
| Release Branch | $releaseBranch |
| CHANGELOG      | $changelogDot  |
"

cat << EOF >> "$GITHUB_STEP_SUMMARY"
### :gift: Ragdata's Release Manager Action Summary
$summaryTable
EOF

exit 0
