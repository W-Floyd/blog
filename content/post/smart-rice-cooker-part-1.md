---
title: "Smart Rice Cooker Conversion: Part 1"
date: "2018-06-18"
author: "William Floyd"
---

The "why" isn't important (read "doesn't exist"), but I want to take a regular old "dumb" rice cooker, and convert it into a "smart" rice cooker.

So, a whim and a few minutes on Aliexpress later, my pint sized rice cooker and an assortment of electronics are on the slow boat from China.

Having no real clue what I'm doing, here's what I've ordered thus far:

Main list of things:

- [Rice cooker](http://ali.onl/128Y) ($26.40 + $3.16 S&H - The star of the show.)
- [Thermistors](http://ali.onl/128Q) ($2.97 - 100pcs, for temperature readings)
- [NodeMCU](http://ali.onl/128R) ($2.47 - To, hopefully, allow me to Wifi control the whole thing)
- [Relay](http://ali.onl/128V) ($0.76 - To switch power on and off.)
- [ESP8266 Relay](http://ali.onl/128T) ($2.91 + $0.14 S&H - Alternative to the NodeMCU + Relay pairing I'm planning on using)

While I have dabbled with Arduino before, this is a far more ambitious project than I have yet done.
Ideally, I will have the rice cooker serve an API, which my Orange Pi will bounce requests across to as dictated by a frontend hosted on the same machine (this resolves CORS, while still allowing options to control the rice cooker by other devices).

For now though, I am away from home, working, so I can't do anything on this for at least another 2 weeks, probably 3.
Many of my parts have arrived (rice cooker, thermistors, relay, and NodeMCU), so once I get home, I can hit the ground running.

#### API

I tentatively (with no real experience designing them) plan on my API being the following.

*Italicized* = Description
**Bolded** = Final endpoints

- /sensor
  - /temperature
    - *Returns temperature*
- /action
  - *Contains all physical heating/cooling/moving actions*
  - /temperature
    - *Contains all temperature related actions*
    - **/kill**
      - *Stops all cooking, lets the cooker cool to room temperature*
    - **/change**
      - *Heat/cool to given temperature, then hold*
      - *Should allow setting a target heat/cool rate*
      - *Should allow setting a hold duration*
- /routine
  - /cook
    - **/list**
      - *List known cooking routines*
    - **/start**
      - *Start, or optionally schedule a routine*
