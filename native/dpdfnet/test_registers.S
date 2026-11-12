/* For test_model.c on Windows. Ceva's kernels are written to the System V
 * calling convention, where a function may leave RSI, RDI and XMM6 to XMM15
 * changed; Windows says it must hand them back as they were, and the Rust
 * library, built by MSVC, counts on that across every frame. GCC saves them
 * round each call to a kernel (third_party/dpdfnet/sysv-kernels.patch); this
 * is how the test sees that it did.
 *
 *   unsigned rift_test_call(int (*fn)(void *, void *), void *a, void *b,
 *                           int *result)
 *
 * calls fn(a, b) as Windows calls a function, with every register a function
 * must keep holding a value of its own, and returns a bit for each that came
 * back changed: bits 0 to 7 RBX, RBP, RSI, RDI, R12 to R15, bits 8 to 17 XMM6
 * to XMM15, bit 18 the rounding and exception controls (MXCSR).
 *
 *   int rift_test_clobber(void *, void *)
 *
 * changes RSI, RDI, XMM6 and XMM15 and nothing else, as a kernel may: what
 * the test must be able to catch. */
    .intel_syntax noprefix
    .text

    .macro keep_gpr reg, bit
    mov rax, 0x0101010101010101 * (\bit + 0x11)
    cmp \reg, rax
    je 1f
    or r11d, 1 << \bit
1:
    .endm

    .macro set_xmm reg, n
    mov rax, 0x0101010101010101 * (\n + 0x21)
    movq \reg, rax
    punpcklqdq \reg, \reg
    .endm

    .macro keep_xmm reg, n
    mov rax, 0x0101010101010101 * (\n + 0x21)
    movq xmm0, rax
    punpcklqdq xmm0, xmm0
    pcmpeqb xmm0, \reg
    pmovmskb eax, xmm0
    cmp eax, 0xffff
    je 1f
    or r11d, 1 << (\n + 8)
1:
    .endm

    .p2align 4
    .globl rift_test_call
rift_test_call:
    push rbx
    push rbp
    push rsi
    push rdi
    push r12
    push r13
    push r14
    push r15
    /* 32 bytes for the callee, 160 for XMM6 to XMM15, 8 for `result` and
     * MXCSR; the stack is 16-aligned at the call. */
    sub rsp, 200
    movups [rsp + 32], xmm6
    movups [rsp + 48], xmm7
    movups [rsp + 64], xmm8
    movups [rsp + 80], xmm9
    movups [rsp + 96], xmm10
    movups [rsp + 112], xmm11
    movups [rsp + 128], xmm12
    movups [rsp + 144], xmm13
    movups [rsp + 160], xmm14
    movups [rsp + 176], xmm15
    mov [rsp + 192], r9
    mov r10, rcx
    mov rcx, rdx
    mov rdx, r8
    mov rbx, 0x0101010101010101 * 0x11
    mov rbp, 0x0101010101010101 * 0x12
    mov rsi, 0x0101010101010101 * 0x13
    mov rdi, 0x0101010101010101 * 0x14
    mov r12, 0x0101010101010101 * 0x15
    mov r13, 0x0101010101010101 * 0x16
    mov r14, 0x0101010101010101 * 0x17
    mov r15, 0x0101010101010101 * 0x18
    set_xmm xmm6, 0
    set_xmm xmm7, 1
    set_xmm xmm8, 2
    set_xmm xmm9, 3
    set_xmm xmm10, 4
    set_xmm xmm11, 5
    set_xmm xmm12, 6
    set_xmm xmm13, 7
    set_xmm xmm14, 8
    set_xmm xmm15, 9
    call r10
    mov r10, [rsp + 192]
    mov [r10], eax
    xor r11d, r11d
    keep_gpr rbx, 0
    keep_gpr rbp, 1
    keep_gpr rsi, 2
    keep_gpr rdi, 3
    keep_gpr r12, 4
    keep_gpr r13, 5
    keep_gpr r14, 6
    keep_gpr r15, 7
    keep_xmm xmm6, 0
    keep_xmm xmm7, 1
    keep_xmm xmm8, 2
    keep_xmm xmm9, 3
    keep_xmm xmm10, 4
    keep_xmm xmm11, 5
    keep_xmm xmm12, 6
    keep_xmm xmm13, 7
    keep_xmm xmm14, 8
    keep_xmm xmm15, 9
    /* The controls, not the flags a calculation raises. */
    stmxcsr [rsp + 196]
    mov eax, [rsp + 196]
    and eax, 0xffc0
    cmp eax, 0x1f80
    je 1f
    or r11d, 1 << 18
1:
    movups xmm6, [rsp + 32]
    movups xmm7, [rsp + 48]
    movups xmm8, [rsp + 64]
    movups xmm9, [rsp + 80]
    movups xmm10, [rsp + 96]
    movups xmm11, [rsp + 112]
    movups xmm12, [rsp + 128]
    movups xmm13, [rsp + 144]
    movups xmm14, [rsp + 160]
    movups xmm15, [rsp + 176]
    add rsp, 200
    pop r15
    pop r14
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rbp
    pop rbx
    mov eax, r11d
    ret

    .p2align 4
    .globl rift_test_clobber
rift_test_clobber:
    xor esi, esi
    xor edi, edi
    pxor xmm6, xmm6
    pxor xmm15, xmm15
    xor eax, eax
    ret
