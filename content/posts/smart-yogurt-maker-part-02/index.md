---
title: "Smart Yogurt Maker Part 2"
date: "2022-03-16"
author: "William Floyd"
featured_image: "media/IMG_20220126_225541.webp"
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
---

[Part 1](/2022/01/smart-yogurt-maker-part-01) | Part 2

***

Last time we met, I got my rice cooker reporting temperature and roughly maintaining a set-point, producing my first batch of yogurt.
Now follows a tale of Accidents, Averages, and Algorithms (sorta).

***

# An accident has occurred

How prophetic...
My last post said so truly that I needed to "ensure the outlet will turn off if the ESP8266 loses connection".
Of course, I couldn't help myself and tried making a new batch before fixing this.
So it came to be that 6 hours into a batch of yogurt, it was unceremoniously [boiled for a full hour](media/Screenshot%20from%202022-01-27%2012-20-17.webp).

At first, all hope was lost - the mess of solidified dairy mocked me from the teflon lining of my dear rice cooker.
As I forlornly drained the whey, I figured I'd give it a taste...
After all, it had been boiled to death, it couldn't possibly hurt me?

![A Dairy Disaster!](media/IMG_20220126_231746.webp)

# Rice Maker $\rightarrow$ Yogurt Maker $\rightarrow$ Cheese Maker?

I had in fact made cheese.
Not at all intentionally, and not very well (it was still somewhat yogurt-sour), but it was undeniably cheese.
A rough straining through a cheese cloth yielded something more passable as cheese, if only barely.
My girlfriend confirmed it seems to be very similar to Paneer, though she declined to taste it.
I ate only a small portion before deciding it wasn't worth the effort...

![Strained](media/IMG_20220127_013502.webp)

# Simmer down now!

Clearly, it was time to get my automation in order.
It didn't take much to ensure the automation would turn the heat off in case of connection loss, but the regular spikes in temperature were yet to be sorted.

## Fortune Telling

The primary issue in using PID for this system is thermal lag.
While my temperature sensor is accurate for it's location, it cannot account for the temperature gradient in the contents itself.
It would require a complete model of the system, including factors such as convection rate from the rice cooker housing, specific heat capacity, power draw, ambient temperature, volume of contents, initial temperature of contents, etc.
All things considered, this is well outside of the scope of this project - this is meant to make yogurt, and I an do with much less.

## Dirty Shortcut

What I have settled on is a simple hybrid between simple and PID-informed bang–bang control.
My automation simply turns the heater on if the PID value (ranging between 0 and 1) is above 0.95.
This is the case on startup, for example.
If the value is between 0.6 and 0.95, it will turn it on, wait 750 milliseconds, turn back off, then delay any further action for the next 15 seconds.
This ensures when attempting to hold a setpoint that the thermal lag in the system will catch up.
These values are found purely by experimentation, but yield sub $1^\circ F$ variation easily.

![A slice of history](media/Screenshot%20from%202022-03-17%2009-48-36.webp)

## P~~ID~~ Settings

Given some changes to the PID integration I am using, as well as further testing, these are now my PID settings:

$$
\begin{aligned}
P &= 175 \\\\
I &= 0 \\\\
D &= 0 \\\\
\end{aligned}
$$

So really, it's just the "P" in "PID" - I don't mind if it works.

# "Next time, on Rice Cooker Adventures"

Completed since last time:
* ensure the outlet will turn off if the ESP8266 loses connection
* PID tune the setup for the most common scenario (steady $107^\circ \text{F}$ with the lid shut)

Left to do now:
* solder a perfboard version of the circuit
* add a relay to control the cooker directly

{{< mathjax >}}