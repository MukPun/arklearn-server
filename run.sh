#!/bin/sh
export ROOT=$(cd `dirname $0`; pwd)
export DAEMON=false

while getopts "D" arg
do
	case $arg in
		D)          # -D
			export DAEMON=true
			;;
	esac
done

$ROOT/skynet/skynet $ROOT/config

