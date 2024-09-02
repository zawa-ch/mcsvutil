# Profile format v1

mcsvutilsで使用されるプロファイルデータのフォーマット

version: 1

## ファイル形式

プロファイルの形式としてJSONを用います。
ルートをオブジェクトとし、その内部に必要な要素を記述することでプロファイルを形成します。

## プロファイルのオブジェクト構造

- `version`: number required = `1`  
	プロファイルのバージョン情報。  
	プロファイル読み出しのときは最初に読み込み、対応バージョンと一致していることを確認します。  
	要素が存在しない、もしくは型が異なる場合はエラーとなります。  
- `name`: string required  
	プロファイルの名前。  
	minecraftサーバーを操作するときにそのインスタンスを一意に識別するために使用されます。  
	要素が存在しない、型が異なる、もしくは空文字列の場合はエラーとなります。  
- `execute`: string required  
	実行されるjarファイルのパス。  
	要素が存在しない、型が異なる、もしくは空文字列の場合はエラーとなります。  
- `options`: array  
	java実行時のオプション引数。  
	- (elements): string  
- `args`: array  
	実行されるjarに渡される引数。  
	- (elements): string  
- `cwd`: string | null  
	実行時の作業ディレクトリ。  
	要素が存在しない場合、コマンド実行時のディレクトリを作業ディレクトリにします。  
	型が異なる場合は内容が空として扱われます。  
- `javapath`: string | null  
	実行するjavaの実行パス。
	存在しない場合、デフォルトで`java`が呼び出されます。
	型が異なる場合は内容が空として扱われます。  
- `owner`: string | null  
	実行時のユーザー。  
	この要素が存在し、異なるユーザーからこのプロファイルのインスタンスに対して操作を行う場合は`sudo`によるユーザー切替が行われます。  
	型が異なる場合は内容が空として扱われます。  

## プロファイルとして有効なデータの例

```json
{"version":1,"name":"mcserver","execute":"server.jar","options":[],"args":["--nogui"],"cwd":null,"javapath":null,"owner":null}
```
