///
// Bootstrap Loader for Paper Tape
//
// rom.v
// to be included from the top module at the compile

`define MEM(x, y) {mem_hi[(x)>>1], mem_lo[(x)>>1]}=y

initial
begin
// Bootstrap Loader for tape
//
//                        LOAD=xx7400          ; Buffer start address
//
//                        .=LOAD+0344          ; Start address of bootstrap loader (xx7744)
//
//xx7744  016701  START:  MOV DEVICE, R1       ; Get reader CSR address
//xx7746  000026
//xx7750  012702  LOOP:   MOV #.-LOAD+2, R2    ; Get buffer pointer
//xx7752  000352                               ;   (<--- pointer to buffer)
//xx7754  005211          INC @R1              ; Enable the paper tape reader
//xx7756  105711  WAIT:   TSTB @R1             ; Wait until data available
//xx7760  100376          BPL WAIT
//xx7762  116162          MOVB 2(R1), LOAD(R2) ; Transfer byte to buffer
//xx7764  000002
//xx7766  xx7400
//xx7770  005267          INC LOOP+2           ; Increment pointer to buffer
//xx7772  177756
//xx7774  000765          BR LOOP              ; Continue reading (<--- modified branch instruction)
//xx7776  yyyyyy  DEVICE: yyyyyy               ; Paper tape reader CSR address

`MEM('o157744, 16'o016701);
`MEM('o157746, 16'o000026);
`MEM('o157750, 16'o012702);
`MEM('o157752, 16'o000352);
`MEM('o157754, 16'o005211);
`MEM('o157756, 16'o105711);
`MEM('o157760, 16'o100376);
`MEM('o157762, 16'o116162);
`MEM('o157764, 16'o000002);
`MEM('o157766, 16'o157400);
`MEM('o157770, 16'o005267);
`MEM('o157772, 16'o177756);
`MEM('o157774, 16'o000765);
`MEM('o157776, 16'o177550);
end
