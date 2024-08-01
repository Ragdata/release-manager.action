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
rm::createTag()
{
	echo "Checking existance of release tag ..."

	$(arr::hasValue "${RELEASE_VERSION['full']}" "${TAGS[@]}") && err::exit "Tag '${RELEASE_VERSION['full']}' already exists"
}

rm::parseVersion()
{
	local ver="${1:-0.0.0}"
	local -n arr="${2}"

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
arr::hasVal()
{
	local e val="${1}"
	shift

	for e; do [[ "$e" == "$val" ]] && return 0; done

	return 1
}

arr::getIndex()
{
	local val="${1:-}"
	# shellcheck disable=SC2178
	local -a arr="${2:-}"

	for i in "${!arr[@]}"; do
		[[ "${arr[$i]}" = "${val}" ]] && { echo "${i}"; return 0; }
	done

	return 1
}

####################################################################
# CHANGELOG FUNCTIONS
####################################################################
chg::buildChangelog()
{
	local TMPL_FILE TMPL_HEADER TMPL_FOOTER TMPL_CONTENT

	TMPL="$TMPL_DIR/changelog.md"

	if [[ -f "$TMPL" ]]; then
		TMPL_HEADER=$(chg::parseTemplateBlock "{{ #doc header }}" "{{ /doc header }}")
		TMPL_FOOTER=$(chg::parseTemplateBlock "{{ #doc footer }}" "{{ /doc footer }}")
		TMPL_BODY=$(chg::parseTemplateBlock "{{ #doc body }}" "{{ /doc body }}")

		# shellcheck disable=SC2157
		if [[ "$GITHUB_WORKSPACE/CHANGELOG.md" ]]; then
			TMPL_CONTENT=$(chg::parseTemplateBlock "[//]: # (START)" "[//]: # (END)" "$GITHUB_WORKSPACE/CHANGELOG.md")
		else
			TMPL_CONTENT=""
		fi

#		TMPL_HEADER=$(chg::parseBlock "$TMPL_HEADER")
#		TMPL_FOOTER=$(chg::parseBlock "$TMPL_FOOTER")
	else
		err::exit "Template file '$TMPL' not found"
	fi
}

chg::parseBlock()
{
	local CONTENT="${1:-}"

	[[ -z "$CONTENT" ]] && return 0


#	while IFS= read -r LINE
#	do
#		if [[ ${LINE,,} =~ $PATTERN ]]; then
#			if [[ ${LINE,,} =~ $CMD ]]; then
#				if [[ ${LINE,,} =~ $COND ]]; then
#					if [[ ${LINE,,} =~ $COND_OPEN ]]; then
#
#					elif [[ ${LINE,,} =~ $COND_CLOSE ]]; then
#
#					fi
#				elif [[ ${LINE,,} =~ $LOOP ]]; then
#					if [[ ${LINE,,} =~ $LOOP_OPEN ]]; then
#
#					elif [[ ${LINE,,} =~ $LOOP_CLOSE ]]; then
#
#					fi
#				fi
#			elif [[ ${LINE,,} =~ $OPEN ]]; then
#
#			elif [[ ${LINE,,} =~ $CLOSE ]]; then
#
#			fi
#		fi
#	done <<< "$CONTENT"
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
