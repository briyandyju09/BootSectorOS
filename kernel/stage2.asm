; ============================================================================
; NanoKernel - stage2.asm  (the mini-kernel / shell)
; ----------------------------------------------------------------------------
; Loaded at 0x0000:0x8000 by stage1. Provides a text-mode console (direct VGA
; writes at 0xB800, mirrored to COM1 for debugging), a command shell, some
; system-info commands (CPUID, BIOS E801/E820 memory), and two games.
;
; Assemble: nasm kernel/stage2.asm -f bin -o build/stage2.bin
; ============================================================================

[BITS 16]
[ORG 0x8000]

VIDEO_SEG   equ 0xB800
COLS        equ 80
ROWS        equ 25
MAXLEN      equ 256

; ----------------------------------------------------------------------------
kmain:
    cli
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7000
    sti

    mov [boot_drive], dl
    call serial_init

    mov byte [text_attr], 0x0B
    call clear_screen
    mov si, banner
    call print
    mov byte [text_attr], 0x07
    mov si, welcome
    call print

shell:
    mov byte [text_attr], 0x0A
    mov si, prompt
    call print
    mov byte [text_attr], 0x07
    mov di, cmd_buf
    call read_line
    call handle_command
    jmp shell

; ----------------------------------------------------------------------------
; Command dispatch
; ----------------------------------------------------------------------------
handle_command:
    mov si, cmd_buf
    call skip_spaces
    cmp byte [si], 0
    je .done

    mov word [arg_ptr], empty_str
    mov bx, si
.scan:
    mov al, [si]
    test al, al
    je .tokend
    cmp al, ' '
    je .space
    inc si
    jmp .scan
.space:
    mov byte [si], 0
    inc si
    call skip_spaces
    mov [arg_ptr], si
.tokend:
    mov si, bx
    call to_lower_str

    mov si, bx
    mov di, cmd_help
    call strcmp
    je do_help
    mov si, bx
    mov di, cmd_echo
    call strcmp
    je do_echo
    mov si, bx
    mov di, cmd_clear
    call strcmp
    je do_clear
    mov si, bx
    mov di, cmd_cls
    call strcmp
    je do_clear
    mov si, bx
    mov di, cmd_color
    call strcmp
    je do_color
    mov si, bx
    mov di, cmd_sysinfo
    call strcmp
    je do_sysinfo
    mov si, bx
    mov di, cmd_mem
    call strcmp
    je do_mem
    mov si, bx
    mov di, cmd_about
    call strcmp
    je do_about
    mov si, bx
    mov di, cmd_reboot
    call strcmp
    je do_reboot
    mov si, bx
    mov di, cmd_shutdown
    call strcmp
    je do_shutdown
    mov si, bx
    mov di, cmd_guess
    call strcmp
    je do_guess
    mov si, bx
    mov di, cmd_snake
    call strcmp
    je do_snake

    mov si, msg_unknown
    call print
    mov si, bx
    call print
    mov si, msg_unknown2
    call print
.done:
    ret

; ----------------------------------------------------------------------------
do_help:
    mov si, help_text
    call print
    ret

do_echo:
    mov si, [arg_ptr]
    call print
    call newline
    ret

do_clear:
    call clear_screen
    ret

do_about:
    mov byte [text_attr], 0x0B
    mov si, banner
    call print
    mov byte [text_attr], 0x07
    mov si, about_text
    call print
    ret

do_color:
    mov si, [arg_ptr]
    call parse_dec
    and al, 0x0F
    mov [text_attr], al
    mov si, msg_color
    call print
    ret

; ----------------------------------------------------------------------------
do_sysinfo:
    mov si, si_cpu
    call print
    xor eax, eax
    cpuid
    mov [vendor+0], ebx
    mov [vendor+4], edx
    mov [vendor+8], ecx
    mov byte [vendor+12], 0
    mov si, vendor
    call print
    call newline

    mov si, si_mem
    call print
    xor cx, cx
    xor dx, dx
    mov ax, 0xE801
    int 0x15
    jc .memfail
    test cx, cx
    jnz .havecxdx
    mov cx, ax
    mov dx, bx
.havecxdx:
    movzx eax, dx
    shl eax, 6
    movzx ebx, cx
    add eax, ebx
    add eax, 1024
    call print_dec32
    mov si, si_kb
    call print
    jmp .drv
.memfail:
    mov si, si_memfail
    call print
.drv:
    mov si, si_drive
    call print
    mov al, [boot_drive]
    call print_hex8
    call newline
    ret

; ----------------------------------------------------------------------------
do_mem:
    mov si, mem_hdr
    call print
    xor ebx, ebx
.loop:
    mov eax, 0xE820
    mov edx, 0x534D4150
    mov ecx, 24
    mov di, e820_buf
    int 0x15
    jc .unsupported
    cmp eax, 0x534D4150
    jne .unsupported

    push ebx
    mov eax, [e820_buf+0]
    call print_hex32
    mov si, mem_sep
    call print
    mov eax, [e820_buf+8]
    call print_hex32
    mov si, mem_sep
    call print
    mov eax, [e820_buf+16]
    call print_dec32
    mov al, [e820_buf+16]
    call print_type_name
    call newline
    pop ebx

    test ebx, ebx
    jz .done
    jmp .loop
.unsupported:
    mov si, mem_unsup
    call print
.done:
    ret

print_type_name:
    cmp al, 1
    jne .r
    mov si, mem_usable
    call print
.r:
    ret

; ----------------------------------------------------------------------------
do_reboot:
    mov si, msg_reboot
    call print
    mov cx, 0x0018
.d1:
    mov dx, 0xFFFF
.d2:
    dec dx
    jnz .d2
    loop .d1
    mov al, 0xFE
    out 0x64, al
    jmp 0xFFFF:0x0000

do_shutdown:
    mov si, msg_shutdown
    call print
    mov ax, 0x2000
    mov dx, 0x604
    out dx, ax
    mov dx, 0xB004
    out dx, ax
    mov si, msg_halt
    call print
    cli
    hlt
    jmp $

; ----------------------------------------------------------------------------
; guess: number guessing game (1..100)
; ----------------------------------------------------------------------------
do_guess:
    call rand16
    xor dx, dx
    mov bx, 100
    div bx
    mov ax, dx
    inc ax
    mov [guess_target], ax
    mov word [guess_count], 0
    mov si, guess_intro
    call print
.round:
    mov si, guess_prompt
    call print
    mov di, num_buf
    call read_line
    mov al, [num_buf]
    cmp al, 'q'
    je .quit
    mov si, num_buf
    call parse_dec
    mov bx, ax
    inc word [guess_count]
    cmp bx, [guess_target]
    je .win
    jb .low
    mov si, guess_high
    call print
    jmp .round
.low:
    mov si, guess_low
    call print
    jmp .round
.win:
    mov si, guess_win
    call print
    mov ax, [guess_count]
    call print_dec16
    mov si, guess_win2
    call print
    ret
.quit:
    mov si, guess_quit
    call print
    ret

; ----------------------------------------------------------------------------
; snake
; ----------------------------------------------------------------------------
do_snake:
    call clear_screen
    call draw_border
    mov word [snake_len], 3
    mov word [snake_dx], 1
    mov word [snake_dy], 0
    mov byte [snake_x+0], 40
    mov byte [snake_y+0], 12
    mov byte [snake_x+1], 39
    mov byte [snake_y+1], 12
    mov byte [snake_x+2], 38
    mov byte [snake_y+2], 12
    mov word [score], 0
    mov cx, 3
    xor si, si
.draw_init:
    mov al, [snake_x+si]
    mov ah, [snake_y+si]
    mov bl, '#'
    mov bh, 0x0A
    push cx
    push si
    call put_cell
    pop si
    pop cx
    inc si
    loop .draw_init
    call spawn_food
    call draw_score

.game_loop:
    ; input: serial first, then keyboard
    mov dx, 0x3FD
    in al, dx
    test al, 0x01
    jz .try_kbd
    mov dx, 0x3F8
    in al, dx
    xor ah, ah
    jmp .have_key
.try_kbd:
    mov ah, 0x01
    int 0x16
    jz .no_key
    mov ah, 0x00
    int 0x16
.have_key:
    cmp al, 0x1B
    je .quit
    cmp al, 'w'
    je .up
    cmp al, 'W'
    je .up
    cmp ah, 0x48
    je .up
    cmp al, 's'
    je .down
    cmp al, 'S'
    je .down
    cmp ah, 0x50
    je .down
    cmp al, 'a'
    je .left
    cmp al, 'A'
    je .left
    cmp ah, 0x4B
    je .left
    cmp al, 'd'
    je .right
    cmp al, 'D'
    je .right
    cmp ah, 0x4D
    je .right
    jmp .no_key
.up:
    cmp word [snake_dy], 1
    je .no_key
    mov word [snake_dx], 0
    mov word [snake_dy], -1
    jmp .no_key
.down:
    cmp word [snake_dy], -1
    je .no_key
    mov word [snake_dx], 0
    mov word [snake_dy], 1
    jmp .no_key
.left:
    cmp word [snake_dx], 1
    je .no_key
    mov word [snake_dx], -1
    mov word [snake_dy], 0
    jmp .no_key
.right:
    cmp word [snake_dx], -1
    je .no_key
    mov word [snake_dx], 1
    mov word [snake_dy], 0
.no_key:
    call tick_delay

    mov al, [snake_x+0]
    add al, [snake_dx]
    mov [new_x], al
    mov al, [snake_y+0]
    add al, [snake_dy]
    mov [new_y], al

    mov al, [new_x]
    cmp al, 0
    jle .over
    cmp al, COLS-1
    jge .over
    mov al, [new_y]
    cmp al, 0
    jle .over
    cmp al, ROWS-1
    jge .over

    mov cx, [snake_len]
    dec cx
    xor si, si
.selfchk:
    cmp cx, 0
    je .no_self
    mov al, [snake_x+si]
    cmp al, [new_x]
    jne .snext
    mov al, [snake_y+si]
    cmp al, [new_y]
    jne .snext
    jmp .over
.snext:
    inc si
    dec cx
    jmp .selfchk
.no_self:

    mov al, [new_x]
    cmp al, [food_x]
    jne .move_normal
    mov al, [new_y]
    cmp al, [food_y]
    jne .move_normal

    ; eat
    mov ax, [snake_len]
    cmp ax, MAXLEN
    jae .grow_done
    inc word [snake_len]
.grow_done:
    call shift_body
    inc word [score]
    call spawn_food
    call draw_score
    jmp .draw_head

.move_normal:
    mov si, [snake_len]
    dec si
    mov al, [snake_x+si]
    mov ah, [snake_y+si]
    mov bl, ' '
    mov bh, 0x00
    call put_cell
    call shift_body

.draw_head:
    mov al, [snake_x+0]
    mov ah, [snake_y+0]
    mov bl, '#'
    mov bh, 0x0A
    call put_cell
    jmp .game_loop

.over:
    mov si, snake_over
    call print_message_center
    mov ah, 0x00
    int 0x16
.quit:
    call clear_screen
    ret

; shift body down; new head at index 0 (snake_len already set)
shift_body:
    mov cx, [snake_len]
    dec cx
    mov si, cx
.sh:
    cmp cx, 0
    je .head
    mov di, si
    dec di
    mov al, [snake_x+di]
    mov [snake_x+si], al
    mov al, [snake_y+di]
    mov [snake_y+si], al
    dec si
    dec cx
    jmp .sh
.head:
    mov al, [new_x]
    mov [snake_x+0], al
    mov al, [new_y]
    mov [snake_y+0], al
    ret

spawn_food:
.retry:
    call rand16
    xor dx, dx
    mov bx, COLS-2
    div bx
    mov al, dl
    add al, 1
    mov [food_x], al
    call rand16
    xor dx, dx
    mov bx, ROWS-2
    div bx
    mov al, dl
    add al, 1
    mov [food_y], al
    mov cx, [snake_len]
    xor si, si
.chk:
    cmp cx, 0
    je .ok
    mov al, [snake_x+si]
    cmp al, [food_x]
    jne .n
    mov al, [snake_y+si]
    cmp al, [food_y]
    jne .n
    jmp .retry
.n:
    inc si
    dec cx
    jmp .chk
.ok:
    mov al, [food_x]
    mov ah, [food_y]
    mov bl, '*'
    mov bh, 0x0C
    call put_cell
    ret

draw_border:
    xor cx, cx
.top:
    mov al, cl
    mov ah, 0
    mov bl, '='
    mov bh, 0x08
    push cx
    call put_cell
    pop cx
    mov al, cl
    mov ah, ROWS-1
    mov bl, '='
    mov bh, 0x08
    push cx
    call put_cell
    pop cx
    inc cx
    cmp cx, COLS
    jl .top
    xor cx, cx
.side:
    mov al, 0
    mov ah, cl
    mov bl, '|'
    mov bh, 0x08
    push cx
    call put_cell
    pop cx
    mov al, COLS-1
    mov ah, cl
    mov bl, '|'
    mov bh, 0x08
    push cx
    call put_cell
    pop cx
    inc cx
    cmp cx, ROWS
    jl .side
    ret

draw_score:
    push ax
    push bx
    push cx
    push si
    push di
    mov si, score_lbl
    mov cl, 2
.lbl:
    lodsb
    test al, al
    jz .num
    mov bl, al
    mov bh, 0x0E
    mov al, cl
    mov ah, 0
    push cx
    call put_cell
    pop cx
    inc cl
    jmp .lbl
.num:
    mov ax, [score]
    mov di, num_tmp
    call utoa16
    mov si, num_tmp
.nl:
    lodsb
    test al, al
    jz .done
    mov bl, al
    mov bh, 0x0E
    mov al, cl
    mov ah, 0
    push cx
    call put_cell
    pop cx
    inc cl
    jmp .nl
.done:
    pop di
    pop si
    pop cx
    pop bx
    pop ax
    ret

; print a message starting near the middle of the screen (row 12, col 2)
print_message_center:
    mov byte [cur_x], 2
    mov byte [cur_y], 12
    mov byte [text_attr], 0x0E
    call print
    mov byte [text_attr], 0x07
    ret

; wait ~3 timer ticks (handles wraparound via subtraction)
tick_delay:
    push ax
    push bx
    push dx
    mov ah, 0x00
    int 0x1A
    mov bx, dx
.w:
    mov ah, 0x00
    int 0x1A
    mov ax, dx
    sub ax, bx
    cmp ax, 3
    jae .done
    jmp .w
.done:
    pop dx
    pop bx
    pop ax
    ret

; ----------------------------------------------------------------------------
; Console primitives
; ----------------------------------------------------------------------------
; put_cell: AL=x, AH=y, BL=char, BH=attr
put_cell:
    push ax
    push bx
    push cx
    push dx
    push di
    push es
    mov [pc_x], al
    mov [pc_y], ah
    mov [pc_ch], bl
    mov [pc_at], bh
    movzx ax, byte [pc_y]
    mov cx, COLS
    mul cx
    movzx cx, byte [pc_x]
    add ax, cx
    shl ax, 1
    mov di, ax
    mov ax, VIDEO_SEG
    mov es, ax
    mov al, [pc_ch]
    mov ah, [pc_at]
    mov [es:di], ax
    pop es
    pop di
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; putc: AL = character
putc:
    push ax
    push bx
    push cx
    push dx
    push di
    push es
    mov [putc_char], al
    mov dx, 0x3F8
    out dx, al                  ; serial mirror
    cmp al, 0x0D
    je .cr
    cmp al, 0x0A
    je .lf
    cmp al, 0x08
    je .bs
    ; normal
    movzx bx, byte [cur_y]
    mov ax, COLS
    mul bx
    movzx bx, byte [cur_x]
    add ax, bx
    shl ax, 1
    mov di, ax
    mov ax, VIDEO_SEG
    mov es, ax
    mov al, [putc_char]
    mov ah, [text_attr]
    mov [es:di], ax
    inc byte [cur_x]
    cmp byte [cur_x], COLS
    jb .upd
    mov byte [cur_x], 0
    call line_feed
    jmp .upd
.cr:
    mov byte [cur_x], 0
    jmp .upd
.lf:
    call line_feed
    jmp .upd
.bs:
    cmp byte [cur_x], 0
    je .upd
    dec byte [cur_x]
    movzx bx, byte [cur_y]
    mov ax, COLS
    mul bx
    movzx bx, byte [cur_x]
    add ax, bx
    shl ax, 1
    mov di, ax
    mov ax, VIDEO_SEG
    mov es, ax
    mov word [es:di], 0x0720
.upd:
    call move_cursor
    pop es
    pop di
    pop dx
    pop cx
    pop bx
    pop ax
    ret

line_feed:
    push ax
    inc byte [cur_y]
    cmp byte [cur_y], ROWS
    jb .done
    call scroll_up
    mov byte [cur_y], ROWS-1
.done:
    pop ax
    ret

scroll_up:
    push ax
    push cx
    push si
    push di
    push ds
    push es
    mov ax, VIDEO_SEG
    mov ds, ax
    mov es, ax
    mov si, COLS*2
    xor di, di
    mov cx, COLS*(ROWS-1)
    rep movsw
    mov di, COLS*(ROWS-1)*2
    mov cx, COLS
    mov ax, 0x0720
    rep stosw
    pop es
    pop ds
    pop di
    pop si
    pop cx
    pop ax
    ret

move_cursor:
    push ax
    push bx
    push dx
    movzx bx, byte [cur_y]
    mov ax, COLS
    mul bx
    movzx bx, byte [cur_x]
    add ax, bx
    mov bx, ax
    mov dx, 0x3D4
    mov al, 0x0F
    out dx, al
    mov dx, 0x3D5
    mov al, bl
    out dx, al
    mov dx, 0x3D4
    mov al, 0x0E
    out dx, al
    mov dx, 0x3D5
    mov al, bh
    out dx, al
    pop dx
    pop bx
    pop ax
    ret

clear_screen:
    push ax
    push cx
    push di
    push es
    mov ax, VIDEO_SEG
    mov es, ax
    xor di, di
    mov cx, COLS*ROWS
    mov ah, [text_attr]
    mov al, ' '
    rep stosw
    mov byte [cur_x], 0
    mov byte [cur_y], 0
    call move_cursor
    pop es
    pop di
    pop cx
    pop ax
    ret

print:
    push ax
    push si
.next:
    lodsb
    test al, al
    jz .done
    call putc
    jmp .next
.done:
    pop si
    pop ax
    ret

newline:
    push ax
    mov al, 0x0D
    call putc
    mov al, 0x0A
    call putc
    pop ax
    ret

; read a line from the keyboard OR the serial port (so NanoKernel can be
; driven interactively or scripted over COM1).
read_line:
    push bx
    push cx
    push dx
    mov bx, di
    xor cx, cx
.poll:
    mov dx, 0x3FD               ; COM1 line status
    in al, dx
    test al, 0x01              ; serial data ready?
    jz .kbd
    mov dx, 0x3F8
    in al, dx
    jmp .have
.kbd:
    mov ah, 0x01
    int 0x16                    ; keyboard key waiting?
    jz .poll
    xor ah, ah
    int 0x16
.have:
    cmp al, 0x0D
    je .enter
    cmp al, 0x0A
    je .enter
    cmp al, 0x08
    je .back
    cmp al, 0x7F
    je .back
    cmp al, 0x20
    jb .poll
    cmp al, 0x7E
    ja .poll
    cmp cx, 126
    jae .poll
    mov [bx], al
    inc bx
    inc cx
    call putc
    jmp .poll
.back:
    cmp cx, 0
    je .poll
    dec bx
    dec cx
    mov al, 0x08
    call putc
    jmp .poll
.enter:
    mov byte [bx], 0
    call newline
    pop dx
    pop cx
    pop bx
    ret

skip_spaces:
    cmp byte [si], ' '
    jne .d
    inc si
    jmp skip_spaces
.d:
    ret

to_lower_str:
    push si
    push ax
.l:
    mov al, [si]
    test al, al
    jz .d
    cmp al, 'A'
    jb .n
    cmp al, 'Z'
    ja .n
    add al, 32
    mov [si], al
.n:
    inc si
    jmp .l
.d:
    pop ax
    pop si
    ret

; strcmp(SI, DI) -> ZF=1 if equal
strcmp:
    push si
    push di
.c:
    mov al, [si]
    cmp al, [di]
    jne .ne
    test al, al
    jz .eq
    inc si
    inc di
    jmp .c
.eq:
    pop di
    pop si
    xor al, al
    ret
.ne:
    pop di
    pop si
    mov al, 1
    or al, al
    ret

; parse_dec(SI) -> AX
parse_dec:
    push bx
    push cx
    push dx
    xor bx, bx
.sk:
    cmp byte [si], ' '
    jne .p
    inc si
    jmp .sk
.p:
    mov al, [si]
    cmp al, '0'
    jb .done
    cmp al, '9'
    ja .done
    sub al, '0'
    movzx cx, al
    mov ax, bx
    mov dx, 10
    mul dx
    add ax, cx
    mov bx, ax
    inc si
    jmp .p
.done:
    mov ax, bx
    pop dx
    pop cx
    pop bx
    ret

; utoa16: AX -> string at DI (null-terminated)
utoa16:
    push ax
    push bx
    push cx
    push dx
    push di
    mov bx, 10
    xor cx, cx
.dv:
    xor dx, dx
    div bx
    add dl, '0'
    push dx
    inc cx
    test ax, ax
    jnz .dv
.wr:
    pop dx
    mov [di], dl
    inc di
    loop .wr
    mov byte [di], 0
    pop di
    pop dx
    pop cx
    pop bx
    pop ax
    ret

print_dec16:
    push si
    push di
    mov di, num_tmp
    call utoa16
    mov si, num_tmp
    call print
    pop di
    pop si
    ret

; print_dec32: EAX
print_dec32:
    push eax
    push ebx
    push ecx
    push edx
    push si
    push di
    mov ebx, 10
    xor cx, cx
.dv:
    xor edx, edx
    div ebx
    add dl, '0'
    push dx
    inc cx
    test eax, eax
    jnz .dv
    mov di, num_tmp
.wr:
    pop dx
    mov [di], dl
    inc di
    loop .wr
    mov byte [di], 0
    mov si, num_tmp
    call print
    pop di
    pop si
    pop edx
    pop ecx
    pop ebx
    pop eax
    ret

; print_hex8: AL
print_hex8:
    push ax
    push cx
    mov cl, al
    shr al, 4
    call .nib
    mov al, cl
    and al, 0x0F
    call .nib
    pop cx
    pop ax
    ret
.nib:
    and al, 0x0F
    cmp al, 10
    jb .dig
    add al, 'A'-10
    jmp .pc
.dig:
    add al, '0'
.pc:
    call putc
    ret

; print_hex32: EAX (8 digits, MSB first)
print_hex32:
    push eax
    push cx
    mov cx, 8
.l:
    rol eax, 4
    push eax
    and al, 0x0F
    cmp al, 10
    jb .d
    add al, 'A'-10
    jmp .p
.d:
    add al, '0'
.p:
    call putc
    pop eax
    dec cx
    jnz .l
    pop cx
    pop eax
    ret

; rand16 -> AX (LCG seeded by the BIOS timer)
rand16:
    push cx
    push dx
    mov ah, 0x00
    int 0x1A
    mov cx, dx
    mov ax, [rng_state]
    mov dx, 25173
    mul dx
    add ax, 13849
    add ax, cx
    mov [rng_state], ax
    pop dx
    pop cx
    ret

serial_init:
    push ax
    push dx
    mov dx, 0x3F9
    xor al, al
    out dx, al
    mov dx, 0x3FB
    mov al, 0x80
    out dx, al
    mov dx, 0x3F8
    mov al, 0x03
    out dx, al
    mov dx, 0x3F9
    xor al, al
    out dx, al
    mov dx, 0x3FB
    mov al, 0x03
    out dx, al
    mov dx, 0x3FA
    mov al, 0xC7
    out dx, al
    mov dx, 0x3FC
    mov al, 0x0B
    out dx, al
    pop dx
    pop ax
    ret

; ----------------------------------------------------------------------------
; Data
; ----------------------------------------------------------------------------
boot_drive   db 0
text_attr    db 0x07
cur_x        db 0
cur_y        db 0
rng_state    dw 0x1234
pc_x         db 0
pc_y         db 0
pc_ch        db 0
pc_at        db 0
putc_char    db 0
arg_ptr      dw 0
empty_str    db 0

guess_target dw 0
guess_count  dw 0

snake_len    dw 0
snake_dx     dw 0
snake_dy     dw 0
score        dw 0
food_x       db 0
food_y       db 0
new_x        db 0
new_y        db 0

banner:
    db 0x0D,0x0A
    db "===============================",0x0D,0x0A
    db "     N a n o K e r n e l       ",0x0D,0x0A
    db "   a tiny x86 boot-up OS  v1.0 ",0x0D,0x0A
    db "===============================",0x0D,0x0A,0
welcome:
    db "Two-stage 16-bit real-mode OS.",0x0D,0x0A
    db "Type 'help' for commands.",0x0D,0x0A,0
prompt:
    db "nano> ",0

help_text:
    db 0x0D,0x0A,"Commands:",0x0D,0x0A
    db "  help            show this help",0x0D,0x0A
    db "  echo <text>     print text",0x0D,0x0A
    db "  clear | cls     clear the screen",0x0D,0x0A
    db "  color <0-15>    set text colour",0x0D,0x0A
    db "  sysinfo         CPU vendor + memory size",0x0D,0x0A
    db "  mem             BIOS E820 memory map",0x0D,0x0A
    db "  guess           number-guessing game",0x0D,0x0A
    db "  snake           play snake (WASD/arrows, ESC quits)",0x0D,0x0A
    db "  about           about NanoKernel",0x0D,0x0A
    db "  reboot          restart the machine",0x0D,0x0A
    db "  shutdown        power off (QEMU)",0x0D,0x0A,0

about_text:
    db 0x0D,0x0A,"NanoKernel boots from a 512-byte boot sector into a",0x0D,0x0A
    db "second-stage shell, all written in NASM x86 assembly.",0x0D,0x0A
    db "Author: Briyan George Dyju",0x0D,0x0A,0

msg_unknown  db "unknown command: ",0
msg_unknown2 db "  (type 'help')",0x0D,0x0A,0
msg_color    db "colour set",0x0D,0x0A,0

si_cpu       db 0x0D,0x0A,"CPU: ",0
si_mem       db "RAM: ",0
si_kb        db " KB",0x0D,0x0A,0
si_memfail   db "(memory query failed)",0x0D,0x0A,0
si_drive     db "Boot drive: 0x",0

mem_hdr      db 0x0D,0x0A,"E820 memory map (base / length / type):",0x0D,0x0A,0
mem_sep      db "  ",0
mem_unsup    db "E820 not supported by BIOS",0x0D,0x0A,0
mem_usable   db " Usable",0

msg_reboot   db 0x0D,0x0A,"Rebooting...",0x0D,0x0A,0
msg_shutdown db 0x0D,0x0A,"Shutting down...",0x0D,0x0A,0
msg_halt     db "System halted - you can close the emulator.",0x0D,0x0A,0

guess_intro  db 0x0D,0x0A,"I'm thinking of a number between 1 and 100.",0x0D,0x0A,"(type q to quit)",0x0D,0x0A,0
guess_prompt db "your guess: ",0
guess_high   db "too high!",0x0D,0x0A,0
guess_low    db "too low!",0x0D,0x0A,0
guess_win    db 0x0D,0x0A,"correct! you got it in ",0
guess_win2   db " guesses.",0x0D,0x0A,0
guess_quit   db "bye!",0x0D,0x0A,0

score_lbl    db "Score: ",0
snake_over   db "GAME OVER - press any key",0

; command literals (lowercase)
cmd_help     db "help",0
cmd_echo     db "echo",0
cmd_clear    db "clear",0
cmd_cls      db "cls",0
cmd_color    db "color",0
cmd_sysinfo  db "sysinfo",0
cmd_mem      db "mem",0
cmd_about    db "about",0
cmd_reboot   db "reboot",0
cmd_shutdown db "shutdown",0
cmd_guess    db "guess",0
cmd_snake    db "snake",0

; buffers
cmd_buf      times 128 db 0
num_buf      times 128 db 0
num_tmp      times 16  db 0
vendor       times 16  db 0
e820_buf     times 24  db 0

snake_x      times MAXLEN db 0
snake_y      times MAXLEN db 0
