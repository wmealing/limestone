#!/bin/bash

set -x 

SENSOR_ID=$1
VALUE=$2

HOST=https://cobalt-mellowed-blossom-1379.fly.dev/api/collect


curl -X POST $HOST \
     -H "Content-Type: application/json" \
     -d '{"sensor_id": "'"$SENSOR_ID"'", "value": '"$VALUE"'}'

