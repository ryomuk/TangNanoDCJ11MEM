// Bootstrap Loader
// rom.v
// to be included from the top module at the comple

`define MEM(x, y) {mem_hi[(x)/2], mem_lo[(x)/2]}=y

initial
begin
`MEM('o037744, 16'o016701);
`MEM('o037746, 16'o000026);
`MEM('o037750, 16'o012702);
`MEM('o037752, 16'o000352);
`MEM('o037754, 16'o005211);
`MEM('o037756, 16'o105711);
`MEM('o037760, 16'o100376);
`MEM('o037762, 16'o116162);
`MEM('o037764, 16'o000002);
`MEM('o037766, 16'o037400);
`MEM('o037770, 16'o005267);
`MEM('o037772, 16'o177756);
`MEM('o037774, 16'o000765);
`MEM('o037776, 16'o177550);
end
