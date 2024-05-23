# TangNanoDCJ11MEM
Memory system and UART implemented on Tang Nano 20K for DEC DCJ11 PDP-11 Processor

This document is written mostly in Japanese. If necessary, please use a translation service such as DeepL (I recommend this) or Google.

# 概要
- PDP-11の命令セットを持つCPU「DEC DCJ11」のメモリシステムとUARTをFPGA(TangNano20K)上に実装する試みです。信号のインターフェース部分に[tangNano-5V](https://github.com/ryomuk/tangnano-5V)を使用しています。
- FPGAに実装するのはメモリやUARTなどの周辺回路部分だけで、CPU自体は本物を使用します。ソフトウェアやFPGAによるシミュレータやエミュレータではなく、本物のCPUを動かします。
- "TangNanoDCJ11"だとTangNano上にDCJ11を実装したみたいな名前になってしまうので、"MEM"を付けて"TangNanoDCJ11MEM"という名前になっています。
- UNIXを動かすにはディスクI/Oを実装する必要があるので後回し。とりあえずベアメタルで動いています。
- PC-11(Paper-Tape Reader/Punch)エミュレータでPaper-Tape BASICをロードして実行することができました．

# ハードウェア
## FPGAに実装した機能
- Initialization Sequence時のPower-Up Configuration Register設定
- メモリ 32K×16bit
- UART．TangNanoのUSB経由およびGPIO経由の2系統
- BS0, BS1は見ていません．TangNano20Kではピンが足りなかったのと，DAL[15:0]とAIO[3:0]を見ればとりあえず十分だったので．
- DAL[21:16]も見ていません．
- PC-11(Paper-Tape Reader/Punch)エミュレータを実装しました．(2024/5/22)

## ブレッドボード版
- console ODT(Octal Debug Technique)の動作確認をするところから始めて，[豊四季タイニーBASIC](https://github.com/vintagechips/ttbasic_arduino)を軽微な修正で動かせるところまで確認しました．
- クロックは18MHzで動きました．遅い方は2MHzでも動きました．
![](images/breadboard1.jpg)

## PCB版
### rev.1.0
最初に作った基板です．とりあえず動きました．
![](images/rev10.jpg)

### rev.1.1
- rev.1.0はいくつか修正箇所があったので修正しました．
- CPUが白いので基板も白くしてみました．
- CPUおよびTangNanoの電源をどこから供給するかを2箇所のジャンパで切り替えられるようにしました．詳細は回路図と基板上のシルクを見て下さい．
![](images/rev11.jpg)
#### BOM
|Reference          |Qty| Value          |Size |Memo |
|-------------------|---|----------------|-----|-----|
|C1,C2              |2	|0.33uF	         ||DECのプロセッサボードで0.33uFを使っていたので。0.1uFでもいいかもしれない。|
|C3                 |1  |47uF            |||
|C4,C5              |2  |68pF            |||
|D1                 |1  |LED             || |
|J1                 |1  |DC Jack         ||例: https://akizukidenshi.com/catalog/g/g106568/ |
|J2                 |1  |pin header      |1x02|DC Jackからの5VをTangNanoに供給するとき用。(そのときはTangNanoのUSBは外すこと)。|
|J3                 |1  |pin header      |1x03|CPUへの5VをDC JackからにするかUSB(TangNano)からにするかの選択用。|
|J4                 |1  |IC socket       |40pin DIP 600mil|TangNano5V用。1x20のpin socket 2列でも可。|
|J5,J6              |2  |pin header or socket|1x20|任意。テストや観測、実験用。|
|J7                 |1  |pin header      |1x06 L字|UART用|
|J8,J9              |2  |pin header or socket|1x30|任意。テストや観測、実験用。|
|JP1                |   |                ||任意。sctl_nとcont_nを切断したときにpin headerを立てる用。|
|R1                 |1  |100K            || 値はLEDに合わせて任意。|
|R2～16             |15 |100K            || プルアップ、プルダウン用。10～100Kで任意。入力電流がmax10μAなので大きめで良さそう。|
|R17                |1  |1M              |||
|SW1                |1  |toggle SW       ||例: https://akizukidenshi.com/catalog/g/g100300/ |
|SW2,SW3            |2  |tactile SW      |6mmxH4.3mm|例: https://akizukidenshi.com/catalog/g/g103647/ |
|U1                 |1  |DCJ11           |60pin DIP 1300mil| 1x30 の丸ピンソケット2列|
|Y1                 |1  |18MHz           |HC49|例: https://mou.sr/3WcWExh|

# PDP-11用プログラム開発環境
## クロス環境の構築
下記リンクにある情報が大変参考になりました．
- [PDP-11のgccクロスコンパイル環境の構築メモ](https://qiita.com/hifistar/items/187fd7ad780c6aa26141), by hifistar
- [PDP-11(エミュ）上でCで"Hello, World!"](https://qiita.com/hifistar/items/8eff4a73087f3a41e19f), by hifistar

これに従ってVMwareのubuntu上にクロス環境を構築し、実機で動くプログラムのバイナリを作成できました。
バージョンが古かったり，いくつか誤りもあったので下記のように修正しています。

- pkginst.shの先頭を/bin/shから/bin/bashに変更．(pushd でエラーになったので)
- ツール類のバージョンを最新か新しめの値に修正．
  - binutils-2.42
  - gmp-6.3.0
  - mpfr-4.2.1
  - mpc-1.3.1
  - gcc-11.4.0
- start.Sの"mov $0x1000, sp"はおそらく"$01000"の間違いなので修正．

## サンプルプログラム
### マンデルブロ集合表示プログラム [samples/asciiart](samples/asciiart)
- クロス環境でコンパイルできます．
- a.outからrom.vへの変換はtools/out2rom.pl を使用．かなり適当に変換してます．
- makeしてできるrom.asciiart.v をrom.vにリネームしてTangNano用プロジェクトに持って行ってビルドします。
- console ODTから，1000g で実行．UART関連がまだ不安定なので文字化けすることがあります．

## シミュレータ
実機で動かす前の動作確認に使えます．後から気がついたのですが，ubuntuだと古いバージョンならapt install simhでインストールできるようでした．
- [SimH (History Simulator)](http://simh.trailing-edge.com/)
- simhv312-4.zipをとってきてmake
- PDP11/pdp11_defs.hの「uint32 uc15_memsize;」 がリンク時にmultiple definitionのエラーになるのでextern uint32に変更したらコンパイルできました．

## PC-11(Paper-Tape Reader/Punch)エミュレータ [sdtape.v](TangNanoDCJ11MEM_project/src/sdtape.v)
- SDメモリに入れた紙テープのイメージを読み込むエミュレータです
- SDメモリはファイルシステム無しの生のままで使うのでddで読み書きします．
- パンチ機能については，BASICのSAVEで書き込むことができたのでとりあえず動いているようですがまだバグがあると思います．(SAVEコマンドの後に，SW2でflushします．)

使用例:
- 下記参考サイトから
absolute loader('ABSOLUTE-BINARY-LOADER.ptap'又は'DEC-11-L2PC-PO.ptap')と，
Paper Tape BASIC ('DEC-11-AJPB-PB.ptap')を入手し，sdメモリに書き込みます．
- /dev/xxx は生のsdメモリの場所です．(先頭のブロックから書くので数字が付いてないやつ．'fdisk -l'等で調べて下さい．)
- 間違えるとパソコンの他のファイルシステムを破壊するので厳重に注意して行って下さい．

```
cat ABSOLUTE-BINARY-LOADER.ptap DEC-11-AJPB-PB.ptap > tapeimage.dat
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

# 関連情報
## データシート等
### bitsavers
- [DCJ11 Microprocessor User's Guide](http://www.bitsavers.org/pdf/dec/pdp11/1173/EK-DCJ11-UG-PRE_J11ug_Oct83.pdf), DEC, EK-DCJ11-UG-PRE(Preliminary)
- [Index of /pdf/dec/pdp11/j11](http://bitsavers.trailing-edge.com/pdf/dec/pdp11/j11/)
- [Index of /pdf/dec/pdp11/1173](http://bitsavers.trailing-edge.com/pdf/dec/pdp11/1173/)

## 先行事例、先駆者たち
- [PDP-11/HACK](http://madrona.ca/e/pdp11hack/index.html), Brent Hilpert
- [My PDP-11 Projects](https://www.5volts.ch/pages/pdp11hack/), Peter Schranz
- [PDP11 on a breadboard A.K.A. J11 Hack](https://www.chronworks.com/J11/), Len Bayles
- [S100 Bus PDP-11 CPU Board](http://www.s100computers.com/My%20System%20Pages/PDP11%20Board/PDP11%20Board.htm), John Monahan

## 開発環境関連
- [PDP-11(エミュ）上でCで"Hello, World!"](https://qiita.com/hifistar/items/8eff4a73087f3a41e19f), hifistar
- [PDP-11のgccクロスコンパイル環境の構築メモ](https://qiita.com/hifistar/items/187fd7ad780c6aa26141), hifistar
- [SimH (History Simulator)](http://simh.trailing-edge.com/)

## Paper Tape Software関連
- [Paper Tape Archive](https://www.vaxhaven.com/Paper_Tape_Archive)
- [DEC PDP-11 Paper Tape Images](https://www.pcjs.org/software/dec/pdp11/tapes/)
- [PDP-11 Paper Tape BASIC](https://avitech.com.au/?page_id=709)
- [Learning PDP-11](https://www.learningpdp11.com/) Paper Tape BASICとboot loaderについてとても詳しく解説されています

# 更新履歴
- 2024/4/25: 初版公開
- 2024/4/25: README修正(BOM追加)
- 2024/5/5: 基板rev.1.1の写真追加．project更新．
- 2024/5/5: README.md修正(開発環境関連の情報を追加)
- 2024/5/5: samplesにasciiart を追加
- 2024/5/22: PC-11(紙テープリーダ/パンチャ)エミュレータを実装
