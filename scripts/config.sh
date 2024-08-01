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
cfg::read()
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

		cfg::validate "$extFilePath"

		envsubst < "$extFilePath" > "$tmpFilePath" || err::exit "Environment substitution failure"

		$(yq 'has("prefix")' "$tmpFilePath") && { PREFIX="$(yq '.prefix' "$tmpFilePath")"; CFG['prefix']="$PREFIX"; echo "::debug::PREFIX = $PREFIX"; }
		if $(yq 'has("git_user")' "$tmpFilePath"); then
			$(yq '.git_user | has("name")' "$tmpFilePath") && { GIT_USER_NAME="$(yq '.git_user.name' "$tmpFilePath")"; CFG['git_user.name']="$GIT_USER_NAME"; echo "::debug::GIT_USER_NAME = $GIT_USER_NAME"; }
			$(yq '.git_user | has("email")' "$tmpFilePath") && { GIT_USER_EMAIL="$(yq '.git_user.email' "$tmpFilePath")"; CFG['git_user.email']="$GIT_USER_EMAIL"; echo "::debug::GIT_USER_EMAIL = $GIT_USER_EMAIL"; }
		fi
		if $(yq 'has("branch")' "$tmpFilePath"); then
			$(yq '.branch | has("prod")' "$tmpFilePath") && { BRANCH_PROD="$(yq '.branch.prod' "$tmpFilePath")"; CFG['branch.prod']="$BRANCH_PROD"; echo "::debug::BRANCH_PROD = $BRANCH_PROD"; }
			$(yq '.branch | has("stage")' "$tmpFilePath") && { BRANCH_STAGE="$(yq '.branch.stage' "$tmpFilePath")"; CFG['branch.stage']="$BRANCH_STAGE"; echo "::debug::BRANCH_STAGE = $BRANCH_STAGE"; }
			$(yq '.branch | has("patch")' "$tmpFilePath") && { BRANCH_PATCH="$(yq '.branch.patch' "$tmpFilePath")"; CFG['branch.patch']="$BRANCH_PATCH"; echo "::debug::BRANCH_PATCH = $BRANCH_PATCH"; }
			$(yq '.branch | has("release")' "$tmpFilePath") && { BRANCH_RELEASE="$(yq '.branch.release' "$tmpFilePath")"; CFG['branch.release']="$BRANCH_RELEASE"; echo "::debug::BRANCH_RELEASE = $BRANCH_RELEASE"; }
		fi
		if $(yq 'has("message")' "$tmpFilePath"); then
			$(yq '.message | has("commit")' "$tmpFilePath") && { MESSAGE_COMMIT="$(yq '.message.commit' "$tmpFilePath")"; CFG['message.commit']="$MESSAGE_COMMIT"; echo "::debug::MESSAGE_COMMIT = $MESSAGE_COMMIT"; }
			$(yq '.message | has("release")' "$tmpFilePath") && { MESSAGE_RELEASE="$(yq '.message.release' "$tmpFilePath")"; CFG['message.release']="$MESSAGE_RELEASE"; echo "::debug::MESSAGE_RELEASE = $MESSAGE_RELEASE"; }
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

	cfg::validate "$filePath"

	$(yq 'has("prefix")' "$filePath") && { PREFIX="$(yq '.prefix' "$filePath")"; CFG['prefix']="$PREFIX"; echo "::debug::PREFIX = $PREFIX"; }
	$(yq 'has("name")' "$filePath") && { REPO_NAME="$(yq '.name' "$filePath")"; CFG['name']="$REPO_NAME"; echo "::debug::REPO_NAME = $REPO_NAME"; }
	$(yq 'has("description")' "$filePath") && { REPO_DESC="$(yq '.description' "$filePath")"; CFG['description']="$REPO_DESC"; echo "::debug::REPO_DESC = $REPO_DESC"; }
	$(yq 'has("repo_url")' "$filePath") && { REPO_URL="$(yq '.repo_url' "$filePath")"; CFG['repo_url']="$REPO_URL"; echo "::debug::REPO_URL = $REPO_URL"; }
	$(yq 'has("copyright")' "$filePath") && { COPYRIGHT="$(yq '.copyright' "$filePath")"; CFG['copyright']="$COPYRIGHT"; echo "::debug::COPYRIGHT = $COPYRIGHT"; }
	$(yq 'has("website")' "$filePath") && { WEBSITE="$(yq '.website' "$filePath")"; CFG['website']="$WEBSITE"; echo "::debug::WEBSITE = $WEBSITE"; }
	if $(yq 'has("git_user")' "$filePath"); then
		$(yq '.git_user | has("name")' "$filePath") && { GIT_USER_NAME="$(yq '.git_user.name' "$filePath")"; CFG['git_user.name']="$GIT_USER_NAME"; echo "::debug::GIT_USER_NAME = $GIT_USER_NAME"; }
		$(yq '.git_user | has("email")' "$filePath") && { GIT_USER_EMAIL="$(yq '.git_user.email' "$filePath")"; CFG['git_user.email']="$GIT_USER_EMAIL"; echo "::debug::GIT_USER_EMAIL = $GIT_USER_EMAIL"; }
	fi
	if $(yq 'has("authors")' "$filePath"); then
		# shellcheck disable=SC2034
		readarray AUTHORS < <(yq -o=j -I=0 '.authors[]' "$filePath")
	fi
	if $(yq 'has("branch")' "$filePath"); then
		$(yq '.branch | has("prod")' "$filePath") && { BRANCH_PROD="$(yq '.branch.prod' "$filePath")"; CFG['branch.prod']="$BRANCH_PROD"; echo "::debug::BRANCH_PROD = $BRANCH_PROD"; }
		$(yq '.branch | has("stage")' "$filePath") && { BRANCH_STAGE="$(yq '.branch.stage' "$filePath")"; CFG['branch.stage']="$BRANCH_STAGE"; echo "::debug::BRANCH_STAGE = $BRANCH_STAGE"; }
		$(yq '.branch | has("patch")' "$filePath") && { BRANCH_PATCH="$(yq '.branch.patch' "$filePath")"; CFG['branch.patch']="$BRANCH_PATCH"; echo "::debug::BRANCH_PATCH = $BRANCH_PATCH"; }
		$(yq '.branch | has("release")' "$filePath") && { BRANCH_RELEASE="$(yq '.branch.release' "$filePath")"; CFG['branch.release']="$BRANCH_RELEASE"; echo "::debug::BRANCH_RELEASE = $BRANCH_RELEASE"; }
	fi
	if $(yq 'has("message")' "$filePath"); then
		$(yq '.message | has("commit")' "$filePath") && { MESSAGE_COMMIT="$(yq '.message.commit' "$filePath")"; CFG['message.commit']="$MESSAGE_COMMIT"; echo "::debug::MESSAGE_COMMIT = $MESSAGE_COMMIT"; }
		$(yq '.message | has("release")' "$filePath") && { MESSAGE_RELEASE="$(yq '.message.release' "$filePath")"; CFG['message.release']="$MESSAGE_RELEASE"; echo "::debug::MESSAGE_RELEASE = $MESSAGE_RELEASE"; }
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
	$(yq 'has("release")' "$filePath") && { RELEASE="$(yq '.release' "$filePath")"; CFG['release']="$RELEASE"; echo "::debug::RELEASE = $RELEASE"; }
	$(yq 'has("changelog")' "$filePath") && { CHANGELOG="$(yq '.changelog' "$filePath")"; CFG['changelog']="$CHANGELOG"; echo "::debug::CHANGELOG = $CHANGELOG"; }

	echo "Release Manager configuration file processed"
}

cfg::validate()
{
	[[ -z "${1}" ]] && err::exit "No Configuration Filepath Passed!"
	[[ -f "${1}" ]] || err::exit "Configuration Filepath '${1}' Not Found!"
	$(yq --exit-status 'tag == "!!map" or tag == "!!seq"' "${1}") || err::exit "Invalid Configuration File '${1}'"
	echo "::debug::Configuration File '${1}' Validated"
}
