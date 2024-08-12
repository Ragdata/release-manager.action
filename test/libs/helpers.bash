#!/usr/bin/env bash

commonSetup()
{
	load libs/bats-support/load
	load libs/bats-assert/load

	# get the containing directory of this file
	# use $BATS_TEST_FILENAME instead of ${BASH_SOURCE[0]} or $0,
	# as those will point to the BATS executable or the preprocessor file respectively
	DIR="$( cd "$( dirname "$BATS_TEST_FILENAME" )" > /dev/null 2>&1 && pwd )"
	# make executables in src/ visible to $PATH
	PATH="$DIR/../../src:$PATH"
}

assertEmpty() { assert [ -z "${1}" ]; }
refuteEmpty() { assert [ ! -z "${1}" ]; }
assertExists() { assert [ -e "${1}" ]; }
refuteExists() { assert [ ! -e "${1}" ]; }
