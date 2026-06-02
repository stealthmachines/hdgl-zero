#!/usr/bin/env python3
"""
HDGL Bytecode Generator
Compiles HDGL glyph programs to bytecode for the firmware interpreter.

Opcode table:
  0x01 GLYPH  arg=class_id     - create node of given class
  0x02 BRANCH arg=parent_idx   - attach last node to parent index
  0x03 MUTATE arg=new_state    - set last node state
  0x04 RECURSE arg=node_idx    - advance all children of node[idx] one state
  0x05 HALT   arg=0            - stop interpreter
  0x06 PRINT  arg=node_idx     - print node[idx] to serial

Classes:
  0=ROOT  1=CPU  2=MEM  3=IO  4=COMPILER  5=PCI  6=GPU  7=STORAGE  8=BOOT

States:
  0=VOID  1=INIT  2=DISCOVERED  3=CONFIGURED  4=READY  5=EXECUTED
"""

OP_GLYPH   = 0x01
OP_BRANCH  = 0x02
OP_MUTATE  = 0x03
OP_RECURSE = 0x04
OP_HALT    = 0x05
OP_PRINT   = 0x06

OMEGA_INIT       = 1
OMEGA_DISCOVERED = 2
OMEGA_CONFIGURED = 3
OMEGA_READY      = 4
OMEGA_EXECUTED   = 5

CLASS_ROOT=0; CLASS_CPU=1; CLASS_MEM=2; CLASS_IO=3; CLASS_COMPILER=4
CLASS_PCI=5; CLASS_GPU=6; CLASS_STORAGE=7; CLASS_BOOT=8

def assemble(program: list[tuple]) -> bytes:
    """Assemble a list of (opcode, arg) tuples to bytecode."""
    bc = bytearray([0x48, 0x44])  # Magic 'H','D'
    for op, arg in program:
        bc += bytes([op, arg & 0xFF])
    # Pad to 2048 bytes (4 sectors)
    bc += bytes(2048 - len(bc))
    return bytes(bc)

# Default program: implements firmware.hdgl semantics
# Pre-existing nodes: 0=ROOT, 1=CPU, 2=MEM, 3=IO, 4=COMPILER
# PCI nodes: 5..N (from hardware scan)
# Bytecode-created nodes start at N+1

FIRMWARE_HDGL_PROGRAM = [
    # Create STORAGE under IO (parent=3)
    (OP_GLYPH,   CLASS_STORAGE),
    (OP_BRANCH,  3),            # IO parent
    (OP_MUTATE,  OMEGA_DISCOVERED),
    (OP_MUTATE,  OMEGA_CONFIGURED),
    (OP_MUTATE,  OMEGA_READY),

    # Create GPU under IO
    (OP_GLYPH,   CLASS_GPU),
    (OP_BRANCH,  3),
    (OP_MUTATE,  OMEGA_DISCOVERED),
    (OP_MUTATE,  OMEGA_CONFIGURED),

    # Create BOOT record under IO
    (OP_GLYPH,   CLASS_BOOT),
    (OP_BRANCH,  3),
    (OP_MUTATE,  OMEGA_DISCOVERED),
    (OP_MUTATE,  OMEGA_READY),
    (OP_MUTATE,  OMEGA_EXECUTED),

    # Print key nodes
    (OP_PRINT,   0),  # ROOT
    (OP_PRINT,   1),  # CPU
    (OP_PRINT,   2),  # MEM
    (OP_PRINT,   4),  # COMPILER

    # Recurse IO subtree (advance all IO children)
    (OP_RECURSE, 3),

    (OP_HALT,    0),
]

if __name__ == '__main__':
    bc = assemble(FIRMWARE_HDGL_PROGRAM)
    with open('hdgl_bytecode.bin', 'wb') as f:
        f.write(bc)
    print(f"Written {len(bc)} bytes ({len(bc)//512} sectors)")
    print(f"Instructions: {len(FIRMWARE_HDGL_PROGRAM)}")
    print(f"Magic: {bc[0]:02X} {bc[1]:02X}")
