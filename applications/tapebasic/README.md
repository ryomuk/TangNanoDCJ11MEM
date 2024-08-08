# TangNanoDCJ11MEM (tapebasic)
  - 二次記憶をエミュレートするために手始めに作った習作です．
  - PC11(tape reader/pucnch)エミュレータで，tape BASICを読み込んで起動します．
  - SDメモリを使う練習用に作ったものなのでとりあえず動きます程度のものです．
  - unix-v1環境用のIRQやEVENT_nのジャンパ配線があると起動しないので外して下さい．
  - UART部分のコードが古いので文字化けすることがあります．ベアメタル版と同じ修正をすると安定すると思いますが動作確認が面倒なのでやってません．
  - PDP11GUIに，console ODT経由でpaper tape softwareをロードする機能があるようなので，いろいろなpaper tape softwareを試すという目的であればベアメタルでPDP11GUIを使うことをお勧めします．

## PC-11(Paper-Tape Reader/Punch)エミュレータ [sdtape.v](TangNanoDCJ11MEM_project/src/sdtape.v)
- SDメモリに入れた紙テープのイメージを読み込むエミュレータです
- SDメモリはファイルシステム無しの生のままで使うのでddで読み書きします．
- パンチ機能については，BASICのSAVEで書き込むことができたのでとりあえず動いているようですがまだバグがあると思います．(SAVEコマンドの後に，SW2でflushします．)
- とりあえず2GBのSD(SanDisk), 16GB, 32GBのSDHC(kioxia), 64GのSDXC(SAMSUNG)で動作しました．

使用例:
- [Paper Tape Archive](https://www.vaxhaven.com/Paper_Tape_Archive)から
absolute loader('ABSOLUTE-BINARY-LOADER.ptap')と，Paper Tape BASIC ('DEC-11-AJPB-PB.ptap')を入手し，sdメモリに書き込みます．(頭の000があると読めないようで，先頭の16byteを削除しました．)
- /dev/xxx は生のsdメモリの場所です．(先頭のブロックから書くので数字が付いてないやつ．'fdisk -l'等で調べて下さい．)
- 間違えるとパソコンの他のファイルシステムを破壊するので厳重に注意して行って下さい．

```
cat ABSOLUTE-BINARY-LOADER.ptap DEC-11-AJPB-PB.ptap | dd of=tapeimage.dat bs=1 skip=16
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

# 更新履歴
- 2024/6/28: tapeimage.datの作成方法を修正

