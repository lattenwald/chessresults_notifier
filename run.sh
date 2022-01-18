#!/bin/sh
exec docker run \
    -v `pwd`/config.toml:/app/config.toml \
    -v `pwd`/storage.term:/app/storage.term \
    -v `pwd`/erl_crash.dump:/app/erl_crash.dump \
    -i -t chessresults_notifier $@
