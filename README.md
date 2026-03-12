# SPISpy

A hardware-based SPI (Serial Peripheral Interface) monitoring and injection tool implemented in VHDL for FPGA platforms. SPISpy sits transparently between a master device and a SPI flash memory, capturing transactions, detecting specific patterns, and optionally injecting modified data into the stream.

## Overview

SPISpy is designed to monitor SPI communications between a microcontroller (MCU) and flash memory in real-time. It can:

- **Passively monitor** SPI transactions between master and slave
- **Capture and buffer** SPI read operations with address and timing information
- **Pattern match** against programmable data sequences
- **Inject modified data** into MISO (Master In Slave Out) stream when patterns are detected
- **Provide external access** via a dedicated communication SPI interface

## Architecture

The system consists of several key components:

### Core Modules

- **`TOP`** (`top.vhdl`) - Top-level entity that interconnects all components and handles I/O routing
- **`SPISPY`** (`spispy.vhdl`) - Core SPI monitoring state machine that decodes SPI commands, extracts addresses, and counts data bytes
- **`INJECTOR`** (`injector.vhdl`) - Pattern matching and data injection engine with programmable entries
- **`BUFCTRL`** (`bufctrl.vhdl`) - Circular buffer controller for storing captured transaction metadata
- **`COMM_CTRL`** (`comm_ctrl.vhdl`) - Bridge between the communication SPI interface and internal control/data paths
- **`RETIMER`** (`retimer.vhdl`) - Clock domain crossing and signal retiming for SPI signals
- **`CLOCK`** (`clock.vhdl`) - Timestamp counter for transaction timing

### Supporting Components

- **`ARBITER`** (`arbiter.vhdl`) - Priority encoder for pattern matching
- **`MUX`** (`mux.vhdl`) - Multiplexer utilities
- **`RANGE_REGISTER`** (`range_register.vhdl`) - Address range matching logic
- **`MEMORY`** (`memory.vhdl`) - Dual-port RAM for transaction buffering
- **`VFLASH`** (`vflash.vhdl`) - On-chip memory for injection pattern storage
- **`PLLCLOCK`** - PLL-based clock generation for high-speed retiming

## Features

### SPI Monitoring
- Decodes SPI flash read commands (0x03)
- Extracts 24-bit addresses from SPI transactions
- Counts data bytes transferred
- Timestamps each transaction
- Buffers transaction metadata for later retrieval

### Pattern Matching & Injection
- Programmable pattern matching with up to 8 entries (configurable)
- Address range-based matching
- Byte offset matching within transactions
- Real-time data injection into MISO stream
- Non-intrusive when not armed

### Communication Interface
- Dedicated SPI slave interface (`COMM_SPI`) for external control
- Four command types:
  - **LATCH:** Read buffered transaction metadata (address, count, timestamp)
  - **PROG:** Program injection patterns into VFLASH memory
  - **DUMP:** Read back programmed pattern memory
  - **CLEAR_BUF:** Clear the capture buffer
- Internal Avalon-ST streaming interface for data transfer
- Simple command-response protocol (see Communication SPI Protocol section)

## Hardware Interfaces

### SPI Bus Connections

- **MCU_SPI_*** - Primary MCU-to-flash SPI bus (monitored)
- **SPI1_*** - Alternative SPI bus (selectable via SELECT_FLASH)
- **FLASH_SPI_*** - Connection to actual SPI flash device
- **COMM_SPI_*** - Control/communication SPI interface

### Control Signals

- **SELECT_FLASH** - Switch between MCU and SPI1 bus
- **LED_READY** - Indicates buffer has data ready
- **LED_OVERFLOW** - Indicates buffer overflow condition
- **LED_MCU_ACT** / **LED_COMM_ACT** - Activity indicators
- **GPIO_READY** - Digital ready signal output

### Debug Signals

- **DBG_SPI_*** - Debug mirror of communication SPI interface

## Building the Project

The project includes a Makefile for building with Intel Quartus:

```bash
make
```

This will synthesize the design and generate programming files.

### Requirements

- Intel Quartus Prime (for Altera/Intel FPGAs)
- VHDL-2008 compatible simulator for verification
- Platform-specific IP cores (PLL, memory, SPI slave)

## Communication SPI Protocol

The system uses a dedicated SPI slave interface (`COMM_SPI`) for external control. The protocol is command-based with the following format:

### Commands

All transactions begin with a command byte (MOSI), where bits [1:0] determine the operation:

| Command | Bits[1:0] | Operation | Response |
|---------|-----------|-----------|----------|
| **CLEAR_BUF** | `00` | Clear the capture buffer | `0xAB` confirmation |
| **LATCH** | `01` | Read next captured transaction | 8 bytes of data |
| **PROG** | `10` | Program injection patterns | Byte counter |
| **DUMP** | `11` | Dump injection pattern memory | Pattern data stream |

### Command Details

#### CLEAR_BUF (0x00, 0x04, 0x08, ...)
- Clears the circular buffer of captured transactions
- Response: Single byte `0xAB` confirmation
- No additional data required

#### LATCH (0x01, 0x05, 0x09, ...)
- Retrieves the next captured SPI transaction from the buffer
- Response: 8 bytes containing transaction metadata
  - Bytes 0-2: 24-bit address (`READ_ADDR`)
  - Bytes 3-5: 24-bit byte count (`READ_COUNT`)
  - Bytes 6-7: 16-bit timestamp (`READ_TIME`)
- If no data is ready, returns `0xFF` for all bytes
- Automatically advances to next buffer entry

#### PROG (0x02, 0x06, 0x0A, ...)
- Programs injection patterns into the VFLASH memory
- Response: Echo of byte counter (increments with each byte received)
- Send continuous stream of pattern data bytes via MOSI
- Transaction ends when CS# is de-asserted
- See "Patch Format" section below for data structure

#### DUMP (0x03, 0x07, 0x0B, ...)
- Reads back the programmed injection pattern memory
- Response stream:
  - Byte 0: Buffer size MSB
  - Byte 1: Buffer size LSB
  - Bytes 2+: Sequential memory contents
- Continues until CS# is de-asserted

### General Protocol Notes
- First byte received after CS# asserted is the command byte
- Command acknowledgment: `0xCC` is returned during command reception
- Invalid state response: `0xEE` indicates protocol error
- All multi-byte values are big-endian

## Monitored SPI Flash Protocol

The SPISPY core monitors the standard SPI Flash read command on the target bus:

- **Command:** `0x03` (Read Data)
- **Format:** `[0x03] [ADDR[23:16]] [ADDR[15:8]] [ADDR[7:0]] [DATA...]`

When this command is detected, the system:
1. Captures the 24-bit address
2. Begins counting data bytes
3. Checks for pattern matches against programmed entries
4. Injects modified data into MISO if a match is found
5. Records transaction metadata when CS# is de-asserted

## Patch Format

Injection patterns are stored in VFLASH memory and loaded at initialization. The format consists of a sequence of **patch entries**, each defining an address range and replacement data.

### Entry Structure

Each patch entry is 8 bytes, followed by variable-length replacement data:

```
Byte 0:    [S|---reserved (7 bits)---]
Bytes 1-3: Address[23:0]        (big-endian, 24-bit start address)
Bytes 4-5: Length[15:0]         (big-endian, number of bytes to match)
Bytes 6-7: Data_Address[15:0]   (big-endian, pointer to replacement data in VFLASH)
```

- **S (bit 7 of byte 0):** Armed flag
  - `1` = Entry is active
  - `0` = Entry is inactive/uninitialized
- **Address:** Starting address in the SPI address space to match
- **Length:** Number of bytes in the address range
- **Data_Address:** Pointer into VFLASH memory where replacement data is stored

### Matching Logic

For each SPI read transaction, the system calculates:
```
effective_addr = transaction_addr + byte_offset
```

An entry matches if:
```
(effective_addr >= entry_addr) && (effective_addr < entry_addr + entry_length)
```

When a match occurs:
- Replacement data is fetched from `data_address + (effective_addr - entry_addr)`
- The fetched byte replaces the normal MISO data
- `MATCH_VALID` asserts and `MATCH_DATA` provides the injection byte

### Example Patch Entry

From `bear.dump` (line 1):
```
8 0 0 f0 0 0 4 d1 26
```

Decoded as:
- **Byte 0:** `0x80` → Armed (S=1), reserved=0
- **Address:** `0x0000F0` (bytes 1-3)
- **Length:** `0x0004` (bytes 4-5) → 4 bytes
- **Data_Address:** `0xD126` (bytes 6-7)
- **Replacement data byte:** `0x26`

This entry will inject data from VFLASH location `0xD126+` when the SPI transaction reads from addresses `0x0000F0` through `0x0000F3`.

### Memory Layout

The VFLASH memory contains:
1. **Patch Table:** Sequential 8-byte entries starting at address 0
2. **Replacement Data:** Variable-length data buffers referenced by `Data_Address` fields
3. **Terminator:** First entry with S=0 marks end of table

Up to 8 active entries can be matched simultaneously (configurable via `NUM_ENTRIES` generic).

### Programming Flow

1. Assert CS# on COMM_SPI
2. Send PROG command (e.g., `0x02`)
3. Stream all patch data (entries + replacement data)
4. De-assert CS#
5. System automatically re-initializes and loads new patterns

## Use Cases

- **Firmware debugging** - Monitor code execution by tracking flash read patterns with timestamps
- **Security testing** - Inject modified code/data to test system fault handling and validation
- **Performance analysis** - Profile memory access patterns and timing with microsecond precision
- **Hardware verification** - Non-intrusive SPI bus monitoring and transaction capture
- **Bootloader modification** - Real-time patching of boot code without reflashing
- **Fault injection** - Controlled corruption of specific memory regions for robustness testing
- **Development acceleration** - Test firmware changes without reprogramming flash memory
- **Protocol analysis** - Capture and analyze SPI transaction sequences for debugging

## Project Structure

```
spispy/
├── top.vhdl              # Top-level design
├── spispy.vhdl           # SPI monitor FSM
├── injector.vhdl         # Pattern match & injection
├── bufctrl.vhdl          # Transaction buffer
├── comm_ctrl.vhdl        # Communication controller
├── retimer.vhdl          # Signal retiming
├── clock.vhdl            # Timestamp counter
├── arbiter.vhdl          # Match arbitration
├── mux.vhdl              # Multiplexer utilities
├── range_register.vhdl   # Address range logic
├── memory.vhd            # Dual-port RAM (generated)
├── vflash.vhd            # Pattern storage (generated)
├── pllclock.vhd          # PLL clock (generated)
├── comm_spi/             # SPI slave IP core
├── Makefile              # Build system
└── spispy.qsf/qpf        # Quartus project files
```

## Design Notes

- The design uses double/triple synchronizers for clock domain crossing from SPI to system clock
- All SPI signals are retimed through a high-speed clock (CLK2) to meet timing on bidirectional paths
- The buffer uses a circular structure with overflow detection
- Pattern injection is non-blocking and occurs in real-time during SPI transactions
- The system is transparent to the monitored SPI bus when not injecting data

## License

[License information to be added]

## Authors

[Author information to be added]
