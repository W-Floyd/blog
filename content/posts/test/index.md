---
title: "Test page"
date: "2024-01-29"
author: "William Floyd"
categories: [
    "Test",
    "Categories"
]
tags: [
    "Test",
    "Tag"
]
render: always
list: never
draft: true
---

foobar

# Icons

{{< icons/icon mdi linkedin >}}
{{< icons/icon vendor=mdi name=book color=red >}}

# Notices

{{< notice note >}}
One note here.
{{< /notice >}}

{{< notice tip >}}
I'm giving a tip about something.
{{< /notice >}}

{{< notice example >}}
This is an example.
{{< /notice >}}

{{< notice question >}}
Is this a question?
{{< /notice >}}

{{< notice info >}}
Notice that this box contain information.
{{< /notice >}}

{{< notice warning >}}
This is the last warning!
{{< /notice >}}

{{< notice error >}}
There is an error in your code.
{{< /notice >}}

# Mermaid

{{<mermaid>}}
sequenceDiagram
    participant Alice
    participant Bob
    Alice->>John: Hello John, how are you?
    loop Healthcheck
        John->>John: Fight against hypochondria
    end
    Note right of John: Rational thoughts <br/>prevail!
    John-->>Alice: Great!
    John->>Bob: How about you?
    Bob-->>John: Jolly good!
{{</mermaid>}}

# Math

$$
y=mx+b
$$

{{< mathjax >}}