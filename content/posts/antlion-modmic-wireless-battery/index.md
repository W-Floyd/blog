---
title: "Antlion ModMic Wireless Battery Swap"
date: "2026-07-24"
author: "William Floyd"
featuredImage: "media/DSC_5999.avif"
categories: [
    "Hardware",
    "Electronics",
    "Repair"
]
tags: [
    "Antlion",
    "ModMic",
    "Battery",
    "LiPo",
    "Repair"
]
---

I've used an [Antlion ModMic Wireless](https://antlionaudio.com/products/modmic-wireless) since I started my first job (where I regularly took calls 6+ hours a day).
Over time, its runtime has dropped from a full day to about half, and Antlion doesn't sell replacement batteries, so officially my only fix was a new mic.
But it's held together with just three screws, so swapping the battery is easy enough (took me 15 minutes).

***

The base of the mic is a two-part plastic body held together by three small screws, with nothing glued.

{{< figures >}}
{{< image src="media/PXL_20260723_165030207.avif" alt="The opened plastic body, one half holding the circuit board with the old battery, the other half an empty shell with a foam pad, a pry tool alongside" >}}
{{< image src="media/PXL_20260723_165502858.avif" alt="Close-up of the green Antlion board with the original silver JHY502030 250mAh pouch cell taped over it, red and black leads soldered near the cable's strain relief, micro-USB port below" rotate="90" >}}
{{< image src="media/PXL_20260723_165800912.avif" alt="The board lifted out of the shell with the old cell flipped up, exposing the ANTLION-marked PCB, its micro-USB charging port, and the two soldered battery leads" >}}
{{< /figures >}}

The cell is a 502030 LiPo cell (3.7V, 250mAh, dated 2022.04.22), stuck with double-sided tape and soldered to two pads.
That "502030" is the cell's size (5 x 20 x 30mm), which is all you need to find a replacement.
I ordered a replacement 502030 from Amazon ($8 after tax).
Unfortunately there's no space to choose a larger size.

{{< image src="media/DSC_6005.avif" alt="The new LP502030 pouch cell, its white label reading 3.7V 250mAh 0.9Wh, with a two-pin JST connector on the end of its leads" >}}

Mine came with a JST plug, so I snipped it off (don't cut the wires at the same time!).
The old cell comes off by desoldering its two leads and working a piece of cardstock underneath to release the double-sided tape without damaging the old cell.
The replacement goes in the same way - leads soldered to the same pads, and taped down in the same spot.
Screw it together the same way it came apart.

{{< image src="media/DSC_6007.avif" alt="The new cell soldered to the Antlion board out of its case, red and black leads joined to the pads beside the cable strain relief" >}}
{{< image src="media/DSC_6008.avif" alt="The new LP502030 battery seated inside the plastic body on top of the board, next to a roll of clear tape" >}}