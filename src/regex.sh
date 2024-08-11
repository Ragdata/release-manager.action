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
# Date:         11/08/2024
# License:      MIT License
# Copyright:    Copyright © 2024 Redeyed Technologies
####################################################################
regex::tmpl()
{
	local VERSION='^([a-z]+[-.]?)?(([0-9]+)\.?([0-9]*)\.?([0-9]*))(-([0-9a-zA-Z\.-]*))?(\+([0-9a-zA-Z\.-]*))?$'

	if [[ -n "${!1}" ]]; then
		printf -- '%s' "${!1}"
		return 0
	else
		return 1
	fi
}
#
# ALIAS FUNCTIONS --------------------------------------------------
#
regex::VERSION()	{ regex::tmpl VERSION; }
