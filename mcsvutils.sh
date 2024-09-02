#! /bin/bash

: <<- __License
MIT License

Copyright (c) 2020-2024 zawa-ch.

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

__main() {
version() {
	cat <<-__EOF
	mcsvutils - Minecraft server commandline utilities
	version 1.0.0-beta1 2024-__-__
	Copyright 2020-2024 zawa-ch.
	This program is provided under the MIT License.
	__EOF
}

## constants ------------------------ ##

local -r VERSION_MANIFEST_LOCATION='https://launchermeta.mojang.com/mc/game/version_manifest.json'
local -r SPIGOT_BUILDTOOLS_LOCATION='https://hub.spigotmc.org/jenkins/job/BuildTools/lastSuccessfulBuild/artifact/target/BuildTools.jar'
local -r PROFILE_VERSION=3
local -r REPO_VERSION=2

## Variables ------------------------ ##

# Minecraft server image repository
local MCSVUTILS_IMAGE_REPOSITORY="$MCSVUTILS_IMAGE_REPOSITORY"
[ -n "$MCSVUTILS_IMAGE_REPOSITORY" ] || {
	if [ -n "$XDG_DATA_HOME" ]; then
		MCSVUTILS_IMAGE_REPOSITORY="$XDG_DATA_HOME/mcsvutils/versions"
	else
		MCSVUTILS_IMAGE_REPOSITORY="$HOME/.local/share/mcsvutils/versions"
	fi
}
MCSVUTILS_IMAGE_REPOSITORY="$(readlink -f "$MCSVUTILS_IMAGE_REPOSITORY")"
local -r MCSVUTILS_IMAGE_REPOSITORY
# mcsvutils runtime directory
local MCSVUTILS_RUNTIME="$MCSVUTILS_RUNTIME"
[ -n "$MCSVUTILS_RUNTIME" ] || {
	if [ -n "$XDG_STATE_HOME" ]; then
		MCSVUTILS_RUNTIME="$XDG_STATE_HOME/mcsvutils/versions"
	else
		MCSVUTILS_RUNTIME="$HOME/.local/state/mcsvutils"
	fi
}
MCSVUTILS_RUNTIME="$(readlink -f "$MCSVUTILS_RUNTIME")"
local -r MCSVUTILS_RUNTIME

## Help ----------------------------- ##

local -r allowed_subcommands=("profile" "server" "image" "piston" "spigot" "version" "help" "usage")
local -r requirement_commands=("cat" "mkfifo" "mktemp" "readlink" "basename" "bash" "jq" "wget" "curl")
usage() {
	cat <<- __EOF
	usage: $0 <subcommand> ...
	subcommands: ${allowed_subcommands[@]}
	__EOF
}
help() {
	version
	cat <<- __EOF

	usage: $0 <subcommand> ...
	subcommands: ${allowed_subcommands[@]}
	  profile  Manage profiles
	  server   Manage server instance
	  image    Manage Minecraft server image repository
	  piston   Manage Minecraft vanilla server images
	  spigot   Manage CraftBukkit/Spigot server images
	  version  Show version
	  help     Show this help
	  usage    Show usage

	For detailed help on each subcommand, add the --help option to subcommand.

	The following options are available for all subcommands:
	--help | -h Show help
	--usage     Show usage
	--          Do not parse subsequent options

	This script runs the following commands:
	  ${requirement_commands[@]}
	In environments where these commands cannot be executed, almost all operations cannot be performed.
	__EOF
}

## Functions ------------------------ ##

assert_precond() {
	suplessed_cmd() { "$@" >/dev/null 2>/dev/null; }
	on_failure() { echo "mcsvutils: A required packages are not installed." >&2; return 2; }
	suplessed_cmd bash --version || { on_failure; return; }
	suplessed_cmd jq --version || { on_failure; return; }
	suplessed_cmd wget --version || { on_failure; return; }
	suplessed_cmd curl --version || { on_failure; return; }
	return 0
}

ask_or_no() {
	echo -n "${1}${1:+ }[y/N]: "
	read -r ans
	[ "$ans" == "y" ] || [ "$ans" == "Y" ] || [ "$ans" == "yes" ] || [ "$ans" == "Yes" ] || [ "$ans" == "YES" ]
}

process_stat() {
	jq -Rc -f <(cat <<<'capture("(?<pid>[0-9]+) \\((?<tcomm>.*)\\) (?<state>[RSDZT]) (?<ppid>[0-9]+) (?<pgrp>[0-9]+) (?<sid>[0-9]+) (?<tty_nr>[0-9]+) (?<tty_pgrp>[0-9]+) (?<flags>[0-9]+) (?<min_flt>[0-9]+) (?<cmin_flt>[0-9]+) (?<maj_flt>[0-9]+) (?<cmaj_flt>[0-9]+) (?<utime>[0-9]+) (?<stime>[0-9]+) (?<cutime>[0-9]+) (?<cstime>[0-9]+) (?<priority>[0-9]+) (?<nice>[0-9]+) (?<num_threads>[0-9]+) (?<it_real_value>[0-9]+) (?<start_time>[0-9]+) (?<vsize>[0-9]+) (?<rss>[0-9]+) (?<rsslim>[0-9]+) (?<start_code>[0-9]+) (?<end_code>[0-9]+) (?<start_stack>[0-9]+) (?<esp>[0-9]+) (?<eip>[0-9]+) (?<pending>[0-9]+) (?<blocked>[0-9]+) (?<sigign>[0-9]+) (?<sigcatch>[0-9]+) [0-9]+ 0 0 (?<exit_signal>[0-9]+) (?<task_cpu>[0-9]+) (?<rt_priority>[0-9]+) (?<policy>[0-9]+) (?<blkio_ticks>[0-9]+) (?<gtime>[0-9]+) (?<cgtime>[0-9]+) (?<start_data>[0-9]+) (?<end_data>[0-9]+) (?<start_blk>[0-9]+) (?<arg_start>[0-9]+) (?<arg_end>[0-9]+) (?<env_start>[0-9]+) (?<env_end>[0-9]+) (?<exit_code>[0-9]+)")|map_values(if test("[0-9]+") then tonumber else . end)') "/proc/$1/stat"
}

fetch_piston_manifest() {
	curl -s "$VERSION_MANIFEST_LOCATION"
}

load_json_file() {
	[ $# -ge 1 ] || { echo "mcsvutils: File not specified." >&2; return 2; }
	jq -c '.' -- "$1"
}

load_json_stdin() {
	jq -c '.'
}

integrity_errstr() {
	local ec;	ec=$(cat)
	case "$ec" in
	OK)	;;
	JSON_READ_ERROR)	echo "Input is not JSON";;
	JSON_CONTEXT_INVALID)	echo "Unable to determine context";;
	PROFILE_CONTEXT_ERROR)	echo "A non-profile context was detected";;
	PROFILE_VERSION_INVALID)	echo "Unable to determine profile context";;
	PROFILE_UPGRADE_NEEDED)	echo "Profile version outdated";;
	PROFILE_VERSION_UNSUPPORTED)	echo "Unsupported profile version";;
	PROFILE_REQUIRED_ELEMENT_MISSING)	echo "Required element is missing";;
	PROFILE_ELEMENT_TYPE_ERROR)	echo "Invalid combination of element and type";;
	PROFILE_EMPTY_STRING)	echo "An empty string was detected in an element that does not allow empty strings";;
	REPOSITORY_CONTEXT_ERROR)	echo "A non-repository context was detected";;
	REPOSITORY_VERSION_INVALID)	echo "Unable to determine repository context";;
	REPOSITORY_UPGRADE_NEEDED)	echo "Repository version outdated";;
	REPOSITORY_VERSION_UNSUPPORTED)	echo "Unsupported repository version";;
	REPOSITORY_REQUIRED_ELEMENT_MISSING)	echo "Required element is missing";;
	REPOSITORY_ELEMENT_TYPE_ERROR)	echo "Invalid combination of element and type";;
	REPOSITORY_EMPTY_STRING)	echo "An empty string was detected in an element that does not allow empty strings";;
	*)	echo "An unknown error has occurred";;
	esac
}

profile_check_integrity() {
	local profile; profile=$(load_json_stdin 2>/dev/null) || { echo "JSON_READ_ERROR"; return 1; }
	local r; r=$(echo "$profile" | jq -r --argjson profile_version "$PROFILE_VERSION" '. as $profile | (if type=="object" then null else "JSON_CONTEXT_INVALID" end) // (if has("@context") then null else (if (.version|type=="number" and .>=1 and .<= 2) then "PROFILE_UPGRADE_NEEDED" else "JSON_CONTEXT_INVALID" end) end) // (."@context" | if type=="object" then null else "JSON_CONTEXT_INVALID" end) // (if ."@context".name=="mcsvutils.profile" then null else "PROFILE_CONTEXT_ERROR" end) // (."@context".version | if type=="number" then null else "PROFILE_VERSION_INVALID" end) // (."@context".version | if .==$profile_version then null elif . < $profile_version then "PROFILE_UPGRADE_NEEDED" else "PROFILE_VERSION_UNSUPPORTED" end) // (if ([has("servicename"), has("imagetag")]|all) then null else "PROFILE_REQUIRED_ELEMENT_MISSING" end) // (if ([(.servicename|type=="string"), (.imagetag|type=="string"), (.jvm|type== "null" or type=="array"), (.jvm|type=="array" and (map(type!="string")|any)|not), (.arguments|type=="null" or type=="array"), (.arguments|type=="array" and (map(type!="string")|any)|not), (.cwd|type=="null" or type=="string"), (.jre|type=="null" or type=="string")]|all) then null else "PROFILE_ELEMENT_TYPE_ERROR" end) // (if ([(.servicename|length > 0), (.imagetag|length > 0), (.cwd|type=="string" and length<=0|not), (.jre|type=="string" and length<=0|not)]|all) then null else "PROFILE_EMPTY_STRING" end) // "OK"')
	echo "$r"
	[ "$r" == "OK" ]
}

profile_check_integrity_v2() {
	local profile; profile=$(load_json_stdin 2>/dev/null) || { echo "JSON_READ_ERROR"; return 1; }
	local r; r=$(echo "$profile" | jq -r --argjson profile_version "$PROFILE_VERSION" '. as $profile | (if type=="object" then null else "PROFILE_CONTEXT_ERROR" end) // (.version | if type=="number" then null else "PROFILE_VERSION_INVALID" end) // (.version | if .==2 then null elif .<2 then "PROFILE_UPGRADE_NEEDED" else "PROFILE_VERSION_UNSUPPORTED" end) // (if ([has("servicename"), has("executejar") or has("imagetag")]|all) then null else "PROFILE_REQUIRED_ELEMENT_MISSING" end) // if ([(.name|type=="string"), (.executejar|type=="string" or type=="null"), (.imagetag|type=="string" or type=="null"), (.executejar|type=="string") or (.imagetag|type=="string"), (.options|type=="array"), (.args|type=="array")]|all) then null else "PROFILE_ELEMENT_TYPE_ERROR" end) // (if ([(.name|length>0), (((.executejar//"")+(.imagetag//""))|length>0)]|all) then null else "PROFILE_EMPTY_STRING" end) // "OK"')
	echo "$r"
	[ "$r" == "OK" ]
}

profile_check_integrity_v1() {
	local profile; profile=$(load_json_stdin 2>/dev/null) || { echo "JSON_READ_ERROR"; return 1; }
	local r; r=$(echo "$profile" | jq -r --argjson profile_version "$PROFILE_VERSION" '. as $profile | (if type=="object" then null else "PROFILE_CONTEXT_ERROR" end) // (.version | if type=="number" then null else "PROFILE_VERSION_INVALID" end) // (.version | if .==1 then null else "PROFILE_VERSION_UNSUPPORTED" end) // (if ([has("name"), has("execute")]|all) then null else "PROFILE_REQUIRED_ELEMENT_MISSING" end) // if ([(.name|type=="string"), (.execute|type=="string"), (.options|type=="array"), (.args|type=="array")]|all) then null else "PROFILE_ELEMENT_TYPE_ERROR" end) // (if ([(.name|length>0), (.execute|length>0)]|all) then null else "PROFILE_EMPTY_STRING" end) // "OK"')
	echo "$r"
	[ "$r" == "OK" ]
}

profile_upgrade() {
	local profile;	profile=$(load_json_stdin 2>/dev/null) || return 1
	local profile_err;	profile_err=$(echo "$profile" | profile_check_integrity)
	[ "$profile_err" != "OK" ] || { echo "$profile"; return 0; }
	[ "$profile_err" == "PROFILE_UPGRADE_NEEDED" ] || return 1
	local p_ver;	p_ver=$(echo "$profile" | jq -c '.version')
	# shellcheck disable=SC2016
	cat_jq_upgradev2_code() { cat <<<'if .version == 1 then . else ("Invalid version.\n" | error) end | if has("name") and (.name|type=="string") then . else ("Schema error.\n" | error) end | if has("execute") and (.execute|type=="string") then . else ("Schema error.\n" | error) end | { version: 2, servicename: .name, imagetag: null, executejar: .execute, options, arguments: .args, cwd: (.cwd|if type == "string" then . else null end), jre: (.javapath|if type == "string" then . else null end), owner: (.owner|if type == "string" then . else null end) }'; }
	# shellcheck disable=SC2016
	cat_jq_upgradev3_code() { cat <<<'if .version == 2 then . else ("Invalid version.\n" | error) end | if has("servicename") and (.servicename|type=="string") and ((has("imagetag") and (.imagetag|type=="string" and length>0) and (has("executejar") and (.executejar|type!="null")|not)) or (has("executejar") and (.executejar|type=="string" and length>0) and (has("imagetag") and (.imagetag|type!="null")|not))) then . else ("Schema error.\n" | error) end | { "@context": { name: "mcsvutils.profile", version: 3}, servicename, imagetag, jvm: (.options|if type=="array" then map(select(type=="string")) else [] end), arguments: (.arguments|if type=="array" then map(select(type=="string")) else [] end), cwd: (.cwd|if type == "string" then . else null end), jre: (.jre|if type == "string" then . else null end) }'; }
	while [ "$p_ver" -lt "$PROFILE_VERSION" ]; do
	case "$p_ver" in
		"1")	profile="$(echo "$profile" | jq -c -f <(cat_jq_upgradev2_code))" || return;;
		"2")	profile="$(echo "$profile" | jq -c -f <(cat_jq_upgradev3_code))" || return;;
	esac
		p_ver=$(( p_ver + 1 ))
	done
	echo "$profile"
}

imagerepo_mkdir() {
	# shellcheck disable=SC2015
	[ -d "$MCSVUTILS_IMAGE_REPOSITORY" ] && [ -w "$MCSVUTILS_IMAGE_REPOSITORY" ] && [ -O "$MCSVUTILS_IMAGE_REPOSITORY" ] && [ -x "$MCSVUTILS_IMAGE_REPOSITORY" ] || {
		mkdir -p "$MCSVUTILS_IMAGE_REPOSITORY" && chmod -R u=rwX,go=rX "$MCSVUTILS_IMAGE_REPOSITORY" || { echo "mcsvutils: Could not configure repository." >&2; return 1; }
	}
}

imagerepo_load() {
	init_repo() { jq -nc --argjson version "$REPO_VERSION" '{"@context": {name: "mcsvutils.repository", version: $version}, images: [], aliases: []}'; }
	# shellcheck disable=SC2015
	[ -d "$MCSVUTILS_IMAGE_REPOSITORY" ] &&  [ -f "$MCSVUTILS_IMAGE_REPOSITORY/repository.json" ] || { init_repo; return; }
	# shellcheck disable=SC2015
	[ -O "$MCSVUTILS_IMAGE_REPOSITORY" ] && [ -x "$MCSVUTILS_IMAGE_REPOSITORY" ] && [ -r "$MCSVUTILS_IMAGE_REPOSITORY/repository.json" ] || { echo "mcsvutils: Could not configure repository folder." >&2; return 1; }
	jq -c '.' -- "$MCSVUTILS_IMAGE_REPOSITORY/repository.json"
}

imagerepo_save() {
	local temp_repos
	# shellcheck disable=SC2317
	cleanup() {
		[ -n "$temp_repos" ] && [ -e "$temp_repos" ] && rm -f -- "${temp_repos:?}"
	}
	trap cleanup RETURN
	imagerepo_mkdir || return
	# shellcheck disable=SC2015
	[ -f "$MCSVUTILS_IMAGE_REPOSITORY/repository.json" ] && [ -w "$MCSVUTILS_IMAGE_REPOSITORY/repository.json" ] || {
		touch "$MCSVUTILS_IMAGE_REPOSITORY/repository.json" && chmod u=rw,go=r "$MCSVUTILS_IMAGE_REPOSITORY/repository.json" || { echo "mcsvutils: Could not configure repository." >&2; return 1; }
	}
	temp_repos=$(mktemp -p "$MCSVUTILS_IMAGE_REPOSITORY") && chmod u=rw,go=r "$temp_repos" && jq -c '.' >"$temp_repos" || return
	mv --exchange -fT "$temp_repos" "$MCSVUTILS_IMAGE_REPOSITORY/repository.json"
}

imagerepo_dbnuke() {
	rm -rf -- "$MCSVUTILS_IMAGE_REPOSITORY"
}

imagerepo_check_integrity() {
	local repo; repo=$(jq -c '.') || { echo "JSON_READ_ERROR"; return 1; }
	local r; r=$(echo "$repo" | jq -r --argjson repository_version "$REPO_VERSION" '. as $repo | (if type=="object" then null else "JSON_CONTEXT_INVALID" end) // (if ."@context"|type=="object" then null else (if (.version|type=="number" and .==1) then "REPOSITORY_UPGRADE_NEEDED" else "JSON_CONTEXT_INVALID" end) end) // (if ."@context".name=="mcsvutils.repository" then null else "REPOSITORY_CONTEXT_ERROR" end) // (if ."@context".version|type=="number" then null else "REPOSITORY_VERSION_INVALID" end) // (if ."@context".version==$repository_version then null elif ."@context".version<$repository_version then "REPOSITORY_UPGRADE_NEEDED" else "REPOSITORY_VERSION_UNSUPPORTED" end) // (if [has("images"), has("aliases")]|all then null else "REPOSITORY_REQUIRED_ELEMENT_MISSING" end) // (if [(.images|type=="array" and all(type=="object")), (.aliases|type=="array" and all(type=="object"))]|all then null else "REPOSITORY_ELEMENT_TYPE_ERROR" end) // (if .images|all([(.id|type=="string"), (.path|type=="string"), (.size|type=="number" or type=="null"), (.sha1|type=="string" or type=="null"), (.sha256|type=="string" or type=="null")]|all) then null else "REPOSITORY_ELEMENT_TYPE_ERROR" end) // (if .aliases|all([(.id|type=="string"), (.reference|type=="string")]|all) then null else "REPOSITORY_ELEMENT_TYPE_ERROR" end) // (if .images|all([(.id|length>0), (.path|length>0)]|all) then null else "REPOSITORY_EMPTY_STRING" end) // (if .aliases|all([(.id|length>0), (.reference|length>0)]|all) then null else "REPOSITORY_EMPTY_STRING" end) // "OK"')
	echo "$r"
	[ "$r" == "OK" ]
}

imagerepo_list_tags() {
	jq -c '(.images|map(.+{type:"image"}))+(.images as $images|.aliases|map(.+{type:"alias",reference:(.reference as $target|$images|map(select(.id==$target))|if length==1 then .[0] else null end)}))'
}

imagerepo_tag_is_exist() {
	imagerepo_list_tags | jq -e --arg tag "$1" 'map(.id)|index($tag)!=null' >/dev/null
}

imagerepo_get_by_tag() {
	imagerepo_list_tags | jq -ce --arg query "$1" '(map(.id)|index($query)) as $i|if $i!=null then .[$i] else null end'
}

imagerepo_id_is_exist() {
	jq -e --arg query "$1" '.images|map(.id)|index($query)!=null' >/dev/null
}

imagerepo_get_new_imageid() {
	local repo;	repo=$(jq -c '.') || return
	local result
	for _ in $(seq 255); do
		result=$(head -c 10 /dev/urandom | base32 | jq -Rr --slurp 'split("\n")|map(ascii_downcase)|join("")')
		echo "$repo" | imagerepo_tag_is_exist "$result" || break
	done
	echo "$repo" | { ! imagerepo_tag_is_exist "$result"; } || {
		echo "mcsvutils: The number of image ID generation attempts has been reached, but no meaningful image ID could be generated." >&2; return 1;
	}
	echo "$result"
}

imagerepo_normalize_path() {
	( cd "$MCSVUTILS_IMAGE_REPOSITORY" 2>/dev/null && readlink -m "$1" )
}

server_check_running() {
	local runtime="$MCSVUTILS_RUNTIME/$servicename"
	[ -d "$runtime" ] || return
	[ -f "$runtime/status" ] || return
	jq -c '.' "$runtime/status" >/dev/null || return
	local server_pid
	server_pid=$(jq -r '.pid' "$runtime/status") || return
	[ -d "/proc/$server_pid" ] || return
	local pstat
	pstat=$(process_stat "$server_pid")
	# shellcheck disable=SC2016
	jq -ec -f <(cat <<<'.pid==$pstat.[0].pid and .start_time==$pstat.[0].start_time') --slurpfile pstat <(echo "$pstat") "$runtime/status" >/dev/null
}

## Subcommands ---------------------- ##

subcommand_profile() {
	## profile/Help --------------------- ##

	local -r allowed_subcommands=("info" "create" "update" "help" "usage")
	usage() {
		cat <<- __EOF
		usage: $0 profile <subcommand> ...
		subcommands: ${allowed_subcommands[@]}
		__EOF
	}
	help() {
		cat <<- __EOF
		mcsvutils profile - Manage profiles

		usage: $0 profile <subcommand> ...
		subcommands: ${allowed_subcommands[@]}
		  info     Show profile infomation
		  create   Create profile
		  upgrade  Update profile format
		  help     Show this help
		  usage    Show usage

		For detailed help on each subcommand, add the --help option to subcommand.

		options:
		  --help | -h Show help
		  --usage     Show usage
		  --          Do not parse subsequent options
		__EOF
	}
	## profile/Subcommands -------------- ##

	subcommand_profile_info() {
		## profile/info/Help ---------------- ##

		usage() {
			cat <<- __EOF
			usage: $0 profile info [<options> ...] [<profile>]
			profile: path to profile
			__EOF
		}
		help() {
			cat <<- __EOF
			mcsvutils profile info - Show profile infomation

			usage: $0 profile info [<options> ...] [<profile>]
			profile: path to profile
			  If no file is specified, it will be read from standard input.
			
			options:
			  --stdin | -i
			    Read from standard input regardless of arguments
			    Exclusive with --file option
			  --file | -p
			    Abort as an error instead of reading from standard input when no file is specified
			    Exclusive with --stdin option
			  --help | -h
			    Show help
			  --usage
			    Show usage
			__EOF
		}

		## profile/info/Analyze args -------- ##

		local flag_stdin=
		local flag_file=
		local args=()
		local flag_help="$flag_help"
		local flag_usage="$flag_usage"
		while (( $# > 0 )); do case $1 in
			--stdin)	flag_stdin='true'; shift;;
			--file)		flag_file='true'; shift;;
			--help)		flag_help='true'; shift;;
			--usage)	flag_usage='true'; shift;;
			--)			shift;	break;;
			--*)		echo "mcsvutils: Invalid option $1" >&2;	usage >&2;	return 2;;
			-*)
				if [[ $1 =~ i ]]; then flag_stdin='true'; fi
				if [[ $1 =~ f ]]; then flag_file='true'; fi
				if [[ $1 =~ h ]]; then flag_help='true'; fi
				shift
				;;
			*)			args+=("$1");	shift;;
		esac done
		while (( $# > 0 )); do 
			args+=("$1");	shift;
		done

		[ -z "$flag_help" ] || { help; return; }
		[ -z "$flag_usage" ] || { usage; return; }
		assert_precond || return
		[ ${#args[@]} -le 1 ] || echo "mcsvutils: Trailing arguments will ignore." >&2

		local profile
		if [ -n "$flag_file" ] && [ ${#args[@]} -gt 0 ]; then
			profile=$(load_json_file "${args[0]}") || return
		elif [ -n "$flag_file" ]; then
			echo "mcsvutils: --file option was specified but no file was specified." >&2
			return 2
		elif [ -n "$flag_stdin" ]; then
			profile=$(load_json_stdin) || return
		elif [ ${#args[@]} -gt 0 ]; then
			profile=$(load_json_file "${args[0]}") || return
		else
			profile=$(load_json_stdin) || return
		fi
		[ -n "$profile" ] || { echo "mcsvutils: The input file is empty." >&2; return 1; }
		local profile_err
		profile_err=$(echo "$profile" | profile_check_integrity) || {
			echo "mcsvutils: Profile integrity error: $(echo "$profile_err" | integrity_errstr)" >&2
			return 1;
		}

		# shellcheck disable=SC2016
		echo "$profile" | jq -r -f <(cat <<<'[.servicename, "Exec image: \(.imagetag)", if (.jre|type=="string") then "Java env: \(.jre)" else empty end, if (.cwd|type=="string") then "Working directory: \(.cwd)" else empty end, if (.jvm|type=="array" and length>0) then "JVM arguments: \(.jvm|join(" "))" else empty end, if (.arguments|type=="array" and length>0) then "Default args: \(.arguments|join(" "))" else empty end]|join("\n")')
	} # subcommand_profile_info

	subcommand_profile_create() {
		## profile/create/Help -------------- ##

		usage() {
			cat <<- __EOF
			usage: $0 profile create [<options> ...] <name> <image>
			name: server instance name
			image: server image tag
			__EOF
		}
		help() {
			cat <<- __EOF
			mcsvutils profile create - Create profile

			usage: $0 profile create [<options> ...] <name> <image>
			name: server instance name
			image: server image tag

			options:
			  --cwd <path>
			    Working directory when running the server
			  --jre <path>
			    Java executable file used to run the server
			  --jvm <string>
			    Default jvm arguments when starting the server
			    You can include multiple options by specifying them multiple times.
			  --arg <string>
			    Default arguments when starting the server
			    You can include multiple options by specifying them multiple times.
			  --help | -h
			    Show help
			  --usage
			    Show usage

			If the command is successful, it will write the generated profile JSON to standard output.
			__EOF
		}

		## profile/info/Analyze args -------- ##

		local opt_cwd=
		local opt_jre=
		local opts_jvm=()
		local opts_arg=()
		local args=()
		local flag_help="$flag_help"
		local flag_usage="$flag_usage"
		while (( $# > 0 )); do case $1 in
			--cwd=*)		opt_cwd="${1#--cwd=}";	shift;;
			--cwd)		shift;	opt_cwd="$1";	shift;;
			--jre=*)		opt_jre="${1#--jre=}";	shift;;
			--jre)		shift;	opt_jre="$1";	shift;;
			--jvm=*)		opts_jvm+=("${1#--jvm=}");	shift;;
			--jvm)		shift;	opts_jvm+=("$1");	shift;;
			--arg=*)		opts_arg+=("${1#--arg=}");	shift;;
			--arg)		shift;	opts_arg+=("$1");	shift;;
			--help)		flag_help='true'; shift;;
			--usage)	flag_usage='true'; shift;;
			--)			shift;	break;;
			--*)		echo "mcsvutils: Invalid option $1" >&2;	usage >&2;	return 2;;
			-*)
				if [[ $1 =~ h ]]; then flag_help='true'; fi
				shift
				;;
			*)			args+=("$1");	shift;;
		esac done
		while (( $# > 0 )); do 
			args+=("$1");	shift;
		done

		[ -z "$flag_help" ] || { help; return; }
		[ -z "$flag_usage" ] || { usage; return; }
		assert_precond || return
		[ ${#args[@]} -ge 2 ] || { echo "mcsvutils: Too few arguments" >&2; usage >&2; return 2; }
		[ ${#args[@]} -le 2 ] || echo "mcsvutils: Trailing arguments will ignore." >&2
		local p_name="${args[0]}"
		local p_imgtag="${args[1]}"
		[ -n "$p_name" ] || { echo "mcsvutils: Empty name not allowed" >&2; usage >&2; return 2; }
		[ -n "$p_imgtag" ] || { echo "mcsvutils: Empty image tag not allowed" >&2; usage >&2; return 2; }
		# todo: イメージタグが実際に存在することを確認
		# todo: jreが実際に存在することを確認
		# todo: 作業ディレクトリが実際に存在することを確認
		local p_jvm;	p_jvm="$(jq -nc '$ARGS.positional' --args -- "${opts_jvm[@]}")" || return
		local p_args;	p_args="$(jq -nc '$ARGS.positional' --args -- "${opts_arg[@]}")" || return

		# shellcheck disable=SC2016
		jq -nc --argjson version "$PROFILE_VERSION" --arg pname "$p_name" --arg pimgtag "$p_imgtag" --arg pcwd "$opt_cwd" --arg pjre "$opt_jre" --slurpfile popts <(echo "$p_jvm") --slurpfile pargs <(echo "$p_args") '{ "@context": { name: "mcsvutils.profile", version: $version }, servicename: $pname, imagetag: $pimgtag, cwd: (if $pcwd|type=="string" and length>0 then $pcwd else null end), jre: (if $pjre|type=="string" and length>0 then $pjre else null end), jvm: $popts.[0], arguments: $pargs.[0] }'
	} # subcommand_profile_create

	subcommand_profile_update() {
		## profile/update/Help -------------- ##

		usage() {
			cat <<- __EOF
			usage: $0 profile update [<options> ...] [<profile>]
			profile: path to profile
			__EOF
		}
		help() {
			cat <<- __EOF
			mcsvutils profile update - Update profile

			usage: $0 profile update [<options> ...] [<profile>]
			profile: path to profile
			  If no file is specified, it will be read from standard input.

			options:
			  --stdin | -i
			    Read from standard input regardless of arguments
			    Exclusive with --file option
			  --file | -p
			    Abort as an error instead of reading from standard input when no file is specified
			    Exclusive with --stdin option
			  --rename <new_name>
			    Rename service name
			  --image <imagetag>
			    Override execute server image
			  --cwd <path>
			    Override working directory
			  --jre <path>
			    Override Java runtime
			  --jvm <string>
			    Override jvm arguments
			    You can include multiple options by specifying them multiple times.
			    If this option is specified, it clears the contents of any existing options in profile.
			    If no options are specified, the options of the input profile will be inherited.
			    If you simply want to delete options, use the --clear-jvmopts flag.
			    This flag is exclusive from the --clear-jvmopts flag.
			  --clear-jvmopts
			    Do not inherit any options contained in the profile and leave it empty.
			    This flag is exclusive from the --option flag.
			  --arg <string>
			    Default arguments when starting the server
			    You can include multiple options by specifying them multiple times.
			    If this option is specified, it clears the contents of any existing options in profile.
			    If no options are specified, the options of the input profile will be inherited.
			    If you simply want to delete options, use the --clear-args flag.
			    This flag is exclusive from the --clear-args flag.
			  --clear-args
			    Do not inherit any arguments contained in the profile and leave it empty.
			    This flag is exclusive from the --arg flag.
			  --allow-destructive-upgrade
			    Allow backwards-incompatible upgrades
			  --help | -h
			    Show help
			  --usage
			    Show usage
			
			If the command is successful, it will write the generated profile JSON to standard output.
			__EOF
		}

		## profile/info/Analyze args -------- ##

		local flag_stdin=
		local flag_file=
		local opt_rename=
		local opt_image=
		local opt_cwd=
		local opt_jre=
		local opts_jvm=()
		local flag_clear_jvmopts=
		local opts_arg=()
		local flag_clear_args=
		local flag_allow_destructive_upgrade=
		local args=()
		local flag_help="$flag_help"
		local flag_usage="$flag_usage"
		while (( $# > 0 )); do case $1 in
			--stdin)	flag_stdin='true'; shift;;
			--file)		flag_file='true'; shift;;
			--rename=*)	opt_rename="${1#--rename=}";	shift;;
			--rename)	shift;	opt_rename="$1";	shift;;
			--image=*)	opt_image="${1#--image=}";	shift;;
			--image)	shift;	opt_image="$1";	shift;;
			--cwd=*)	opt_cwd="${1#--cwd=}";	shift;;
			--cwd)		shift;	opt_cwd="$1";	shift;;
			--jre=*)	opt_jre="${1#--jre=}";	shift;;
			--jre)		shift;	opt_jre="$1";	shift;;
			--jvm=*)	opts_jvm+=("${1#--jvm=}");	shift;;
			--jvm)		shift;	opts_jvm+=("$1");	shift;;
			--clear-jvmopts)
				flag_clear_jvmopts='true';	shift;;
			--arg=*)	opts_arg+=("${1#--arg=}");	shift;;
			--arg)		shift;	opts_arg+=("$1");	shift;;
			--clear-args)
				flag_clear_args='true';	shift;;
			--allow-destructive-upgrade)
				flag_allow_destructive_upgrade='true';	shift;;
			--help)		flag_help='true'; shift;;
			--usage)	flag_usage='true'; shift;;
			--)			shift;	break;;
			--*)		echo "mcsvutils: Invalid option $1" >&2;	usage >&2;	return 2;;
			-*)
				if [[ $1 =~ i ]]; then flag_stdin='true'; fi
				if [[ $1 =~ f ]]; then flag_file='true'; fi
				if [[ $1 =~ h ]]; then flag_help='true'; fi
				shift
				;;
			*)			args+=("$1");	shift;;
		esac done
		while (( $# > 0 )); do 
			args+=("$1");	shift;
		done

		[ -z "$flag_help" ] || { help; return; }
		[ -z "$flag_usage" ] || { usage; return; }
		assert_precond || return
		[ ${#args[@]} -le 1 ] || echo "mcsvutils: Trailing arguments will ignore." >&2
		[ ${#opts_jvm[@]} -le 0 ] || [ -z "$flag_clear_jvmopts" ] || {
			echo "--option flag and --clear-options are exclusive." >&2
			return 2
		}
		[ ${#opts_arg[@]} -le 0 ] || [ -z "$flag_clear_args" ] || {
			echo "--arg flag and --clear-args are exclusive." >&2
			return 2
		}

		local profile
		if [ -n "$flag_file" ] && [ ${#args[@]} -gt 0 ]; then
			profile=$(load_json_file "${args[0]}") || return
		elif [ -n "$flag_file" ]; then
			echo "mcsvutils: --file option was specified but no file was specified." >&2
			return 2
		elif [ -n "$flag_stdin" ]; then
			profile=$(load_json_stdin) || return
		elif [ ${#args[@]} -gt 0 ]; then
			profile=$(load_json_file "${args[0]}") || return
		else
			profile=$(load_json_stdin) || return
		fi
		[ -n "$profile" ] || { echo "mcsvutils: The input file is empty." >&2; return 1; }
		local profile_err;	profile_err=$(echo "$profile" | profile_check_integrity)
		[ "$profile_err" == "OK" ] || [ "$profile_err" == "PROFILE_UPGRADE_NEEDED" ] || {
			echo "mcsvutils: Profile integrity error: $(echo "$profile_err" | integrity_errstr)" >&2
			return 1;
		}

		local p_ver;	p_ver=$(echo "$profile" | jq -c 'if (."@context"|type=="object" and (.version|type=="number")) then ."@context".version else .version end')
		local -r backwards_compatible_version=3
		if [ "$profile_err" == "OK" ]; then
			: No need to upgrade
		elif [ "$p_ver" -ge "$backwards_compatible_version" ] || [ -n "$flag_allow_destructive_upgrade" ]; then
			profile="$(echo "$profile" | profile_upgrade)" || return
		else
			echo "mcsvutils: Profile data upgrade required, but with breaking changes." >&2
			echo "mcsvutils: If you still want it to run, add the --allow-destructive-upgrade flag and run it again." >&2
			return 1
		fi

		# todo: イメージタグが実際に存在することを確認
		# todo: jreが実際に存在することを確認
		# todo: 作業ディレクトリが実際に存在することを確認
		local p_jvm;	p_jvm="$(jq -nc '$ARGS.positional' --args -- "${opts_jvm[@]}")" || return
		local p_args;	p_args="$(jq -nc '$ARGS.positional' --args -- "${opts_arg[@]}")" || return
		# shellcheck disable=SC2016
		cat_jq_overrideprofile_code() { cat <<<'.+([ if $pname|length>0 then {key:"servicename",value:$pname} else empty end, if $pimgtag|length>0 then {key:"imagetag",value:$pimgtag} else empty end, if $pcwd|length>0 then {key:"cwd",value:$pcwd} else empty end, if $pjre|length>0 then {key:"jre",value:$pjre} else empty end, if $popts|length>0 then {key:"jvm",value:$popts} else empty end, if $optcls|length>0 then {key:"jvm",value:[]} else empty end, if $pargs|length>0 then {key:"arguments",value:$pargs} else empty end, if $argcls|length>0 then {key:"arguments",value:[]} else empty end ]|from_entries)'; }
		profile=$(echo "$profile" | jq -c -f <(cat_jq_overrideprofile_code) --arg pname "$opt_rename" --arg pimgtag "$opt_image" --arg pcwd "$opt_cwd" --arg pjre "$opt_jre" --argjson popts "$p_jvm" --arg optcls "$flag_clear_jvmopts" --argjson pargs "$p_args" --arg argcls "$flag_clear_args") || return

		profile_err=$(echo "$profile" | profile_check_integrity) || {
			echo "mcsvutils: Profile integrity error: $(echo "$profile_err" | integrity_errstr)" >&2
			[ "$profile_err" == "PROFILE_REQUIRED_ELEMENT_MISSING" ] || [ "$profile_err" == "PROFILE_ELEMENT_TYPE_ERROR" ] && {
				echo "note: The notation to write the execution jar directly in the profile is no longer available." >&2
				echo "note: Add the jar to the image repository instead and write the image tag." >&2
			}
			return 1;
		}

		jq -c '.' <<-__EOF
		$profile
		__EOF
	} # subcommand_profile_create

	## profile/Analyze args ------------- ##

	local flag_help="$flag_help"
	local flag_usage="$flag_usage"
	while (( $# > 0 )); do case $1 in
		--help)		flag_help='true'; shift;;
		--usage)	flag_usage='true'; shift;;
		--*)		echo "mcsvutils: Invalid option $1" >&2;	usage >&2;	return 2;;
		-*)
			if [[ $1 =~ h ]]; then flag_help='true'; fi
			shift
			;;
		info)		shift;	subcommand_profile_info "$@";	return;;
		create)		shift;	subcommand_profile_create "$@";	return;;
		update)		shift;	subcommand_profile_update "$@";	return;;
		help)		help;	return;;
		usage)		usage;	return;;
		*)			echo "mcsvutils: Invalid subcommand $1" >&2;	usage >&2;	return 2;;
	esac done
	[ -z "$flag_help" ] || { help; return; }
	[ -z "$flag_usage" ] || { usage; return; }
	echo "mcsvutils: Subcommand not specified" >&2;	usage >&2;	return 2
} # subcommand_profile

subcommand_server() {
	## server/Help ---------------------- ##

	local -r allowed_subcommands=("status" "run" "exec" "stop" "help" "usage")
	usage() {
		cat <<- __EOF
		usage: $0 image <subcommand> ...
		subcommands: ${allowed_subcommands[@]}
		__EOF
	}
	help() {
		cat <<- __EOF
		mcsvutils server - Manage server instance

		usage: $0 image <subcommand> ...
		subcommands: ${allowed_subcommands[@]}
		  status   Show server status
		  run      Start server
		  exec     Send command to server
		  stop     Stop server
		  help     Show this help
		  usage    Show usage

		For detailed help on each subcommand, add the --help option to subcommand.

		options:
		  --help | -h Show help
		  --usage     Show usage
		  --          Do not parse subsequent options
		__EOF
	}
	## server/Subcommands --------------- ##

	subcommand_server_status() {
		## server/status/Help --------------- ##

		usage() {
			cat <<- __EOF
			usage: $0 server status [<options> ...] <profile>
			profile: path to profile
			__EOF
		}
		help() {
			cat <<- __EOF
			mcsvutils server status - Show server status

			usage: $0 server status [<options> ...] <profile>
			profile: path to profile

			options:
			  --help | -h
			    Show help
			  --usage
			    Show usage

			If the server is running, it prints its status in JSON and returns 0.
			Otherwise it outputs null and returns a non-zero value.
			__EOF
		}

		## server/status/Analyze args ------- ##

		local argi=1
		local arg_profile=
		local args=()
		local flag_help="$flag_help"
		local flag_usage="$flag_usage"
		while (( $# > 0 )); do case $1 in
			--help)		flag_help='true'; shift;;
			--usage)	flag_usage='true'; shift;;
			--)			shift;	break;;
			--*)		echo "mcsvutils: Invalid option $1" >&2;	usage >&2;	return 2;;
			-*)
				if [[ $1 =~ h ]]; then flag_help='true'; fi
				shift
				;;
			*)
				if [ $argi -eq 1 ]; then arg_profile="$1"; (( argi++ )) else args+=("$1"); fi; shift;;
		esac done
		while (( $# > 0 )); do 
			if [ $argi -eq 1 ]; then arg_profile="$1"; (( argi++ )) else args+=("$1"); fi; shift
		done

		[ -z "$flag_help" ] || { help; return; }
		[ -z "$flag_usage" ] || { usage; return; }
		assert_precond || return

		local profile
		if [ -n "$arg_profile" ]; then
			profile=$(load_json_file "$arg_profile") || return
		else
			echo "mcsvutils: No file was specified." >&2
			return 2
		fi
		[ -n "$profile" ] || {
			echo "mcsvutils: The input file is empty." >&2
			jq -nec 'null'
			return 1
		}
		local profile_err
		profile_err=$(echo "$profile" | profile_check_integrity) || {
			echo "mcsvutils: Profile integrity error: $(echo "$profile_err" | integrity_errstr)" >&2
			jq -nec 'null'
			return 1
		}

		local servicename
		servicename=$(echo "$profile" | jq -r -f <(cat <<<'.servicename')) || return
		local runtime="$MCSVUTILS_RUNTIME/$servicename"
		[ -d "$runtime" ] || { jq -nec 'null'; return; }
		[ -f "$runtime/status" ] || { jq -nec 'null'; return; }
		jq -c '.' "$runtime/status" >/dev/null || { jq -nec 'null'; return; }
		local server_pid
		server_pid=$(jq -r '.pid' "$runtime/status") || { jq -nec 'null'; return; }

		[ -d "/proc/$server_pid" ] || { jq -nec 'null'; return; }
		local pstat
		pstat=$(process_stat "$server_pid")
		# shellcheck disable=SC2016
		jq -ec -f <(cat <<<'if .pid==$pstat.[0].pid and .start_time==$pstat.[0].start_time then (.+{ process: ($pstat.[0]|{ state, vsize }) }) else null end') --slurpfile pstat <(echo "$pstat") "$runtime/status"
	} # subcommand_server_status

	subcommand_server_run() {
		## server/run/Help ------------------ ##

		usage() {
			cat <<- __EOF
			usage: $0 server run [<options> ...] <profile> [<argument> ...]
			profile: path to profile
			argument: Override arguments to use at startup
			__EOF
		}
		help() {
			cat <<- __EOF
			mcsvutils server run - Start server

			usage: $0 server run [<options> ...] <profile> [<argument> ...]
			profile: path to profile
			argument: Override arguments to use at startup

			options:
			  --cwd <path>
			    Override the working directory configuration
			  --jre <path>
			    Override the Java runtime path configuration
			  --jvm <option>
			    Override jvm arguments to use at startup
			    You can include multiple options by specifying them multiple times.
			  --override-args / --append-after-args / --append-before-args
			    Select how to handle arguments when they are entered (default: --override-args)
			    --override-args overrides the argument list with the specified arguments.
			    --append-after-args appends the specified arguments after the profile's default arguments.
			    --append-before-args is similar to --append-after-args but appends before the profile default arguments.
			    If these arguments are specified at the same time, it will be overwritten by the last specified.
			  --help | -h
			    Show help
			  --usage
			    Show usage
			__EOF
		}

		## server/run/Analyze args ---------- ##

		local opt_cwd=
		local opt_jre=
		local opts_jvm=()
		local opt_argsmixmode='override'
		local argi=1
		local arg_profile=
		local args=()
		local flag_help="$flag_help"
		local flag_usage="$flag_usage"
		while (( $# > 0 )); do case $1 in
			--cwd)		shift;	opt_cwd="$1";	shift;;
			--jre)		shift;	opt_jre="$1";	shift;;
			--jvm)		shift;	opts_jvm+=("$1");	shift;;
			--override-args)
				opt_argsmixmode='override';	shift;;
			--append-after-args)
				opt_argsmixmode='append-after';	shift;;
			--append-before-args)
				opt_argsmixmode='append-before';	shift;;
			--help)		flag_help='true'; shift;;
			--usage)	flag_usage='true'; shift;;
			--)			shift;	break;;
			--*)		echo "mcsvutils: Invalid option $1" >&2;	usage >&2;	return 2;;
			-*)
				if [[ $1 =~ h ]]; then flag_help='true'; fi
				shift
				;;
			*)
				if [ $argi -eq 1 ]; then arg_profile="$1"; (( argi++ )) else args+=("$1"); fi; shift;;
		esac done
		while (( $# > 0 )); do 
			if [ $argi -eq 1 ]; then arg_profile="$1"; (( argi++ )) else args+=("$1"); fi; shift
		done

		[ -z "$flag_help" ] || { help; return; }
		[ -z "$flag_usage" ] || { usage; return; }
		assert_precond || return
		local override_args
		# shellcheck disable=SC2016
		override_args=$(jq -nc -f <(cat <<<'$ARGS.positional') --args -- "${args[@]}") || return
		local override_jvms
		# shellcheck disable=SC2016
		override_jvms=$(jq -nc -f <(cat <<<'$ARGS.positional') --args -- "${opts_jvm[@]}") || return

		local profile
		if [ -n "$arg_profile" ]; then
			profile=$(load_json_file "$arg_profile") || return
		else
			echo "mcsvutils: No file was specified." >&2
			return 2
		fi
		[ -n "$profile" ] || { echo "mcsvutils: The input file is empty." >&2; return 1; }
		local profile_err
		profile_err=$(echo "$profile" | profile_check_integrity) || {
			echo "mcsvutils: Profile integrity error: $(echo "$profile_err" | integrity_errstr)" >&2
			return 1;
		}

		local servicename
		servicename=$(echo "$profile" | jq -r -f <(cat <<<'.servicename')) || return
		! server_check_running "$servicename" || {
			echo "mcsvutils: Server already running." >&2
			return 1
		}

		# todo: イメージが存在しない場合にMinecraftイメージマニフェストからの探索を施行する
		local image
		image=$(subcommand_image info -j -- "$(echo "$profile" | jq -r '.imagetag')") || return
		local image_path
		image_path=$(imagerepo_normalize_path "$(echo "$image" | jq -r 'if .type=="image" then .path elif .type=="alias" then .reference.path else empty end')") || return
		[ -n "$image_path" ] || {
			echo "mcsvutils: No image is associated with the tag" >&2
			return 1
		}
		[ -f "$image_path" ] || {
			echo "mcsvutils: File corresponding to image not found" >&2
			return 1
		}
		local image_size
		image_size=$(wc -c -- "$image_path")
		echo "$image" | jq -e --arg imgsize "$image_size" '(if .type=="image" then .size elif .type=="alias" then .reference.size else empty end) as $db_imgsize|($imgsize|gsub("(?<s>[0-9]+) .*$"; .s)|tonumber) as $act_imgsize|($db_imgsize//$act_imgsize)==$act_imgsize' >/dev/null || {
			echo "mcsvutils: Image corruption detected. Abort" >&2
			return 1
		}
		local image_sha1
		image_sha1=$(echo "$image" | jq -r 'if .type=="image" then .sha1 elif .type=="alias" then .reference.sha1 else empty end // ""')
		if [ -n "$image_sha1" ]; then
			sha1sum --quiet -c <<<"$image_sha1 *$image_path" || { echo "mcsvutils: Image corruption detected. Abort" >&2; return 1; }
		fi
		local image_sha256
		image_sha256=$(echo "$image" | jq -r 'if .type=="image" then .sha256 elif .type=="alias" then .reference.sha256 else empty end // ""')
		if [ -n "$image_sha256" ]; then
			sha256sum --quiet -c <<<"$image_sha256 *$image_path" || { echo "mcsvutils: Image corruption detected. Abort" >&2; return 1; }
		fi

		local workingdir
		# shellcheck disable=SC2016
		workingdir=$(readlink -m -- "$(echo "$profile" | jq -r -f <(cat <<<'($override_cwd|if length>0 then . else null end)//.cwd//"."') --arg override_cwd "$opt_cwd")") || return
		local invocation
		# shellcheck disable=SC2016
		invocation=$(echo "$profile" | jq -r -f <(cat <<<'([($override_jre|if length>0 then . else null end)//.jre//"java"]+(($override_jvm|if length>0 then . else null end)//.jvm//[])+["-jar", $image_path]+(if $arg_mode=="override" then (($override_args|if length>0 then . else null end)//.arguments//[]) elif $arg_mode=="append-after" then ((.arguments//[])+$override_args) elif $arg_mode=="append-before" then ($override_args+(.arguments//[])) else ("Invalid argument mix mode"|error) end))|@sh') --arg image_path "$image_path" --argjson override_args "$override_args" --arg arg_mode "$opt_argsmixmode" --argjson override_jvm "$override_jvms" --arg override_jre "$opt_jre") || return

		mkdir -p "$workingdir" || return
		local runtime="$MCSVUTILS_RUNTIME/$servicename"
		server_cleanup() {
			[ -z "$runtime" ] || rm -rf "${runtime:?}"
		}
		mkdir -p "$runtime" || return
		trap server_cleanup RETURN
		local con
		con=$(mktemp -p "$runtime" con.XXXXXXXXXX) || return
		rm "$con"
		mkfifo -m 'u=rw,go=' -- "$con" || return
		notify_con() {
			local f;	f=$(lsof -Fp "$con" | sed -e 's/p//g')
			# shellcheck disable=SC2086
			[ -z "$f" ] || kill -int $f
		}
		server_main() {
			trap notify_con RETURN
			# shellcheck disable=SC2086
			cd "$workingdir" && eval $invocation <"$con" &
			local server_pid=$!
			# shellcheck disable=SC2016
			process_stat "$server_pid" | jq -c -f <(cat <<<'{ servicename: $profile.[0].servicename, profile: $profile.[0], launch_config: { jre: (($override_jre|if length>0 then . else null end)//$profile.[0].jre//"java"), jvm: (($override_jvm.[0]|if length>0 then . else null end)//$profile.[0].jvm//[]), arguments: (if $arg_mode=="override" then (($override_args.[0]|if length>0 then . else null end)//$profile.[0].arguments//[]) elif $arg_mode=="append-after" then (($profile.[0].arguments//[])+$override_args.[0]) elif $arg_mode=="append-before" then ($override_args.[0]+($profile.[0].arguments//[])) else (null) end), cwd: (($override_cwd|if length>0 then . else null end)//.cwd//".") }, pid, start_time, console: $console }') --arg console "$con" --slurpfile profile <(echo "$profile") --arg override_cwd "$opt_cwd" --slurpfile override_args <(echo "$override_args") --arg arg_mode "$opt_argsmixmode" --slurpfile override_jvm <(echo "$override_jvms") --arg override_jre "$opt_jre" >"$runtime/status" || return
			wait "$server_pid"
		}
		server_main &
		local runner_pid=$!
		server_input() {
			trap notify_con RETURN
			while ps -p "$runner_pid" >/dev/null; do
				read -r c
				[ -z "$c" ] || echo "$c"
			done
		}
		(server_input) >"$con"
		return 0
	} # subcommand_server_run

	subcommand_server_exec() {
		## server/exec/Help ----------------- ##

		usage() {
			cat <<- __EOF
			usage: $0 server exec [<options> ...] <profile> <command>
			profile: path to profile
			command: command to send to server
			__EOF
		}
		help() {
			cat <<- __EOF
			mcsvutils server exec - Send command to server

			usage: $0 server exec [<options> ...] <profile> <command>
			profile: path to profile
			command: command to send to server

			options:
			  --help | -h
			    Show help
			  --usage
			    Show usage

			No execution results are displayed on the console.
			__EOF
		}

		## server/exec/Analyze args --------- ##

		local argi=1
		local arg_profile=
		local args_command=()
		local flag_help="$flag_help"
		local flag_usage="$flag_usage"
		while (( $# > 0 )); do case $1 in
			--help)		flag_help='true'; shift;;
			--usage)	flag_usage='true'; shift;;
			--)			shift;	break;;
			--*)		echo "mcsvutils: Invalid option $1" >&2;	usage >&2;	return 2;;
			-*)
				if [[ $1 =~ h ]]; then flag_help='true'; fi
				shift
				;;
			*)
				if [ $argi -eq 1 ]; then arg_profile="$1"; (( argi++ )) else args_command+=("$1"); fi; shift;;
		esac done
		while (( $# > 0 )); do 
			if [ $argi -eq 1 ]; then arg_profile="$1"; (( argi++ )) else args_command+=("$1"); fi; shift
		done

		[ -z "$flag_help" ] || { help; return; }
		[ -z "$flag_usage" ] || { usage; return; }
		assert_precond || return

		local profile
		if [ -n "$arg_profile" ]; then
			profile=$(load_json_file "$arg_profile") || return
		else
			echo "mcsvutils: No file was specified." >&2
			return 2
		fi
		[ -n "$profile" ] || {
			echo "mcsvutils: The input file is empty." >&2
			jq -nec 'null'
			return 1
		}
		local profile_err
		profile_err=$(echo "$profile" | profile_check_integrity) || {
			echo "mcsvutils: Profile integrity error: $(echo "$profile_err" | integrity_errstr)" >&2
			jq -nec 'null'
			return 1
		}

		local servicename
		servicename=$(echo "$profile" | jq -r -f <(cat <<<'.servicename')) || return
		server_check_running "$servicename" || {
			echo "mcsvutils: Server not running." >&2
			return 1
		}
		local runtime="$MCSVUTILS_RUNTIME/$servicename"
		local endpoint_path
		endpoint_path=$(jq -r '.console' "$runtime/status") || {
			echo "mcsvutils: Server console endpoint missing." >&2
			return 1
		}
		[ -p "$endpoint_path" ] || {
			echo "mcsvutils: Server console endpoint missing." >&2
			return 1
		}
		echo "${args_command[@]}" >"$endpoint_path"
	} # subcommand_server_exec

	subcommand_server_stop() {
		## server/stop/Help ----------------- ##

		usage() {
			cat <<- __EOF
			usage: $0 server stop [<options> ...] <profile>
			profile: path to profile
			__EOF
		}
		help() {
			cat <<- __EOF
			mcsvutils server stop - Stop server

			usage: $0 server stop [<options> ...] <profile>
			profile: path to profile

			options:
			  --help | -h
			    Show help
			  --usage
			    Show usage
			__EOF
		}

		## server/stop/Analyze args --------- ##

		local argi=1
		local arg_profile=
		local args=()
		local flag_help="$flag_help"
		local flag_usage="$flag_usage"
		while (( $# > 0 )); do case $1 in
			--help)		flag_help='true'; shift;;
			--usage)	flag_usage='true'; shift;;
			--)			shift;	break;;
			--*)		echo "mcsvutils: Invalid option $1" >&2;	usage >&2;	return 2;;
			-*)
				if [[ $1 =~ h ]]; then flag_help='true'; fi
				shift
				;;
			*)
				if [ $argi -eq 1 ]; then arg_profile="$1"; (( argi++ )) else args+=("$1"); fi; shift;;
		esac done
		while (( $# > 0 )); do 
			if [ $argi -eq 1 ]; then arg_profile="$1"; (( argi++ )) else args+=("$1"); fi; shift
		done

		[ -z "$flag_help" ] || { help; return; }
		[ -z "$flag_usage" ] || { usage; return; }
		assert_precond || return
		[ ${#args[@]} -le 0 ] || echo "mcsvutils: Trailing arguments will ignore." >&2

		local profile
		if [ -n "$arg_profile" ]; then
			profile=$(load_json_file "$arg_profile") || return
		else
			echo "mcsvutils: No file was specified." >&2
			return 2
		fi
		[ -n "$profile" ] || {
			echo "mcsvutils: The input file is empty." >&2
			jq -nec 'null'
			return 1
		}
		local profile_err
		profile_err=$(echo "$profile" | profile_check_integrity) || {
			echo "mcsvutils: Profile integrity error: $(echo "$profile_err" | integrity_errstr)" >&2
			jq -nec 'null'
			return 1
		}

		local servicename
		servicename=$(echo "$profile" | jq -r -f <(cat <<<'.servicename')) || return
		server_check_running "$servicename" || {
			echo "mcsvutils: Server not running." >&2
			return 1
		}
		local runtime="$MCSVUTILS_RUNTIME/$servicename"
		local endpoint_path
		endpoint_path=$(jq -r '.console' "$runtime/status") || {
			echo "mcsvutils: Server console endpoint missing." >&2
			return 1
		}
		[ -p "$endpoint_path" ] || {
			echo "mcsvutils: Server console endpoint missing." >&2
			return 1
		}
		echo "stop" >"$endpoint_path"
	} # subcommand_server_stop

	## server/Analyze args -------------- ##

	local flag_help="$flag_help"
	local flag_usage="$flag_usage"
	while (( $# > 0 )); do case $1 in
		--help)		flag_help='true'; shift;;
		--usage)	flag_usage='true'; shift;;
		--*)		echo "mcsvutils: Invalid option $1" >&2;	usage >&2;	return 2;;
		-*)
			if [[ $1 =~ h ]]; then flag_help='true'; fi
			shift
			;;
		run)		shift;	subcommand_server_run "$@";	return;;
		exec)		shift;	subcommand_server_exec "$@";	return;;
		stop)		shift;	subcommand_server_stop "$@";	return;;
		status)		shift;	subcommand_server_status "$@";	return;;
		help)		help;	return;;
		usage)		usage;	return;;
		*)			echo "mcsvutils: Invalid subcommand $1" >&2;	usage >&2;	return 2;;
	esac done
	[ -z "$flag_help" ] || { help; return; }
	[ -z "$flag_usage" ] || { usage; return; }
	echo "mcsvutils: Subcommand not specified" >&2;	usage >&2;	return 2
} # subcommand_server

subcommand_image() {
	## image/Help ----------------------- ##

	local -r allowed_subcommands=("list" "info" "add" "alias" "remove" "update" "init" "help" "usage")
	usage() {
		cat <<- __EOF
		usage: $0 image <subcommand> ...
		subcommands: ${allowed_subcommands[@]}
		__EOF
	}
	help() {
		cat <<- __EOF
		mcsvutils image - Manage Minecraft server image repository

		usage: $0 image <subcommand> ...
		subcommands: ${allowed_subcommands[@]}
		  list     Show image list
		  info     Show image infomation
		  add      Add server image into image repository
		  alias    Create alias for server image
		  remove   Remove server image from image repository
		  update   Update image repository
		  init     (re)Initialize image repository
		  help     Show this help
		  usage    Show usage

		For detailed help on each subcommand, add the --help option to subcommand.

		options:
		  --help | -h Show help
		  --usage     Show usage
		  --          Do not parse subsequent options
		__EOF
	}
	## image/Subcommands ---------------- ##

	subcommand_image_list() {
		## image/list/Help ------------------ ##

		usage() {
			cat <<- __EOF
			usage: $0 image list [<options> ...] [<query> ...]
			query: regexp query of server image tag
			__EOF
		}
		help() {
			cat <<- __EOF
			mcsvutils image list - Show image list

			usage: $0 image list [<options> ...] [<query> ...]
			query: regexp query of server image tag

			options:
			  --id | -i
			    List images with matching (or all) ID
			  --alias | -n
			    List images with matching (or all) alias
			  --json | -j
			    Outputs the results in JSON
			  --help | -h
			    Show help
			  --usage
			    Show usage

			This command returns an exit code of 0 even if nothing is found.
			Use info if you want to check that the specified tag exists.
			__EOF
		}

		## image/list/Analyze args ---------- ##

		local flag_id=
		local flag_alias=
		local flag_json=
		local args_query=()
		local flag_help="$flag_help"
		local flag_usage="$flag_usage"
		while (( $# > 0 )); do case $1 in
			--id)		flag_id='true';	shift;;
			--alias)	flag_alias='true'; shift;;
			--json)		flag_json='true'; shift;;
			--help)		flag_help='true'; shift;;
			--usage)	flag_usage='true'; shift;;
			--)			shift;	break;;
			--*)		echo "mcsvutils: Invalid option $1" >&2;	usage >&2;	return 2;;
			-*)
				if [[ $1 =~ i ]]; then flag_id='true'; fi
				if [[ $1 =~ n ]]; then flag_alias='true'; fi
				if [[ $1 =~ j ]]; then flag_json='true'; fi
				if [[ $1 =~ h ]]; then flag_help='true'; fi
				shift
				;;
			*)			args_query+=("$1");	shift;;
		esac done
		while (( $# > 0 )); do 
			args_query+=("$1");	shift
		done

		[ -z "$flag_help" ] || { help; return; }
		[ -z "$flag_usage" ] || { usage; return; }
		assert_precond || return

		local repo;	repo=$(imagerepo_load) || return
		local repo_err;	repo_err=$(echo "$repo" | imagerepo_check_integrity) || {
			echo "mcsvutils: Repository integrity error: $(echo "$repo_err" | integrity_errstr)" >&2
			return 1
		}

		# shellcheck disable=SC2016
		cat_jq_finder_code() { cat <<<'map(. as $i|select(([($find_id or ($find_alias|not)) and .type=="image", ($find_alias or ($find_id|not)) and .type=="alias"]|any) and ($ARGS.positional|if length>0 then any(. as $query|$i.id|test($query)) else true end)))|sort_by(.id)'; }
		# shellcheck disable=SC2016
		cat_jq_echo_code() { cat <<<'|.[]|if (.type=="alias") then (.id+" -> "+(.reference.id? // "<dangling reference>")) else .id end'; }

		if [ "$flag_json" == 'true' ]; then
			echo "$repo" | imagerepo_list_tags | jq -c --argjson find_id "${flag_id:-false}" --argjson find_alias "${flag_alias:-false}" "$(cat_jq_finder_code)" --args -- "${args_query[@]}"
		else
			echo "$repo" | imagerepo_list_tags | jq -r --argjson find_id "${flag_id:-false}" --argjson find_alias "${flag_alias:-false}" "$(cat_jq_finder_code; cat_jq_echo_code)" --args -- "${args_query[@]}"
		fi
	} # subcommand_image_list

	subcommand_image_info() {
		## image/info/Help ------------------ ##

		usage() {
			cat <<- __EOF
			usage: $0 image info [<options> ...] <imagetag>
			imagetag: server image tag
			__EOF
		}
		help() {
			cat <<- __EOF
			mcsvutils image info - Show image infomation

			usage: $0 image info [<options> ...] <imagetag>
			imagetag: server image tag

			options:
			  --json | -j
			    Outputs the results in JSON
			  --help | -h
			    Show help
			  --usage
			    Show usage
			__EOF
		}

		## image/info/Analyze args ---------- ##

		local flag_json=
		local argi=1
		local arg_image=
		local args=()
		local flag_help="$flag_help"
		local flag_usage="$flag_usage"
		while (( $# > 0 )); do case $1 in
			--json)		flag_json='true'; shift;;
			--help)		flag_help='true'; shift;;
			--usage)	flag_usage='true'; shift;;
			--)			shift;	break;;
			--*)		echo "mcsvutils: Invalid option $1" >&2;	usage >&2;	return 2;;
			-*)
				if [[ $1 =~ j ]]; then flag_json='true'; fi
				if [[ $1 =~ h ]]; then flag_help='true'; fi
				shift
				;;
			*)
				if [ "$argi" -eq 1 ]; then arg_image="$1"; ((argi++)); else args+=("$1"); fi;	shift;;
		esac done
		while (( $# > 0 )); do
			if [ "$argi" -eq 1 ]; then arg_image="$1"; ((argi++)); else args+=("$1"); fi;	shift
		done

		[ -z "$flag_help" ] || { help; return; }
		[ -z "$flag_usage" ] || { usage; return; }
		assert_precond || return
		[ "$argi" -gt 1 ] || { echo "mcsvutils: Too few arguments" >&2; usage >&2; return 2; }
		[ ${#args[@]} -le 0 ] || echo "mcsvutils: Trailing arguments will ignore." >&2

		local repo;	repo=$(imagerepo_load) || return
		local repo_err;	repo_err=$(echo "$repo" | imagerepo_check_integrity) || {
			echo "mcsvutils: Repository integrity error: $(echo "$repo_err" | integrity_errstr)" >&2
			return 1
		}

		echo "$repo" | imagerepo_tag_is_exist "$arg_image" || { echo "mcsvutils: imagetag not found" >&2; return 1; }
		if [ "$flag_json" == 'true' ]; then
			echo "$repo" | imagerepo_get_by_tag "$arg_image"
		else
			# shellcheck disable=SC2016
			echo "$repo" | imagerepo_get_by_tag "$arg_image" | jq -r '[.id]+if .type=="alias" and (.reference|type=="object") then ["alias for \(.reference.id)", "path: \(.reference.path)", (.reference|if has("size") and (.size|type=="number") then "size: \(.size)" else empty end), (.reference|if has("sha1") and (.sha1|type=="string") then "sha1: \(.sha1)" else empty end), (.reference|if has("sha256") and (.sha256|type=="string") then "sha256: \(.sha256)" else empty end)] elif .type=="alias" then ["<dangling reference>"] else ["path: \(.path)", if has("size") and (.size|type=="number") then "size: \(.size)" else empty end, if has("sha1") and (.sha1|type=="string") then "sha1: \(.sha1)" else empty end, if has("sha256") and (.sha256|type=="string") then "sha256: \(.sha256)" else empty end] end|join("\n")'
		fi
	} # subcommand_image_info

	subcommand_image_add() {
		## image/add/Help ------------------- ##

		usage() {
			cat <<- __EOF
			usage: $0 image add [<options> ...] [<alias> ...] <image>
			alias: alias to give to this image when adding
			image: path to Minacraft server image
			__EOF
		}
		help() {
			cat <<- __EOF
			mcsvutils image add - Add server image into image repository

			usage: $0 image add [<options> ...] [<alias> ...] <image>
			alias: alias to give to this image when adding
			image: path to Minacraft server image

			options:
			  --copy
			    Copy the server image to the image repository (default)
			    If specified at the same time as --link, it will be overwritten by the last specified.
			  --link | l
			    Create a hard link for the server image to the image repository
			    If specified at the same time as --copy, it will be overwritten by the last specified.
			  --help | -h
			    Show help
			  --usage
			    Show usage
			__EOF
		}

		## image/add/Analyze args ----------- ##

		local addition_behavior='copy'
		local argi=1
		local arg_imgpath=
		local arg_aliases=()
		local flag_help="$flag_help"
		local flag_usage="$flag_usage"
		while (( $# > 0 )); do case $1 in
			--copy)		addition_behavior='copy'; shift;;
			--link)		addition_behavior='link'; shift;;
			--help)		flag_help='true'; shift;;
			--usage)	flag_usage='true'; shift;;
			--)			shift;	break;;
			--*)		echo "mcsvutils: Invalid option $1" >&2;	usage >&2;	return 2;;
			-*)
				if [[ $1 =~ l ]]; then addition_behavior='link'; fi
				if [[ $1 =~ h ]]; then flag_help='true'; fi
				shift
				;;
			*)
				if [ $argi -eq 1 ]; then
					arg_imgpath="$1";	((argi++))
				else
					arg_aliases+=("$arg_imgpath")
					arg_imgpath="$1"
				fi
				shift;;
		esac done
		while (( $# > 0 )); do 
			if [ $argi -eq 1 ]; then
				arg_imgpath="$1";	((argi++))
			else
				arg_aliases+=("$arg_imgpath")
				arg_imgpath="$1"
			fi
			shift
		done

		[ -z "$flag_help" ] || { help; return; }
		[ -z "$flag_usage" ] || { usage; return; }
		assert_precond || return
		[ -n "$arg_imgpath" ] || { echo "mcsvutils: Too few arguments" >&2; usage >&2; return 2; }
		local aliases;	aliases=$(jq -nc '$ARGS.positional|sort|unique' --args -- "${arg_aliases[@]}") || return
		[ -e "$arg_imgpath" ] || { echo "mcsvutils: Image not found" >&2; usage >&2; return 1; }
		[ -f "$arg_imgpath" ] || { echo "mcsvutils: Image is not file" >&2; usage >&2; return 1; }

		local repo;	repo=$(imagerepo_load) || return
		local repo_err;	repo_err=$(echo "$repo" | imagerepo_check_integrity) || {
			echo "mcsvutils: Repository integrity error: $(echo "$repo_err" | integrity_errstr)" >&2
			return 1
		}
		echo "$repo" | jq -ec --slurpfile aliases <(echo "$aliases") '(.images+.aliases)|all(.id as $item|$aliases.[0]|all(.!=$item))' >/dev/null || { echo "mcsvutils: alias conflicts with existing tag" >&2; return 1; }

		local img_id;	img_id=$(echo "$repo" | imagerepo_get_new_imageid) || return
		local img_path
		imagerepo_mkdir || return
		case "$addition_behavior" in
		link)
			! [ -e "${MCSVUTILS_IMAGE_REPOSITORY:?}/${img_id:?}/$(basename "$arg_imgpath")" ] || { echo "mcsvutils: An entry already exists at the location in the repository. Abort." >&2; return 1; }
			mkdir -p "$MCSVUTILS_IMAGE_REPOSITORY/${img_id:?}" || return
			chmod u=rwx,go=rx "$MCSVUTILS_IMAGE_REPOSITORY/${img_id:?}" || return
			ln -t "$MCSVUTILS_IMAGE_REPOSITORY/${img_id:?}" "$arg_imgpath" || return
			img_path="${img_id:?}/$(basename "$arg_imgpath")"
		;;
		*)
			! [ -e "${MCSVUTILS_IMAGE_REPOSITORY:?}/${img_id:?}/$(basename "$arg_imgpath")" ] || { echo "mcsvutils: An entry already exists at the location in the repository. Abort." >&2; return 1; }
			mkdir -p "$MCSVUTILS_IMAGE_REPOSITORY/${img_id:?}" || return
			chmod u=rwx,go=rx "$MCSVUTILS_IMAGE_REPOSITORY/${img_id:?}" || return
			cp -t "$MCSVUTILS_IMAGE_REPOSITORY/${img_id:?}" "$arg_imgpath" || return
			chmod u=rw,go=r "$MCSVUTILS_IMAGE_REPOSITORY/${img_id:?}/$(basename "$arg_imgpath")" || return
			img_path="${img_id:?}/$(basename "$arg_imgpath")"
		;;
		esac

		local img_sha1;	img_sha1=$(sha1sum -b "$MCSVUTILS_IMAGE_REPOSITORY/${img_path:?}" &)
		local img_sha256;	img_sha256=$(sha256sum -b "$MCSVUTILS_IMAGE_REPOSITORY/${img_path:?}" &)
		local img_size;	img_size=$(wc -c -- "$MCSVUTILS_IMAGE_REPOSITORY/${img_path:?}" &)
		wait
		{ [ -n "$img_sha1" ] && [ -n "$img_sha256" ] && [ -n "$img_size" ]; } || {
			rm -rf -- "${MCSVUTILS_IMAGE_REPOSITORY:?}/${img_id:?}"
			return 1
		}

		# shellcheck disable=SC2016
		repo=$(echo "$repo" | jq -c --arg imgid "${img_id:?}" --arg imgpath "${img_path:?}" --arg imgsize "${img_size:?}" --arg imgsha1 "${img_sha1:?}" --arg imgsha256 "${img_sha256:?}" --slurpfile aliases <(echo "$aliases") '.images|=(.+[{id:$imgid,path:$imgpath,size:($imgsize|gsub("(?<s>[0-9]+) .*$";.s)|tonumber),sha1:($imgsha1|gsub("(?<s>[0-9a-f]+) .*$";.s)),sha256:($imgsha256|gsub("(?<s>[0-9a-f]+) .*$";.s))}])|.aliases|=(.+($aliases.[0]|map({id: ., reference: $imgid})))') || { rm -rf -- "${MCSVUTILS_IMAGE_REPOSITORY:?}/${img_id:?}"; return 1; }
		echo "$repo" | imagerepo_save
	} # subcommand_image_add

	subcommand_image_alias() {
		## image/alias/Help ----------------- ##

		usage() {
			cat <<- __EOF
			usage: $0 image alias [<options> ...] <alias> ... <imagetag>
			alias: alias to give to this image
			image: path to Minacraft server image
			__EOF
		}
		help() {
			cat <<- __EOF
			mcsvutils image alias - Create alias for server image

			usage: $0 image alias [<options> ...] <alias> ... <imagetag>
			alias: alias to give to image
			imagetag: server image tag

			options:
			  --force | -f
			    Overwrite existing alias
			  --help | -h
			    Show help
			  --usage
			    Show usage
			__EOF
		}

		## image/alias/Analyzargs ----------- ##

		local flag_force=
		local flag_help="$flag_help"
		local flag_usage="$flag_usage"
		local argi=1
		local arg_imgtag=
		local arg_aliases=()
		while (( $# > 0 )); do case $1 in
			--force)	flag_force='true'; shift;;
			--help)		flag_help='true'; shift;;
			--usage)	flag_usage='true'; shift;;
			--)			shift;	break;;
			--*)		echo "mcsvutils: Invalid option $1" >&2;	usage >&2;	return 2;;
			-*)
				if [[ $1 =~ f ]]; then flag_force='true'; fi
				if [[ $1 =~ h ]]; then flag_help='true'; fi
				shift
				;;
			*)
				if [ $argi -eq 1 ]; then
					arg_imgtag="$1";	argi=$((argi + 1))
				else
					arg_aliases+=("$arg_imgtag");	arg_imgtag="$1"
				fi
				shift;;
		esac done
		while (( $# > 0 )); do 
			if [ $argi -eq 1 ]; then
				arg_imgtag="$1";	argi=$((argi + 1))
			else
				arg_aliases+=("$arg_imgtag");	arg_imgtag="$1"
			fi
			shift
		done

		[ -z "$flag_help" ] || { help; return; }
		[ -z "$flag_usage" ] || { usage; return; }
		assert_precond || return
		[ "${#arg_aliases[@]}" -ge 1 ] || { echo "mcsvutils: Too few arguments" >&2; usage >&2; return 2; }
		local aliases;	aliases=$(jq -nc '$ARGS.positional|sort|unique' --args -- "${arg_aliases[@]}") || return

		local repo;	repo=$(imagerepo_load) || return
		local repo_err;	repo_err=$(echo "$repo" | imagerepo_check_integrity) || {
			echo "mcsvutils: Repository integrity error: $(echo "$repo_err" | integrity_errstr)" >&2
			return 1
		}
		echo "$repo" | imagerepo_tag_is_exist "$arg_imgtag" || { echo "mcsvutils: imagetag not found" >&2; return 1; }
		echo "$repo" | jq -ec --argjson force "${flag_force:-false}" --slurpfile aliases <(echo "$aliases") '(if $force then [] else .aliases end+.images)|all(.id as $item|$aliases.[0]|all(.!=$item))' >/dev/null || { echo "mcsvutils: alias conflicts with existing tag" >&2; [ "$flag_force" == 'true' ] || echo "note: To overwrite an existing alias, use the --force flag" >&2; return 1; }

		repo=$(echo "$repo" | jq -c --slurpfile aliases <(echo "${aliases:?}") --arg target "${arg_imgtag:?}" '(if .images|map(.id)|index($target)!=null then .images.[(.images|map(.id)|index($target))].id elif .aliases|map(.id)|index($target)!=null then .aliases.[(.aliases|map(.id)|index($target))].reference else "imagetag not found"|error end) as $tgtid|.aliases|=(map(select(. as $i|$aliases.[0]|all(.!=$i.name)))+($aliases.[0]|map({id:.,reference:$tgtid})))') || return
		echo "$repo" | imagerepo_save
	} # subcommand_image_alias

	subcommand_image_remove() {
		## image/remove/Help ---------------- ##

		usage() {
			cat <<- __EOF
			usage: $0 image remove [<options> ...] <imagetag> [<imagetag> ...]
			image: server image tag
			__EOF
		}
		help() {
			cat <<- __EOF
			mcsvutils image remove - Remove server image from image repository

			usage: $0 image remove [<options> ...] <imagetag> [<imagetag> ...]
			image: server image tag

			options:
			  --id | -i
			    Delete the image with matching ID
			    It is exclusive with the --dereference flag. If used simultaneously, the last flag specified will override it.
			  --alias | -n
			    Delete the image with matching alias
			  --dereference | -R
			    Deletes the image pointing to the specified alias instead of deleting the alias
			    If specify this flag, also specify the --alias flag.
			    It is exclusive with the --id flag. If used simultaneously, the last flag specified will override it.
			  --grep | -g
			    Match by regular expression instead of exact match
			  --force | -f
			    Do not ask if multiple images are deleted
			  --help | -h
			    Show help
			  --usage
			    Show usage
			__EOF
		}

		## image/remove/Analyze args -------- ##

		local flag_id=
		local flag_alias=
		local flag_dereference=
		local flag_grep=
		local flag_force=
		local args_query=()
		local flag_help="$flag_help"
		local flag_usage="$flag_usage"
		while (( $# > 0 )); do case $1 in
			--id)		flag_id='true';	flag_dereference='false';	shift;;
			--alias)	flag_alias='true'; shift;;
			--dereference)
				flag_dereference='true';	flag_id='false';	flag_alias='true';	shift;;
			--grep)		flag_grep='true'; shift;;
			--force)	flag_force='true'; shift;;
			--help)		flag_help='true'; shift;;
			--usage)	flag_usage='true'; shift;;
			--)			shift;	break;;
			--*)		echo "mcsvutils: Invalid option $1" >&2;	usage >&2;	return 2;;
			-*)
				if [[ $1 =~ i ]]; then flag_id='true';	flag_dereference='false'; fi
				if [[ $1 =~ n ]]; then flag_alias='true'; fi
				if [[ $1 =~ R ]]; then flag_dereference='true';	flag_id='false';	flag_alias='true'; fi
				if [[ $1 =~ g ]]; then flag_grep='true'; fi
				if [[ $1 =~ f ]]; then flag_force='true'; fi
				if [[ $1 =~ h ]]; then flag_help='true'; fi
				shift
				;;
			*)			args_query+=("$1");	shift;;
		esac done
		while (( $# > 0 )); do 
			args_query+=("$1");	shift
		done

		[ -z "$flag_help" ] || { help; return; }
		[ -z "$flag_usage" ] || { usage; return; }
		assert_precond || return
		[ ${#args_query[@]} -ge 1 ] || { echo "mcsvutils: Too few arguments" >&2; usage >&2; return 2; }

		local repo;	repo=$(imagerepo_load) || return
		local repo_err;	repo_err=$(echo "$repo" | imagerepo_check_integrity) || {
			echo "mcsvutils: Repository integrity error: $(echo "$repo_err" | integrity_errstr)" >&2
			return 1
		}

		local target;	target=$(echo "$repo" | jq -c --argjson find_id "${flag_id:-false}" --argjson find_alias "${flag_alias:-false}" --argjson dereference "${flag_dereference:-false}" --argjson grep "${flag_grep:-false}" '{images:(if $find_id or ($find_alias|not) then (.images|map(.id as $i|select($ARGS.positional|any(if $grep then (. as $query|$i|test($query)) else (.==$i) end)))) elif $dereference then ((.aliases|map(.id as $i|select($ARGS.positional|any(if $grep then (. as $query|$i|test($query)) else (.==$i) end)))|map(.reference)) as $target_ids|.images|map(. as $i|select($target_ids|any(.==$i.id)))) else [] end),aliases:((if $find_alias or ($find_id|not) then (.aliases|map(. as $i|select($ARGS.positional|any(if $grep then (. as $query|$i.id|test($query)) else (.==$i.id) end)))) else [] end)+(if $find_id or ($find_alias|not) then (.aliases|map(.reference as $i|select($ARGS.positional|any(if $grep then (. as $query|$i|test($query)) else (.==$i) end)))) elif $dereference then ((.aliases|map(.id as $i|select($ARGS.positional|any(if $grep then (. as $query|$i|test($query)) else (.==$i) end)))|map(.reference)) as $target_ids|.aliases|map(.reference as $i|select($target_ids|any(.==$i)))) else [] end)|map(.id)|unique)}' --args -- "${args_query[@]}") || return
		echo "$target" | jq -e '((.images|length)+(.aliases|length))>0' >/dev/null || { echo "mcsvutils: nothing to do." >&2; return 1; }
		if echo "$target" | jq -e --argjson force "${flag_force:-false}" '($force|not) and (.images|length>1)' >/dev/null; then
			echo "This operation deletes the following $(echo "$target" | jq '.images|length') images." >&2
			echo "$target" | jq -r '.images|map(.id)|join(" ")'
			ask_or_no "continue?" || return 1
		fi
		repo=$(echo "$repo" | jq -c --slurpfile target <(echo "$target") '.aliases|=map(.id as $item|select($target[0].aliases|all(.!=$item)))|.images|=map(.id as $item|select($target[0].images|all(.id!=$item)))') || return
		echo "$repo" | imagerepo_save || return

		while IFS= read -r -d $'\0' item <&3; do
			rm -f -- "${MCSVUTILS_IMAGE_REPOSITORY:?}/${item:?}"
		done 3< <(echo "$target" | jq --raw-output0 '.images[]|.path')
		while IFS= read -r -d $'\0' item <&3; do
			rmdir -- "${MCSVUTILS_IMAGE_REPOSITORY:?}/${item:?}"
		done 3< <(echo "$target" | jq --raw-output0 '.images[]|.id')
	} # subcommand_image_remove

	subcommand_image_update() {
		## image/update/Help ---------------- ##

		usage() {
			cat <<- __EOF
			usage: $0 image update [<options> ...]
			__EOF
		}
		help() {
			cat <<- __EOF
			mcsvutils image update - Update image repository

			usage: $0 image update [<options> ...]

			options:
			  --dry | -p
			    Do not perform any operations, only check the repository status
			  --force | -f
			    Perform all operations without interaction
			    If --dry is specified, this takes precedence.
			  --hash-recalc | -r
			    Recalculate checksums for all images
			  --help | -h
			    Show help
			  --usage
			    Show usage
			__EOF
		}

		## image/update/Analyze args -------- ##

		local flag_dry=
		local flag_force=
		local flag_hash_recalc=
		local args=()
		local flag_help="$flag_help"
		local flag_usage="$flag_usage"
		while (( $# > 0 )); do case $1 in
			--dry)		flag_dry='true'; shift;;
			--force)	flag_force='true'; shift;;
			--hash-recalc)
				flag_hash_recalc='true'; shift;;
			--help)		flag_help='true'; shift;;
			--usage)	flag_usage='true'; shift;;
			--)			shift;	break;;
			--*)		echo "mcsvutils: Invalid option $1" >&2;	usage >&2;	return 2;;
			-*)
				if [[ $1 =~ p ]]; then flag_dry='true'; fi
				if [[ $1 =~ f ]]; then flag_force='true'; fi
				if [[ $1 =~ r ]]; then flag_hash_recalc='true'; fi
				if [[ $1 =~ h ]]; then flag_help='true'; fi
				shift
				;;
			*)
				args+=("$1")
				shift;;
		esac done
		while (( $# > 0 )); do
			args+=("$1")
			shift
		done

		[ -z "$flag_help" ] || { help; return; }
		[ -z "$flag_usage" ] || { usage; return; }
		assert_precond || return
		[ ${#args[@]} -le 0 ] || echo "mcsvutils: Trailing arguments will ignore." >&2

		local repo;	repo=$(imagerepo_load) || return
		# todo: リポジトリのバージョンが古い場合にバージョンアップを行う
		local repo_err;	repo_err=$(echo "$repo" | imagerepo_check_integrity) || {
			echo "mcsvutils: Repository integrity error: $(echo "$repo_err" | integrity_errstr)" >&2
			return 1
		}

		local dangling_aliases='[]'
		dangling_aliases=$(echo "$repo" | jq -c '.images as $images|.aliases|map(select(.reference as $i|$images|all($i!=.id)))|map(.id)')

		local deletion_candidate='[]'
		while read -rd $'\0' item; do
			local img_id
			img_id=$(echo "$item" | jq -r '.id')
			local img_path
			img_path=$(echo "$item" | jq -r '.path')
			[ -f "$(imagerepo_normalize_path "$img_path")" ] || deletion_candidate=$(echo "$deletion_candidate" | jq -c '.+[$imgid]' --arg imgid "$img_id")
		done < <(echo "$repo" | jq --raw-output0 '.images[]|tostring')

		local unref_files='[]'
		unref_files=$( ( while read -rd $'\0' item; do printf '%s\0' "${item#"./"}"; done < <(cd "$MCSVUTILS_IMAGE_REPOSITORY" && find . -type f -print0) ) | jq -Rsc --slurpfile repo <(echo "$repo") 'split("\u0000")|map(. as $i|select([length==0, .=="repository.json", ($repo.[0].images|any(.path==$i))]|any|not))' )

		local recalchash_candidate='[]'
		recalchash_candidate=$(echo "$repo" | jq -c --argjson recalcall "${flag_hash_recalc:-false}" '.images|map(select(([(.size|type=="number"), (.sha1|type=="string" and length==40), (.sha256|type=="string" and length==64)]|all|not) or $recalcall))|map(.id)')

		echo "$dangling_aliases" | jq -r '"Aliases will remove (dangling): " + (if length>0 then join(" ") else "<none>" end)' >&2
		echo "$deletion_candidate" | jq -r '"Tags will remove (file not found): " + (if length>0 then join(" ") else "<none>" end)' >&2
		echo "$unref_files" | jq -r '"Files will delete (unreferenced): " + (if length>0 then "\n" + join(" ") else "<none>" end)' >&2
		echo "$recalchash_candidate" | jq -r '"Hash recalculation: " + (if length>0 then join(" ") else "<none>" end)' >&2

		[ "$flag_dry" != 'true' ] || return 0
		jq -ne --slurpfile da <(echo "$dangling_aliases") --slurpfile dt <(echo "$deletion_candidate") --slurpfile uf <(echo "$unref_files") --slurpfile hc <(echo "$recalchash_candidate") '($da.[0] + $dt.[0] + $uf.[0] + $hc.[0])|length>0' >/dev/null || {
			echo "mcsvutils: nothing to do." >&2
			return 0
		}
		[ "$flag_force" == 'true' ] || {
			ask_or_no "continue?" || {
				echo "mcsvutils: Operation cancelled by user" >&2
				return 1
			}
		}

		repo=$(echo "$repo" | jq -c --slurpfile dt <(echo "$deletion_candidate") '.images as $images|.images|=map(.id as $i|select($dt.[0]|all(.!=$i)))|.aliases|=map(.reference as $i|select(($dt.[0]|all(.!=$i)) and ($images|any(.id==$i))))') && echo "$repo" | imagerepo_save

		while read -rd $'\0' item; do
			local img_path;	img_path=$(echo "$item" | jq -r '.path') || continue
			local img_sha1;	img_sha1=$(sha1sum -b "$(imagerepo_normalize_path "${img_path:?}")" &)
			local img_sha256;	img_sha256=$(sha256sum -b "$(imagerepo_normalize_path "${img_path:?}")" &)
			local img_size;	img_size=$(wc -c -- "$(imagerepo_normalize_path "${img_path:?}")" &)
			wait
			{ [ -n "$img_sha1" ] && [ -n "$img_sha256" ] && [ -n "$img_size" ]; } || { continue; }
			repo=$(echo "$repo" | jq -c --argjson item "$item" --arg imgsize "${img_size:?}" --arg imgsha1 "${img_sha1:?}" --arg imgsha256 "${img_sha256:?}" '(.images[(.images|map(.id)|index($query))]|=($item + {size:($imgsize|gsub("(?<s>[0-9]+) .*$";.s)|tonumber),sha1:($imgsha1|gsub("(?<s>[0-9a-f]+) .*$";.s)),sha256:($imgsha256|gsub("(?<s>[0-9a-f]+) .*$";.s))}))') && echo "$repo" | imagerepo_save
		done < <(echo "$repo" | jq --raw-output0 --slurpfile hc <(echo "$recalchash_candidate") '.images|map(.id as $i|select($hc.[0]|any(.==$i)))|.[]|tostring')

		while read -rd $'\0' item; do
			rm -f "$(imagerepo_normalize_path "${item:?}")"
		done < <(echo "$unref_files" | jq --raw-output0 '.[]')
		while read -rd $'\0' item; do
			[ "$item" != "." ] || continue
			rmdir --ignore-fail-on-non-empty -- "${MCSVUTILS_IMAGE_REPOSITORY:?}/${item#./}"
		done < <(cd "$MCSVUTILS_IMAGE_REPOSITORY" && find . -type d -print0)

		echo "mcsvutils: done." >&2
	} # subcommand_image_update

	subcommand_image_init() {
		## image/init/Help ------------------ ##

		usage() {
			cat <<- __EOF
			usage: $0 image init [<options> ...]
			__EOF
		}
		help() {
			cat <<- __EOF
			mcsvutils image init - (re)Initialize image repository

			usage: $0 image init [<options> ...]

			options:
			  --force
			    Perform operations without interaction
			  --nuke-repository
			    Nuke the repository until there's no trace left
			  --help | -h
			    Show help
			  --usage
			    Show usage
			__EOF
		}

		## image/init/Analyze args ---------- ##

		local flag_nuke_repository=
		local args=()
		local flag_help="$flag_help"
		local flag_usage="$flag_usage"
		while (( $# > 0 )); do case $1 in
			--force)	flag_force='true'; shift;;
			--nuke-repository)
				flag_nuke_repository='true'; shift;;
			--help)		flag_help='true'; shift;;
			--usage)	flag_usage='true'; shift;;
			--)			shift;	break;;
			--*)		echo "mcsvutils: Invalid option $1" >&2;	usage >&2;	return 2;;
			-*)
				if [[ $1 =~ h ]]; then flag_help='true'; fi
				shift
				;;
			*)
				args+=("$arg_imgpath")
				shift;;
		esac done
		while (( $# > 0 )); do
			args+=("$arg_imgpath")
			shift
		done

		[ -z "$flag_help" ] || { help; return; }
		[ -z "$flag_usage" ] || { usage; return; }
		assert_precond || return
		[ ${#args[@]} -le 0 ] || echo "mcsvutils: Trailing arguments will ignore." >&2

		if [ -s "$MCSVUTILS_IMAGE_REPOSITORY" ]; then
			[ "$flag_nuke_repository" == 'true' ] || {
				echo "mcsvutils: Detected that repository exists. To completely remove this repository, add --nuke-repository and run again." >&2
				return 1
			}
			[ "$flag_force" == 'true' ] || {
				echo "mcsvutils: Choiced to completely destroy the repository." >&2
				echo "WARNING: Deleting a repository cannot be undone." >&2
				ask_or_no "continue?" || return
			}
			imagerepo_dbnuke
		fi
		local repo
		imagerepo_mkdir || return
		repo=$(imagerepo_load) || return
		echo "$repo" | imagerepo_save
	} # subcommand_image_init

	## image/Analyze args --------------- ##

	local flag_help="$flag_help"
	local flag_usage="$flag_usage"
	while (( $# > 0 )); do case $1 in
		--help)		flag_help='true'; shift;;
		--usage)	flag_usage='true'; shift;;
		--*)		echo "mcsvutils: Invalid option $1" >&2;	usage >&2;	return 2;;
		-*)
			if [[ $1 =~ h ]]; then flag_help='true'; fi
			shift
			;;
		list)		shift;	subcommand_image_list "$@";	return;;
		info)		shift;	subcommand_image_info "$@";	return;;
		add)		shift;	subcommand_image_add "$@";	return;;
		alias)		shift;	subcommand_image_alias "$@";	return;;
		remove)		shift;	subcommand_image_remove "$@";	return;;
		update)		shift;	subcommand_image_update "$@";	return;;
		init)		shift;	subcommand_image_init "$@";	return;;
		help)		help;	return;;
		usage)		usage;	return;;
		*)			echo "mcsvutils: Invalid subcommand $1" >&2;	usage >&2;	return 2;;
	esac done
	[ -z "$flag_help" ] || { help; return; }
	[ -z "$flag_usage" ] || { usage; return; }
	echo "mcsvutils: Subcommand not specified" >&2;	usage >&2;	return 2
} # subcommand_image

subcommand_piston() {
	## piston/Help ---------------------- ##

	local -r allowed_subcommands=("search" "info" "pull" "help" "usage")
	usage() {
		cat <<- __EOF
		usage: $0 piston <subcommand> ...
		subcommands: ${allowed_subcommands[@]}
		__EOF
	}
	help() {
		cat <<- __EOF
		mcsvutils piston - Manage Minecraft vanilla server images

		usage: $0 piston <subcommand> ...
		subcommands: ${allowed_subcommands[@]}
		  search   Search and list images
		  info     Show server image info
		  pull     Download image and add to image repository
		  help     Show this help
		  usage    Show usage

		For detailed help on each subcommand, add the --help option to subcommand.

		options:
		  --help | -h Show help
		  --usage     Show usage
		  --          Do not parse subsequent options
		__EOF
	}
	## piston/Subcommands --------------- ##

	subcommand_piston_search() {
		## piston/search/Help --------------- ##

		usage() {
			cat <<- __EOF
			usage:
			  $0 piston search [<options> ...] [<query>]
			  $0 piston search [<options> ...] --latest
			query: regexp query of versions
			__EOF
		}
		help() {
			cat <<- __EOF
			mcsvutils piston search - Search and list images

			usage:
			  $0 piston search [<options> ...] [<query>]
			  $0 piston search [<options> ...] --latest
			query: regexp query of versions

			options:
			  --latest
			    Query latest version
			  --release[=(true|false)]
			    Show release version (default: true)
			    If omit argument, will assign true.
			  --snapshot[=(true|false)]
			    Show snapshot version (default: false)
			    If omit argument, will assign true.
			  --old-alpha[=(true|false)]
			    Show old alpha version (default: false)
			    If omit argument, will assign true.
			  --old-beta[=(true|false)]
			    Show old beta version (default: false)
			    If omit argument, will assign true.
			  --all | -a
			    Equivalent --release=true --snapshot=true --old-alpha=true --old-beta=true
			  --json | -j
			    Outputs the results in JSON
			  --help | -h
			    Show help
			  --usage
			    Show usage
			__EOF
		}

		## piston/search/Analyze args ------- ##

		local flag_latest=''
		local flag_release='true'
		local flag_snapshot='false'
		local flag_old_alpha='false'
		local flag_old_beta='false'
		local flag_json=''
		local argi=1
		local arg_query=
		local args=()
		local flag_help="$flag_help"
		local flag_usage="$flag_usage"
		while (( $# > 0 )); do case $1 in
			--latest)	flag_latest='true'; shift;;
			--release=*)
				flag_release="${1#--release=}"; shift;;
			--release)	flag_release='true'; shift;;
			--snapshot=*)
				flag_snapshot="${1#--snapshot=}"; shift;;
			--snapshot)	flag_snapshot='true'; shift;;
			--old-alpha)
				flag_old_alpha='true'; shift;;
			--old-alpha=*)
				flag_old_alpha="${1#--old-alpha=}"; shift;;
			--old-beta=*)
				flag_old_beta="${1#--old-beta=}"; shift;;
			--old-beta)	flag_old_beta='true'; shift;;
			--all)		flag_release='true';	flag_snapshot='true';	flag_old_alpha='true';	flag_old_beta='true'; shift;;
			--json)		flag_json='true'; shift;;
			--help)		flag_help='true'; shift;;
			--usage)	flag_usage='true'; shift;;
			--)			shift;	break;;
			--*)		echo "mcsvutils: Invalid option $1" >&2;	usage >&2;	return 2;;
			-*)
				if [[ $1 =~ a ]]; then flag_release='true';	flag_snapshot='true';	flag_old_alpha='true';	flag_old_beta='true'; fi
				if [[ $1 =~ j ]]; then flag_json='true'; fi
				if [[ $1 =~ h ]]; then flag_help='true'; fi
				shift
				;;
			*)
				if [ $argi -eq 1 ]; then
					arg_query="$1";	((argi++))
				else
					args+=("$1")
				fi
				shift;;
		esac done
		while (( $# > 0 )); do 
			if [ $argi -eq 1 ]; then
				arg_query="$1";	((argi++))
			else
				args+=("$1")
			fi
			shift
		done

		[ -z "$flag_help" ] || { help; return; }
		[ -z "$flag_usage" ] || { usage; return; }
		assert_precond || return
		[ ${#args[@]} -le 0 ] || echo "mcsvutils: Trailing arguments will ignore." >&2
		local qflags;	qflags=$(jq -nc --argjson latest "${flag_latest:-false}" --rawfile release <(echo "$flag_release") --rawfile snapshot <(echo "$flag_snapshot") --rawfile old_alpha <(echo "$flag_old_alpha") --rawfile old_beta <(echo "$flag_old_beta") 'def toboolean($e): if ([.=="true", .=="on", .=="yes", ((tonumber?)//0)!=0]|any) then true elif ([.=="false", .=="off", .=="no", ((tonumber?)//1)==0]|any) then false else ($e|error) end; { latest: $latest, release: ($release|toboolean("The value of --release is neither a Boolean value nor a string that can be interpreted as such.")), snapshot: ($snapshot|toboolean("The value of --snapshot is neither a Boolean value nor a string that can be interpreted as such.")), old_alpha: ($old_alpha|toboolean("The value of --old_alpha is neither a Boolean value nor a string that can be interpreted as such.")), old_beta: ($old_beta|toboolean("The value of --old_beta is neither a Boolean value nor a string that can be interpreted as such.")) }') || return

		local piston_manifest;	piston_manifest=$(fetch_piston_manifest) || return
		local find_result;	find_result=$(echo "$piston_manifest" | jq -c --arg query "$arg_query" --slurpfile flags <(echo "$qflags") '.latest as $latest|.versions|map(select([(if $flags[0].latest then (. as $i|$latest|map(.==$i.id)|any) elif ($query|length>0) then (.id|test($query)) else true end), (.type!="release" or $flags[0].release), (.type!="snapshot" or $flags[0].snapshot), (.type!="old_alpha" or $flags[0].old_alpha), (.type!="old_beta" or $flags[0].old_beta)]|all))') || return
		if [ "$flag_json" == 'true' ]; then
			echo "$find_result" | jq -c '.'
		else
			echo "$find_result" | jq -r '.[]|"\(.id)"'
		fi
	} # subcommand_piston_search

	subcommand_piston_info() {
		## piston/info/Help ----------------- ##

		usage() {
			cat <<- __EOF
			usage:
			  $0 piston info [<options> ...] [--latest[=(release|snapshot)]]
			  $0 piston info [<options> ...] <version>
			version: query of versions
			__EOF
		}
		help() {
			cat <<- __EOF
			mcsvutils piston info - Show server image info

			usage:
			  $0 piston info [<options> ...] [--latest[=(release|snapshot)]]
			  $0 piston info [<options> ...] <version>
			version: query of versions

			options:
			  --latest[=(release|snapshot)]
			    Query latest version
			  --json | -j
			    Outputs the results in JSON
			  --help | -h
			    Show help
			  --usage
			    Show usage
			__EOF
		}

		## piston/info/Analyze args --------- ##

		local flag_latest='off'
		local flag_json=''
		local argi=1
		local arg_version=
		local args=()
		local flag_help="$flag_help"
		local flag_usage="$flag_usage"
		while (( $# > 0 )); do case $1 in
			--latest)	flag_latest='release'; shift;;
			--latest=*)	flag_latest="${1#--latest=}"; shift;;
			--json)		flag_json='true'; shift;;
			--help)		flag_help='true'; shift;;
			--usage)	flag_usage='true'; shift;;
			--)			shift;	break;;
			--*)		echo "mcsvutils: Invalid option $1" >&2;	usage >&2;	return 2;;
			-*)
				if [[ $1 =~ j ]]; then flag_json='true'; fi
				if [[ $1 =~ h ]]; then flag_help='true'; fi
				shift
				;;
			*)
				if [ $argi -eq 1 ]; then
					arg_version="$1";	((argi++))
				else
					args+=("$1")
				fi
				shift;;
		esac done
		while (( $# > 0 )); do 
			if [ $argi -eq 1 ]; then
				arg_version="$1";	((argi++))
			else
				args+=("$1")
			fi
			shift
		done

		[ -z "$flag_help" ] || { help; return; }
		[ -z "$flag_usage" ] || { usage; return; }
		assert_precond || return
		[ ${#args[@]} -le 0 ] || echo "mcsvutils: Trailing arguments will ignore." >&2
		[ $argi -gt 1 ] || [ "$flag_latest" != 'off' ] || flag_latest='release'
		[ "$flag_latest" == 'off' ] || [ "$flag_latest" == 'release' ] || [ "$flag_latest" == 'snapshot' ] || {
			echo "mcsvutils: Possible arguments for --latest option are either release or snapshot." >&2
			return 2
		}

		local version_url
		# shellcheck disable=SC2016
		version_url=$(fetch_piston_manifest | jq -r --arg latest "${flag_latest:-off}" --arg query "$arg_version" '(if $latest=="release" then .latest.release elif $latest=="snapshot" then .latest.snapshot else $query end) as $id|.versions|map({key:.id,value:.})|from_entries|.[$id]//("Version \"\($id)\" not found"|error)|.url') || return
		local version_info
		version_info=$(curl -s "$version_url") || return

		if [ "$flag_json" == 'true' ]; then
			echo "$version_info" | jq -c '.'
		else
			echo "$version_info" | jq -r '["\(.type) \(.id)", "Released at \(.releaseTime)", "Server jar: \(.downloads.server.url)", "  size: \(.downloads.server.size)", "  sha1: \(.downloads.server.sha1)", "Java version: \(.javaVersion.majorVersion)"]|join("\n")'
		fi
	} # subcommand_piston_info

	subcommand_piston_pull() {
		## piston/pull/Help ----------------- ##

		usage() {
			cat <<- __EOF
			usage:
			  $0 piston info [<options> ...] [--latest[=(release|snapshot)]]
			  $0 piston info [<options> ...] <version>
			version: query of versions
			__EOF
		}
		help() {
			cat <<- __EOF
			mcsvutils piston pull - Download image and add to image repository

			usage:
			  $0 piston pull [<options> ...] [--latest[=(release|snapshot)]]
			  $0 piston pull [<options> ...] <version>
			version: query of versions

			options:
			  --latest[=(release|snapshot)]
			    Query latest version
			  --update
			    Overwrite the corresponding tag if it exists
			  --out <location>
			    Download to specified location instead of adding to repository
			  --help | -h
			    Show help
			  --usage
			    Show usage
			__EOF
		}

		## piston/pull/Analyze args --------- ##

		local flag_latest='off'
		local flag_update=''
		local opt_out=
		local argi=1
		local arg_version=
		local args=()
		local flag_help="$flag_help"
		local flag_usage="$flag_usage"
		while (( $# > 0 )); do case $1 in
			--latest=*)	flag_latest="${1#--latest=}"; shift;;
			--latest)	flag_latest='release'; shift;;
			--update)	flag_update='true'; shift;;
			--out=*)	opt_out="${1#--out=}"; shift;;
			--out)		shift;	opt_out="$1"; shift;;
			--help)		flag_help='true'; shift;;
			--usage)	flag_usage='true'; shift;;
			--)			shift;	break;;
			--*)		echo "mcsvutils: Invalid option $1" >&2;	usage >&2;	return 2;;
			-*)
				if [[ $1 =~ h ]]; then flag_help='true'; fi
				shift
				;;
			*)
				if [ $argi -eq 1 ]; then
					arg_version="$1";	((argi++))
				else
					args+=("$1")
				fi
				shift;;
		esac done
		while (( $# > 0 )); do 
			if [ $argi -eq 1 ]; then
				arg_version="$1";	((argi++))
			else
				args+=("$1")
			fi
			shift
		done

		[ -z "$flag_help" ] || { help; return; }
		[ -z "$flag_usage" ] || { usage; return; }
		assert_precond || return
		[ ${#args[@]} -le 0 ] || echo "mcsvutils: Trailing arguments will ignore." >&2
		[ $argi -gt 1 ] || [ "$flag_latest" != 'off' ] || flag_latest='release'
		[ "$flag_latest" == 'off' ] || [ "$flag_latest" == 'release' ] || [ "$flag_latest" == 'snapshot' ] || {
			echo "mcsvutils: Possible arguments for --latest option are either release or snapshot." >&2
			return 2
		}

		local piston_manifest;	piston_manifest=$(fetch_piston_manifest) || return
		local version_url;	version_url=$(echo "$piston_manifest" | jq -r --arg latest "${flag_latest:-off}" --arg query "$arg_version" '(if $latest=="release" then .latest.release elif $latest=="snapshot" then .latest.snapshot else $query end) as $id|.versions|map({key:.id,value:.})|from_entries|.[$id]//("Version \"\($id)\" not found"|error)|.url') || return
		local aliases;	aliases=$(echo "$piston_manifest" | jq -r --arg latest "${flag_latest:-off}" --arg query "$arg_version" '(if $latest=="release" then .latest.release elif $latest=="snapshot" then .latest.snapshot else $query end) as $id|[(.versions|map({key:.id,value:.})|from_entries|.[$id].id), if .latest.release==$id then "latest" else empty end, if .latest.snapshot==$id then "snapshot" else empty end]') || return
		local version_info;	version_info=$(curl -s "$version_url") || return
		local version_source;	version_source=$(echo "$version_info" | jq -r '.downloads.server.url') || return
		local version_fname;	version_fname=$(basename "$version_source")

		local repo
		[ -n "$opt_out" ] || {
			repo=$(imagerepo_load) || return
			local repo_err;	repo_err=$(echo "$repo" | imagerepo_check_integrity) || {
				echo "mcsvutils: Repository integrity error: $(echo "$repo_err" | integrity_errstr)" >&2
				return 1
			}
			echo "$repo" | jq -ec --argjson force "${flag_update:-false}" --argjson aliases "$aliases" '(if $force then [] else .aliases end+.images)|all(.id as $item|$aliases|all(.!=$item))' >/dev/null || { echo "mcsvutils: alias conflicts with existing tag" >&2; [ "$flag_update" == 'true' ] || echo "note: To overwrite an existing alias, use the --update flag" >&2; return 1; }
		}

		local temp_dir
		temp_dir=$(mktemp -dt "mcsvutils.XXXXXXXXXX.tmp") || return
		( cd "$temp_dir" && wget --quiet --show-progress --progress=bar:force -- "$version_source" ) || return
		local image_size;	image_size=$(wc -c -- "$temp_dir/$version_fname")
		echo "$version_info" | jq -e --arg imgsize "$image_size" '(.downloads.server.size) as $src_imgsize|($imgsize|gsub("(?<s>[0-9]+) .*$"; .s)|tonumber) as $act_imgsize|$src_imgsize==$act_imgsize' >/dev/null || { echo "mcsvutils: File sizes do not match." >&2; return 1; }
		sha1sum --quiet -c <<<"$(echo "$version_info" | jq -r '.downloads.server.sha1') *$temp_dir/$version_fname" || return

		if [ -z "$opt_out" ]; then
			local img_id;	img_id=$(echo "$repo" | imagerepo_get_new_imageid) || return
			local img_path
			imagerepo_mkdir || return
			! [ -e "${MCSVUTILS_IMAGE_REPOSITORY:?}/$img_id/$version_fname" ] || { echo "mcsvutils: An entry already exists at the location in the repository. Abort." >&2; return 1; }
			mkdir -p "$MCSVUTILS_IMAGE_REPOSITORY/$img_id"
			chmod u=rwx,go=rx "$MCSVUTILS_IMAGE_REPOSITORY/$img_id" || return
			cp -t "$MCSVUTILS_IMAGE_REPOSITORY/$img_id" "$temp_dir/$version_fname" || return
			chmod u=rw,go=r "$MCSVUTILS_IMAGE_REPOSITORY/$img_id/$version_fname" || return
			img_path="$img_id/$version_fname"
			local img_sha256;	img_sha256=$(sha256sum -b "$MCSVUTILS_IMAGE_REPOSITORY/${img_path:?}")
			[ -n "$img_sha256" ] || { rm -rf -- "${MCSVUTILS_IMAGE_REPOSITORY:?}/${img_id:?}"; return 1; }
			repo=$(echo "$repo" | jq -c --slurpfile vinfo <(echo "$version_info") --arg imgid "$img_id" --arg imgpath "$img_path" --arg imgsha256 "$img_sha256" --argjson aliases "$aliases" '(.images|=.+[{id:$imgid,path:$imgpath,size:$vinfo[0].downloads.server.size,sha1:$vinfo[0].downloads.server.sha1,sha256:($imgsha256|gsub("(?<s>[0-9a-f]+) .*$";.s)) }])|.aliases|=(map(select(.id as $i|$aliases|all(.!=$i)))+($aliases|map({id: .,reference: $imgid})))') || { rm -rf -- "${MCSVUTILS_IMAGE_REPOSITORY:?}/${img_id:?}"; return 1; }
			echo "$repo" | imagerepo_save
		else
			mv -i -T "$temp_dir/$version_fname" "$opt_out" || return
		fi
		rm -rf "${temp_dir:?}"
	} # subcommand_piston_pull

	## piston/Analyze args -------------- ##

	local flag_help="$flag_help"
	local flag_usage="$flag_usage"
	while (( $# > 0 )); do case $1 in
		--help)		flag_help='true'; shift;;
		--usage)	flag_usage='true'; shift;;
		--*)		echo "mcsvutils: Invalid option $1" >&2;	usage >&2;	return 2;;
		-*)
			if [[ $1 =~ h ]]; then flag_help='true'; fi
			shift
			;;
		search)		shift;	subcommand_piston_search "$@";	return;;
		info)		shift;	subcommand_piston_info "$@";	return;;
		pull)		shift;	subcommand_piston_pull "$@";	return;;
		help)		help;	return;;
		usage)		usage;	return;;
		*)			echo "mcsvutils: Invalid subcommand $1" >&2;	usage >&2;	return 2;;
	esac done
	[ -z "$flag_help" ] || { help; return; }
	[ -z "$flag_usage" ] || { usage; return; }
	echo "mcsvutils: Subcommand not specified" >&2;	usage >&2;	return 2
} # subcommand_piston

subcommand_spigot() {
	## spigot/Help ---------------------- ##

	local -r allowed_subcommands=("build" "help" "usage")
	usage() {
		cat <<- __EOF
		usage: $0 spigot <subcommand> ...
		subcommands: ${allowed_subcommands[@]}
		__EOF
	}
	help() {
		cat <<- __EOF
		mcsvutils spigot - Manage CraftBukkit/Spigot server images

		usage: $0 spigot <subcommand> ...
		subcommands: ${allowed_subcommands[@]}
		  build    Build Craftbukkit/Spigot image
		  help     Show this help
		  usage    Show usage

		For detailed help on each subcommand, add the --help option to subcommand.

		options:
		  --help | -h Show help
		  --usage     Show usage
		  --          Do not parse subsequent options
		__EOF
	}
	## spigot/Subcommands --------------- ##

	subcommand_spigot_build() {
		## spigot/build/Help ---------------- ##

		usage() {
			cat <<- __EOF
			usage:
			  $0 spigot build [<options> ...] [--latest]
			  $0 spigot build [<options> ...] <version>
			version: query of versions
			__EOF
		}
		help() {
			cat <<- __EOF
			mcsvutils spigot build - Download image and add to image repository

			usage:
			  $0 spigot build [<options> ...] [--latest]
			  $0 spigot build [<options> ...] <version>
			version: query of versions

			options:
			  --latest
			    Query latest version
			  --craftbukkit
			    Select to compile Craftbukkit
			  --spigot
			    Select to compile Spigot
			  --jre <path>
			    Java executable file used to run build tool
			  --update
			    Overwrite the corresponding tag if it exists
			  --out <location>
			    Download to specified location instead of adding to repository
			  --help | -h
			    Show help
			  --usage
			    Show usage
			__EOF
		}

		## spigot/build/Analyze args -------- ##

		local flag_latest=
		local flag_compile=''
		local opt_jre=
		local flag_update=
		local opt_out=
		local argi=1
		local arg_version=
		local args=()
		local flag_help="$flag_help"
		local flag_usage="$flag_usage"
		while (( $# > 0 )); do case $1 in
			--latest)	flag_latest='true'; shift;;
			--craftbukkit)
				flag_compile='craftbukkit'; shift;;
			--spigot)	flag_compile='spigot'; shift;;
			--jre=*)	opt_jre="${1#--jre=}"; shift;;
			--jre)		shift;	opt_jre="$1"; shift;;
			--update)	flag_update='true'; shift;;
			--out=*)	opt_out="${1#--out=}"; shift;;
			--out)		shift;	opt_out="$1"; shift;;
			--help)		flag_help='true'; shift;;
			--usage)	flag_usage='true'; shift;;
			--)			shift;	break;;
			--*)		echo "mcsvutils: Invalid option $1" >&2;	usage >&2;	return 2;;
			-*)
				if [[ $1 =~ h ]]; then flag_help='true'; fi
				shift
				;;
			*)
				if [ $argi -eq 1 ]; then
					arg_version="$1";	((argi++))
				else
					args+=("$1")
				fi
				shift;;
		esac done
		while (( $# > 0 )); do 
			if [ $argi -eq 1 ]; then
				arg_version="$1";	((argi++))
			else
				args+=("$1")
			fi
			shift
		done

		[ -z "$flag_help" ] || { help; return; }
		[ -z "$flag_usage" ] || { usage; return; }
		assert_precond || return
		local nargs
		nargs=$(jq -nc --argjson latest "${flag_latest:-false}" --arg compile_type "$flag_compile" --arg jre "$opt_jre" --argjson update "${flag_update:-false}" --arg out_dir "$opt_out" --arg version "$arg_version" '{ latest: $latest, version: (if ($version|length > 0) then $version else null end), compile_type: (if (["", "craftbukkit", "spigot"]|map($compile_type==.)|any) then $compile_type else ("Invalid compile type option"|error) end), jre: (if ($jre|length > 0) then $jre else null end), update: $update, out_dir: (if ($out_dir|length > 0) then $out_dir else null end) }') || return 2

		local repo
		[ -n "$opt_out" ] || {
			repo=$(imagerepo_load) || return
			local repo_err;	repo_err=$(echo "$repo" | imagerepo_check_integrity) || {
				echo "mcsvutils: Repository integrity error: $(echo "$repo_err" | integrity_errstr)" >&2
				return 1
			}
		}

		local invocation;	invocation=$(echo "$nargs" | jq -r '[(.jre//"java"), "-jar", "BuildTools.jar", (if .compile_type=="craftbukkit" then ("--compile", "CRAFTBUKKIT") elif .compile_type=="spigot" then ("--compile", "SPIGOT") else empty end), (if (.latest|not) and (.version|type!="null") then ("--rev", .version) else empty end), (if (.out_dir|type!="null") then ("--output-dir", .out_dir) else empty end)]|@sh') || return
		local workingdir;	workingdir=$(mktemp -dt mcsvutils.XXXXXXXXXX) || return
		# shellcheck disable=SC2086
		( cd "$workingdir" && wget --quiet --show-progress --progress=bar:force -- "$SPIGOT_BUILDTOOLS_LOCATION" && eval $invocation) || return
		tail "$workingdir/BuildTools.log.txt" | grep 'Success! Everything completed successfully\. Copying final \.jar files now\.' >/dev/null 2>&1 || { echo "mcsvutils: Something went wrong in building. Abort." >&2; return 1; }

		[ -z "$opt_out" ] || { rm -rf "${workingdir:?}"; return 0; }
		local resultjar
		resultjar=$(tail "$workingdir/BuildTools.log.txt" | jq -Rsr 'split("\n")|map(select(test("- Saved as")))|if length>0 then . else ("Result jar can'\''t detected"|error) end|.[0]|capture("- Saved as (?<f>.*\\.jar)")|.f') || return
		resultjar=$(basename -s .jar "$resultjar") || return
		[ -f "$workingdir/${resultjar}.jar" ] || { echo "mcsvutils: Result jar not found" >&2; return 1; }

		# shellcheck disable=SC2016
		echo "$repo" | jq -ec --argjson force "${flag_update:-false}" --arg jarname "$resultjar" --slurpfile args <(echo "$nargs") '[$jarname, (if ($args[0].version|type=="null") or ($args[0].version=="latest") then "spigot" else empty end)] as $aliases|(if $force then [] else .aliases end+.images)|all(.id as $item|$aliases|all(.!=$item))' >/dev/null || { echo "mcsvutils: alias conflicts with existing tag" >&2; [ "$flag_update" == 'true' ] || echo "note: To overwrite an existing alias, use the --update flag" >&2; return 1; }

		local img_id;	img_id=$(echo "$repo" | imagerepo_get_new_imageid) || return
		local img_path
		imagerepo_mkdir || return
		! [ -e "${MCSVUTILS_IMAGE_REPOSITORY:?}/$img_id/${resultjar}.jar" ] || { echo "mcsvutils: An entry already exists at the location in the repository. Abort." >&2; return 1; }
		mkdir -p "$MCSVUTILS_IMAGE_REPOSITORY/$img_id"
		chmod u=rwx,go=rx "$MCSVUTILS_IMAGE_REPOSITORY/$img_id" || return
		cp -t "$MCSVUTILS_IMAGE_REPOSITORY/$img_id" "$workingdir/${resultjar}.jar" || return
		chmod u=rw,go=r "$MCSVUTILS_IMAGE_REPOSITORY/$img_id/${resultjar}.jar" || return
		img_path="$img_id/${resultjar}.jar"
		local img_sha1;	img_sha1=$(sha1sum -b "$MCSVUTILS_IMAGE_REPOSITORY/${img_path:?}" &)
		local img_sha256;	img_sha256=$(sha256sum -b "$MCSVUTILS_IMAGE_REPOSITORY/${img_path:?}" &)
		local img_size;	img_size=$(wc -c -- "$MCSVUTILS_IMAGE_REPOSITORY/${img_path:?}" &)
		wait
		{ [ -n "$img_sha1" ] && [ -n "$img_sha256" ] && [ -n "$img_size" ]; } || {
			rm -rf -- "${MCSVUTILS_IMAGE_REPOSITORY:?}/${img_id:?}"
			return 1
		}

		repo=$(echo "$repo" | jq -c --arg imgid "$img_id" --arg jarname "$resultjar" --rawfile imgpath <(echo "$img_path") --rawfile imgsize <(echo "$img_size") --rawfile imgsha1 <(echo "$img_sha1") --rawfile imgsha256 <(echo "$img_sha256") --slurpfile args <(echo "$nargs") '[$jarname, (if ($args[0].version|type=="null") or ($args[0].version=="latest") then "spigot" else empty end)] as $aliases|(.images|=.+[{id:$imgid,path:$imgpath,size:($imgsize|gsub("(?<s>[0-9]+) .*$";.s)|tonumber),sha1:($imgsha1|gsub("(?<s>[0-9a-f]+) .*$";.s)),sha256:($imgsha256|gsub("(?<s>[0-9a-f]+) .*$";.s))}])|.aliases|=(map(select(.id as $i|$aliases|all(.!=$i)))+($aliases|map({id:.,reference:$imgid})))') || { rm -rf -- "${MCSVUTILS_IMAGE_REPOSITORY:?}/${img_id:?}"; return 1; }
		echo "$repo" | imagerepo_save
		rm -rf "${workingdir:?}"
	} # subcommand_spigot_build

	## spigot/Analyze args -------------- ##

	local flag_help="$flag_help"
	local flag_usage="$flag_usage"
	while (( $# > 0 )); do case $1 in
		--help)		flag_help='true'; shift;;
		--usage)	flag_usage='true'; shift;;
		--*)		echo "mcsvutils: Invalid option $1" >&2;	usage >&2;	return 2;;
		-*)
			if [[ $1 =~ h ]]; then flag_help='true'; fi
			shift
			;;
		build)		shift;	subcommand_spigot_build "$@";	return;;
		help)		help;	return;;
		usage)		usage;	return;;
		*)			echo "mcsvutils: Invalid subcommand $1" >&2;	usage >&2;	return 2;;
	esac done
	[ -z "$flag_help" ] || { help; return; }
	[ -z "$flag_usage" ] || { usage; return; }
	echo "mcsvutils: Subcommand not specified" >&2;	usage >&2;	return 2
} # subcommand_spigot

## Analyze commandline args --------- ##

local flag_help
local flag_usage
while (( $# > 0 )); do case $1 in
	--version)	version;	return;;
	--help)		flag_help='true'; shift;;
	--usage)	flag_usage='true'; shift;;
	--*)		echo "mcsvutils: Invalid option $1" >&2;	usage >&2;	return 2;;
	-*)
		if [[ $1 =~ h ]]; then flag_help='true'; fi
		shift
		;;
	profile)	shift;	subcommand_profile "$@";	return;;
	server)		shift;	subcommand_server "$@";	return;;
	image)		shift;	subcommand_image "$@";	return;;
	piston)		shift;	subcommand_piston "$@";	return;;
	spigot)		shift;	subcommand_spigot "$@";	return;;
	version)	version;	return;;
	help)		help;	return;;
	usage)		usage;	return;;
	*)			echo "mcsvutils: Invalid subcommand $1" >&2;	usage >&2;	return 2;;
esac done
[ -z "$flag_help" ] || { help; return; }
[ -z "$flag_usage" ] || { usage; return; }
echo "mcsvutils: Subcommand not specified" >&2;	usage >&2;	return 2
} # __main
__main "$@"
