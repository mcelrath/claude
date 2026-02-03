# GPU BIOS Analyzer

Analyzes GPU ROM files using specialized firmware analysis tools. Provides detailed information about GPU hardware configurations, sensor profiles, and ROM structure.

## Usage

```
/agent:rom_analyzer <command> [arguments]
```

## Commands

### `analyze`
Analyze a single ROM file.

```
/agent:rom_analyzer analyze <rom_path> [--type <analysis_type>]
```

**Arguments:**
- `rom_path`: Path to the ROM file (relative to project root)
- `--type`: Analysis type (default: summary)
  - `summary`: Basic ROM information and structure
  - `detailed`: Comprehensive analysis with all regions
  - `hardware`: Extract hardware configuration arrays
  - `power`: Power limit and configuration arrays
  - `clock`: Clock frequency configurations
  - `memory`: Memory clock and timing arrays
  - `sensors`: Fan curves and thermal profiles
  - `hash`: Hash function analysis and verification
  - `containers`: Firmware container analysis

**Examples:**
```bash
/agent:rom_analyzer analyze roms/Gigabyte.RTX5090.32768.250115.rom
/agent:rom_analyzer analyze roms/Gigabyte.RTX5090.32768.250115.rom --type hardware
/agent:rom_analyzer analyze roms/Gigabyte.RTX5090.32768.250115.rom --type sensors
```

### `compare`
Compare multiple ROM files to identify differences.

```
/agent:rom_analyzer compare <rom_path1> <rom_path2> [...]
```

**Example:**
```bash
/agent:rom_analyzer compare roms/Gigabyte.RTX5090.32768.250115.rom roms/NVIDIA.RTX4090.24576.220830.rom
```

### `list`
List all available ROM files in the roms directory.

```
/agent:rom_analyzer list
```

### `batch`
Analyze all ROM files in the roms directory.

```
/agent:rom_analyzer batch [--type <analysis_type>]
```

**Example:**
```bash
/agent:rom_analyzer batch --type hardware
```

## Output Format

The agent provides structured output including:
- **Success/Failure status** with error messages
- **ROM file information** (name, size, GPU model)
- **Analysis results** based on the specified type
- **Hardware specifications** (power limits, clock speeds, memory frequencies)
- **Sensor data** (fan curves, thermal limits, power states)
- **Container information** and ROM structure details

## Supported GPU Models

- **NVIDIA RTX 50 Series** (Blackwell): RTX 5090, RTX 5080, RTX 5070, etc.
- **NVIDIA RTX 40 Series** (Ada Lovelace): RTX 4090, RTX 4080, RTX 4070, etc.
- **NVIDIA RTX 30 Series** (Ampere): RTX 3090, RTX 3080, RTX 3070, etc.
- **AMD RX 7000 Series** (RDNA 3): RX 7900 XTX, RX 7900 XT, etc.
- **AMD RX 6000 Series** (RDNA 2): RX 6900 XT, RX 6800 XT, etc.

## Example Outputs

### Basic Analysis
```
✓ Analysis successful
ROM: Gigabyte.RTX5090.32768.250115.rom
[ROM structure and basic information]
```

### Hardware Arrays
```
✓ Analysis successful
ROM: Gigabyte.RTX5090.32768.250115.rom
All Power Arrays:
  1. Power Limit: 600W at 0x03859e
     Voltage Limit: 1.05V
     Confidence: high

All Clock Arrays:
  1. Base: 2865MHz, Boost: 3288MHz at 0x0193bd
     Difference: 423MHz
     Confidence: high
```

## Technical Capabilities

- **Pattern Recognition**: Identifies hardware configuration patterns
- **Binary Analysis**: Parses complex binary firmware structures
- **Cross-Variant Comparison**: Compares different BIOS versions
- **Integrity Verification**: Checks ROM validity and corruption
- **Performance Analysis**: Extracts optimization parameters

## Agent Integration

This agent wraps the existing GPU BIOS analysis tools:
- `bios_struct.py` - Main ROM analysis engine
- `comprehensive_rom_analysis.py` - Batch processing
- `cross_variant_analysis.py` - Variant comparison

The agent provides a clean interface to these tools while handling error cases, path resolution, and output formatting.