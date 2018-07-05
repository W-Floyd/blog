---
title: "Smart Rice Cooker Conversion"
date: "2018-06-18"
author: "William Floyd"
categories: [
    "Development",
    "Hardware",
    "Software"
]
tags: [
    "Arduino",
    "Rice Cooker",
    "Aliexpress"
]
---

The "why" isn't important (read "doesn't exist"), but I want to take a regular old "dumb" rice cooker, and convert it into a "smart" rice cooker.

So, a whim and a few minutes on Aliexpress later, my pint sized rice cooker and an assortment of electronics are on the slow boat from China.

Having no real clue what I'm doing, here's what I've ordered thus far:

Main list of things:

- [Rice cooker](http://ali.onl/128Y) ($26.40 + $3.16 S&H - The star of the show.)
- [Thermistors](http://ali.onl/128Q) ($2.97 - 100pcs, for temperature readings)
- [NodeMCU](http://ali.onl/128R) ($2.47 - To, hopefully, allow me to WiFi control the whole thing)
- [Relay](http://ali.onl/128V) ($0.76 - To switch power on and off.)
- [ESP8266 Relay](http://ali.onl/128T) ($2.91 + $0.14 S&H - Alternative to the NodeMCU + Relay pairing I'm planning on using)

While I have dabbled with Arduino before, this is a far more ambitious project than I have yet done.
Ideally, I will have the rice cooker serve an API, which my Orange Pi will bounce requests across to as dictated by a frontend hosted on the same machine (this resolves CORS, while still allowing options to control the rice cooker by other devices).

For now though, I am away from home, working, so I can't do anything on this for at least another 2 weeks, probably 3.
Many of my parts have arrived (rice cooker, thermistors, relay, and NodeMCU), so once I get home, I can hit the ground running.

***

# Terminology

### Directive

A directive is an instruction for the rice cooker.
User facing directives have, at most, a single input.

Internally, directives chain each other with conditions to achieve their given goal.

***

# Thoughts

Having received shipment of the rice cooker, and beginning to use it, I realize there's nothing about it that makes it fit only for rice, if I can control the heating myself.
Everything about it is like any other hot pot, it's just tuned for cooking rice.

Thus, once I convert the thing to being smart, I will be able to use it for, say, ramen, or any number of other things.
The possibility of steaming things only furthers this goal.

## Recipes

Recipes should be submitted as simple JSON structures.
These may be linted, and will contain no logic.
All calculations are to be done when producing the recipe.
This is done so as to ease the technical burden on the cooker.

## Heating / Cooling

Active cooling is not something worth designing for, as it is not an issue to begin with.

## Coding

Internally, a temperature kill switch should be enacted, which will kick in if the 

***

# API

I tentatively (with no real experience designing them) plan on my API being something like the following.

- `/action/light/kill` - *Kill all light activity*
- `/action/light/set` - *Change lighting mode, with optional duration*
- `/action/temperature/kill` - *Stops all heating*
- `/action/temperature/set` - *Heat/cool to given temperature.*
- `/routine/cook/kill` - *Kill any current running routine*
- `/routine/cook/list` - *List known cooking routines*
- `/routine/cook/schedule/list` - *List any scheduled routines*
- `/routine/cook/schedule/set` - *Submit/modify/delete a scheduled routine*
- `/routine/cook/start` - *Start a routine*
- `/sensor/temperature` - *Returns temperature*
- `/settings/cook/recipe/list` - *List known cooking routines*
- `/settings/cook/recipe/set` - *Submit/modify/delete a cooking routine*
- `/settings/lighting/list` - *List lighting modes*
- `/settings/lighting/set` - *Submit/modify/delete a lighting mode*
- `/settings/time/set` - *Set/read date and time*

# Cooking recipe definition specifications

They may be categorized as follows:

#### Primary Directives

* Heat
* Sleep

#### Secondary Directives

* Lighting Change
* Lighting Kill
* Temperature Change
* Temperature Hold
* Temperature Kill

## Definitions

These are defined as such:

### Sleep
Wait for a given duration.
No need to expose to recipes directly, see `Kill`, `Temperature Change`, and `Temperature Hold` instead.
Will keep things like LED lights going still.

### Heat
Takes a bool, turns the heating element on or off.
Non-blocking so that conditions may be checked without unnecessarily cycling the relay.
Dangerous to expose to recipes directly, see `Kill`

### Lighting Change
Change lighting mode.

### Lighting Kill
Kill any running lighting mode.

### Temperature Change
Heat/cool to given temperature.
This should just be a proxy directive to `Heat` and `Sleep`.
That is, `Heat` if under temp, `Sleep` if over temp.
As heating during cooking tends to be a matter of getting to temperature as quickly as possible, there is no need for a duration setting.

### Temperature Hold
Hold at current temperature for given duration.
This should just be a proxy directive to `Heat` and `Sleep`.
That is, `Heat` if under temp, `Sleep` if over temp, until an internal clock has ticked over the time required.

### Temperature Kill
Turns off heat, cancels any running recipe.
Takes no input.
Just a proxy to `Heat`, but only as a false bool.

*Might* be used at the end of a recipe, unnecessary though.
Mostly to be used as a soft kill switch, invoked from a physical button or via API.
Examples might be canceling an infinite temperature holding cycle (e.g rice warming).

# Dep Graph

<img src="/images/rice/connections.svg">
