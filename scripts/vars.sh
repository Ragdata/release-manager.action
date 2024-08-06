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
declare -Ax RESPONSE REPO CFG
declare -Ax LATEST_RELEASE CURRENT_VERSION

declare -ax HEADERS RELEASES
declare -ax SEARCH_DIRS LOGGED_TYPES

declare -x REPO_NAME REPO_DESC REPO_URL REPO_DEFAULT_BRANCH VERSION
declare -x OWNER_LOGIN OWNER_ID OWNER_LOCATION OWNER_COMPANY OWNER_BLOG OWNER_TWITTER

declare -x FIRST_RELEASE=false

declare -x BIN_DIR SHARE_DIR SCRIPT_DIR CFG_DIR TMP_DIR

BIN_DIR="/usr/local/bin"
SHARE_DIR="/usr/local/share"
SCRIPT_DIR="$BIN_DIR/scripts"
CFG_DIR="$SHARE_DIR/cfg"

SEARCH_DIRS=("$GITHUB_WORKSPACE/.github" "$GITHUB_WORKSPACE/.github/release")

TMP_DIR="$(mktemp -d)"

HEADERS=("-H \"Accept: application/vnd.github+json\"" "-H \"Authorization: Bearer ${GITHUB_TOKEN}\"" "-H \"X-GitHub-Api-Version: 2022-11-28\"")

declare -x cfgFile cfgBase cfgTypes tmpFile tmpBase
declare -x logFile logTmpl relTmpl pullTmpl


#declare -Ax LOGGED_COMMITS FILTERED_COMMITS RESPONSE CFG
#declare -Ax LATEST_TAG LATEST_REPO_TAG IN_VERSION CURRENT_VERSION RELEASE_VERSION
#
#declare -ax BRANCHES COMMITS TYPES TYPE_ALIASES LOGGED_TYPES TAGS AUTHORS HEADERS
#
#declare -x PREFIX="" SUFFIX="" BUILD=""
#declare -x GIT_USER_NAME GIT_USER_EMAIL
#declare -x BRANCH_PROD BRANCH_STAGE BRANCH_PATCH BRANCH_RELEASE BRANCH_CURRENT BRANCH_SOURCE
#declare -x MESSAGE_COMMIT MESSAGE_RELEASE
#declare -x REPO_NAME REPO_DESC REPO_URL
#declare -x COPYRIGHT PROTECT_PROD CHANGELOG
#
#declare -x BIN_DIR SHARE_DIR SCRIPT_DIR TMPL_DIR TMP_DIR
#
#declare -x cfgFile cfgDefault
#declare -x logFile logTmpl logDefault TMPL_LOG
#declare -x isFirst=false
#
#BIN_DIR="/usr/local/bin"
#SHARE_DIR="/usr/local/share"
#SCRIPT_DIR="$BIN_DIR/scripts"
#TMPL_DIR="$SHARE_DIR/tmpl"
#
#TMP_DIR="$(mktemp -d)"
#
#HEADERS=("-H \"Accept: application/vnd.github+json\"" "-H \"Authorization: Bearer ${GITHUB_TOKEN}\"" "-H \"X-GitHub-Api-Version: 2022-11-28\"")
#
#cfgFile="$GITHUB_WORKSPACE/.github/.release.yml"
#cfgDefault="$TMPL_DIR/.release.yml"
#
#logTmpl="$GITHUB_WORKSPACE/.github/.changelog.md"
#logDefault="$TMPL_DIR/.changelog.md"
#logFile="$GITHUB_WORKSPACE/CHANGELOG.md"
#
#if [[ -f "$logTmpl" ]]; then TMPL_LOG="$logTmpl"; else TMPL_LOG="$logDefault"; fi
