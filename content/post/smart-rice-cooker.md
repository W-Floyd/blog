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

# Thoughts

Having received shipment of the rice cooker, and beginning to use it, I realise there's nothing about it that makes it fit only for rice, if I can control the heating myself.
Everything about it is like any other hot pot, it's just tuned for cooking rice.

Thus, once I convert the thing to being smart, I will be able to use it for, say, ramen, or any number of other things.
The possibility of steaming things only furthers this goal.

## Recipes

The question is raised, how should I deal with parametric recipes, and more specifically, internally governed parametric recipes.
That is, recipes that have no prior knowledge of the volume of rice and water added, but infer it from the time it takes to reach temperature.
This value, that is, the duration taken to reach temperature, only holds value when a set heating cycle is used, such as full heat, or constant PWM.
Typically however, no PWM is required during initial heat, only once at heat.

As such, a value that any directive may rely upon should be the duration taken by some prior directive.
This then leads me to say that each and every step in a recipe must have a unique identity, so that later directives may rely on them.

This, then, immediately appears to be far more complicated than I should worry about, instead, this behaviour aught to be offloaded to Lua or some other scripting system.
As such, the NodeMCU should be ideal, as it supports a variation of Lua.
Ideally, this will allow branching logic also, and storing of values, simplifying my technical burden.

Alternatively, it does not sound impossible to write a simple translator to emit both a Lua scripted version of a recipe, and a version that may be embedded directly into the compiled code (so that non-Lua boards may be used).

## Heating

The contents of the rice cooker should be considered when heating/cooling, as they will absorb the heat and thermal lag will be an issue.
If possible, look into either weighing the contents for a rough approximation (hard/complicated) or use recipe provided portion sizes to calculate the thermal capacity of the contents (water, mainly).

Seeing as the dumb rice cooker still manages to kick itself off when needed, even given different serving sizes, there must be a simple way to find the time needed to cook the rice, even without predefines portion sizes.

On the face of it, I would assume the time rice is kept at full heat will only slightly increase in duration as the volume of rice increases, if at all.
The time it takes to get up to heat shouln't be ignored, as some cooking must be done during that time.
The variety of rice should not be discounted either.

Further research into the dynamics of rice cooking are meritted, once internet and more rice is available once again.

## Cooling

I am planning my setup in such a way as to allow actively cooling the cooking pot, but upon further consideration, it is likely not an issue worth worrying about.
As such, I'll continue my planning as I am, but not be too worried about the details for now.

***

# API

I tentatively (with no real experience designing them) plan on my API being something like the following.

- `/action/light/kill` - *Stops all light activity*
- `/action/light/set` - *Change lighting mode, with optional duration*
- `/action/temperature/kill` - *Stops all heating/cooling, lets the cooker cool to room temperature alone*
- `/action/temperature/set` - *Heat/cool to given temperature, then hold. Should allow setting a target heat/cool rate. Should allow setting a hold duration*
*(proxy to `/settings/cook/recipe/list`)*
- `/routine/cook/kill` - *Kill any current running routine*
- `/routine/cook/list` - *List known cooking routines*
- `/routine/cook/schedule/list` - *List any scheduled routines*
- `/routine/cook/schedule/set` - *Submit/modify/delete a scheduled routine*
- `/routine/cook/start` - *Start a routine*
- `/sensor/temperature` - *Returns temperature*
- `/settings/cook/recipe/list` - *List known cooking routines*
- `/settings/cook/recipe/set` - *Submit/modify/delete a cooking routine*
- `/settings/cook/warm/duration` - *Determine post-cook warming duration*
- `/settings/cook/warm/set` - *Turn post-cook warming on/off*
- `/settings/cook/warm/temperature` - *Set post-cook warming temperature*
- `/settings/lighting/list` - *List lighting modes*
- `/settings/lighting/set` - *Submit/modify/delete a lighting mode*
- `/settings/time/set` - *Set/read date and time*

# Cooking schedule definition specifications

Directives are distinct actions to be taken.

They may be catagorised as follows:

#### Primary Directives

* Sleep
* Heat
* Cooling

#### Secondary Directives

* Temperature

These are defined as such:

### Sleep
Just wait for given duration, or until a given condition is met.

### Heat
Heat for a given duration, or until a given condition is met.

### Cool
Cool for a given duration, or until a given condition is met.
If I someday choose to use a fan, this should be an active feature.
Instead, it's the same as `Sleep` for now.

### Temperature
Heat/cool to given temperature, optionally at a given rate of change (may be difficult for cooling if no fan is included), or percentage load (which will set a PWM rate, or if full, run constant).
This should just be a proxy directive to `Heat`, `Cool`, and `Sleep`.
For now that should work, but in due course, with tuning and benchmarks, this should run cooling at a variable rate (using a fan, I wouldn't want to cut on and off all the time).
Heating should be fine be fine with fairly large PWM, as the thermal lag I expect to be significant, and we want to try to hit our deadline as quickly as possible.

# Dep Graph

<img src="/images/rice/connections.svg">
