# Synthesis Analysis — MCPU8_1 (8-bit Microprogrammed CPU)

> I already knew how to run the RTL-to-GDSII flow.  
> This week I learned what is actually happening inside it.

**Author:** Jaydeep Panchal | [LinkedIn](https://www.linkedin.com/in/jaydeep-panchal-0j28p88/) | [GitHub](https://github.com/Jaydeep8)  
**Tool:** Cadence Encounter RTL Compiter (RC v12.10) | **Library:** slow_vdd1v0 | **PVT:** 0.9V, 125°C (worst case)  
**Previous work:** [RTL-to-GDSII Flow — MCPU8_1](https://github.com/Jaydeep8/RTL2GDSII-Flow-Cadence)

---

## What I Did

I took the same 8-bit microprogrammed CPU I had already implemented through the full RTL-to-GDSII flow and asked a different question:

**What actually happens inside the synthesizer when you push timing harder?**

To find out, I ran 10 synthesis experiments — same design, same library, same everything — and changed only the clock constraint. I read every timing report carefully, tracked every metric, and documented what the tool did and why at each step.

This is that documentation.

---

## The Design

MCPU8_1 is an 8-bit microprogrammed CPU sourced from OpenCores. It executes LDA, ADD, SUB, and OUT instructions through a microprogrammed control unit. The architecture that matters for timing analysis:



Two paths will matter throughout this analysis:
- **Counter → Control ROM → ALU** (the control distribution path)
- **Accumulator → ALU → Accumulator** (the arithmetic feedback path)

---

## Part 1 — Run by Run Results

### The Complete Table

| Constraint | Frequency | WNS | Status | Cells | Area | Power (µW) |
|-----------|-----------|-----|--------|-------|------|------------|
| 10ns | 100 MHz | +7999ps |  PASS | 281 | 697 | 24.25 |
| 5ns | 200 MHz | +3008ps |  PASS | 280 | 698 | 48.99 |
| 2ns | 500 MHz | +352ps |  PASS | 315 | 742 | 117.19 |
| 1.6ns | 625 MHz | +10ps |  TIGHT | 352 | 794 | 154.11 |
| 1.5ns | 667 MHz | +8ps |  TIGHT | 354 | 806 | 159.01 |
| 1.4ns | 714 MHz | +2ps |  TIGHT | 362 | 816 | 176.58 |
| 1.3ns | 769 MHz | +1ps |  TIGHT | 371 | 834 | 187.45 |
| 1.2ns | 833 MHz | +3ps |  TIGHT | 400 | 869 | 209.10 |
| 1.1ns (medium) | 909 MHz | **-46ps** |  FAIL | 426 | 912 | 237.82 |
| 1.1ns (high) | 909 MHz | **0ps** |  PASS | 415 | 876 | 248.65 |

**Maximum frequency with robust margin: 769 MHz (1.3ns)**  
**Absolute frequency limit: 909 MHz (1.1ns) at 0ps slack — no manufacturing margin**

---

### What I Observed At Each Step

#### 10ns → 5ns: Nothing interesting. That was the point.

At 10ns the design had **7999ps of slack** — the path only needed 2001ps out of 10000ps available. Changing to 5ns barely mattered. Area stayed flat (697 → 698). The critical path was identical. The tool had zero pressure to do anything different.

**What I learned:** Slack is the gap between what the path needs and what the clock allows. If that gap is enormous, the synthesizer is essentially idle — it picks the smallest cells it can find and stops. The 10ns run is not a characterization of the design. It is a characterization of what happens when you ask nothing of the tool.

The only thing that changed noticeably was power: it doubled from 24.25µW to 48.99µW despite no cell changes. **Power doubled at the same area because the tool synthesized for higher switching frequency, increasing dynamic power even though no cells changed size.**

---

#### 2ns: The first real constraint. The first real problem.

At 2ns the critical path changed completely. A new bottleneck appeared:

```
Path: COUNT_OUT_r_reg[0] → ... → ACC_OUT_r_reg[8]

COUNT_OUT_r_reg[0]/Q  DFFRHQX1  fanout=11  delay=241ps
g493/Y                NOR2X1    fanout=12  load=4.0fF  delay=189ps  ← PROBLEM
g3548/Y               INVX1     fanout=9   load=3.3fF  delay=180ps
g3542/Y               NAND2X1   fanout=9   load=3.6fF  delay=125ps
g3541/Y               INVX1     fanout=8   load=3.2fF  delay=118ps

Slack: +352ps  (close, but passing)
```

The gate `g493/NOR2X1` was driving **12 other gates simultaneously** with a total load of 4.0fF. I had never thought about why a single gate would be slow — I learned it is because every gate it drives has capacitance, and the driving gate must charge all of them before its output reaches a valid logic level.

**The analogy that made it click for me:**

```
WITHOUT BUFFERING:
                     ┌─► gate 1
                     ├─► gate 2
g493 / NOR2X1 ───────├─► gate 3   (one tap filling 12 buckets)
   load = 4.0fF      ├─► ...      (each bucket fills very slowly)
   delay = 189ps     └─► gate 12

WITH BUFFERING:
                     ┌─► BUF ──┬─► gate 1-6   (two taps)
g493 / NOR2X1 ───────┤         └─► gate 4-6   (each fills faster)
   load ≈ 0.7fF      └─► BUF ──┬─► gate 7-9
   delay ≈ 60ps                 └─► gate 10-12

Saving: ~130ps on one gate alone
```

The tool had not yet inserted buffers here — at 352ps of slack it did not need to. But I now knew where the problem was and exactly how it would need to be fixed if timing got tighter.

---

#### 1.6ns → 1.5ns: Living dangerously

Slack collapsed to 10ps, then 8ps. The flip-flop types started changing:

| Constraint | FF type | FF output delay |
|-----------|---------|-----------------|
| 5ns | SDFFQX1 | 180ps |
| 2ns | DFFRHQX1 | 241ps |
| 1.6ns | DFFRX1 | 321ps |
| 1.5ns | DFFRX1 | 325ps |

**What I learned:** The tool changed flip-flop types automatically. At 5ns it used scan flip-flops (SDFF) which have an extra input for manufacturing test but are slightly larger. As timing tightened it swapped to regular DFFs with higher drive strength. This is cell substitution — the tool is not just sizing gates, it is choosing completely different cell functions to survive.

I also saw **slew degradation cascading** for the first time. After the high-fanout gates, the signal transition was so slow that the downstream AOI33XL gate — despite having fanout=1 — showed a 256ps input slew and 211ps delay. A slow signal arriving at a complex gate causes the output to switch slowly too. The problem from three gates earlier was still affecting timing two gates later.

---

#### 1.4ns → 1.3ns: The tool gets creative

At 1.3ns I saw cell names I had not seen before:

```
g23637/Y   CLKAND2X6   fanout=10   delay=122ps
g23618_dup23699/Y   CLKAND2X2   fanout=8   delay=119ps
```

Two things happening here that required research to understand:

**CLK cells in a data path.** The `CLK` prefix means these are clock-network-grade cells — designed for high-speed, high-fanout signal distribution. They are not supposed to be in data paths. The tool borrowed infrastructure cells to fix a data path timing problem. This is a legitimate optimization — the tool knows these cells switch faster and chose them deliberately.

**`_dup` suffix = cell duplication.** The tool created a physical copy of the gate and split the fanout between the original and the duplicate. Instead of one gate driving 16 loads, two gates each drive 8. Same logic function, half the load per gate, lower delay on each. I had read about cell duplication in textbooks. Seeing it appear automatically in a report with the actual gate name made it real.

---

#### 1.1ns (medium effort): The first violation

```
Timing slack: -46ps  ❌

Startpoint: UUT9/ACC_OUT_r_reg[3]/CK   ← ACCUMULATOR (new!)
Endpoint:   UUT9/ACC_OUT_r_reg[6]/D0   ← ACCUMULATOR

ACC_OUT_r_reg[3]/Q   MDFFHQX2   fanout=6    delay=216ps
g23196/Y             OAI2BB1X2  load=1.6fF  delay=167ps  ← violation source
...
Total: 1146ps   Budget: 1100ps   Slack: -46ps
```

**The critical path changed completely.** For every run from 2ns onwards, the worst path started in the counter (UUT6) and traveled through the control ROM (UUT7). By 1.1ns, that path had been optimized so thoroughly that it was no longer the worst path. A completely different path — entirely inside the accumulator feedback loop — was now the bottleneck.

This is called the **whack-a-mole problem** of timing closure:

```
Fix path 1  →  path 2 becomes worst  →  fix path 2  →  path 3 emerges
                                                              ↓
                                          repeat until everything closes
                                          OR you hit a library limit
```

The synthesizer had exhausted every optimization on the counter→ALU path. It had used cell upsizing, logic remapping, buffer insertion, cell duplication, and clock cell borrowing. There was nothing left to do there. And now a path it had never needed to optimize was suddenly the critical path — with 46ps of unrecoverable deficit.

---

#### 1.1ns (high effort): Recovery

Changing `synthesize -to_mapped` to `synthesize -to_mapped -effort high` recovered the violation entirely:

```
Timing slack: 0ps  ✅  (exactly at the limit)
```

**What high effort did that medium effort did not:**

| Technique | Medium effort | High effort |
|-----------|--------------|-------------|
| FF types explored | 5 | 10 |
| Inverter count | ~26 | 54 (doubled) |
| Buffer count | 9 | 14 |
| CLK-grade cells | 2 | 8 |
| CLKXOR2X1 for ALU | 0 | 6 |
| Total cells | 426 | 415 |
| Total area | 912 | 876 |

The last two rows are the most surprising: **high effort used fewer cells and less area than medium effort, yet met timing**. It restructured the logic itself rather than adding more cells defensively. Specifically, it replaced the ALU XOR operations with `CLKXOR2X1` cells — clock-grade XOR gates — reducing the logic depth in the arithmetic path. Fewer levels of faster cells beats more levels of slower cells every time.

It also doubled the inverter count from 26 to 54. Every extra inverter was placed to split a high-fanout net. Medium effort addressed individual known-bad nodes. High effort applied systematic fanout splitting across the entire design simultaneously.

---

## Part 2 — What I Learned (The Concepts)

### Concept 1: How to read a timing report

Before this week I could open a timing report and confirm the slack number. Now I can read the entire path and answer:

- Which gate is the bottleneck and exactly why (load, fanout, or slew)?
- Is this a logic-dominated or interconnect-dominated failure?
- What fix would address the root cause?
- What tradeoff would that fix introduce?

The columns that matter most are not the ones I expected:

```
Pin         Type      Fanout  Load   Slew   Delay  Arrival
                              (fF)   (ps)   (ps)    (ps)

g493/Y      NOR2X1    12      4.0    176    +189    596 R
                      ↑       ↑      ↑
                      |       |      └── how slowly the signal transitions
                      |       └──── total capacitance being driven
                      └──── how many gates this output connects to
```

High fanout → high load → slow slew → high delay → slow next gate. These four things cascade. Finding the first one in the chain is how you find the real root cause.

---

### Concept 2: The speed-area-power tradeoff is not symmetric

This is the result that I think about most:

```
Going 7.7× faster (100MHz → 769MHz):
  Area increase:  +19.7%   (697 → 834 units)
  Power increase: +675%    (24.25µW → 187.45µW)
```

Area barely moves. Power explodes. I expected both to scale similarly — they do not.

The reason: dynamic power = C × V² × f × activity. When you upsize a cell for speed, capacitance C increases. When you run faster, frequency f increases. Both increase together. Power scales roughly as f² in practice, not linearly with f. Area scales much more slowly because the tool replaces small cells with large cells rather than adding entirely new cells.

**The practical implication:** In modern chip design, the constraint that kills you is not "do I have enough silicon area?" It is "can I remove enough heat?" Power is the hard wall. Area is negotiable.

---

### Concept 3: The synthesizer is not a passive tool

Before this analysis I thought of synthesis as a translation step — RTL goes in, netlist comes out. After watching what the tool did across 10 runs, I think of it differently.

The synthesizer is solving an optimization problem under constraints. When you tighten the constraint, it does not just swap in bigger cells. It:

1. Tries every available flip-flop type for every register
2. Restructures Boolean logic to reduce depth
3. Inserts buffers at high-fanout nodes
4. Duplicates cells to split load
5. Borrows clock-infrastructure cells for data paths
6. At high effort, rebuilds arithmetic logic using clock-grade cells

Each of these is a deliberate decision with a tradeoff. The tool is balancing delay against area against power at every node simultaneously. Understanding what it decided — and why — is what lets you guide it when it cannot close timing on its own.

---

### Concept 4: Why I could not fix the violation with a multicycle path constraint

When I saw the -46ps violation, the obvious question was: can I apply a multicycle path (MCP) exception to give this path two cycles?

I read the RTL and the control ROM microcode to check. The violation path is the accumulator feedback loop. The relevant microinstruction is `CR[10]`:

```verilog
CR[10] <= 17'b00111000010010011; // EU and LA activated simultaneously
```

`EU` (enable ALU output to bus) and `LA` (load accumulator) are both active in the **same microinstruction step**. This means the ALU result must be captured by the accumulator in a single clock cycle. There is no second cycle available — `CR[11]` performs a completely different operation.

Applying a multicycle constraint here would make timing appear to close in the tool, but the accumulator would capture the wrong data. The CPU would compute incorrect arithmetic results. The bug would only appear in silicon, not in simulation.

**This is one of the most dangerous mistakes in physical design.** The constraint tells the tool a lie about the architecture, the tool believes it, timing closes on paper, and the chip is fabricated with a functional bug that cannot be fixed in software.

The correct fix is adding a pipeline register after the ALU output, which breaks the path physically into two stages. This requires a microarchitectural change — modifying both the Verilog and the control ROM microcode — not a constraint file change.

---

## Part 3 — The Synthesizer's Bag of Tricks

A summary of every optimization technique I observed, in the order the tool applied them:

| Technique | First seen | What it does | Observable in report |
|-----------|-----------|--------------|---------------------|
| Cell upsizing | 2ns | Replaces X1 with X2/X4 for lower delay | Cell name suffix changes |
| Logic remapping | 2ns | Changes gate type while preserving function | AOI33 → AOI22, etc. |
| FF type substitution | 2ns | Swaps FF variant for better drive/speed | SDFFQX1 → DFFRHQX1 |
| fopt buffer insertion | 1.6ns | Auto-inserts buffers at high-fanout nets | `fopt` prefix in cell name |
| Slew recovery | 1.5ns | Upsizes gate after slow-slew input | Reduces cascade delay |
| Clock cell borrowing | 1.3ns | Uses CLK-grade cells in data path | `CLK` prefix in cell name |
| Cell duplication | 1.3ns | Copies a gate to split its fanout | `_dup` suffix in cell name |
| Full FF library sweep | 1.1ns high | Tries every FF variant simultaneously | 10 FF types used vs 5 |
| CLKXOR in ALU | 1.1ns high | Clock-grade XOR for arithmetic | `CLKXOR2X1` in gates.rpt |
| Inverter fanout splitting | 1.1ns high | Doubles inverter count to split all high-fanout nets | Inverter count 26 → 54 |

---

## What Comes Next

This analysis was done entirely at the synthesis level using wireload models for interconnect — estimated wire delays based on statistical averages, not real routing.

The next step is taking the optimized netlist into Innovus and observing what changes when:
- Wire delays become real (extracted from actual placement and routing)
- Congestion appears as a physical constraint
- Clock tree insertion changes the timing picture
- The same critical paths may shift because real wires are longer or shorter than the wireload estimate predicted

That analysis — synthesis timing vs post-layout timing — is the next document.

---

## References

- Design source: [OpenCores — SAP Microprogrammed Processor](https://opencores.org/projects/sap_microprogrammed_processor)
- Previous flow documentation: [RTL-to-GDSII Flow — MCPU8_1](https://github.com/Jaydeep8/RTL2GDSII-Flow-Cadence)
- Cadence Encounter RTL Compiler User Guide v12.10

---

