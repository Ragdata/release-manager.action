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

declare -Ax LOGGED_COMMITS FILTERED_COMMITS RESPONSE CFG
declare -Ax LATEST_TAG LATEST_REPO_TAG IN_VERSION CURRENT_VERSION RELEASE_VERSION

declare -ax BRANCHES COMMITS TYPES TYPE_ALIASES LOGGED_TYPES TAGS AUTHORS HEADERS

declare -x PREFIX="" SUFFIX="" BUILD=""
declare -x GIT_USER_NAME GIT_USER_EMAIL
declare -x BRANCH_PROD BRANCH_STAGE BRANCH_PATCH BRANCH_RELEASE BRANCH_CURRENT
declare -x MESSAGE_COMMIT MESSAGE_RELEASE
declare -x REPO_NAME REPO_DESC REPO_URL
declare -x COPYRIGHT PROTECT_PROD CHANGELOG

declare -x BIN_DIR SHARE_DIR SCRIPT_DIR TMPL_DIR TMP_DIR

declare -x cfgFile cfgDefault
declare -x isFirst=false

BIN_DIR="/usr/local/bin"
SHARE_DIR="/usr/local/share"
SCRIPT_DIR="$BIN_DIR/scripts"
TMPL_DIR="$SHARE_DIR/tmpl"

TMP_DIR="$(mktemp -d)"

HEADERS=("-H \"Accept: application/vnd.github+json\"" "-H \"Authorization: Bearer ${GITHUB_TOKEN}\"" "-H \"X-GitHub-Api-Version: 2022-11-28\"")

cfgFile="$GITHUB_WORKSPACE/.github/.release.yml"
cfgDefault="$TMPL_DIR/.release.yml"

