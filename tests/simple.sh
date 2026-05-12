#!/bin/bash

set -x 

SENSOR_ID=$1
VALUE=$2

curl -X POST http://localhost:4000/api/collect \
     -H "Content-Type: application/json" \
     -d '{"sensor_id": "'"$SENSOR_ID"'", "value": '"$VALUE"'}'

