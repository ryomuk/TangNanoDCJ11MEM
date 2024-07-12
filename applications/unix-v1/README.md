# TangNanoDCJ11MEM (unix-v1)
![](../../images/unixv1_jumper.jpg)

- SDメモリを使ったdiskエミュレータを作成し，UNIX V1を動かそうとしています．
- まだかなり不安定で，ちょっと修正しただけで起動しなくなるのですが，とりあえず公開することにしました．
- DMAの制御が面倒だったので、時分割された擬似dual port RAMを作ってディスクからメモリへの読み書きをしています．

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
- ~~Power up configurationにより，INITでboot loaderにジャンプするようにしています．ただし1000番地単位にしか飛べないので，173000番地にPS=340とjmp 173700を置きました．~~ 
- ~~電源ONや，FPGAへの書き込み直後はSDの読み込みに失敗するせいか，54000あたりでHALTします．もう一度INITボタンを押すと起動します．~~
- INIT時に読み込まれる Power up configuration をTang NanoのSW2で選択するようにしました．
  - SW2を押さずにINIT: console ODTが起動します．
  - SW2を押しながらINIT: 173000番地から起動します．
- ~~電源ONや，FPGAへの書き込み直後はSDの読み込みに失敗するせいか，54000あたりでHALTします．もう一度INITボタンを押すと起動します．~~
- ROM領域は書き込み禁止にはしてないので，上書きされる可能性があり，その場合はconsole ODTでboot.txtの手順で書き込みます．

## デバッグ用の機能について
- デバッグ用の機能をいくつか実装しています．詳細はtop.vを見て下さい．
### disk accessログ
- top.vの `define USR_GPIOUART_DEBUG を有効にすると使えます．
- GPIOのUARTにディスクアクセスに関する情報を出力しています．
  - 100μ秒のカウンタ，ディスク関連レジスタ，最後に読んだ命令のアドレスなどを表示しています．
### ブレークポイント
- デバッグ用レジスタDBG_REG0〜2(177760, 177762, 177764番地)に書いたアドレスの命令をフェッチしたときにHALT信号を出力する機能です．トリガ条件は下記の2種類があります．
  - (address == DBG_REG0 )
  - (address == DBG_REG1 ) の後に(address == DBG_REG2 )
### 命令ログ
  - 177700〜177716番地に，HALTする直前にフェッチしていた命令のアドレスを8つ記録しています．原因不明のHALTが起きたときの解析用です．

## 既知のノウハウ
- single user modeの方が起動しやすいです。177570番地の値を73700にして起動するとsingle user modeになります。
- 過去に起動した環境で起動しなくなったようなときは、sdメモリのディスクイメージが破壊されている可能性があるので、sd.dskに書き直します。
- 起動しにくい状態になったときは，ビットストリームをロードした直後の方が起動しやすい気がします．

## 既知の問題
- ~~とにかく不安定です．~~ 起動したりしなかったりします．よく落ちます．
- ~~リセット時間を250msから350msに変えただけで起動しなったりします。~~
- ~~UARTの速度を変えただけで起動しなかったりします．~~ 対処しました．
- ~~UARTが不安定で文字化けします．~~ 対処しました．
- ~~論理合成時に，logical loopがあるというwarningが大量に出ます．除算器の部分なのですが，特に問題は無いはずなので放置しています．~~ 非同期SR付きDFFが合成できないというのが原因のようだったので修正しました．
- ~~論理合成時に，タイミング関連で警告が大量に出ているのですが，対処方法調査中です．不安定なのはこのあたりが原因かもしれません．~~ 一応対処しました．
- ~~0710.alphaでRF,RKの制御を大幅に修正し，/usrディレクトリ(RK)でmkdirができるようになりましたが，あいかわらず不安定です．~~ 0712.alphaで解消
- ~~login時に000056でHALTする頻度が高くなりました．~~ 0712.alphaで解消(?)
- ~~login時にpasswdファイルが読めないというエラーが起きることがあります．~~ 0712.alphaで解消(?)
- ~~/usrディレクトリ(RK)でcpするとHALTすることがあります．~~ 0712.alphaで解消

## 動画
- [UNIX V1 on DEC DCJ-11 with TangNano 20K (under development)](https://www.youtube.com/watch?v=DT7xJWeF46Y)

## 更新履歴
- 2024/06/28: テスト用バージョン(TangNanoDCJ11MEM_project.0628.alpha)暫定公開．GPIOのUARTにディスクアクセスの情報を出力します．
- 2024/07/04: テスト用バージョン(0704.alpha)upload．
- 2024/07/07: テスト用バージョン(0707.alpha)upload．
- 2024/07/09: テスト用バージョン(0709.alpha)upload．
- 2024/07/10: テスト用バージョン(0710.alpha)upload．RFとRKのコマンド受付を並列化しました．
- 2024/07/12: テスト用バージョン(0712.alpha)upload．命令ログ機能追加．diskログ機能用のフラグはコメントアウトしました．