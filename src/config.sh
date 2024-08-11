#!/usr/bin/env bash
# shellcheck disable=SC2091
####################################################################
# config.sh
####################################################################
# Release Manager Docker Action - Config Functions
#
# File:         config.sh
# Author:       Ragdata
# Date:         11/08/2024
# License:      MIT License
# Copyright:    Copyright © 2024 Redeyed Technologies
####################################################################
# CONFIG FUNCTIONS
####################################################################
cfg::getFile()
{
	local file="$1"
	local default="$2"
	local dir outFile

	for dir in "${SEARCH_DIRS[@]}"
	do
		[ -f "$dir/$file" ] && outFile="$dir/$file"
	done

	[ -z "$outFile" ] && outFile="$default"

	printf -- '%s' "$outFile"
}

cfg::getPrimary()
{
	local extends

	CFG_FILE="$(cfg::getFile relman.yml "$CFG_DEFAULT")"

	[[ "$(yq 'has("extends")' "$CFG_FILE")" ]] && extends="$(yq '.extends' "$CFG_FILE")"

	[[ -n "$extends" ]] && CFG_BASE="$(cfg::getFile "$extends" "$CFG_BASE_DEFAULT")"

	if [[ "$CFG_FILE" == "$CFG_FILE_DEFAULT" ]]; then
		echo "Creating temporary configuration file"
		TMP_CFG_FILE="$TMP_DIR/relman.yml"
		envsubst < "$CFG_FILE" > "$TMP_CFG_FILE" || err::exit "Failed to write temporary config file '$TMP_CFG_FILE'"
		CFG_FILE="$TMP_CFG_FILE"
	fi

	if [[ -n "$CFG_BASE" ]] && [[ "$CFG_BASE" == "$CFG_BASE_DEFAULT" ]]; then
		echo "Creating temporary base configuration file"
		TMP_CFG_BASE="$TMP_DIR/relman.base.yml"
		envsubst < "$CFG_BASE" > "$TMP_CFG_BASE" || err::exit "Failed to write temporary base config file '$TMP_CFG_BASE'"
		CFG_BASE="$TMP_CFG_BASE"
	fi
}

cfg::parse()
{
	local filePath="$1"

	[ -f "$filePath" ] || err::exit "Configuration file '$filePath' not found"

	echo "Parsing configuration file '$filePath'"

	cfg::validate "$filePath"

	$(yq 'has("name")' "$filePath") && { REPO_NAME="$(yq '.name' "$filePath")"; echo "::debug::.name = ${REPO_NAME}"; }
	$(yq 'has("description")' "$filePath") && { REPO_DESC="$(yq '.description' "$filePath")"; echo "::debug::.description = ${REPO_DESC}"; }
	$(yq 'has("copyright")' "$filePath") && { COPYRIGHT="$(yq '.copyright' "$filePath")"; echo "::debug::.copyright = ${COPYRIGHT}"; }
	$(yq 'has("website")' "$filePath") && { WEBSITE="$(yq '.website' "$filePath")"; echo "::debug::.website = ${WEBSITE}"; }
	$(yq 'has("repo_url")' "$filePath") && { REPO_URL="$(yq '.repo_url' "$filePath")"; echo "::debug::.repo_url = ${REPO_URL}"; }
	if $(yq 'has("authors")' "$filePath"); then
		yq -o=j -I4 '.authors' "$filePath" > "$TMP_DIR/authors.json"
	fi
	if $(yq 'has("git_user")' "$filePath"); then
		$(yq '.git_user | has("name")' "$filePath") && { GIT_USER_NAME="$(yq '.git_user.name' "$filePath")"; echo "::debug::.git_user.name = ${GIT_USER_NAME}"; }
		$(yq '.git_user | has("email")' "$filePath") && { GIT_USER_EMAIL="$(yq '.git_user.email' "$filePath")"; echo "::debug::.git_user.email = ${GIT_USER_EMAIL}"; }
	fi
	if $(yq 'has("branch")' "$filePath"); then
		$(yq '.branch | has("prod")' "$filePath") && { BRANCH_PROD="$(yq '.branch.prod' "$filePath")"; echo "::debug::.branch.prod = ${BRANCH_PROD}"; }
		$(yq '.branch | has("stage")' "$filePath") && { BRANCH_STAGE="$(yq '.branch.stage' "$filePath")"; echo "::debug::.branch.stage = ${BRANCH_STAGE}"; }
		$(yq '.branch | has("patch")' "$filePath") && { BRANCH_PATCH="$(yq '.branch.patch' "$filePath")"; echo "::debug::.branch.patch = ${BRANCH_PATCH}"; }
		$(yq '.branch | has("release")' "$filePath") && { BRANCH_RELEASE="$(yq '.branch.release' "$filePath")"; echo "::debug::.branch.release = ${BRANCH_RELEASE}"; }
	fi
	if $(yq 'has("date_format")' "$filePath"); then
		$(yq '.date_format | has("short")' "$filePath") && { DATE_FORMAT_SHORT="$(yq '.date_format.short' "$filePath")"; echo "::debug::.date_format.short = ${DATE_FORMAT_SHORT}"; }
		$(yq '.date_format | has("long")' "$filePath") && { DATE_FORMAT_LONG="$(yq '.date_format.long' "$filePath")"; echo "::debug::.date_format.long = ${DATE_FORMAT_LONG}"; }
		$(yq '.date_format | has("dtg")' "$filePath") && { DATE_FORMAT_DTG="$(yq '.date_format.dtg' "$filePath")"; echo "::debug::.date_format.dtg = ${DATE_FORMAT_DTG}"; }
	fi
	if $(yq 'has("message")' "$filePath"); then
		$(yq '.message | has("commit")' "$filePath") && { MESSAGE_COMMIT="$(yq '.message.commit' "$filePath")"; echo "::debug::.message.commit = ${MESSAGE_COMMIT}"; }
		$(yq '.message | has("release")' "$filePath") && { MESSAGE_RELEASE="$(yq '.message.release' "$filePath")"; echo "::debug::.message.release = ${MESSAGE_RELEASE}"; }
	fi
	if $(yq 'has("changelog")' "$filePath"); then
		$(yq '.changelog | has("template")' "$filePath") && { CHANGELOG_TEMPLATE="$(yq '.changelog.template' "$filePath")"; echo "::debug::.changelog.template = ${CHANGELOG_TEMPLATE}"; }
		$(yq '.changelog | has("file")' "$filePath") && { CHANGELOG_FILE="$(yq '.changelog.file' "$filePath")"; echo "::debug::.changelog.file = ${CHANGELOG_FILE}"; }
		$(yq '.changelog | has("style")' "$filePath") && { CHANGELOG_STYLE="$(yq '.changelog.style' "$filePath")"; echo "::debug::.changelog.style = ${CHANGELOG_STYLE}"; }
		$(yq '.changelog | has("create")' "$filePath") && { CHANGELOG_CREATE="$(yq '.changelog.create' "$filePath")"; echo "::debug::.changelog.create = ${CHANGELOG_CREATE}"; }
	fi
	if $(yq 'has("release")' "$filePath"); then
		$(yq '.release | has("template")' "$filePath") && { RELEASE_TEMPLATE="$(yq '.release.template' "$filePath")"; echo "::debug::.release.template = ${RELEASE_TEMPLATE}"; }
		$(yq '.release | has("create")' "$filePath") && { RELEASE_CREATE="$(yq '.release.create' "$filePath")"; echo "::debug::.release.create = ${RELEASE_CREATE}"; }
	fi
	if $(yq 'has("pull_request")' "$filePath"); then
		$(yq '.pull_request | has("template")' "$filePath") && { PULL_REQUEST_TEMPLATE="$(yq '.pull_request.template' "$filePath")"; echo "::debug::.pull_request.template = ${PULL_REQUEST_TEMPLATE}"; }
		$(yq '.pull_request | has("create")' "$filePath") && { PULL_REQUEST_CREATE="$(yq '.pull_request.create' "$filePath")"; echo "::debug::.pull_request.create = ${PULL_REQUEST_CREATE}"; }
	fi
	if $(yq 'has("standard")' "$filePath"); then
		$(yq '.standard | has("config")' "$filePath") && { STANDARD_CONFIG="$(yq '.standard.config' "$filePath")"; echo "::debug::.standard.config = ${STANDARD_CONFIG}"; }
		$(yq '.standard | has("name")' "$filePath") && { STANDARD_NAME="$(yq '.standard.name' "$filePath")"; echo "::debug::.standard.name = ${STANDARD_NAME}"; }
		$(yq '.standard | has("url")' "$filePath") && { STANDARD_URL="$(yq '.standard.url' "$filePath")"; echo "::debug::.standard.url = ${STANDARD_URL}"; }
		$(yq '.standard | has("create")' "$filePath") && { STANDARD_CREATE="$(yq '.standard.create' "$filePath")"; echo "::debug::.standard.create = ${STANDARD_CREATE}"; }
	fi
	if $(yq 'has("commit_types")' "$filePath"); then
		yq -o=j -I4 '.commit_types' "$filePath" > "$TMP_DIR/commit_types.json"
	fi
	if $(yq 'has("commit_scopes")' "$filePath"); then
		yq -o=j -I4 '.commit_scopes' "$filePath" > "$TMP_DIR/commit_scopes.json"
	fi
	if $(yq 'has("logged_types")' "$filePath"); then
		# shellcheck disable=SC2034
		readarray LOGGED_TYPES < <(yq '.logged_types[]' "$filePath")
	fi
	if $(yq 'has("logged_scopes")' "$filePath"); then
		# shellcheck disable=SC2034
		readarray LOGGED_SCOPES < <(yq '.logged_scopes[]' "$filePath")
	fi
}

cfg::validate()
{
	[[ -z "${1}" ]] && err::exit "No Configuration Filepath Passed!"
	[[ -f "${1}" ]] || err::exit "Configuration Filepath '${1}' Not Found!"
	$(yq --exit-status 'tag == "!!map" or tag == "!!seq"' "${1}") || err::exit "Invalid Configuration File '${1}'"
	echo "Configuration File '${1}' Validated"
}
