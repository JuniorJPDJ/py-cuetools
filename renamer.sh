#!/bin/bash
set -e

# Supported music files: flac, mp3
# Files should first be tagged with Musicbrainz Picard

# Looks the best with Picard file naming set to:
# $if(%tracknumber%,$num(%tracknumber%,2). ,)%artist% - %title%

# This script expects folder tree like that:

# Main Music Directory (Library)
# |- Single CD Album
# |  |- Some additional file(s) (cover, cue sheet or anything additional)
# |  |- Track 01
# |  |- Track 02
# |  |- ...
# |
# |- Multi CD Album
# |  |- CD1 Folder
# |  |  |- Some additional file(s)
# |  |  |- Track 01
# |  |  |- Track 02
# |  |  |- ...
# |  |
# |  |- CD2 Folder
# |  |  |- ...
# |  |- ...
# |
# |- ...


format_disc(){
	if [ "$tag_totaldiscs" -gt 1 ] ; then
		printf '%s' "CD${tag_disc}"
		[ -z "$tag_discsubtitle" ] || printf '%s' " - ${tag_discsubtitle}"
	fi
}

format_album(){
	printf '%s' "${tag_originalyear}. ${tag_album_artist} - ${tag_album}"
}

format_additional_file(){
	printf '%s' "00. ${tag_album_artist} - ${tag_album}"
	if [ "$tag_totaldiscs" -gt 1 ] ; then
		printf '%s' " - CD${tag_disc}"
		[ -z "$tag_discsubtitle" ] || printf '%s' " - ${tag_discsubtitle}"
	fi
} 

color(){
	color="$1"
	printf '\e[%sm' "$1"
}

creset(){
	color 0
}

cgreen(){
	color 32
}

cfname(){
	# color filename
	local fname="$1"
	printf '%s/%s%s%s' "$(dirname "$fname")" "`cgreen`" "$(basename "$fname")" "`creset`"
}

tags_to_vars(){
	file="$1"
	callback="$2"

	[ ! -f "$file" ] && return 1

	# import tags as local variables
	eval "$(ffprobe -v quiet -print_format json -show_format "$file" | jq -r '.format.tags | to_entries | map("local \("tag_\(.key)" | ascii_downcase | gsub("\\s+"; "_") | gsub("-"; "_") | gsub("\\."; "") | @sh)=\(.value | @sh)") | join("\n")')"

	# run callback function in local scope
	eval "$callback"
}

safe_fname(){
	fname="$1"
	fname="${fname//\</`printf "\u2039"`}"
	fname="${fname//\>/`printf "\u203A"`}"
	fname="${fname//\:/`printf "\u2236"`}"
	fname="${fname//\"/`printf "\u201D"`}"
	fname="${fname//\//`printf "\u2044"`}"
	fname="${fname//\\/`printf "\u2216"`}"
	fname="${fname//\|/`printf "\u2223"`}"
	fname="${fname//\?/`printf "\uFF1F"`}"
	fname="${fname//\*/`printf "\u2217"`}"
	printf '%s' "$fname"
}

change_name(){
	in="$1"
	out="$2"
	pushd "$(dirname "$1")" > /dev/null
	mv "$(basename "$1")" "$out"
	popd > /dev/null
}

interactive_rename(){
	in="$1"
	out="$2"
	read -p "Rename \"$(cfname "$in")\" to \"`cgreen`$out`creset`\"? [Y/n/e]: " answer
	answer=${answer:-y}

	[ "$answer" = "n" ] && return
	[ "$answer" = "e" ] && answer="y" && read -ep "Rename \"$(cfname "$in")\" to: " -i "$out" out || true
	[ "$answer" = "y" ] && change_name "$in" "$out" && return

	echo "Invalid answer."
	interactive_rename "$in" "$out"
}

process_file(){
	# should be called as tags_as_vars callback - depends on tags

	# don't process the same directory more than once
	# TODO: bad idea, need to find ONE suitable file in dir and use it
	[ "$(dirname "$file")" = "$last_dir" ] && return || true
	last_dir="$(dirname "$file")"
	
	# additional files in the same directory
	new_name="$(safe_fname "$(format_additional_file)")"
	while IFS= read -r -d $'\0' additional_file ; do {
		echo "Found additional file: $(cfname "$additional_file")"
		fname="$(basename "$additional_file")"
		new_name_ext="$new_name.${fname##*.}"

		[ -f "$additional_file" ] && \
		[ "$fname" != "$new_name_ext" ] && \
		interactive_rename "$additional_file" "$new_name_ext" || true 

	} <&3 ; done 3>&2 < <(find "$last_dir" -maxdepth 1 -type f -not \( -iname '*.flac' -or -iname '*.mp3' \) -print0)

	# mark disc dir for rename if multidisc (else this is empty)
	disc_new_name="$(safe_fname "$(format_disc)")"

	# get album dir for single disc releases
	album_dir="$last_dir"
	# get album dir for multidisc releases
	[ "$disc_new_name" ] && album_dir="$(dirname "$album_dir")" || true

	# mark album dir for rename
	album_new_name="$(safe_fname "$(format_album)")"

	#declare -p | grep "tag_"
}

process_files(){
	dir="$1"
	while IFS= read -r -d $'\0' file ; do {
		tags_to_vars "$file" process_file
	} <&3 ; done 3>&2 < <(find "$dir" -maxdepth 1 -type f -and \( -iname '*.flac' -or -iname '*.mp3' \) -and -print0)
}

process_dir(){
	local base_dir="$1"
	echo "Processing directory: $(cfname "$base_dir")"

	# recursively process child directories
	while IFS= read -r -d $'\0' dir ; do {
		[ "$dir" = "$base_dir" ] && continue
		process_dir "$dir"
		#echo "$dir"
	} <&3 ; done 3>&2 < <(find "$base_dir" -maxdepth 1 -type d -print0)

	process_files "$base_dir"

	# try renaming if this is disc dir
	[ "$disc_new_name" ] && \
	[ "$base_dir" = "$last_dir" ] && \
	[ "$(basename "$last_dir")" != "$disc_new_name" ] && \
	interactive_rename "$last_dir" "$disc_new_name" || true

	# try renaming if this is album dir
	[ "$base_dir" = "$album_dir" ] && \
	[ "$(basename "$album_dir")" != "$album_new_name" ] && \
	interactive_rename "$album_dir" "$album_new_name" || true
	
	echo "End of processing of directory: $(cfname "$base_dir")"
}

process_dir "$1"
