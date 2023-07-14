---
title: "Smart Yogurt Maker Part 3"
date: "2023-07-12"
author: "William Floyd"
categories: [
    "Development",
    "Hardware",
    "Software"
]
tags: [
    "ESPHome",
    "Rice Cooker",
    "Home Assistant",
    "Smart Home",
    "Automation",
    "Yogurt"
]
series: ["Smart Yogurt Maker"]
draft: true
---

It's been a while, a lot has happened (graduated University, moved cross country, started my first real job), but you know what's **actually** important? Yogurt.
So sit down, relax, and hear ~~the ramblings of a madman~~ of the simplifications of my yogurt making automation.
Now follows a tale of Accidents, Averages, and Algorithms (sorta).

***


# "Next time, on Rice Cooker Adventures"

Completed since last time:
* ensure the outlet will turn off if the ESP8266 loses connection
* PID tune the setup for the most common scenario (steady $107^\circ \text{F}$ with the lid shut)

Left to do now:
* solder a perfboard version of the circuit
* add a relay to control the cooker directly

{{< mathjax >}}