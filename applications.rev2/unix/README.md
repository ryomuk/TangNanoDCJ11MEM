# TangNanoDCJ11MEM (unix for rev2 PCB)

![](../../images/rev22_leds.jpg)

- [unix-v1](../../applications/unix-v1/)，[unix-v6](../../applications/unix-v6/)で必要だったパターンカットとジャンパ線を反映させた基板rev2.x(最新版は2.2)用のHDLコードです．
- FPGAのクロックをCPUからのCLK2に同期させることによってかなり安定して動くようになりました．
- unix v1, v6が起動します．(SDメモリはそれぞれ別に用意する必要があります．)
  - 使い方はrev1.1基板の[unix-v1](../unix-v1/)，[unix-v6](../unix-v6/)と同じです．
    - 173000g でv1用ブートローダ起動
    - 174000g でv6用ブートローダ起動．'@'でunixと入力する．
- rev1.1基板でも，CPUのCLK2を33Ω程度のダンピング抵抗をはさんでGPIO_RXに接続すればrev2.x用のHDLコードで動作します．
```
DCJ11               rev1.1基板
CLK2 ---33Ω抵抗--- GPIO_RX
```
![](../../images/rev11_CLK2patch.jpg)

- RGB, GND, 3V3をWS2812に接続するとアドレスやデータを表示します．Aliで売られている安いLEDテープでも動作しました．

## 更新履歴
- 2025/09/04: 20250904.pcbrev2
- 2025/09/15: 20250915.pcbrev2 (ws2812モジュール修正)
- 2025/09/17: 20250917.pcbrev2 (SDメモリ無しで起動するとスタックしてリセットも効かなくなる問題を修正)
