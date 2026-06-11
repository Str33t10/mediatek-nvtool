#!/sbin/sh

umask 22
setenforce 0

[ -z $OUTFD ] && OUTFD="$2"
[ -z $ZIPFILE ] && ZIPFILE="$3"
[ "$ANDROID_CACHE" ] || ANDROID_CACHE=/cache
[ "$ANDROID_DATA" ] || ANDROID_DATA=/data
[ "$ANDROID_ROOT" ] || ANDROID_ROOT=/system
[ "$EXTERNAL_STORAGE" ] || EXTERNAL_STORAGE=/sdcard

# mount <partition>
mount() {
	if [ "$(grep -w -o $1 /etc/recovery.fstab)" ]; then
		/sbin/mount -o ro -t auto $1 > /dev/null 2>&1
		/sbin/mount -o rw,remount -t auto $1 > /dev/null 2>&1
		is_mounted $1 || abort "! Failed to mount $1. Aborting..."
	fi
}

# is_mounted <partition>
is_mounted() {
	grep -q " $(readlink -f $1) " /proc/mounts 2>/dev/null
	return $?
}

# unmount <partition>
unmount() {
	if [ "$(grep -w -o $1 /etc/recovery.fstab)" ]; then
		(umount $1 && umount -l $1) > /dev/null 2>&1
	fi
}




# delete <file> [<file2> ...]
delete() { rm -f "$@"; }

# delete_recursive <dir> [<dir2> ...]
delete_recursive() { rm -rf "$@"; }



# show_progress <amount> <time>
show_progress() { echo "progress $1 $2" >> /proc/self/fd/$OUTFD; }

# set_progress <amount>
set_progress() { echo "set_progress $1" >> /proc/self/fd/$OUTFD; }



# package_extract_dir <dir> <destination_dir>
package_extract_dir() {
	local path i
	for i in $(unzip -l "$ZIPFILE" 2>/dev/null | tail -n+4 | grep -v '/$' | grep -o " $1.*$" | cut -c2-); do
		path="$(echo "$i" | sed "s|${1}|${2}|")"
		mkdir -p "$(dirname "$path")"
		unzip -o "$ZIPFILE" "$i" -p > "$path"
	done
}

# package_extract_file <file> <destination_file>
package_extract_file()	{
	mkdir -p "$(dirname "$2")"
	unzip -o "$ZIPFILE" "$1" -p > "$2"
}



# symlink <file/dir> <link> [<link2> ...]
symlink()	{
	local path
	path="$1"
	while [ "$2" ]; do
		ln -sf "$path" "$2"
		shift
	done
}



# set_perm <owner> <group> <mode> <file> [<file2> ...]
set_perm() {
	local uid gid mod
	uid=$1
	gid=$2
	mod=$3
	shift 3
	chown $uid:$gid "$@" || chown $uid.$gid "$@"
	chmod $mod "$@"
}

# set_perm_recursive <owner> <group> <dir_mode> <file_mode> <dir> [<dir2> ...]
set_perm_recursive() {
	local uid gid dmod fmod;
	uid=$1
	gid=$2
	dmod=$3
	fmod=$4
	shift 4
	while [ "$1" ]; do
		chown -R $uid:$gid "$1" || chown -R $uid.$gid "$1"
		find "$1" -type d -exec chmod $dmod {} +
		find "$1" -type f -exec chmod $fmod {} +
		shift
	done
}



# set_metadata <file> <uid|gid|mode|capabilities|selabel> <value> [<uid|gid|mode|capabilities|selabel_2> <value2> ...]
set_metadata() {
	local path i
	path="$1"
	shift
	while [ "$2" ]; do
		case $1 in
      uid) chown $2 "$path";;
      gid)
				chown :$2 "$path" || chown .$2 "$path"
			;;
      mode) chmod $2 "$path";;
      capabilities) twrp setcap "$path" $2;;
      selabel)
				for i in $ANDROID_ROOT/bin/toybox $ANDROID_ROOT/toolbox $ANDROID_ROOT/bin/toolbox; do
					(LD_LIBRARY_PATH=$ANDROID_ROOT/lib $i chcon -h $2 "$path" || LD_LIBRARY_PATH=$ANDROID_ROOT/lib $i chcon $2 "$path") 2>/dev/null
				done || chcon -h $2 "$path" || chcon $2 "$path"
			;;
			*) ;;
		esac
		shift 2
	done
}

# set_metadata_recursive <dir> <uid|gid|dmode|fmode|capabilities|selabel> <value> [<uid|gid|dmode|fmode|capabilities|selabel_2> <value2> ...]
set_metadata_recursive() {
	local path i
	path="$1"
	shift
	while [ "$2" ]; do
		case $1 in
      uid) chown -R $2 "$path";;
      gid)
				chown -R :$2 "$path" || chown -R .$2 "$path"
			;;
			dmode) find "$path" -type d -exec chmod $2 {} +;;
			fmode) find "$path" -type f -exec chmod $2 {} +;;
			capabilities) find "$path" -exec twrp setcap {} $2 +;;
			selabel)
				for i in $ANDROID_ROOT/bin/toybox $ANDROID_ROOT/toolbox $ANDROID_ROOT/bin/toolbox; do
          (find "$path" -exec LD_LIBRARY_PATH=$ANDROID_ROOT/lib $i chcon -h $2 {} + || find "$path" -exec LD_LIBRARY_PATH=$ANDROID_ROOT/lib $i chcon $2 {} +) 2>/dev/null;
        done || find "$path" -exec chcon -h $2 '{}' + || find "$path" -exec chcon $2 '{}' +;
			;;
			*) ;;
		esac
		shift 2
	done
}



# getprop <property>
getprop() {
	local key val i
	key="$1"
	for i in $ANDROID_ROOT/build.prop /default.prop; do
		if [ -e "$i" ]; then
			val="$(file_getprop "$i" "$key")"
			if [ -n "$val" ]; then
				break
			fi
		fi
	done
	if [ -z "$val" ]; then
		/sbin/getprop "$key" | cut -c1-
	else
		printf "$val"
	fi
}

# file_getprop <file> <property>
file_getprop() { grep "^$2" "$1" | head -n1 | cut -d= -f2-; }



# write_raw_image <file> <block>
write_raw_image() { dd if="$1" of="$2"; }
#write_raw_image() { unzip -op $ZIPFILE "$1" | dd of="$2"; }



# ui_print "<message>" ["<message 2>" ...]
ui_print() {
	while [ "$1" ]; do
		echo "ui_print $1" >> /proc/self/fd/$OUTFD
		shift
	done
}



# assert "<command>" ["<command2>" ...]
assert() {
	while [ "$1" ]; do
		$1
		test $? != 0 && abort "! Failed to assert $1. Aborting..."
		shift
	done
}



# abort [<message>]
abort() {
	ui_print "$@"
	sleep 1
	exit 1
}



# run_program "<program>"
run_program() {
	case $1 in
		*.sh) source "$@";;
		*) "$*";;
	esac
}

# _____________________________________________________________________________________________________________________