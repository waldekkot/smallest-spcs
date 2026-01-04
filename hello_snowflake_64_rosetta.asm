; hello_snowflake_64_rosetta.asm - "Hello, Snowflake" for QEMU/Rosetta (Docker on Mac)
;
; This version uses tricks from the native 112-byte version that work on QEMU:
;   ✓ 8-byte header overlap (phdr at offset 56)
;   ✓ String split: "Hello, S" in p_paddr, "nowflake" in p_align
;   ✓ Stack-constructed string
;   ✓ argc as stdout fd (pop rdi = 1)
;   ✓ Optimized code (push/pop, push rsp/pop rsi, base register)
;
; Tricks that DON'T work on QEMU (code in header fields rejected):
;   ✗ Code in e_ident[8-15], e_version, e_shoff, e_flags
;   ✗ Backward jump in e_ehsize
;   ✗ int 0x80 for exit (segfaults in QEMU)
;
; Size: 141 bytes (vs 112 native, vs 159 without any tricks)
;
; Build: nasm -f bin -o hello_snowflake_64_rosetta hello_snowflake_64_rosetta.asm
; Test:  docker run --rm --platform linux/amd64 \
;          -v "$(pwd):/work" -w /work debian:bookworm-slim \
;          sh -c './hello_snowflake_64_rosetta; echo "Exit: $?"'

BITS 64
base equ 0x10000
ORG base

; === ELF Header (64 bytes, with 8-byte overlap at end) ===
ehdr:
    db 0x7f, "ELF"
    db 2, 1, 1, 0           ; 64-bit, little-endian, ELF v1
    dq 0                    ; e_ident[8-15] padding

    dw 2                    ; e_type = ET_EXEC
    dw 0x3e                 ; e_machine = x86-64
    dd 1                    ; e_version = 1

    dq code                 ; e_entry - points to code
    dq 56                   ; e_phoff = 56 (8-byte overlap!)

    dq 0                    ; e_shoff = 0
    dd 0                    ; e_flags = 0
    dw 64                   ; e_ehsize = 64
    dw 56                   ; e_phentsize = 56

; === Offset 56: 8-byte overlap zone ===
phdr:
    dd 1                    ; p_type = PT_LOAD / e_phnum = 1
    dd 5                    ; p_flags = R|X

; === Program header continues (unique bytes 64-111) ===
    dq 0                    ; p_offset = 0
    dq base                 ; p_vaddr
str1:
    db "Hello, S"           ; p_paddr = first 8 chars! (offset 80)
    dq filesize             ; p_filesz
    dq filesize             ; p_memsz
str2:
    db "nowflake"           ; p_align = last 8 chars! (offset 104)

; === Offset 112: CODE (optimized) ===
code:
    ; Get argc from stack as stdout fd (same trick as native!)
    pop     rdi             ; 1 byte - rdi = argc = 1 (stdout fd)
    
    ; Build "Hello, Snowflake\n" on stack
    push    0x0a            ; 2 bytes - newline
    
    ; Push strings using base register
    ; str1 is at offset 80, str2 is at offset 104 (str1 + 24)
    mov     eax, str1       ; 5 bytes - load str1 address
    push    qword [rax+24]  ; 4 bytes - push "nowflake" (str2 = str1+24)
    push    qword [rax]     ; 2 bytes - push "Hello, S"
    
    ; sys_write(1, rsp, 17) - rdi already = 1 from argc!
    mov     eax, edi        ; 2 bytes - rax = 1 (sys_write)
    push    rsp
    pop     rsi             ; 2 bytes - rsi = stack
    push    17              ; 2 bytes
    pop     rdx             ; 1 byte - rdx = 17
    syscall                 ; 2 bytes
    
    ; sys_exit(0)
    push    60              ; 2 bytes
    pop     rax             ; 1 byte - rax = 60 (sys_exit)
    xor     edi, edi        ; 2 bytes - rdi = 0
    syscall                 ; 2 bytes

filesize equ $ - $$
