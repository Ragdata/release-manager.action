#!/usr/bin/env bash
# shellcheck disable=SC2034
# shellcheck disable=SC2091
####################################################################
# regex.sh
####################################################################
# Release Manager Docker Action - REGEX Functions
#
# File:         regex.sh
# Author:       Ragdata
# Date:         26/07/2024
# License:      MIT License
# Copyright:    Copyright © 2024 Redeyed Technologies
####################################################################
# REGEX FUNCTIONS
####################################################################
regex::tmpl()
{
	local PATTERN="(\{\{ *((#|/)?([_a-z0-9.-]*)) ?([_a-z0-9.-]*)? *\}\})"
	local OPEN="(\{\{ *((#)([_a-z0-9.-]*)) ?([_a-z0-9.-]*)? *\}\})"
	local CLOSE="(\{\{ *((/)([_a-z0-9.-]*)) ?([_a-z0-9.-]*)? *\}\})"
	local CMD="(\{\{ *((#|/)(if|each)) ?([_a-z0-9.-]*)? *\}\})"
	local COND="(\{\{ *((#|/)(if)) ?([_a-z0-9.-]*)? *\}\})"
	local COND_OPEN="(\{\{ *((#)(if)) ?([_a-z0-9.-]*)? *\}\})"
	local COND_CLOSE="(\{\{ *((/)(if)) *\}\})"
	local LOOP="(\{\{ *((#|/)(each)) ?([_a-z0-9.-]*)? *\}\})"
	local LOOP_OPEN="(\{\{ *((#)(each)) ?([_a-z0-9.-]*)? *\}\})"
	local LOOP_CLOSE="(\{\{ *((/)(each)) *\}\})"
	local VAR="(\{\{ *([_a-z0-9.-]+) *\}\})"

	if [[ -n "${!1}" ]]; then
		printf '%s' "${!1}"
		return 0
	else
		return 1
	fi
}
#
# ALIAS FUNCTIONS --------------------------------------------------
#
regex::PATTERN()	{ regex::tmpl PATTERN; }
regex::OPEN()		{ regex::tmpl OPEN; }
regex::CLOSE()		{ regex::tmpl CLOSE; }
regex::CMD()		{ regex::tmpl CMD; }
regex::COND()		{ regex::tmpl COND; }
regex::COND_OPEN()	{ regex::tmpl COND_OPEN; }
regex::COND_CLOSE()	{ regex::tmpl COND_CLOSE; }
regex::LOOP()		{ regex::tmpl LOOP; }
regex::LOOP_OPEN()	{ regex::tmpl LOOP_OPEN; }
regex::LOOP_CLOSE()	{ regex::tmpl LOOP_CLOSE; }
regex::VAR()		{ regex::tmpl VAR; }

