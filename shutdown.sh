#!/bin/sh
export ROOT=$(cd `dirname $0`; pwd)
PID=$(ps e -u ${USER} | grep -v grep | grep "$(pwd)" | grep skynet | awk '{print $1}')
kill ${PID}
exit 0;
