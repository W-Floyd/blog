---
title: "Extracting Energy Data from Home Assistant"
date: "2026-04-09"
author: "William Floyd"
categories: [
    "Software"
]
tags: [
    "Home Assistant",
    "Home Automation",
    "Frugal"
]
---

Couldn't find a complete guide for this.

Install https://github.com/klausj1/homeassistant-statistics

Run like so:
![alt text](media/dev-tools.webp)

Using this as the timestamp string:
`%Y-%m-%dT%H:%M:00Z`

Once downloaded, to find what id you should filter to (you might already know the entity name from Home Assistant):
```sh
cat export_counters.json |
    jq 'map(.id | select(contains("consumption")))'
```

In my case, the file is large, so it's best to pre-process the file and filter it to just the target entities values:
```sh
cat export_counters.json |
    jq 'map(select(.id=="opower:xxx_energy_consumption")) | first | .values' > export_filtered_counters.json
```

Now you have your power data, ready to process!

This is where things can get as crazy as you like, depending on your afinity for JQ.

# Simple Route (CSV / Excel)

If you want to do stuff in Excel (or any similar product) you might want to further process this data:
```sh
cat export_filtered_counters.json |
    jq 'map(.datetime |= (fromdate | strftime("%Y-%m-%d %H:%M:00")))' |
    yq -o csv > export_filtered_counters.csv
```

This gets you a CSV with date strings that Excel can work with:
```csv
datetime,sum,state,delta
2025-04-05 00:00:00,3010.138800000007,1.041,0.0
2025-04-05 01:00:00,3010.948800000007,0.81,0.8099999999999454
2025-04-05 02:00:00,3011.637600000007,0.6888,0.688799999999901
2025-04-05 03:00:00,3012.369600000007,0.732,0.7319999999999709
2025-04-05 04:00:00,3013.131600000007,0.762,0.762000000000171
2025-04-05 05:00:00,3013.871400000007,0.7398,0.7397999999998319
```

You'll probably just want the `state` and `datetime` column.

# Draw the Rest of the Owl

I get carried away, and built out JQ functions to model my utility rate options. Ultimate flexibility, much easier than wrangling in Excel.

[Script](data/calculate.jq). Usage is like so:
```sh
cat export_filtered_counters.json | jq -f calculate.jq
```

(Note as of writing, syntax highlighting is funky, [someday I'll try adding JQ support](https://github.com/alecthomas/chroma/issues/1135), but I'll embed below if I figure that out)

<!-- ```jq
{{< file-content "data/calculate.jq" >}}
``` -->