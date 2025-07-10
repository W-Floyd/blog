---
title: "Smart Yogurt Maker Part 1"
date: "2022-01-25"
author: "William Floyd"
featured_image: "media/IMG_20220125_113949_cleaned.webp"
categories: [
    "Development",
    "Hardware",
    "Software"
]
tags: [
    "ESPHome",
    "Rice Cooker",
    "Home Assistant",
    "Smart Home",
    "Automation",
    "Yogurt"
]
series: ["Smart Yogurt Maker"]
---

A certain [Rice](/2018/06/smart-rice-cooker) [Cooker](/2018/07/dumb-rice-cooker) has been languishing in a box for the last several years - now it is time to revisit it.
It is a tale of Solder, Software, and Streptococcus thermophilus.

***

# "Last time, on Rice Cooker Adventures"

This story picks up where I left off 3 years ago - the rice cooker has thermistors taped to the bottom of the pot with high temperature fiberglass tape. Specifically, I have 4 of the same thermistor in 2 parallel lines of 2 series resistors, like so.

![Thermistor Diagram][thermistors]

This serves to roughly average the resistances, to account for possible hotspots on the pot, while only taking a single ADC pin.

However, time has not been kind to my memory, and the specific parameters of these thermistors are unknown, so first, it's time to do some testing.

# Side Quest: Thermistor Calibration

I have a thermocouple that I can use to verify the temperature of the pot with, so here is the setup: log the resistance through the thermistor bank at close to room temperature, rolling boil, and a middle temperature (during cooldown). These three sample points may then be used to find the parameters of the thermistor exactly.

From hazy memory (and counting parts in inventory), my suspicion was that I had used a $100k\Omega$ thermistor.
Brand is unknown, but representative datasheets online cite a $\beta$ value of 3950 - let's see how we compare.

## Wait, what does $\boldsymbol{\beta}$ mean?

For a more in depth read, look [here](https://www.qtisensing.com/wp-content/uploads/Beta-vs-Steinhart-Hart.pdf), but in summary early studies proposed that for NTC thermistors, the temperature $T$ could be determined given a measured resistance $R$, coefficient $\beta$ and reference resistance $R_0$ and temperature $T_0$, like so:

$$
\frac {1}{T}=\frac{1}{T_{0}}+{\frac {1}{\beta}} \ln{\frac {R}{R_{0}}}
$$

While this may work for small temperature ranges (approximately $20^\circ \text{C}$ or so), we require a larger range, and so we are instead going to look at the...

## Steinhart-Hart Equation

Briefly summarizing [Wikipedia](https://en.wikipedia.org/wiki/Steinhart%E2%80%93Hart_equation), the equation states:

$$\frac{1}{T}=A+B\cdot\ln\{\left(R\right)}+C(\ln \left(R\right))^{3}$$

Which, when using 3 sample points, results in:

$$
\begin{bmatrix}
    1 & \ln R_1 & \ln^3 R_1 \\\\
    1 & \ln R_2 & \ln^3 R_2 \\\\
    1 & \ln R_3 & \ln^3 R_3
\end{bmatrix}\begin{bmatrix}
    A \\
    B \\
    C
\end{bmatrix} = \begin{bmatrix}
    \frac{1}{T_1} \\\\
    \frac{1}{T_2} \\\\
    \frac{1}{T_3}
\end{bmatrix}
$$

In my case, I found the points of reference using a setup like so:

![Measuring water temperature and thermistor resistance](media/IMG_20220124_174144.webp)

Do note that in order to reach a full boil (and $100^\circ \text{C}$ on the thermocouple), the lid of the rice cooker was attached.

While I could show the calculations, and they wouldn't be difficult, I'll be honest: I used an [online calculator](https://www.thinksrs.com/downloads/programs/therm%20calc/ntccalibrator/ntccalculator.html).

![Calculator results](media/calc.webp)

Using the measurements:

$$
\begin{array}{|l|l|}
\hline \mathbf{R}(\boldsymbol{\Omega}) & \mathbf{T}\left({ }^{\circ} \mathbf{C}\right) \\\\
\hline 81 \mathrm{k} & 33 \\\\
\hline 21.3 \mathrm{k} & 66 \\\\
\hline 6.4 \mathrm{k} & 100 \\\\
\hline
\end{array}
$$

Yielded

$$
\begin{aligned}
A &= 1.032978070 \cdot 10^{-3}\\\\
B &= 1.733021623 \cdot 10^{-4}\\\\
C &= 1.902682261 \cdot 10^{-7}\\\\
\hline
R_{(25^\circ \text{C})} &= 117072.68 \Omega \\\\
\beta_\text{calculated} &= 4202.76 \text{K}
\end{aligned}
$$

As we can see then, the actual $\beta$ value is larger than predicted ($3950\text{K}$ predicted vs. $4203\text{K}$ actual), as is the reference resistance ($100\text{k}\Omega$ predicted vs. $117\text{k}\Omega$ actual).
In fact, neither of these are even in the commonly stated "$\pm 1 \\%$" range.
Good thing we're calibrating, hey?

# "Back to our regularly scheduled programming"

How to use this data then?
Being short on time, I opted to take the easy way out, and use the wonderful [ESPHome](https://esphome.io/), as I already use Home Assistant.
As it turns out, they already have us covered, with a [NTC Sensor component](https://esphome.io/components/sensor/ntc.html) already built in.
This, coupled with a [resistance](https://esphome.io/components/sensor/resistance.html) and [ADC](https://esphome.io/components/sensor/adc.html) sensor allow using a voltage divider to measure the resistance of the thermistor.

You know those calculations and equations we did above?
Unnecessary, all of it. 
ESPHome supports doing Steinhart-Hart calculations itself, and only needs the three sample points.

In the meantime, a Wemos D1 Mini on a breadboard is ready to go (they're cheap and chearful).
I wire it up with a $6.8\text{k}\Omega$ resistor (what I had handy), and away I went.
The circuit looks something like this, where the two trailing wires connect to the thermistor bank:

![Wired breadboard](media/IMG_20220125_114006_cleaned.webp)

To prevent confusion, here is my final working config, then I'll explain.

```yaml
sensor:
  - platform: ntc
    sensor: resistance_sensor
    calibration:
      - 81.0kOhm -> 33°C
      - 21.3kOhm -> 66°C
      - 6.4kOhm -> 100°C
    name: Rice Cooker Temperature
    unit_of_measurement: °C

  - platform: resistance
    id: resistance_sensor
    sensor: source_sensor
    configuration: DOWNSTREAM
    resistor: 6.96kOhm
    reference_voltage: 3.306V
    name: Resistance Sensor

  - platform: adc
    id: source_sensor
    pin: A0
    name: Voltage Sensor
    filters:
      - multiply: 3.2
    update_interval: 1s
```

# Calibrate all the things

## Series Resistor
Easy, measuring mine I found it to be $6.96\text{k}\Omega$, certainly different from the $6.8\text{k}\Omega$ it's meant to be.
Throw that in the config.

## Reference Voltage
This is also easy enough, measure the $3.3\text{V}$ pin off the D1 mini.
Mine came out to be $3.306\text{V}$, respectably close to rated!
That goes in the config too.

## Multiply Filter
As it turns out, the D1 mini has an internal voltage divider to convert the $3.3\text{V}$ of the input voltage down to the $1\text{V}$ the ADC is rated for.
This is nice, as it protects the ADC, but it must be accounted for.
But there's a catch - on my board this wasn't quite right - the voltage read was still slightly wrong.
I could try manually tuning this, but there is an easier way.
Instead, I measured the actual voltage ($3.306\text{V}$), and compared it to the voltage being read.

Say there was no error, then we would say $V_\text{actual}=V_\text{measured}$, and if there is an error of a multiple difference between the two, we can say $V_\text{actual}=m\cdot V_\text{measured}$. Thus, to find this multiplier, we say:

$$
m = \frac{V_\text{actual}}{V_\text{measured}}
$$

Using this method, I find my multiplier to be $3.2$, not $3.3$.

With that, the board is finally reading the correct voltage, the correct resistance, and the correct temperature.

# "You're so controlling!"

Given that I have Home Assistant, automating it becomes easy.

I'm currently using a [Tasmota](https://tasmota.github.io/docs/) flashed smart outlet to control the power to the heating element of the rice cooker (for reference, it pulls up to $400\text{W}$ at full load).
In future, I would like to condense all functionality into a relay controlled directly by the ESP8266, to allow greater safety in case of network issues or even local PID tuning.

I am also using a [PID controller for Home Assistant](https://github.com/soloam/ha-pid-controller).
It seems to work fine, I am just bad at PID tuning, so results may vary depending on hardware, amount of mass in the cooker, ambient temperatures, etc.
That being said, a simple automation to turn the heater on when the PID response goes high and turn off when not high yields acceptable results.

From fiddling with the settings, I currently am using the following parameters:

$$
\begin{aligned}
P &= 60 \\\\
I &= 5.6 \\\\
D &= 6.7 \\\\
\end{aligned}
$$

Further tuning is required, but this held well overnight - mostly...

![First overnight test](media/log.webp)

I did change the set point from $105^\circ\text{F}$ to $107^\circ\text{F}$ halfway through, as well as tweaked some of the PID tuning.
The concerning spike at 9:00 is marked by a momentary loss of connection with the ESP board - my automation failed to account for a loss of connection and so allowed the heat to continue rising.
Thankfully, this was a short-lived event, but it is concerning nonetheless, and will require testing of my automation to prove that power loss tends towards a "safer" outcome.
Do note that "safer" means no dead yogurt culture - the safety features of the rice cooker remain unchanged and functional.

# The proof is in the... yogurt?

So how did it do?
I am notoriously _not_ picky when it comes to food, but I think it turned out great!
Filling the rice cooker about halfway with whole milk, I heated it to $180^\circ \text{F}$ for a few minutes (I read I ought to go for longer...), cooled to about $110^\circ \text{F}$, then added a liberal few spoonfuls (think 1/5 volume of milk) of plain Dannon yogurt.
I let it proof in the rice cooker for 7.5 hours, with the lid sealed.

![First batch, still warm](media/IMG_20220125_105918.webp)

I put the whole rice cooker in the fridge to cool, with the lid sealed.
Trying it later that same evening, I quite enjoyed it.
I'll start my next batch from this one, and hopefully it'll be even better.

![Spoonful of the good stuff](media/IMG_20220125_180035.webp)

# "Next time, on Rice Cooker Adventures"

Now that I have a temperature controllable rice-cooker, and the ability to remotely start, stop, and modify set points, I may try other foods.
For now, I need to:

* solder a perfboard version of the circuit
* add a relay to control the cooker directly
* ensure the outlet will turn off if the ESP8266 loses connection
* PID tune the setup for the most common scenario (steady $107^\circ \text{F}$ with the lid shut)

First though, I'm gonna go eat some fresh yogurt...

[thermistors]: media/circuit.svg "Thermistor Diagram]"

{{< mathjax >}}
