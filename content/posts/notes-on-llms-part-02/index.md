---
title: "Notes on LLMs - Part 2"
date: "2026-11-06"
author: "William Floyd"
toc: true
categories: [
    "Software",
    "Development",
    "LLM"
]
tags: [
    "LLM"
]
---

Some notes on how I've found the most use out of LLMs.
The specifics of the tools honestly change so fast, I won't get into the details too much, but here's a look at some themes I've found.
Note that some of these principles are likely helpful even without LLMs, but are especially important with them.

# TL;DR

* Know your actual goal, and when "good enough" is all it needs.
* Get *something* working first, and make the feedback loop as fast as you can so each iteration runs on its own.
* Turn anything you repeat into a script: scripts are inspectable, reusable, and outlast cheap tokens.
* Do homework on prior art and primary sources before running an LLM on a large or opaque task.
* Reshape a task into a common, well-trodden form, so the novel work is small and contained.
* Get both ends working, then use the LLM to fill in the step between them.
* With profiling and low stakes, LLMs are good for trying out speedups.
* LLMs are a hammer; not everything is a nail.
* Pin down how you'll measure features, performance and correctness, early.

# Keep the "Main Thing" the Main Thing

Know what you're looking to *achieve* when you set out on a project.

This depends heavily on the criticality of what's being done, but know when "it ain't stupid if it works" applies.
For example, with my work in [Part 1]({{< relref "notes-on-llms-part-01" >}}) getting a phone and then a car's head unit running Linux, the goal was just that - getting Linux running.

Non-goals included:
* sharing every random script used
* documenting every step
* doing it "right"
* mainlining modifications

This sounds terrible, perhaps, but bear with me.
The *goal* is to get mainline-ish Linux running on these devices.
No-one else has done this, to my knowledge - not because it's impossible or even hard for the right person (it *is* hard for me), but because I happen to be the *first* attempting it.

> I assure you I had rather be the first man here than the second man in Rome.
>
> — Julius Caesar ([Wikiquote](https://en.wikiquote.org/wiki/Julius_Caesar#:~:text=I%20assure%20you%20I%20had%20rather%20be%20the%20first%20man%20here%20than%20the%20second%20man%20in%20Rome%2E))

Put another way, if you can't be the best, at least be first.

This is not, however, meant to disparage taking the time to do good work.
On the contrary I value good work very much, and hope to do as much of it as I can.
But sometimes what I need is "good enough" work to achieve a goal.

LLMs are a tool used to achieve this goal for me.
Were my goal to simply write lines of code, there are myriad ways of fulfilling that goal, but rest assured I would not achieve the goal of booting mainline-ish Linux as quickly as I did with LLMs.

# Make It Work, Make It Right, Make It Fast

> Make it work, make it right, make it fast.
>
> — attributed to Kent Beck ([c2 wiki](https://wiki.c2.com/?MakeItWorkMakeItRightMakeItFast))

LLMs are fairly good at the first (and sometimes the third, see more [here](#i-am-speed)) part of this phrase.
Run an LLM in a loop against a clear goal, and you can often brute-force *something* working, however hacky it might be.

Again, this may sound terrible, but I find it much easier to have a working end-point to work backwards from, than to do everything "right" from scratch.
This is especially true of things like embedded Linux bringup, where simply getting a booting system with remote access is so much more helpful than any amount of "doing it right" blindly could ever yield.
Once you get it working, it's much easier to get it working right.

When using LLMs it is especially important to close the feedback loop as quickly as possible, so the tool can iterate automatically.
For example, in [Part 1]({{< relref "notes-on-llms-part-01#2024-kia-ev6-head-unit" >}}), I ensured there was a script that automated as much of the USB-to-boot cycle as possible.
See also [xkcd 1205, "Is It Worth the Time?"](https://xkcd.com/1205/).
Which leads me to my next point...

# Produce Durable Goods

Make scripts for everything you do more than twice.
LLMs have a tendency to produce inscrutable one-liners for routine tasks, so I find it helpful to step in to ensure durable scripts are made instead, especially if I know I'm going to do the task often.
These scripts don't need to be especially *good*, but the fact they're at least written down in one place and inspectable is critical.
They can be committed, reviewed, and tweaked as time goes on.
These scripts, once sufficiently worked through, serve to reduce the cognitive load on humans and context usage of LLMs, which then simply run a small command to do a rote task instead of reinventing the wheel.

These cobbled together scripts may be a rat's nest as a whole, but if they work, they inch you closer to your goal.
Once that goal is achieved, it is at least repeatable.
And once it's repeatable, it can be made more "right" (see [above](#make-it-work-make-it-right-make-it-fast)).

These "durable goods" will outlive the cheap LLM tokens.
Once the true cost of operating LLMs at a loss funded by gobs of VC money is brought to bear, we will still have these outputs.
Ultimately, the less you depend on LLMs being cheap, the better.
And if they do remain cheap (or get cheaper), then all the better I guess...

# Prior Art and Primary Sources

It is useful to survey prior art and primary sources before just setting LLMs running on a given task.
For example, in [Part 1]({{< relref "notes-on-llms-part-01#2024-kia-ev6-head-unit" >}}), tracking down the somewhat obscure Mobis open source portal got me a vendor kernel tree.
Perhaps an LLM would have found it eventually (and I'd still have had to download it myself), but by doing at least a modicum of up-front homework, a lot of time can be saved.
In this instance, the LLMs could then derive vendor changes for the SoC in question and port them to a new mainline branch, something that would take me far, *far* longer.

# Intermediate Formats and Task Normalization

Massage your tasks into something that is *like* something that is already commonly done.
Once a common intermediate format is achieved, you will have a much easier time of making progress.
This is especially true when reverse engineering, but may still prove useful in other projects.
For example, converting an obtuse API spec from a 500-page PDF into an OpenAPI spec that is 95% complete with the last 5% captured in prose descriptions yielded better results with LLMs than just using the PDF directly.

I might call this "task normalization": breaking a project down into the most idiomatic steps such that LLMs need to do the least novel work, or at least that the novel work is well bounded and concentrated into one domain.

# Fill in the Blank

A theme alluded to above is the idea of filling in the blank - you get the bare minimum working, and flesh out the in-between later.
This is not always appropriate, but when it is, it allows LLMs to serve as a powerful tool to get some momentum on a goal.
The "blank" need not be a full project, it may be some increment - so as usual, it does well to at least think through what is required to solve a particular problem.

Take, for example, camera support for the [Moto G Play in Part 1]({{< relref "notes-on-llms-part-01#motorola-moto-g-play-2024---fogona" >}}).
I had `libcamera`, stock camera calibration files, and a working sensor.
The "blank" I had to fill was converting these stock calibration files into something that `libcamera` could at least begin to use for better camera support.
The goal (in [keeping the "main thing" the main thing](#keep-the-main-thing-the-main-thing)) was a working camera that at least looked halfway decent.
The useful increment to get there was to make [a tool]({{< relref "notes-on-llms-part-01#go-chromatix2libcamera" >}}) to read stock calibration files and convert them into something that `libcamera` could read, and make `libcamera` modifications to support them.
That way I could go from stock calibration to a working camera without redistributing stock files.

This camera case is a good low-stakes example - getting it wrong is both immediately evident and harmless: it's simply a "bad" picture, no harm done.
Thus, doing it "right" isn't terribly important - if it *looks* good, it *is* by nature an acceptable result.
It also lent itself well to an iterative approach, wherein I used LLMs to trawl GitHub for relevant source code (i.e., the vendor-distributed camera stack from Qualcomm), read calibration files, approximate that same feature (if new) in `libcamera` and then test on a live device.
The tight development loop meant I could use LLMs to work against both captured RAW images and live camera feed and start to zero in on an acceptable result.
For more subjective/temporal failures that required human review (unstable brightness, focus breathing) it was still easy to use LLMs to try things, with occasional nudges in the right direction.

# I Am Speed

Once you've done the "make it work", you *should* do the "make it right", but if it's low stakes and you've instead done the "make it right (enough)", then why not go ahead and do the "make it fast"?
LLMs, when combined with good old fashioned profiling, are great for testing things out.

The key here is to scope the problem: find a user experience that is slow, make sure it can be profiled (in itself something that LLMs could help set up), then you can dig in.
It's a low stakes way to try things, and see some of what's *possible* for a given problem.
For example, take [this PR to flacoutcpp](https://github.com/Snesnopic/flacoutcpp/pull/1), a tool that searches for the smallest FLAC encoding of a file.
Profiling put 93% of its exhaustive mode's runtime in two loops, and reworking just those made it about 3x faster with byte-identical output.
It also added a search level about 90x faster than exhaustive mode, for about a quarter of a percent in file size.
Lossless audio kept the stakes low: every change could be checked by decoding and comparing against the source.

# Hammer Meets Nail

> I suppose it is tempting, if the only tool you have is a hammer, to treat everything as if it were a nail.
>
> — Abraham Maslow, *The Psychology of Science* (1966) ([Wikipedia](https://en.wikipedia.org/wiki/Law_of_the_instrument#Abraham_Maslow))

LLMs are a hammer; learn to tell what is actually a nail.
This, depending on experience and personality, will likely be difficult (it is for me).
As LLMs get better, it will become increasingly difficult.

I have no solution for this, and I am not a good example of doing this anywhere close to right.
For now, I'm seeing a lot of nails.

# Treasured Measurements

> When you can measure what you are speaking about, and express it in numbers, you know something about it; but when you cannot measure it, when you cannot express it in numbers, your knowledge is of a meagre and unsatisfactory kind.
>
> — Lord Kelvin, "Electrical Units of Measurement" (1883) ([Wikiquote](https://en.wikiquote.org/wiki/William_Thomson))

Put another way:

> You can't treasure what you can't measure.

You must be able to measure several things for a successful project, some of which include:
* Features
* Performance
* Correctness

Nail these down as soon as you can, and you'll have more success.
Acceptance criteria exist for a reason.
At the same time, if you learn something along the way and the goalposts *must* shift, so be it - but be discerning when doing so; LLMs often make it feel like I have more bandwidth than I really do.

***

Still a mixed bag, as in [Part 1]({{< relref "notes-on-llms-part-01" >}}), but here we are anyway.

Part 3 someday, likely once I get a bench setup for a spare EV6 head unit (working on getting 64bit boot).