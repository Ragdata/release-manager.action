#!/usr/bin/env bash
# shellcheck disable=SC2034
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
rm::getReleases()
{
	local -n data="$1"
	local result code body length

	result="$(gh::listReleases)"

	code=$(tail -n1 <<< "$result")
	body=$(sed '$ d' <<< "$result")

	[[ "$code" != "200" ]] && err::exit "GitHub API returned status code '$code'"

	length="$(echo "$body" | yq 'length' -)"

	if [[ "$length" -gt 0 ]]; then
		echo "$body" | yq -o=j -I4 - > "$TMP_DIR/releases.json"
		readarray data < <(yq -o=j -I0 '.[]' "$TMP_DIR/releases.json")
	else
		data=()
	fi
}

rm::getReleaseVersion()
{
	local p="" v="" s="" b="" d

	$INPUT_PRE_RELEASE && s="-alpha"

	case "$INPUT_TYPE" in
		auto)
			[[ -n "${CURRENT_VERSION['prefix']}" ]] && p="${CURRENT_VERSION['prefix']}"
			if [[ "$FIRST_RELEASE" ]]; then
				v="${CURRENT_VERSION['version']}"
			else
				if [[ -n "${CURRENT_VERSION['suffix']}" ]] && [[ ! $INPUT_PRE_RELEASE ]]; then
					v="${CURRENT_VERSION['version']}"
				elif [[ "$BRANCH_SOURCE" == "$BRANCH_PATCH"* ]]; then
					d="${CURRENT_VERSION['patch']}"
					((d+=1))
					v="${CURRENT_VERSION['major']}.${CURRENT_VERSION['minor']}.$d"
				else
					d="${CURRENT_VERSION['minor']}"
					((d+=1))
					v="${CURRENT_VERSION['major']}.$d.0"
				fi
			fi
			;;
		version)
			[[ -n "${IN_VERSION['prefix']}" ]] && p="${IN_VERSION['prefix']}"
			v="${IN_VERSION['version']}"
			[[ -n "${IN_VERSION['suffix']}" ]] && s="${IN_VERSION['suffix']}"
			[[ -n "${IN_VERSION['build']}" ]] && b="${IN_VERSION['build']}"
			;;
		patch|minor|major)
			[[ -n "${CURRENT_VERSION['prefix']}" ]] && p="${CURRENT_VERSION['prefix']}"
			case "$INPUT_TYPE" in
				patch)
					d="${CURRENT_VERSION['patch']}"
					((d+=1))
					v="${CURRENT_VERSION['major']}.${CURRENT_VERSION['minor']}.$d"
					;;
				minor)
					d="${CURRENT_VERSION['minor']}"
					((d+=1))
					v="${CURRENT_VERSION['major']}.$d.0"
					;;
				major)
					d="${CURRENT_VERSION['major']}"
					((d+=1))
					v="$d.0.0"
					;;
			esac
			;;
	esac

	echo "$p$v$s$b"
}

rm::getRepository()
{
	# shellcheck disable=SC2178
	local -n data="$1"
	local result code body user

	result="$(gh::getRepository)"

	code=$(tail -n1 <<< "$result")
	body=$(sed '$ d' <<< "$result")

	[[ "$code" != "200" ]] && err::exit "GitHub API returned status code '$code'"

	echo "$body" | yq -o=j -I4 - > "$TMP_DIR/repository.json"

	result="$(gh::GET "$(echo "$body" | yq '.owner.url' -)")"

	code=$(tail -n1 <<< "$result")
	user=$(sed '$ d' <<< "$result")

	[[ "$code" != "200" ]] && err::exit "GitHub API returned status code '$code'"

	echo "$user" | yq -o=j -I4 - > "$TMP_DIR/owner.json"

	data['name']="$(echo "$body" | yq '.name' -)"
	data['full_name']="$(echo "$body" | yq '.full_name' -)"
	data['html_url']="$(echo "$body" | yq '.html_url' -)"
	data['description']="$(echo "$body" | yq '.description' -)"
	data['created_at']="$(echo "$body" | yq '.created_at' -)"
	data['updated_at']="$(echo "$body" | yq '.updated_at' -)"
	data['pushed_at']="$(echo "$body" | yq '.pushed_at' -)"
	data['git_url']="$(echo "$body" | yq '.git_url' -)"
	data['ssh_url']="$(echo "$body" | yq '.ssh_url' -)"
	data['clone_url']="$(echo "$body" | yq '.clone_url' -)"
	data['homepage']="$(echo "$body" | yq '.homepage' -)"
	data['language']="$(echo "$body" | yq '.language' -)"
	data['has_issues']="$(echo "$body" | yq '.has_issues' -)"
	data['has_projects']="$(echo "$body" | yq '.has_projects' -)"
	data['has_downloads']="$(echo "$body" | yq '.has_downloads' -)"
	data['has_wiki']="$(echo "$body" | yq '.has_wiki' -)"
	data['has_pages']="$(echo "$body" | yq '.has_pages' -)"
	data['has_discussions']="$(echo "$body" | yq '.has_discussions' -)"
	data['open_issues']="$(echo "$body" | yq '.open_issues' -)"
	data['license.name']="$(echo "$body" | yq '.license.name' -)"
	data['license.spdx_id']="$(echo "$body" | yq '.license.spdx_id' -)"
	data['license.url']="$(echo "$body" | yq '.license.url' -)"
	data['visibility']="$(echo "$body" | yq '.visibility' -)"
	data['default_branch']="$(echo "$body" | yq '.default_branch' -)"
	data['owner.login']="$(echo "$user" | yq '.owner.login' -)"
	data['owner.id']="$(echo "$user" | yq '.owner.id' -)"
	data['owner.avatar_url']="$(echo "$user" | yq '.owner.avatar_url' -)"
	data['owner.html_url']="$(echo "$user" | yq '.owner.html_url' -)"
	data['owner.name']="$(echo "$user" | yq '.owner.name' -)"
	data['owner.company']="$(echo "$user" | yq '.owner.company' -)"
	data['owner.blog']="$(echo "$user" | yq '.owner.blog' -)"
	data['owner.location']="$(echo "$user" | yq '.owner.location' -)"
	data['owner.email']="$(echo "$user" | yq '.owner.email' -)"
	data['owner.bio']="$(echo "$user" | yq '.owner.bio' -)"
	data['owner.twitter_username']="$(echo "$user" | yq '.owner.twitter_username' -)"
	data['owner.created_at']="$(echo "$user" | yq '.owner.created_at' -)"
	data['owner.updated_at']="$(echo "$user" | yq '.owner.updated_at' -)"

	REPO_NAME="${data['name']}"
	REPO_DESC="${data['description']}"
	REPO_URL="${data['html_url']}"
	REPO_DEFAULT_BRANCH="${data['default_branch']}"
	OWNER_LOGIN="${data['owner.login']}"
	OWNER_ID="${data['owner.id']}"
	OWNER_LOCATION="${data['owner.location']}"
	OWNER_COMPANY="${data['owner.company']}"
	OWNER_BLOG="${data['owner.blog']}"
	OWNER_TWITTER="${data['owner.twitter_username']}"
}

rm::parseVersion()
{
	local ver="$1"
	local -n arr="$2"

	[[ -z "$ver" ]] && err::exit "Version not passed"
	if [[ $ver =~ ^([a-z]+[-.]?)?(([0-9]+)\.?([0-9]*)\.?([0-9]*))(-([0-9a-zA-Z\.-]*))?(\+([0-9a-zA-Z\.-]*))?$ ]]; then
		arr['full']="${BASH_REMATCH[0]}"
		arr['prefix']="${BASH_REMATCH[1]}"
		arr['version']="${BASH_REMATCH[2]}"
		arr['major']="${BASH_REMATCH[3]}"
		arr['minor']="${BASH_REMATCH[4]}"
		arr['patch']="${BASH_REMATCH[5]}"
		arr['suffix']="${BASH_REMATCH[7]}"
		arr['build']="${BASH_REMATCH[9]}"
		arr['n_version']="${arr['major']}${arr['minor']}${arr['patch']}"
	else
		err::exit "Invalid version format - '$ver'"
	fi
}


####################################################################
# ARRAY FUNCTIONS
####################################################################
arr::getIndex()
{
	local val="$1"
	# shellcheck disable=SC2178
	local -a arr="$2"

	for i in "${!arr[@]}"; do
		[[ "${arr[$i]}" = "${val}" ]] && { echo "${i}"; return 0; }
	done

	return 1
}

arr::hasKey()
{
	local -n array="$1"
	local key="$2"

	[[ ${array[$key]+_} ]] && return 0

	return 1
}

arr::hasVal()
{
	local e val="${1}"
	shift

	for e; do [[ "$e" == "$val" ]] && return 0; done

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
