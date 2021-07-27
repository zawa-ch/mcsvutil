#! /bin/bash

: <<- __License
MIT License

Copyright (c) 2020,2021 zawa-ch.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
__License

version()
{
	cat <<- __EOF
	mcsvutils - Minecraft server commandline utilities
	version 0.3.0 2021-07-20
	Copyright 2020,2021 zawa-ch.
	__EOF
}

SUBCOMMANDS=("version" "usage" "help" "check" "mcversions" "mcdownload" "spigotbuild" "profile" "server")

usage()
{
	cat <<- __EOF
	使用法: $0 <サブコマンド> ...
	使用可能なサブコマンド: ${SUBCOMMANDS[@]}
	__EOF
}

help()
{
	cat <<- __EOF
	  profile     サーバーインスタンスのプロファイルを管理する
	  server      サーバーインスタンスを管理する
	  mcversions  minecraftのバージョンのリストを出力する
	  mcdownload  minecraftサーバーをダウンロードする
	  check       このスクリプトの動作要件を満たしているかチェックする
	  version     現在のバージョンを表示して終了
	  usage       使用法を表示する
	  help        このヘルプを表示する

	各コマンドの詳細なヘルプは各コマンドに--helpオプションを付けてください。

	すべてのサブコマンドに対し、次のオプションが使用できます。
	  --help | -h 各アクションのヘルプを表示する
	  --usage     各アクションの使用法を表示する
	  --          以降のオプションのパースを行わない
	__EOF
}

## Const -------------------------------
readonly VERSION_MANIFEST_LOCATION='https://launchermeta.mojang.com/mc/game/version_manifest.json'
readonly SPIGOT_BUILDTOOLS_LOCATION='https://hub.spigotmc.org/jenkins/job/BuildTools/lastSuccessfulBuild/artifact/target/BuildTools.jar'
readonly RESPONCE_POSITIVE=0
readonly RESPONCE_NEGATIVE=1
readonly RESPONCE_ERROR=2
readonly DATA_VERSION=2
SCRIPT_LOCATION="$(cd "$(dirname "$0")" && pwd)" || {
	echo "mcsvutils: [E] スクリプトが置かれているディレクトリを検出できませんでした。" >&2
	exit $RESPONCE_ERROR
}
readonly SCRIPT_LOCATION
## -------------------------------------

## Variables ---------------------------
# 一時ディレクトリ設定
# 一時ディレクトリの場所を設定します。
# 通常は"/tmp"で問題ありません。
[ -z "$TEMP" ] && readonly TEMP="/tmp"
# Minecraftバージョン管理ディレクトリ設定
# Minecraftバージョンの管理を行うためのディレクトリを設定します。
[ -z "$MCSVUTILS_VERSIONS_LOCATION" ] && readonly MCSVUTILS_VERSIONS_LOCATION="$SCRIPT_LOCATION/versions"
## -------------------------------------

echo_invalid_flag()
{
	echo "mcsvutils: [W] 無効なオプション $1 が指定されています" >&2
	echo "通常の引数として読み込ませる場合は先に -- を使用してください" >&2
}

oncheckfail()
{
	cat >&2 <<- __EOF
	mcsvutils: [E] 動作要件のチェックに失敗しました。必要なパッケージがインストールされているか確認してください。
	    このスクリプトを実行するために必要なソフトウェアは以下のとおりです:
	    bash sudo wget curl jq screen
	__EOF
}

# エラー出力にログ出力
# $1..: echoする内容
echoerr()
{
	echo "$*" >&2
}

# 指定ユーザーでコマンドを実行
# $1: ユーザー
# $2..: コマンド
as_user()
{
	local user="$1"
	shift
	local command=("$@")
	if [ "$(whoami)" = "$user" ]; then
		bash -c "${command[@]}"
	else
		sudo -u "$user" -sH "${command[@]}"
	fi
}

# 指定ユーザーでスクリプトを実行
# $1: ユーザー
# note: 標準入力にコマンドを流すことでスクリプトを実行できる
as_user_script()
{
	local user="$1"
	if [ "$(whoami)" = "$user" ]; then
		bash
	else
		sudo -u "$user" -sH
	fi
}

# スクリプトの動作要件チェック
check()
{
	check_installed()
	{
		bash -c "$1 --version" > /dev/null
	}
	local RESULT=0
	check_installed sudo || RESULT=$RESPONCE_NEGATIVE
	check_installed wget || RESULT=$RESPONCE_NEGATIVE
	check_installed curl || RESULT=$RESPONCE_NEGATIVE
	check_installed jq || RESULT=$RESPONCE_NEGATIVE
	check_installed screen || RESULT=$RESPONCE_NEGATIVE
	return $RESULT
}

# Minecraftバージョンマニフェストファイルの取得
VERSION_MANIFEST=
fetch_mcversions() { VERSION_MANIFEST=$(curl -s "$VERSION_MANIFEST_LOCATION") || { echoerr "mcsvutils: [E] Minecraftバージョンマニフェストファイルのダウンロードに失敗しました"; return $RESPONCE_ERROR; } }

profile_data=""

# プロファイルデータを開く
# 指定されたプロファイルデータを開き、 profile_data 変数に格納する
# プロファイルデータの指定がなかった場合、標準入力から取得する
profile_open()
{
	[ $# -le 1 ] && { profile_data="$(jq -c '.')"; return; }
	local profile_file="$1"
	[ -e "$profile_file" ] || { echoerr "mcsvutils: [E] 指定されたファイル $profile_file が見つかりません"; return $RESPONCE_ERROR; }
	profile_data="$(jq -c '.' "$profile_file")"
	return
}

profile_get_version() { { echo "$profile_data" | jq -r ".version | numbers"; } || { echoerr "mcsvutils: [E] プロファイルのパース中に問題が発生しました"; return $RESPONCE_ERROR; } }
profile_get_servicename() { { echo "$profile_data" | jq -r ".servicename | strings"; } || { echoerr "mcsvutils: [E] プロファイルのパース中に問題が発生しました"; return $RESPONCE_ERROR; } }
profile_get_mcversion() { { echo "$profile_data" | jq -r ".mcversion | strings"; } || { echoerr "mcsvutils: [E] プロファイルのパース中に問題が発生しました"; return $RESPONCE_ERROR; } }
profile_get_executejar() { { echo "$profile_data" | jq -r ".executejar | strings"; } || { echoerr "mcsvutils: [E] プロファイルのパース中に問題が発生しました"; return $RESPONCE_ERROR; } }
profile_get_options() { { echo "$profile_data" | jq -r ".options[]"; } || { echoerr "mcsvutils: [E] プロファイルのパース中に問題が発生しました"; return $RESPONCE_ERROR; } }
profile_get_arguments() { { echo "$profile_data" | jq -r ".arguments[]"; } || { echoerr "mcsvutils: [E] プロファイルのパース中に問題が発生しました"; return $RESPONCE_ERROR; } }
profile_get_cwd() { { echo "$profile_data" | jq -r ".cwd | strings"; } || { echoerr "mcsvutils: [E] プロファイルのパース中に問題が発生しました"; return $RESPONCE_ERROR; } }
profile_get_jre() { { echo "$profile_data" | jq -r ".jre | strings"; } || { echoerr "mcsvutils: [E] プロファイルのパース中に問題が発生しました"; return $RESPONCE_ERROR; } }
profile_get_owner() { { echo "$profile_data" | jq -r ".owner | strings"; } || { echoerr "mcsvutils: [E] プロファイルのパース中に問題が発生しました"; return $RESPONCE_ERROR; } }
profile_check_integrity()
{
	local version; version="$(profile_get_version)" || return $RESPONCE_NEGATIVE
	[ "$version" -ne "$DATA_VERSION" ] && { echoerr "mcsvutils: [E] 対応していないプロファイルのバージョン($version)です"; return $RESPONCE_NEGATIVE; }
	local servicename; servicename="$(profile_get_servicename)" || return $RESPONCE_NEGATIVE
	[ -z "$servicename" ] && { echoerr "mcsvutils: [E] 必要な要素 servicename がありません"; return $RESPONCE_NEGATIVE; }
	local mcversion; mcversion="$(profile_get_mcversion)" || return $RESPONCE_NEGATIVE
	local executejar; executejar="$(profile_get_executejar)" || return $RESPONCE_NEGATIVE
	{ { [ -z "$mcversion" ] && [ -z "$executejar" ]; } || { [ -n "$mcversion" ] && [ -n "$executejar" ]; } } && { echoerr "mcsvutils: [E] mcversion と executejar の要素はどちらかひとつだけが存在する必要があります"; return $RESPONCE_ERROR; }
	return $RESPONCE_POSITIVE
}

# Subcommands --------------------------
action_profile()
{
	# Usage/Help ---------------------------
	local SUBCOMMANDS=("help" "info" "create" "upgrade")
	usage()
	{
		cat <<- __EOF
		使用法: $0 profile <サブコマンド>
		使用可能なサブコマンド: ${SUBCOMMANDS[@]}
		__EOF
	}
	help()
	{
		cat <<- __EOF
		profile はMinecraftサーバーのプロファイルを管理します。

		使用可能なサブコマンドは以下のとおりです。

		  help     このヘルプを表示する
		  info     プロファイルの内容を表示する
		  create   プロファイルを作成する
		  upgrade  プロファイルを新しいフォーマットにする
		__EOF
	}

	# Subcommands --------------------------
	action_profile_info()
	{
		usage()
		{
			cat <<- __EOF
			使用法: $0 profile info <プロファイル>
			__EOF
		}
		help()
		{
			cat <<- __EOF
			profile info はMinecraftサーバーのプロファイルの情報を取得します。
			プロファイルにはプロファイルデータが記述されたファイルのパスを指定します。
			ファイルの指定がなかった場合は、標準入力から読み込まれます。
			__EOF
		}
		local args=()
		local helpflag=''
		local usageflag=''
		while (( $# > 0 ))
		do
			case $1 in
				--help) 	helpflag='--help'; shift;;
				--usage)	usageflag='--usage'; shift;;
				--)	shift; break;;
				--*)	echo_invalid_flag "$1"; shift;;
				-*)
					[[ "$1" =~ h ]] && { helpflag='-h'; }
					shift
					;;
				*)
					args=("${args[@]}" "$1")
					shift
					;;
			esac
		done
		while (( $# > 0 ))
		do
			args=("${args[@]}" "$1")
			shift
		done

		[ -n "$helpflag" ] && { version; echo; usage; echo; help; return; }
		[ -n "$usageflag" ] && { usage; return; }
		if [ "${#args[@]}" -ge 1 ]; then profile_open "$profileflag" || return; else profile_open || return; fi
		profile_check_integrity || { echoerr "mcsvutils: [E] 指定されたデータは正しいプロファイルデータではありません"; return $RESPONCE_ERROR; }
		echo "サービス名: $(profile_get_servicename)"
		[ -n "$(profile_get_owner)" ] && echo "サービス所有者: $(profile_get_owner)"
		[ -n "$(profile_get_cwd)" ] && echo "作業ディレクトリ: $(profile_get_cwd)"
		[ -n "$(profile_get_mcversion)" ] && echo "Minecraftバージョン: $(profile_get_mcversion)"
		[ -n "$(profile_get_executejar)" ] && echo "実行jarファイル: $(profile_get_executejar)"
		[ -n "$(profile_get_jre)" ] && echo "Java環境: $(profile_get_jre)"
		[ -n "$(profile_get_options)" ] && echo "Java呼び出しオプション: $(profile_get_options)"
		[ -n "$(profile_get_arguments)" ] && echo "デフォルト引数: $(profile_get_arguments)"
		return $RESPONCE_POSITIVE
	}
	action_profile_create()
	{
		usage()
		{
			cat <<- __EOF
			使用法:
			$0 profile create --name <名前> --version <バージョン> [オプション]
			$0 profile create --name <名前> --execute <jarファイル> [オプション]
			__EOF
		}
		help()
		{
			cat <<- __EOF
			profile create はMinecraftサーバーのプロファイルを作成します。

			--profile | -p
			    基となるプロファイルデータのファイルを指定します。
			--input | -i
			    基となるプロファイルデータを標準入力から取得します。
			--out | -o
			    出力先ファイル名を指定します。
			    指定がなかった場合は標準出力に書き出されます。
			--name | -n (必須)
			    インスタンスの名前を指定します。
			--version | -r
			    サーバーとして実行するMinecraftのバージョンを指定します。
			    --versionオプションまたは--executeオプションのどちらかを必ずひとつ指定する必要があります。
			    また、--executeオプションと同時に使用することはできません。
			--execute | -e
			    サーバーとして実行するjarファイルを指定します。
			    --versionオプションまたは--executeオプションのどちらかを必ずひとつ指定する必要があります。
			    また、--versionオプションと同時に使用することはできません。
			--owner | -u
			    実行時のユーザーを指定します。
			--cwd
			    実行時の作業ディレクトリを指定します。
			--java
			    javaの環境を指定します。
			    このオプションを指定するとインストールされているjavaとは異なるjavaを使用することができます。
			--option
			    実行時にjreに渡すオプションを指定します。
			    複数回呼び出された場合、呼び出された順に連結されます。
			--args
			    実行時にjarに渡されるデフォルトの引数を指定します。
			    複数回呼び出された場合、呼び出された順に連結されます。
			__EOF
		}
		local args=()
		local profileflag=''
		local inputflag=''
		local outflag=''
		local nameflag=''
		local versionflag=''
		local executeflag=''
		local ownerflag=''
		local cwdflag=''
		local javaflag=''
		local optionflag=()
		local argsflag=()
		local helpflag=''
		local usageflag=''
		while (( $# > 0 ))
		do
			case $1 in
				--profile)	shift; profileflag="$1"; shift;;
				--input)	shift; inputflag="$1"; shift;;
				--out)  	shift; outflag="$1"; shift;;
				--name) 	shift; nameflag="$1"; shift;;
				--version)	shift; versionflag="$1"; shift;;
				--execute)	shift; executeflag="$1"; shift;;
				--owner)	shift; ownerflag="$1"; shift;;
				--cwd)  	shift; cwdflag="$1"; shift;;
				--java) 	shift; javaflag="$1"; shift;;
				--option)	shift; optionflag+=("$1"); shift;;
				--args) 	shift; argsflag+=("$1"); shift;;
				--help) 	helpflag='--help'; shift;;
				--usage)	usageflag='--usage'; shift;;
				--)	shift; break;;
				--*)	echo_invalid_flag "$1"; shift;;
				-*)
					[[ "$1" =~ p ]] && { if [[ "$1" =~ p$ ]]; then shift; profileflag="$1"; else profileflag=''; fi; }
					[[ "$1" =~ i ]] && { inputflag='-i'; }
					[[ "$1" =~ o ]] && { if [[ "$1" =~ o$ ]]; then shift; outflag="$1"; else outflag=''; fi; }
					[[ "$1" =~ n ]] && { if [[ "$1" =~ n$ ]]; then shift; nameflag="$1"; else nameflag=''; fi; }
					[[ "$1" =~ r ]] && { if [[ "$1" =~ r$ ]]; then shift; versionflag="$1"; else versionflag=''; fi; }
					[[ "$1" =~ e ]] && { if [[ "$1" =~ e$ ]]; then shift; executeflag="$1"; else executeflag=''; fi; }
					[[ "$1" =~ u ]] && { if [[ "$1" =~ u$ ]]; then shift; ownerflag="$1"; else ownerflag=''; fi; }
					[[ "$1" =~ h ]] && { helpflag='-h'; }
					shift
					;;
				*)
					args=("${args[@]}" "$1")
					shift
					;;
			esac
		done
		while (( $# > 0 ))
		do
			args=("${args[@]}" "$1")
			shift
		done

		[ -n "$helpflag" ] && { version; echo; usage; echo; help; return; }
		[ -n "$usageflag" ] && { usage; return; }
		local result="{}"
		[ -n "$profileflag" ] && [ -n "$inputflag" ] && { echoerr "mcsvutils: [E] --profileと--inputは同時に指定できません"; return $RESPONCE_ERROR; }
		[ -n "$profileflag" ] && { { profile_open "$profileflag" && profile_check_integrity && result="$profile_data"; } || return $RESPONCE_ERROR; }
		[ -n "$inputflag" ] && { { profile_open && profile_check_integrity && result="$profile_data"; } || return $RESPONCE_ERROR; }
		[ -z "$profileflag" ] && [ -z "$inputflag" ] && [ -z "$nameflag" ] && { echoerr "mcsvutils: [E] --nameは必須です"; return $RESPONCE_ERROR; }
		result=$(echo "$result" | jq -c --argjson version "$DATA_VERSION" '.version |= $version') || { echoerr "mcsvutils: [E] データの生成に失敗しました"; return $RESPONCE_ERROR; }
		[ -n "$nameflag" ] && { result=$(echo "$result" | jq -c --arg servicename "$nameflag" '.servicename |= $servicename') || { echoerr "mcsvutils: [E] データの生成に失敗しました"; return $RESPONCE_ERROR; } }
		{ [ -z "$profileflag" ] && [ -z "$inputflag" ] && [ -z "$executeflag" ] && [ -z "$versionflag" ]; } && { echoerr "mcsvutils: [E] --executeまたは--versionは必須です"; return $RESPONCE_ERROR; }
		{ [ -z "$profileflag" ] && [ -z "$inputflag" ] && [ -n "$executeflag" ] && [ -n "$versionflag" ]; } && { echoerr "mcsvutils: [E] --executeと--versionは同時に指定できません"; return $RESPONCE_ERROR; }
		[ -n "$executeflag" ] && { result=$(echo "$result" | jq -c --arg executejar "$executeflag" '.executejar |= $executejar | .mcversion |= null' ) || { echoerr "mcsvutils: [E] データの生成に失敗しました"; return $RESPONCE_ERROR; } }
		[ -n "$versionflag" ] && { result=$(echo "$result" | jq -c --arg mcversion "$versionflag" '.mcversion |= $mcversion | .executejar |= null' ) || { echoerr "mcsvutils: [E] データの生成に失敗しました"; return $RESPONCE_ERROR; } }
		local options="[]"
		[ ${#optionflag[@]} -ne 0 ] && { for item in "${optionflag[@]}"; do options=$(echo "$options" | jq -c ". + [ \"$item\" ]"); done }
		result=$(echo "$result" | jq -c --argjson options "$options" '.options |= $options') || { echoerr "mcsvutils: [E] データの生成に失敗しました"; return $RESPONCE_ERROR; }
		local arguments="[]"
		[ ${#argsflag[@]} -ne 0 ] && { for item in "${argsflag[@]}"; do arguments=$(echo "$arguments" | jq -c ". + [ \"$item\" ]"); done }
		result=$(echo "$result" | jq -c --argjson arguments "$arguments" '.arguments |= $arguments') || { echoerr "mcsvutils: [E] データの生成に失敗しました"; return $RESPONCE_ERROR; }
		if [ -n "$cwdflag" ]; then
			result=$(echo "$result" | jq -c --arg cwd "$cwdflag" '.cwd |= $cwd') || { echoerr "mcsvutils: [E] データの生成に失敗しました"; return $RESPONCE_ERROR; }
		else
			result=$(echo "$result" | jq -c '.cwd |= null') || { echoerr "mcsvutils: [E] データの生成に失敗しました"; return $RESPONCE_ERROR; }
		fi
		if [ -n "$javaflag" ]; then
			result=$(echo "$result" | jq -c --arg jre "$javaflag" '.jre |= $jre') || { echoerr "mcsvutils: [E] データの生成に失敗しました"; return $RESPONCE_ERROR; }
		else
			result=$(echo "$result" | jq -c '.jre |= null') || { echoerr "mcsvutils: [E] データの生成に失敗しました"; return $RESPONCE_ERROR; }
		fi
		if [ -n "$ownerflag" ]; then
			result=$(echo "$result" | jq -c --arg owner "$ownerflag" '.owner |= $owner') || { echoerr "mcsvutils: [E] データの生成に失敗しました"; return $RESPONCE_ERROR; }
		else
			result=$(echo "$result" | jq -c '.owner |= null') || { echoerr "mcsvutils: [E] データの生成に失敗しました"; return $RESPONCE_ERROR; }
		fi
		profile_data="$result"
		if [ -n "$outflag" ]; then
			echo "$profile_data" > "$outflag"
		else
			echo "$profile_data"
		fi
	}
	action_profile_upgrade()
	{
		usage()
		{
			cat <<- __EOF
			使用法:
			$0 profile upgrade [オプション] [プロファイル]
			__EOF
		}
		help()
		{
			cat <<- __EOF
			profile upgrade はMinecraftサーバーのプロファイルのバージョンを最新にします。
			プロファイルにはプロファイルデータが記述されたファイルのパスを指定します。
			ファイルの指定がなかった場合は、標準入力から読み込まれます。

			--out | -o
			    出力先ファイル名を指定します。
			    指定がなかった場合は標準出力に書き出されます。
			__EOF
		}
		local args=()
		local outflag=''
		local helpflag=''
		local usageflag=''
		while (( $# > 0 ))
		do
			case $1 in
				--out)  	shift; outflag="$1"; shift;;
				--help) 	helpflag='--help'; shift;;
				--usage)	usageflag='--usage'; shift;;
				--)	shift; break;;
				--*)	echo_invalid_flag "$1"; shift;;
				-*)
					[[ "$1" =~ o ]] && { if [[ "$1" =~ o$ ]]; then shift; outflag="$1"; else outflag=''; fi; }
					[[ "$1" =~ h ]] && { helpflag='-h'; }
					shift
					;;
				*)
					args=("${args[@]}" "$1")
					shift
					;;
			esac
		done
		while (( $# > 0 ))
		do
			args=("${args[@]}" "$1")
			shift
		done

		[ -n "$helpflag" ] && { version; echo; usage; echo; help; return; }
		[ -n "$usageflag" ] && { usage; return; }

		if [ "${#args[@]}" -ge 1 ]
			then { profile_open "${args[0]}" || return $RESPONCE_ERROR; }
			else { profile_open || return $RESPONCE_ERROR; }
		fi
		local version=''
		local servicename=''
		local mcversion=''
		local executejar=''
		local owner=''
		local cwd=''
		local jre=''
		local options=''
		local arguments=''
		version="$(profile_get_version)" || return $RESPONCE_ERROR
		echoerr "mcsvutils: 読み込まれたプロファイルのバージョン: $version"
		case "$version" in
			"$DATA_VERSION") {
				if profile_check_integrity
					then echoerr "mcsvutils: [W] このプロファイルはすでに最新です。更新の必要はありません。"; return $RESPONCE_NEGATIVE;
					else return $RESPONCE_ERROR;
				fi
			};;
			"1") {
				servicename=$(echo "$profile_data" | jq -r ".name | strings") || { echoerr "mcsvutils: [E] プロファイルのパース中に問題が発生しました"; return $RESPONCE_ERROR; }
				[ -z "$servicename" ] && { echoerr "mcsvutils: [E] .name要素が空であるか、正しい型ではありません"; return $RESPONCE_ERROR; }
				executejar=$(echo "$profile_data" | jq -r ".execute | strings") || { echoerr "mcsvutils: [E] プロファイルのパース中に問題が発生しました"; return $RESPONCE_ERROR; }
				[ -z "$executejar" ] && { echoerr "mcsvutils: [E] .execute要素が空であるか、正しい型ではありません"; return $RESPONCE_ERROR; }
				owner=$(echo "$profile_data" | jq -r ".owner | strings") || { echoerr "mcsvutils: [E] プロファイルのパース中に問題が発生しました"; return $RESPONCE_ERROR; }
				cwd=$(echo "$profile_data" | jq -r ".cwd | strings") || { echoerr "mcsvutils: [E] プロファイルのパース中に問題が発生しました"; return $RESPONCE_ERROR; }
				jre=$(echo "$profile_data" | jq -r ".javapath | strings") || { echoerr "mcsvutils: [E] プロファイルのパース中に問題が発生しました"; return $RESPONCE_ERROR; }
				options=$(echo "$profile_data" | jq -c ".options") || { echoerr "mcsvutils: [E] プロファイルのパース中に問題が発生しました"; return $RESPONCE_ERROR; }
				arguments=$(echo "$profile_data" | jq -c ".args") || { echoerr "mcsvutils: [E] プロファイルのパース中に問題が発生しました"; return $RESPONCE_ERROR; }
			};;
			*) {
				echoerr "mcsvutils: [E] サポートされていないバージョン $version が選択されました。"
				return $RESPONCE_ERROR
			};;
		esac

		local result="{}"
		result=$(echo "$result" | jq -c --argjson version "$DATA_VERSION" '.version |= $version') || { echoerr "mcsvutils: [E] データの生成に失敗しました"; return $RESPONCE_ERROR; }
		[ -z "$servicename" ] && { echoerr "mcsvutils: [E] サービス名が空です"; return $RESPONCE_ERROR; }
		result=$(echo "$result" | jq -c --arg servicename "$servicename" '.servicename |= $servicename') || { echoerr "mcsvutils: [E] データの生成に失敗しました"; return $RESPONCE_ERROR; }
		{ [ -z "$mcversion" ] && [ -z "$executejar" ]; } && { echoerr "mcsvutils: [E] executejarとmcversionがどちらも空です"; return $RESPONCE_ERROR; }
		{ [ -n "$mcversion" ] && [ -n "$executejar" ]; } && { echoerr "mcsvutils: [E] executejarとmcversionは同時に存在できません"; return $RESPONCE_ERROR; }
		[ -n "$mcversion" ] && { result=$(echo "$result" | jq -c --arg mcversion "$mcversion" '.mcversion |= $mcversion | .executejar |= null' ) || { echoerr "mcsvutils: [E] データの生成に失敗しました"; return $RESPONCE_ERROR; } }
		[ -n "$executejar" ] && { result=$(echo "$result" | jq -c --arg executejar "$executejar" '.executejar |= $executejar | .mcversion |= null' ) || { echoerr "mcsvutils: [E] データの生成に失敗しました"; return $RESPONCE_ERROR; } }
		if [ -n "$owner" ]; then
			result=$(echo "$result" | jq -c --arg owner "$owner" '.owner |= $owner') || { echoerr "mcsvutils: [E] データの生成に失敗しました"; return $RESPONCE_ERROR; }
		else
			result=$(echo "$result" | jq -c '.owner |= null') || { echoerr "mcsvutils: [E] データの生成に失敗しました"; return $RESPONCE_ERROR; }
		fi
		if [ -n "$cwd" ]; then
			result=$(echo "$result" | jq -c --arg cwd "$cwd" '.cwd |= $cwd') || { echoerr "mcsvutils: [E] データの生成に失敗しました"; return $RESPONCE_ERROR; }
		else
			result=$(echo "$result" | jq -c '.cwd |= null') || { echoerr "mcsvutils: [E] データの生成に失敗しました"; return $RESPONCE_ERROR; }
		fi
		if [ -n "$jre" ]; then
			result=$(echo "$result" | jq -c --arg jre "$jre" '.jre |= $jre') || { echoerr "mcsvutils: [E] データの生成に失敗しました"; return $RESPONCE_ERROR; }
		else
			result=$(echo "$result" | jq -c '.jre |= null') || { echoerr "mcsvutils: [E] データの生成に失敗しました"; return $RESPONCE_ERROR; }
		fi
		result=$(echo "$result" | jq -c --argjson options "$options" '.options |= $options') || { echoerr "mcsvutils: [E] データの生成に失敗しました"; return $RESPONCE_ERROR; }
		result=$(echo "$result" | jq -c --argjson arguments "$arguments" '.arguments |= $arguments') || { echoerr "mcsvutils: [E] データの生成に失敗しました"; return $RESPONCE_ERROR; }
		profile_data="$result"
		if [ -n "$outflag" ]; then
			echo "$profile_data" > "$outflag"
		else
			echo "$profile_data"
		fi
	}

	# Analyze arguments --------------------
	local subcommand=""
	if [[ $1 =~ -.* ]] || [ "$1" = "" ]; then
		subcommand="none"
		while (( $# > 0 ))
		do
			case $1 in
				--help) 	helpflag='--help'; shift;;
				--usage)	usageflag='--usage'; shift;;
				--*)	echo_invalid_flag "$1"; shift;;
				-*)
					[[ "$1" =~ h ]] && { helpflag='-h'; }
					shift
					;;
				*)	break;;
			esac
		done
	else
		for item in "${SUBCOMMANDS[@]}"
		do
			[ "$item" == "$1" ] && {
				subcommand="$item"
				shift
				break
			}
		done
	fi
	[ -z "$subcommand" ] && { echoerr "mcsvutils: [E] 無効なサブコマンドを指定しました。"; usage >&2; return $RESPONCE_ERROR; }
	{ [ "$subcommand" == "help" ] || [ -n "$helpflag" ]; } && { version; echo; usage; echo; help; return; }
	[ -n "$usageflag" ] && { usage; return; }
	[ "$subcommand" == "none" ] && { echoerr "mcsvutils: [E] サブコマンドが指定されていません。"; echoerr "$0 profile help で詳細なヘルプを表示します。"; usage >&2; return $RESPONCE_ERROR; }
	"action_profile_$subcommand" "$@"
}

action_server()
{
	# Usage/Help ---------------------------
	local SUBCOMMANDS=("help" "status" "start" "stop" "attach" "command")
	usage()
	{
		cat <<- __EOF
		使用法: $0 server <サブコマンド>
		使用可能なサブコマンド: ${SUBCOMMANDS[@]}
		__EOF
	}
	help()
	{
		cat <<- __EOF
		server はMinecraftサーバーのインスタンスを管理します。

		使用可能なサブコマンドは以下のとおりです。

		  help     このヘルプを表示する
		  status   インスタンスの状態を問い合わせる
		  start    インスタンスを開始する
		  stop     インスタンスを停止する
		  attach   インスタンスのコンソールにアタッチする
		  command  インスタンスにコマンドを送信する
		__EOF
	}

	# Minecraftコマンドを実行
	# $1: サーバー所有者
	# $2: サーバーのセッション名
	# $3..: 送信するコマンド
	dispatch_mccommand()
	{
		local owner="$1"
		shift
		local servicename="$1"
		shift
		as_user "$owner" "screen -p 0 -S $servicename -X eval 'stuff \"$*\"\015'"
	}

	# Subcommands --------------------------
	action_server_status()
	{
		usage()
		{
			cat <<- __EOF
			使用法:
			$0 server status -p <プロファイル> [オプション]
			$0 server status -n <名前> [オプション]
			__EOF
		}
		help()
		{
			cat <<- __EOF
			server status はMinecraftサーバーの状態を問い合わせます。
			コマンドの実行には名前、もしくはプロファイルのどちらかを指定する必要があります。
			いずれの指定もなかった場合は、標準入力からプロファイルを取得します。

			--profile | -p
			    インスタンスを実行するための情報を記したプロファイルの場所を指定します。
			    名前を指定していない場合のみ必須です。
			    名前を指定している場合はこのオプションを指定することはできません。
			--name | -n
			    インスタンスの名前を指定します。
			    プロファイルを指定しない場合のみ必須です。
			    プロファイルを指定している場合はこのオプションを指定することはできません。
			--owner | -u
			    実行時のユーザーを指定します。
			    このオプションを指定するとプロファイルの設定を上書きします。

			指定したMinecraftサーバーが起動している場合は $RESPONCE_POSITIVE 、起動していない場合は $RESPONCE_NEGATIVE が返されます。
			__EOF
		}
		local args=()
		local profileflag=''
		local nameflag=''
		local ownerflag=''
		local helpflag=''
		local usageflag=''
		while (( $# > 0 ))
		do
			case $1 in
				--profile) 	shift; profileflag="$1"; shift;;
				--name) 	shift; nameflag="$1"; shift;;
				--owner)	shift; ownerflag="$1"; shift;;
				--help) 	helpflag='--help'; shift;;
				--usage)	usageflag='--usage'; shift;;
				--)	shift; break;;
				--*)	echo_invalid_flag "$1"; shift;;
				-*)
					[[ "$1" =~ p ]] && { if [[ "$1" =~ p$ ]]; then shift; profileflag="$1"; else profileflag=''; fi; }
					[[ "$1" =~ n ]] && { if [[ "$1" =~ n$ ]]; then shift; nameflag="$1"; else nameflag=''; fi; }
					[[ "$1" =~ u ]] && { if [[ "$1" =~ u$ ]]; then shift; ownerflag="$1"; else ownerflag=''; fi; }
					[[ "$1" =~ h ]] && { helpflag='-h'; }
					shift
					;;
				*)
					args=("${args[@]}" "$1")
					shift
					;;
			esac
		done
		while (( $# > 0 ))
		do
			args=("${args[@]}" "$1")
			shift
		done

		[ -n "$helpflag" ] && { version; echo; usage; echo; help; return; }
		[ -n "$usageflag" ] && { usage; return; }
		local servicename=''
		local owner=''
		if [ -n "$nameflag" ]; then
			[ -n "$profileflag" ] && { echoerr "mcsvutils: [E] プロファイルを指定した場合、名前の指定は無効です"; return $RESPONCE_ERROR; }
			servicename=$nameflag
		else
			if [ -n "$profileflag" ]; then profile_open "$profileflag" || return; else profile_open || return; fi
			profile_check_integrity || { echoerr "mcsvutils: [E] プロファイルのロードに失敗したため、中止します"; return $RESPONCE_ERROR; }
			servicename="$(profile_get_servicename)" || return $RESPONCE_ERROR
			owner="$(profile_get_owner)" || return $RESPONCE_ERROR
		fi
		[ -z "$servicename" ] && { echoerr "mcsvctrl: [E] インスタンスの名前が指定されていません"; return $RESPONCE_ERROR; }
		[ -n "$ownerflag" ] && owner=$ownerflag
		[ -z "$owner" ] && owner="$(whoami)"
		if as_user "$owner" "screen -list \"$servicename\"" > /dev/null
		then
			echo "mcsvutils: ${servicename} は起動しています"
			return $RESPONCE_POSITIVE
		else
			echo "mcsvutils: ${servicename} は起動していません"
			return $RESPONCE_NEGATIVE
		fi
	}
	action_server_start()
	{
		usage()
		{
			cat <<- __EOF
			使用法:
			$0 server start -p <プロファイル> [オプション] [引数]
			$0 server start -n <名前> -r <バージョン> [オプション] [引数]
			$0 server start -n <名前> -e <jarファイル> [オプション] [引数]
			__EOF
		}
		help()
		{
			cat <<- __EOF
			server start はMinecraftサーバーのインスタンスを開始します。
			インスタンスの開始には名前とバージョン、もしくはプロファイルのどちらかを指定する必要があります。
			いずれの指定もなかった場合は、標準入力からプロファイルを取得します。

			--profile | -p
			    インスタンスを実行するための情報を記したプロファイルの場所を指定します。
			    名前・バージョンをともに指定していない場合のみ必須です。
			    名前・バージョンを指定している場合はこのオプションを指定することはできません。
			--name | -n
			    インスタンスの名前を指定します。
			    プロファイルを指定しない場合のみ必須です。
			    プロファイルを指定している場合はこのオプションを指定することはできません。
			--version | -r
			    サーバーとして実行するMinecraftのバージョンを指定します。
			    プロファイルを指定しない場合、--versionオプションまたは--executeオプションのどちらかを必ずひとつ指定する必要があります。
			    --executeオプションと同時に使用することはできません。
			    また、プロファイルを指定している場合はこのオプションを指定することはできません。
			--execute | -e
			    サーバーとして実行するjarファイルを指定します。
			    プロファイルを指定しない場合、--versionオプションまたは--executeオプションのどちらかを必ずひとつ指定する必要があります。
			    --versionオプションと同時に使用することはできません。
			    また、プロファイルを指定している場合はこのオプションを指定することはできません。
			--owner | -u
			    実行時のユーザーを指定します。
			    このオプションを指定するとプロファイルの設定を上書きします。
			--cwd
			    実行時の作業ディレクトリを指定します。
			    このオプションを指定するとプロファイルの設定を上書きします。
			--java
			    javaの環境を指定します。
			    この引数を指定するとインストールされているjavaとは異なるjavaを使用することができます。
			    このオプションを指定するとプロファイルの設定を上書きします。
			--option
			    実行時にjavaに渡すオプションを指定します。
			    このオプションを指定するとプロファイルの設定を上書きします。
			__EOF
		}
		local args=()
		local profileflag=''
		local nameflag=''
		local versionflag=''
		local executeflag=''
		local ownerflag=''
		local cwdflag=''
		local javaflag=''
		local optionflag=()
		local helpflag=''
		local usageflag=''
		while (( $# > 0 ))
		do
			case $1 in
				--profile) 	shift; profileflag="$1"; shift;;
				--name) 	shift; nameflag="$1"; shift;;
				--version)	shift; versionflag="$1"; shift;;
				--execute)	shift; executeflag="$1"; shift;;
				--owner)	shift; ownerflag="$1"; shift;;
				--cwd)  	shift; cwdflag="$1"; shift;;
				--java) 	shift; javaflag="$1"; shift;;
				--option)	shift; optionflag+=("$1"); shift;;
				--help) 	helpflag='--help'; shift;;
				--usage)	usageflag='--usage'; shift;;
				--)	shift; break;;
				--*)	echo_invalid_flag "$1"; shift;;
				-*)
					[[ "$1" =~ p ]] && { if [[ "$1" =~ p$ ]]; then shift; profileflag="$1"; else profileflag=''; fi; }
					[[ "$1" =~ n ]] && { if [[ "$1" =~ n$ ]]; then shift; nameflag="$1"; else nameflag=''; fi; }
					[[ "$1" =~ r ]] && { if [[ "$1" =~ r$ ]]; then shift; versionflag="$1"; else versionflag=''; fi; }
					[[ "$1" =~ e ]] && { if [[ "$1" =~ e$ ]]; then shift; executeflag="$1"; else executeflag=''; fi; }
					[[ "$1" =~ u ]] && { if [[ "$1" =~ u$ ]]; then shift; ownerflag="$1"; else ownerflag=''; fi; }
					[[ "$1" =~ h ]] && { helpflag='-h'; }
					shift
					;;
				*)
					args=("${args[@]}" "$1")
					shift
					;;
			esac
		done
		while (( $# > 0 ))
		do
			args=("${args[@]}" "$1")
			shift
		done

		[ -n "$helpflag" ] && { version; echo; usage; echo; help; return; }
		[ -n "$usageflag" ] && { usage; return; }
		local servicename=''
		local mcversion=''
		local executejar=''
		local options=()
		local arguments=()
		local cwd=''
		local jre=''
		local owner=''
		if [ -n "$nameflag" ] || [ -n "$versionflag" ] || [ -n "$executeflag" ]; then
			[ -n "$profileflag" ] && { echoerr "mcsvutils: [E] プロファイルを指定した場合、名前・バージョンおよびjarファイルの指定は無効です"; return $RESPONCE_ERROR; }
			servicename=$nameflag
			[ -n "$versionflag" ] && [ -n "$executeflag" ] && { echoerr "mcsvutils: [E] バージョンとjarファイルは同時に指定できません"; return $RESPONCE_ERROR; }
			[ -n "$versionflag" ] && mcversion=$versionflag
			[ -n "$executeflag" ] && executejar=$executeflag
		else
			if [ -n "$profileflag" ]; then profile_open "$profileflag" || return; else profile_open || return; fi
			profile_check_integrity || { echoerr "mcsvutils: [E] プロファイルのロードに失敗したため、中止します"; return $RESPONCE_ERROR; }
			servicename="$(profile_get_servicename)" || return $RESPONCE_ERROR
			mcversion="$(profile_get_mcversion)" || return $RESPONCE_ERROR
			executejar="$(profile_get_executejar)" || return $RESPONCE_ERROR
			for item in $(profile_get_options); do options+=("$item"); done
			for item in $(profile_get_arguments); do arguments+=("$item"); done
			cwd="$(profile_get_cwd)" || return $RESPONCE_ERROR
			jre="$(profile_get_jre)" || return $RESPONCE_ERROR
			owner="$(profile_get_owner)" || return $RESPONCE_ERROR
		fi
		[ -z "$servicename" ] && { echoerr "mcsvctrl: [E] インスタンスの名前が指定されていません"; return $RESPONCE_ERROR; }
		[ -z "$mcversion" ] && [ -z "$executejar" ] && { echoerr "mcsvctrl: [E] 実行するjarファイルが指定されていません"; return $RESPONCE_ERROR; }
		[ "${#optionflag[@]}" -ne 0 ] && options=("${optionflag[@]}")
		[ "${#args[@]}" -ne 0 ] && arguments=("${args[@]}")
		[ -n "$cwdflag" ] && cwd=$cwdflag
		[ -n "$javaflag" ] && jre=$javaflag
		[ -n "$ownerflag" ] && owner=$ownerflag
		[ -z "$cwd" ] && cwd="./"
		[ -z "$jre" ] && jre="java"
		[ -z "$owner" ] && owner="$(whoami)"
		as_user_script "$owner" <<- __EOF
		screen -list $servicename > /dev/null && { echo "mcsvutils: ${servicename} は起動済みです" >&2; exit $RESPONCE_NEGATIVE; }
		echo "mcsvutils: $servicename を起動しています"
		cd "$cwd" || { echo "mcsvutils: [E] $cwd に入れませんでした" >&2; exit $RESPONCE_ERROR; }
		invocations="$jre"
		[ "${#options[@]}" -ne 0 ] && invocations="\$invocations ${options[@]}"
		invocations="\$invocations -jar $executejar"
		[ "${#arguments[@]}" -ne 0 ] && invocations="\$invocations ${arguments[@]}"
		screen -h 1024 -dmS "$servicename" \$invocations
		sleep .5
		if screen -list "$servicename" > /dev/null; then
			echo "mcsvutils: ${servicename} が起動しました"
			exit $RESPONCE_POSITIVE
		else
			echo "mcsvutils: [E] ${servicename} を起動できませんでした" >&2
			exit $RESPONCE_ERROR
		fi
		__EOF
	}
	action_server_stop()
	{
		usage()
		{
			cat <<- __EOF
			使用法:
			$0 server stop -p <プロファイル> [オプション]
			$0 server stop -n <名前> [オプション]
			__EOF
		}
		help()
		{
			cat <<- __EOF
			server stop はMinecraftサーバーのインスタンスを停止します。
			インスタンスの停止には名前、もしくはプロファイルのどちらかを指定する必要があります。
			いずれの指定もなかった場合は、標準入力からプロファイルを取得します。

			--profile | -p
			    インスタンスを実行するための情報を記したプロファイルの場所を指定します。
			    名前を指定していない場合のみ必須です。
			    名前を指定している場合はこのオプションを指定することはできません。
			--name | -n
			    インスタンスの名前を指定します。
			    プロファイルを指定しない場合のみ必須です。
			    プロファイルを指定している場合はこのオプションを指定することはできません。
			--owner | -u
			    実行時のユーザーを指定します。
			    このオプションを指定するとプロファイルの設定を上書きします。
			__EOF
		}
		local args=()
		local profileflag=''
		local nameflag=''
		local ownerflag=''
		local helpflag=''
		local usageflag=''
		while (( $# > 0 ))
		do
			case $1 in
				--profile) 	shift; profileflag="$1"; shift;;
				--name) 	shift; nameflag="$1"; shift;;
				--owner)	shift; ownerflag="$1"; shift;;
				--help) 	helpflag='--help'; shift;;
				--usage)	usageflag='--usage'; shift;;
				--)	shift; break;;
				--*)	echo_invalid_flag "$1"; shift;;
				-*)
					[[ "$1" =~ p ]] && { if [[ "$1" =~ p$ ]]; then shift; profileflag="$1"; else profileflag=''; fi; }
					[[ "$1" =~ n ]] && { if [[ "$1" =~ n$ ]]; then shift; nameflag="$1"; else nameflag=''; fi; }
					[[ "$1" =~ u ]] && { if [[ "$1" =~ u$ ]]; then shift; ownerflag="$1"; else ownerflag=''; fi; }
					[[ "$1" =~ h ]] && { helpflag='-h'; }
					shift
					;;
				*)
					args=("${args[@]}" "$1")
					shift
					;;
			esac
		done
		while (( $# > 0 ))
		do
			args=("${args[@]}" "$1")
			shift
		done

		[ -n "$helpflag" ] && { version; echo; usage; echo; help; return; }
		[ -n "$usageflag" ] && { usage; return; }
		local servicename=''
		local owner=''
		if [ -n "$nameflag" ]; then
			[ -n "$profileflag" ] && { echoerr "mcsvutils: [E] プロファイルを指定した場合、名前の指定は無効です"; return $RESPONCE_ERROR; }
			servicename=$nameflag
		else
			if [ -n "$profileflag" ]; then profile_open "$profileflag" || return; else profile_open || return; fi
			profile_check_integrity || { echoerr "mcsvutils: [E] プロファイルのロードに失敗したため、中止します"; return $RESPONCE_ERROR; }
			servicename="$(profile_get_servicename)" || return $RESPONCE_ERROR
			owner="$(profile_get_owner)" || return $RESPONCE_ERROR
		fi
		[ -z "$servicename" ] && { echoerr "mcsvctrl: [E] インスタンスの名前が指定されていません"; return $RESPONCE_ERROR; }
		[ -n "$ownerflag" ] && owner=$ownerflag
		[ -z "$owner" ] && owner="$(whoami)"
		as_user "$owner" "screen -list \"$servicename\"" > /dev/null || { echo "mcsvutils: ${servicename} は起動していません" >&2; return $RESPONCE_NEGATIVE; }
		echo "mcsvutils: ${servicename} を停止しています"
		dispatch_mccommand "$owner" "$servicename" stop
		as_user_script "$owner" <<- __EOF
		trap 'echo "mcsvutils: SIGINTを検出しました。処理は中断しますが、遅れてサービスが停止する可能性はあります…"; exit $RESPONCE_ERROR' 2
		while screen -list "$servicename" > /dev/null
		do
			sleep 1
		done
		__EOF
		if ! as_user "$owner" "screen -list \"$servicename\"" > /dev/null
		then
			echo "mcsvutils: ${servicename} が停止しました"
			return $RESPONCE_POSITIVE
		else
			echo "mcsvutils: [E] ${servicename} が停止しませんでした" >&2
			return $RESPONCE_ERROR
		fi
	}
	action_server_attach()
	{
		usage()
		{
			cat <<- __EOF
			使用法:
			$0 server attach -p <プロファイル> [オプション]
			$0 server attach -n <名前> [オプション]
			__EOF
		}
		help()
		{
			cat <<- __EOF
			server attach はMinecraftサーバーのコンソールに接続します。
			インスタンスのアタッチには名前、もしくはプロファイルのどちらかを指定する必要があります。
			いずれの指定もなかった場合は、標準入力からプロファイルを取得します。

			--profile | -p
			    インスタンスを実行するための情報を記したプロファイルの場所を指定します。
			    名前を指定していない場合のみ必須です。
			    名前を指定している場合はこのオプションを指定することはできません。
			--name | -n
			    インスタンスの名前を指定します。
			    プロファイルを指定しない場合のみ必須です。
			    プロファイルを指定している場合はこのオプションを指定することはできません。
			--owner | -u
			    実行時のユーザーを指定します。
			    このオプションを指定するとプロファイルの設定を上書きします。

			接続するコンソールはscreenで作成したコンソールです。
			そのため、コンソールの操作はscreenでのものと同じです。
			指定したMinecraftサーバーが起動していない場合は $RESPONCE_NEGATIVE が返されます。
			__EOF
		}
		local args=()
		local profileflag=''
		local nameflag=''
		local ownerflag=''
		local helpflag=''
		local usageflag=''
		while (( $# > 0 ))
		do
			case $1 in
				--profile) 	shift; profileflag="$1"; shift;;
				--name) 	shift; nameflag="$1"; shift;;
				--owner)	shift; ownerflag="$1"; shift;;
				--help) 	helpflag='--help'; shift;;
				--usage)	usageflag='--usage'; shift;;
				--)	shift; break;;
				--*)	echo_invalid_flag "$1"; shift;;
				-*)
					[[ "$1" =~ p ]] && { if [[ "$1" =~ p$ ]]; then shift; profileflag="$1"; else profileflag=''; fi; }
					[[ "$1" =~ n ]] && { if [[ "$1" =~ n$ ]]; then shift; nameflag="$1"; else nameflag=''; fi; }
					[[ "$1" =~ u ]] && { if [[ "$1" =~ u$ ]]; then shift; ownerflag="$1"; else ownerflag=''; fi; }
					[[ "$1" =~ h ]] && { helpflag='-h'; }
					shift
					;;
				*)
					args=("${args[@]}" "$1")
					shift
					;;
			esac
		done
		while (( $# > 0 ))
		do
			args=("${args[@]}" "$1")
			shift
		done

		[ -n "$helpflag" ] && { version; echo; usage; echo; help; return; }
		[ -n "$usageflag" ] && { usage; return; }
		local servicename=''
		local owner=''
		if [ -n "$nameflag" ]; then
			[ -n "$profileflag" ] && { echoerr "mcsvutils: [E] プロファイルを指定した場合、名前の指定は無効です"; return $RESPONCE_ERROR; }
			servicename=$nameflag
		else
			if [ -n "$profileflag" ]; then profile_open "$profileflag" || return; else profile_open || return; fi
			profile_check_integrity || { echoerr "mcsvutils: [E] プロファイルのロードに失敗したため、中止します"; return $RESPONCE_ERROR; }
			servicename="$(profile_get_servicename)" || return $RESPONCE_ERROR
			owner="$(profile_get_owner)" || return $RESPONCE_ERROR
		fi
		[ -z "$servicename" ] && { echoerr "mcsvctrl: [E] インスタンスの名前が指定されていません"; return $RESPONCE_ERROR; }
		[ -n "$ownerflag" ] && owner=$ownerflag
		[ -z "$owner" ] && owner="$(whoami)"
		as_user "$owner" "screen -list \"$servicename\"" > /dev/null || { echo "mcsvutils: ${servicename} は起動していません"; return $RESPONCE_NEGATIVE; }
		as_user "$owner" "screen -r \"$servicename\""
	}
	action_server_command()
	{
		usage()
		{
			cat <<- __EOF
			使用法:
			$0 server command -p <プロファイル> [オプション] <コマンド>
			$0 server command -n <名前> [オプション] <コマンド>
			__EOF
		}
		help()
		{
			cat <<- __EOF
			server command はMinecraftサーバーにコマンドを送信します。
			インスタンスへのコマンド送信には名前、もしくはプロファイルのどちらかを指定する必要があります。
			いずれの指定もなかった場合は、標準入力からプロファイルを取得します。

			--profile | -p
			    インスタンスを実行するための情報を記したプロファイルの場所を指定します。
			    名前を指定していない場合のみ必須です。
			    名前を指定している場合はこのオプションを指定することはできません。
			--name | -n
			    インスタンスの名前を指定します。
			    プロファイルを指定しない場合のみ必須です。
			    プロファイルを指定している場合はこのオプションを指定することはできません。
			--owner | -u
			    実行時のユーザーを指定します。
			    このオプションを指定するとプロファイルの設定を上書きします。
			--cwd
			    実行時の作業ディレクトリを指定します。
			    このオプションを指定するとプロファイルの設定を上書きします。
			__EOF
		}
		local args=()
		local profileflag=''
		local nameflag=''
		local ownerflag=''
		local cwdflag=''
		local helpflag=''
		local usageflag=''
		while (( $# > 0 ))
		do
			case $1 in
				--profile) 	shift; profileflag="$1"; shift;;
				--name) 	shift; nameflag="$1"; shift;;
				--owner)	shift; ownerflag="$1"; shift;;
				--cwd)  	shift; cwdflag="$1"; shift;;
				--help) 	helpflag='--help'; shift;;
				--usage)	usageflag='--usage'; shift;;
				--)	shift; break;;
				--*)	echo_invalid_flag "$1"; shift;;
				-*)
					[[ "$1" =~ p ]] && { if [[ "$1" =~ p$ ]]; then shift; profileflag="$1"; else profileflag=''; fi; }
					[[ "$1" =~ n ]] && { if [[ "$1" =~ n$ ]]; then shift; nameflag="$1"; else nameflag=''; fi; }
					[[ "$1" =~ u ]] && { if [[ "$1" =~ u$ ]]; then shift; ownerflag="$1"; else ownerflag=''; fi; }
					[[ "$1" =~ h ]] && { helpflag='-h'; }
					shift
					;;
				*)
					args=("${args[@]}" "$1")
					shift
					;;
			esac
		done
		while (( $# > 0 ))
		do
			args=("${args[@]}" "$1")
			shift
		done

		[ -n "$helpflag" ] && { version; echo; usage; echo; help; return; }
		[ -n "$usageflag" ] && { usage; return; }
		local servicename=''
		local cwd=''
		local owner=''
		if [ -n "$nameflag" ]; then
			[ -n "$profileflag" ] && { echoerr "mcsvutils: [E] プロファイルを指定した場合、名前の指定は無効です"; return $RESPONCE_ERROR; }
			servicename=$nameflag
		else
			if [ -n "$profileflag" ]; then profile_open "$profileflag" || return; else profile_open || return; fi
			profile_check_integrity || { echoerr "mcsvutils: [E] プロファイルのロードに失敗したため、中止します"; return $RESPONCE_ERROR; }
			servicename="$(profile_get_servicename)" || return $RESPONCE_ERROR
			owner="$(profile_get_owner)" || return $RESPONCE_ERROR
		fi
		[ -z "$servicename" ] && { echoerr "mcsvctrl: [E] インスタンスの名前が指定されていません"; return $RESPONCE_ERROR; }
		[ -n "$cwdflag" ] && cwd=$cwdflag
		[ -n "$ownerflag" ] && owner=$ownerflag
		[ -z "$cwd" ] && cwd="."
		[ -z "$owner" ] && owner="$(whoami)"
		send_command="${args[*]}"
		as_user "$owner" "screen -list \"$servicename\"" > /dev/null || { echo "mcsvutils: ${servicename} は起動していません"; return $RESPONCE_NEGATIVE; }
		local pre_log_length
		if [ "$cwd" != "" ]; then
			pre_log_length=$(as_user "$owner" "wc -l \"$cwd/logs/latest.log\"" | awk '{print $1}')
		fi
		echo "mcsvutils: ${servicename} にコマンドを送信しています..."
		echo "> $send_command"
		dispatch_mccommand "$owner" "$servicename" "$send_command"
		echo "mcsvutils: コマンドを送信しました"
		sleep .1
		echo "レスポンス:"
		as_user "$owner" "tail -n $(($(as_user "$owner" "wc -l \"$cwd/logs/latest.log\"" | awk '{print $1}') - pre_log_length)) \"$cwd/logs/latest.log\""
		return $RESPONCE_POSITIVE
	}

	# Analyze arguments --------------------
	local subcommand=""
	if [[ $1 =~ -.* ]] || [ "$1" = "" ]; then
		subcommand="none"
		while (( $# > 0 ))
		do
			case $1 in
				--help) 	helpflag='--help'; shift;;
				--usage)	usageflag='--usage'; shift;;
				--*)	echo_invalid_flag "$1"; shift;;
				-*)
					[[ "$1" =~ h ]] && { helpflag='-h'; }
					shift
					;;
				*)	break;;
			esac
		done
	else
		for item in "${SUBCOMMANDS[@]}"
		do
			[ "$item" == "$1" ] && {
				subcommand="$item"
				shift
				break
			}
		done
	fi
	[ -z "$subcommand" ] && { echoerr "mcsvutils: [E] 無効なサブコマンドを指定しました。"; usage >&2; return $RESPONCE_ERROR; }
	{ [ "$subcommand" == "help" ] || [ -n "$helpflag" ]; } && { version; echo; usage; echo; help; return; }
	[ -n "$usageflag" ] && { usage; return; }
	[ "$subcommand" == "none" ] && { echoerr "mcsvutils: [E] サブコマンドが指定されていません。"; echoerr "$0 server help で詳細なヘルプを表示します。"; usage >&2; return $RESPONCE_ERROR; }
	"action_server_$subcommand" "$@"
}

action_mcversions()
{
	usage()
	{
		cat <<- __EOF
		使用法: $0 mcversions [オプション] [クエリ]
		__EOF
	}
	help()
	{
		cat <<- __EOF
		mcversions はMinecraftサーバーのバージョン一覧を出力します。
		
		  --latest
		    最新のバージョンを表示する
		  --no-release
		    releaseタグの付いたバージョンを除外する
		  --snapshot
		    snapshotタグの付いたバージョンをリストに含める
		  --old-alpha
		    old_alphaタグの付いたバージョンをリストに含める
		  --old-beta
		    old_betaタグの付いたバージョンをリストに含める
		
		クエリに正規表現を用いて結果を絞り込むことができます。
		__EOF
	}
	local args=()
	local latestflag=''
	local no_releaseflag=''
	local snapshotflag=''
	local old_alphaflag=''
	local old_betaflag=''
	local helpflag=''
	local usageflag=''
	while (( $# > 0 ))
	do
		case $1 in
			--latest)   	latestflag="--latest"; shift;;
			--no-release)	no_releaseflag="--no-release"; shift;;
			--snapshot) 	snapshotflag="--snapshot"; shift;;
			--old-alpha) 	old_alphaflag="--old-alpha"; shift;;
			--old-beta) 	old_betaflag="--old-beta"; shift;;
			--help)     	helpflag='--help'; shift;;
			--usage)    	usageflag='--usage'; shift;;
			--)	shift; break;;
			--*)	echo_invalid_flag "$1"; shift;;
			-*)
				[[ "$1" =~ h ]] && { helpflag='-h'; }
				shift
				;;
			*)
				args=("${args[@]}" "$1")
				shift
				;;
		esac
	done
	while (( $# > 0 ))
	do
		args=("${args[@]}" "$1")
		shift
	done

	[ -n "$helpflag" ] && { version; echo; usage; echo; help; return; }
	[ -n "$usageflag" ] && { usage; return; }

	check || { oncheckfail; return $RESPONCE_ERROR; }
	fetch_mcversions || return $?
	if [ -n "$latestflag" ]; then
		if [ -z "$snapshotflag" ]; then
			echo "$VERSION_MANIFEST" | jq -r '.latest.release'
		else
			echo "$VERSION_MANIFEST" | jq -r '.latest.snapshot'
		fi
	else
		local select_types="false"
		[ -z "$no_releaseflag" ] && select_types="$select_types or .type == \"release\""
		[ -n "$snapshotflag" ] && select_types="$select_types or .type == \"snapshot\""
		[ -n "$old_betaflag" ] && select_types="$select_types or .type == \"old_beta\""
		[ -n "$old_alphaflag" ] &&  select_types="$select_types or .type == \"old_alpha\""
		local select_ids
		if [ ${#args[@]} -ne 0 ]; then
			select_ids="false"
			for search_query in "${args[@]}"
			do
				select_ids="$select_ids or test( \"$search_query\" )"
			done
		else
			select_ids="true"
		fi
		local result
		mapfile -t result < <(echo "$VERSION_MANIFEST" | jq -r ".versions[] | select( $select_types ) | .id | select( $select_ids )")
		if [ ${#result[@]} -ne 0 ]; then
			for item in "${result[@]}"
			do
				echo "$item"
			done
			return $RESPONCE_POSITIVE
		else
			echoerr "mcsvutils: 対象となるバージョンが存在しません"
			return $RESPONCE_NEGATIVE
		fi
	fi
}

action_mcdownload()
{
	usage()
	{
		cat <<- __EOF
		使用法: $0 mcdownload <バージョン> [保存先]
		__EOF
	}
	help()
	{
		cat <<- __EOF
		mcdownloadはMinecraftサーバーのjarをダウンロードします。
		<バージョン>に指定可能なものは$0 mcversionsで確認可能です。
		__EOF
	}
	local args=()
	local helpflag=''
	local usageflag=''
	while (( $# > 0 ))
	do
		case $1 in
			--help)     	helpflag='--help'; shift;;
			--usage)    	usageflag='--usage'; shift;;
			--)	shift; break;;
			--*)	echo_invalid_flag "$1"; shift;;
			-*)
				[[ "$1" =~ h ]] && { helpflag='-h'; }
				shift
				;;
			*)
				args=("${args[@]}" "$1")
				shift
				;;
		esac
	done
	while (( $# > 0 ))
	do
		args=("${args[@]}" "$1")
		shift
	done

	[ -n "$helpflag" ] && { version; echo; usage; echo; help; return; }
	[ -n "$usageflag" ] && { usage; return; }

	check || { oncheckfail; return $RESPONCE_ERROR; }
	fetch_mcversions
	if [ ${#args[@]} -lt 1 ]; then
		echoerr "mcsvutils: [E] ダウンロードするMinecraftのバージョンを指定する必要があります"
		return $RESPONCE_ERROR
	fi
	local selected_version
	selected_version="$(echo "$VERSION_MANIFEST" | jq ".versions[] | select( .id == \"${args[0]}\" )")"
	if [ "$selected_version" = "" ]; then
		echoerr "mcsvutils: 指定されたバージョンは見つかりませんでした"
		return $RESPONCE_NEGATIVE
	fi
	echo "mcsvutils: ${args[0]} のカタログをダウンロードしています..."
	selected_version=$(curl "$(echo "$selected_version" | jq -r '.url')")
	if ! [ $? ]; then
		echoerr "mcsvutils: [E] カタログのダウンロードに失敗しました"
		return $RESPONCE_ERROR
	fi
	local dl_data
	local dl_sha1
	dl_data=$(echo "$selected_version" | jq -r '.downloads.server.url')
	dl_sha1=$(echo "$selected_version" | jq -r '.downloads.server.sha1')
	local destination
	if [ "${args[1]}" != "" ]; then
		destination="${args[1]}"
	else
		destination="$(basename "$dl_data")"
	fi
	echo "mcsvutils: データをダウンロードしています..."
	if ! wget "$dl_data" -O "$destination"; then
		echoerr "mcsvutils: [E] データのダウンロードに失敗しました"
		return $RESPONCE_ERROR
	fi
	if [ "$(sha1sum "$destination" | awk '{print $1}')" = "$dl_sha1" ]; then
		echo "mcsvutils: データのダウンロードが完了しました"
		return
	else
		echoerr "mcsvutils: [W] データのダウンロードが完了しましたが、チェックサムが一致しませんでした"
		return $RESPONCE_ERROR
	fi
}

action_spigotbuild()
{
	usage()
	{
		cat <<- __EOF
		使用法: $0 spigotbuild <バージョン> [保存先]
		__EOF
	}
	help()
	{
		cat <<- __EOF
		mcdownloadはSpigotサーバーのビルドツールをダウンロードし、Minecraftサーバーからビルドします。
		<バージョン>に指定可能なものは https://www.spigotmc.org/wiki/buildtools/#versions を確認してください。
		__EOF
	}
	local args=()
	local helpflag=''
	local usageflag=''
	while (( $# > 0 ))
	do
		case $1 in
			--help)     	helpflag='--help'; shift;;
			--usage)    	usageflag='--usage'; shift;;
			--)	shift; break;;
			--*)	echo_invalid_flag "$1"; shift;;
			-*)
				[[ "$1" =~ h ]] && { helpflag='-h'; }
				shift
				;;
			*)
				args=("${args[@]}" "$1")
				shift
				;;
		esac
	done
	while (( $# > 0 ))
	do
		args=("${args[@]}" "$1")
		shift
	done

	[ -n "$helpflag" ] && { version; echo; usage; echo; help; return; }
	[ -n "$usageflag" ] && { usage; return; }

	check || { oncheckfail; return $RESPONCE_ERROR; }
	[ ${#args[@]} -lt 1 ] && { echoerr "mcsvutils: [E] ビルドするMinecraftのバージョンを指定する必要があります"; return $RESPONCE_ERROR; }
	local selected_version="${args[0]}"
	local work_dir
	work_dir="$TEMP/mcsvutils-$(cat /proc/sys/kernel/random/uuid)"
	(
		mkdir -p "$work_dir" || { echoerr "mcsvutils: [E] 作業用ディレクトリを作成できませんでした"; return $RESPONCE_ERROR; }
		cd "$work_dir" || { echoerr "mcsvutils: [E] 作業用ディレクトリに入れませんでした"; return $RESPONCE_ERROR; }
		wget "$SPIGOT_BUILDTOOLS_LOCATION" || { echoerr "mcsvutils: [E] BuildTools.jar のダウンロードに失敗しました"; return $RESPONCE_ERROR; }
		java -jar BuildTools.jar --rev "$selected_version" || { echoerr "mcsvutils: [E] Spigotサーバーのビルドに失敗しました。詳細はログを確認してください。"; return $RESPONCE_ERROR; }
	)
	local destination="./"
	[ ${#args[@]} -ge 2 ] && destination=${args[1]}
	if [ -e "${work_dir}/spigot-${selected_version}.jar" ]; then
		mv "${work_dir}/spigot-${selected_version}.jar" "$destination" || { echoerr "[E] jarファイルの移動に失敗しました。"; return $RESPONCE_ERROR; }
		rm -rf "$work_dir"
		return $RESPONCE_POSITIVE
	else
		echoerr "[W] jarファイルの自動探索に失敗しました。ファイルは移動されません。"
		return $RESPONCE_NEGATIVE
	fi
}

action_check()
{
	usage()
	{
		cat <<- __EOF
		使用法: $0 check
		__EOF
	}
	help()
	{
		cat <<- __EOF
		checkはこのスクリプトの動作要件のチェックを行います。
		チェックに成功した場合 $RESPONCE_POSITIVE 、失敗した場合は $RESPONCE_NEGATIVE を返します。
		checkに失敗した場合は必要なパッケージが不足していないか確認してください。
		__EOF
	}
	local helpflag=''
	local usageflag=''
	local args=()
	while (( $# > 0 ))
	do
		case $1 in
			--help) 	helpflag='--help'; shift;;
			--usage)	usageflag='--usage'; shift;;
			--)	shift; break;;
			--*)	echo_invalid_flag "$1"; shift;;
			-*)
				[[ "$1" =~ h ]] && { helpflag='-h'; }
				shift
				;;
			*)
				args=("${args[@]}" "$1")
				shift
				;;
		esac
	done
	while (( $# > 0 ))
	do
		args=("${args[@]}" "$1")
		shift
	done

	[ -n "$helpflag" ] && { version; echo; usage; echo; help; return; }
	[ -n "$usageflag" ] && { usage; return; }
	if check ;then
		echo "mcsvutils: チェックに成功しました。"
		return $RESPONCE_POSITIVE
	else
		echo "mcsvutils: チェックに失敗しました。"
		return $RESPONCE_NEGATIVE
	fi
}

action_version()
{
	version
	return $RESPONCE_POSITIVE
}

action_usage()
{
	usage
	return $RESPONCE_POSITIVE
}

action_help()
{
	version
	echo
	usage
	echo
	help
	return $RESPONCE_POSITIVE
}

action_none()
{
	if [ "$helpflag" != "" ]; then
		action_help
		return $?
	elif [ "$usageflag" != "" ]; then
		action_usage
		return $?
	elif [ "$versionflag" != "" ]; then
		action_version
		return $?
	else
		echoerr "mcsvutils: [E] アクションが指定されていません。"
		usage >&2
		return $RESPONCE_ERROR
	fi
}

# Analyze arguments --------------------
subcommand=""
if [[ $1 =~ -.* ]] || [ "$1" = "" ]; then
	subcommand="none"
	while (( $# > 0 ))
	do
		case $1 in
			--help) 	helpflag='--help'; shift;;
			--usage)	usageflag='--usage'; shift;;
			--*)	echo_invalid_flag "$1"; shift;;
			-*)
				[[ "$1" =~ h ]] && { helpflag='-h'; }
				shift
				;;
			*)	break;;
		esac
	done
else
	for item in "${SUBCOMMANDS[@]}"
	do
		[ "$item" == "$1" ] && {
			subcommand="$item"
			shift
			break
		}
	done
fi

if [ -n "$subcommand" ]
	then "action_$subcommand" "$@"; exit $?
	else echoerr "mcsvutils: [E] 無効なアクションを指定しました。"; usage >&2; return $RESPONCE_ERROR
fi
