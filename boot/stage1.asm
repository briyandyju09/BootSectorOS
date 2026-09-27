; ============================================================================
; NanoKernel - stage1.asm  (512-byte boot sector)
; ----------------------------------------------------------------------------
; Loads the stage-2 kernel from the boot disk into 0x0000:0x8000 and jumps to
; it. Reads one sector at a time with CHS advance + retry, so it works across
; track/head boundaries on a standard 1.44MB floppy geometry (18 spt, 2 heads).
;
; Assemble: nasm boot/stage1.asm -f bin -DSTAGE2_SECTORS=<n> -o build/stage1.bin
; ============================================================================

[BITS 16]
[ORG 0x7C00]

%ifndef STAGE2_SECTORS
%define STAGE2_SECTORS 16          ; overridden by the build script
%endif

STAGE2_SEG      equ 0x0000
STAGE2_OFF      equ 0x8000
SPT             equ 18             ; sectors per track (1.44MB floppy)
HEADS           equ 2

start:
    cli
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7C00                 ; stack just below the boot code
    sti

    mov [boot_drive], dl           ; BIOS passes boot drive in DL

    mov si, msg_boot
    call print

    ; --- load stage2, one sector at a time ---
    mov bx, STAGE2_OFF             ; ES:BX = destination (ES already 0)
    mov cx, STAGE2_SECTORS         ; sectors remaining
    mov byte [cur_cyl], 0
    mov byte [cur_head], 0
    mov byte [cur_sect], 2         ; sector 1 is this boot sector

.load_loop:
    push cx
    call read_one_sector
    pop cx
    add bx, 512                    ; next destination
    ; advance CHS
    inc byte [cur_sect]
    cmp byte [cur_sect], SPT + 1
    jne .no_wrap
    mov byte [cur_sect], 1
    inc byte [cur_head]
    cmp byte [cur_head], HEADS
    jne .no_wrap
    mov byte [cur_head], 0
    inc byte [cur_cyl]
.no_wrap:
    loop .load_loop

    mov si, msg_ok
    call print

    ; hand control to stage2
    jmp STAGE2_SEG:STAGE2_OFF

; --- read a single sector (CHS in cur_*) into ES:BX, with retries ---
read_one_sector:
    mov di, 4                      ; retry count
.try:
    mov ah, 0x02                   ; read sectors
    mov al, 1                      ; one sector
    mov ch, [cur_cyl]
    mov cl, [cur_sect]
    mov dh, [cur_head]
    mov dl, [boot_drive]
    int 0x13
    jnc .done
    ; error -> reset disk and retry
    xor ah, ah
    mov dl, [boot_drive]
    int 0x13
    dec di
    jnz .try
    ; give up
    mov si, msg_err
    call print
    cli
    hlt
    jmp $
.done:
    ret

; --- print null-terminated string at DS:SI via BIOS teletype ---
print:
    mov ah, 0x0E
.next:
    lodsb
    test al, al
    jz .end
    int 0x10
    jmp .next
.end:
    ret

; --- data ---
boot_drive  db 0
cur_cyl     db 0
cur_head    db 0
cur_sect    db 2

msg_boot    db "NanoKernel: loading kernel...", 0x0D, 0x0A, 0
msg_ok      db "ok", 0x0D, 0x0A, 0
msg_err     db 0x0D, 0x0A, "disk error", 0

; --- boot signature ---
times 510 - ($ - $$) db 0
dw 0xAA55
