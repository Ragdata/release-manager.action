#!/usr/bin/env bash
# shellcheck disable=SC2034
# shellcheck disable=SC2091
####################################################################
# array.sh
####################################################################
# Release Manager Docker Action - Array Functions
#
# File:         array.sh
# Author:       Ragdata
# Date:         11/08/2024
# License:      MIT License
# Copyright:    Copyright © 2024 Redeyed Technologies
####################################################################
# ------------------------------------------------------------------
# arr::getIndex
# ------------------------------------------------------------------
# @description Return index of array value
#
# @arg $1			[string]	Needle				(required)
# @arg $@			[array]		Haystack			(required)
#
# @example
#	array=(a b c d)
#	arr::getIndex c "${array[@]}"
#	# OUTPUT
#	2
#
# @stdout $i		[string]	Index of needle in haystack
#
# @exitcode 0 - Success (true)
# @exitcode 1 - Failure (false)
# ------------------------------------------------------------------
arr::getIndex()
{
	local val="$1"
	shift
	local arr=("$@")

	for i in "${!arr[@]}"; do
		[[ "${arr[$i]}" = "${val}" ]] && { echo "${i}"; return 0; }
	done

	return 1
}

# ------------------------------------------------------------------
# arr::hasKey
# ------------------------------------------------------------------
# @description Status T/F indicating if array has specified key
#
# @arg $1			[string]	Array name (ref)	(required)
# @arg $2			[string]	Key name			(required)
#
# @example
#	ARRAY['al']="pha"
#	ARRAY['br']="avo"
#	arr::hasKey ARRAY "al"
#	# STATUS
#	0
#
# @exitcode 0 - Success (true)
# @exitcode 1 - Failure (false)
# ------------------------------------------------------------------
arr::hasKey()
{
	local -n array="$1"
	local key="$2"

	[[ ${array[$key]+_} ]] && return 0

	return 1
}

# ------------------------------------------------------------------
# arr::hasVal
# ------------------------------------------------------------------
# @description Status T/F indicating if array contains specified value
#
# @arg $1			[string]	Needle				(required)
# @arg $@			[array]		Haystack			(required)
#
# @example
#	array=(a b c d)
#	arr::hasVal c "${array[@]}"
#	# STATUS
#	0
#
# @exitcode 0 - Success (true)
# @exitcode 1 - Failure (false)
# ------------------------------------------------------------------
arr::hasVal()
{
	local e val="${1}"
	shift

	for e; do [[ "$e" == "$val" ]] && return 0; done

	return 1
}
