# NanoKernel
NASM ?= nasm
QEMU ?= qemu-system-i386
IMG  := build/nanokernel.img

.PHONY: all run clean

all:
	NASM=$(NASM) bash build.sh

run: all
	$(QEMU) -drive file=$(IMG),format=raw,if=floppy

clean:
	rm -rf build
