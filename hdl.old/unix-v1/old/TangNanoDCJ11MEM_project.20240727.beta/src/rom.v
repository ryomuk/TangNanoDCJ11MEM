///
// Bootstrap Loader for Hard Disk
//
// rom.v
// to be included from the top module at the compile

`define MEM(x, y) {mem_hi[(x)>>1], mem_lo[(x)>>1]}=y

initial
begin
// Console Switch (177570) switch register for user mode
REG_SWR = 16'o173700; // UNIX V1 multi user mode
//REG_SWR = 16'o073700; // UNIX V1 single user mode
//REG_SWR = 16'o173030; // UNIX V6 single user mode

// for UNIX V1 (load from RF)
`MEM('o173000, 16'o012737); // mov #340,@#177776 // PS=340
`MEM('o173002, 16'o000340);
`MEM('o173004, 16'o177776);
`MEM('o173006, 16'o000137); // jmp @#173700
`MEM('o173010, 16'o173700);

`MEM('o173700, 16'o012700); // mov #177472,r0
`MEM('o173702, 16'o177472);
`MEM('o173704, 16'o012740); // mov #3,-(r0)     // DAE=3
`MEM('o173706, 16'o000003);
`MEM('o173710, 16'o012740); // mov #14000,-(r0) // DAR=14000
`MEM('o173712, 16'o140000);
`MEM('o173714, 16'o012740); // mov #54000,-(r0) // CMA=54000
`MEM('o173716, 16'o054000);
`MEM('o173720, 16'o012740); // mov #-2000,-(r0) // WC=-2000
`MEM('o173722, 16'o176000);
`MEM('o173724, 16'o012740); // mov #5, -(r0)    // DCS=5
`MEM('o173726, 16'o000005);
`MEM('o173730, 16'o105710); // tstb (r0)
`MEM('o173732, 16'o002376); // bge .-2
`MEM('o173734, 16'o000137); // jmp @#54000
`MEM('o173736, 16'o054000);

// for UNIX V6 (load from RK)
`MEM('o174000, 16'o012737); // mov #340,@#177776 // PS=340
`MEM('o174002, 16'o000340);
`MEM('o174004, 16'o177776);
`MEM('o174006, 16'o000137); // jmp @#173400
`MEM('o174010, 16'o174700);

`MEM('o174700, 16'o012700); // mov #177412,r0
`MEM('o174702, 16'o177412);
`MEM('o174704, 16'o005010); // clr (r0)  // RKDA=0
`MEM('o174706, 16'o005040); // clr -(r0) // RKBA=0
`MEM('o174710, 16'o012740); // 
`MEM('o174712, 16'o177400); // mov #-400,-(r0) // WC=-400
`MEM('o174714, 16'o012740); // mov #5, -(r0)   // DCS=5
`MEM('o174716, 16'o000005);
`MEM('o174720, 16'o105710); // tstb (r0)
`MEM('o174722, 16'o002376); // bge .-2
`MEM('o174724, 16'o005007); // clr pc (jmp @#00000)
end
