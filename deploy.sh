#!/usr/bin/env bash

nimble build -d:release --threads:off --verbose

for i in $(seq 1 $(nproc --all)); do
  ./test_jester &
  sleep 0.1
done

wait

