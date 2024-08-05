#!/usr/bin/env bash
# shellcheck disable=SC2034
# shellcheck disable=SC2091
# shellcheck disable=SC2155
# ###################################################################
# builder.sh
####################################################################
# Release Manager Docker Action - Builder Functions
#
# File:         builder.sh
# Author:       Ragdata
# Date:         02/08/2024
# License:      MIT License
# Copyright:    Copyright © 2024 Redeyed Technologies
####################################################################
# BUILDER FUNCTIONS
####################################################################
bld::changelog()
{
	TMPL="$TMPL_DIR/changelog.md"

	if [[ -f "$TMPL" ]]; then
		bld::parseTemplateBlock "{{ #doc header }}" "{{ /doc header }}" "$TMP_DIR/tmpl_header.md"
		bld::parseTemplateBlock "{{ #doc footer }}" "{{ /doc footer }}" "$TMP_DIR/tmpl_footer.md"
		bld::parseTemplateBlock "{{ #doc body }}" "{{ /doc body }}" "$TMP_DIR/tmpl_body.md"

		if [[ -f "../CHANGELOG.md" ]]; then
			TMPL_CONTENT=$(bld::parseTemplateBlock "[//]: # (START)" "[//]: # (END)" "../CHANGELOG.md")
		else
			TMPL_CONTENT=""
		fi

		bld::parseBlock "$TMP_DIR/tmpl_header.md"
		bld::parseBlock "$TMP_DIR/tmpl_footer.md"
		bld::parseBlock "$TMP_DIR/tmpl_body.md"
	else
		err::exit "Template file '$TMPL' not found"
	fi
}

bld::firstlog()
{
	TMPL="$TMPL_DIR/firstlog.md"

	if [[ -f "$TMPL" ]]; then
		echo "Parsing CHANGELOG template ..."
		bld::parseTemplateBlock "{{ #doc header }}" "{{ /doc header }}" "$TMP_DIR/tmpl_header.md"
		bld::parseTemplateBlock "{{ #doc footer }}" "{{ /doc footer }}" "$TMP_DIR/tmpl_footer.md"
		bld::parseTemplateBlock "{{ #doc body }}" "{{ /doc body }}" "$TMP_DIR/tmpl_body.md"

		echo "Parsing CHANGELOG template blocks ..."
		bld::parseBlock "$TMP_DIR/tmpl_header.md"
		bld::parseBlock "$TMP_DIR/tmpl_footer.md"
		bld::parseBlock "$TMP_DIR/tmpl_body.md"
	else
		err::exit "Template file '$TMPL' not found"
	fi

	echo "Writing CHANGELOG"

	touch "$GITHUB_WORKSPACE/CHANGELOG.md"

	[[ -f "$TMP_DIR/tmpl_header.md" ]] && cat "$TMP_DIR/tmpl_header.md" >> "$GITHUB_WORKSPACE/CHANGELOG.md"
	[[ -f "$TMP_DIR/tmpl_body.md" ]] && cat "$TMP_DIR/tmpl_body.md" >> "$GITHUB_WORKSPACE/CHANGELOG.md"
	[[ -f "$TMP_DIR/tmpl_footer.md" ]] && cat "$TMP_DIR/tmpl_footer.md" >> "$GITHUB_WORKSPACE/CHANGELOG.md"
}

bld::parseBlock()
{
	local fileName="${1}"

	local PATTERN=$(regex::PATTERN)
	local CMD=$(regex::CMD)
	local COND=$(regex::COND)
	local COND_OPEN=$(regex::COND_OPEN)
	local COND_CLOSE=$(regex::COND_CLOSE)
	local LOOP=$(regex::LOOP)
	local LOOP_OPEN=$(regex::LOOP_OPEN)
	local LOOP_CLOSE=$(regex::LOOP_CLOSE)
	local OPEN=$(regex::OPEN)
	local CLOSE=$(regex::CLOSE)
	local VAR=$(regex::VAR)
	local OUTPUT=""

	while IFS= read -r LINE
	do
		if [[ ${LINE,,} =~ $VAR ]]; then
			echo "${BASH_REMATCH[0]}"
			OUTPUT="$(bld::parseVar "$LINE" "$VAR")"
		fi
	done < "$fileName"

	echo -e "$OUTPUT" > "$fileName"
}

bld::parseTemplateBlock()
{
	local start="${1}"
	local finish="${2}"
	local outFile="${3}"
	local template="${4:-${TMPL_DIR}/changelog.md}"
	local active=0 LF="\n"
	local OUTPUT=""

	while IFS= read -r LINE
	do
		[[ "$LINE" == *"$finish"* && $active -eq 1 ]] && active=0
		if [[ $active -eq 1 ]]; then
			if [[ -n "$OUTPUT" ]]; then
				OUTPUT="$OUTPUT$LF$LINE"
			else
				OUTPUT="$LINE"
			fi
		fi
		[[ "$LINE" == *"$start"* && $active -eq 0 ]] && active=1
	done < "$template"

	echo -e "$OUTPUT" > "$outFile"
}

bld::parseVar()
{
	local LINE="${1}"
	local VAR="${2}"
	local tag varName

	while [[ "${LINE,,}" =~ $VAR ]]; do
		tag="${BASH_REMATCH[0]}"
		varName="${BASH_REMATCH[2]}"
		if arr::hasKey CFG "$varName"; then
			LINE="${LINE/$tag/${CFG[$varName]}}"
		else
			err::exit "Variable '$varName' not found"
		fi
	done

	echo -e "$LINE"
}
