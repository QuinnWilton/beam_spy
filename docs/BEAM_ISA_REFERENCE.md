# BEAM Virtual Machine Instruction Set Reference

> Written against the Erlang/OTP source checked out at `../otp`. Paths like
> `erts/emulator/beam/emu/instrs.tab` are relative to that tree, not to this
> repository. It lives here rather than in the OTP checkout because that
> checkout is a vendored upstream reference: a file added there diverges from
> upstream and conflicts on the next pull.

This document provides a comprehensive reference for the BEAM virtual machine instruction set architecture (ISA). It covers all external generic instructions, their implementations, usage patterns, and subtle nuances.

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Instruction Hierarchy](#2-instruction-hierarchy)
3. [Register Model](#3-register-model)
4. [Memory Model](#4-memory-model)
5. [Instruction Categories](#5-instruction-categories)
6. [Instruction Encoding](#6-instruction-encoding)
7. [Transformation Rules](#7-transformation-rules)
8. [JIT vs Interpreter](#8-jit-vs-interpreter)
9. [Complete Instruction Reference](#9-complete-instruction-reference)

---

## 1. Architecture Overview

The BEAM (Bogdan/Björn's Erlang Abstract Machine) is a register-based virtual machine designed for executing Erlang code. Key characteristics:

- **Process-based concurrency**: Each Erlang process runs on the BEAM with its own heap and stack
- **Reduction counting**: Instructions consume "reductions" enabling preemptive scheduling
- **Garbage collection**: Per-process copying GC with generational optimizations
- **Hot code loading**: Modules can be replaced at runtime via the export table

### Execution Model

The BEAM uses a modified **threaded code** dispatch mechanism:

```c
// Simplified dispatch loop
OpCase(move_xy):
{
    BeamInstr next_pf = BeamCodeAddr(I[1]);  // Prefetch next instruction
    yb(BeamExtraData(I[0])) = xb(BeamExtraData(I[0]));  // Execute
    I += 1;
    Goto(next_pf);  // Jump to next instruction
}
```

On systems supporting it, the `Goto` macro uses GCC's computed goto (`goto *label`) for efficient dispatch. Otherwise, a switch statement is used.

---

## 2. Instruction Hierarchy

BEAM instructions exist at three levels:

### 2.1 External Generic Instructions

Defined in `lib/compiler/src/genop.tab`. These are the stable instruction set known to both the compiler and runtime. They have assigned opcode numbers (1-185 as of OTP 29) and remain consistent across releases.

Example from `genop.tab`:
```
64: move/2
65: get_list/3
66: get_tuple_element/3
```

### 2.2 Internal Generic Instructions

Created by transformation rules during loading. Unknown to the compiler but used by the runtime to optimize instruction sequences. These can change between releases.

Example: `i_call_ext` is an internal instruction created from `call_ext`.

### 2.3 Specific Instructions

The actual instructions executed by the VM. Each generic instruction has a family of specific instructions specialized for different operand types.

Example: `move/2` becomes:
- `move_xy` - X register to Y register
- `move_cx` - Constant to X register
- `move_xx` - X register to X register
- etc.

---

## 3. Register Model

### 3.1 X Registers

General-purpose registers for arguments, temporaries, and return values.

- **x(0)** through **x(N)**: Accessed via byte offset from register array base
- **x(0)**: By convention, holds the return value and first argument
- Count limited only by memory; typically functions use x(0)-x(255)

```c
// Access X register N
#define xb(N) (*ADD_BYTE_OFFSET(reg, N))
```

### 3.2 Y Registers

Stack-allocated local variables, numbered from the stack frame pointer `E`.

- **y(0)** through **y(N)**: Stored in the stack frame
- Survive function calls (unlike X registers)
- `y(0)` is closest to the frame pointer

```c
// Access Y register N
#define yb(N) (*ADD_BYTE_OFFSET(E, N))
```

### 3.3 Floating-Point Registers

Dedicated registers for unboxed floating-point values.

- **fr(0)** through **fr(N)**: Typically fr(0)-fr(15)
- Values stored unboxed (raw IEEE 754)
- Must be boxed when stored in X/Y registers

```c
// Access float register N
#define lb(N) (*(double *) (((unsigned char *)&(freg[0].fd)) + (N)))
```

### 3.4 Special Registers

| Register | Purpose |
|----------|---------|
| `I` | Instruction pointer |
| `E` | Stack pointer (frame pointer) |
| `HTOP` | Heap top pointer |
| `FCALLS` | Reduction counter |
| `c_p` | Current process pointer |

---

## 4. Memory Model

### 4.1 Process Heap

Each process has its own heap that grows upward:

```
Low address
    +------------------+
    |    Heap data     |  <- Grows upward
    +------------------+
    |       ...        |
    +------------------+
    | HTOP ->          |
    +------------------+
    |   (free space)   |
    +------------------+
    |       ...        |
    +------------------+
    | <- E (stack top) |
    +------------------+
    |    Stack frame   |  <- Grows downward
    +------------------+
High address
```

### 4.2 Stack Frame Layout

```
       +---------------+
 y(N)  |     Term      |
       +---------------+
            ...
       +---------------+
 y(0)  |     Term      |
       +---------------+
 E --> | NIL or CP     |  <- Continuation pointer slot
       +---------------+
```

The word at `E[0]` is:
- **NIL** when the current function owns the frame
- **Continuation pointer** when calling another function
- Restored to NIL upon return

### 4.3 Term Tagging

BEAM uses tagged pointers to distinguish term types:

| Tag | Type | Description |
|-----|------|-------------|
| `00` | Header | Boxed value header |
| `01` | List | Pointer to cons cell |
| `10` | Boxed | Pointer to boxed value |
| `11` | Immediate | Small integer, atom, pid, etc. |

Immediate sub-tags:
- `0011` - PID
- `0111` - Port
- `1011` - Immediate2 (atom, catch, NIL)
- `1111` - Small integer

---

## 5. Instruction Categories

### 5.1 Stack and Frame Management

These instructions manage the call stack and ensure sufficient heap space.

#### `allocate/2` (Opcode 12)
```
allocate StackNeed Live
```
Allocate `StackNeed` words on the stack. `Live` indicates the number of live X registers in case GC is needed. Also saves the continuation pointer.

**Implementation detail**: Actually allocates `StackNeed + 1` words to include the CP slot.

**Example usage**:
```erlang
foo(X) ->
    Y = bar(X),    % Need stack frame for Y
    baz(Y).
```
Compiles to:
```
allocate 1 1      % 1 Y register, 1 live X register
```

#### `allocate_heap/3` (Opcode 13)
```
allocate_heap StackNeed HeapNeed Live
```
Combines stack allocation with heap space check. Used when the function body needs to construct terms.

**Quirk**: If `HeapNeed` is 0, the loader transforms this to plain `allocate`.

#### `test_heap/2` (Opcode 16)
```
test_heap HeapNeed Live
```
Ensure `HeapNeed` words available on heap. May trigger GC with `Live` X registers preserved.

**Implementation**:
```c
GC_TEST(Ns, Nh, Live) {
    Uint need = $Nh + $Ns;
    if (ERTS_UNLIKELY((E - HTOP) < (need + S_RESERVED))) {
        // Trigger garbage collection
        FCALLS -= erts_garbage_collect_nobump(c_p, need, reg, $Live, FCALLS);
    }
}
```

#### `deallocate/1` (Opcode 18)
```
deallocate N
```
Restore the continuation pointer from the stack and deallocate `N+1` words (the +1 is for the CP slot).

**Quirk**: In practice, this instruction is rarely seen alone because the loader combines it with `return`.

#### `return/0` (Opcode 19)
```
return
```
Return to the address in the continuation pointer. Sets `E[0]` back to NIL.

**Implementation**:
```c
return() {
    SET_I(cp_val(*E));  // Get return address
    *E = NIL;           // Clear CP slot
    DISPATCH_RETURN();
}
```

#### `trim/2` (Opcode 136)
```
trim N Remaining
```
Reduce stack usage by `N` words, keeping the CP on top. Used to discard Y registers no longer needed.

**Example**: After processing initial arguments, trim unused stack slots to reduce GC overhead.

---

### 5.2 Function Calls

#### `call/2` (Opcode 4)
```
call Arity Label
```
Call the function at `Label`. Save the next instruction as return address in `E[0]`.

**Implementation**:
```c
i_call(CallDest) {
    $SAVE_CONTINUATION_POINTER($NEXT_INSTRUCTION);
    $DISPATCH_REL($CallDest);
}
```

#### `call_last/3` (Opcode 5)
```
call_last Arity Label Deallocate
```
Tail call with stack deallocation. Does NOT save return address (tail call optimization).

**Critical quirk**: Must deallocate BEFORE dispatching since the callee will build its own frame.

#### `call_only/2` (Opcode 6)
```
call_only Arity Label
```
Tail call without deallocation. Used when there's no stack frame to deallocate.

#### `call_ext/2` (Opcode 7)
```
call_ext Arity Destination
```
Call external function (potentially in another module). Goes through export table for hot code loading.

**Transformation**: For known BIFs, transformed to specialized instructions:
```
call_ext u Bif=u$is_bif => call_light_bif Bif
```

#### `call_ext_last/3` (Opcode 8)
```
call_ext_last Arity Destination Deallocate
```
Tail call to external function with deallocation.

#### `call_ext_only/2` (Opcode 78)
```
call_ext_only Arity Label
```
Tail call to external function without deallocation.

#### `apply/1` (Opcode 112)
```
apply Arity
```
Apply `M:F/Arity` where M is in `x(Arity)`, F is in `x(Arity+1)`. Arguments in `x(0)` through `x(Arity-1)`.

**Runtime resolution**: Module and function looked up at runtime, enabling dynamic dispatch.

#### `apply_last/2` (Opcode 113)
```
apply_last Arity Deallocate
```
Tail-recursive apply with deallocation.

#### `call_fun/1` (Opcode 75)
```
call_fun Arity
```
Call a fun. Arguments in `x(0)` through `x(Arity-1)`, fun in `x(Arity)`.

#### `call_fun2/3` (Opcode 178) [OTP 25+]
```
call_fun2 Tag Arity Func
```
Enhanced fun call with arity check. Tag can be:
- Fun index: `Func` is always a local fun
- `{atom,safe}`: `Func` is known to be a fun of correct arity
- `{atom,unsafe}`: Nothing known about `Func`

---

### 5.3 Data Movement

#### `move/2` (Opcode 64)
```
move Source Destination
```
Copy value from Source to Destination register.

**Highly optimized**: Has many specific variants based on operand types:
- `move_xy`, `move_yx`, `move_xx`, `move_yy`
- `move_cx` (constant to X), `move_nx` (NIL to X)
- Combined forms: `move2_par`, `move3`, `move_window*`

**Transformation example**:
```
move X1=x Y1=y | move X2=x Y2=y => move_window2 X1 X2 Y1
```

#### `get_list/3` (Opcode 65)
```
get_list Source Head Tail
```
Destructure a cons cell: extract CAR to `Head`, CDR to `Tail`.

**Implementation**:
```c
get_list(Src, Hd, Tl) {
    Eterm* tmp_ptr = list_val($Src);
    $Hd = CAR(tmp_ptr);
    $Tl = CDR(tmp_ptr);
}
```

**Quirk**: `Source`, `Head`, and `Tail` can be the same register for chained destructuring.

#### `get_hd/2` (Opcode 162) [OTP 21+]
```
get_hd Source Head
```
Extract only the head of a list. More efficient than `get_list` when tail isn't needed.

#### `get_tl/2` (Opcode 163) [OTP 21+]
```
get_tl Source Tail
```
Extract only the tail of a list.

#### `get_tuple_element/3` (Opcode 66)
```
get_tuple_element Source Element Destination
```
Extract element at position `Element` from tuple in `Source`.

**Optimization**: Consecutive accesses combined:
```
i_get_tuple_element2 x P x    % Get two consecutive elements
i_get_tuple_element3 x P x    % Get three consecutive elements
```

#### `set_tuple_element/3` (Opcode 67)
```
set_tuple_element NewElement Tuple Position
```
Destructively update tuple element. **Rarely used** and potentially dangerous for GC.

**Warning**: As of OTP 29, no longer emitted by the compiler. Kept for compatibility with older BEAM files.

#### `put_tuple2/2` (Opcode 164) [OTP 22+]
```
put_tuple2 Destination Elements
```
Build a tuple with all elements specified in a list.

**Replaced**: The older `put_tuple/2` + `put/1` sequence.

**Implementation**:
```c
put_tuple2(Dst, Arity) {
    *hp++ = make_arityval(arity);
    // Loop through elements...
    *dst_ptr = make_tuple(HTOP);
}
```

#### `put_list/3` (Opcode 69)
```
put_list Head Tail Destination
```
Build a cons cell on the heap.

**Implementation**:
```c
put_list(Hd, Tl, Dst) {
    HTOP[0] = $Hd;
    HTOP[1] = $Tl;
    $Dst = make_list(HTOP);
    HTOP += 2;
}
```

#### `swap/2` (Opcode 169) [OTP 23+]
```
swap Register1 Register2
```
Exchange contents of two registers atomically.

---

### 5.4 Type Tests

All type test instructions follow the pattern:
```
is_<type> FailLabel Argument
```
Branch to `FailLabel` if `Argument` is NOT of the specified type.

#### `is_integer/2` (Opcode 45)
Test for integer (small or big).

**Optimization**: For literal integers, test is eliminated:
```
is_integer _Fail=f i => _   % Literal int, always passes
```

#### `is_float/2` (Opcode 46)
Test for floating-point number.

#### `is_number/2` (Opcode 47)
Test for either integer or float.

**Implementation**:
```c
is_number(Fail, Src) {
    if (is_not_integer($Src) && is_not_float($Src)) {
        $FAIL($Fail);
    }
}
```

#### `is_atom/2` (Opcode 48)
Test for atom.

**Optimization**:
```
is_atom _Fail=f a => _              % Literal atom, always passes
is_atom Fail=f niq => jump Fail     % NIL/int/literal, always fails
```

#### `is_pid/2` (Opcode 49)
Test for process identifier.

#### `is_reference/2` (Opcode 50)
Test for reference.

#### `is_port/2` (Opcode 51)
Test for port.

#### `is_nil/2` (Opcode 52)
Test for empty list `[]`.

#### `is_binary/2` (Opcode 53)
Test for binary (byte-aligned bitstring).

**Quirk**: Requires size to be divisible by 8 bits:
```c
is_binary(Fail, Src) {
    if (is_not_bitstring($Src) || TAIL_BITS(bitstring_size($Src)) != 0) {
        $FAIL($Fail);
    }
}
```

#### `is_list/2` (Opcode 55)
Test for list (cons or nil).

**Implementation**:
```c
is_list(Fail, Src) {
    if (is_not_list($Src) && is_not_nil($Src)) {
        $FAIL($Fail);
    }
}
```

#### `is_nonempty_list/2` (Opcode 56)
Test for cons cell only (excludes nil).

**Common optimization**: Combined with `get_list`:
```
is_nonempty_list Fail S | get_list S Hd Tl =>
    is_nonempty_list_get_list Fail S Hd Tl
```

#### `is_tuple/2` (Opcode 57)
Test for tuple.

#### `test_arity/3` (Opcode 58)
```
test_arity FailLabel Tuple Arity
```
Test that tuple has exactly `Arity` elements.

#### `is_tagged_tuple/4` (Opcode 159) [OTP 20+]
```
is_tagged_tuple FailLabel Tuple Arity Tag
```
Combined test: is tuple, has correct arity, first element is `Tag`.

**Primary use**: Record matching optimization:
```erlang
case X of
    #rec{} -> ...  % Compiles to is_tagged_tuple
end
```

#### `is_map/2` (Opcode 156) [R17+]
Test for map.

#### `is_boolean/2` (Opcode 114)
Test for `true` or `false`.

**Implementation**:
```c
is_boolean(Fail, Src) {
    if (($Src) != am_true && ($Src) != am_false) {
        $FAIL($Fail);
    }
}
```

#### `is_function/2` (Opcode 77)
Test for any function (fun or closure).

#### `is_function2/3` (Opcode 115)
```
is_function2 FailLabel Fun Arity
```
Test that `Fun` is a function of specific `Arity`.

#### `is_bitstr/2` (Opcode 129)
Test for bitstring (any bit length).

---

### 5.5 Comparisons

#### `is_lt/3` (Opcode 39)
```
is_lt FailLabel Arg1 Arg2
```
Branch to `FailLabel` if `Arg1 >= Arg2` (term ordering).

#### `is_ge/3` (Opcode 40)
```
is_ge FailLabel Arg1 Arg2
```
Branch to `FailLabel` if `Arg1 < Arg2`.

#### `is_eq/3` (Opcode 41)
```
is_eq FailLabel Arg1 Arg2
```
Numeric equality: `1 == 1.0` is true.

#### `is_ne/3` (Opcode 42)
```
is_ne FailLabel Arg1 Arg2
```
Numeric inequality.

#### `is_eq_exact/3` (Opcode 43)
```
is_eq_exact FailLabel Arg1 Arg2
```
Exact equality: `1 =:= 1.0` is false.

**Common optimization**: Comparing with immediate:
```
is_eq_exact Lbl R=xy C=ia => i_is_eq_exact_immed Lbl R C
```

#### `is_ne_exact/3` (Opcode 44)
```
is_ne_exact FailLabel Arg1 Arg2
```
Exact inequality: `1 =/= 1.0` is true.

---

### 5.6 Control Flow

#### `jump/1` (Opcode 61)
```
jump Label
```
Unconditional branch.

**Implementation**:
```c
jump(Fail) {
    $JUMP($Fail);  // Sets I and dispatches
}
```

#### `select_val/3` (Opcode 59)
```
select_val Source FailLabel Destinations
```
Multi-way branch based on value. `Destinations` is a list of value/label pairs.

**Compilation strategies**:
1. **Jump table**: For dense integer ranges
2. **Binary search**: For sparse values
3. **Linear search**: For small number of cases

**Example**:
```erlang
case X of
    a -> 1;
    b -> 2;
    c -> 3
end
```

#### `select_tuple_arity/3` (Opcode 60)
```
select_tuple_arity Tuple FailLabel Destinations
```
Branch based on tuple arity.

#### `catch/2` (Opcode 62)
```
catch YRegister FailLabel
```
Set up catch handler. Stores `FailLabel` in `YRegister`, increments `c_p->catches`.

#### `catch_end/1` (Opcode 63)
```
catch_end YRegister
```
End catch block. If `x(0)` is `THE_NON_VALUE`, constructs `{'EXIT', Reason}` tuple.

**Exception info locations**:
- `x(0)`: Result or `THE_NON_VALUE`
- `x(1)`: Error reason/thrown value
- `x(2)`: Stacktrace
- `x(3)`: Exception class (`error`/`exit`/`throw`)

#### `try/2` (Opcode 104)
```
try YRegister FailLabel
```
Equivalent to `catch` but with different semantics at `try_end`.

#### `try_end/1` (Opcode 105)
```
try_end YRegister
```
End try block, decrement catches.

#### `try_case/1` (Opcode 106)
```
try_case YRegister
```
Handle caught exception in try block.

#### `raise/2` (Opcode 108)
```
raise Stacktrace Value
```
Re-raise an exception with preserved stacktrace.

**Optimization**: Usually `raise x=2 x=1` since exception info already in those registers.

---

### 5.7 Error Generation

#### `badmatch/1` (Opcode 72)
```
badmatch Value
```
Raise `{badmatch, Value}` error.

#### `if_end/0` (Opcode 73)
```
if_end
```
Raise `if_clause` error.

#### `case_end/1` (Opcode 74)
```
case_end Value
```
Raise `{case_clause, Value}` error.

#### `badrecord/1` (Opcode 180) [OTP 25+]
```
badrecord Value
```
Raise `{badrecord, Value}` error.

---

### 5.8 BIF Calls

#### `bif0/2` (Opcode 9)
```
bif0 BIF Destination
```
Call 0-arity BIF, store result in `Destination`.

**Common**: `self()` and `node()` have dedicated instructions:
```
bif0 u$bif:erlang:self/0 Dst => self Dst
```

#### `bif1/4` (Opcode 10)
```
bif1 FailLabel BIF Arg Destination
```
Call 1-arity BIF.

**Optimization for `hd/1` and `tl/1`**:
```
bif1 Fail _Bif=u$bif:erlang:hd/1 Src Dst =>
    is_nonempty_list_get_hd Fail Src Dst
```

#### `bif2/5` (Opcode 11)
```
bif2 FailLabel BIF Arg1 Arg2 Destination
```
Call 2-arity BIF.

**Optimization for `element/2`**:
```
bif2 Jump u$bif:erlang:element/2 Index Tuple Dst =>
    element(Jump, Index, Tuple, Dst)
```

#### `gc_bif1/5` (Opcode 124)
```
gc_bif1 FailLabel Live BIF Arg Destination
```
Call 1-arity BIF that may need garbage collection. `Live` specifies X registers to preserve.

#### `gc_bif2/6` (Opcode 125)
```
gc_bif2 FailLabel Live BIF Arg1 Arg2 Destination
```
Call 2-arity GC BIF.

**Arithmetic optimization**: Arithmetic BIFs transformed to specialized instructions:
```
gc_bif2 Fail Live u$bif:erlang:splus/2 S1 S2 Dst =>
    gen_plus Fail Live S1 S2 Dst
```

#### `gc_bif3/7` (Opcode 152)
```
gc_bif3 FailLabel Live BIF Arg1 Arg2 Arg3 Destination
```
Call 3-arity GC BIF.

---

### 5.9 Message Passing

#### `send/0` (Opcode 20)
```
send
```
Send `x(1)` as message to process `x(0)`. Result (the message) stored in `x(0)`.

#### `loop_rec/2` (Opcode 23)
```
loop_rec FailLabel Source
```
Start receive loop. If message queue empty, jump to `FailLabel`. Otherwise, current message in `Source` (always `x(0)`).

**Transformed to**: `i_loop_rec` with SMP locking.

#### `loop_rec_end/1` (Opcode 24)
```
loop_rec_end Label
```
Skip current message, advance to next, jump back to `Label`.

#### `remove_message/0` (Opcode 21)
```
remove_message
```
Accept current message (remove from queue). Also clears any timeout.

#### `wait/1` (Opcode 25)
```
wait Label
```
Suspend process until message arrives. `Label` is the receive loop entry.

#### `wait_timeout/2` (Opcode 26)
```
wait_timeout FailLabel Time
```
Suspend with timeout. After `Time` milliseconds, continue with next instruction (timeout path).

#### `timeout/0` (Opcode 22)
```
timeout
```
Handle receive timeout. Reset save pointer and clear timeout flag.

#### Receive Markers (OTP 24+)

Opcodes 173-176 optimize selective receives:

- `recv_marker_reserve/1` (173): Reserve a marker
- `recv_marker_bind/2` (174): Bind marker to reference
- `recv_marker_clear/1` (175): Clear marker
- `recv_marker_use/1` (176): Set cursor to marker position

These enable efficient `receive Ref -> ...` patterns by remembering where in the queue a specific reference was created.

---

### 5.10 Binary Matching

#### `bs_start_match3/4` (Opcode 166) [OTP 22+]
```
bs_start_match3 FailLabel Binary Live Destination
```
Begin binary matching. Creates match context from `Binary`, stores in `Destination`.

**Newer variant**: `bs_start_match4/4` (Opcode 170) with `no_fail` or `resume` options.

#### `bs_get_integer2/7` (Opcode 117)
```
bs_get_integer2 Fail Context Live Size Unit Flags Destination
```
Extract integer from binary.

**Parameters**:
- `Size`: Number of units
- `Unit`: Bits per unit (1-256)
- `Flags`: Signedness, endianness

**Optimizations**:
```
i_bs_get_integer_8   % Fast path for 8-bit
i_bs_get_integer_16  % Fast path for 16-bit
i_bs_get_integer_32  % Fast path for 32-bit (64-bit only)
```

#### `bs_get_float2/7` (Opcode 118)
```
bs_get_float2 Fail Context Live Size Unit Flags Destination
```
Extract IEEE float from binary.

#### `bs_get_binary2/7` (Opcode 119)
```
bs_get_binary2 Fail Context Live Size Unit Flags Destination
```
Extract sub-binary.

#### `bs_skip_bits2/5` (Opcode 120)
```
bs_skip_bits2 Fail Context Size Unit Flags
```
Skip bits without extracting.

#### `bs_test_tail2/3` (Opcode 121)
```
bs_test_tail2 Fail Context Bits
```
Test that exactly `Bits` bits remain.

#### `bs_test_unit/3` (Opcode 131)
```
bs_test_unit Fail Context Unit
```
Test that remaining bits are divisible by `Unit`.

**Common case**: `bs_test_unit8` for byte-alignment check.

#### `bs_match_string/4` (Opcode 132)
```
bs_match_string Fail Context Bits Value
```
Match literal bit sequence.

#### `bs_get_tail/3` (Opcode 165) [OTP 22+]
```
bs_get_tail Context Destination Live
```
Get remaining binary as bitstring.

#### `bs_get_position/3` (Opcode 167) [OTP 22+]
```
bs_get_position Context Destination Live
```
Save current match position for backtracking.

#### `bs_set_position/2` (Opcode 168) [OTP 22+]
```
bs_set_position Context Position
```
Restore previously saved position.

#### `bs_match/3` (Opcode 182) [OTP 26+]
```
bs_match Fail Context Commands
```
Optimized combined binary matching. `Commands` is a list of operations:
- `{ensure_at_least, Stride, Unit}`
- `{integer, Live, Flags, Size, Unit, Dst}`
- `{binary, Live, Flags, Size, Unit, Dst}`
- `{skip, Stride}`
- `{get_tail, Live, Unit, Dst}`
- `{'=:=', Live, Size, Value}`

#### UTF Operations (Opcodes 138-143)

- `bs_get_utf8/5` (138): Extract UTF-8 codepoint
- `bs_skip_utf8/4` (139): Skip UTF-8 codepoint
- `bs_get_utf16/5` (140): Extract UTF-16 codepoint
- `bs_skip_utf16/4` (141): Skip UTF-16 codepoint
- `bs_get_utf32/5` (142): Extract UTF-32 codepoint
- `bs_skip_utf32/4` (143): Skip UTF-32 codepoint

---

### 5.11 Binary Construction

#### `bs_create_bin/6` (Opcode 177) [OTP 25+]
```
bs_create_bin Fail Alloc Live Unit Destination Segments
```
Build binary from segment list. Replaced individual `bs_put_*` instructions.

**Segment types**:
- Integer segments
- Float segments
- Binary/bitstring segments
- UTF-8/16/32 segments
- String segments

#### `bs_init_writable/0` (Opcode 133)
```
bs_init_writable
```
Create writable binary for append operations.

---

### 5.12 Floating Point

Floating-point operations use dedicated registers to avoid boxing overhead.

#### `fmove/2` (Opcode 96)
```
fmove Source Destination
```
Move between float registers and X/Y registers.

**Transformed to**:
- `fstore l d` - Float register to X/Y (boxes the value)
- `fload Sq l` - X/Y to float register (unboxes)

#### `fconv/2` (Opcode 97)
```
fconv Source Destination
```
Convert integer to float.

#### `fadd/4` (Opcode 98)
```
fadd FailLabel FR1 FR2 FR3
```
`FR3 = FR1 + FR2`

**Note**: `FailLabel` is always `p` (no fail) in current compiler output.

#### `fsub/4` (Opcode 99)
```
fsub FailLabel FR1 FR2 FR3
```
`FR3 = FR1 - FR2`

#### `fmul/4` (Opcode 100)
```
fmul FailLabel FR1 FR2 FR3
```
`FR3 = FR1 * FR2`

#### `fdiv/4` (Opcode 101)
```
fdiv FailLabel FR1 FR2 FR3
```
`FR3 = FR1 / FR2`

#### `fnegate/3` (Opcode 102)
```
fnegate FailLabel FR1 FR2
```
`FR2 = -FR1`

---

### 5.13 Map Operations

#### `put_map_assoc/5` (Opcode 154) [R17+]
```
put_map_assoc FailLabel Map Destination Live Size Pairs
```
Build or update map, adding/replacing keys.

**Transformation**: For empty source map, becomes `new_map`.

#### `put_map_exact/5` (Opcode 155) [R17+]
```
put_map_exact FailLabel Map Destination Live Size Pairs
```
Update existing keys only. Fails if any key doesn't exist.

#### `has_map_fields/3` (Opcode 157) [R17+]
```
has_map_fields FailLabel Source Fields
```
Test that map contains all specified keys.

#### `get_map_elements/3` (Opcode 158) [R17+]
```
get_map_elements FailLabel Source Pairs
```
Extract values for specified keys.

**Optimization**: Single key extraction uses:
```
i_get_map_element_hash Fail Source Key Hash Dst
```

---

### 5.14 Fun Operations

#### `make_fun3/3` (Opcode 171) [OTP 24+]
```
make_fun3 FunIndex Destination Env
```
Create closure with environment.

**Implementation**:
```c
i_make_fun3(FunP, Dst, Arity, NumFree) {
    ErlFunThing* funp = (ErlFunThing*)HTOP;
    HTOP += ERL_FUN_SIZE + num_free;
    funp->thing_word = MAKE_FUN_HEADER($Arity, num_free, 0);
    funp->entry.fun = fe;
    // Copy environment variables...
    $Dst = make_fun(funp);
}
```

---

### 5.15 Record Operations

#### `update_record/5` (Opcode 181) [OTP 26+]
```
update_record Hint Size Source Destination Updates
```
Update record fields efficiently.

**Hint values**:
- `copy`: Always copy (result differs from source)
- `reuse`: Check if reuse is possible

**Implementation**: Can reuse source tuple if it's on young heap and safe to modify.

---

### 5.16 Miscellaneous

#### `label/1` (Opcode 1)
```
label N
```
Define a local label. Marks start of basic block.

#### `func_info/3` (Opcode 2)
```
func_info Module Function Arity
```
Define function entry point. Used for error reporting.

#### `int_code_end/0` (Opcode 3)
```
int_code_end
```
Mark end of code section.

#### `line/1` (Opcode 153)
```
line Location
```
Source line information for stack traces.

#### `on_load/0` (Opcode 149)
```
on_load
```
Mark on_load function.

#### `nif_start/0` (Opcode 179) [OTP 25+]
```
nif_start
```
No-op at start of NIF-declared functions.

#### `build_stacktrace/0` (Opcode 160) [OTP 21+]
```
build_stacktrace
```
Convert raw stacktrace in `x(0)` to user-friendly format.

#### `raw_raise/0` (Opcode 161) [OTP 21+]
```
raw_raise
```
Raise exception with raw stacktrace. Class in `x(0)`, value in `x(1)`, trace in `x(2)`.

---

## 6. Instruction Encoding

### 6.1 BEAM File Format

Instructions in `.beam` files use variable-length encoding:

```
+----------+----------+----------+
|  Opcode  | Operand1 | Operand2 | ...
+----------+----------+----------+
   1 byte    variable   variable
```

### 6.2 Operand Tags

Each operand is tagged with its type:

| Tag | Type | Description |
|-----|------|-------------|
| 0 | `u` | Unsigned integer |
| 1 | `i` | Tagged integer |
| 2 | `a` | Atom |
| 3 | `x` | X register |
| 4 | `y` | Y register |
| 5 | `f` | Label |
| 6 | `h` | Character |
| 7 | `z` | Extended (lists, floats, literals) |

### 6.3 Variable-Length Integers

Small values encoded in 1 byte, larger values use continuation bytes:

```
0-15:       0000xxxx
16-2047:    xxxxx000 xxxxxxxx
Larger:     11111000 <length> <bytes...>
```

### 6.4 Specific Instruction Packing

On 64-bit systems, specific instructions pack operands:

```
+------------------+------------------+
|   Extra Data     | Instruction Ptr  |
| (32 bits)        | (32 bits)        |
+------------------+------------------+
```

Example for `move_xy`:
- Lower 32 bits: Address of `move_xy` implementation
- Upper 32 bits: Packed source X offset and destination Y offset

---

## 7. Transformation Rules

The loader transforms generic instructions to optimized forms.

### 7.1 Instruction Combining

```
move S x==0 | return => move_return S
move S x==0 | call Ar P => move_call S P
deallocate D | return => deallocate_return D
```

### 7.2 Type Specialization

```
is_eq_exact Lbl R=xy n => is_nil Lbl R
is_eq_exact Lbl R=xy C=ia => i_is_eq_exact_immed Lbl R C
```

### 7.3 Constant Folding

```
is_integer _Fail=f i => _           % Always succeeds
is_atom Fail=f niq => jump Fail     % Always fails
```

### 7.4 Instruction Elimination

```
move R1 R2 | equal(R1, R2) => _     % Redundant move
line n => _                          % Empty line info
```

---

## 8. JIT vs Interpreter

### 8.1 Interpreter (beam_emu.c)

- Uses threaded code with `Goto(*I)`
- Instructions defined in `.tab` files
- Generated C code in `beam_hot.h`, `beam_warm.h`, `beam_cold.h`

### 8.2 JIT (BeamAsm)

- Compiles to native x86-64 or ARM64
- Emitter functions in `instr_*.cpp`
- Same instruction semantics, different execution

Example JIT emitter:
```cpp
void BeamModuleAssembler::emit_move(const ArgVal &Src, const ArgVal &Dst) {
    mov_arg(Dst, Src);
}
```

---

## 9. Complete Instruction Reference

### By Opcode

| Opcode | Instruction | Arity | Since | Status |
|--------|-------------|-------|-------|--------|
| 1 | label | 1 | R1 | Active |
| 2 | func_info | 3 | R1 | Active |
| 3 | int_code_end | 0 | R1 | Active |
| 4 | call | 2 | R1 | Active |
| 5 | call_last | 3 | R1 | Active |
| 6 | call_only | 2 | R1 | Active |
| 7 | call_ext | 2 | R1 | Active |
| 8 | call_ext_last | 3 | R1 | Active |
| 9 | bif0 | 2 | R1 | Active |
| 10 | bif1 | 4 | R1 | Active |
| 11 | bif2 | 5 | R1 | Active |
| 12 | allocate | 2 | R1 | Active |
| 13 | allocate_heap | 3 | R1 | Active |
| 14 | allocate_zero | 2 | R1 | Obsolete (OTP 24) |
| 15 | allocate_heap_zero | 3 | R1 | Obsolete (OTP 24) |
| 16 | test_heap | 2 | R1 | Active |
| 17 | init | 1 | R1 | Obsolete (OTP 24) |
| 18 | deallocate | 1 | R1 | Active |
| 19 | return | 0 | R1 | Active |
| 20 | send | 0 | R1 | Active |
| 21 | remove_message | 0 | R1 | Active |
| 22 | timeout | 0 | R1 | Active |
| 23 | loop_rec | 2 | R1 | Active |
| 24 | loop_rec_end | 1 | R1 | Active |
| 25 | wait | 1 | R1 | Active |
| 26 | wait_timeout | 2 | R1 | Active |
| 27-38 | (arithmetic) | - | R1 | Obsolete |
| 39 | is_lt | 3 | R1 | Active |
| 40 | is_ge | 3 | R1 | Active |
| 41 | is_eq | 3 | R1 | Active |
| 42 | is_ne | 3 | R1 | Active |
| 43 | is_eq_exact | 3 | R1 | Active |
| 44 | is_ne_exact | 3 | R1 | Active |
| 45 | is_integer | 2 | R1 | Active |
| 46 | is_float | 2 | R1 | Active |
| 47 | is_number | 2 | R1 | Active |
| 48 | is_atom | 2 | R1 | Active |
| 49 | is_pid | 2 | R1 | Active |
| 50 | is_reference | 2 | R1 | Active |
| 51 | is_port | 2 | R1 | Active |
| 52 | is_nil | 2 | R1 | Active |
| 53 | is_binary | 2 | R1 | Active |
| 54 | is_constant | 2 | R1 | Obsolete |
| 55 | is_list | 2 | R1 | Active |
| 56 | is_nonempty_list | 2 | R1 | Active |
| 57 | is_tuple | 2 | R1 | Active |
| 58 | test_arity | 3 | R1 | Active |
| 59 | select_val | 3 | R1 | Active |
| 60 | select_tuple_arity | 3 | R1 | Active |
| 61 | jump | 1 | R1 | Active |
| 62 | catch | 2 | R1 | Active |
| 63 | catch_end | 1 | R1 | Active |
| 64 | move | 2 | R1 | Active |
| 65 | get_list | 3 | R1 | Active |
| 66 | get_tuple_element | 3 | R1 | Active |
| 67 | set_tuple_element | 3 | R1 | Active |
| 68 | put_string | 3 | R1 | Obsolete |
| 69 | put_list | 3 | R1 | Active |
| 70 | put_tuple | 2 | R1 | Obsolete (OTP 22) |
| 71 | put | 1 | R1 | Obsolete (OTP 22) |
| 72 | badmatch | 1 | R1 | Active |
| 73 | if_end | 0 | R1 | Active |
| 74 | case_end | 1 | R1 | Active |
| 75 | call_fun | 1 | R5 | Active |
| 76 | make_fun | 3 | R5 | Obsolete |
| 77 | is_function | 2 | R5 | Active |
| 78 | call_ext_only | 2 | R5 | Active |
| 79-86 | (old bs) | - | R7 | Obsolete |
| 87-93 | (old bs) | - | R7A/B | Obsolete |
| 94 | fclearerror | 0 | R8 | Obsolete (OTP 24) |
| 95 | fcheckerror | 1 | R8 | Obsolete (OTP 24) |
| 96 | fmove | 2 | R8 | Active |
| 97 | fconv | 2 | R8 | Active |
| 98 | fadd | 4 | R8 | Active |
| 99 | fsub | 4 | R8 | Active |
| 100 | fmul | 4 | R8 | Active |
| 101 | fdiv | 4 | R8 | Active |
| 102 | fnegate | 3 | R8 | Active |
| 103 | make_fun2 | 1 | R8 | Obsolete (OTP 24) |
| 104 | try | 2 | R10B | Active |
| 105 | try_end | 1 | R10B | Active |
| 106 | try_case | 1 | R10B | Active |
| 107 | try_case_end | 1 | R10B | Active |
| 108 | raise | 2 | R10B | Active |
| 109 | bs_init2 | 6 | R10B | Obsolete |
| 110 | bs_bits_to_bytes | 3 | R10B | Obsolete |
| 111 | bs_add | 5 | R10B | Obsolete |
| 112 | apply | 1 | R10B | Active |
| 113 | apply_last | 2 | R10B | Active |
| 114 | is_boolean | 2 | R10B | Active |
| 115 | is_function2 | 3 | R10B-6 | Active |
| 116 | bs_start_match2 | 5 | R11B | Obsolete |
| 117 | bs_get_integer2 | 7 | R11B | Active |
| 118 | bs_get_float2 | 7 | R11B | Active |
| 119 | bs_get_binary2 | 7 | R11B | Active |
| 120 | bs_skip_bits2 | 5 | R11B | Active |
| 121 | bs_test_tail2 | 3 | R11B | Active |
| 122 | bs_save2 | 2 | R11B | Obsolete |
| 123 | bs_restore2 | 2 | R11B | Obsolete |
| 124 | gc_bif1 | 5 | R11B | Active |
| 125 | gc_bif2 | 6 | R11B | Active |
| 126-127 | (bs) | - | R11B | Obsolete |
| 128 | put_literal | 2 | R11B-4 | Obsolete |
| 129 | is_bitstr | 2 | R11B-5 | Active |
| 130 | bs_context_to_binary | 1 | R12B | Obsolete |
| 131 | bs_test_unit | 3 | R12B | Active |
| 132 | bs_match_string | 4 | R12B | Active |
| 133 | bs_init_writable | 0 | R12B | Active |
| 134 | bs_append | 8 | R12B | Obsolete |
| 135 | bs_private_append | 6 | R12B | Obsolete |
| 136 | trim | 2 | R12B | Active |
| 137 | bs_init_bits | 6 | R12B | Obsolete |
| 138 | bs_get_utf8 | 5 | R12B-5 | Active |
| 139 | bs_skip_utf8 | 4 | R12B-5 | Active |
| 140 | bs_get_utf16 | 5 | R12B-5 | Active |
| 141 | bs_skip_utf16 | 4 | R12B-5 | Active |
| 142 | bs_get_utf32 | 5 | R12B-5 | Active |
| 143 | bs_skip_utf32 | 4 | R12B-5 | Active |
| 144-148 | (utf put) | - | R12B-5 | Obsolete |
| 149 | on_load | 0 | R13B03 | Active |
| 150-151 | recv_mark/set | - | R14A | Obsolete |
| 152 | gc_bif3 | 7 | R14A | Active |
| 153 | line | 1 | R15A | Active |
| 154 | put_map_assoc | 5 | R17 | Active |
| 155 | put_map_exact | 5 | R17 | Active |
| 156 | is_map | 2 | R17 | Active |
| 157 | has_map_fields | 3 | R17 | Active |
| 158 | get_map_elements | 3 | R17 | Active |
| 159 | is_tagged_tuple | 4 | OTP 20 | Active |
| 160 | build_stacktrace | 0 | OTP 21 | Active |
| 161 | raw_raise | 0 | OTP 21 | Active |
| 162 | get_hd | 2 | OTP 21 | Active |
| 163 | get_tl | 2 | OTP 21 | Active |
| 164 | put_tuple2 | 2 | OTP 22 | Active |
| 165 | bs_get_tail | 3 | OTP 22 | Active |
| 166 | bs_start_match3 | 4 | OTP 22 | Active |
| 167 | bs_get_position | 3 | OTP 22 | Active |
| 168 | bs_set_position | 2 | OTP 22 | Active |
| 169 | swap | 2 | OTP 23 | Active |
| 170 | bs_start_match4 | 4 | OTP 23 | Active |
| 171 | make_fun3 | 3 | OTP 24 | Active |
| 172 | init_yregs | 1 | OTP 24 | Active |
| 173 | recv_marker_bind | 2 | OTP 24 | Active |
| 174 | recv_marker_clear | 1 | OTP 24 | Active |
| 175 | recv_marker_reserve | 1 | OTP 24 | Active |
| 176 | recv_marker_use | 1 | OTP 24 | Active |
| 177 | bs_create_bin | 6 | OTP 25 | Active |
| 178 | call_fun2 | 3 | OTP 25 | Active |
| 179 | nif_start | 0 | OTP 25 | Active |
| 180 | badrecord | 1 | OTP 25 | Active |
| 181 | update_record | 5 | OTP 26 | Active |
| 182 | bs_match | 3 | OTP 26 | Active |
| 183 | executable_line | 2 | OTP 27 | Active |
| 184 | debug_line | 4 | OTP 28 | Active |
| 185 | bif3 | 6 | OTP 29 | Active |

---

## Appendix A: Source Files

### Instruction Definitions
- `lib/compiler/src/genop.tab` - External generic instruction definitions

### Transformation Rules & Specific Instructions
- `erts/emulator/beam/emu/ops.tab` - Interpreter transformations
- `erts/emulator/beam/jit/*/ops.tab` - JIT transformations

### Implementations
- `erts/emulator/beam/emu/instrs.tab` - Core instructions
- `erts/emulator/beam/emu/arith_instrs.tab` - Arithmetic
- `erts/emulator/beam/emu/bif_instrs.tab` - BIF calls
- `erts/emulator/beam/emu/bs_instrs.tab` - Binary syntax
- `erts/emulator/beam/emu/msg_instrs.tab` - Messaging
- `erts/emulator/beam/emu/map_instrs.tab` - Maps
- `erts/emulator/beam/emu/select_instrs.tab` - Select/case
- `erts/emulator/beam/emu/float_instrs.tab` - Floating point
- `erts/emulator/beam/emu/trace_instrs.tab` - Tracing
- `erts/emulator/beam/emu/macros.tab` - Common macros

### JIT Implementation (x86-64)
- `erts/emulator/beam/jit/x86/instr_common.cpp`
- `erts/emulator/beam/jit/x86/instr_arith.cpp`
- `erts/emulator/beam/jit/x86/instr_bs.cpp`
- `erts/emulator/beam/jit/x86/instr_*.cpp`

### JIT Implementation (ARM64)
- `erts/emulator/beam/jit/arm/instr_*.cpp`

---

## Appendix B: Glossary

| Term | Definition |
|------|------------|
| BIF | Built-In Function, implemented in C |
| Boxed | Heap-allocated term (tuple, binary, big integer, etc.) |
| CP | Continuation Pointer (return address) |
| Immediate | Term fitting in a single word (small int, atom, pid, etc.) |
| Live | Number of X registers containing valid terms |
| Match Context | Structure tracking position in binary during matching |
| Reduction | Unit of work; scheduler preempts after N reductions |
| SSMALL | Small small integer, fits in immediate |
| Tagged | Term with type tag in low bits |
