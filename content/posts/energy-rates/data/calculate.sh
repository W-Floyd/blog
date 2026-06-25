#!/bin/bash

cat export_filtered_counters.json | jq -f calculate.jq

exit