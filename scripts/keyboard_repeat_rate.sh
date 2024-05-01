#!/usr/bin/env sh
defaults write -g InitialKeyRepeat -int 13 # normal minimum is 15 (225 ms)
defaults write -g KeyRepeat -int 1 # normal minimum is 2 (30 ms)

# reminder -- need to re-login to macbook to see results
ˆ
