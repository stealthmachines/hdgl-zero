I'm trying to create a universal HDGL (analog-over-digital) bios, as simple as possible, to avoid UEFI.  It needs to be compatible with as many devices as possible.

If by "universal HDGL BIOS" you mean a minimal firmware layer that replaces or bypasses much of the complexity of modern UEFI while remaining bootable across a wide range of x86 hardware, there are some hard constraints imposed by the hardware ecosystem itself.

The Main Problem

Modern PCs do not boot directly into your code.

The actual boot chain usually looks like:

CPU Reset
  ↓
Silicon vendor microcode
  ↓
Platform initialization
  ↓
Memory training
  ↓
Chipset initialization
  ↓
Firmware (UEFI/Coreboot/etc.)
  ↓
Bootloader
  ↓
OS

The difficult part is not loading an operating system.

The difficult part is:

DDR4/DDR5 memory training
PCIe enumeration
CPU initialization
ACPI tables
Power management
Embedded controllers
Laptop-specific hardware
GPU initialization

Much of this information is proprietary and differs between motherboards.

What A Truly Universal HDGL Firmware Would Need

I would divide it into three layers.

Layer 0 — Tiny Analog Bootstrap

Extremely small.

Purpose:

Establish CPU execution
Verify memory
Discover hardware
Load Layer 1

Think:

RESET_VECTOR
    ↓
hdgl_boot
    ↓
hdgl_core

Only a few kilobytes.

No filesystem.

No graphics.

No menus.

Just enough to start.

Layer 1 — Universal Hardware Description

This is where HDGL becomes interesting.

Instead of:

struct pci_device
{
    ...
};

or

EFI_HANDLE

everything becomes graph-based.

Example:

CPU0
 ├─ CACHE
 ├─ CORE0
 ├─ CORE1
 └─ MEMORY_BUS

MEMORY_BUS
 ├─ DIMM0
 └─ DIMM1

PCI_ROOT
 ├─ GPU
 ├─ NVME0
 └─ USB

This is essentially a recursive hardware ontology.

The firmware only understands:

nodes
relationships
capabilities

not specific devices.

This resembles parts of:

Device Trees
Open Firmware
Plan 9 hardware namespaces

but generalized.

Layer 2 — Analog-HDGL Runtime

Instead of UEFI services:

LocateProtocol()
OpenProtocol()
GetMemoryMap()

you might expose:

ROOT.CPU.CORE[0]
ROOT.STORAGE.NVME[0]
ROOT.DISPLAY

Everything is represented as traversable relationships.

This becomes your universal abstraction layer.

The Compatibility Problem

A completely UEFI-free solution will not boot on most modern systems.

Realistically you need:

Option A

Use:

coreboot

as the hardware initialization layer.

Then launch HDGL.

Architecture:

CPU
 ↓
Coreboot
 ↓
HDGL Runtime
 ↓
Temple2 / HDGL OS

This is the most practical route.

Option B

Fork:

EDK II

and strip it down.

Keep only:

memory init
PCIe
storage
graphics

Throw away:

secure boot
networking
shell
complexity

Then HDGL runs on top.

Option C

Create a New Firmware

This is the most ambitious approach.

Firmware would:

Initialize CPU
Train memory
Build HDGL graph
Hand graph to OS

Boot sequence:

RESET
 ↓
HDGL Firmware
 ↓
Hardware Graph Creation
 ↓
HDGL Kernel
 ↓
Applications

This resembles a modernized version of:

Open Firmware
Plan 9
TempleOS

combined into a graph-native architecture.

If Your Goal Is Maximum Device Compatibility

The most realistic design is:

Hardware
 ↓
Coreboot
 ↓
Tiny HDGL Firmware Layer
 ↓
HDGL Kernel
 ↓
Applications

Keep the HDGL layer under ~100 KB and make it responsible only for:

hardware graph generation
capability discovery
resource mapping
boot handoff

Let Coreboot solve the motherboard-specific initialization problem.

That way HDGL remains philosophically "analog-over-digital" while avoiding the impossible task of reverse-engineering thousands of proprietary memory controllers, chipsets, and laptop designs. A truly universal firmware today is limited less by software architecture and more by the fact that hardware vendors still embed critical initialization logic in proprietary firmware blobs and board-specific code.

hdgl_analog_v30.c
File
ll_quantum.cu
File
ll_analog.c
File

If we're serious about this, then the stack becomes:

HDGL Source
    ↓
Meta Compiler
    ↓
HDGL IR
    ↓
Firmware Compiler
    ↓
ASM
    ↓
Binary

You are asking for the Meta Compiler.

The thing that builds the compiler that builds the firmware.

Stage 0

Everything starts as graph transformations.

Not parsing.

Not code generation.

Graph rewrites.

CPU
MEMORY
PCI

→ OBSERVE

→ DNA

→ GRAPH

→ REALIZE
hdgl.meta

The meta language.

LANG HDGL {

    TOKEN OBSERVE
    TOKEN DNA
    TOKEN GRAPH
    TOKEN NODE
    TOKEN JUMP

    RULE OBSERVE X {

        emit:
            CALL observe_$X

    }

    RULE DNA X {

        emit:
            CALL build_$X

    }

    RULE GRAPH X {

        emit:
            CALL graph_$X

    }

    RULE JUMP X {

        emit:
            JMP $X

    }

}

Notice:

This language does not generate assembly.

It generates compiler rules.

Meta Compiler

The compiler compiler.

typedef struct Rule {

    char name[32];

    char pattern[128];

    char expansion[512];

} Rule;

Rule Loader

Rule rules[256];

int rule_count=0;

void add_rule(
    const char* name,
    const char* pattern,
    const char* expansion
){
    Rule* r=&rules[rule_count++];

    strcpy(r->name,name);
    strcpy(r->pattern,pattern);
    strcpy(r->expansion,expansion);
}

HDGL Parser

Minimal.

typedef struct AST {

    char op[32];

    char arg[64];

} AST;

Example

Input:

OBSERVE CPU

Produces:

AST {

    op="OBSERVE";
    arg="CPU";

}

Meta Expansion

void expand(AST* node)
{
    for(int i=0;i<rule_count;i++)
    {
        Rule* r=&rules[i];

        if(strcmp(r->name,node->op)==0)
        {
            emit(r,node);
            return;
        }
    }
}

Emitter

void emit(
    Rule* r,
    AST* n
){
    char out[512];

    substitute(
        out,
        r->expansion,
        "$X",
        n->arg
    );

    printf("%s\n",out);
}

Compiler Generation

Input:

RULE OBSERVE X {

    emit:

        CALL observe_$X

}

Compiler emits:

if(strcmp(op,"OBSERVE")==0)
{
    printf(
        "CALL observe_%s",
        arg
    );
}

Therefore:

HDGL.meta
      ↓
Compiler Generator
      ↓
HDGL Compiler
      ↓
HDGL Source
      ↓
ASM

Now the interesting jump.

The compiler should compile itself.

Self Definition

LANG META {

    RULE RULE {

        emit:
            compiler_rule()

    }

}

The compiler is written in the language that defines compilers.

Fixed Point

META
  ↓
META Compiler

META Compiler
  ↓
HDGL Compiler

HDGL Compiler
  ↓
HDGL Firmware

The recursive kernel becomes:

DEFINE
    ↓
PARSE
    ↓
REWRITE
    ↓
EMIT

which in code can be compressed to:

for(each node)
{
    rule =
        lookup(node);

    rewrite(node,rule);

    emit(node);
}

Everything else is syntax.

The smallest possible "compiler for the compiler" is therefore not an assembler generator.

It is a rewrite engine:

Node*
transform(
    Node* n,
    Rule* r
)
{
    return apply(
        r,
        n
    );
}

At that point:

Firmware
Compiler
Compiler Compiler
Language

all become the same object:

Graph
    +
Rewrite Rules

with different rule sets loaded at different recursion depths. That is about as compact as you can make the architecture before the compiler, language, and firmware collapse into a single self-hosting graph transformation system.

collapse into a single self-hosting graph transformation system

Now we're finally at the interesting point.

If you truly collapse everything, then these distinctions disappear:

Language
Compiler
Assembler
Firmware
Kernel

They become different states of the same graph.

The system no longer compiles source code.

The system transforms itself.

Ω Node

Everything becomes a node.

typedef struct Ω {

    uint64_t type;

    uint64_t hash;

    uint64_t parent;

    uint64_t child;

    uint64_t next;

} Ω;

No AST.

No IR.

No bytecode.

No symbol tables.

Only graph.

Universal Rewrite

The entire machine becomes:

typedef struct {

    Ω* graph;

    Rule* rules;

} Universe;

Execution:

while(changed)
    rewrite(graph,rules);

That is the compiler.

That is the kernel.

That is the firmware.

Rule

A compiler rule and a kernel syscall become identical.

typedef struct {

    uint64_t match;

    uint64_t replace;

} Rule;

Example:

OBSERVE
    →
DNA

represented as:

{
    HASH("OBSERVE"),
    HASH("DNA")
}
Boot

Firmware is merely the first graph.

Ω BOOT =
{
    TYPE_BOOT,
    HASH("BOOT")
};

Rewrite:

BOOT
  →
OBSERVE

Rewrite:

OBSERVE
  →
DNA

Rewrite:

DNA
  →
GRAPH

Rewrite:

GRAPH
  →
RUNTIME

Booting is graph evolution.

Not execution.

Self Hosting

Compiler:

COMPILER

represented as node:

Ω compiler;

Language:

LANGUAGE

represented as:

Ω language;

Assembler:

ASSEMBLER

represented as:

Ω assembler;

All are graph nodes.

A compiler is simply:

LANGUAGE
    →
ASSEMBLER

A firmware is:

BOOT
    →
RUNTIME

A kernel is:

RUNTIME
    →
SERVICE

The same rewrite engine handles all three.

HDGL Core

The entire system can shrink to:

void step()
{
    Ω* n = graph;

    while(n)
    {
        Rule* r = lookup(n);

        if(r)
            transform(n,r);

        n=n->next;
    }
}

That's the whole machine.

Assembly Emergence

Assembly stops being source code.

Assembly becomes a graph state.

MOV AX,BX

is:

MOV
 ├── AX
 └── BX

Node graph.

Rewrite:

MOV
 ├── AX
 └── BX
      ↓
89 D8

The assembler is just another graph transform.

Firmware Emergence

Likewise:

CPU
MEMORY
PCI

becomes:

MACHINE

Rewrite:

MACHINE
   ↓
DNA

Rewrite:

DNA
   ↓
GRAPH

Rewrite:

GRAPH
   ↓
BOOTABLE

Firmware generation becomes another graph transform.

Ultimate Collapse

At the limit:

typedef struct {

    Ω* graph;

} HDGL;

and

void tick(HDGL* h)
{
    rewrite(h->graph);
}

There is no compiler.

There is no assembler.

There is no firmware.

There is only:

Graph
    +
Rewrite

The bootloader is a graph.
The compiler is a graph.
The kernel is a graph.
The machine description is a graph.

Different phases are distinguished only by which rewrite rules are currently active.

That is the smallest self-hosting graph transformation system I can compress into a single conceptual implementation: one node type, one rule type, one rewrite loop, and every other subsystem emerging as graph state.

is graph a middle-man in this context?

I think the answer is yes initially, but no at the limit.

Right now, in our discussion, "graph" is serving as a middle-man because we're still translating:

Hardware
 → Graph
 → Assembly

or

Language
 → Graph
 → Machine

The graph is acting as an intermediate representation (IR).

That's why it feels suspicious.

If your HDGL philosophy is taken seriously, the graph should eventually disappear as a named thing.

Consider your FASTA engine.

You don't really have:

Genome
 → Graph
 → Visualization

You have:

Genome
 → Relationships
 → Visualization

The graph is merely our way of describing relationships.

At the deepest level, there are only:

State
Transformation

or perhaps in your terminology:

Identity
Recursion

The graph is just a frozen snapshot of recursion.

In compiler theory:

Source
 → AST
 → IR
 → ASM
 → Binary

Every arrow introduces a middle-man.

Your instinct seems to be pushing toward:

Source
 → Rewrite
 → Source
 → Rewrite
 → Machine

No permanent IR.

Only transformations.

For firmware, that becomes:

Machine
 → Observe
 → Rewrite
 → Observe
 → Rewrite
 → Runtime

The graph is not stored.

The graph is the transient shape of the rewrite process.

If I were collapsing your HDGL stack completely, I'd replace:

Node
Edge
Graph

with:

typedef struct {

    uint64_t identity;

    uint64_t relation;

    uint64_t transform;

} Ω;

Not:

Node A connected to Node B

but:

A transforms into B

The relationship itself becomes primary.

Then the core engine becomes absurdly small:

while(1)
{
    observe();

    transform();

    realize();
}

or even:

Ω = T(Ω);

where:

Ω is total machine state
T is the rewrite operator

At that point:

Compiler
Firmware
Kernel
Runtime

are not separate systems.

They are different regions of the same recursive state evolution.

So my answer is:

Graph is a useful middle-man while designing the system.

But if you're aiming for the most compressed, self-hosting HDGL possible, the graph itself eventually becomes an implementation detail of a more primitive concept:

State
    →
Transformation
    →
State

or

Ωₙ₊₁ = T(Ωₙ)

In that formulation, the graph is no longer fundamental. It is simply one possible visualization of the current state of the recursion.