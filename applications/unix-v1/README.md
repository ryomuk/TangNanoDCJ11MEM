# TangNanoDCJ11MEM (unix-v1)
![](../../images/unixv1_jumper.jpg)

- SDメモリを使ったdiskエミュレータを作成し，UNIX V1を動かそうとしています．
- まだかなり不安定で，ちょっと修正しただけで起動しなくなるのですが，とりあえず公開することにしました．
- DMAの制御が面倒だったので、時分割された擬似dual port RAMを作ってディスクからメモリへの読み書きをしていますが、不安定なのはそのあたりが原因かもしれません。

## RF11(drum), RK11(disk)エミュレータ [sdhd.v](TangNanoDCJ11MEM_project/src/sdhd.v)
- SDメモリはファイルシステム無しの生のままで使うのでddで読み書きします．
- ブロックサイズ(BS)は512で，0〜1023ブロックがRF11，それ以降がRK11です．

##とりあえず動かすための手順
- クロック用の水晶を4MHzにする
- IRQ、EVENT用に下記ジャンパ配線をする。HALTはデバッグ用なので任意。HALTはスイッチと競合するので1kの抵抗を付けます。
```
IRQ1    --- LED1
IRQ2    --- LED2
EVENT_n --- LED4
HALT    --- 1k 抵抗 --- LED5
```
- [jserv/unix-v1](https://github.com/jserv/unix-v1) からsimh用のunix-v1環境一式をmakeして作られる images/rf0.dsk, images/rk0.dsk からsd用のイメージsd.dskを作り、sdメモリに書き込む。(書き込み先のsdメモリが/dev/sdb で正しいかちゃんと確認すること。間違えるとPCのディスクを破壊します。)
- 参考手順は下記の通り。
```
git clone https://github.com/jserv/unix-v1.git
cd unix-v1
make
dd if=/dev/zero of=sd.dsk bs=512 count=8192
dd if=images/rf0.dsk of=sd.dsk
dd if=images/rk0.dsk of=sd.dsk bs=512 seek=1024
dd if=sd.dsk of=/dev/sdb
```

## 既知のノウハウ
- single user modeの方が起動しやすいです。177570番地の値を73700にして起動するとsingle user modeになります。
- 以前に起動した環境で起動しなくなったときは、sdメモリのディスクイメージが破壊されている可能性があるので、sd.dskに書き直します。

## 既知の問題
- リセット時間を250msから350msに変えただけで起動しなったりします。
- UARTの速度を変えただけで起動しなかったりします。
- UARTが不安定で文字化けします。

## 動画
- [UNIX V1 on DEC DCJ-11 with TangNano 20K (under development)](https://www.youtube.com/watch?v=DT7xJWeF46Y)
