---
title: "Clickbait - The Automatic Fishing Caster"
date: "2020-03-13"
author: "William Floyd"
featured_image: "/images/reduced/clickbait/20191120_224129.jpg"
categories: [
    "Hardware",
    "Engineering",
    "School"
]
tags: [
    "Fishing",
    "3D Printing",
    "SolidWorks"
]
---

This project was completed in the Fall Semester of 2019, for my EPM class at LeTourneau University.

***

The mandate given to us was as follows:

Create a device to launch a fishing weight. It must:

* be capable of selectively launching 20 and 40 feet
* weight less than 5 pounds
* cost less than $100
* be battery powered
* be capable of firing 30 times over the course of 1 hour
* (for extra credit) be wirelessly controlled

I was assigned as an engineering lead, and as it turned out, completed the majority of the physical project.
This was a mutual arrangement, however - I bounced ideas off of team members as needed, and provided information needed for the report writing - they completed the report and peripheral tasks, and helped me as I found tasks that could be assigned.
Being a small project of such singular focus, there was little in the way of division possible on tasks, not without loss of efficiency.

And so it was that we began brainstorming.

***

![Laying the groundwork](/images/reduced/clickbait/20190919_143530.jpg)

The idea was fairly simple - use two smooth rods and a leadscrew to pull a carriage against springs that would then somehow fire the fishing weight.
The choice of this mechanism was, for the most part, due to availability of parts.
I already owned the necessary rods and bearings, and springs were readily available.

![First print](/images/reduced/clickbait/20190919_224711.jpg)

Soon though, we had [some](/images/reduced/clickbait/20190919_213947.jpg) basic 3D printed parts in order - for it was 3D printing that was most accessible to us, and allowed largely unattended manufacturing while classes continued.
Despite this early start of progress, however, the ever present tendency toward procrastination crept in.
The usual array of excuses were made by all, and little actual work was accomplished.

So it was that we inched ever closer to the deadline.
Past the basic idea of our launch mechanism, all else was yet to be decided.
A few calculations were half-heartedly done (kinetic energy, spring constants, etc.), but we all knew we didn't know enough to make any meaningful decisions yet.
We had some very much unfounded fears concerning battery power, and not enough fears concerning torque - we believed we would be using NEMA 17 motors to tension to leadscrew.
Needless to say, this did not turn out to be realistic.
Nor was it realistic for us to budget a baitcasting reel instead of a much cheaper spincaster.

***

![T'was but a Fanta-sea](/images/reduced/clickbait/20191010_152148.jpg)

Eventually, however, some progress was made - progress in something of a wrong direction, but progress nonetheless.
As the shape of our ungainly creation began to emerge, it was clear progress needed to be made quickly.
Once we coupled our stepper motor to the leadscrew and power tested the unit, it was also clear that change was in order.

So a decision was made: a cheap cordless drill would be pilfered for a battery, motor and chuck.
A H-Bridge would need to be bought (I [tried to](/images/reduced/clickbait/20191025_194859.jpg) [make one](/images/reduced/clickbait/20191102_144426.jpg))