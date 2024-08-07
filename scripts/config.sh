#!/usr/bin/env bash
# shellcheck disable=SC2034
# shellcheck disable=SC2091
####################################################################
# config.sh
####################################################################
# Release Manager Docker Action - Config Functions
#
# File:         config.sh
# Author:       Ragdata
# Date:         02/08/2024
# License:      MIT License
# Copyright:    Copyright © 2024 Redeyed Technologies
####################################################################
# CONFIG FUNCTIONS
####################################################################
cfg::get()
{
	#local extends types changelog release
	local extends
	local types changelog_template changelog_file release_template pull_request_template

	# release.yml
	for dir in "${SEARCH_DIRS[@]}"; do
		[[ -f "$dir/release.yml" ]] && cfgFile="$dir/release.yml"
	done

	[[ -z "$cfgFile" ]] && cfgFile="$CFG_DIR/release.yml"

	# Check if main config file extends base config file
	$(yq 'has("extends")' "$cfgFile") && extends="$(yq '.extends' "$cfgFile")"

	# release.base.yml
	if [[ -n "$extends" ]]; then
		for dir in "${SEARCH_DIRS[@]}"; do
			[[ -f "$dir/$extends" ]] && cfgBase="$dir/$extends"
		done
		[[ -z "$cfgBase" ]] && cfgBase="$CFG_DIR/release.base.yml"
		$(yq '.standard | has("config")' "$cfgBase") && types="$(yq '.standard.config' "$cfgBase")"
		$(yq '.changelog | has("template")' "$cfgBase") && changelog_template="$(yq '.changelog.template' "$cfgBase")"
		$(yq '.changelog | has("file")' "$cfgBase") && changelog_file="$(yq '.changelog.file' "$cfgBase")"
		$(yq '.release | has("template")' "$cfgBase") && release_template="$(yq '.release.template' "$cfgBase")"
		$(yq '.pull_request | has("template")' "$cfgBase") && pull_request_template="$(yq '.pull_request.template' "$cfgBase")"
	fi

	# Elements in main config file override elements in base config file
	$(yq '.standard | has("config")' "$cfgFile") && types="$(yq '.standard.config' "$cfgFile")"
	$(yq '.changelog | has("template")' "$cfgFile") && changelog_template="$(yq '.changelog.template' "$cfgFile")"
	$(yq '.changelog | has("file")' "$cfgFile") && changelog_file="$(yq '.changelog.file' "$cfgFile")"
	$(yq '.release | has("template")' "$cfgFile") && release_template="$(yq '.release.template' "$cfgFile")"
	$(yq '.pull_request | has("template")' "$cfgFile") && pull_request_template="$(yq '.pull_request.template' "$cfgFile")"

	# Set to default filename if still empty
	[[ -z "$types" ]] && types="types.conventional.yml"
	[[ -z "$changelog_template" ]] && changelog_template="changelog.md"
	[[ -z "$changelog_file" ]] && changelog_file="CHANGELOG.md"
	[[ -z "$release" ]] && release_template="release.md"
	[[ -z "$pull_request" ]] && pull_request_template="pull_request.md"

	# remainder
	for dir in "${SEARCH_DIRS[@]}"; do
		[[ -f "$dir/$types" ]] && cfgTypes="$dir/$types"
		[[ -f "$dir/$changelog_template" ]] && logTmpl="$dir/$changelog_template"
		[[ -f "$dir/$release_template" ]] && relTmpl="$dir/$release_template"
		[[ -f "$dir/$pull_request_template" ]] && pullTmpl="$dir/$pull_request_template"
	done

	[[ -z "$logFile" ]] && logFile="$GITHUB_WORKSPACE/$changelog_file"

	# Set to default path if still empty
	[[ -z "$cfgTypes" ]] && cfgTypes="$CFG_DIR/types.conventional.yml"
	[[ -z "$cfgDefault" ]] && cfgDefault="$CFG_DIR/release.yml"
	[[ -z "$cfgDefaultBase" ]] && cfgDefaultBase="$CFG_DIR/release.base.yml"
	[[ -z "$logTmpl" ]] && logTmpl="$CFG_DIR/changelog.md"
	[[ -z "$logFile" ]] && logFile="$GITHUB_WORKSPACE/CHANGELOG.md"
	[[ -z "$relTmpl" ]] && relTmpl="$CFG_DIR/release.md"
	[[ -z "$pullTmpl" ]] && pullTmpl="$CFG_DIR/pull_request.md"
}

cfg::set()
{
	# If we're STILL using the default configuration files
	# replace values in each file and save to temp dir
	if [[ "$cfgFile" == "$CFG_DIR/release.yml" ]]; then
		echo "Creating temporary config file"
		tmpFile="$TMP_DIR/release.yml"
		envsubst < "$cfgFile" > "$tmpFile" || err::exit "Failed to write temporary config file '$tmpFile'"
		cfgFile="$tmpFile"
	fi
	if [[ "$cfgBase" == "$CFG_DIR/release.base.yml" ]]; then
		echo "Creating temporary base config file"
		tmpBase="$TMP_DIR/release.base.yml"
		envsubst < "$cfgBase" > "$tmpBase" || err::exit "Failed to write temporary base config file '$tmpBase'"
		cfgBase="$tmpBase"
	fi
}

cfg::read()
{
	local filePath="$1"
	local -n arr="$2"

	[[ -f "$filePath" ]] || err::exit "Configuration file '$filePath' not found"

	echo "Parsing configuration file '$filePath'"

	cfg::validate "$filePath"

	$(yq 'has("name")' "$filePath") && { arr['name']="$(yq '.name' "$filePath")"; echo "::debug::.name = ${arr['name']}"; }
	$(yq 'has("description")' "$filePath") && { arr['description']="$(yq '.description' "$filePath")"; echo "::debug::.description = ${arr['description']}"; }
	$(yq 'has("website")' "$filePath") && { arr['website']="$(yq '.website' "$filePath")"; echo "::debug::.website = ${arr['website']}"; }
	$(yq 'has("repo_url")' "$filePath") && { arr['repo_url']="$(yq '.repo_url' "$filePath")"; echo "::debug::.repo_url = ${arr['repo_url']}"; }
	if $(yq 'has("authors")' "$filePath"); then
		yq -o=j -I4 '.authors' "$filePath" > "$TMP_DIR/authors.json"
	fi
	if $(yq 'has("git_user")' "$filePath"); then
		$(yq '.git_user | has("name")' "$filePath") && { arr['git_user.name']="$(yq '.git_user.name' "$filePath")"; echo "::debug::.git_user.name = ${arr['git_user.name']}"; }
		$(yq '.git_user | has("email")' "$filePath") && { arr['git_user.email']="$(yq '.git_user.email' "$filePath")"; echo "::debug::.git_user.email = ${arr['git_user.email']}"; }
	fi
	if $(yq 'has("branch")' "$filePath"); then
		$(yq '.branch | has("prod")' "$filePath") && { arr['branch.prod']="$(yq '.branch.prod' "$filePath")"; echo "::debug::.branch.prod = ${arr['branch.prod']}"; }
		$(yq '.branch | has("stage")' "$filePath") && { arr['branch.stage']="$(yq '.branch.stage' "$filePath")"; echo "::debug::.branch.stage = ${arr['branch.stage']}"; }
		$(yq '.branch | has("patch")' "$filePath") && { arr['branch.patch']="$(yq '.branch.patch' "$filePath")"; echo "::debug::.branch.patch = ${arr['branch.patch']}"; }
		$(yq '.branch | has("release")' "$filePath") && { arr['branch.release']="$(yq '.branch.release' "$filePath")"; echo "::debug::.branch.release = ${arr['branch.release']}"; }
	fi
	if $(yq 'has("date_format")' "$filePath"); then
		$(yq '.date_format | has("short")' "$filePath") && { arr['date_format.short']="$(yq '.date_format.short' "$filePath")"; echo "::debug::.date_format.short = ${arr['date_format.short']}"; }
		$(yq '.date_format | has("long")' "$filePath") && { arr['date_format.long']="$(yq '.date_format.long' "$filePath")"; echo "::debug::.date_format.long = ${arr['date_format.long']}"; }
		$(yq '.date_format | has("dtg")' "$filePath") && { arr['date_format.dtg']="$(yq '.date_format.dtg' "$filePath")"; echo "::debug::.date_format.dtg = ${arr['date_format.dtg']}"; }
	fi
	if $(yq 'has("message")' "$filePath"); then
		$(yq '.message | has("commit")' "$filePath") && { arr['message.commit']="$(yq '.message.commit' "$filePath")"; echo "::debug::.message.commit = ${arr['message.commit']}"; }
		$(yq '.message | has("release")' "$filePath") && { arr['message.release']="$(yq '.message.release' "$filePath")"; echo "::debug::.message.release = ${arr['message.release']}"; }
	fi
	if $(yq 'has("changelog")' "$filePath"); then
		$(yq '.changelog | has("template")' "$filePath") && { arr['changelog.template']="$(yq '.changelog.template' "$filePath")"; echo "::debug::.changelog.template = ${arr['changelog.template']}"; }
		$(yq '.changelog | has("file")' "$filePath") && { arr['changelog.file']="$(yq '.changelog.file' "$filePath")"; echo "::debug::.changelog.file = ${arr['changelog.file']}"; }
		$(yq '.changelog | has("style")' "$filePath") && { arr['changelog.style']="$(yq '.changelog.style' "$filePath")"; echo "::debug::.changelog.style = ${arr['changelog.style']}"; }
		$(yq '.changelog | has("create")' "$filePath") && { arr['changelog.create']="$(yq '.changelog.create' "$filePath")"; echo "::debug::.changelog.create = ${arr['changelog.create']}"; }
	fi
	if $(yq 'has("release")' "$filePath"); then
		$(yq '.release | has("template")' "$filePath") && { arr['release.template']="$(yq '.release.template' "$filePath")"; echo "::debug::.release.template = ${arr['release.template']}"; }
		$(yq '.release | has("create")' "$filePath") && { arr['release.create']="$(yq '.release.create' "$filePath")"; echo "::debug::.release.create = ${arr['release.create']}"; }
	fi
	if $(yq 'has("pull_request")' "$filePath"); then
		$(yq '.pull_request | has("template")' "$filePath") && { arr['pull_request.template']="$(yq '.pull_request.template' "$filePath")"; echo "::debug::.pull_request.template = ${arr['pull_request.template']}"; }
		$(yq '.pull_request | has("create")' "$filePath") && { arr['pull_request.create']="$(yq '.pull_request.create' "$filePath")"; echo "::debug::.pull_request.create = ${arr['pull_request.create']}"; }
	fi

	$(yq 'has("standard_name")' "$filePath") && { arr['standard_name']="$(yq '.standard_name' "$filePath")"; echo "::debug::.standard_name = ${arr['standard_name']}"; }
	$(yq 'has("standard_url")' "$filePath") && { arr['standard_url']="$(yq '.standard_url' "$filePath")"; echo "::debug::.standard_url = ${arr['standard_url']}"; }
	$(yq 'has("standard_regex")' "$filePath") && { arr['standard_regex']="$(yq '.standard_regex' "$filePath")"; echo "::debug::.standard_regex = ${arr['standard_regex']}"; }
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
	echo "::debug::Configuration File '${1}' Validated"
}

cfg::write()
{
	if [[ ! -f "${SEARCH_DIRS[0]}/release.yml" ]] && [[ ! -f "${SEARCH_DIRS[1]}/release.yml" ]]; then
		echo "Creating config file 'release.yml' for repository"
		# Check for existing temp file
		if [[ -f "$TMP_DIR/release.yml" ]]; then
			cp "$TMP_DIR/release.yml" "${SEARCH_DIRS[0]}/release.yml" || err::exit "Unable to copy config file from '$TMP_DIR/release.yml' to '${SEARCH_DIRS[0]}/release.yml'"
		else
			if [[ -f "$cfgDefault" ]]; then
				envsubst < "$cfgDefault" > "${SEARCH_DIRS[0]}/release.yml" || err::exit "Unable to write config file '${SEARCH_DIRS[0]}/release.yml'"
			else
				err::exit "Unable to find default configuration file"
			fi
		fi
	fi
	if [[ ! -f "${SEARCH_DIRS[0]}/release.base.yml" ]] && [[ ! -f "${SEARCH_DIRS[1]}/release.base.yml" ]] && [[ "${cfgBase##*/}" == "release.base.yml" ]]; then
		echo "Creating config file 'release.base.yml' for repository"
		# Check existing temp file
		if [[ -f "$TMP_DIR/release.base.yml" ]]; then
			cp "$TMP_DIR/release.base.yml" "${SEARCH_DIRS[1]}/release.base.yml" || err::exit "Unable to copy config file from '$TMP_DIR/release.base.yml' to '${SEARCH_DIRS[1]}/release.base.yml'"
		else
			envsubst < "$cfgDefault" > "${SEARCH_DIRS[1]}/release.base.yml" || err::exit "Unable to write config file '${SEARCH_DIRS[1]}/release.base.yml'"
		fi
	fi
	if [[ ! -f "${SEARCH_DIRS[0]}/types.conventional.yml" ]] && [[ ! -f "${SEARCH_DIRS[1]}/types.conventional.yml" ]] && [[ "${cfgTypes##*/}" == "types.conventional.yml" ]]; then
		echo "Creating config file 'types.conventional.yml' for repository"
		cp "$CFG_DIR/types.conventional.yml" "${SEARCH_DIRS[1]}/types.conventional.yml" || err::exit "Unable to write config file '${SEARCH_DIRS[1]}/types.conventional.yml'"
	fi
	if [[ ! -f "${SEARCH_DIRS[0]}/changelog.md" ]] && [[ ! -f "${SEARCH_DIRS[1]}/changelog.md" ]] && [[ "${logTmpl##*/}" == "changelog.md" ]]; then
		echo "Creating config file 'changelog.md' for repository"
		cp "$CFG_DIR/changelog.md" "${SEARCH_DIRS[1]}/changelog.md" || err::exit "Unable to write config file '${SEARCH_DIRS[1]}/changelog.md'"
	fi
	if [[ ! -f "${SEARCH_DIRS[0]}/release.md" ]] && [[ ! -f "${SEARCH_DIRS[1]}/release.md" ]] && [[ "${relTmpl##*/}" == "release.md" ]]; then
		echo "Creating config file 'release.md' for repository"
		cp "$CFG_DIR/release.md" "${SEARCH_DIRS[1]}/release.md" || err::exit "Unable to write config file '${SEARCH_DIRS[1]}/release.md'"
	fi
	if [[ ! -f "${SEARCH_DIRS[0]}/pull_request.md" ]] && [[ ! -f "${SEARCH_DIRS[1]}/pull_request.md" ]] && [[ "${pullTmpl##*/}" == "pull_request.md" ]]; then
		echo "Creating config file 'pull_request.md' for repository"
		cp "$CFG_DIR/pull_request.md" "${SEARCH_DIRS[1]}/pull_request.md" || err::exit "Unable to write config file '${SEARCH_DIRS[1]}/pull_request.md'"
	fi
}
