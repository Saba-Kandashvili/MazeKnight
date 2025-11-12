# Place your compiled DLL here

Name it: **mazegen.dll**

This folder should contain your compiled Wave Function Collapse DLL.

If you need to use a different name, update the path in:
`src/ffi_wrapper.lua` (line 15)

## DLL Requirements:

The DLL must export these functions:

- `uint16_t*** generateGrid(uint32_t width, uint32_t length, uint32_t height, uint32_t seed, uint32_t targetFullness)`
- `void freeGrid(uint16_t*** grid, uint32_t width, uint32_t length, uint32_t height)`

Make sure the DLL is compiled for your system:

- Windows 64-bit: Most common for modern systems
- Windows 32-bit: Older systems or specific builds
