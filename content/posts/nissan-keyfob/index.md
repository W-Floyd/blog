---
title: "Analysis of a 2005 Nissan Altima Remote Keyfob"
date: "2021-01-08"
author: "William Floyd"
featured_image: "media/fob/closed.jpg"
categories: [
    "Hardware",
    "Electronics",
    "Hacking",
    "SDR",
    "Automotive",
    "RF"
]
tags: [
    "Nissan",
    "Altima",
    "Wireless",
    "315MHz"
]
---

I got my first car a few months ago - a decidedly beat up North American 2005 Nissan Altima.
It came with a remote keyfob, but something was shorting internally, and the battery would drain within a matter of hours.
I ordered a two-pack of aftermarket fobs from Amazon, paired them no problem, and that was that.

After a while though, I got to thinking, how might I connect my car to my Home Assistant system?
I am reluctant to tap into the CAN bus directly, so instead I am going to investigate utilizing the same method as my remote fob. Specifically, I want to program my own "fob" using an Arduino and a RF transmitter (spoiler: I cannot, at least for now).

***

# The Hardware

[![Opened remote](media/fob/opened.jpg)](media/src/fob/opened.jpg)

While I may analyze the original fob at some point, for the time being I shall work from the aftermarket fob.
Opening the casing reveals a rather simple circuit ([front](media/fob/pcb_front.jpg), [back](media/fob/pcb_back.jpg)) - battery contacts, four buttons, a smattering of passives, an oscillator, the main control chip, 8 test points, and an antenna trace running around the perimeter of the PCB.

[![Closeup](media/fob/closeup.jpg)](media/src/fob/closeup.jpg)

Rather unhelpfully, the control IC is unmarked, so either I'll need to wait until I can look at the original fob to find any clues, or try to find what I need online.

As a note, it should be easy enough for me to replace the buttons with an electrical solution controlled by an ESP8266 or similar - I may end up doing this some day.
For the time being, however, I have nothing to glean from the hardware in my fob.

# Research

A quick look at the Amazon listing for my fob already tells me what models of fobs it replaces: KBRASTU15, CWTWB1U758, and CWTWB1U821.
Matching other listings, my specific model is the KBRASTU15.
This is actually an FCC ID, so that's my next lead.

This [fccid.io](https://fccid.io/KBRASTU15) listing is a rather useful, providing original FCC images and documents.
Unfortunately, the [internal images](https://fccid.io/KBRASTU15/Internal-Photos/Internal-Photos-140601.pdf) are low enough resolution to prevent reading the IC silkscreen.
Interestingly, the aftermarket fob has a small fraction of the part count of the original fob, while still functioning perfectly.
The most useful available document is the [Technical Description](https://fccid.io/KBRASTU15/Operational-Description/Technical-Description-139545.pdf).
This is where we start to get somewhere.

In essence, the fob emits a wakeup sequence 'A', followed by sequence 'B' repeated as long as the button is pressed.
The structure of these sequences is also described - sufficient to say, it uses a rolling code system.
Importantly for my analysis, the encoding method of the signal is given (though interestingly their diagram annotations seems to be incorrect).

With this information in hand, I ordered a cheap RTL-SDR (a Nooelec NESDR Mini 2+).

# SDR Analysis

[![4 Presses of the Locking Key](media/4_locks.png)](media/4_locks.png)

The radio, being a North American model, operates at 315MHz.
Using Universal [Radio Hacker](https://github.com/jopohl/urh), I began capturing examples of locking and unlocking signals.
Using the software is outside the scope of this post, but I found some YouTube videos by the software author that proved to be useful - it's not hard to learn to use.

Ultimately, I ended up trimming down 4 'B' sequences each of locking and unlocking (that is, different presses, not repeats during the same press).
I also opted not to include the preamble and header of these 'B' sequences, as these are the same for any fob and include no actual information.

The resulting signals varied in length and followed no apparent repeating format - this is where the encoding scheme described in the FCC documents comes in.
Fortunately, URH allows specifying and chaining encoding schemes, as well as calling external software to decode the data.
As I am not dealing with a large amount of data, I wrote a quick bash script to decode the data:

```bash
#!/bin/bash

lc=''

while IFS= read -r -n1 c; do

        if [ "${c}" == '' ]; then
                break
        fi

        if [ "${c}" != "${lc}" ] && [ "${lc}" != '' ]; then
                echo -n "${lc}" # Deal with the last character
                lc="${c}"
        elif [ "${lc}" == "${c}" ]; then
                if [ "${c}" == '0' ]; then
                        echo -n '1'
                else
                        echo -n '0'
                fi
                lc=''
        elif [ "${lc}" == '' ]; then
                lc="${c}"
        fi

done <<<"${1}"

exit

```

This does the trick, and all the data has a uniform length of 67 bits.
While the document specifies 66 bits, perhaps the aftermarket keyfob adds an extra bit.
In any case, this extra trailing bit is always 0.

Finally we have something like this:

[![Decoded data](media/decoded.png)](media/decoded.png)

The top four entries are when locking, the bottom four when unlocking.
The highlighted segments from left to right, as per the technical document, are:
* encrypt
* serial number
* function code
* verify code

It can easily be seen how the intent of the button press is not encrypted, but is part of the function code near the end.
Also, the serial is correctly defined, as it does not change at any point.
I am not sure what the verify bits are present for - perhaps if an error occurs the encoding scheme would result in a non 0 result (though this is purely speculation).

What we know now is that the keyfob does indeed use a rolling code algorithm, though not which one (web searches do not seem to specify).

# More Research

I do not have access to the original keyfob at this time, so some image searching may be in order.
Several leads appeared:
[![Different model fob with same compatibility](media/research/alt_1.jpg)](media/research/alt_1.jpg)
[![Pre-owned OEM fob](media/research/alt_2.jpg)](media/research/alt_2.jpg)
[![Similar model to mine](media/research/alt_3.jpg)](media/research/alt_3.jpg)

None of them appear especially legible, so the first thing I can do is compare the logo on the OEM fob to existing rolling code chip manufacturers.
As it happens, Microchip is the company in question, producing the widely documented Keeloq product line ([leaked spec sheet](http://keeloq.narod.ru/decryption.pdf)).
Looking at their product lines, it becomes clear that the original fob used the HCS361 chip.
My aftermarket chips must be using a knockoff or unmarked version of this.