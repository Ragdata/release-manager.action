#!/usr/bin/env bash
# shellcheck disable=SC2034
# shellcheck disable=SC2091
####################################################################
# ghapi.sh
####################################################################
# Release Manager Docker Action - GitHub API Functions
#
# File:         ghapi.sh
# Author:       Ragdata
# Date:         11/08/2024
# License:      MIT License
# Copyright:    Copyright © 2024 Redeyed Technologies
####################################################################
gh::GET()
{
	local url="$1"
	local result

	result=$(curl -s "${HEADERS[@]}" -w '%{http_code}' "$url")

	printf -- '%s' "$result"
}

gh::getRepository() { printf -- '%s' "$(gh::GET "https://api.github.com/repos/${GITHUB_REPOSITORY}")"; }

gh::listReleases() { printf -- '%s' "$(gh::GET "https://api.github.com/repos/${GITHUB_REPOSITORY}/releases")"; }
