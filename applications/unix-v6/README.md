# TangNanoDCJ11MEM (unix-v6)
![](../../images/unixv6_jumper.jpg)

[unix-v1](../unix-v1/)をベースにしてUNIX V6に必要な機能を逐次追加していく試みです．

## 最近の話題
### 2024/07/30  (0730.v6.beta, 0730a.v6.beta版公開)
- 複数disk drive(rk0, rk1, rk2, rk3,..., rk7)を実装しました．(disk_blockのbit幅を増やすだけだったので最初からやっておけば良かったのですが，UNIX V1には不要だったので…)
- [Installing UNIX v6 (PDP-11) on SIMH](https://gunkies.org/wiki/Installing_UNIX_v6_(PDP-11)_on_SIMH)の手順で作ったrk0,rk1,rk2を/, /usr/source, /usr/docにマウントしてloginできました．(下記「sd用イメージ作成手順」参照)
- tic-tac-tooやbjは動きましたが，chessはtoo largeで動かず。ccもまだ動かないのでまだ問題はありそうです．
- 電源ON時にログが大量に出る問題がありましたので，デバッグログをabortではなくbus errorに修正した0730a.v6.betaも置きました．もしかしたら不具合があるかもしれないので0730.v6.betaも残してあります．

### 2024/07/29 (0729.v6.beta版公開)
- unix-v1用とunix-v6用を別プロジェクトにしました．
- 160000台を全部つぶすのはもったいないのでRAM30KWにしました．
- ABORT_nをトライステートにして，非アサート時は'Z'にしました．
- ABORT_nとLED2は直接ジャンパせずに抵抗を入れて下さい．
- ABORT_nは双方向で，INIT時にDCJ11が'L'にアサートしていてTangNano側が'H'なので，直結だと数十mAの電流が流れてしまうことがわかりました．1KだとTangNano側のアサート時にLレベルまで下がらず，本当は470Ωぐらいにしたいのですが，立ち下がりが間に合わないようなので100Ωで対処しました．
  - → ABORT_nをtri-stateにしてアサート時以外はZにしたので，INIT時の競合は回避できています．TangNanoの出力は'Z'か'L'なので直結でも大丈夫なはずですが，念のため100Ωを入れておくようにします．

- 20240728.beta版以降でUNIX V6実験用の機能を追加しています．(とりあえず作ってみた程度のものです．)
- rkunixが ~~文字化けしながら~~ マルチユーザーで起動しました．
  - → simh用にmkconfしたカーネル(unix)も起動しました．
- 下記の場合にLED2にABORT_n(bus error)を(意図的に)出力します．
  - 177700へのread (power-up sequenceのMicrodiagnostic test 2 用)
  - ~~160000〜167777へのwrite~~
  - ~~160000〜160077~~ 170000〜170077へのread．(mainの最初のcoremap初期化ループのfuibyteをエラーにしてメモリサイズを特定するのに必要．)
- ~~160000~~ 170000〜177777までは書き込みできないROMエリアにしました．(I/Oは除く)
- RK0用ブートストラップローダー
  - RK0のblock 0 (SDメモリのblock 1024)のブートストラッププログラムを0〜776番地(256word(=512byte))にロードして0番地にジャンプします．
  - 174000〜のROMに配置したので，174000g で起動します．(詳細はrom.v参照)
- UNIX V6起動実験について
  - かんぱぱさんの [unix v6の起動にチャレンジ](https://lateral-apartment-215.notion.site/unix-v6-67b9abee6b784c4795d5094cf69c4f96) が大変参考になりました．
  - アドレス空間が18bit必要だと思っていたのですが，28KWのPDP11で動いていたとのことなので試してみることにしました．
  - メモリ容量の判定にbus errorを使っているみたいだったのでABORT_nを実装しました．
  -  DC11は実装していないので，とりあえず最小限の構成のrkunixで試してみたところ， ~~文字化けしながら~~ 起動しました． (PDP11GUI，TeraTermでデータを7bitだと文字化けしなくなりました．)
  - single userはsr(177570)=173030 ですが，マルチユーザーで起動しました．
  - イメージの作成は[Installing_UNIX_v6_(PDP-11)_on_SIMH](https://gunkies.org/wiki/Installing_UNIX_v6_(PDP-11)_on_SIMH)を参考にしています．
  - GPIO UARTの使い方を変更すると起動しなくなることがあります．デバッグ情報出力ありだけで動作確認しています．


## ジャンパ配線等
- IRQ、EVENT、CONT_n、ABORT_n用に下記ジャンパ配線をする。HALTはデバッグ用なので任意。HALTはスイッチと競合するので1kΩの抵抗を付けます。
- ABORT_nは双方向で，INIT時にDCJ11が'L'にアサートしていてTangNano側が'H'なので，直結だと数十mAの電流が流れてしまうことがわかりました．1KだとTangNano側のアサート時にLレベルまで下がらず，本当は470Ωぐらいにしたいのですが，立ち下がりが間に合わないようなので100Ωで対処しました．
  - → ABORT_nをtri-stateにしてアサート時以外はZにしたので，INIT時の競合は回避できています．TangNanoの出力は'Z'か'L'なので直結でも大丈夫なはずですが，念のため100Ωを入れておくようにします．
```
DCJ11       TangNano5V
IRQ0    --- LED0  (ttyi, ttyo用)
IRQ1    --- LED1  (drum(RF), disk(RK)用)
EVENT_n --- LED4  (clock用)
CONT_n  --- LED3  (stretched cycle用)
ABORT_n ---100Ω抵抗--- LED2 (bus error用)

HALT    --- K(1N4148)A --- LED5 (デバッグ用, 無くても可)

```

## sd用イメージ作成手順
- [Installing UNIX v6 (PDP-11) on SIMH](https://gunkies.org/wiki/Installing_UNIX_v6_(PDP-11)_on_SIMH)の手順通りにrk0,rk1,rk2を作ります．
  - ↑リンクが切れているようです．Internet Archiveに保存されてました→ [Feb.27, 2025 Installing UNIX v6 (PDP-11) on SIMH](https://web.archive.org/web/20250227030852/https://gunkies.org/wiki/Installing_UNIX_v6_(PDP-11)_on_SIMH) 
  - dc11は実装していないので，'enable multiuser'は省略しました．(mkconfには入れました．)
  - rk2で'bad free count'というエラーが出ますが，simhでも出るので気にせずそのまま．
- rk0, rk1, rk2からsd用のイメージsd.dskの作成，書き込み手順は下記の通り．
```
dd if=/dev/zero of=sd.dsk bs=512 count=1024
dd if=rk0 of=sd.dsk bs=512 seek=1024 conv=notrunc
dd if=rk1 of=sd.dsk bs=512 seek=7168 conv=notrunc
dd if=rk2 of=sd.dsk bs=512 seek=13312 conv=notrunc

sudo dd if=sd.dsk of=/dev/sdb (sdメモリが/dev/sdbで正しいかちゃんと確認すること)
```
- sdメモリのブロックとの関係は下記の通り．
  - block0〜1023はrf0用です．(V6では使いませんが，V1との互換性を考慮しました．)
```
SD memory block (512byte/block)
         0-1023: rf0 (1024 block/drive)
      1024-7167: rk0 (6144 block/drive (=256cyl*2sur*12sectors))
     7168-13311: rk1
    13312-19455: rk2
    19456-25599: rk3
    ...
```

## 既知の問題
- ccを起動すると，'Can't find /lib/c0' となります．lsでは見えるのですが．15KBあるので，メモリが足りなくてロードできないという可能性があるかも． → simh 64K MEM でも同様らしいです．
- power on時に，DCJ11からABORT_nがパルス状に出力され，デバッグ情報のログに大量に出ます．INITでも収まらないので，構わず174000gで起動すればいいようです．~~次のリリースでbus_error信号を見るように修正します．~~ → 20240730a.v6.betaが修正版です．
- 放置しているだけでtrap&panicで終了することがあります．

## 更新履歴
- 2024/07/28: 0728.beta
  - 160000番地readでbus error．(V6実験用)
- 2024/07/29: 0729.v6.beta
  - unix-v1とunix-v6のフォルダを分離．
  - ABORT_nをトライステート化．
  - RAM 30MW化．bus errorの条件変更．(170000番地readでbus error)
- 2024/07/30: 0730.v6.beta
  - 複数disk drive(rk0, rk1, rk2, rk3,...,rk7)に対応．
- 2024/07/30: 0730a.v6.beta
  - デバッグログをabortではなくbus errorに修正
