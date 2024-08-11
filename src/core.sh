#!/usr/bin/env bash
# shellcheck disable=SC2034
# shellcheck disable=SC2091
####################################################################
# core.sh
####################################################################
# Release Manager Docker Action - Core Functions
#
# File:         core.sh
# Author:       Ragdata
# Date:         11/08/2024
# License:      MIT License
# Copyright:    Copyright © 2024 Redeyed Technologies
####################################################################
core::getCurrent()
{
	local -n data="$1"

	if [[ -n "$CFG_FILE" ]] && [[ "$CFG_FILE" != "$CFG_FILE_DEFAULT" ]] && [[ "$(yq 'has("version")' "$CFG_FILE")" ]]; then
		echo "Current version obtained from config file"
		core::parseVersion "$(yq '.version' "$CFG_FILE")" data
	elif [[ "${PREV_RELEASE['version']}" != "0.0.0" ]]; then
		echo "Current version obtained from previous release"
		core::parseVersion "${PREV_RELEASE['full']}" data
	elif [[ -n "$CFG_BASE" ]] && [[ "$(yq 'has("version")' "$CFG_BASE")" ]]; then
		echo "Current version obtained from base config file"
		core::parseVersion "$(yq '.version' "$CFG_BASE")" data
	else
		echo "Current version assigned as default first version"
		core::parseVersion "v0.1.0" data
	fi
}

core::getReleases()
{
	local -n data="$1"
	local result code body length

	result="$(gh::listReleases)"

	code=$(tail -n1 <<< "$result")
	body=$(sed '$ d' <<< "$result")

	[[ "$code" != "200" ]] && err::exit "GitHub API returned status code '$code'"

	length="$(echo "$body" | yq 'length' -)"

	if (( length > 0 )); then
		echo "$body" | yq -o=j -I4 - > "$TMP_DIR/releases.json"
		readarray data < <(yq -o=j -I0 '.[]' "$TMP_DIR/releases.json")
	else
		data=()
	fi
}

core::getRepository()
{
	# shellcheck disable=SC2178
	local -n data="$1"
	local result code body user

	result="$(gh::getRepository)"

	code=$(tail -n1 <<< "$result")
	body=$(sed '$ d' <<< "$result")

	[[ "$code" != "200" ]] && err::exit "GitHub API returned status code '$code'"

	result="$(gh::GET "$(echo "$body" | yq '.owner.url' -)")"

	code=$(tail -n1 <<< "$result")
	user=$(sed '$ d' <<< "$result")

	[[ "$code" != "200" ]] && err::exit "GitHub API returned status code '$code'"

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
}

core::parseVersion()
{
	local ver="$1"
	local -n arr="$2"

	[ -z "$ver" ] && err::exit "Version not passed"

	if [[ $ver =~ $(regex::VERSION) ]]; then
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
