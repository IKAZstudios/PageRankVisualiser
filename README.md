# PageRank Visualiser
<img width="1108" height="624" alt="image" src="https://github.com/user-attachments/assets/49ea85e6-614c-472d-a73a-8c606da2df54" />
An interactive visualiser for the PageRank algorithm (invented by Larry Page) made using Godot 4.
Do not expect updates.

# Try in your browser!!
**Click this link:**
https://ikazstudios.github.io/PageRankVisualiser/

# Features
- Interactive link editor
- Panning and zoom
- Visual representation of PageRank score and ordinal ranking
- Allows testing the iterations and the damping factor parameters
- Free and not bloated

# Formula
```math
PR(A) = \frac{1 - d}{N} + d \cdot \frac{\sum_{P \in D} PR(P)}{N} + d \sum_{T_i \in M(A)} \frac{PR(T_i)}{C(T_i)}
```

At iteration $`0`$, every page starts with an equal share of rank: $`PR_0(A) = \frac{1}{N}`$.

### Definitions

- $`PR(A)`$ - The PageRank score of page $`A`$ ($`0 \le PR(A) \le 1`$).
- $`N`$ - The total number of pages in the diagram.
- $`d`$ - The damping factor ($`0 \le d \le 1`$, default $`0.85`$), representing the probability that a visitor clicks an outbound link rather than jumping to a random page.
- $`D`$ - The set of dangling pages (pages with zero outbound links), whose accumulated rank is redistributed evenly across all $`N`$ pages to prevent rank leakage.
- $`M(A)`$ - The collection of incoming links pointing to page $`A`$ (parallel links from the same source page are counted individually).
- $`T_i`$ - A source page that links to page $`A`$.
- $`C(T_i)`$ - The total number of outbound links leaving page $`T_i`$.

# AI Usage
I did use AI to help me create this project and to give me a better understanding of the algorithm. Mostly, it was used to give me a UI base and for debugging my implementation of the algorithm.
Overall, this is not code slop, I made sure that this is still a quality application.
