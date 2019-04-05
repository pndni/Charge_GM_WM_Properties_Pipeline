#!/bin/bash

set -u
set -e

usage () {
    cat <<EOF
Search directory for file with a given suffix.  If exactly one file
is found, print the base filename. If more than one file is found,
exit with error code 1 and print to stderr
Arguments:
    search_directory
    suffix
EOF
    exit 1
}

if [ ! $# -eq 2 ]
then
    >&2 usage
fi

indir=$1
suffix=$2

if [ $(ls $indir/*$suffix | wc -l) != 1 ];
then
    >&2 echo "Could not find exactly one file in \"$indir\" with suffix \"$suffix\""
    exit 1
fi
basename $(ls $indir/*$suffix)
