#!/bin/bash -x
IFS=$'\n'

UA="Mozilla/5.0 (Linux; rv:69.0) Gecko/20100101 Firefox/79.0"
TMPDIR=`mktemp -d`
TMPNAME=`echo $TMPDIR| cut -f 2 -d '.'`
SRCDIR="$HOME"/scripts/defaults/firefox/Default/
PROFILE_NUM=0
PROFILES_INI="$HOME"/.mozilla/firefox/profiles.ini
PROXY_HOST="127.0.0.1"
PROXY_PORT=8080
FF="/usr/bin/firefox"

profiles=`grep "\[Profile" "$PROFILES_INI"`
for profile in $profiles;
do
pn=`echo $profile | egrep -o [0-9]+`
if [ $pn -gt $PROFILE_NUM ]; then
    PROFILE_NUM=$pn
fi
done

PROFILE_NUM=$(($PROFILE_NUM+1))

cat << EOF >> "$PROFILES_INI"
[Profile$PROFILE_NUM]
Name=$TMPNAME
IsRelative=0
Path=$TMPDIR

EOF

cp -r "$SRCDIR"/* "$TMPDIR"/
cat << EOF >> $TMPDIR/prefs.js
user_pref("general.useragent.override", "$UA"); 
user_pref("network.proxy.http","$PROXY_HOST");
user_pref("network.proxy.http_port", $PROXY_PORT);
user_pref("network.proxy.type",1);
user_pref("network.proxy.share_proxy_settings",true);
EOF

"$FF" -P "$TMPNAME"

profile_start=`grep -n "\[Profile$PROFILE_NUM\]" "$PROFILES_INI" | cut -f 1 -d :`
profile_end=$(($profile_start+4))
sed -i "$profile_start","$profile_end"d "$PROFILES_INI"

find "$TMPDIR" -type f -exec shred -n3 -zu {} \;
rm -rf "$TMPDIR"
