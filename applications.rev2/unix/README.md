# TangNanoDCJ11MEM (unix for rev2 PCB)

![](../../images/pcb20.jpg)
[unix-v1](../../applications/unix-v1/)，[unix-v6](../../applications/unix-v6/)で必要だったパターンカットとジャンパ線を反映させた基板rev.2.0用のプロジェクトです．
FPGAのクロックをCPUからのCLK2に同期させることによってかなり安定して動くようになりました．

## 最近の話題
### 2025/09/04 (20250904.rev2pcb)公開
- rev2.0基板用のプロジェクトです．sys_clkをCLK2にしたのが大きな変更点です．
- 使い方は[unix-v1](../unix-v1/)，[unix-v6](../unix-v6/)と同じです．
- rev.1.1基板でも，CPUのCLK2を33Ω程度のダンピング抵抗をはさんでGPIO_RXに接続すれば動作します．
```
DCJ11               rev1.1基板
CLK2 ---33Ω抵抗--- GPIO_RX
```
![](../../images/CLK2_jumper.jpg)


## 更新履歴
- 2025/09/04: 20250904.pcb2
