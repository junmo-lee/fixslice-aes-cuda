#!/bin/bash

# AES Bruteforce MPI + CUDA Test Script
# This script demonstrates how to run the bruteforce program on multiple nodes

# Configuration
PLAINTEXT="00112233445566778899aabbccddeeff"
CIPHERTEXT="69c4e0d86a7b0430d8cdb78070b4c55a"
KEY_PREFIX="2b7e151628aed2a6abf71588"  # First 12 bytes of key
# Actual full key: 2b7e151628aed2a6abf7158809cf4f3c
# Last 4 bytes to find: 09cf4f3c

NUM_PROCESSES=4  # Number of MPI processes

echo "=== AES-128 Bruteforce Test ==="
echo "This will search for the last 4 bytes of the key"
echo "Known prefix: ${KEY_PREFIX}"
echo "Target suffix: 09cf4f3c (in this test example)"
echo ""
echo "Running with ${NUM_PROCESSES} MPI processes..."
echo ""

# Run with mpirun
mpirun -np ${NUM_PROCESSES} \
  --bind-to none \
  ./build/cuda-aes-bruteforce-mpi \
  ${PLAINTEXT} \
  ${CIPHERTEXT} \
  ${KEY_PREFIX}

echo ""
echo "=== Test Complete ==="
