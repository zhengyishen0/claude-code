#!/bin/bash
# Shared output functions for zenix scripts

ok() { echo "  ✓ $*"; }
warn() { echo "  ! $*"; }
err() { echo "  ✗ $*"; }
