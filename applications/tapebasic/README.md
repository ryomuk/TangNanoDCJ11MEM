# TangNanoDCJ11MEM (tapebasic)
  - 二次記憶をエミュレートするために手始めに作った習作です．
  - PC11(tape reader/pucnch)エミュレータで，tape BASICを読み込んで起動します．
  - SDメモリを使う練習用に作ったものなのでとりあえず動きます程度のものです．

## PC-11(Paper-Tape Reader/Punch)エミュレータ [sdtape.v](TangNanoDCJ11MEM_project/src/sdtape.v)
- SDメモリに入れた紙テープのイメージを読み込むエミュレータです
- SDメモリはファイルシステム無しの生のままで使うのでddで読み書きします．
- パンチ機能については，BASICのSAVEで書き込むことができたのでとりあえず動いているようですがまだバグがあると思います．(SAVEコマンドの後に，SW2でflushします．)

使用例:
- [Paper Tape Archive](https://www.vaxhaven.com/Paper_Tape_Archive)から
absolute loader('DEC-11-L2PC-PO.ptap')と，Paper Tape BASIC ('DEC-11-AJPB-PB.ptap')を入手し，sdメモリに書き込みます．('ABSOLUTE-BINARY-LOADER.ptap'は先頭の000のせいで読めないようでした．)
- /dev/xxx は生のsdメモリの場所です．(先頭のブロックから書くので数字が付いてないやつ．'fdisk -l'等で調べて下さい．)
- 間違えるとパソコンの他のファイルシステムを破壊するので厳重に注意して行って下さい．
- とりあえず2GBのSD(SanDisk), 16GB, 32GBのSDHC(kioxia), 64GのSDXC(SAMSUNG)で動作しました．

```
cat DEC-11-L2PC-PO.ptap DEC-11-AJPB-PB.ptap > tapeimage.dat
dd if=tapeimage.dat of=/dev/xxx
```
- TangNano20KのSDメモリスロットに入れて電源を入れ，ODT consoleから下記のように
してBASICが起動できます．

```
@37744g   ←bootstrap loader起動してabsolute loaderを読み込む
037500
@37500g   ←absolute loaderを起動してBASICを読み込む
PDP-11 BASIC, VERSION 007A
*O
READY
```

# 動画
- [PDP-11 Paper-Tape BASIC running on DCJ-11 Processor](https://www.youtube.com/watch?v=F_eFMz5ysK8)
