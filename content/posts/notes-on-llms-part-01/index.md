---
title: "Notes on LLMs - Part 1"
date: "2026-10-17"
author: "William Floyd"
featuredImage: "media/PXL_20261017_003820837.avif"
featuredImageCrop: "16/9"
featuredImagePosition: "50% 60%"
toc: true
categories: [
    "Software",
    "Hardware",
    "Development",
    "LLM"
]
tags: [
    "LLM",
    "Linux",
    "Kernel",
    "postmarketOS",
    "Android",
    "Samsung Galaxy S9",
    "Moto G Play",
    "Kia EV6",
    "Linuxboot",
    "Go",
    "Slint",
    "libcamera",
    "DOOM"
]
---

I had written a draft of an anti-LLM post some months ago, and ended up not posting it.
Since then, I've used these tools much more during my day job, as well as hobby projects.
I've had many thoughts about LLMs, and their impact on my mental health and ability to learn (or the stunting of said growth).
I've also experienced many cases where it is undoubtedly an amazing tool that has enabled me to learn new things by reducing the barrier to entry for new fields.

**In all, it's been a mixed bag, and I wish LLMs never existed.**

But the technology is here now, so I thought I'd show *some* of the things I have managed to do aided by these tools.
In line with not letting perfect get in the way of good/done, I'll probably post updates in Part 2 and so on.

# Linux Hacking

The Linux kernel is huge, complicated, amazing, and *not* something I have experience in modifying.
I am however quite comfortable compiling software and figuring out how the pieces fit together (eg [here](https://github.com/W-Floyd/solus-deepin) and [here](https://github.com/W-Floyd/solus-lxqt)).
That being the case, I've gone ahead and tried a couple projects with kernel related hacking.

## Samsung Galaxy S9 - `starqltechn`

My old phone collecting dust, so why not try to get it running Nura?[^nura]
There's already a [working port](https://wiki.nura.eco/wiki/Samsung_Galaxy_S9_(samsung-starqltechn)), but lots of peripherals don't yet work, so I figured I'd start there.

Long story short, using LLMs I was able to get:
* Working camera+flash
* Aperture control
* Manual focus
* WiFi+BT (tracked down an existing patch)
* DisplayPort output

{{< figures >}}
{{< image src="media/PXL_20260908_152254681.avif" alt="Samsung Galaxy S9 running a camera app, showing a color-bar test pattern from its working rear camera." >}}
{{< image src="media/PXL_20260911_140412637.avif" alt="Galaxy S9 camera app with the aperture selector open, offering f/1.5 and f/2.4." >}}
{{< image src="media/PXL_20260911_133003469.MP.avif" alt="Galaxy S9 connected over USB-C to a monitor, which shows the GNOME About screen: postmarketOS edge, Linux 7.1.0-rc1-sdm845, FD630 graphics." >}}
{{< /figures >}}

### My Code
* [Kernel tree](https://github.com/W-Floyd/linux/tree/dev)
* [aports](https://github.com/W-Floyd/pmaports) (spread across branches)

{{< details summary="Vendor Resources" >}}
* [Level 3 service manual (SM-G9600)](https://elektrotanya.com/samsung_galaxy_s9_g9600_service_manual.pdf/download.html)
* [Samsung 4.9 kernel source](https://github.com/droidian-devices/linux-android-samsung-starqlte) (Droidian's tree)
* [Stock firmware dump](https://dumps.tadiphone.dev/dumps/samsung/starqltechn)
{{< /details >}}

## Motorola Moto G Play (2024) - `fogona`

Fresh on the success of getting progress on an *older* phone, I decided to find the cheapest phone that a US resident can just go out and potentially install Linux on.
At this time, it's the Motorola Moto G Play (2024), which can be had for $100 USD new in box, carrier unlocked and bootloader unlockable.
There's [already SoC support](https://wiki.nura.eco/wiki/Qualcomm_Snapdragon_680_(SM6225)), but it's somewhat early.

After much back and forth, I was able to get:
* GPU support
* Video decoder acceleration
* Cameras with PDAF and stock tunings
* WiFi, BT
* Modem (data, calls, texts/mms)
* GPS, accelerometer, compass, rotation, lux, proximity

### My Code
* [Kernel tree](https://github.com/W-Floyd/linux/tree/fogona-mainline)
* [Kernel tree with Linuxboot + camera changes](https://github.com/W-Floyd/linux/tree/exp-pdaf)
* [pmaports](https://github.com/W-Floyd/pmaports/tree/fogona)

{{< details summary="Vendor Resources" >}}
* [Level 3 service manual (XT2413)](https://www.ifixit.com/Document/ohXytuihYMtgUiFU/Moto-G-Play-XT2413-Level-3-Service-Manual.pdf)
* Kernel: [Older, more complete](https://github.com/MotorolaMobilityLLC/kernel-msm/tree/android-13-release-t3tfs33.66-37-3), [Latest](https://github.com/MotorolaMobilityLLC/kernel-msm/tree/android-14-release-u1tf34.100-35-5-3-1)
* Device tree: [Older](https://github.com/MotorolaMobilityLLC/kernel-devicetree/tree/android-13-release-t3tfs33.66-37-3), [Latest](https://github.com/MotorolaMobilityLLC/kernel-devicetree/tree/android-14-release-u1tf34.100-35-5-3-1)
* Subsystem device trees
  * display: [Older](https://github.com/MotorolaMobilityLLC/kernel-display-devicetree/tree/android-13-release-t3tfs33.66-37-3), [Latest](https://github.com/MotorolaMobilityLLC/kernel-display-devicetree/tree/android-14-release-u1tf34.100-35-5-3-1)
  * camera: [Older](https://github.com/MotorolaMobilityLLC/kernel-camera-devicetree/tree/android-13-release-t3tfs33.66-37-3)
  * audio: [Older](https://github.com/MotorolaMobilityLLC/kernel-audio-devicetree/tree/android-13-release-t3tfs33.66-37-3), [Latest](https://github.com/MotorolaMobilityLLC/kernel-audio-devicetree/tree/android-14-release-u1tf34.100-35-5-3-1)
  * nfc: [Older](https://github.com/MotorolaMobilityLLC/kernel-nfc-devicetree/tree/android-13-release-t3tfs33.66-37-3), [Latest](https://github.com/MotorolaMobilityLLC/kernel-nfc-devicetree/tree/android-14-release-u1tf34.100-35-5-3-1)
  * bt: [Older](https://github.com/MotorolaMobilityLLC/kernel-bt-devicetree/tree/android-13-release-t3tfs33.66-37-3), [Latest](https://github.com/MotorolaMobilityLLC/kernel-bt-devicetree/tree/android-14-release-u1tf34.100-35-5-3-1)
  * graphics: [Older](https://github.com/MotorolaMobilityLLC/kernel-graphics-devicetree/tree/android-13-release-t3tfs33.66-37-3)
  * video: [Older](https://github.com/MotorolaMobilityLLC/kernel-video-devicetree/tree/android-13-release-t3tfs33.66-37-3)
  * wlan: [Older](https://github.com/MotorolaMobilityLLC/kernel-wlan-devicetree/tree/android-13-release-t3tfs33.66-37-3), [Latest](https://github.com/MotorolaMobilityLLC/kernel-wlan-devicetree/tree/android-14-release-u1tf34.100-35-5-3-1)
* Drivers
  * Motorola modules: [Older](https://github.com/MotorolaMobilityLLC/motorola-kernel-modules/tree/android-13-release-t3tfs33.66-37-3)
  * Camera: [Older](https://github.com/MotorolaMobilityLLC/vendor-qcom-opensource-camera-kernel/tree/android-13-release-t3tfs33.66-37-3)
  * Graphics (KGSL): [Older](https://github.com/MotorolaMobilityLLC/vendor-qcom-opensource-graphics-kernel/tree/android-13-release-t3tfs33.66-37-3), [Latest](https://github.com/MotorolaMobilityLLC/vendor-qcom-opensource-graphics-kernel/tree/android-14-release-u1tf34.100-35-5-3-1)
  * Video: [Older](https://github.com/MotorolaMobilityLLC/vendor-qcom-opensource-video-driver/tree/android-13-release-t3tfs33.66-37-3)
{{< /details >}}

### PRs that resulted:
* Merged (as of writing):
  * [mobile-broadband/libqmi | voice: add the pre-alerting call state](https://gitlab.freedesktop.org/mobile-broadband/libqmi/-/merge_requests/477)
  * [GNOME/gnome-control-center | wwan: Restore the APN dialog header bar](https://gitlab.gnome.org/GNOME/gnome-control-center/-/merge_requests/3505)
  * [postmarketOS/boot-deploy | flash vendor_boot: look up the partition before checking its size](https://gitlab.postmarketos.org/postmarketOS/boot-deploy/-/merge_requests/116)
* Unmerged:
  * [mobile-broadband/ModemManager | qmi: handle the pre-alerting call state](https://gitlab.freedesktop.org/mobile-broadband/ModemManager/-/merge_requests/1503)
  * [GNOME/mobile-broadband-provider-info | us: AT&T: add ERESELLER as MVNO APN](https://gitlab.gnome.org/GNOME/mobile-broadband-provider-info/-/merge_requests/165)
  * [kop316/mmsd | service-providers: match the APN case-insensitively](https://gitlab.com/kop316/mmsd/-/merge_requests/132)

### Projects that resulted:
#### [bootmanager](https://github.com/W-Floyd/bootmanager)
Such an inventive name, I know...
A Slint GUI + Go backend tailored for Linuxboot+u-root setups, meant to be a beautiful alternative to uboot.
Supports touchscreen, SSH, fastboot, LUKS decryption, usage in place of [unl0kr](https://github.com/droidian/unl0kr), and a web GUI built in WASM from same Slint.

{{< figures >}}
{{< image src="media/PXL_20261017_195654058.avif" alt="Moto G Play (2024) in hand, showing the bootmanager Unlock screen with a password field and on-screen keyboard for the UFS userdata partition." >}}
{{< image src="media/PXL_20261017_195700115.avif" alt="Moto G Play (2024) in hand, showing the bootmanager Choose a system screen with a postmarketOS card marked default, on encrypted UFS userdata." >}}
{{< immich-video id="ebf60442-44d2-4a6d-a578-b7f413fc37e8" slug="bootmanager-fogona" ratio="9/16" >}}
{{< /figures >}}

#### [godot-maps](https://github.com/W-Floyd/godot-maps)

Comaps doesn't look great on Linux, and I couldn't find anything else that did what I wanted, so I made a quick and dirty navigation app built on Comaps backend using Godot.
It compiles to many platforms too, including MacOS and Android.

{{< image src="media/PXL_20260929_223737700.avif" alt="godot-maps running turn-by-turn navigation on a phone held in a car: a 3D map with buildings, a blue route line, a 0.4 mi right-turn banner, a 35 mph speed limit sign, and a one-minute ETA bar." >}}

#### [go-msm-firmware-loader](https://github.com/W-Floyd/go-msm-firmware-loader)
Go port of [`msm-firmware-loader`](https://gitlab.postmarketos.org/postmarketOS/msm-firmware-loader), used by `bootmanager`

#### [go-qbootctl](https://github.com/W-Floyd/go-qbootctl)
A static Go replacement for the A/B slot subset of [`qbootctl`](https://github.com/linux-msm/qbootctl) so it works in an initramfs, used by `bootmanager`

#### [go-chromatix2libcamera](https://github.com/W-Floyd/go-chromatix2libcamera)
Translates Qualcomm Chromatix tuning files to something libcamera (or a fork thereof) can interpret.

#### [go-unbrick](https://github.com/W-Floyd/go-unbrick)
Swiss army knife that I use to inspect stock firmware images, any files contained therein, and to make some files to help with bricked devices.

#### [go-qshrink4](https://github.com/W-Floyd/go-qshrink4)
A reader for Qualcomm QShrink4 hash databases (`.qdb` / `.qsr4`), mapping the hashes in QShrink'd modem diag messages back to their format string, file and line.

## 2024 Kia EV6 Head Unit

New (to me) car, new project!
Once I got the stock system image (download from Kia, community knows how to decrypt), a root shell on the running unit (others already figured this out), and the vendor source, I was off to the races.

Given the ancient (3.18.24, from 2015) vendor kernel (for Android Kitkat!), I used LLMs to do minimal mainline porting for the quad Cortex-A53 Telechips TCC803x SoC, which turned out to almost work first try.
With a bit of back and forth (and much USB swapping), display out was achieved and I could feed log messages back into the LLM to help it fix things up.
Note that stock was never reflashed, this is a `kexec` cycle that uses USB data only.
The old Android version is in some ways a blessing in disguise, because older systems are in some ways much easier to bend to your will.

I figured the quickest path to something useful was to get `bootmanager` running, which turned out to be trivial.

{{< image src="media/PXL_20261016_214811840.MP.avif" alt="bootmanager running on the Kia EV6 head unit: a Choose a system screen titled Telechips TCC803x AVN, with a single Tools card (services, partitions, log, power)." >}}

Still, after ~3.5min, it would reboot.
So using LLMs I logged serial transfers from Android and did some decompilation of the MICOM firmware (seems to be some kind of PowerPC VLE chip) and Android apps to see what signals we needed to respond to, and found a hung SoC check that we can respond to to keep from being reset.
At the same time we find signals for things like power draw of climate, battery state, etc. (I still need to map this out properly).

Working:
* Display
* I2C
* USB
* eMMC
* WiFi (and soon, BT)
* Touch
* Serial
* MICOM keepalive + Vehicle data
* re-kexecing back to stock Android

### Does it run DOOM?

If you saw the cover image, you'll know. Of course it does!

{{< figures >}}
{{< image src="media/PXL_20261017_003820837.avif" alt="DOOM running on the 2024 Kia EV6 head unit at night, a first-person corridor with on-screen touch controls (move, turn, run, fire, use, map) on either side." >}}
{{< immich-video id="dd0c904e-5202-4942-9c63-af051766bfa4" slug="2024-kia-ev6-doom" muted="true" ratio="9/16" >}}
{{< /figures >}}

{{< details summary="Vendor Resources" >}}
* [Mobis open source](https://www.mobis.com/en/tech/rnd.do#open): "AVNT STD G50 WIDE R6" for "EV6 (CV1)" (`AVNT_STD_G50_WIDE_R6.zip`, 565 MB)
{{< /details >}}

### My Code
* [Kernel tree](https://github.com/W-Floyd/linux/tree/2024-kia-ev6)


[^nura]: Formerly PostmarketOS