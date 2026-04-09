#!/bin/bash

# cat export_counters.json | jq 'map(.id | select(contains("consumption")))'
# cat export_counters.json | jq 'map(select(.id=="opower:kcpk_elec_5769595305_energy_consumption")) | first | .values' > export_filtered_counters.json
cat export_filtered_counters.json | jq -f calculate.jq

# cat export_counters.json | jq 'map(select(.statistic_id=="opower:kcpk_elec_5769595305_energy_consumption") | { start: (.start | strptime("%d.%m.%Y %H:%M") | mktime | strftime("%Y-%m-%d %H:%M:00")), delta: .delta } )'

exit