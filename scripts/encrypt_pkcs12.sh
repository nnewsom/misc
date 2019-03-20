#!/bin/bash

random-string()
{
    cat /dev/urandom | tr -dc 'a-zA-Z0-9_.()&*%^#$!@~' | fold -w 10 | head -n 1
}

TMP_DIR=`mktemp -d`
TMP_KEY=$TMP_DIR/tmp.key
TMP_CRT=$TMP_DIR/tmp.crt
TMP_PW=$TMP_DIR/tmp.pw

openssl pkcs12 -in $1 -nocerts -nodes -passin pass: | sed -ne '/-BEGIN PRIVATE KEY-/,/-END PRIVATE KEY-/p' > $TMP_KEY
openssl pkcs12 -in $1 -clcerts -nokeys  -passin pass: | sed -ne '/-BEGIN CERTIFICATE-/,/END CERTIFICATE-/p' >  $TMP_CRT
openssl pkcs12 -in $1 -cacerts -nokeys  -passin pass: | sed -ne '/-BEGIN CERTIFICATE-/,/END CERTIFICATE-/p' >> $TMP_CRT

passwd=`random-string`
echo $passwd > $TMP_PW
openssl pkcs12 -export -out encrypted.p12 -inkey $TMP_KEY -in $TMP_CRT -passout file:$TMP_PW 

echo $passwd
shred -n7 -zu $TMP_KEY
shred -n7 -zu $TMP_PW
shred -n7 -zu $TMP_CRT
rmdir $TMP_DIR
