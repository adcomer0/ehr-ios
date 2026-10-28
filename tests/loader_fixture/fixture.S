// Original arm64 macOS test functions. These are not game code.
.text
.p2align 2
.globl _fixture_murder
_fixture_murder:
    sub sp, sp, #32
    stp x29, x30, [sp, #16]
    add x29, sp, #16
    str w2, [x0]
    add w4, w2, #1
    str w4, [x1]
    str x0, [x3]
    str x1, [x3, #8]
    str w2, [x3, #16]
    ldp x29, x30, [sp, #16]
    add sp, sp, #32
    ret

.p2align 2
.globl _fixture_version
_fixture_version:
    movz w0, #7
    ret

// Preserve the address of an original local target, including its ASLR slide.
// A NOP prevents a linker pair relaxation from replacing this ADRP example.
.p2align 2
.globl _fixture_adrp
_fixture_adrp:
    adrp x0, Lfixture_pc_target@PAGE
    nop
    add x0, x0, Lfixture_pc_target@PAGEOFF
    ret

.p2align 2
.globl _fixture_adr
_fixture_adr:
    adr x0, Lfixture_pc_target
    ret

.p2align 2
.globl _fixture_stp
_fixture_stp:
    stp x29, x30, [sp, #-32]!
    mov x29, sp
    movz w0, #0x1234
    ldp x29, x30, [sp], #32
    ret

.p2align 2
.globl _fixture_pc_constant
_fixture_pc_constant:
Lfixture_pc_target:
    .long 0x13579bdf

// Original fixtures for additional PC-independent forms. Register choices,
// constants and memory contracts are authored here, not copied from a game.
.p2align 2
.globl _fixture_stpd
_fixture_stpd:
    stp d8, d10, [sp, #-32]!
    fmov d8, d0
    fmov d10, d1
    fadd d0, d8, d10
    ldp d8, d10, [sp], #32
    ret

// The ordinary caller checks both the floating return and callee-saved lanes
// across the handler -> original trampoline -> original function round trip.
.p2align 2
.globl _fixture_check_stpd_preserves
_fixture_check_stpd_preserves:
    stp x29, x30, [sp, #-48]!
    stp d8, d10, [sp, #16]
    fmov d8, #2.0
    fmov d10, #4.0
    fmov d0, #1.5
    fmov d1, #2.0
    mov x0, #0
    bl _fixture_stpd
    fmov d2, #2.0
    fmov d3, #4.0
    fcmp d0, d3
    cset w0, eq
    fcmp d8, d2
    cset w1, eq
    and w0, w0, w1
    fcmp d10, d3
    cset w1, eq
    and w0, w0, w1
    ldp d8, d10, [sp, #16]
    ldp x29, x30, [sp], #48
    ret

.p2align 2
.globl _fixture_ldrb
_fixture_ldrb:
    ldrb w0, [x0, #3]
    ret

.p2align 2
.globl _fixture_ldrw
_fixture_ldrw:
    ldr w9, [x0, #12]
    mov w0, w9
    ret

.p2align 2
.globl _fixture_ldrx
_fixture_ldrx:
    ldr x11, [x0, #24]
    mov x0, x11
    ret

.p2align 2
.globl _fixture_ldpw
_fixture_ldpw:
    ldp w10, w11, [x0, #-8]
    add w0, w10, w11
    ret
