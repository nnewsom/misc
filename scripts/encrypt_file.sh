#!/bin/bash

openssl aes-256-cbc -a -pbkdf2 -salt -in "$1" -out "$1".enc
