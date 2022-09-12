#!/bin/sh
docker pull elixir:alpine
docker build --network host -t chessresults_notifier .
