#!/bin/sh
export ROOT=$(cd `dirname $0`; pwd)

kill `cat $ROOT/run/skynet.pid`
exit 0;
