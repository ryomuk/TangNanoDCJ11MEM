    .GLOBAL start
    .GLOBAL _cstart

    .text
start:
    mov     $01000, sp
    jsr     pc, _cstart
    .end           
