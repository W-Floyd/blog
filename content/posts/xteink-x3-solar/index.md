---
title: "A Solar Battery Backpack for the XTEINK X3"
date: "2026-07-21"
author: "William Floyd"
featuredImage: "media/PXL_20260721_185507668.avif"
categories: [
    "Hardware",
    "Electronics",
    "Power",
    "Solar"
]
tags: [
    "XTEINK",
    "E-Ink",
    "LiPo",
    "Solar",
    "Epoxy"
]
---

***(CLAUDE)*** The XTEINK X3 is a pocket-sized e-reader.
***(CLAUDE)*** It measures roughly 97.6 × 63.7mm, is 5.1mm thick, and has a 3.7" E-ink screen and a 650mAh internal battery.
***(CLAUDE)*** It charges over a proprietary 4-pin magnetic pogo connector, and its back is magnetic so it can attach to a phone.

***(CLAUDE)*** Because the X3 is designed to mount to the back of a phone, the accessory can be built as the surface it docks to rather than as a case that wraps around it.
***(CLAUDE)*** The goal of this project was a slim slab that acts like the back of a phone, holds a battery and a solar panel, and supplies power to the X3 whenever the two are docked together.

{{< image src="media/PXL_20260721_185507668.avif" alt="The finished solar slab lying on a table with the XTEINK X3 docked on top, its E-ink screen showing the cover of the book Wool by Hugh Howey" >}}

***

# Planning it out

***(CLAUDE)*** I worked out the design in an extended conversation with Gemini.
***(CLAUDE)*** It steered the parts selection away from options that did not fit the constraints, such as harvesting a phone battery or using a garden-lamp solar controller that disables its output in daylight.

***(CLAUDE)*** The requirements I settled on:

***(CLAUDE)*** - Thin, flat components, to suit a shallow epoxy pour.
***(CLAUDE)*** - A solar input, so the pack tops itself up from ambient light.
***(CLAUDE)*** - A stable 5V output to the X3's charging pins.
***(CLAUDE)*** - No moving parts, so nothing needs to survive being cast in resin.

# The parts

***(CLAUDE)*** The bill of materials came out to a handful of low-cost boards:

| Part | Role | Notes |
| --- | --- | --- |
| 5V 150mA polycrystalline solar panel (~89 × 61mm) | Charging input | Close to the footprint of the X3's back |
| CN3163 mini solar charger board | Battery management | Linear solar-tracking charger, 4.4-6V in, 4.2V out |
| TPS63020 buck-boost module | 5V output | Fixed 5V via a solder jumper, has an EN pin |
| 303450 LiPo pouch cell, 3.7V 500mAh | Energy storage | Roughly doubles the X3's onboard capacity |
| Molded reed switch (N/O) | Magnetic power switch | Enables the boost converter only when docked |
| 4-pin 2.54mm magnetic pogo connector | Output to the X3 | Matches the X3's charging pin pitch |
| BSI slow-cure epoxy | Potting | See the notes on the pour below |

***(CLAUDE)*** The initial plan called for a three-cell parallel pack of small pouch cells to keep the assembly flat.
***(CLAUDE)*** I used a single, larger 500mAh 303450 cell instead.
***(CLAUDE)*** A single cell removes the need for voltage-matching and balancing and leaves one block to plan around rather than three.

{{< image src="media/PXL_20260721_023603657.avif" alt="Close-up of the single 3.7V 500mAh 303450 lithium polymer pouch cell on the workbench" >}}

# The circuit

***(CLAUDE)*** The solar panel feeds the CN3163 charger, the charger sits across the battery, and the battery feeds the boost converter, which supplies 5V to the pogo pins.

***(CLAUDE)*** The reed switch gates the boost converter's enable (EN) pin rather than leaving the converter powered continuously.
***(CLAUDE)*** When the X3 is docked, its magnet closes the switch, the converter enables, and 5V is supplied.
***(CLAUDE)*** When the X3 is removed, the converter shuts down to a near-zero standby draw.

```
 [ 5V 150mA solar panel ]
        + │ -
          ▼
 ┌─────────────────────┐
 │ IN+            IN-   │
 │      CN3163          │
 │ BAT+           BAT-  │
 └───┬─────────────┬────┘
     │             │
     ├── LiPo + ───┼── LiPo -            (single 500mAh cell)
     │             │
     ├── VIN ──────┼── GND ── TPS63020
     │             │
 [reed]            │
     │             │
     └── EN        │
         │         │
    [ resistor to GND ]
                   │
   TPS63020 VOUT ──┴─► pogo pin 1 (+5V)
   TPS63020 GND  ────► pogo pin 4 (GND)
   pogo pins 2 & 3 (data) left unconnected
```

***(CLAUDE)*** The TPS63020 requires two solder jumpers to be set: one to select 5V output (the boards typically ship configured for 3.3V), and the PS jumper bridged to select the high-power mode instead of the low-power mode.
***(CLAUDE)*** The high-power mode produces less output ripple, at the cost of higher idle current, which the reed switch offsets by disabling the converter when undocked.

## The enable pin

***(CLAUDE)*** The intended behavior was: the reed switch pulls EN up to the battery voltage when docked, and a resistor pulls EN down to ground when undocked.
***(CLAUDE)*** My TPS63020 board had an internal pull-up on EN, so the pin floated high and the converter was enabled by default, which is the opposite of the intended behavior.

***(CLAUDE)*** Adding a pull-down resistor between EN and ground overrides the internal pull-up.
***(CLAUDE)*** A 5.1kΩ resistor left EN at 2.67V when undocked, above the chip's ~0.4V off threshold, so the converter stayed enabled.
***(CLAUDE)*** The internal pull-up and the 5.1kΩ resistor formed a voltage divider that held EN too high.
***(CLAUDE)*** A smaller resistor of a few hundred ohms pulls EN below the off threshold when the magnet is removed.

# Building it

***(CLAUDE)*** Rather than use a perfboard, I wired the boards together point to point and hot-glued everything directly to the back of the solar panel, positioning the pogo connector at one edge so its pins would exit the side of the finished slab.
***(CLAUDE)*** 30 AWG silicone wire keeps the runs thin and flexible enough to lie flat.

{{< image src="media/PXL_20260721_022353626.avif" alt="The components laid out on a workbench mat: solar panel, TPS63020 and CN3163 boards, the LiPo cell, and a box of hook-up wire" >}}

{{< image src="media/PXL_20260721_035106094.avif" alt="The wired components inside a clear acrylic box, with the boost board, charger, reed switch, resistor and battery held together with hot glue" >}}

***(CLAUDE)*** The pogo output uses a pre-made magnetic connector with the pins already wired, which avoids soldering near the neodymium magnets; the magnets lose strength if heated past roughly 80°C.
***(CLAUDE)*** Only two of the four pins carry power; the two data pins are unused and left unconnected.

{{< image src="media/PXL_20260721_133258834.avif" alt="Fingers holding the small 4-pin magnetic pogo connector, its four gold spring pins facing up" >}}

***(CLAUDE)*** The battery was wrapped in a plastic sleeve and silicone tape before assembly.
***(CLAUDE)*** LiPo cells expand and contract as they cycle, so the tape provides a compressible buffer between the cell and the rigid resin.

{{< image src="media/PXL_20260721_023949842.avif" alt="The 500mAh LiPo cell sealed inside a clear plastic sleeve, next to the wired boost board" >}}

# The pour

***(CLAUDE)*** Rather than 3D-print a mold, I used a clear acrylic display box of about the right footprint, with the solar panel face-down against the bottom and the pogo connector exiting one edge.

***(CLAUDE)*** The appropriate material for potting electronics around a battery is a slow deep-pour casting resin, which cures over a day or two and generates little heat.
***(CLAUDE)*** I used a 30-minute BSI slow-cure epoxy, which cures faster and generates more heat during curing.

{{< image src="media/PXL_20260721_143444631.avif" alt="The acrylic box after pouring, the epoxy full of tiny bubbles with the battery, boards and pogo connector visible underneath" >}}

***(CLAUDE)*** The faster cure trapped air and produced heat, and the cured block came out cloudy and full of microbubbles rather than clear.
***(CLAUDE)*** The block is structurally sound and the cell did not overheat, but the resin is not transparent.

{{< image src="media/PXL_20260721_152110380.avif" alt="Edge-on view of the cured epoxy slab, cloudy and bubbly, with the four pogo pins protruding cleanly from one edge" >}}

# Finishing touches

***(CLAUDE)*** For the X3 to attach, the slab needs magnets that align with the X3's own.
***(CLAUDE)*** I located the X3's internal magnets by sliding a loose magnet across its back and marking where it held, then set matching disc magnets into the slab at those positions.

{{< image src="media/PXL_20260721_180618967.avif" alt="The back of the XTEINK X3 showing its four gold pogo charging contacts and the XTEINK logo" >}}

***(CLAUDE)*** Because the magnets were not positioned accurately before casting, I drilled into the cured block to seat them in the correct locations.
***(CLAUDE)*** Casting the magnets in place would have avoided the post-pour drilling.

{{< image src="media/PXL_20260721_180835507.avif" alt="A drill bit boring a hole into the cured epoxy slab to seat a magnet, near the embedded battery" >}}

***(CLAUDE)*** Since the cured back is opaque, I covered it with black marker.

{{< image src="media/PXL_20260721_185526103.avif" alt="The back of the finished slab on a wood floor, scribbled over in black marker, with embedded disc magnets and the pogo pins along one edge" >}}

# Results

***(CLAUDE)*** The assembly works as intended.

{{< image src="media/PXL_20260721_190433874.avif" alt="The solar-panel face of the finished slab held up to daylight outdoors" >}}

***(CLAUDE)*** The solar face charges the cell through the CN3163, and when the X3 is docked the reed switch closes and 5V is supplied to its pogo pins.
***(CLAUDE)*** When the X3 is removed, the output is disabled.
***(CLAUDE)*** The 500mAh cell roughly doubles the X3's 650mAh internal capacity, and the 150mA panel offsets the low average power draw of the E-ink display, which draws meaningful current mainly during page turns.

{{< image src="media/PXL_20260721_185514888.avif" alt="The XTEINK X3 docked on the slab, solar panel facing up, the two magnetically snapped together" >}}

# Notes for a future build

***(CLAUDE)*** - Use a deep-pour casting resin instead of fast epoxy, for a clear, cool cure.
***(CLAUDE)*** - Position and cast the magnets before pouring, rather than drilling them in afterward.
***(CLAUDE)*** - Check the boost board's EN pull-up configuration before wiring the enable circuit.
***(CLAUDE)*** - Plan for the final thickness that results from the chosen components rather than a target thinner than they allow.
