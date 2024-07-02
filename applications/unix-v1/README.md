# TangNanoDCJ11MEM (unix-v1)
![](../../images/unixv1_jumper.jpg)

- SDメモリを使ったdiskエミュレータを作成し，UNIX V1を動かそうとしています．
- まだかなり不安定で，ちょっと修正しただけで起動しなくなるのですが，とりあえず公開することにしました．
- DMAの制御が面倒だったので、時分割された擬似dual port RAMを作ってディスクからメモリへの読み書きをしていますが、不安定なのはそのあたりが原因かもしれません。

## RF11(drum), RK11(disk)エミュレータ [sdhd.v](TangNanoDCJ11MEM_project/src/sdhd.v)
- SDメモリはファイルシステム無しの生のままで使うのでddで読み書きします．
- ブロックサイズ(BS)は512で，0〜1023ブロックがRF11，それ以降がRK11です．

## とりあえず動かすための手順
- クロック用の水晶を4MHzにする
- IRQ、EVENT用に下記ジャンパ配線をする。HALTはデバッグ用なので任意。HALTはスイッチと競合するので1kΩの抵抗を付けます。
```
DCJ11       TangNano5V
IRQ1    --- LED1
IRQ2    --- LED2
EVENT_n --- LED4
HALT    ---1kΩ抵抗--- LED5
```
- [jserv/unix-v1](https://github.com/jserv/unix-v1) にあるsimh用のunix-v1環境一式をmakeし， images/rf0.dsk, images/rk0.dsk からsd用のイメージsd.dskを作り、sdメモリに書き込む。(書き込み先のsdメモリが/dev/sdb で正しいかちゃんと確認すること。間違えるとPCのディスクを破壊します。)
- 参考手順は下記の通り。
```
git clone https://github.com/jserv/unix-v1.git
cd unix-v1
make
dd if=/dev/zero of=sd.dsk bs=512 count=8192
dd if=images/rf0.dsk of=sd.dsk
dd if=images/rk0.dsk of=sd.dsk bs=512 seek=1024
sudo dd if=sd.dsk of=/dev/sdb
```

## boot loaderについて
- simh版のboot loaderは73700番地に配置されていましたが，そこはRAM領域だし，オリジナルの資料によると173700のROM領域にあったので173700に配置しました．
- Power up configurationにより，INITでboot loaderにジャンプするようにしています．ただし1000番地単位にしか飛べないので，173000番地にPS=340とjmp 173700を置きました．
- 電源ONや，FPGAへの書き込み直後はSDの読み込みに失敗するせいか，54000あたりでHALTします．もう一度INITボタンを押すと起動します．
- ROM領域は書き込み禁止にはしてないので，上書きされる可能性があり，その場合はconsole ODTでboot.txtの手順で書き込みます．

## 既知のノウハウ
- single user modeの方が起動しやすいです。177570番地の値を73700にして起動するとsingle user modeになります。
- 過去に起動した環境で起動しなくなったようなときは、sdメモリのディスクイメージが破壊されている可能性があるので、sd.dskに書き直します。
- 起動しにくい状態になったときは，ビットストリームをロードした直後の方が起動しやすい気がします．

## 既知の問題
- とにかく不安定です．
- リセット時間を250msから350msに変えただけで起動しなったりします。
- UARTの速度を変えただけで起動しなかったりします。
- UARTが不安定で文字化けします。
- 論理合成時に，logical loopがあるというwarningが大量に出ます．除算器の部分なのですが，特に問題は無いはずなので放置しています．
- 論理合成時に，タイミング関連で警告が大量に出ているのですが，対処方法調査中です．不安定なのはこのあたりが原因かもしれません．

## 動画
- [UNIX V1 on DEC DCJ-11 with TangNano 20K (under development)](https://www.youtube.com/watch?v=DT7xJWeF46Y)

## 更新履歴
- 2024/06/28: テスト用のバージョン(TangNanoDCJ11MEM_project.0628.alpha)を暫定的に置きました．GPIOのUARTにディスクアクセスの情報を出力します．
- 2024/07/02: テスト用のバージョン(TangNanoDCJ11MEM_project.0702.alpha)を暫定的に置きました．まだかなり不安定です．
