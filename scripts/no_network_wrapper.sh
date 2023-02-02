#!/bin/bash

# create a new container with:
# -f run target as forked child 
# -p new pid namespace
# -n new network namespace 
# -c run as current user ( no root required )

# the command running will have no network access unless configured otherwise

unshare -frpnc "$1"
