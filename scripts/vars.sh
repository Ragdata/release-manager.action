#!/usr/bin/env bash
# shellcheck disable=SC2317
####################################################################
# vars.sh
####################################################################
# Release Manager Docker Action - Variables
#
# File:         vars.sh
# Author:       Ragdata
# Date:         28/07/2024
# License:      MIT License
# Copyright:    Copyright © 2024 Redeyed Technologies
####################################################################

declare -Ax LOGGED_COMMITS
declare -Ax FILTERED_COMMITS
declare -Ax TYPES
declare -Ax TYPE_ALIASES

declare -ax COMMITS
declare -ax LOGGED_TYPES
declare -ax TAGS

declare -x LATEST_TAG PREV_TAG
declare -x PREFIX SUFFIX BUILD
declare -x GIT_USER_NAME GIT_USER_EMAIL
declare -x BRANCH_PROD BRANCH_STAGE BRANCH_PATCH BRANCH_RELEASE
declare -x MESSAGE_RELEASE

declare -x BIN_DIR SHARE_DIR SCRIPT_DIR TMPL_DIR TMP_DIR

declare -x cfgFile cfgDefault

BIN_DIR="/usr/local/bin"
SHARE_DIR="/usr/local/share"
SCRIPT_DIR="$BIN_DIR/scripts"
TMPL_DIR="$SHARE_DIR/tmpl"

TMP_DIR="$(mktemp -d)"

cfgFile="$GITHUB_WORKSPACE/.release.yml"
cfgDefault="$TMPL_DIR/.release.yml"
