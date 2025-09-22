# TangNanoDCJ11MEM_project.tape (tapebasic)
- TangNano20KのSDスロットをPC11(tape reader/punch)エミュレータとして起動するHDLです．
- paper tape BASICを読み込んで起動できます．

## PC-11(Paper-Tape Reader/Punch)エミュレータ [sdtape.v](TangNanoDCJ11MEM_project.tape/src/sdtape.v)
- SDメモリに入れた紙テープのイメージを読み込むエミュレータです
- SDメモリはファイルシステム無しの生のままで使うのでddで読み書きします．
- パンチ機能については，BASICのSAVEで書き込むことができたのでとりあえず動いているようですが，SDメモリを不用意に上書きしてしまうのを避けるため，top.vで無効化してあります．
- 2GBのSD(SanDisk), 32GBのSDHC(kioxia), 64GのSDXC(kioxia, SAMSUNG)で動作しました．

使用例:
- [Paper Tape Archive](https://www.vaxhaven.com/Paper_Tape_Archive)から
absolute loader('ABSOLUTE-BINARY-LOADER.ptap')と，Paper Tape BASIC ('DEC-11-AJPB-PB.ptap')を入手し，sdメモリに書き込みます．(頭の000があると読めないようで，先頭の16byteを削除しました．)
- /dev/xxx は生のsdメモリの場所です．(先頭のブロックから書くので数字が付いてないやつ．'fdisk -l'等で調べて下さい．)
- 間違えるとパソコンの他のファイルシステムを破壊するので厳重に注意して行って下さい．

```
cat ABSOLUTE-BINARY-LOADER.ptap DEC-11-AJPB-PB.ptap | dd of=tapeimage.dat bs=1 skip=16
dd if=tapeimage.dat of=/dev/xxx
```
- 上記手順で作成したtapeimage.datを[./data](./data)に置いておきました．
- TangNano20KのSDメモリスロットに入れて電源を入れ，ODT consoleから下記のように
してBASICが起動できます．

```
@157744g   ←bootstrap loader起動してabsolute loaderを読み込む
157500
@157500g   ←absolute loaderを起動してBASICを読み込む
PDP-11 BASIC, VERSION 007A
*O         ←returnを押す(ここでいろいろ初期設定等できるらしい．)
READY
```

# 関連情報
- かんぱぱさんのページにいろいろと詳しい説明がありました．
  - [きょうのかんぱぱ「TangNanoDCJ11MEMとPDP11GUIでPDP-11 BASICを動かしてみました」](https://kanpapa.com/2024/08/tangnanodcj11mem-pdp-11-cpu-3-pdp11basic.html)

# 動画
- [PDP-11 Paper-Tape BASIC running on DCJ-11 Processor](https://www.youtube.com/watch?v=F_eFMz5ysK8)

# 更新履歴
- 2025/9/22: rev2基板用のHDL公開

