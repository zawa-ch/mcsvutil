# Image repository format v2

mcsvutilsで使用されるイメージリポジトリのフォーマット

version: 2

## 形式

イメージリポジトリは、特定のディレクトリをルートとするディレクトリ構造です。

### ディレクトリ構造

- ...`/`  
	イメージリポジトリのルートディレクトリです。  
	このディレクトリ以下はすべてmcsvutilsによって管理されます。  
	一部のコマンドによって、リポジトリの内容に関連しないファイルはすべて削除されます。  
	このディレクトリ以下の手動でのファイル操作は推奨されません。
	- `repository.json`  
		IDとそれに紐付けられたイメージファイル、タグの情報を格納します。
	- {ID}  
		IDに紐付けられたイメージファイルを格納するためのディレクトリです。
		- {ファイル名}`.jar`  
			格納される Minecraft サーバーjarファイルです。

### `repository.json` オブジェクト構造

- `@context`: object required  
	このJSONのオブジェクト型情報。  
	リポジトリ読み出しのときは最初に読み込み、内容が既定値と一致していることを確認します。  
	要素が存在しない、型が異なる、もしくは内容が一致しない場合はエラーとなります。  
	- `name`: string required = `"mcsvutils.repository"`  
	- `version`: number required = `2`
- `images`: array required  
	リポジトリ内のイメージのリスト。
	- (elements): object
		- `id`: string required  
			イメージID。  
			`images`の要素内で一意である必要があります。
		- `path`: string required  
			イメージの実体が存在するパス。  
			イメージリポジトリのルートを基点とした相対パスで表されます。
		- `size`: number | null  
			イメージのファイルサイズ。  
			実行時にはファイルのサイズを確認し、一致していることを確認します。
		- `sha1`: string | null  
			イメージのSHA-1ハッシュ。  
			実行時にはファイルのハッシュダイジェストを確認し、一致していることを確認します。
		- `sha256`: string | null  
			イメージのSHA-256ハッシュ。  
			実行時にはファイルのハッシュダイジェストを確認し、一致していることを確認します。
- `aliases`: array required  
	リポジトリ内のイメージにつけられたエイリアスのリスト。
	- (elements): object
		- `id`: string required  
			イメージの名前。  
			`aliases`の要素内で一意である必要があります。  
			また、`images`の`id`に一致する要素が存在**しない**必要があります。
		- `reference`: string required  
			参照するイメージID。  
			`images`に一致する`id`を持つ要素が存在する必要があります。

## イメージID

イメージIDはイメージを一意に識別するための識別子です。  
通常、80ビットの乱数によって生成され、Base32エンコードされた文字列として割り当てられます。

## `repository.json` のデータとした有効なデータの例

```json
{"@context":{"name":"mcsvutils.repository","version":2},"images":[{"id":"rkuqv3nrgbalu24k","path":"rkuqv3nrgbalu24k/server.jar","size":51627615,"sha1":"59353fb40c36d304f2035d51e7d6e6baa98dc05c","sha256":"e3bc55693e93cda0188f2e60aea28113fc647c5e85a15fa3d1b347349231b4bb"}],"aliases":[{"id":"1.21.1","reference":"rkuqv3nrgbalu24k"},{"id":"latest","reference":"rkuqv3nrgbalu24k"}]}
```
