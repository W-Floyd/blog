---
title: "Ghetto NAS Part 1"
date: "2023-08-29"
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

This is an ongoing project to build a custom NAS on the most minimal budget possible.

# Use Case

Storing a large (30TB+) amount of infrequently accessed data that must still be immediately accessible (primarily Jellyfin, Nextcloud), with some level of safety.

Some details about my use case:
* There will be no external network access except via a single local client mounting the drive and sharing via ZeroTier
* There will be very few clients total
* Most data is replaceable, though inconveniently so (media may be reacquired / restored from backups)
* Neither latency nor throughput are very important

# Bill of Materials

| Quantity | Item                         | Per Unit Cost | Notes                                                                                         |
|----------|------------------------------|---------------|-----------------------------------------------------------------------------------------------|
| 3        | Dell Wyse 3030LT Thin Client | $11           | Ebay - Fairly common, though may run out eventually - other thin clients will no doubt appear |
| 3        | HGST 10TB He10 510           | $80           | Amazon / Ebay - Very common, can pick these up any day                                        |
| 3        | ORICO 3.5in to USB enclosure | $25           | Amazon - Could use another, this is what I chose, does the job for me                         |
| 5        | Ethernet Cables              | $2.5          | Amazon - $12.50 / 5 pack - Or whatever you have lying around                                  |
| 1        | 8 Port Ethernet Switch       | $13           | Amazon - Or whatever you have lying around                                                    |
| 0.5kg    | PLA                          | $20           | For the NAS enclosure                                                                         |

# Rationale

In order of importance for my use case: Price > Redundancy > Performance

## Hardware

### Thin Client
You simply cannot beat a whole working Linux box for $11.
With 2GB RAM, 4GB eMMC, 1 GbE, 1 USB 3 port, and a bundled power adapter, it does the bare minimum I need.

### HDD
Similarly, **used** enterprise drives deliver an amazing value.
For less than $9/TB or just over $10/TB with the enclosure, these drives are the cheapest possible way to get storage right now.
By using external enclosures we can also upgrade to larger drives in future, with minimal effort.
No shucking required!

I buy ones that have a 5 year warranty (spoiler - it's worth having!).

### Networking
1GbE is plenty enough for me, but if in future I need more speed, I can find a network switch with 10GbE uplink and scale horizontally a fair bit.
For now, a cheap unmanaged GbE switch will do just fine.

### UPS
Not 100% required, but the peace of mind in having the whole system on a UPS is worth it.

## Software

### Gluster

I am using Gluster to run my NAS cluster.
This is in large part due to its very modest hardware requirements, especially memory.
I can run my nodes with less than 50% memory utilization, and not fill my limited eMMC storage either.
It is very easy to work with, and offers flexible redundancy configurations.

#### Configuration

I am using Gluster with a dispersed volume, using the native client on my main server to mount the volume.
Dispersed lets me add clusters of bricks fairly easily, which suits my needs well.

### Netdata

This lets me know if/when drives get full, lets me know drive temperature from SMART data, and will email me if any hosts go offline.

# Experiences so far

I've been too busy to document the whole process, but I currently have a 2 x (2 + 1) array running (if I'd known I'd need 6 drives, I'd have done 1 x (4 + 2), but I didn't know at first).
Capacity is 60TB raw, 40TB usable.

## HDD Failures

That 5 year warranty I mentioned?
I've needed it twice so far - one drive died about 1 month in, and a second died 2 months in.
To their credit, the vendor got me a return package label within one business day each time, and refunded me as soon as the return package arrived.
For now, I continue to use these drives because the $/TB is so good, but in future I may upgrade to some larger drives in the same way to keep power costs down.

## Power Draw

6 x HDDs + 6 x Thin Clients + Network Switch + 12V Power Supply, draws about 40W at the wall under regular load (serving files).