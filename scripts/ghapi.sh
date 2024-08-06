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
# Date:         02/08/2024
# License:      MIT License
# Copyright:    Copyright © 2024 Redeyed Technologies
####################################################################
# GHAPI FUNCTIONS
####################################################################
gh::latestRelease()
{
	local result

	result=$(curl -s "${HEADERS[@]}" -w '%{http_code}' "https://api.github.com/repos/${GITHUB_REPOSITORY}/releases/latest")

	echo "$result"
}

gh::listReleases()
{
	local result

	result=$(curl -s "${HEADERS[@]}" -w '%{http_code}' "https://api.github.com/repos/${GITHUB_REPOSITORY}/releases")

	echo "$result"
}

gh::getRepository()
{
	local result

	result=$(curl -s "${HEADERS[@]}" -w '%{http_code}' "https://api.github.com/repos/${GITHUB_REPOSITORY}")

	echo "$result"
}

gh::GET()
{
	local url="$1"
	local result

	result=$(curl -s "${HEADERS[@]}" -w '%{http_code}' "$url")

	echo "$result"
}
