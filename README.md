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
  - **RETRIEVE:** Read buffered transaction metadata (address, count, timestamp)
  - **PROGRAM:** Program injection patterns into VFLASH memory
  - **INSPECT:** Read back programmed pattern memory
  - **CLEAR:** Clear the capture buffer
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

This project is designed for Intel/Altera FPGAs and uses Quartus Prime for synthesis and implementation.

### Requirements

- Intel Quartus Prime (for Altera/Intel FPGAs)
- VHDL-2008 compatible simulator for verification
- Platform-specific IP cores (PLL, memory, SPI slave)

### Quartus Project Files

- `spispy.qpf` - Quartus project file
- `spispy.qsf` - Quartus settings file
- `spispy.out.sdc` - Timing constraints

## Communication SPI Protocol

The system uses a dedicated SPI slave interface (`COMM_SPI`) for external control. The protocol is command-based with the following format:

### Commands

All transactions begin with a command byte (MOSI), where bits [1:0] determine the operation:

| Command | Bits[1:0] | Operation | Response |
|---------|-----------|-----------|----------|
| **CLEAR** | `00` | Clear the capture buffer | `0xAB` confirmation |
| **RETRIEVE** | `01` | Read next captured transaction | 8 bytes of data |
| **PROGRAM** | `10` | Program injection patterns | Byte counter |
| **INSPECT** | `11` | Inspect injection pattern memory | Pattern data stream |

### Command Details

#### CLEAR (0x00)
- Clears the circular buffer of captured transactions
- Response: Single byte `0xAB` confirmation
- No additional data required

#### RETRIEVE (0x01)
- Retrieves the next captured SPI transaction from the buffer
- Response: 8 bytes containing transaction metadata
  - Bytes 0-2: 24-bit address (`READ_ADDR`)
  - Bytes 3-5: 24-bit byte count (`READ_COUNT`)
  - Bytes 6-7: 16-bit timestamp (`READ_TIME`)
- If no data is ready, returns `0xFF` for all bytes
- Automatically advances to next buffer entry

#### PROGRAM (0x02)
- Programs injection patterns into the VFLASH memory
- Response: Echo of byte counter (increments with each byte received)
- Send continuous stream of pattern data bytes via MOSI
- Transaction ends when CS# is de-asserted
- See "Patch Format" section below for data structure

#### INSPECT (0x03)
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

Injection patterns are programmed via the PROGRAM command, which streams a complete patch buffer into the device's VFLASH memory. The buffer consists of a sequence of **patch entries** (headers) followed by all replacement data.

### Entry Structure

Each patch entry header is 8 bytes:

```
Byte 0:    [S|---reserved (7 bits)---]
Bytes 1-3: Address[23:0]        (big-endian, 24-bit start address)
Bytes 4-5: Length[15:0]         (big-endian, number of bytes to match)
Bytes 6-7: Data_Offset[15:0]    (big-endian, offset to replacement data in buffer)
```

- **S (bit 7 of byte 0):** Armed flag
  - `1` = Entry is active
  - `0` = Entry is inactive/marks end of table
- **Address:** Starting address in the SPI address space to match
- **Length:** Number of bytes in the address range
- **Data_Offset:** Byte offset within the PROG buffer where replacement data begins

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
- Replacement data is fetched from `data_offset + (effective_addr - entry_addr)`
- The fetched byte replaces the normal MISO data
- `MATCH_VALID` asserts and `MATCH_DATA` provides the injection byte

### Example Patch Buffer

To inject 4 bytes at SPI address `0x0000F0` and 2 bytes at `0x000200`:

```
Complete PROGRAM buffer:

Offset 0x0000: Entry 1 Header (8 bytes)
  0x80 0x00 0x00 0xF0 0x00 0x04 0x00 0x18

Offset 0x0008: Entry 2 Header (8 bytes)
  0x80 0x00 0x02 0x00 0x00 0x02 0x00 0x1C

Offset 0x0010: Header Terminator (1 byte minimum)
  0x00

Offset 0x0011: Padding to align data (7 bytes, optional but shown for clarity)
  0x00 0x00 0x00 0x00 0x00 0x00 0x00

Offset 0x0018: Entry 1 Replacement Data (4 bytes)
  0xAA 0xBB 0xCC 0xDD

Offset 0x001C: Entry 2 Replacement Data (2 bytes)
  0x11 0x22
```

**Decoded Entry 1:**
- Armed (0x80, S=1)
- Start address: 0x0000F0
- Length: 4 bytes
- Data at buffer offset 0x0018: `[0xAA, 0xBB, 0xCC, 0xDD]`

**Decoded Entry 2:**
- Armed (0x80, S=1)
- Start address: 0x000200
- Length: 2 bytes
- Data at buffer offset 0x001C: `[0x11, 0x22]`

**Terminator:**
- Single `0x00` byte (S=0) signals end of headers
- Remaining buffer bytes are interpreted as replacement data

When the monitored SPI reads from `0x0000F0-0x0000F3`, bytes `0xAA-0xDD` are injected. When it reads from `0x000200-0x000201`, bytes `0x11, 0x22` are injected.

### Buffer Layout

The complete PROGRAM buffer structure:
1. **Active Patch Headers:** Sequential 8-byte entries (up to NUM_ENTRIES active, each with S=1)
2. **Header Terminator:** Single byte with S=0 (can be just `0x00`)
3. **Replacement Data:** All replacement data blocks referenced by Data_Offset fields

**Key Points:**
- The terminator distinguishes between headers and data
- Minimum terminator is 1 byte (`0x00`), but can include padding
- Data_Offset values must point past the terminator section
- Up to 8 active entries can be matched simultaneously (configurable via `NUM_ENTRIES` generic)
- All data is written to VFLASH on-chip memory during PROGRAM command

### Programming Flow

1. Assert CS# on COMM_SPI (low)
2. Send PROGRAM command byte (e.g., `0x02`)
3. Stream patch buffer in order:
   - All active patch headers (8 bytes each, S=1)
   - Terminator byte (`0x00`, S=0)
   - All replacement data blocks
4. De-assert CS# (high)
5. System automatically re-initializes, parses headers (stopping at S=0), and arms matching entries

**Important:** 
- Headers MUST come first, followed by the terminator, then all data
- The terminator can be as short as a single `0x00` byte
- Data_Offset values reference positions within the entire transmitted buffer
- The system reads headers sequentially until it encounters a byte with S=0

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
