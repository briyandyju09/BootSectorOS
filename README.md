# BootSectorOS

> A minimal 16-bit x86 boot-sector bootloader and interactive shell, written in NASM assembly.

## Stack

- **Language:** x86 real-mode assembly (NASM)
- **Interfaces:** BIOS interrupts — `int 0x10` (video), `int 0x16` (keyboard)
- **Tooling:** [NASM](https://www.nasm.us/) to assemble, [QEMU](https://www.qemu.org/) to run

## Description

BootSectorOS is a tiny operating environment that fits entirely inside a 512-byte boot
sector. When the BIOS loads it at `0x7C00`, it prints a welcome banner and drops you into a
simple command shell that reads and executes typed commands — no operating system, no disk
driver, just raw assembly talking to the BIOS.

## Features

- Boots directly from the boot sector (loaded at `0x7C00`; sets up segment registers and stack).
- Interactive shell with a `>` prompt and line input, including backspace handling.
- Built-in commands:
  - `echo` — print text back to the screen
  - `clear` — clear the screen (resets to text video mode 3)
  - `shutdown` — halt the CPU
- Graceful "Unknown command" fallback for unrecognised input.

## How to Build / Run

Assemble the boot sector with NASM:

```bash
nasm boot_shell.asm -f bin -o boot_shell.bin
```

Run it in an emulator (QEMU):

```bash
qemu-system-i386 -fda boot_shell.bin
```

The output is a flat 512-byte image ending in the `0xAA55` boot signature, so it can also be
written to a USB stick or floppy image to boot on real hardware.

## License

Released under the [MIT License](LICENSE).
