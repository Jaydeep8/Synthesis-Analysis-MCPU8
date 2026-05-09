# Synthesis Analysis MCPU8_1 (8-bit Microprogrammed CPU)

> I already knew how to run the RTL-to-GDSII flow.  
> This week I learned what is actually happening inside it.

**Author:** Jaydeep Panchal | [LinkedIn](https://www.linkedin.com/in/jaydeep-panchal-0j28p88/) | [GitHub](https://github.com/Jaydeep8)  
**Tool:** Cadence Encounter RTL Compiter v12.10 | **Library:** slow_vdd1v0 | **PVT:** 0.9V, 125°C (worst case)  
**Previous work:** [RTL-to-GDSII Flow MCPU8_1](https://github.com/Jaydeep8/RTL2GDSII-Flow-Cadence)

---

## Why I Did This

When I completed the RTL-to-GDSII flow earlier, I ran synthesis, saw a passing timing report, and moved on. I knew the slack was positive. I did not know what that actually meant like which gates were slow, why they were slow, what the tool did to make them faster, or what would happen if I pushed harder.

So I ran the same design 10 times, tightening the clock constraint each time, and read every timing report carefully. I tracked what changed, what surprised me, and what I understood after each run that I did not understand before.

This document is that learning organised by phase, with the actual report data and the reasoning behind every observation.

---

## The Design in One Paragraph

MCPU8_1 is an 8-bit microprogrammed CPU from OpenCores. It executes four instructions LDA, ADD, SUB, OUT through a microprogrammed control unit. The micro-program counter (UUT6) steps through a control ROM (UUT7) which generates a 17bit control word every cycle. That control word is decoded and distributed to every functional unit accumulator, ALU, registers simultaneously. The ALU (UUT12) feeds its result back into the accumulator (UUT9), which feeds back into the ALU. These two paths the **control distribution path** and the **accumulator feedback path**  are what this entire analysis is about.

---

## Complete Results at a Glance

| Constraint | Frequency | WNS | Status | Cells | Area | Power (µW) | FF Type |
|-----------|-----------|-----|--------|-------|------|------------|---------|
| 10ns | 100 MHz | +7999ps | ✅ | 281 | 697 | 24.25 | SDFFQX1 |
| 5ns | 200 MHz | +3008ps | ✅ | 280 | 698 | 48.99 | SDFFQX1 |
| 2ns | 500 MHz | +352ps | ✅ | 315 | 742 | 117.19 | DFFRHQX1 |
| 1.6ns | 625 MHz | +10ps | ⚠️ | 352 | 794 | 154.11 | DFFRX1 |
| 1.5ns | 667 MHz | +8ps | ⚠️ | 354 | 806 | 159.01 | DFFRX1 |
| 1.4ns | 714 MHz | +2ps | ⚠️ | 362 | 816 | 176.58 | DFFRHQX2 |
| 1.3ns | 769 MHz | +1ps | ⚠️ | 371 | 834 | 187.45 | DFFRHQX1 |
| 1.2ns | 833 MHz | +3ps | ⚠️ | 400 | 869 | 209.10 | DFFRHQX1 |
| 1.1ns medium | 909 MHz | **-46ps** | ❌ | 426 | 912 | 237.82 | MDFFHQX2 |
| 1.1ns high | 909 MHz | **0ps** | ✅ | 415 | 876 | 248.65 | SDFFRHQX1 |

> **Maximum frequency with robust margin: 769 MHz (1.3ns)**  
> **Absolute limit: 909 MHz (1.1ns) 0ps slack, no manufacturing margin**

---

## The Three Phases

The 10 runs split naturally into three distinct phases based on how the synthesizer behaved:

```
Phase 1 - RELAXED       Phase 2 - OPTIMIZATION      Phase 3 - LIMIT
   10ns, 5ns              2ns → 1.3ns, 1.2ns           1.1ns

Tool is idle.           Tool fights harder             Tool has nothing
Minimum cells.          with every run.                left to try.
No pressure.            New techniques appear.         Violation appears.
                                                       High effort recovers.
```

---

---

# PHASE 1 RELAXED (10ns and 5ns)

---

## Run 1 10ns (100 MHz)

<img width="1746" height="2853" alt="10ns timing rpt" src="https://github.com/user-attachments/assets/a09c012f-ae66-479f-89e4-804978c16816" />

> *Timing report at 10ns path uses only 2001ps out of 10000ps budget*

### What the report showed

```
Startpoint: UUT10/B_OUT_r_reg[0]/CK   (B register)
Endpoint:   UUT9/ACC_OUT_r_reg[8]/D   (Accumulator)
FF type:    SDFFQX1

Path delay: 2001ps
Clock budget: 10000ps
Slack: +7999ps
```

The path needed 2001ps. The clock allowed 10000ps. The tool had 7999ps of slack nearly 4× more time than the path actually needed.

### What I learned: What slack actually means

Before this I thought of slack as a pass/fail number. After reading this report I understood what it physically represents:

```
Clock period:    |←————————— 10000ps ————————————→|
Path delay:      |←— 2001ps —→|
                              ↑
                         data arrives here
                                            ↑
                                     clock captures here

Slack = 10000<img width="1744" height="2257" alt="1 1ns timing rpt " src="https://github.com/user-attachments/assets/43fda098-adfb-4bed-896c-8dbe38046d54" />2001 = 7999ps of unused time
```

The data arrives at the endpoint with 7999ps to spare before the clock edge captures it. The larger this gap, the more comfortable the design. The moment it goes negative the data arrives after the clock edge the flip-flop captures the wrong value.

### What I learned: The tool was not trying

At 10ns the synthesizer chose **SDFFQX1**  a scan flip-flop. Scan flip-flops have an extra multiplexer input used for manufacturing test (scan chains). They are slightly larger and slower than regular DFFs, but the tool chose them because it had no timing pressure. When you give the tool 10× more time than it needs, it optimises for area and testability, not speed.
```
Here’s the breakdown of the name: SDFFQX1
S → Scan
DFF → D-type Flip-Flop
Q → Normal output pin Q
X1 → Drive strength 1 (lowest drive version)
```
This was my first real understanding that the synthesizer is making active decisions not just translating RTL into gates, but choosing between options based on what the constraints demand.

### What I learned: How to read a timing report path

```
Pin              Type      Fanout  Load   Slew   Delay  Arrival
                                   (fF)   (ps)   (ps)    (ps)

FF_reg[0]/Q      SDFFQX1   5       1.0    33     +180    180 R
g1653/Y          AND2XL    3       0.8    41     +124    304 R
g1622/Y          AOI22X1   3       0.8    123    +124    429 F
...
```

**What each column actually means:**
- **Fanout**-how many gates this cell's output connects to. More connections = more capacitance to charge = slower
- **Load (fF)**-total capacitance the cell must drive. Higher load = slower switching
- **Slew (ps)**-how slowly the signal transitions from 0→1 or 1→0. Slow slew into a gate causes slow output from that gate
- **Delay (ps)**-time this specific cell took
- **Arrival (ps)**-total elapsed time from clock edge to this point
- **R / F**-Rising or Falling transition at this gate output

The R/F alternation is normal-every inverting gate (AOI, OAI, INV, NAND, NOR) flips the transition direction.

---

## Run 2-5ns (200 MHz)

<img width="1747" height="2842" alt="5ns timing rpt" src="https://github.com/user-attachments/assets/75fe1911-a90a-4c0c-aadb-e5c910295369" />

> *Timing report at 5ns same critical path, same FF type, area identical*

### What the report showed

```
Startpoint: UUT10/B_OUT_r_reg[0]/CK   (same as 10ns)
Endpoint:   UUT9/ACC_OUT_r_reg[8]/D   (same as 10ns)
FF type:    SDFFQX1                   (unchanged)

Path delay: ~2001ps
Clock budget: 5000ps
Slack: +3008ps

Cells: 280  (was 281)
Area:  698   (was 697)
Power: 48.99µW  (was 24.25µW)
```

### What I learned: Power doubles even when nothing else changes

This was the most surprising result of the first two runs. Area stayed completely flat 697 to 698, essentially unchanged. The same cells. The same logic. But power doubled from 24.25µW to 48.99µW.

Why? Dynamic power formula:

```
P_dynamic = C × V² × f × activity

Where:
C = capacitance (unchanged same cells)
V = supply voltage (unchanged same library)
f = frequency (doubled 100MHz → 200MHz)
activity = switching probability (unchanged)

Result: power doubles when frequency doubles
```

The tool synthesized the exact same netlist for a faster clock. But at twice the frequency, every gate switches twice as many times per second, drawing twice the current from the supply. **You pay for speed in power, not in area at least at first.**

This was my first real understanding of why power is the hard constraint in modern chip design.

---

### Phase 1 Summary What the Tool Was Doing

```
10ns and 5ns: The tool was essentially idle.

Technique used:    Minimum-size XL cells everywhere
FF choice:         SDFFQX1 (scan FF chosen for testability, not speed)  
Buffers inserted:  9 (minimum)
Optimization:      None 7999ps and 3008ps of slack needs no help

Key insight: When you give the tool far more time than it needs,
it optimises for area and testability. Speed costs nothing here
because no speed is required.
```

---

---

# PHASE 2 OPTIMIZATION (2ns to 1.2ns)

---

## Run 3 2ns (500 MHz)

<img width="1745" height="2594" alt="2ns timing rpt" src="https://github.com/user-attachments/assets/7e1e45a1-4580-47a1-86e8-466b998e8076" />

> *Timing report at 2ns new critical path through counter, fanout=12 bottleneck identified*

### What the report showed

```
Startpoint: UUT6/COUNT_OUT_r_reg[0]/CK   ← NEW counter, not B register
Endpoint:   UUT9/ACC_OUT_r_reg[8]/D
FF type:    DFFRHQX1                      ← NEW no longer scan FF

Worst gate:
g493/Y   NOR2X1   fanout=12   load=4.0fF   delay=189ps   ← PROBLEM

Slack: +352ps
Cells: 315  (+35 from 5ns)
Area:  742  (+44 from 5ns)
Power: 117.19µW  (2.4× jump from 5ns)
```

### What I learned: The critical path changed completely

At 5ns the worst path started in the B register (UUT10). At 2ns it starts in the micro-program counter (UUT6). These are completely different parts of the design.

Why did it change? Because the 5ns run had already optimized the B register path when the tool synthesized for 5ns, it made that path fast enough that it was no longer the bottleneck at 2ns. A different, previously hidden path emerged as the new worst case.

This is the first time I saw what would later become the central theme of this analysis: **tightening the constraint reveals paths that were always there but never mattered before.**

### What I learned: The flip-flop changed and why

At 10ns and 5ns the tool used **SDFFQX1**  a scan flip-flop with standard drive strength. At 2ns it switched to **DFFRHQX1**  a regular D flip-flop with Reset and High-drive output.

Three changes in one cell name:
- **Dropped scan (S→D):** Scan FFs have a test multiplexer that adds delay. Removed it for speed.
- **Added reset (R):** Matches the design's reset requirement more efficiently.
- **High-drive (HQ):** The HQ suffix means this cell can drive more load without slowing down.

**This was my first understanding that the tool does not just size gates it changes the fundamental cell type based on what the downstream load demands.**

### What I learned: The fanout problem the most important concept in this analysis

The gate `g493/NOR2X1` drove 12 other gates with a total load of 4.0fF and a delay of 189ps. This was the single most expensive gate on the entire critical path.

Why is high fanout so damaging?


WHAT IS HAPPENING ELECTRICALLY:

<img width="1440" height="680" alt="image" src="https://github.com/user-attachments/assets/8f17a2fc-ce14-4fdd-9fb9-a507337326a0" />

```
g493 must charge ALL 12 cells before its output reaches a valid logic level. It has limited drive current.
The more load, the longer it takes. Result: 189ps delay.

ANALOGY: One small water tap filling 12 buckets simultaneously.
Each bucket fills very slowly because the pressure is split 12 ways.
```

The fix is **buffer insertion** adding intermediate driver cells to share the load:


<img width="1440" height="800" alt="image" src="https://github.com/user-attachments/assets/5af08f78-275d-4040-9ae8-d6bb70524a57" />


At 352ps of slack the tool did not need to insert buffers yet. But now I knew exactly where the problem was and what the fix would look like when timing got tighter.

### What I learned: Area jumped because the tool needed bigger cells

Cells jumped from 280 to 315 (+12.5%) and area from 698 to 742 (+6.3%). This was the first significant increase. Why?

At 5ns the tool used XL (extra-low drive strength) cells everywhere the smallest possible cells. At 2ns it needed cells that switch faster, which means cells with larger transistors. Larger transistors = more area. The tool was making a conscious tradeoff: pay more silicon area to get lower delay.

---

## Run 4 1.6ns (625 MHz)

<img width="1744" height="2265" alt="1 6ns timing rpt" src="https://github.com/user-attachments/assets/4dad250c-53f6-4fd4-a381-0565928ee64b" />
  
> *Timing report at 1.6ns 10ps slack, slew degradation cascade appears*

### What the report showed

```
Startpoint: UUT6/COUNT_OUT_r_reg[0]/CK
Endpoint:   UUT9/ACC_OUT_r_reg[7]/D
FF type:    DFFRX1   ← upgraded again

Critical section:
COUNT_OUT_r_reg[0]/Q  DFFRX1    fanout=14  load=5.0fF  delay=321ps
g677/Y                NAND2X1   fanout=2               delay=127ps
g649/Y                NOR2X1    fanout=12  load=3.2fF  delay=152ps
g15561/Y              INVX1     fanout=10  load=3.9fF  delay=168ps  ← worst
g15546/Y              NOR2X1    fanout=8               delay=160ps
g15439/Y              AOI33XL   fanout=1   slew=256ps  delay=211ps  ← cascade

Slack: +10ps
```

### What I learned: Slew degradation cascading

The AOI33XL gate showed 211ps delay despite fanout=1 and tiny load=0.4fF. Normally a fanout=1 gate with tiny load should be fast. But look at the slew: **256ps**. That is extremely slow.

Why? The previous three gates all had high fanout (12, 10, 8). High fanout means the driving gate struggles to push the output voltage quickly the signal transition is sluggish. That sluggish signal arrives at AOI33XL as a slow input. A slow input to a complex gate (AOI33 implements 3-input AND followed by 3-input OR with inversion) causes a slow output. The problem from three gates earlier was still causing damage two gates downstream.

```
HIGH FANOUT GATES              DOWNSTREAM EFFECT
───────────────────────────────────────────────────────────
NOR2X1  (fanout=12) ──► slow output ──► slow input to INVX1
INVX1   (fanout=10) ──► slow output ──► slow input to NOR2X1  
NOR2X1  (fanout=8)  ──► slow output ──► slow input to AOI33XL
                                         slew=256ps → delay=211ps
                                         ↑
                              The fanout problem 3 gates back
                              is still costing time here
```

**This is called slew degradation cascading.** Fixing the fanout problem at the source would have cleaned up the slew at AOI33XL without touching it at all.

### What I learned: 10ps slack is not safe

Ten picoseconds looks like a pass. But real silicon has variation manufacturing process spread, temperature fluctuations, voltage droop during operation. Standard sign-off practice requires at least 50-100ps of margin to account for these effects. At 10ps, any real-world variation would push this into violation.

**A timing report showing 10ps slack in industry would be sent back for more optimization, not signed off.**

---

## Run 5 1.5ns (667 MHz)

<img width="1746" height="2530" alt="1 5ns timing rpt" src="https://github.com/user-attachments/assets/a6cca4c9-0798-4c03-b19b-20c3704a4379" />
  
> *Timing report at 1.5ns 8ps slack, cell duplication appears for first time*

### What the report showed

```
FF type: DFFRX1   (same as 1.6ns tool tried but could not do better)

Startpoint FF: fanout=15, load=5.4fF, delay=325ps  ← fanout grew
Slack: +8ps

New observations in gates.rpt:
- Cell duplication: _dup suffix appeared on gate names
```

### What I learned: Cell duplication

For the first time I saw gate names with `_dup` suffix for example `g23618_dup23699`. The `_dup` means the tool created a **physical copy** of that gate and split the fanout load between the original and the duplicate.

```
BEFORE DUPLICATION:
g23618/Y ──────────────────► 16 downstream gates
fanout=16, load=5.2fF, delay=160ps

AFTER DUPLICATION:
g23618/Y     ──► gates 1-8   (fanout=8, load=2.6fF, delay≈100ps)
g23618_dup/Y ──► gates 9-16  (fanout=8, load=2.6fF, delay≈100ps)

Same logic function. Same outputs. Half the load per driver.
```

The tool is implementing the same idea as buffer insertion but without adding a new cell type it duplicates existing logic and splits the connections. Area increases slightly (one extra cell) but both copies now see half the load and switch in roughly half the time.

**I had read about cell duplication in textbooks. Seeing `_dup` appear automatically in a real report made it concrete in a way the textbook never did.**

---

## Run 6 1.4ns (714 MHz)

<img width="1743" height="2439" alt="1 4ns timing rpt" src="https://github.com/user-attachments/assets/61f9df8f-5308-472e-8435-aff2b7e9d747" />

> *Timing report at 1.4ns 2ps slack, DFFRHQX2 chosen, logic completely remapped*

### What the report showed

```
FF type: DFFRHQX2   ← jumped to X2 (double drive strength)

FF delay dropped: 325ps → 283ps  (saved 42ps just from FF change)

First gate after FF:
1.5ns: g877/Y   NAND2X1   fanout=3   delay=152ps
1.4ns: g1379/Y  INVX2     fanout=5   delay=63ps   ← completely different

Slack: +2ps
```

### What I learned: The tool changed the logic itself, not just the cells

At 1.5ns the first logic gate after the flip-flop was a NAND2X1 with 152ps delay. At 1.4ns it is an INVX2 with 63ps delay. These are not equivalent gates NAND and INV have different logic functions.

The tool did not just swap a slow cell for a fast cell of the same type. It **restructured the Boolean logic** found a different implementation of the same function that uses fewer or faster gates. This is called logic remapping.

```
SAME FUNCTION, DIFFERENT IMPLEMENTATION:

1.5ns approach:  NAND2X1 (delay=152ps) → NOR2X2 → ... → endpoint
1.4ns approach:  INVX2   (delay=63ps)  → OR2X1  → ... → endpoint

The tool explored the entire solution space and found a path
through different gates that arrives at the same result faster.
```

**This is why synthesis takes compute time.** The tool is not mechanically translating RTL to gates it is searching through a huge space of equivalent implementations to find the one that best fits your constraints.

---

## Run 7 1.3ns (769 MHz)

<img width="1748" height="2356" alt="1 3ns timing rpt " src="https://github.com/user-attachments/assets/eb2768c3-696d-45af-8d07-aca730411c94" />
  
> *Timing report at 1.3ns 1ps slack, clock-grade cells appear in data path*

### What the report showed

```
FF type: DFFRHQX1   (stepped back from X2 tool found better combination)

New cell types in timing path:
g23637/Y   CLKAND2X6   fanout=10   delay=122ps   ← CLOCK CELL
g23618_dup23699/Y   CLKAND2X2   fanout=8    delay=119ps   ← CLOCK CELL + DUP

Slack: +1ps
```

### What I learned: The tool raided the clock cell library

**CLK prefix** on a cell name means it is a clock-network-grade cell designed for distributing clock signals to thousands of flip-flops with minimal skew. These cells have the strongest drive strength and fastest switching characteristics in the entire library.

They are not supposed to be in data paths. But the tool used them anyway and it is valid.

```
WHY CLK CELLS ARE FASTER:
Clock cells are designed to drive enormous fanout (thousands of FFs)
with guaranteed fast transitions. They have:
- Very low output resistance
- High drive current
- Optimised layout for fast switching

When the tool runs out of fast DATA cells, it borrows CLK cells.
The logic function is identical. Only the drive strength differs.
```

Also notice: `g23618_dup23699` both duplication AND a clock cell on the same gate. The tool applied two optimizations simultaneously to the same node.

At +1ps slack the design is essentially at its limit. Any further tightening would require architectural changes, not just cell substitution.

---

## Run 8 1.2ns (833 MHz)

<img width="1742" height="2521" alt="1 2ns timing rpt " src="https://github.com/user-attachments/assets/e879bccd-d547-4675-85ee-1e1694eefacf" />

> *Timing report at 1.2ns 3ps slack, fopt buffers and NOR2X4 appear*

### What the report showed

```
FF type: DFFRHQX1

New observations:
fopt/Y      INVX3   fanout=6   delay=59ps    ← auto-inserted buffer (INVX3!)
fopt26238/Y INVX1   fanout=1   delay=64ps    ← second auto-inserted buffer
g26183/Y    NOR2X4  fanout=4   delay=67ps    ← quad drive strength

Slack: +3ps
```

### What I learned: fopt means the tool inserted a buffer automatically

`fopt` prefix stands for **feed-through optimization**. These are cells the synthesizer inserted by itself they were not in the original RTL, not manually added, not placed by any explicit command. The tool identified a high-fanout node, decided it needed a buffer, and added one.

More interesting: it chose **INVX3** a triple drive strength inverter as the buffer. Standard buffers are BUF cells. But an inverter followed by another inverter produces the same logic (double inversion = non-inverting). The tool picked INVX3 because it had better delay characteristics for this specific load than a BUFX3 would have.

Also notable: **NOR2X4** quad drive strength. At 10ns the tool used NOR2X1. Now it needs NOR2X4 to meet timing. The same logical function, implemented with a transistor that is four times wider, consuming four times the area and power per cell. This is where the area and power increases accumulate.

---

### Phase 2 Summary The Synthesizer's Bag of Tricks

By the end of Phase 2, the tool had used every technique available:

| Technique | First seen | What it does | How to spot it in report |
|-----------|-----------|--------------|--------------------------|
| Cell upsizing | 2ns | X1 → X2 → X4 → X6 for lower delay | Cell name suffix changes |
| FF type substitution | 2ns | Changes FF variant for speed vs drive | Different FF prefix/suffix |
| Logic remapping | 1.4ns | Restructures Boolean logic for fewer levels | Gate type changes on same net |
| fopt buffer insertion | 1.2ns | Auto-inserts buffers at high-fanout nodes | `fopt` prefix in cell name |
| Slew repair | 1.5ns | Upsizes gate after slow-slew predecessor | Slew number improves |
| Clock cell borrowing | 1.3ns | Uses CLK-grade cells in data paths | `CLK` prefix in cell name |
| Cell duplication | 1.5ns | Copies gate to split fanout load | `_dup` suffix in cell name |

**Area and power across Phase 2:**

```
Constraint:    2ns    1.6ns   1.5ns   1.4ns   1.3ns   1.2ns
Cells:         315    352     354     362     371     400
Area:          742    794     806     816     834     869
Power (µW):    117    154     159     177     187     209

Area grew 17% (742→869). Power grew 79% (117→209µW).
Power grows much faster than area because bigger cells
switch harder AND frequency is increasing simultaneously.
```

---

---

# PHASE 3 LIMIT (1.1ns)

---

## Run 9 1.1ns Medium Effort (909 MHz)

<img width="1744" height="2257" alt="1 1ns timing rpt " src="https://github.com/user-attachments/assets/e973351c-079e-4c65-93d1-e0bade82db93" />

> *Timing report at 1.1ns medium effort  first violation, accumulator becomes critical path*

### What the report showed

```
Startpoint: UUT9/ACC_OUT_r_reg[3]/CK   ← ACCUMULATOR completely new
Endpoint:   UUT9/ACC_OUT_r_reg[6]/D0   ← ACCUMULATOR

FF type: MDFFHQX2   ← multi-drive FF, never seen before

Critical path:
ACC_OUT_r_reg[3]/Q  MDFFHQX2   fanout=6    delay=216ps
g23196/Y            OAI2BB1X2  load=1.6fF  slew=51ps   delay=167ps ← source
g23195/Y            OAI21X4    fanout=5    delay=93ps
...
Total arrival: 1146ps
Clock budget:  1100ps
Slack: -46ps   ❌ VIOLATION
```

### What I learned: The whack-a-mole problem

For every run from 2ns to 1.2ns, the critical path started in the micro-program counter (UUT6) and traveled through the control ROM (UUT7) into the ALU (UUT12). At 1.1ns, that path was no longer the worst path.

**The counter→ALU path had been so thoroughly optimized clock cells, duplication, fopt buffers, X4/X6 cells that the tool could not improve it further. But in doing so, it neglected a path it never needed to optimize before: the accumulator internal feedback loop.**

```
THE WHACK-A-MOLE PROBLEM:

Run 2ns:    Fix counter→ALU path   ─► counter→ALU path improves
Run 1.6ns:  Fix counter→ALU path   ─► counter→ALU path improves
Run 1.5ns:  Fix counter→ALU path   ─► counter→ALU path improves
...
Run 1.1ns:  counter→ALU path FULLY OPTIMIZED
             ─► New worst path emerges: ACC→ALU→ACC
             ─► -46ps violation

In real chip design this iteration continues until:
- All paths close timing  ✅
- OR you hit a fundamental library/architecture limit  ❌
```

This was the most important concept I encountered in this entire analysis. Timing closure is not a single optimization it is a sequence of them, each fix revealing the next problem.

### What I learned: The violation source

The OAI2BB1X2 gate with 167ps delay was the violation source. Despite being X2 (double drive strength), it consumed 167ps because of a 1.6fF load combined with a 51ps input slew from the previous gate.

**This is the same slew degradation cascade I first saw at 1.6ns just appearing in a completely different part of the design.** The same failure mode, in a path I had never looked at before, because it had never been the critical path before.

### What I learned: Why I could not fix this with a multicycle path constraint

The obvious next question: can I apply a multicycle path (MCP) exception? This would tell the tool "give this path two clock cycles" essentially halving the timing requirement.

I went back to the RTL and the control ROM to check:

```verilog
// From CONTROL_ROM.v:
CR[10] <= 17'b00111000010010011; // EU and LA activated simultaneously
```

`EU` (enable ALU output to bus) and `LA` (load accumulator) are both active in the **same microinstruction**. In one clock cycle, the accumulator value must travel through the ALU and return to be captured by the accumulator. `CR[11]` performs a completely different operation there is no second cycle available.

```
WHAT MCP WOULD DO:

Tell the tool: "ACC→ALU→ACC path can take 2 cycles"
Tool says:     "Great, timing closes!"
Silicon does:  ACC captures wrong data because CR[10] only
               lasts one cycle the second cycle captures
               whatever comes next, not the ALU result

Result: CPU computes wrong arithmetic in silicon
        while simulation shows correct results
```

**Applying an incorrect MCP constraint is one of the most dangerous mistakes in physical design.** It makes the timing tool happy while introducing a functional bug that only appears in fabricated silicon. I investigated it, understood why it was wrong, and rejected it. The correct fix is architectural adding a pipeline register which is documented in the companion README.

---

## Run 10 1.1ns High Effort (909 MHz)

<img width="1811" height="2401" alt="1 1ns high timing rpt" src="https://github.com/user-attachments/assets/e87805d3-816f-4f87-95d6-ed459136bf4b" />

> * Timing report at 1.1ns high effort 0ps slack, CLKXOR2X1 in ALU, violation recovered*

### What the report showed

```
Startpoint: UUT6/COUNT_OUT_r_reg[3]/CK   ← back to counter (not accumulator!)
Endpoint:   UUT9/ACC_OUT_r_reg[8]/D
FF type:    SDFFRHQX1   ← scan FF again, but with reset and high drive

Path highlights:
SDFFRHQX1   fanout=3    delay=243ps   (fanout dropped from 15 to 3!)
fopt22094/Y INVX2       fanout=5      delay=48ps
...all fanouts ≤ 5 throughout path...

Slack: 0ps   ✅
Cells: 415   (medium had 426, 11 FEWER cells)
Area:  876   (medium had 912, 36 FEWER area units)
```


### What I learned: High effort found a smaller solution

This was the most counterintuitive result of the entire analysis. High effort synthesis which does more work and tries more combinations produced a **smaller design with fewer cells** that met timing where medium effort failed with more cells.

```
MEDIUM EFFORT at 1.1ns:           HIGH EFFORT at 1.1ns:
Slack: -46ps  ❌                   Slack: 0ps  ✅
Cells: 426                         Cells: 415  (-11)
Area:  912                         Area:  876  (-36)
Inverters: ~26                     Inverters: 54  (+28)
CLK cells: 2                       CLK cells: 8   (+6)
FF types:  5                       FF types:  10  (2×)
CLKXOR2X1: 0                       CLKXOR2X1: 6   ← new
```

Medium effort added cells defensively buffers and upsized gates placed at known problem nodes. It addressed symptoms without restructuring the underlying logic.

High effort restructured the logic itself. The six `CLKXOR2X1` cells in the ALU are the key: the tool replaced the ALU's XOR operations (used for addition carry logic) with clock-grade XOR cells the fastest switching XOR available in the library. This reduced the logic depth in the arithmetic path. Fewer levels of faster cells beats more levels of slower cells.

### What I learned: Synthesis effort is a design variable

Before this I thought of synthesis effort (low/medium/high) as a compile-time performance setting high effort takes longer to run, produces the same result. That is wrong.

**High effort explores a fundamentally larger solution space.** It tries more cell combinations, more logic restructuring options, more FF variants simultaneously. It finds solutions that medium effort never considered.

The practical implication: when timing is tight and medium effort cannot close it, switching to high effort is the first thing to try before making any manual changes to the design. The tool may find a solution you would never think of.

```
WHAT HIGH EFFORT DID THAT MEDIUM EFFORT DID NOT:

1. Tried all 10 FF variants simultaneously for every register
   (medium only tried 5)

2. Used CLKXOR2X1 for ALU XOR operations
   (never appeared in any medium effort run)

3. Applied inverter-based fanout splitting across entire design
   (inverter count doubled: 26 → 54)

4. Chose SDFFRHQX1 (scan FF with reset, high drive) for startpoint
   - fanout dropped from 15 (medium) to 3 (high)
   - this single change saved enormous downstream delay
```

---

## Phase 3 Summary

```
1.1ns medium:  Tool exhausted. -46ps violation. New accumulator path.
               Architecture has reached its limit with current cells.

1.1ns high:    Same constraint. 0ps slack. 11 fewer cells. 36 less area.
               High effort found a completely different implementation.

Lesson: When timing fails, try higher effort before touching the design.
        The tool often knows something you do not.
```

---

---

# The Speed-Area-Power Tradeoff By the Numbers

```
Going from 100MHz to 769MHz (7.7× faster):

Area increase:   +19.7%   (697 → 834 units)
Power increase:  +675%    (24.25µW → 187.45µW)

Area barely moved. Power exploded.
```

**Why they scale so differently:**

Area grows slowly because the tool swaps small cells for large cells the footprint of each cell grows, but the number of cells stays roughly the same. Cell count went from 281 to 371 (+32%) but area only grew 19.7% because many cells were replaced rather than added.

Power grows catastrophically because:
1. Larger cells have larger transistors → larger capacitance C
2. Higher frequency means each capacitance charges/discharges more times per second
3. Power = C × V² × f , both C and f increased simultaneously
4. Power scales roughly as f² in practice, not linearly

**The practical reality of modern chip design:**

```
Question: "Can we run this at 909MHz instead of 769MHz?"

Silicon area cost:   +9.8%  (834 → 912 units)  - manageable
Power cost:          +27%   (187µW → 238µW)     - significant
Timing margin:       0ps vs 1ps                  - no manufacturing margin

Answer: Technically possible. Not production-ready.
        Would fail under any real-world variation.
```

This is why power not area is the hard constraint in modern high-performance chip design. Silicon is cheap. Cooling is expensive. Battery life is finite.

---

# What Comes Next

This analysis was done entirely at the synthesis level using **wireload models** statistical estimates of wire delay based on design size and fanout, not actual physical routing.

The next step is taking the optimized 1.3ns netlist into Encounter and running the full physical implementation. When that happens:

- Wire delays become real (extracted from actual placement and routing geometry)
- The same gates that were slow in synthesis may become faster or slower depending on physical placement
- Congestion appears as a constraint — routing channels can fill up
- Clock tree insertion changes timing by adding real clock delays
- The critical path may shift because real interconnect is different from statistical estimates

**The question I want to answer in the next analysis:** Do the same paths that were critical in synthesis remain critical after physical implementation? Or does placement change everything?

That document will be linked here when complete.

---

# References

- Design source: [OpenCores — SAP Microprogrammed Processor](https://opencores.org/projects/sap_microprogrammed_processor)
- Previous flow: [RTL-to-GDSII Flow — MCPU8_1](https://github.com/Jaydeep8/RTL2GDSII-Flow-Cadence)
- Cadence Genus RTL Compiler User Guide v12.10
- Weste & Harris — *CMOS VLSI Design*, 4th Edition

---

