#!/bin/bash

openssl aes-256-cbc -d -a -pbkdf2 -salt -in "$1" -out "$1".plaintext
