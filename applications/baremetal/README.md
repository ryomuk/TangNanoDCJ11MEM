# TangNanoDCJ11MEM (baremetal)
  - クロス環境で作成したプログラムを実行します．
  - HDLは小規模なので，いろいろ試すベースラインに最適です．

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
