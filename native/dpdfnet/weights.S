/* The two models' weights as Ceva ships them (models/<model>/weights.f32,
 * little-endian floats in the order its graphs read them), inside the
 * library. build.sh checks their sha256 before this is assembled, and passes
 * the folder they are in with -I. */
#ifdef _WIN32
    .section .rdata,"dr"
#else
    .section .rodata,"a",@progbits
    .hidden rift_dpdfnet_weights_2, rift_dpdfnet_weights_2_end
    .hidden rift_dpdfnet_weights_8, rift_dpdfnet_weights_8_end
#endif
    .balign 32
    .globl rift_dpdfnet_weights_2, rift_dpdfnet_weights_2_end
rift_dpdfnet_weights_2:
    .incbin "dpdfnet2_48khz_hr/weights.f32"
rift_dpdfnet_weights_2_end:
    .balign 32
    .globl rift_dpdfnet_weights_8, rift_dpdfnet_weights_8_end
rift_dpdfnet_weights_8:
    .incbin "dpdfnet8_48khz_hr/weights.f32"
rift_dpdfnet_weights_8_end:
#ifndef _WIN32
    .section .note.GNU-stack,"",@progbits
#endif
