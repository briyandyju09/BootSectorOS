; boot_shell.asm - A simple bootloader and shell for a 16-bit real mode environment
; Assembled with NASM: nasm boot_shell.asm -f bin -o boot_shell.bin

[ORG 0x7C00]       ; Set the origin to 0x7C00, where BIOS loads the boot sector

START:
    ; Initialize segment registers
    xor ax, ax          ; Clear AX
    mov ds, ax          ; Data segment = 0x0000
    mov es, ax          ; Extra segment = 0x0000
    mov ss, ax          ; Stack segment = 0x0000
    mov sp, 0x7C00      ; Stack pointer to the end of bootloader area

    ; Display welcome message
    call clear_screen
    call print_welcome

    ; Command loop
shell_loop:
    call prompt_user        ; Display prompt
    call get_input          ; Get user input
    call parse_command      ; Parse and execute command
    jmp shell_loop          ; Go back to command loop

; --------------------------------------------
; Helper Functions
; --------------------------------------------

print_welcome:
    mov si, welcome_msg     ; Load welcome message
    call print_string
    ret

prompt_user:
    mov si, prompt_msg      ; Display the prompt: "> "
    call print_string
    ret

get_input:
    xor di, di              ; Set the input buffer pointer to the start
    call read_line          ; Read input from the user
    ret

parse_command:
    mov si, input_buffer    ; SI points to user input

    ; Check for "echo" command
    mov di, cmd_echo
    call strcmp
    jz echo_cmd

    ; Check for "clear" command
    mov di, cmd_clear
    call strcmp
    jz clear_cmd

    ; Check for "shutdown" command
    mov di, cmd_shutdown
    call strcmp
    jz shutdown_cmd

    ; Unknown command
    mov si, unknown_cmd_msg
    call print_string
    ret

echo_cmd:
    mov si, input_buffer + 5; Skip "echo "
    call print_string        ; Echo back user input
    ret

clear_cmd:
    call clear_screen
    ret

shutdown_cmd:
    mov si, shutdown_msg
    call print_string
    cli                      ; Disable interrupts
    hlt                      ; Halt the CPU
    ret

strcmp:
    ; Compare two strings at SI and DI
    xor cx, cx
strcmp_loop:
    mov al, [si]
    mov bl, [di]
    cmp al, 0
    je strcmp_done          ; End of string
    cmp al, bl
    jne strcmp_fail         ; Strings differ
    inc si
    inc di
    jmp strcmp_loop
strcmp_done:
    xor ax, ax              ; Strings match
    ret
strcmp_fail:
    mov ax, 1               ; Strings don't match
    ret

read_line:
    xor cx, cx              ; Clear counter
    mov bx, input_buffer

read_char_loop:
    ; Wait for key press (BIOS interrupt 16h)
    mov ah, 0
    int 0x16
    cmp al, 0x0D            ; Enter key?
    je read_done
    cmp al, 0x08            ; Backspace?
    je handle_backspace
    stosb                   ; Store character
    mov ah, 0x0E            ; BIOS teletype function
    int 0x10                ; Echo typed character
    jmp read_char_loop

handle_backspace:
    cmp bx, input_buffer    ; Beginning of buffer?
    je read_char_loop
    dec bx                  ; Move back in buffer
    mov ah, 0x0E
    mov al, 0x08            ; Backspace character
    int 0x10
    mov al, ' '             ; Space to erase
    int 0x10
    mov al, 0x08            ; Move back again
    int 0x10
    jmp read_char_loop

read_done:
    mov al, 0               ; Null-terminate string
    stosb
    ret

clear_screen:
    ; BIOS service to clear screen
    mov ah, 0x00
    mov al, 0x03            ; Set video mode 3 (text mode)
    int 0x10
    ret

print_string:
    mov ah, 0x0E            ; BIOS teletype output
print_string_loop:
    lodsb                   ; Load byte from SI
    cmp al, 0
    je print_string_done
    int 0x10                ; Print character
    jmp print_string_loop
print_string_done:
    ret

; --------------------------------------------
; Data Section
; --------------------------------------------

welcome_msg db 'Welcome to the Boot Shell!', 0x0A, 0x0D, 0
prompt_msg db '> ', 0
unknown_cmd_msg db 'Unknown command', 0x0A, 0x0D, 0
shutdown_msg db 'Goodbye!', 0x0A, 0x0D, 0
input_buffer times 256 db 0

cmd_echo db 'echo', 0
cmd_clear db 'clear', 0
cmd_shutdown db 'shutdown', 0

; --------------------------------------------
; Boot signature (end of boot sector)
; --------------------------------------------

times 534 - ($ - $$) db 0   ; Fill to 510 bytes
dw 0xAA55                   ; Boot signature
