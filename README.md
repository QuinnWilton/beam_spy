# BeamSpy

[![CI](https://github.com/QuinnWilton/beam_spy/actions/workflows/test.yml/badge.svg)](https://github.com/QuinnWilton/beam_spy/actions/workflows/test.yml)
[![Hex.pm](https://img.shields.io/hexpm/v/beam_spy.svg)](https://hex.pm/packages/beam_spy)
[![Docs](https://img.shields.io/badge/hex-docs-blue.svg)](https://hexdocs.pm/beam_spy)

**objdump, strings, and readelf for the BEAM VM**

BeamSpy is a BEAM file analysis tool that provides commands for inspecting compiled BEAM modules.

## Features

- **Atom extraction** - Extract and filter the atom table
- **Export/Import analysis** - List module interfaces
- **Bytecode disassembly** - Human-readable assembly with opcode categorization
- **Source interleaving** - See source code alongside bytecode
- **Call graph generation** - Build DOT graphs of function calls
- **Chunk inspection** - Examine raw BEAM file structure
- **Themeable output** - Syntax highlighting with customizable themes

## Installation

```bash
git clone https://github.com/quinnwilton/beam_spy
cd beam_spy
mix deps.get && mix escript.build
```

This creates a `beam_spy` executable in the project directory.

## Quick Start

```bash
# Show module metadata
./beam_spy info Enum

# List exported functions, filtered by name
./beam_spy exports lists --filter=map

# Disassemble with source interleaving
./beam_spy disasm GenServer -f "handle_call*" --source

# Generate a call graph as SVG
./beam_spy callgraph Enum --format=dot | dot -Tsvg -o graph.svg
```

## Module Resolution

All commands accept either a file path or a module name:

```bash
# Module names (resolved automatically via code path)
./beam_spy info Enum           # Elixir module
./beam_spy info lists          # Erlang module
./beam_spy info GenServer      # Standard library

# Direct file paths
./beam_spy info ./my_module.beam
./beam_spy info /path/to/module.beam
```

## Commands Reference

| Command | Purpose |
|---------|---------|
| `atoms` | Extract atom table |
| `exports` | List exported functions |
| `imports` | List imported functions |
| `info` | Show module metadata |
| `chunks` | List/inspect BEAM chunks |
| `disasm` | Disassemble bytecode |
| `callgraph` | Build function call graph |

### atoms

Extract the atom table from a BEAM file.

```bash
./beam_spy atoms Enum
./beam_spy atoms Enum --filter=map
./beam_spy atoms Enum --format=json
```

**Options:**
| Option | Short | Description |
|--------|-------|-------------|
| `--format` | `-o` | Output format: `text`, `json` |
| `--filter` | `-F` | Filter pattern (substring, `re:regex`, or `glob:pattern`) |

### exports

List exported functions from a module.

```bash
./beam_spy exports lists
./beam_spy exports Enum --filter=map
./beam_spy exports Enum --plain    # One per line (for piping)
```

**Options:**
| Option | Short | Description |
|--------|-------|-------------|
| `--format` | `-o` | Output format: `text`, `json` |
| `--filter` | `-F` | Filter pattern |
| `--plain` | | Output plain text (one per line) |

### imports

List imported functions from a module.

```bash
./beam_spy imports GenServer
./beam_spy imports GenServer --group    # Group by module
```

**Options:**
| Option | Short | Description |
|--------|-------|-------------|
| `--format` | `-o` | Output format: `text`, `json` |
| `--filter` | `-F` | Filter pattern |
| `--group` | `-g` | Group imports by module |

### info

Show module metadata.

```bash
./beam_spy info Enum
```

**Output includes:**
- Module name and source file
- Compile time and OTP version
- MD5 checksum and file size
- Count of chunks, exports, imports, atoms

### chunks

List BEAM file chunks or dump raw chunk data.

```bash
./beam_spy chunks Enum               # List all chunks
./beam_spy chunks Enum --raw AtU8    # Hex dump of atom table
```

**Options:**
| Option | Short | Description |
|--------|-------|-------------|
| `--format` | `-o` | Output format: `text`, `json` |
| `--raw` | `-r` | Hex dump of specific chunk (e.g., `AtU8`) |

**Common chunk IDs:**
| Chunk | Description |
|-------|-------------|
| `AtU8` | Atom table (UTF-8) |
| `Code` | Bytecode |
| `StrT` | String table |
| `ImpT` | Import table |
| `ExpT` | Export table |
| `FunT` | Lambda/fun table |
| `LitT` | Literal table (compressed) |
| `Dbgi` | Debug info |
| `Docs` | Documentation |
| `Line` | Line number table |

### disasm

Disassemble BEAM bytecode into human-readable assembly.

```bash
./beam_spy disasm lists -f "reverse/1"
./beam_spy disasm Enum -f "map*" --source
./beam_spy disasm GenServer --format=json
```

**Options:**
| Option | Short | Description |
|--------|-------|-------------|
| `--format` | `-o` | Output format: `text`, `json` |
| `--function` | `-f` | Filter to specific function (supports globs) |
| `--source` | `-S` | Interleave source code with disassembly |

**Function filter patterns:**
- `map/2` - Exact match (name and arity)
- `handle_*` - Glob pattern
- `map` - Substring match

### callgraph

Build a function call graph.

```bash
./beam_spy callgraph Enum
./beam_spy callgraph Enum --format=dot | dot -Tsvg -o graph.svg
./beam_spy callgraph Enum --format=json
```

**Options:**
| Option | Short | Description |
|--------|-------|-------------|
| `--format` | `-o` | Output format: `text`, `json`, `dot` |

## Assembler Syntax Reference

The `disasm` command outputs BEAM bytecode in a human-readable assembler syntax. This section documents the syntax so you can understand the output.

### Registers

BEAM uses several register types:

| Type | Syntax | Purpose |
|------|--------|---------|
| X registers | `x(0)`, `x(1)`, ... | Arguments, return values, and temporaries |
| Y registers | `y(0)`, `y(1)`, ... | Stack frame slots (preserved across calls) |
| Float registers | `fr(0)`, `fr(1)`, ... | Floating-point operations |
| Labels | `f(19)`, `f(23)`, ... | Branch targets (failure labels) |

**X registers** are the primary working registers. `x(0)` through `x(N-1)` hold function arguments on entry. `x(0)` holds the return value.

**Y registers** are stack slots allocated with `allocate`. They persist across function calls and must be deallocated before returning.

### Atoms

Atoms are displayed with Elixir-style colon prefix:

```
:ok
:error
:handle_call
Enum                  # Module atoms may omit the colon
```

### External Function References

External function calls use the format `:module:function/arity`:

```
:erlang:error/1
:lists:reverse/2
Enum:map/2
```

### Lists

Lists use square bracket notation:

```
[]                    # Empty list
[x(0), x(1)]         # List of registers
[:ok, x(0)]          # Mixed list
```

### Map Operations

Map instructions use special syntax:

**get_map_elements** - Extract map values:
```
get_map_elements f(425), x(0), [step => x(5), last => x(4), first => x(3)]
```

**put_map_assoc/put_map_exact** - Create/update maps:
```
put_map_assoc f(0), x(1), x(2), 2, %{key: x(3), other: x(4)}
```

### Allocation Tuples

Stack allocation uses compact notation:

```
alloc(w:2)           # Allocate 2 words
alloc(w:1, fn:1)     # 1 word + 1 fun slot
alloc(w:2, fl:1)     # 2 words + 1 float slot
```

### Labels

Labels mark branch targets and function entry points:

```
  label 19:
  func_info :lists, :reverse, 1
  label 20:           # Entry point (from function header)
  test :is_nonempty_list, f(23), [x(0)]
```

The number in `f(x)` in test instructions refers to the label to jump to on failure.

### Opcode Categories

BeamSpy categorizes opcodes for syntax highlighting:

| Category | Opcodes | Description |
|----------|---------|-------------|
| **call** | `call`, `call_ext`, `call_only`, `call_fun2`, `apply`, `bif1`, `gc_bif2` | Function invocation |
| **control** | `label`, `jump`, `select_val`, `is_*` tests | Control flow |
| **data** | `move`, `swap`, `get_list`, `put_list`, `get_tuple_element` | Data manipulation |
| **stack** | `allocate`, `deallocate`, `test_heap`, `trim` | Stack management |
| **return** | `return` | Function return |
| **exception** | `try`, `catch`, `raise`, `build_stacktrace` | Exception handling |
| **error** | `func_info`, `badmatch`, `case_end` | Error generation |
| **message** | `send`, `receive`, `wait`, `timeout` | Message passing |
| **binary** | `bs_get_*`, `bs_match`, `bs_create_bin` | Binary operations |
| **float** | `fadd`, `fsub`, `fmul`, `fdiv`, `fconv` | Floating-point |
| **meta** | `line`, `executable_line` | Metadata |

### Common Instruction Patterns

**Function entry:**
```
  label 19:
  func_info :lists, :reverse, 1    # Error info (called on pattern match failure)
  label 20:                         # Actual entry point
```

**Type tests:**
```
  test :is_nonempty_list, f(23), [x(0)]    # Test x(0), jump to label 23 on failure
  test :is_nil, f(21), [x(2)]
  test :is_eq_exact, f(425), [x(2), Range]
```

**List operations:**
```
  get_list x(0), x(1), x(2)    # x(1) = hd(x(0)), x(2) = tl(x(0))
  put_list x(1), [], x(1)      # x(1) = [x(1) | []]
  put_list x(0), x(1), x(0)    # x(0) = [x(0) | x(1)]
```

**Stack management:**
```
  allocate 4, 6                # Allocate 4 Y slots, preserve 6 X regs
  test_heap 4, 2               # Ensure 4 words heap space, preserve 2 X regs
  deallocate 1                 # Free 1 Y slot
  trim 3, 1                    # Remove 3 Y slots, keep 1
```

**Function calls:**
```
  call 2, {Enum, :map_range, 4}        # Local call
  call_ext 3, :Elixir.Enum:reduce/3    # External call
  call_only 2, {Enum, :"-map/2-...", 2} # Tail call (local)
  call_ext_only 2, :lists:reverse/2     # Tail call (external)
```

### Example: lists:reverse/1

```
function reverse/1 (entry: 20)
────────────────────────────────────────────────────────
  line 15
  label 19:
  func_info :lists, :reverse, 1
  label 20:
  test :is_nonempty_list, f(23), [x(0)]
  get_list x(0), x(1), x(2)
  test :is_nonempty_list, f(22), [x(2)]
  get_list x(2), x(0), x(2)
  test :is_nil, f(21), [x(2)]
  test_heap 4, 2
  put_list x(1), [], x(1)
  put_list x(0), x(1), x(0)
  return
  label 21:
  test_heap 4, 3
  put_list x(1), [], x(1)
  put_list x(0), x(1), x(1)
  move x(2), x(0)
  line 16
  call_ext_only 2, :lists:reverse/2
  label 22:
  test :is_nil, f(19), [x(2)]
  return
  label 23:
  test :is_nil, f(19), [x(0)]
  return
```

This shows the optimized implementation:
- Labels 22, 23 handle edge cases (empty list, single element)
- Label 20 is the main entry point
- The function inlines the first two iterations of the loop for common cases
- Label 21 falls through to `reverse/2` for lists longer than 2 elements

### Source Interleaving

With `--source`, BeamSpy shows source code alongside bytecode:

```
function map/2 (entry: 420)
────────────────────────────────────────────────────────
1687 │ def map(enumerable, fun)
     │      label 419:
     │      func_info Enum, :map, 2
     │      label 420:
     │      test :is_list, f(421), [x(0)]
     │      call_only 2, {Enum, :"-map/2-lists^map/1-1-", 2}
```

**Format:**
- Line numbers appear in the left margin with a `│` border
- Source lines are shown in italic (in supported terminals)
- Bytecode is indented under the corresponding source
- Line numbers are clickable hyperlinks in supported terminals

**Distant references:**

When bytecode references lines far from the current function (e.g., inlined code), BeamSpy shows a compact reference:

```
→ map_range (line 4539)
     │      call_fun 1
```

This indicates the bytecode came from the `map_range` function at line 4539.

## Common Options

These options are available on all subcommands:

| Option | Short | Description |
|--------|-------|-------------|
| `--theme` | `-t` | Color theme to use (default: `default`) |
| `--paging` | | Paging mode: `auto`, `always`, `never` |

The `--list-themes` flag is available at the top level to list available themes.

### Environment Variables

- `NO_COLOR` - Disable all color output when set (any value)

## Output Formats

Most commands support multiple output formats:

- **text** (default) - Human-readable, styled with colors
- **json** - Machine-readable JSON
- **dot** - GraphViz DOT format (callgraph only)

```bash
./beam_spy exports Enum --format=json | jq '.[] | select(.arity == 2)'
./beam_spy callgraph Enum --format=dot | dot -Tpng -o graph.png
```

## Themes

BeamSpy supports color themes defined in TOML format. Themes are stored in `priv/themes/`.

```bash
# List available themes
./beam_spy --list-themes

# Use a specific theme
./beam_spy disasm Enum --theme=monokai
```

Theme files define colors for:
- UI elements (headers, borders, keys)
- Data types (atoms, modules, functions, numbers)
- Opcode categories (call, control, data, etc.)
- Register types (x, y, fr)

## Development

Built with AI assistance. See [CLAUDE.md](CLAUDE.md) for contribution guidelines.

## License

MIT
