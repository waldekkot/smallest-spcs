; hello_snowflake_64_112.asm - 112-byte "Hello, Snowflake" ELF (NATIVE LINUX ONLY)
;
; THEORETICAL MINIMUM for 64-bit ELF on native modern Linux.
; This WILL NOT work in Docker on Mac (Rosetta/QEMU) due to header overlap tricks.
; For Docker on Mac, use hello_snowflake_64_rosetta.asm (159 bytes) instead.
;
; Build: nasm -f bin -o hello_snowflake_64_112 hello_snowflake_64_112.asm && chmod +x hello_snowflake_64_112
;
; Size breakdown:
;   ELF64 header:     64 bytes
;   Program header:   56 bytes
;   8-byte overlap:   -8 bytes
;   ─────────────────────────────
;   TOTAL MINIMUM:   112 bytes
;
; Key techniques:
;   1. All code embedded in header fields (no code after headers!)
;   2. String split: "Hello, S" in p_paddr, "nowflake" in p_align
;   3. Newline from syscall's rcx (low byte = 0x0a after first syscall)
;   4. argc from stack as stdout fd (pop rdi = 1)
;   5. Exit via int 0x80 (32-bit syscall in 64-bit mode, ebx=0 from kernel)
;   6. Backward jump encoded in e_ehsize field

BITS 64
base equ 0x10000
ORG base

ehdr:
    db 0x7f, "ELF"
    db 2, 1, 1, 0           ; 64-bit, little-endian, ELF v1

; e_ident[8-15] - ENTRY POINT CODE!
frag1:
    syscall                  ; Sets rcx = 0x1000a (RIP after syscall)
    pop rdi                  ; rdi = argc = 1 (stdout fd)
    push rcx                 ; Push newline (rcx low byte = 0x0a)
    mov eax, edi             ; rax = 1 (write syscall)
    jmp short frag2          ; Jump to next code fragment

    dw 2                     ; e_type = ET_EXEC
    dw 0x3e                  ; e_machine = x86-64

; e_version - EXIT CODE!
exit_code:
    mov al, 1                ; 32-bit exit syscall = 1
    int 0x80                 ; exit(ebx) - ebx = 0 from kernel init!

    dq frag1                 ; e_entry - points to frag1
    dq phdr - ehdr           ; e_phoff = 56

; e_shoff - STRING CONSTRUCTION CODE!
frag2:
    push qword [rcx + 0x5e]  ; Push "nowflake" from p_align
    push qword [rcx + 0x46]  ; Push "Hello, S" from p_paddr
    mov dl, 17               ; Length = 17 (16 chars + newline)

; e_flags - WRITE SYSCALL CODE!
frag3:
    push rsp
    pop rsi                  ; rsi = stack pointer (message buffer)
    syscall                  ; write(1, buf, 17)

    dw 0xdeeb                ; e_ehsize = jmp -34 (encoded as instruction: back to exit_code!)
    dw 56                    ; e_phentsize = 56

; === Program header at offset 56 (8-byte overlap with ELF header) ===
phdr:
    dd 1                     ; p_type = PT_LOAD (overlaps e_phnum = 1)
    dd 5                     ; p_flags = PF_R | PF_X
    dq 0                     ; p_offset = 0
    dq base                  ; p_vaddr = 0x10000
    db "Hello, S"            ; p_paddr = first 8 chars of string!
    dq file_end - ehdr       ; p_filesz = 112
    dq file_end - ehdr       ; p_memsz = 112
    db "nowflake"            ; p_align = last 8 chars of string!

file_end:
; Total: 112 bytes (0x70) = THEORETICAL MINIMUM for 64-bit ELF

