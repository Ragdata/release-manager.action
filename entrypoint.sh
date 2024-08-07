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

#-------------------------------------------------------------------
# REPOSITORY
#-------------------------------------------------------------------
echo "Querying GitHub API for repository data"

rm::getRepository REPO
#-------------------------------------------------------------------
# RELEASES
#-------------------------------------------------------------------
echo "Querying GitHub API for latest releases"

rm::getReleases RELEASES

echo "Getting latest release info"

if [[ "${#RELEASES[@]}" -gt 0 ]]; then
	rm::parseVersion "$(echo "${RELEASES[0]}" | yq '.tag_name' -)" LATEST_RELEASE
else
	rm::parseVersion "0.0.0" LATEST_RELEASE
	FIRST_RELEASE=true
fi

#-------------------------------------------------------------------
# GET CONFIG FILES
#-------------------------------------------------------------------
echo "Checking configuration files"

cfg::get

#-------------------------------------------------------------------
# CURRENT VERSION
#-------------------------------------------------------------------
echo "Determine current version"

if [[ -n "$cfgFile" ]] && [[ "$cfgFile" != "$tmpFile" ]]; then
	if yq 'has("version")' "$cfgFile"; then
		echo "Current version obtained from config file"
		rm::parseVersion "$(yq '.version' "$cfgFile")" CURRENT_VERSION
	fi
elif [[ "${LATEST_RELEASE['version']}" != "0.0.0" ]]; then
	echo "Current version obtained from latest release"
	rm::parseVersion "${LATEST_RELEASE['full']}" CURRENT_VERSION
elif [[ -n "$cfgBase" ]]; then
	if yq 'has("version")' "$cfgBase"; then
		echo "Current version obtained from base config file"
		rm::parseVersion "$(yq '.version' "$cfgBase")" CURRENT_VERSION
	fi
else
	echo "Current version assigned as default first version"
	rm::parseVersion "v0.1.0" CURRENT_VERSION
fi

VERSION="${CURRENT_VERSION['full']}"
CFG['version']="$VERSION"

echo "CURRENT_VERSION = $VERSION"

#-------------------------------------------------------------------
# SET / READ CONFIG FILES
#-------------------------------------------------------------------
echo "Setting configuration files"

cfg::set

#-------------------------------------------------------------------
# Check / read config files
#-------------------------------------------------------------------
echo "Reading configuration files ..."

[[ -f "$cfgBase" ]] && cfg::read "$cfgBase" CFG
[[ -f "$cfgTypes" ]] && cfg::read "$cfgTypes" CFG
[[ -f "$cfgFile" ]] && cfg::read "$cfgFile" CFG

#-------------------------------------------------------------------
# Check git config
#-------------------------------------------------------------------
echo "Checking Git Config ..."

if ! git config --get user.email; then
	[[ -z "${CFG['git_user.name']}" ]] && err::exit "Git username not configured"
	[[ -z "${CFG['git_user.email']}" ]] && err::exit "Git email address not configured"
	git config --global user.name = "${CFG['git_user.name']}"
	git config --global user.email = "${CFG['git_user.email']}"
	echo "Git global user configuration set: ${CFG['git_user.name']} <${CFG['git_user.email']}>"
	git config --global push.autoSetupRemote true
	echo "Git global push.autoSetupRemote set: true"
fi

#-------------------------------------------------------------------
# Massage input variables
#-------------------------------------------------------------------
echo "Massage input variables ..."

case "$INPUT_TYPE" in
	auto)
		# PLACEHOLDER
		;;
	version)
		[[ -z "$INPUT_VERSION" ]] && err::exit "Bump Type = 'version', but no release version specified"
		;;
	patch)
		[[ "${LATEST_RELEASE['version']}" == "0.0.0" ]] && err::exit "Bump Type 'patch', but no previous releases"
		;;
	minor)
		[[ "${LATEST_RELEASE['version']}" == "0.0.0" ]] && err::exit "Bump Type 'minor', but no previous releases"
		;;
	major)
		[[ "${LATEST_RELEASE['version']}" == "0.0.0" ]] && err::exit "Bump Type 'major', but no previous releases"
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
BRANCH_PROD="${CFG['branch.prod']}"
BRANCH_STAGE="${CFG['branch.stage']}"
BRANCH_PATCH="${CFG['branch.patch']}"
BRANCH_RELEASE="${CFG['branch.release']}"

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

rm::parseVersion "$releaseTag" RELEASE_VERSION

CFG['release_version']="${RELEASE_VERSION['full']}"
CFG['release_url']="https://github.com/$GITHUB_REPOSITORY/releases/tag/${RELEASE_VERSION['full']}"
CFG['release_date']="$(date "${CFG['date_format.short']}")"
#@TODO release.md template inclusion
if [[ "$FIRST_RELEASE" ]]; then CFG['release_notes']="_**First Release**_"; else CFG['release_notes']="NOTES"; fi

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
# Write config files if required
#-------------------------------------------------------------------
echo "Writing repository configuration files ..."

cfg::write

#-------------------------------------------------------------------
# Write changelog if required
#-------------------------------------------------------------------
if [[ "${CFG['changelog.create']}" ]]; then
	changelogDot="🟢"
	bld::changelog
else
	changelogDot="🔴"
fi

#-------------------------------------------------------------------
# Update release config
#-------------------------------------------------------------------
echo "Updating release config file"
yq -i ".version = \"$releaseTag\"" "$GITHUB_WORKSPACE/.github/release.yml"

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
