---
title: "Ghetto NAS Part 2"
date: "2024-02-16"
author: "William Floyd"
#featured_image: "media/IMG_20220126_225541.webp"
categories: [
    "Sys Admin",
    "Hardware",
    "Software"
]
tags: [
    "NAS",
    "3D Printing",
    "Gluster",
    "Homelab"
]
series: ["Ghetto NAS"]
list: never
draft: true
---

I've been running the Gluster array from [part one](../ghetto-nas-part-01/) of this series for some months now, and am looking to improve my setup as I move to a new location and have new requirements.

# Existing Hardware

As a reminder/update, here is my existing hardware setup:

* Used HP Z440
    * CPU
        * Intel Xeon 1650-v4 (6 core, 12 thread, 3.6/4.0GHZ)
    * Memory
        * 128GB LRDDR4 @ 2133MT/s
    * Storage
        * 1TB NVME boot drive via PCIE adapter
        * 8TB shucked WD Easystore (bought new)
        * 14TB shucked WD Easystore (bought new)
    * GPU
        * Dell GTX 1080 (for gaming)
        * Intel Arc A380 (for transcoding)
* 6 x Gluster Nodes
    * Dell Wyse 3030 LT Thin Client
        * CPU
            * Intel Celerton N2807 (2 core, 0.5/2.167GHz)
        * Memory
            * 2GB Memory
        * Storage
            * 4GB MMC boot drive
            * ORICO 3.5" SATA to USB 3.0 desktop adapter
                * 10TB HGST He10 (refurbished, 5 year warranty)
* Generic 360W 12V power supply for Thin Clients and HDDs
* Generic Gigabit ethernet switch for all thin clients and workstation

# Requirements

Given my experiences with my existing solution, my new setup must (continue) to be:
* Able to support my existing 40TB usable space, scalable up to ~100TB
* Easily maintainable
* Performant
* Mostly quiet
* Cost effective
    * Initial cost
    * Cost over time (aiming for 5 year lifecycle)
* Power efficient
    * Fewer Gluster nodes
    * Large disks > many disks
* Reliable
    * ECC Memory
    * Redundant storage

This leaves me with the following requirements:
* Must support a `n x (4 + 2)` disk arrangement (~67% usable space with 2 disks of redundancy, especially as I plan to use used drives)
* Disks must be 10TB or larger
* Disks must be cheap
* Disks should have reasonable warranty

Additional observations/experience:
* The 4GB storage on the Dell Wyse 3030 LT nodes is difficult to work in. If the storage fills, it can result in a node failing to come online after a restart
* Network latency results in slow directory operations via Gluster
* The workstation is already well capable of handling this many drives, it makes more sense to connect them directly to the drives as it is their only client

With this in mind, I want to move away from multiple storage nodes and consolidate into a more unified storage system

# Options

## NAS

### Prebuilt

Easiest option, but not my ideal as I want to learn, and know my system wholely.
Hardware is too expensive, no expandability, so I'm not going to do it.
Good more many people's cases though.

### Custom built

Solid option, but too expensive - I already have a workstation, I don't want another desktop holding all the drives and not doing anything useful otherwise. More of a sunk cost issue than a failure of this option, I just can't justify redundant hardware like this. Also, power draw would be increased as I'd be adding a system, not replacing.

If I were to do this, these are some of the options I've looked at:
* Mini ITX motherboard
    * [All in one](https://www.aliexpress.us/item/3256806141617147.html) ([alternative](https://www.aliexpress.us/item/3256806353828287.html)) - $125-$160 depending on spec
      * 6 SATA ports, PCIE, 4x2.5GbE, NVME
      * Power efficient (<10W TDP)
      * No ECC, memory not included
      * No brand support
    * [Xeon Kit](https://www.aliexpress.us/item/3256805579918121.html) - ~$135
      * 6(?) SATA ports, PCIE, 2x2.5GbE, NVME(?)
      * Powerful, not power efficient (90W TDP)
      * ECC memory included
      * No brand support
      * Cooler not included
      * More of a replacement to my workstation
* [3D printed case](https://modcase.com.au/products/nas)
* NAS Case
  * [Silverstone DS308B](https://www.silverstonetek.com/en/product/info/server-nas/DS380/)
    * Too expensive ($200+)
  * [Generic 8 bay ITX enclosure](https://www.amazon.com/KCMconmey-Internal-Compatible-Backplane-Enclosure/dp/B0BXKSS8YY/)
    * Too expensive ($150)
    * No brand support
    * Leaves empty bays if expanding in 6 drive increments

Overall something I've strongly considered, mostly for space savings, but cost is keeping me away, as it's basically a whole new PC for each new node (unless I'm expanding somehow otherwise, which I could do via the workstation anyway).

## JBOD

Requires an external HBA/SATA expander from the workstation. 

### Prebuilt (ex-Enterprise)

Strong option, moderately easy to set up.
Concerns are:
* Power draw
* Noise
* Need for rack mounting
* More bays than I need

If I were to do this (and I may do some day), I would probably get an EMC KTN-STL3, a 15 bay chassis.

### Custom built (from scratch)

Too much work, don't want to *need* to design my own PCB for this.

### Custom built (using ex-Enterprise parts)

A few options,

https://www.supermicro.com/manuals/other/BPN-SAS3-815TQ.pdf

# Physical layout

I had begun modelling and came close to 3D printing an all in one cluster enclosure for 3 clients and 3 drives that would include a power distribution board, fan controller with temperature sensor, and panel mounted Ethernet ports.
This was never finished, and as I look to 